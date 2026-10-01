/// Persistence for the account layer.
///
/// Accounts and the current session live in [FlutterSecureStorage] —
/// Android Keystore-encrypted — so the password hashes and session token
/// are not readable by other apps or by casual file edits. Anything the
/// platform cannot provide degrades gracefully: auth still works for the
/// session, persistence just falls back to defaults.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AccountKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAccountStore implements AccountKeyValue {
  SecureAccountStore();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _prefix = 'mahtem.auth.';

  @override
  Future<String?> read(String key) =>
      _storage.read(key: '$_prefix$key').catchError((_) => null);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: '$_prefix$key').catchError((_) {});
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
