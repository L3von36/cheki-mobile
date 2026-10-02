import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:mahtem/core/receipt_verify/parsers.dart' show pbkdf2Sha1;

/// Test fixture: encrypts a BOA slip QR payload exactly the way BOA's
/// web app does (AES-256-CBC, PBKDF2-SHA1 key from a static passphrase,
/// static salt and IV) so the offline decryptor round-trips in tests.
Uint8List encryptBoaQrForTests(String plain) {
  final key = pbkdf2Sha1(
      utf8.encode('ELqVy2g4pGWLUIKSa+1ijwpPy6eDxBFBLBPrJ24v/IA='),
      utf8.encode('salt'),
      10000,
      32);
  final cbc = CBCBlockCipher(AESEngine());
  final padded = PaddedBlockCipherImpl(PKCS7Padding(), cbc);
  padded.init(
    true,
    PaddedBlockCipherParameters(
      ParametersWithIV(
          KeyParameter(key), Uint8List.fromList(utf8.encode('1234567890123456'))),
      null,
    ),
  );
  return padded.process(Uint8List.fromList(utf8.encode(plain)));
}
