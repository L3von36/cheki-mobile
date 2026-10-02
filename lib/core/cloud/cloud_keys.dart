/// Zero-knowledge cloud crypto for Mahtem Cloud Backup (v1.13.0).
///
/// All three secrets are derived ON THE DEVICE; the raw password never
/// leaves it. The server (Cloudflare Worker `mahtem-api`) can therefore
/// never decrypt a vault — it only ever sees:
///   * `authKey` — a 256-bit PBKDF2 output used to prove identity
///     (one-way: deriving it back into the password or the vault key is
///     computationally infeasible),
///   * `identifierHash` — SHA-256 of the normalized account identifier,
///   * the vault ciphertext itself.
///
/// Salt strings are versioned so parameters can evolve without breaking
/// stored backups.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int kCloudKdfIterations = 120000;

final Pbkdf2 _kdf = Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: kCloudKdfIterations,
  bits: 256,
);
final AesGcm _aes = AesGcm.with256bits();

/// Normalizes an identifier the same way the local auth flow does before
/// hashing (lowercase + trim), so `0911223344` and `+251…` variants that
/// normalize identically locally also hash identically in the cloud.
String normalizeCloudIdentifier(String identifier) =>
    identifier.trim().toLowerCase();

/// SHA-256 hex of the normalized identifier — what the server stores
/// instead of the identifier itself.
Future<String> cloudIdentifierHash(String identifier) async {
  final hash = await Sha256().hash(
    utf8.encode(normalizeCloudIdentifier(identifier)),
  );
  return bytesToHex(hash.bytes);
}

/// Client-side login secret: PBKDF2(password, fixed app salt). Sent to
/// the server at account creation / sign-in INSTEAD of the password.
Future<String> deriveCloudAuthKey(String password) async {
  final key = await _kdf.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: utf8.encode('mahtem-cloud-auth-v1'),
  );
  return bytesToHex(await key.extractBytes());
}

/// Vault encryption key: PBKDF2 over the password AND the identifier —
/// per-user salt without server storage. NEVER leaves the device.
Future<Uint8List> deriveVaultKey(String password, String identifier) async {
  final key = await _kdf.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce:
        utf8.encode('mahtem-cloud-vault-v1:${normalizeCloudIdentifier(identifier)}'),
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// Encrypts the vault JSON. Wire format: base64( nonce(12) ‖ mac(16) ‖
/// ciphertext ). Throws on failure of the underlying cipher only.
Future<String> encryptVaultBlob(Uint8List vaultKey, String plaintext) async {
  final nonce = _aes.newNonce();
  final box = await _aes.encrypt(
    utf8.encode(plaintext),
    secretKey: SecretKey(vaultKey),
    nonce: nonce,
  );
  final out = BytesBuilder()
    ..add(box.nonce)
    ..add(box.mac.bytes)
    ..add(box.cipherText);
  return base64Encode(out.toBytes());
}

/// Decrypts a vault blob; throws [VaultDecryptException] on a wrong key
/// or a tampered payload.
Future<String> decryptVaultBlob(Uint8List vaultKey, String blobB64) async {
  final raw = base64Decode(blobB64);
  if (raw.length < 12 + 16) {
    throw const VaultDecryptException('blob too short');
  }
  try {
    final plain = await _aes.decrypt(
      SecretBox(
        raw.sublist(28),
        nonce: raw.sublist(0, 12),
        mac: Mac(raw.sublist(12, 28)),
      ),
      secretKey: SecretKey(vaultKey),
    );
    return utf8.decode(plain);
  } on SecretBoxAuthenticationError {
    throw const VaultDecryptException('wrong key or tampered blob');
  }
}

class VaultDecryptException implements Exception {
  final String message;
  const VaultDecryptException(this.message);
  @override
  String toString() => 'VaultDecryptException: $message';
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
