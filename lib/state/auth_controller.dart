import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/auth/account.dart';
import '../core/auth/account_store.dart';
import '../core/auth/password_hasher.dart';
import '../core/auth/remote_account.dart';
import '../core/error_safety_net.dart';

/// Why a sign-up / sign-in attempt was refused. The UI maps these to
/// localized messages; the controller stays language-free.
enum AuthError {
  invalidName,
  invalidIdentifier,
  invalidEmail,
  invalidPassword,
  passwordMismatch,
  alreadyExists,
  accountNotFound,
  wrongPassword,
  network,
  storageFailed,
}

/// Result of a sign-up / sign-in attempt.
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  const AuthSuccess(this.account);
  final AccountRecord account;
}

class AuthFailure extends AuthResult {
  const AuthFailure(this.error);
  final AuthError error;
}

/// Central account state for Mahtem's device-local accounts: sign-up,
/// sign-in, sign-out and the persisted session. Exposed app-wide via
/// `provider`.
///
/// Accounts are stored ON-DEVICE (Android Keystore-encrypted secure
/// storage with a SharedPreferences mirror) — passwords are PBKDF2-
/// hashed and the raw password is never sent anywhere. Since v1.14.4
/// sign-in is no longer device-bound: when the identifier is unknown
/// LOCALLY, the controller asks the [RemoteAccountDirectory] (the
/// zero-knowledge cloud provisioned at sign-up by backup arming) to
/// prove the credentials remotely; a confirmed match rebuilds the local
/// account — display name rides back inside the encrypted vault — so
/// clearing app data or switching phones no longer locks the user out.
/// The [AccountKeyValue] store and the directory are both injectable so
/// tests can run without platform secure storage or the network.
///
/// Gating model: when a valid session exists the app boots straight into
/// the shell; otherwise the auth gate shows sign-in (or create-account on
/// a fresh install with no accounts).
class AuthController extends ChangeNotifier {
  AuthController({
    AccountKeyValue? store,
    PasswordHasher? hasher,
    RemoteAccountDirectory? remoteDirectory,
    DateTime Function()? now,
  }) : _store = store ?? ResilientAccountStore(),
       _hasher = hasher ?? PasswordHasher(),
       _remoteDirectory = remoteDirectory,
       _now = now ?? (() => DateTime.now().toUtc());

  final AccountKeyValue _store;
  final PasswordHasher _hasher;
  final RemoteAccountDirectory? _remoteDirectory;
  final DateTime Function() _now;

  static const String _kAccountsKey = 'accounts_v1';
  static const String _kSessionKey = 'session_v1';

  static const int _minNameLength = 2;
  static const int _minPasswordLength = 6;
  static const int _maxAccounts = 8;

  bool _loaded = false;
  bool _loading = false;
  bool _busy = false;
  List<AccountRecord> _accounts = <AccountRecord>[];
  String? _sessionId;

  // ---------------------------------------------------------------- accessors

  bool get isLoaded => _loaded;

  /// True while a sign-up / sign-in / reset request is in flight — the
  /// buttons show a spinner and ignore extra taps.
  bool get isBusy => _busy;

  /// All accounts registered on this device.
  List<AccountRecord> get accounts => List.unmodifiable(_accounts);

  /// True when at least one account exists on this device.
  bool get hasAccounts => _accounts.isNotEmpty;

  /// The signed-in account, or null when signed out / session invalid.
  AccountRecord? get currentAccount {
    final id = _sessionId;
    if (id == null) return null;
    for (final account in _accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  bool get isSignedIn => currentAccount != null;

  // ---------------------------------------------------------------- lifecycle

  /// Loads persisted accounts and the session. Idempotent and
  /// concurrency-safe; the auth gate awaits this before deciding which
  /// screen to show.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      await _loadAccounts();
      await _loadSession();
      _loaded = true;
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadAccounts() async {
    _accounts = <AccountRecord>[];
    try {
      final raw = await _store.read(_kAccountsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _accounts = decoded
          .whereType<Map<String, dynamic>>()
          .map(AccountRecord.tryFromJson)
          .whereType<AccountRecord>()
          .toList();
    } catch (e, s) {
      // Persisted accounts could not be decoded — surface it in the
      // diagnostics trail instead of failing silently; sign-up still
      // works and the next write replaces the corrupt payload.
      DiagnosticsLog.I.record('auth: accounts payload unreadable — $e', s);
      _accounts = <AccountRecord>[];
    }
  }

  Future<void> _loadSession() async {
    _sessionId = null;
    try {
      final raw = await _store.read(_kSessionKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return;
      final id = map['accountId'];
      if (id is String && _accounts.any((a) => a.id == id)) {
        _sessionId = id;
      }
    } catch (e, s) {
      DiagnosticsLog.I.record('auth: session payload unreadable — $e', s);
      _sessionId = null;
    }
  }

  // ---------------------------------------------------------------- mutation

  /// Creates an account and signs in. The first account on the device
  /// becomes the session immediately.
  Future<AuthResult> signUp({
    required String displayName,
    required String identifier,
    required String password,
  }) async {
    return _guard(() async {
      final name = displayName.trim();
      if (name.length < _minNameLength || name.length > 60) {
        return const AuthFailure(AuthError.invalidName);
      }
      final validation = validateAccountIdentifier(identifier);
      if (validation is! AccountIdValid) {
        // Sealed hierarchy: not valid ⇒ AccountIdInvalid.
        final issue = (validation as AccountIdInvalid).issue;
        return AuthFailure(switch (issue) {
          AccountIdIssue.empty ||
          AccountIdIssue.invalidPhone => AuthError.invalidIdentifier,
          AccountIdIssue.invalidEmail => AuthError.invalidEmail,
        });
      }
      if (password.length < _minPasswordLength) {
        return const AuthFailure(AuthError.invalidPassword);
      }
      final id = validation.normalized;
      if (_accounts.any((a) => a.id == id)) {
        return const AuthFailure(AuthError.alreadyExists);
      }

      // v1.14.1: a hashing failure (platform crypto edge case) must be a
      // visible storageFailed, not an exception escaping into the UI.
      final String hash;
      try {
        hash = (await _hasher.hash(password)).encode();
      } catch (_) {
        return const AuthFailure(AuthError.storageFailed);
      }
      final account = AccountRecord(
        id: id,
        identifier: identifier.trim(),
        displayName: name,
        passwordHash: hash,
        createdAtUtc: _now(),
      );
      _makeRoomForNewAccount();
      _accounts.add(account);
      if (!await _persistAccounts()) {
        _accounts.remove(account);
        return const AuthFailure(AuthError.storageFailed);
      }
      await _storeSession(account.id);
      _sessionId = account.id;
      notifyListeners();
      return AuthSuccess(account);
    });
  }

  /// Signs in with the identifier + password. The identifier is
  /// normalized the same way sign-up normalized it, so `0911223344`,
  /// `+251911223344` and `251911223344` all find the same account.
  ///
  /// v1.14.4 — two-tier lookup. Fast path: the account exists on this
  /// device, the password is verified against the local PBKDF2 hash and
  /// no network is touched. Fallback: the identifier is unknown locally
  /// (fresh install, cleared app data, second phone) — the cloud
  /// provisioned at sign-up is asked to prove the credentials instead;
  /// a confirmed match rebuilds the account locally and signs in, so
  /// the user's account follows them across devices.
  Future<AuthResult> signIn({
    required String identifier,
    required String password,
  }) async {
    return _guard(() async {
      final validation = validateAccountIdentifier(identifier);
      if (validation is! AccountIdValid) {
        // A malformed identifier is an INPUT problem, not a missing
        // account — the old accountNotFound message here sent users
        // re-creating accounts over a typo.
        final issue = (validation as AccountIdInvalid).issue;
        return AuthFailure(switch (issue) {
          AccountIdIssue.empty || AccountIdIssue.invalidPhone =>
            AuthError.invalidIdentifier,
          AccountIdIssue.invalidEmail => AuthError.invalidEmail,
        });
      }
      final id = validation.normalized;
      AccountRecord? account;
      for (final a in _accounts) {
        if (a.id == id) account = a;
      }
      if (account == null) {
        final directory = _remoteDirectory;
        if (directory == null) {
          return const AuthFailure(AuthError.accountNotFound);
        }
        final RemoteAuthOutcome outcome;
        try {
          outcome = await directory.authenticate(
            accountId: id,
            password: password,
          );
        } catch (_) {
          // The directory itself blew up — inconclusive, report it as a
          // network problem rather than inventing "no account".
          return const AuthFailure(AuthError.network);
        }
        return switch (outcome) {
          RemoteAuthConfirmed(:final profile) =>
            await _adoptCloudAccount(id, identifier.trim(), profile, password),
          RemoteAuthUnknownAccount() =>
            const AuthFailure(AuthError.accountNotFound),
          RemoteAuthBadPassword() =>
            const AuthFailure(AuthError.wrongPassword),
          RemoteAuthUnreachable() => const AuthFailure(AuthError.network),
        };
      }
      final ok = await _hasher.verifyEncoded(password, account.passwordHash);
      if (!ok) return const AuthFailure(AuthError.wrongPassword);
      await _storeSession(account.id);
      _sessionId = account.id;
      notifyListeners();
      return AuthSuccess(account);
    });
  }

  /// Clears the session — accounts stay on the device.
  Future<void> signOut() async {
    _sessionId = null;
    try {
      await _store.delete(_kSessionKey);
    } catch (_) {
      // Session could not be cleared from storage; the in-memory sign-out
      // still applies for this run.
    }
    notifyListeners();
  }

  /// "Forgot password" escape hatch: wipes every account (and the
  /// session) from THIS device only, returning the app to the
  /// create-account state. Verification history and licensing are
  /// untouched — they live under different storage keys.
  Future<void> resetAccounts() async {
    _busy = true;
    notifyListeners();
    try {
      _accounts = <AccountRecord>[];
      _sessionId = null;
      try {
        await _store.delete(_kAccountsKey);
        await _store.delete(_kSessionKey);
      } catch (_) {
        // Storage wipe failed — in-memory reset still applies.
      }
      notifyListeners();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- internals

  /// v1.14.4 — the cloud proved the identifier + password; rebuild the
  /// account on this device and sign in. The display name and original
  /// identifier come from the profile that rode inside the encrypted
  /// vault; older vaults (or no vault yet) fall back to the normalized
  /// identifier for display. The local password hash is minted fresh
  /// from the just-proven password, so every later sign-in on this
  /// device is offline-local again.
  Future<AuthResult> _adoptCloudAccount(
    String id,
    String typedIdentifier,
    RemoteAccountProfile? profile,
    String password,
  ) async {
    final String hash;
    try {
      hash = (await _hasher.hash(password)).encode();
    } catch (_) {
      return const AuthFailure(AuthError.storageFailed);
    }
    // A local record appeared meanwhile (race) — treat it as the
    // ordinary local sign-in instead of duplicating the account.
    AccountRecord? existing;
    for (final a in _accounts) {
      if (a.id == id) existing = a;
    }
    if (existing != null) {
      final ok = await _hasher.verifyEncoded(password, existing.passwordHash);
      if (!ok) return const AuthFailure(AuthError.wrongPassword);
      await _storeSession(existing.id);
      _sessionId = existing.id;
      notifyListeners();
      return AuthSuccess(existing);
    }
    _makeRoomForNewAccount();
    final profileName = profile?.displayName.trim() ?? '';
    final profileIdentifier = profile?.identifier.trim() ?? '';
    final account = AccountRecord(
      id: id,
      identifier: profileIdentifier.isNotEmpty
          ? profileIdentifier
          : typedIdentifier,
      displayName:
          (profileName.length >= _minNameLength && profileName.length <= 60)
              ? profileName
              : displayIdentifierFor(id),
      passwordHash: hash,
      createdAtUtc: profile?.createdAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(
              profile!.createdAtMs!,
              isUtc: true,
            )
          : _now(),
    );
    _accounts.add(account);
    if (!await _persistAccounts()) {
      _accounts.remove(account);
      return const AuthFailure(AuthError.storageFailed);
    }
    await _storeSession(account.id);
    _sessionId = account.id;
    // Observability without leaking the identifier into the trail.
    DiagnosticsLog.I.record(
      'auth: account restored via cloud sign-in',
      StackTrace.current,
    );
    notifyListeners();
    return AuthSuccess(account);
  }

  /// Keeps the persisted list within [_maxAccounts]: when the device is
  /// full, the OLDEST record gives way. (Previously the newest account
  /// was the one silently dropped at persist time — the worse loss.)
  void _makeRoomForNewAccount() {
    while (_accounts.length >= _maxAccounts) {
      _accounts.removeAt(0);
    }
  }

  /// Runs a mutation while flagging [isBusy], so the UI can show spinners.
  Future<T> _guard<T>(Future<T> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _persistAccounts() async {
    try {
      final list = _accounts.take(_maxAccounts).map((a) => a.toJson()).toList();
      await _store.write(_kAccountsKey, jsonEncode(list));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _storeSession(String accountId) async {
    try {
      await _store.write(
        _kSessionKey,
        jsonEncode(<String, dynamic>{
          'accountId': accountId,
          'sinceMs': _now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {
      // Session persistence failed — sign-in still holds for this run.
    }
  }
}
