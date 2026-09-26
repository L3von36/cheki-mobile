/// One-time helper: generates the Mahtem license signing keypair.
/// Writes the PRIVATE seed to tool/license_secret.key (gitignored —
/// back it up!) and prints the PUBLIC key that is baked into the app.
///
/// Run:  dart run tool/gen_license_seed.dart
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final seedFile = File('tool/license_secret.key');
  if (seedFile.existsSync()) {
    final hex = seedFile.readAsStringSync().trim();
    final seed = _bytes(hex);
    stdout.writeln('tool/license_secret.key already exists — nothing done.');
    stdout.writeln('Public key: ${await _pubHex(seed)}');
    return;
  }

  final random = Random.secure();
  final seed =
      Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  seedFile.writeAsStringSync(_hex(seed));
  stdout.writeln('WROTE tool/license_secret.key (KEEP THIS FILE SAFE — it '
      'signs all activation codes; anyone holding it can mint codes).');
  stdout.writeln('');
  stdout.writeln('Public key (must match kLicensePublicKeyV1 in the app):');
  stdout.writeln(await _pubHex(seed));
}

Future<String> _pubHex(Uint8List seed) async {
  final algorithm = Ed25519();
  final pair = await algorithm.newKeyPairFromSeed(seed);
  final pub = await pair.extractPublicKey();
  return _hex(pub.bytes);
}

Uint8List _bytes(String hex) => Uint8List.fromList(List.generate(
    hex.length ~/ 2,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
