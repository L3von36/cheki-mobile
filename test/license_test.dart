import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/licensing/license.dart';

/// Fixed TEST signing seed — production signs with tool/license_secret.key,
/// whose public key is baked into the app. Tests mint + verify with this
/// local pair via the injectable publicKeyHex parameter.
const String _testSeedHex =
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';

Uint8List _seed() => _bytes(_testSeedHex);

Future<String> _publicKeyHex() async {
  // Derive the test public key by minting a token and reading it back is
  // impossible — expose it via a throwaway sign/verify loop instead:
  // simplest is to recompute it the same way the app constant was made.
  final algorithm = Ed25519();
  final pair = await algorithm.newKeyPairFromSeed(_seed());
  final pub = await pair.extractPublicKey();
  return pub.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<String> _mint({
  required Uint8List deviceHash,
  required DateTime expiryUtc,
}) =>
    makeLicenseToken(seed: _seed(), expiryUtc: expiryUtc, deviceHash: deviceHash);

Uint8List _bytes(String hex) => Uint8List.fromList(List.generate(
    hex.length ~/ 2,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));

void main() {
  final deviceHash = deviceHashFor('device-1');
  final now = DateTime.utc(2026, 9, 26);

  group('device identity', () {
    test('device hash is stable and 4 bytes', () {
      expect(deviceHashFor('device-1'), deviceHashFor('device-1'));
      expect(deviceHashFor('device-1').length, 4);
      expect(
          deviceHashFor('device-1'), isNot(deviceHashFor('device-2')));
    });

    test('device code round-trips through deviceHashFromCode', () {
      final code = deviceCodeFor(deviceHash);
      expect(code.startsWith('MAH-'), isTrue);
      expect(deviceHashFromCode(code), deviceHash);
      // Tolerates the ways users copy/send it.
      expect(deviceHashFromCode(code.toLowerCase()), deviceHash);
      expect(deviceHashFromCode(' ${code.toLowerCase()} '), deviceHash);
      // 'U' is not in the Crockford alphabet — undecodable.
      expect(deviceHashFromCode('UUU'), isNull);
      expect(deviceHashFromCode(''), isNull);
    });
  });

  group('license tokens', () {
    test('valid token verifies and carries its expiry', () async {
      final expiry = DateTime.utc(2026, 10, 27);
      final token = await _mint(
          deviceHash: deviceHash, expiryUtc: expiry);
      final result = await validateLicenseToken(
        token,
        deviceHash: deviceHash,
        now: now,
        publicKeyHex: await _publicKeyHex(),
      );
      expect(result, isA<LicenseValid>());
      expect((result as LicenseValid).expiryUtc, expiry);
    });

    test('a token for another device is refused', () async {
      final token = await _mint(
          deviceHash: deviceHashFor('other-phone'),
          expiryUtc: DateTime.utc(2026, 10, 27));
      final result = await validateLicenseToken(
        token,
        deviceHash: deviceHash,
        now: now,
        publicKeyHex: await _publicKeyHex(),
      );
      expect(result, isA<LicenseWrongDevice>());
    });

    test('an expired token is refused but still identified', () async {
      final token = await _mint(
          deviceHash: deviceHash,
          expiryUtc: DateTime.utc(2026, 3, 1));
      final result = await validateLicenseToken(
        token,
        deviceHash: deviceHash,
        now: now,
        publicKeyHex: await _publicKeyHex(),
      );
      expect(result, isA<LicenseExpired>());
      expect((result as LicenseExpired).expiryUtc, DateTime.utc(2026, 3, 1));
    });

    test('a flipped character breaks the signature', () async {
      final token = await _mint(
          deviceHash: deviceHash, expiryUtc: DateTime.utc(2026, 10, 27));
      // Corrupt the LAST character — it sits inside the signature part, so
      // the payload still decodes (version byte intact) but the signature
      // no longer verifies.
      final chars = token.split('');
      final last = chars[chars.length - 1];
      chars[chars.length - 1] = last == 'Z' ? 'Y' : 'Z';
      final result = await validateLicenseToken(
        chars.join(),
        deviceHash: deviceHash,
        now: now,
        publicKeyHex: await _publicKeyHex(),
      );
      expect(result, isA<LicenseBadSignature>());
    });

    test('non-tokens are bad-format', () async {
      for (final garbage in ['', 'hello world', 'U-U-U-U-U', '12345']) {
        final result = await validateLicenseToken(
          garbage,
          deviceHash: deviceHash,
          now: now,
          publicKeyHex: await _publicKeyHex(),
        );
        expect(result, isA<LicenseBadFormat>(), reason: 'input: "$garbage"');
      }
    });

    test('paste noise is tolerated (case, spacing, prefixes, lookalikes)',
        () async {
      final token = await _mint(
          deviceHash: deviceHash, expiryUtc: DateTime.utc(2026, 10, 27));

      final variants = <String>[
        token.toLowerCase(),
        token.replaceAll('-', ' '),
        token.replaceAll('-', ''),
        token.substring(4), // without the MAH- prefix
        'mahtem ${token.toLowerCase()}',
        // Crockford lookalikes: 0→O, 1→I must decode identically.
        token.contains('0') && token.contains('1')
            ? token.replaceAll('0', 'O').replaceAll('1', 'I')
            : token,
      ];

      for (final variant in variants) {
        final result = await validateLicenseToken(
          variant,
          deviceHash: deviceHash,
          now: now,
          publicKeyHex: await _publicKeyHex(),
        );
        expect(result, isA<LicenseValid>(), reason: 'input: "$variant"');
      }
    });
  });
}
