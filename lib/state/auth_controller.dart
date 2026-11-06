import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/auth/account.dart';
import '../core/auth/account_store.dart';
import '../core/auth/password_hasher.dart';
import '../core/auth/remote_account.dart';
import '../core/cloud/cloud_api.dart';
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

  /// The account signs in with GitHub — password sign-in cannot prove it.
  /// The UI responds by opening the GitHub device-flow sheet.
  githubRequired,
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
    BetterAuthLink? cloudLink,
    void Function(String token)? onSessionTokenDropped,
    DateTime Function()? now,
  }) : _store = store ?? ResilientAccountStore(),
       _hasher = hasher ?? PasswordHasher(),
       _remoteDirectory = remoteDirectory,
       _cloudLink = cloudLink,
       _onSessionTokenDropped = onSessionTokenDropped,
       _now = now ?? (() => DateTime.now().toUtc());

  final AccountKeyValue _store;
  final PasswordHasher _hasher;
  final RemoteAccountDirectory? _remoteDirectory;

  /// Best-effort BetterAuth link for locally-proven password accounts —
  /// runs in the background after sign-in so every account ends up with a
  /// BetterAuth identity (v1.19.0). Null in tests / when disabled.
  final BetterAuthLink? _cloudLink;
  final void Function(String token)? _onSessionTokenDropped;
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

  /// BetterAuth bearer token of the current session, when one was minted
  /// (GitHub sign-in, remote directory sign-in or the background link).
  /// The app's cloud calls accept it directly (server-side bridge).
  String? _sessionToken;

  /// The signed-in account's BetterAuth bearer token, or null.
  String? get sessionToken => _sessionToken;

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
    _sessionToken = null;
    try {
      final raw = await _store.read(_kSessionKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return;
      final id = map['accountId'];
      if (id is String && _accounts.any((a) => a.id == id)) {
        _sessionId = id;
        _sessionToken = map['token'] is String && (map['token'] as String).isNotEmpty
            ? map['token'] as String
            : null;
      }
    } catch (e, s) {
      DiagnosticsLog.I.record('auth: session payload unreadable — $e', s);
      _sessionId = null;
      _sessionToken = null;
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
      // GitHub accounts have no local password to verify — the only way
      // back in is the GitHub device flow, which the UI opens for this.
      if (account != null && account.provider == AccountRecord.kProviderGithub) {
        return const AuthFailure(AuthError.githubRequired);
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
          RemoteAuthConfirmed(:final profile, :final sessionToken) =>
            await _adoptCloudAccount(id, identifier.trim(), profile, password,
                sessionToken: sessionToken),
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
      _sessionToken = null;
      notifyListeners();
      // v1.19.0 — quietly make sure this account also exists in the
      // BetterAuth identity layer (first sign-in after the upgrade, or an
      // earlier attempt that ran offline). Non-blocking: the sign-in is
      // already complete, and a failure retries on the next sign-in.
      if (!account.baLinked) unawaited(_linkCloudIdentity(account, password));
      return AuthSuccess(account);
    });
  }

  /// Clears the session — accounts stay on the device. Any stored
  /// BetterAuth session is revoked server-side best-effort (its 30-day
  /// expiry is the backstop when the device is offline).
  Future<void> signOut() async {
    final token = _sessionToken;
    _sessionId = null;
    _sessionToken = null;
    if (token != null) {
      try {
        _onSessionTokenDropped?.call(token);
      } catch (_) {
        // Revocation is hygiene, never a gate for local sign-out.
      }
    }
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
      _sessionToken = null;
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
    String password, {
    String? sessionToken,
  }) async {
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
      // The identity was just proven through BetterAuth — it is linked.
      baLinked: sessionToken != null,
    );
    _accounts.add(account);
    if (!await _persistAccounts()) {
      _accounts.remove(account);
      return const AuthFailure(AuthError.storageFailed);
    }
    await _storeSession(account.id, token: sessionToken);
    _sessionId = account.id;
    _sessionToken = sessionToken;
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

  Future<void> _storeSession(String accountId, {String? token}) async {
    try {
      await _store.write(
        _kSessionKey,
        jsonEncode(<String, dynamic>{
          'accountId': accountId,
          'sinceMs': _now().millisecondsSinceEpoch,
          if (token != null && token.isNotEmpty) 'token': token,
        }),
      );
    } catch (_) {
      // Session persistence failed — sign-in still holds for this run.
    }
  }

  /// v1.19.0 — background BetterAuth link for a locally-proven password
  /// account. Fires after a successful sign-in; on success the record is
  /// flagged (so it never runs twice) and the bearer token rides in the
  /// persisted session. Failures are silent: the next sign-in retries,
  /// and the remote directory performs the same upgrade when needed.
  Future<void> _linkCloudIdentity(AccountRecord account, String password) async {
    final link = _cloudLink;
    if (link == null) return;
    try {
      final token = await link.linkAccount(
        accountId: account.id,
        identifier: account.identifier,
        displayName: account.displayName,
        password: password,
      );
      if (token == null || token.isEmpty) return;
      final index = _accounts.indexWhere((a) => a.id == account.id);
      if (index < 0) return;
      _accounts[index] = _accounts[index].copyWith(baLinked: true);
      await _persistAccounts();
      if (_sessionId == account.id && _sessionToken == null) {
        _sessionToken = token;
        await _storeSession(account.id, token: token);
      }
      DiagnosticsLog.I.record(
        'auth: account linked to BetterAuth identity',
        StackTrace.current,
      );
      notifyListeners();
    } catch (e, s) {
      DiagnosticsLog.I.record('auth: BetterAuth link failed — $e', s);
    }
  }

  /// v1.19.0 — completes a GitHub device-flow sign-in: the browser proved
  /// the user's identity and the app holds the resulting BetterAuth
  /// session. Creates (or refreshes) the local record — GitHub accounts
  /// carry an unusable random password hash, since sign-in always reruns
  /// the device flow — and signs the user in.
  Future<AuthResult> completeGitHubSignIn(BetterAuthSession session) {
    return _guard(() async {
      final identifier = identifierFromBetterAuthEmail(session.user.email);
      final validation = validateAccountIdentifier(identifier);
      if (validation is! AccountIdValid) {
        return const AuthFailure(AuthError.invalidIdentifier);
      }
      final id = validation.normalized;
      final name = session.user.name.trim();

      AccountRecord? existing;
      for (final a in _accounts) {
        if (a.id == id) existing = a;
      }
      if (existing != null && existing.provider == AccountRecord.kProviderGithub) {
        // Refresh the display name if the GitHub profile grew one.
        if (name.length >= _minNameLength && name != existing.displayName) {
          final index = _accounts.indexOf(existing);
          _accounts[index] = existing.copyWith(displayName: name);
          await _persistAccounts();
          existing = _accounts[index];
        }
        await _storeSession(existing.id, token: session.token);
        _sessionId = existing.id;
        _sessionToken = session.token;
        notifyListeners();
        return AuthSuccess(existing);
      }

      // A password account with the same identifier exists — GitHub simply
      // proves the same identity; adopt the session without touching the
      // local credential.
      if (existing != null) {
        await _storeSession(existing.id, token: session.token);
        _sessionId = existing.id;
        _sessionToken = session.token;
        notifyListeners();
        return AuthSuccess(existing);
      }

      // A random 256-bit value no password verifies against — the record
      // exists so settings can show the account; sign-in reruns GitHub.
      final random = Random.secure();
      final unusableHash =
          List.generate(64, (_) => random.nextInt(16).toRadixString(16)).join();
      _makeRoomForNewAccount();
      final account = AccountRecord(
        id: id,
        identifier: displayIdentifierFor(id),
        displayName: name.length >= _minNameLength
            ? name
            : displayIdentifierFor(id),
        passwordHash: unusableHash,
        createdAtUtc: _now(),
        provider: AccountRecord.kProviderGithub,
      );
      _accounts.add(account);
      if (!await _persistAccounts()) {
        _accounts.remove(account);
        return const AuthFailure(AuthError.storageFailed);
      }
      await _storeSession(account.id, token: session.token);
      _sessionId = account.id;
      _sessionToken = session.token;
      notifyListeners();
      return AuthSuccess(account);
    });
  }
}
