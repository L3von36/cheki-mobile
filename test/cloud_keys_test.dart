import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/cloud/cloud_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('key derivation', () {
    test('identifierHash is stable, normalized, 64-hex', () async {
      final a = await cloudIdentifierHash(' User@Example.COM ');
      final b = await cloudIdentifierHash('user@example.com');
      expect(a, b);
      expect(a, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
    });

    test('cloud authKey is a deterministic 64-hex digest', () async {
      final a = await deriveCloudAuthKey('secret123');
      final b = await deriveCloudAuthKey('secret123');
      final c = await deriveCloudAuthKey('secret124');
      expect(a, b);
      expect(a, isNot(c));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
    });

    test('vault key differs per identifier and is 32 bytes', () async {
      final a = await deriveVaultKey('secret123', 'user@example.com');
      final b = await deriveVaultKey('secret123', 'other@example.com');
      final c = await deriveVaultKey('secret124', 'user@example.com');
      expect(a, hasLength(32));
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });

  group('vault encryption', () {
    test('encrypt/decrypt round-trips', () async {
      final key = await deriveVaultKey('secret123', 'user@example.com');
      const plaintext = '{"v":1,"entries":[{"id":"a"}]}';

      final blob = await encryptVaultBlob(key, plaintext);
      expect(blob, isNot(contains('entries'))); // no plaintext leakage
      final decrypted = await decryptVaultBlob(key, blob);
      expect(decrypted, plaintext);
    });

    test('same plaintext encrypts to different ciphertexts (random nonce)',
        () async {
      final key = await deriveVaultKey('secret123', 'user@example.com');
      final b1 = await encryptVaultBlob(key, 'same-text');
      final b2 = await encryptVaultBlob(key, 'same-text');
      expect(b1, isNot(b2));
    });

    test('wrong key throws VaultDecryptException', () async {
      final key = await deriveVaultKey('secret123', 'user@example.com');
      final other = await deriveVaultKey('other-password', 'user@example.com');
      final blob = await encryptVaultBlob(key, 'top secret');

      expect(
        () => decryptVaultBlob(other, blob),
        throwsA(isA<VaultDecryptException>()),
      );
    });

    test('tampered ciphertext throws VaultDecryptException', () async {
      final key = await deriveVaultKey('secret123', 'user@example.com');
      final blob = base64Decode(await encryptVaultBlob(key, 'payload'));
      blob[blob.length - 1] ^= 0xFF; // flip the last ciphertext byte

      expect(
        () => decryptVaultBlob(key, base64Encode(blob)),
        throwsA(isA<VaultDecryptException>()),
      );
    });

    test('truncated blob throws VaultDecryptException', () async {
      final key = await deriveVaultKey('secret123', 'user@example.com');
      expect(
        () => decryptVaultBlob(key, base64Encode([1, 2, 3])),
        throwsA(isA<VaultDecryptException>()),
      );
    });
  });

  group('hex helpers', () {
    test('bytesToHex / hexToBytes round-trip', () {
      final bytes = [0x00, 0x0f, 0xa0, 0xff];
      expect(hexToBytes(bytesToHex(bytes)), bytes);
    });
  });
}
