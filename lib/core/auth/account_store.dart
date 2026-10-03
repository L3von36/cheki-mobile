/// Persistence for the account layer.
///
/// Primary layer: [ResilientAccountStore] keeps accounts AND the session
/// in FlutterSecureStorage (Android Keystore-encrypted) with a
/// SharedPreferences mirror behind it. Passwords are never stored in any
/// form other than the PBKDF2-encoded hash; nothing is ever sent to a
/// server.
///
/// Why the mirror: the encrypted secure-storage payload can become
/// unreadable on a small but real set of devices (Keystore invalidation
/// after OS events, device migrations restoring data without the
/// non-exportable keys, plugin migration bugs — the flutter_secure_storage
/// v10 line shipped several such data-loss fixes). When that happens the
/// account silently vanishes: the user sees "No account found for this
/// phone/email — create one first" after every restart. The mirror holds
/// the exact same bytes in the app's private storage, so an unreadable
/// secure layer self-heals from it on the next read instead of losing the
/// account. The mirror adds no new exposure class: it contains only the
/// encoded password hash — the same data the verify history already keeps
/// in plain app-private storage.
library;

import 'dart:async' show unawaited;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../error_safety_net.dart';

abstract class AccountKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Secure storage with a SharedPreferences mirror and self-heal.
///
/// * write: goes to BOTH layers; throws only when BOTH fail —
///   degraded-but-persisted beats a hard error when one layer is broken.
/// * read: primary (secure) layer first; on throw OR absent key falls
///   back to the mirror and re-seeds the primary in the background
///   ("heal") so later reads hit the encrypted layer again.
/// * delete: removes from both.
///
/// Both layers are [AccountKeyValue]s so tests can inject fakes; in the
/// app the primary is [SecureAccountStore] and the mirror wraps
/// SharedPreferences. Every degraded event is recorded in
/// [DiagnosticsLog.I] so the Settings "Report a problem" trail shows
/// what the platform storage did.
class ResilientAccountStore implements AccountKeyValue {
  ResilientAccountStore({AccountKeyValue? primary, AccountKeyValue? mirror})
    : _primary = primary ?? SecureAccountStore(),
      _mirrorOverride = mirror;

  final AccountKeyValue _primary;
  final AccountKeyValue? _mirrorOverride;
  AccountKeyValue? _lazyMirror;

  @override
  Future<String?> read(String key) async {
    String? value;
    try {
      value = await _primary.read(key);
    } catch (e, s) {
      _record('primary-read', e, s);
    }
    if (value != null) return value;

    // Primary has nothing usable — fall back to the mirror.
    final mirror = await _resolveMirror();
    if (mirror == null) return null;
    try {
      final mirrored = await mirror.read(key);
      if (mirrored != null) {
        // Heal once so subsequent reads hit the encrypted layer again.
        unawaited(_heal(key, mirrored));
        return mirrored;
      }
    } catch (e, s) {
      _record('mirror-read', e, s);
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    Object? firstError;
    var persistedAnywhere = false;

    try {
      await _primary.write(key, value);
      persistedAnywhere = true;
    } catch (e, s) {
      firstError ??= e;
      _record('primary-write', e, s);
    }

    final mirror = await _resolveMirror();
    if (mirror != null) {
      try {
        await mirror.write(key, value);
        persistedAnywhere = true;
      } catch (e, s) {
        firstError ??= e;
        _record('mirror-write', e, s);
      }
    }

    if (!persistedAnywhere) {
      throw firstError ??
          Exception('ResilientAccountStore: both storage layers failed');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _primary.delete(key);
    } catch (e, s) {
      _record('primary-delete', e, s);
    }
    final mirror = await _resolveMirror();
    if (mirror == null) return;
    try {
      await mirror.delete(key);
    } catch (e, s) {
      _record('mirror-delete', e, s);
    }
  }

  Future<AccountKeyValue?> _resolveMirror() {
    if (_mirrorOverride != null) {
      return Future<AccountKeyValue?>.value(_mirrorOverride);
    }
    if (_lazyMirror != null) return Future<AccountKeyValue?>.value(_lazyMirror);
    return _loadPrefsMirror();
  }

  Future<AccountKeyValue?> _loadPrefsMirror() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _lazyMirror = SharedPreferencesMirror(prefs);
    } catch (e, s) {
      _record('mirror-init', e, s);
      return null;
    }
  }

  Future<void> _heal(String key, String value) async {
    try {
      await _primary.write(key, value);
      _record('heal', 're-seeded primary layer from mirror', StackTrace.current);
    } catch (e, s) {
      // Mirror stays authoritative until the primary layer recovers.
      _record('heal-failed', e, s);
    }
  }

  void _record(String op, Object error, StackTrace stack) {
    // Fire-and-forget: diagnostics must never break account operations.
    try {
      DiagnosticsLog.I.record('account-store[$op]: $error', stack);
    } catch (_) {}
  }
}

/// The default primary layer — Android Keystore-encrypted secure storage.
class SecureAccountStore implements AccountKeyValue {
  SecureAccountStore();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) =>
      _storage.read(key: _qualified(key)).catchError((_) => null);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: _qualified(key), value: value);

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: _qualified(key)).catchError((_) {});

  static String _qualified(String key) => 'mahtem.auth.$key';
}

/// SharedPreferences-backed mirror — same app sandbox, plain storage.
class SharedPreferencesMirror implements AccountKeyValue {
  SharedPreferencesMirror(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<String?> read(String key) async => _prefs.getString(_qualified(key));

  @override
  Future<void> write(String key, String value) async =>
      _prefs.setString(_qualified(key), value);

  @override
  Future<void> delete(String key) async => _prefs.remove(_qualified(key));

  static String _qualified(String key) => 'mahtem.auth.$key';
}

/// In-memory store for tests.
class MemoryAccountStore implements AccountKeyValue {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
