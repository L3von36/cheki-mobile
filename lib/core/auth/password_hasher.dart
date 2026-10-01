/// Password hashing for Mahtem accounts.
///
/// Passwords are never stored — only a PBKDF2-HMAC-SHA256 derived key with
/// a random per-account salt, encoded as a single version-tagged string
/// (`pbkdf2-sha256$<iterations>$<saltHex>$<hashHex>`) that lives inside the
/// account record. The iteration count is injectable so tests can run a
/// fast parameter set while the app keeps a hard-to-brute-force default.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// App default — 120k PBKDF2 iterations (OWASP guidance floor for
/// PBKDF2-HMAC-SHA256). Changing it does not break stored accounts: the
/// iteration count travels inside the encoded hash.
const int kPasswordHashIterations = 120000;

/// A derived password hash: salt + key + the parameters that produced it.
class PasswordHash {
  final int iterations;
  final Uint8List salt;
  final Uint8List hash;

  const PasswordHash({
    required this.iterations,
    required this.salt,
    required this.hash,
  });

  String get _saltHex => _hex(salt);
  String get _hashHex => _hex(hash);

  /// Single-string form persisted inside the account record.
  String encode() => 'pbkdf2-sha256\$$iterations\$$_saltHex\$$_hashHex';

  /// Parses an [encode]d hash; null when malformed or from an unknown
  /// algorithm tag (forward compatibility).
  static PasswordHash? tryParse(String raw) {
    final parts = raw.split(r'$');
    if (parts.length != 4) return null;
    if (parts[0] != 'pbkdf2-sha256') return null;
    final iterations = int.tryParse(parts[1]);
    final salt = _hexDecode(parts[2]);
    final hash = _hexDecode(parts[3]);
    if (iterations == null ||
        iterations <= 0 ||
        salt == null ||
        salt.isEmpty ||
        hash == null ||
        hash.isEmpty) {
      return null;
    }
    return PasswordHash(
      iterations: iterations,
      salt: Uint8List.fromList(salt),
      hash: Uint8List.fromList(hash),
    );
  }
}

/// Derives and verifies [PasswordHash]es with PBKDF2-HMAC-SHA256.
class PasswordHasher {
  PasswordHasher({int iterations = kPasswordHashIterations})
    : iterations = iterations <= 0 ? kPasswordHashIterations : iterations;

  final int iterations;

  static const int _saltBytes = 16;
  static const int _keyBits = 256;

  final Random _random = Random.secure();

  /// Hashes [password] with a fresh random salt.
  Future<PasswordHash> hash(String password) async {
    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => _random.nextInt(256)),
    );
    final hash = await _derive(password, salt, iterations);
    return PasswordHash(iterations: iterations, salt: salt, hash: hash);
  }

  /// Constant-verification of [password] against a stored hash. Malformed
  /// stored hashes simply fail.
  Future<bool> verify(String password, PasswordHash stored) async {
    try {
      final candidate = await _derive(password, stored.salt, stored.iterations);
      return _constantTimeEquals(candidate, stored.hash);
    } catch (_) {
      return false;
    }
  }

  /// Verifies against the encoded string form — convenience for stores
  /// that keep [PasswordHash.encode] output.
  Future<bool> verifyEncoded(String password, String encoded) async {
    final stored = PasswordHash.tryParse(encoded);
    if (stored == null) return false;
    return verify(password, stored);
  }

  Future<Uint8List> _derive(
    String password,
    Uint8List salt,
    int iterations,
  ) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _keyBits,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int>? _hexDecode(String hex) {
  if (hex.isEmpty || hex.length.isOdd) return null;
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (byte == null) return null;
    out.add(byte);
  }
  return out;
}
