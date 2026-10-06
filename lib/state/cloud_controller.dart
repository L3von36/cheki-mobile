/// Mahtem Cloud Backup controller — zero-knowledge, self-arming.
///
/// Local-first forever: the app works fully without this controller ever
/// reaching the network. Since v1.14.0 the backup arms ITSELF: the auth
/// screens call [autoEnable] right after a successful sign-up / sign-in
/// while the plaintext password is still in hand — no settings visit, no
/// second password prompt, no button. That call:
///
///   1. verifies the password against the LOCAL account record first,
///   2. derives authKey + identifierHash + vault key on-device,
///   3. creates (or reuses) the cloud account for that identifier hash,
///   4. opens a session, merge-uploads the local history as one AES-GCM
///      blob whose key never leaves the phone,
///   5. pulls cloud-only entries back down (a fresh sign-in on a new
///      device restores the history with zero user action).
///
/// The server stores only ciphertext + digests — see cloud_keys.dart.
/// After arming, auto-sync (v1.13.1) keeps the mirror live: every local
/// change is merged and pushed debounced, and each app boot catches up
/// changes from other devices. Transient failures retry with backoff.
/// Turning the feature OFF deletes both the
/// session and the cloud copy (privacy-safe default); the next sign-in
/// arms it again.
///
/// v1.14.1 — arming is no longer one-shot: a sign-up/sign-in that lands
/// while the network is down (flaky mobile data, DNS hiccup, worker
/// outage) RETRIES with backoff for a few minutes, so the cloud account
/// gets created the moment the connection returns. The plaintext password
/// is held only in memory during that window (never persisted, never
/// logged) and is dropped as soon as arming succeeds, fails for a
/// non-transient reason, the window expires, the feature is disabled or
/// the controller dies. After that the Settings sheet remains the manual
/// fallback and the next sign-in re-arms.
///
/// v1.15.0 — SESSION CONTINUITY FIX: the OAuth upgrade (v1.14.5) made
/// access tokens 15-minute JWTs, but the 30-day refresh token was never
/// persisted — so every session silently died a quarter hour after sign-in
/// and realtime polling / auto-sync / boot catch-up all stopped. The
/// refresh token is now stored and rotated like the server expects:
/// whenever the access token is missing or about to expire, sync operations
/// transparently refresh it first ([_ensureFreshSession]), a 401 mid-flight
/// triggers exactly one refresh-and-continue, and a dead refresh token is
/// the only thing that still forces a re-sign-in.
///
/// v1.15.0 — ANALYTICS PIGGYBACK: local scans queued by [VerifyHistory]
/// ride on vault uploads as plaintext bank-only metadata (bank id/name,
/// timestamp, pass/fail) so the owner's /admin dashboard can show usage
/// and bank popularity WITHOUT any receipt content ever leaving the
/// encrypted blob. No session → no uploads → no analytics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/account.dart';
import '../core/auth/password_hasher.dart';
import '../core/auth/remote_account.dart';
import '../core/cloud/cloud_api.dart';
import '../core/cloud/cloud_keys.dart';
import '../core/cloud/cloud_vault.dart';
import '../core/verify_history.dart';

enum CloudStep { idle, working }

/// What went wrong last, mapped 1:1 to localized strings in the UI.
enum CloudFailure { none, wrongPassword, network, server, sessionExpired, decrypt }

class CloudController extends ChangeNotifier with WidgetsBindingObserver {
  CloudController({
    CloudApi? api,
    PasswordHasher? hasher,
    SharedPreferences? prefs,
    int Function()? revisionClock,
    this.autoSyncDebounce = const Duration(milliseconds: 500),
    this.autoSyncRetry = const Duration(minutes: 2),
    this.autoSyncBackoff = const Duration(minutes: 15),
    this.bootCatchUpDelay = const Duration(seconds: 5),
    this.maxAutoFailures = 3,
    this.autoArmRetries = 4,
    this.autoArmRetryDelay = const Duration(seconds: 20),
    this.enableRealtimePolling = true,
    this.realtimePollInterval = const Duration(seconds: 3),
  })  : _api = api ?? CloudApi(),
        _hasher = hasher ?? PasswordHasher(),
        _prefs = prefs,
        _revisionClock = revisionClock ?? (() => DateTime.now().millisecondsSinceEpoch) {
    WidgetsBinding.instance.addObserver(this);
  }

  final CloudApi _api;
  final PasswordHasher _hasher;
  final SharedPreferences? _prefs;
  final int Function() _revisionClock;

  // Auto-sync tuning (v1.13.1). Injected small in tests.
  final Duration autoSyncDebounce;
  final Duration autoSyncRetry;
  final Duration autoSyncBackoff;
  final Duration bootCatchUpDelay;
  final int maxAutoFailures;

  // Auto-arm retry tuning (v1.14.1). Injected small in tests. With the
  // defaults the arming window is ~5 minutes: 20s → 40s → 80s → 160s
  // backoffs after the initial attempt.
  final int autoArmRetries;
  final Duration autoArmRetryDelay;
  final bool enableRealtimePolling;
  final Duration realtimePollInterval;

  // Auto-arm retry state (ephemeral). The plaintext password lives here
  // ONLY while bounded retries are pending — never persisted, never
  // logged, dropped by [_dropArmCredentials] on every terminal outcome.
  String? _armPassword;
  AccountRecord? _armAccount;
  VerifyHistory? _armHistory;
  Timer? _armTimer;
  int _armAttempts = 0;
  static const Duration _armRecheckDelay = Duration(seconds: 3);

  // persisted state
  bool _enabled = false;
  int? _lastSyncAt;
  String? _sessionToken;
  String? _refreshToken;
  String? _identifierHash;
  String? _vaultKeyHex;
  int? _sessionExpiresAt;
  bool _autoSync = true;
  bool _dirty = false;

  /// v1.14.4 — the signed-in account's profile (name + identifier as
  /// typed). Written into every vault upload so a fresh device can
  /// rebuild the account after a cloud-proven sign-in; restored from
  /// prefs so auto-sync keeps it alive across reboots.
  RemoteAccountProfile? _profile;

  // ephemeral state
  CloudStep _step = CloudStep.idle;
  CloudFailure _failure = CloudFailure.none;

  // Session-continuity state (v1.15.0). The in-flight refresh future
  // serializes concurrent callers — the server rotates refresh tokens
  // single-use, so two parallel refreshes would burn one.
  Future<bool>? _refreshFuture;

  // auto-sync engine state (ephemeral)
  VerifyHistory? _history;
  Timer? _autoTimer;
  int _autoFailures = 0;
  int? _nextAutoAttemptAt;
  bool _catchUpPending = false;
  Timer? _realtimeTimer;
  int? _lastRemoteRevision;
  bool _isPulling = false;

  /// Banners the owner broadcasts from the admin console (v1.18 API) —
  /// active-only, newest first. Best-effort: a disabled console
  /// (tests), an offline device or a server hiccup simply leaves the
  /// last good list in place, and an authoritative empty list clears it.
  List<CloudAnnouncement> announcements = const [];

  // ---------------------------------------------------------------- accessors
  bool get enabled => _enabled;
  bool get isWorking => _step == CloudStep.working;
  CloudFailure get failure => _failure;
  int? get lastSyncAt => _lastSyncAt;

  /// The JWT access token is still valid (or expiry unknown — legacy).
  bool get _accessLive =>
      _sessionExpiresAt == null ||
      _sessionExpiresAt! > DateTime.now().millisecondsSinceEpoch;

  /// A rotating refresh token is stored, so an expired access token can
  /// be renewed transparently instead of ending the session.
  bool get _refreshable => (_refreshToken ?? '').isNotEmpty;

  /// Restore/backup only make sense with a live session. v1.15.0: a
  /// refreshable session counts too — sync paths refresh before syncing.
  bool get hasSession =>
      _enabled &&
      _sessionToken != null &&
      (_accessLive || _refreshable);

  /// Whether local changes push to the cloud automatically (v1.13.1).
  bool get autoSyncEnabled => _autoSync;

  /// True when a local change has not reached the cloud yet.
  bool get hasUnsyncedChanges => _dirty;

  // ---------------------------------------------------------------- wiring
  /// Hooks the history store so every local change can auto-sync while a
  /// backup session is live. Idempotent for the same instance (the proxy
  /// provider re-runs it on every history notification).
  void observe(VerifyHistory history) {
    if (_observes(history)) return;
    _history?.removeListener(_onHistoryChanged);
    _history = history;
    history.addListener(_onHistoryChanged);
    if (_enabled && hasSession && _autoSync) {
      _startRealtimePolling();
    }
    if (_catchUpPending) {
      if (_enabled && hasSession && _autoSync) {
        _catchUpPending = false;
        _scheduleAutoSync(bootCatchUpDelay);
      }
    }
  }

  bool _observes(VerifyHistory history) =>
      _history != null && identical(_history, history);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopRealtimePolling();
      if (_enabled && _autoSync && hasSession && _dirty) {
        _scheduleAutoSync(Duration.zero);
      }
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final history = _history;
    if (_enabled && _autoSync && hasSession && history != null) {
      _scheduleAutoSync(Duration.zero);
      _startRealtimePolling();
    }
  }

  // ---------------------------------------------------------------- auto-sync
  void _onHistoryChanged() {
    // Changes made by our own restore()/enable() are already in the
    // cloud — only user-driven edits mark the session dirty. Dirty is
    // tracked even while auto-sync is paused, so the next push (toggle
    // back on, boot catch-up) never loses a change.
    if (_step == CloudStep.working) return;
    if (!_enabled) return;
    _dirty = true;
    _persistState();
    if (_autoSync) _scheduleAutoSync(autoSyncDebounce);
  }

  void _scheduleAutoSync(Duration delay) {
    if (!_enabled || !_autoSync || !hasSession) return;
    _autoTimer?.cancel();
    _autoTimer = Timer(delay, _runAutoSync);
  }

  Future<void> _runAutoSync() async {
    if (!_enabled || !_autoSync || !hasSession) return;
    if (isWorking) {
      _scheduleAutoSync(autoSyncRetry);
      return;
    }
    final gate = _nextAutoAttemptAt;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (gate != null && now < gate) {
      _scheduleAutoSync(Duration(milliseconds: gate - now));
      return;
    }
    final history = _history;
    if (history == null) return;
    _failure = CloudFailure.none;
    _setWorking(true);
    try {
      if (!await _ensureFreshSession()) {
        // Deterministic refresh failure already disabled us (failure =
        // sessionExpired); a network-level failure is retried as usual.
        if (_enabled && _failure == CloudFailure.none) {
          _failure = CloudFailure.network;
          _noteAutoFailure();
        }
        return;
      }
      await _mergeUpload(history);
      _dirty = false;
      _autoFailures = 0;
      _nextAutoAttemptAt = null;
      _persistState();
    } on CloudApiException catch (e) {
      if (e.error == CloudApiError.unauthorized) {
        // Session died server-side — _handleApiFailure disables us, so
        // auto-sync stops until the user re-enables (re-enable merges
        // whatever is still on the server).
        _handleApiFailure(e);
      } else {
        _failure = _failureFor(e);
        _noteAutoFailure();
      }
    } on VaultDecryptException {
      _failure = CloudFailure.decrypt;
    } catch (_) {
      _failure = CloudFailure.network;
      _noteAutoFailure();
    } finally {
      _setWorking(false);
    }
  }

  void _noteAutoFailure() {
    _autoFailures++;
    final backoff = _autoFailures >= maxAutoFailures;
    if (backoff) {
      _nextAutoAttemptAt =
          DateTime.now().millisecondsSinceEpoch + autoSyncBackoff.inMilliseconds;
    }
    _scheduleAutoSync(backoff ? autoSyncBackoff : autoSyncRetry);
  }

  /// User-facing auto-backup toggle. Turning it on syncs pending changes
  /// promptly; turning it off cancels the pending push (manual Back-up-now
  /// still works).
  Future<void> setAutoSync(bool on) async {
    if (_autoSync == on) return;
    _autoSync = on;
    if (on) {
      _startRealtimePolling();
      if (_dirty) {
        _scheduleAutoSync(autoSyncDebounce);
      }
    } else {
      _stopRealtimePolling();
      _autoTimer?.cancel();
    }
    _persistState();
    notifyListeners();
  }

  // ---------------------------------------------------------------- session continuity
  /// v1.15.0 — makes sure the access token is usable before a sync
  /// operation, silently rotating it via the stored refresh token when it
  /// is expired or about to expire. Returns false only when no usable
  /// session can be established.
  Future<bool> _ensureFreshSession() async {
    if (!_enabled || _sessionToken == null) return false;
    if (_accessLive) return true;
    if (!_refreshable) return false;
    return _refreshSession();
  }

  /// Serialized wrapper: concurrent callers share one in-flight refresh
  /// (the server rotates refresh tokens single-use).
  Future<bool> _refreshSession() async {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;
    final token = _refreshToken ?? '';
    if (token.isEmpty) return false;
    final fut = _performRefresh(token);
    _refreshFuture = fut;
    try {
      return await fut;
    } finally {
      if (identical(_refreshFuture, fut)) _refreshFuture = null;
    }
  }

  Future<bool> _performRefresh(String refreshToken) async {
    try {
      final session = await _api.refreshSession(refreshToken);
      if (session.sessionToken.isEmpty) return false;
      _sessionToken = session.sessionToken;
      // The server always rotates; keep the old token only as a fallback
      // if a future server build stops returning one.
      _refreshToken = (session.refreshToken ?? '').isNotEmpty
          ? session.refreshToken
          : refreshToken;
      _sessionExpiresAt =
          session.expiresAtMs != 0 ? session.expiresAtMs : _sessionExpiresAt;
      _autoFailures = 0;
      _nextAutoAttemptAt = null;
      _persistState();
      return true;
    } on CloudApiException catch (e) {
      if (e.error == CloudApiError.unauthorized ||
          e.error == CloudApiError.badInput ||
          e.error == CloudApiError.badCredentials) {
        // The refresh grant is dead (used / revoked / expired) — nothing
        // left to renew. Drop to the re-sign-in path.
        _enabled = false;
        _failure = CloudFailure.sessionExpired;
        _persistState();
        notifyListeners();
      }
      return false;
    } catch (_) {
      // Network-level — tokens stay put; the next tick retries.
      return false;
    }
  }

  // ---------------------------------------------------------------- realtime sync
  void _startRealtimePolling() {
    _stopRealtimePolling();
    if (!enableRealtimePolling || !_enabled || !hasSession || !_autoSync) return;
    _realtimeTimer = Timer.periodic(realtimePollInterval, (_) {
      _onRealtimeTick();
    });
  }

  void _stopRealtimePolling() {
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
  }

  Future<void> _onRealtimeTick() async {
    if (!enableRealtimePolling ||
        !_enabled ||
        !hasSession ||
        !_autoSync ||
        isWorking ||
        _isPulling) {
      return;
    }
    if (!await _ensureFreshSession()) return;
    final history = _history;
    if (history == null) return;

    if (_dirty) {
      await _runAutoSync();
      return;
    }

    await pollNow(history);
  }

  /// Pulls the latest changes from the cloud immediately.
  /// Ultra-fast: checks sinceRevision so no bandwidth or decryption
  /// happens if the vault hasn't changed.
  Future<int> pollNow(VerifyHistory history) async {
    if (!_enabled || !hasSession || isWorking || _isPulling) return 0;
    if (!await _ensureFreshSession()) return 0;
    _isPulling = true;
    try {
      final remote = await _api.getVault(
        _sessionToken!,
        sinceRevision: _lastRemoteRevision,
      );
      if (remote == null) return 0;
      if (remote.notModified) {
        _lastRemoteRevision = remote.revision;
        return 0;
      }
      if (remote.revision == _lastRemoteRevision && _lastRemoteRevision != null) {
        return 0;
      }
      _lastRemoteRevision = remote.revision;
      if (remote.blob.isEmpty) return 0;
      final key = hexToBytes(_vaultKeyHex!);
      final incoming = await _decodeRemoteEntries(key, remote.blob);
      final added = await history.mergeRemote(incoming);
      if (added > 0) {
        _lastSyncAt = _revisionClock();
        _persistState();
      }
      return added;
    } on CloudApiException catch (e) {
      if (e.error == CloudApiError.unauthorized) {
        _handleApiFailure(e);
      }
      return 0;
    } catch (_) {
      return 0;
    } finally {
      _isPulling = false;
    }
  }

  /// Fetches the owner's active announcements for the banner on the
  /// Verify tab. No-op when the cloud is disabled (prefs-less, as in
  /// tests); failures keep the last good list; the server's list is
  /// authoritative when it answers.
  Future<void> refreshAnnouncements() async {
    if (_prefs == null) return;
    try {
      final list = await _api.fetchAnnouncements();
      list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      announcements = list;
      notifyListeners();
    } catch (_) {
      // offline / 5xx — keep showing the last successfully loaded set
    }
  }

  // ---------------------------------------------------------------- auto-on
  /// v1.14.0 — backup arms ITSELF: the auth screens call this right after
  /// a successful sign-up / sign-in, while the plaintext password is still
  /// in hand. No settings visit, no second password prompt, no button.
  ///
  /// Bounded-retry contract (v1.14.1): failures never escape (enable/
  /// restore swallow them into [failure]); a TRANSIENT failure (network /
  /// server) schedules up to [autoArmRetries] retries with exponential
  /// backoff, so a sign-up that lands offline still creates the cloud
  /// account once the connection returns — zero user action. Deterministic
  /// failures (wrong password, decrypt) drop the credentials immediately:
  /// retrying cannot fix those. Signing in on a new device therefore
  /// restores the history without any user action: enable() merge-uploads
  /// local ∪ remote, then restore() pulls cloud-only entries down (a
  /// no-op on fresh sign-up).
  Future<void> autoEnable({
    required String password,
    required AccountRecord account,
    required VerifyHistory history,
  }) async {
    // Already syncing THIS exact account (re-sign-in)? Everything is
    // live — refresh the local history without creating another session.
    if (_enabled &&
        hasSession &&
        _identifierHash != null &&
        _identifierHash == await cloudIdentifierHash(account.id)) {
      if (isWorking) {
        _armPassword = password;
        _armAccount = account;
        _armHistory = history;
        _armAttempts = 0;
        _scheduleArm(_armRecheckDelay);
      } else {
        await restore(history);
      }
      return;
    }
    if (isWorking) {
      _armPassword = password;
      _armAccount = account;
      _armHistory = history;
      _armAttempts = 0;
      _scheduleArm(_armRecheckDelay);
      return;
    }
    // Account SWITCH (another device account): re-link to that cloud
    // identity. The previous account's server copy is intentionally left
    // untouched — signing back into it merges and continues.
    _armPassword = password;
    _armAccount = account;
    _armHistory = history;
    _armAttempts = 0;
    await _armAttempt();
  }

  /// One arming attempt inside the bounded retry window. See autoEnable.
  Future<void> _armAttempt() async {
    final password = _armPassword;
    final account = _armAccount;
    final history = _armHistory;
    if (password == null || account == null || history == null) return;
    if (isWorking) {
      // Another operation owns the controller right now — recheck
      // shortly WITHOUT burning a retry (its duration is bounded by
      // network timeouts, so this cannot loop forever).
      _scheduleArm(_armRecheckDelay);
      return;
    }
    // Armed for THIS account in the meantime (e.g. manual enable in the
    // Settings sheet)? The credentials are no longer needed. Armed for a
    // DIFFERENT account? Keep going — enable() below performs the switch.
    if (_enabled && hasSession && _identifierHash != null) {
      final armedForSame =
          _identifierHash == await cloudIdentifierHash(account.id);
      if (armedForSame) {
        _dropArmCredentials();
        await restore(history);
        return;
      }
    }
    final ok = await enable(
      password: password,
      account: account,
      history: history,
    );
    if (ok) {
      _dropArmCredentials();
      await restore(history);
      return;
    }
    // Wrong password / unreadable cloud copy will not heal by retrying.
    if (_failure != CloudFailure.network && _failure != CloudFailure.server) {
      _dropArmCredentials();
      return;
    }
    if (_armAttempts >= autoArmRetries) {
      _dropArmCredentials();
      return;
    }
    _armAttempts++;
    _scheduleArm(autoArmRetryDelay * (1 << (_armAttempts - 1)));
  }

  void _scheduleArm(Duration delay) {
    _armTimer?.cancel();
    _armTimer = Timer(delay, _armAttempt);
  }

  /// Ends the retry window and forgets the plaintext password.
  void _dropArmCredentials() {
    _armTimer?.cancel();
    _armTimer = null;
    _armPassword = null;
    _armAccount = null;
    _armHistory = null;
    _armAttempts = 0;
  }

  // ---------------------------------------------------------------- lifecycle
  Future<void> ensureLoaded() async {
    final prefs = _prefs;
    if (prefs == null) return;
    _enabled = prefs.getBool(_kEnabled) ?? false;
    _sessionToken = prefs.getString(_kToken);
    _refreshToken = prefs.getString(_kRefreshToken);
    _identifierHash = prefs.getString(_kIdentifierHash);
    _vaultKeyHex = prefs.getString(_kVaultKey);
    _sessionExpiresAt = prefs.getInt(_kExpiresAt);
    _lastSyncAt = prefs.getInt(_kLastSync);
    _autoSync = prefs.getBool(_kAutoSync) ?? true;
    _dirty = prefs.getBool(_kDirty) ?? false;
    _profile = _profileFromPrefs(prefs);
    // Boot catch-up pushes pending changes and pulls changes from other
    // devices. It is consumed once a history store is attached.
    if (_enabled &&
        (_sessionToken == null ||
            _vaultKeyHex == null ||
            _identifierHash == null ||
            !hasSession)) {
      // v1.15.0 — an expired JWT no longer kills the session here: when a
      // refresh token is stored, hasSession stays true and the first sync
      // silently renews the access token. Without a refresh token there is
      // nothing to renew — require a fresh enable (re-enter password). The
      // server copy, if any, is untouched; the user can re-enable and
      // merge it.
      _enabled = false;
      _failure = CloudFailure.sessionExpired;
      _persistState();
    }
    // Every app boot checks for entries written by another device, even
    // when this device's last upload was recent.
    _catchUpPending = _enabled;
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

      // v1.14.4 — the profile rides inside the encrypted vault so sign-in
      // on a cleared device / second phone can restore the display name.
      _profile = RemoteAccountProfile.fromAccount(account);

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
      _refreshToken = session.refreshToken;
      _identifierHash = identifierHash;
      _vaultKeyHex = bytesToHex(vaultKey);
      _sessionExpiresAt = session.expiresAtMs;

      // First sync is a MERGE so an existing cloud copy (device change /
      // re-enable) is preserved and combined, never clobbered.
      await _mergeUpload(history);
      _dirty = false;
      _autoFailures = 0;
      _nextAutoAttemptAt = null;
      _catchUpPending = false;
      _persistState();
      _startRealtimePolling();
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
    if (!await _ensureFreshSession()) return false;
    _failure = CloudFailure.none;
    _setWorking(true);
    try {
      await _mergeUpload(history);
      _dirty = false;
      _autoFailures = 0;
      _nextAutoAttemptAt = null;
      _persistState();
      return true;
    } on CloudApiException catch (e) {
      _handleApiFailure(e);
    } on VaultDecryptException {
      _failure = CloudFailure.decrypt;
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
    if (!await _ensureFreshSession()) return -1;
    _failure = CloudFailure.none;
    _setWorking(true);
    try {
      final remote = await _api.getVault(_sessionToken!);
      if (remote == null) return 0;
      _lastRemoteRevision = remote.revision;
      final key = hexToBytes(_vaultKeyHex!);
      final incoming = await _decodeRemoteEntries(key, remote.blob);
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
      _stopRealtimePolling();
      _dropArmCredentials();
      _autoTimer?.cancel();
      _enabled = false;
      _sessionToken = null;
      _refreshToken = null;
      _identifierHash = null;
      _vaultKeyHex = null;
      _sessionExpiresAt = null;
      _lastSyncAt = null;
      _failure = CloudFailure.none;
      _autoFailures = 0;
      _nextAutoAttemptAt = null;
      _dirty = false;
      _profile = null;
      _persistState();
      _setWorking(false);
    }
  }

  // ---------------------------------------------------------------- internals
  Future<void> _mergeUpload(VerifyHistory history) async {
    await history.ensureLoaded();
    final key = hexToBytes(_vaultKeyHex!);
    // v1.15.0 analytics: local scans queued by the history store ride
    // along as bank-only plaintext metadata. Peeked BEFORE the write and
    // acked only AFTER it succeeds, so a failed upload never loses them.
    final pendingStats = history.peekPendingReport();
    final stats = pendingStats.map((e) => <String, Object>{
          'b': e.bankId,
          'n': e.bankName,
          't': e.verifiedAt,
          'v': e.isVerified ? 1 : 0,
        }).toList();
    for (var attempt = 0; attempt < 2; attempt++) {
      final remote = await _api.getVault(_sessionToken!);
      List<HistoryEntry> remoteEntries = const [];
      if (remote != null) {
        remoteEntries = await _decodeRemoteEntries(key, remote.blob);
        await history.mergeRemote(remoteEntries);
      }
      final merged = mergeHistoryEntries(history.entries, remoteEntries);
      final blob = await encryptVaultBlob(
        key,
        encodeVaultPayload(merged, account: _profile),
      );

      final rev = _revisionClock();
      try {
        await _api.putVault(
          sessionToken: _sessionToken!,
          blob: blob,
          revision: rev,
          baseRevision: remote?.revision,
          stats: stats.isEmpty ? null : stats,
        );
      } on CloudApiException catch (e) {
        if (e.error != CloudApiError.conflict || attempt == 1) rethrow;
        continue;
      }
      _lastRemoteRevision = rev;
      _lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      if (pendingStats.isNotEmpty) {
        history.ackPendingReport(pendingStats.length);
      }
      return;
    }
  }

  Future<List<HistoryEntry>> _decodeRemoteEntries(
    Uint8List key,
    String blob,
  ) async {
    try {
      return decodeVaultPayload(await decryptVaultBlob(key, blob));
    } on VaultDecryptException {
      rethrow;
    } catch (_) {
      throw const VaultDecryptException('invalid cloud vault payload');
    }
  }

  void _handleApiFailure(CloudApiException e) {
    if (e.error == CloudApiError.unauthorized) {
      // v1.15.0 — a 401 mid-flight usually means the access token expired
      // while the operation ran. One refresh revives the session and the
      // caller's normal retry schedule takes over; only a dead refresh
      // grant actually ends the session.
      if (_refreshable) {
        // Run asynchronously so this handler stays sync-safe for every
        // caller; the next scheduled sync uses the renewed token.
        _refreshSession();
        return;
      }
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
  static const String _kRefreshToken = 'cloud.refreshToken';
  static const String _kIdentifierHash = 'cloud.identifierHash';
  static const String _kVaultKey = 'cloud.vaultKey';
  static const String _kExpiresAt = 'cloud.expiresAt';
  static const String _kLastSync = 'cloud.lastSyncAt';
  static const String _kAutoSync = 'cloud.autoSync';
  static const String _kDirty = 'cloud.dirty';
  static const String _kProfile = 'cloud.accountProfile';

  /// Parses the persisted profile; malformed payloads are dropped (the
  /// next vault upload from a signed-in session re-writes it).
  static RemoteAccountProfile? _profileFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(_kProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final identifier = map['identifier'];
      final displayName = map['displayName'];
      if (identifier is! String ||
          identifier.isEmpty ||
          displayName is! String ||
          displayName.trim().isEmpty) {
        return null;
      }
      return RemoteAccountProfile(
        identifier: identifier,
        displayName: displayName.trim(),
        createdAtMs: (map['createdAtMs'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  void _persistState() {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      prefs.setBool(_kEnabled, _enabled);
      final token = _sessionToken;
      if (token == null) {
        prefs.remove(_kToken);
        prefs.remove(_kRefreshToken);
        prefs.remove(_kIdentifierHash);
        prefs.remove(_kVaultKey);
        prefs.remove(_kExpiresAt);
      } else {
        prefs.setString(_kToken, token);
        final refresh = _refreshToken;
        if (refresh == null || refresh.isEmpty) {
          prefs.remove(_kRefreshToken);
        } else {
          prefs.setString(_kRefreshToken, refresh);
        }
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
      final profile = _profile;
      if (profile == null) {
        prefs.remove(_kProfile);
      } else {
        prefs.setString(
          _kProfile,
          jsonEncode(<String, dynamic>{
            'identifier': profile.identifier,
            'displayName': profile.displayName,
            if (profile.createdAtMs != null) 'createdAtMs': profile.createdAtMs,
          }),
        );
      }
      prefs.setBool(_kAutoSync, _autoSync);
      prefs.setBool(_kDirty, _dirty);
    } catch (_) {
      // Storage failure keeps the in-memory state for this run.
    }
  }

  @override
  void dispose() {
    _stopRealtimePolling();
    WidgetsBinding.instance.removeObserver(this);
    _dropArmCredentials();
    _autoTimer?.cancel();
    _history?.removeListener(_onHistoryChanged);
    super.dispose();
  }
}
