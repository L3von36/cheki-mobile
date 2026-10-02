/// Mahtem Cloud Backup controller (v1.13.0) — opt-in, zero-knowledge.
///
/// Local-first forever: the app works fully without this controller ever
/// being touched. Enabling it requires the user's own account password
/// (verified against the LOCAL account record first — the same password
/// that already protects the device account), then:
///
///   1. derive authKey + identifierHash + vault key on-device,
///   2. create (or reuse) the cloud account for that identifier hash,
///   3. open a session, merge-upload the local history as one AES-GCM
///      blob whose key never leaves the phone.
///
/// The server stores only ciphertext + digests — see cloud_keys.dart.
/// Turning the feature OFF deletes both the session and the cloud copy,
/// the privacy-safe default (the user can always re-enable).
library;


import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/account.dart';
import '../core/auth/password_hasher.dart';
import '../core/cloud/cloud_api.dart';
import '../core/cloud/cloud_keys.dart';
import '../core/cloud/cloud_vault.dart';
import '../core/verify_history.dart';

enum CloudStep { idle, working }

/// What went wrong last, mapped 1:1 to localized strings in the UI.
enum CloudFailure { none, wrongPassword, network, server, sessionExpired, decrypt }

class CloudController extends ChangeNotifier {
  CloudController({
    CloudApi? api,
    PasswordHasher? hasher,
    SharedPreferences? prefs,
    int Function()? revisionClock,
  })  : _api = api ?? CloudApi(),
        _hasher = hasher ?? PasswordHasher(),
        _prefs = prefs,
        _revisionClock = revisionClock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final CloudApi _api;
  final PasswordHasher _hasher;
  final SharedPreferences? _prefs;
  final int Function() _revisionClock;

  // persisted state
  bool _enabled = false;
  int? _lastSyncAt;
  String? _sessionToken;
  String? _identifierHash;
  String? _vaultKeyHex;
  int? _sessionExpiresAt;

  // ephemeral state
  CloudStep _step = CloudStep.idle;
  CloudFailure _failure = CloudFailure.none;

  // ---------------------------------------------------------------- accessors
  bool get enabled => _enabled;
  bool get isWorking => _step == CloudStep.working;
  CloudFailure get failure => _failure;
  int? get lastSyncAt => _lastSyncAt;

  /// Restore/backup only make sense with a live session.
  bool get hasSession =>
      _enabled &&
      _sessionToken != null &&
      (_sessionExpiresAt == null ||
          _sessionExpiresAt! > DateTime.now().millisecondsSinceEpoch);

  // ---------------------------------------------------------------- lifecycle
  Future<void> ensureLoaded() async {
    final prefs = _prefs;
    if (prefs == null) return;
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _sessionToken = prefs.getString(_kToken);
    _identifierHash = prefs.getString(_kIdentifierHash);
    _vaultKeyHex = prefs.getString(_kVaultKey);
    _sessionExpiresAt = prefs.getInt(_kExpiresAt);
    _lastSyncAt = prefs.getInt(_kLastSync);
    if (_enabled &&
        (_sessionToken == null ||
            _vaultKeyHex == null ||
            _identifierHash == null ||
            !hasSession)) {
      // Stale/expired session — require a fresh enable (re-enter
      // password). The server copy, if any, is untouched; the user can
      // re-enable and merge it.
      _enabled = false;
      _failure = CloudFailure.sessionExpired;
      _persistState();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- enable
  /// Verifies [password] against the local [account], then links (or
  /// creates) the cloud account and merge-uploads the current history.
  /// Returns true when the backup is on.
  Future<bool> enable({
    required String password,
    required AccountRecord account,
    required VerifyHistory history,
  }) async {
    if (isWorking) return false;
    _failure = CloudFailure.none;
    final okLocal = await _hasher.verifyEncoded(password, account.passwordHash);
    if (!okLocal) {
      _failure = CloudFailure.wrongPassword;
      notifyListeners();
      return false;
    }

    _setWorking(true);
    try {
      final identifierHash = await cloudIdentifierHash(account.id);
      final authKey = await deriveCloudAuthKey(password);
      final vaultKey = await deriveVaultKey(password, account.id);

      // Link: create when the cloud doesn't know this identifier yet.
      final exists = await _api.lookupAccount(identifierHash: identifierHash);
      if (!exists) {
        await _api.createAccount(identifierHash: identifierHash, authKey: authKey);
      }
      final session = await _api.createSession(
        identifierHash: identifierHash,
        authKey: authKey,
      );

      _enabled = true;
      _sessionToken = session.sessionToken;
      _identifierHash = identifierHash;
      _vaultKeyHex = bytesToHex(vaultKey);
      _sessionExpiresAt = session.expiresAtMs;

      // First sync is a MERGE so an existing cloud copy (device change /
      // re-enable) is preserved and combined, never clobbered.
      await _mergeUpload(history);
      _persistState();
      return true;
    } on CloudApiException catch (e) {
      _enabled = false;
      _failure = _failureFor(e);
    } on VaultDecryptException {
      _enabled = false;
      _failure = CloudFailure.decrypt;
    } catch (_) {
      _enabled = false;
      _failure = CloudFailure.network;
    } finally {
      _setWorking(false);
    }
    return false;
  }

  // ---------------------------------------------------------------- backup
  /// Downloads the cloud vault (if any), merges it with the local
  /// history and uploads the union. Safe to run repeatedly.
  Future<bool> backupNow(VerifyHistory history) async {
    if (!hasSession || isWorking) return false;
    _failure = CloudFailure.none;
    _setWorking(true);
    try {
      await _mergeUpload(history);
      _persistState();
      return true;
    } on CloudApiException catch (e) {
      _handleApiFailure(e);
    } catch (_) {
      _failure = CloudFailure.network;
    } finally {
      _setWorking(false);
    }
    return false;
  }

  // ---------------------------------------------------------------- restore
  /// Pulls the cloud vault, decrypts it and merges the incoming entries
  /// into the local history. Returns the number of NEW entries added
  /// (-1 on failure).
  Future<int> restore(VerifyHistory history) async {
    if (!hasSession || isWorking) return -1;
    _failure = CloudFailure.none;
    _setWorking(true);
    try {
      final remote = await _api.getVault(_sessionToken!);
      if (remote == null) return 0;
      final key = hexToBytes(_vaultKeyHex!);
      final plaintext = await decryptVaultBlob(key, remote.blob);
      final incoming = decodeVaultPayload(plaintext);
      return history.mergeRemote(incoming);
    } on CloudApiException catch (e) {
      _handleApiFailure(e);
    } on VaultDecryptException {
      _failure = CloudFailure.decrypt;
    } catch (_) {
      _failure = CloudFailure.network;
    } finally {
      _setWorking(false);
    }
    return -1;
  }

  // ---------------------------------------------------------------- disable
  /// Disconnects AND deletes the cloud copy (privacy-safe default).
  Future<void> disable() async {
    if (isWorking) return;
    _setWorking(true);
    final token = _sessionToken;
    try {
      if (token != null && hasSession) {
        try {
          await _api.deleteVault(token);
        } catch (_) {/* best effort — local disconnect proceeds */}
        try {
          await _api.deleteSession(token);
        } catch (_) {/* best effort */}
      }
    } finally {
      _enabled = false;
      _sessionToken = null;
      _identifierHash = null;
      _vaultKeyHex = null;
      _sessionExpiresAt = null;
      _lastSyncAt = null;
      _failure = CloudFailure.none;
      _persistState();
      _setWorking(false);
    }
  }

  // ---------------------------------------------------------------- internals
  Future<void> _mergeUpload(VerifyHistory history) async {
    final key = hexToBytes(_vaultKeyHex!);
    final remote = await _api.getVault(_sessionToken!);
    List<HistoryEntry> merged;
    int? baseRevision;
    if (remote != null) {
      List<HistoryEntry> remoteEntries;
      try {
        remoteEntries = decodeVaultPayload(await decryptVaultBlob(key, remote.blob));
      } on VaultDecryptException {
        // The cloud copy is unreadable with THIS key (e.g. the password
        // changed on another device). Local is the source of truth for
        // this key — upload local alone; baseRevision still matches the
        // stored revision so the overwrite is clean, not a conflict.
        remoteEntries = const [];
      }
      merged = mergeHistoryEntries(history.entries, remoteEntries);
      baseRevision = remote.revision;
    } else {
      merged = history.entries.toList();
    }

    final blob = await encryptVaultBlob(key, encodeVaultPayload(merged));

    // One optimistic attempt; on conflict take the server's revision,
    // re-merge nothing (our payload already includes the union we saw —
    // a blind overwrite is safe for a fresh merge) and retry once.
    try {
      await _api.putVault(
        sessionToken: _sessionToken!,
        blob: blob,
        revision: _revisionClock(),
        baseRevision: baseRevision,
      );
    } on CloudApiException catch (e) {
      if (e.error != CloudApiError.conflict) rethrow;
      await _api.putVault(
        sessionToken: _sessionToken!,
        blob: blob,
        revision: _revisionClock(),
      );
    }
    _lastSyncAt = DateTime.now().millisecondsSinceEpoch;
  }

  void _handleApiFailure(CloudApiException e) {
    if (e.error == CloudApiError.unauthorized) {
      // Session died server-side — drop to disabled; the next enable
      // re-links and merges whatever is still on the server.
      _enabled = false;
      _failure = CloudFailure.sessionExpired;
      _persistState();
      return;
    }
    _failure = _failureFor(e);
  }

  static CloudFailure _failureFor(CloudApiException e) {
    switch (e.error) {
      case CloudApiError.badCredentials:
      case CloudApiError.exists:
      case CloudApiError.noAccount:
        return CloudFailure.wrongPassword;
      case CloudApiError.server:
      case CloudApiError.notFound:
        return CloudFailure.server;
      case CloudApiError.conflict:
      case CloudApiError.badInput:
      case CloudApiError.empty:
      case CloudApiError.network:
      case CloudApiError.unauthorized:
        return CloudFailure.network;
    }
  }

  void _setWorking(bool v) {
    _step = v ? CloudStep.working : CloudStep.idle;
    notifyListeners();
  }

  static const String _kEnabled = 'cloud.enabled';
  static const String _kToken = 'cloud.sessionToken';
  static const String _kIdentifierHash = 'cloud.identifierHash';
  static const String _kVaultKey = 'cloud.vaultKey';
  static const String _kExpiresAt = 'cloud.expiresAt';
  static const String _kLastSync = 'cloud.lastSyncAt';

  void _persistState() {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      prefs.setBool(_kEnabled, _enabled);
      final token = _sessionToken;
      if (token == null) {
        prefs.remove(_kToken);
        prefs.remove(_kIdentifierHash);
        prefs.remove(_kVaultKey);
        prefs.remove(_kExpiresAt);
      } else {
        prefs.setString(_kToken, token);
        prefs.setString(_kIdentifierHash, _identifierHash ?? '');
        prefs.setString(_kVaultKey, _vaultKeyHex ?? '');
        prefs.setInt(_kExpiresAt, _sessionExpiresAt ?? 0);
      }
      final sync = _lastSyncAt;
      if (sync == null) {
        prefs.remove(_kLastSync);
      } else {
        prefs.setInt(_kLastSync, sync);
      }
    } catch (_) {
      // Storage failure keeps the in-memory state for this run.
    }
  }
}
