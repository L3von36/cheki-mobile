/// Persistence for the licensing layer.
///
/// Values live in [FlutterSecureStorage] — Android Keystore-encrypted — so
/// a casual "clear app data" or a root file edit cannot simply flip the
/// trial counter or paste a license token. Anything the platform cannot
/// provide degrades gracefully: the app still works, licensing just falls
/// back to defaults.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class LicenseKeyValue {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureLicenseStore implements LicenseKeyValue {
  SecureLicenseStore();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _prefix = 'mahtem.license.';

  @override
  Future<String?> read(String key) =>
      _storage.read(key: '$_prefix$key').catchError((_) => null);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);
}

/// In-memory store for tests.
class MemoryLicenseStore implements LicenseKeyValue {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
