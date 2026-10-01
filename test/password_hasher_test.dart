import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/auth/password_hasher.dart';

void main() {
  group('PasswordHasher', () {
    test('round-trips a correct password', () async {
      final hasher = PasswordHasher(iterations: 1000);
      final hash = await hasher.hash('correct horse');
      expect(await hasher.verify('correct horse', hash), isTrue);
      expect(await hasher.verify('wrong horse', hash), isFalse);
    });

    test('salts are unique per hash call', () async {
      final hasher = PasswordHasher(iterations: 1000);
      final a = await hasher.hash('same-password');
      final b = await hasher.hash('same-password');
      expect(a.salt, isNot(equals(b.salt)));
      expect(a.hash, isNot(equals(b.hash)));
    });

    test('encode/tryParse round-trip keeps parameters', () async {
      final hasher = PasswordHasher(iterations: 2000);
      final hash = await hasher.hash('p@ss');
      final encoded = hash.encode();
      expect(encoded.startsWith('pbkdf2-sha256\$2000\$'), isTrue);

      final parsed = PasswordHash.tryParse(encoded);
      expect(parsed, isNotNull);
      expect(parsed!.iterations, 2000);
      expect(parsed.salt, hash.salt);
      expect(parsed.hash, hash.hash);
      expect(await hasher.verify('p@ss', parsed), isTrue);
      expect(await hasher.verifyEncoded('p@ss', encoded), isTrue);
      expect(await hasher.verifyEncoded('nope', encoded), isFalse);
    });

    test('tryParse refuses garbage and unknown algorithms', () {
      expect(PasswordHash.tryParse(''), isNull);
      expect(PasswordHash.tryParse('garbage'), isNull);
      expect(PasswordHash.tryParse('md5\$1000\$ab\$cd'), isNull);
      expect(PasswordHash.tryParse('pbkdf2-sha256\$x\$ab\$cd'), isNull);
      expect(PasswordHash.tryParse('pbkdf2-sha256\$1000\$zz\$cd'), isNull);
      expect(PasswordHash.tryParse('pbkdf2-sha256\$0\$ab\$cd'), isNull);
    });

    test('malformed stored hash verifies false without throwing', () async {
      final hasher = PasswordHasher(iterations: 1000);
      expect(await hasher.verifyEncoded('x', 'garbage'), isFalse);
      expect(await hasher.verifyEncoded('x', ''), isFalse);
    });

    test('app default iterations stay strong', () {
      expect(kPasswordHashIterations, 120000);
      expect(PasswordHasher().iterations, kPasswordHashIterations);
    });
  });
}
