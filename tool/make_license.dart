/// Mahtem license generator — the owner's side of the paywall.
///
///   dart run tool/make_license.dart MAH-7Q2M4VB              # 1 month
///   dart run tool/make_license.dart MAH-7Q2M4VB --months 12  # 1 year
///   dart run tool/make_license.dart MAH-7Q2M4VB --days 7     # custom
///
/// The device code comes from the customer's paywall screen; the payment
/// (150 ETB/month) is confirmed by YOU on Telebirr first. The signing seed
/// lives in tool/license_secret.key — keep it private and BACKED UP; anyone
/// holding it can mint free codes.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mahtem/core/licensing/license.dart';

const String _kSecretPath = 'tool/license_secret.key';

Future<void> main(List<String> args) async {
  // ── load (or first-run create) the signing seed ──────────────────────────
  final seedFile = File(_kSecretPath);
  Uint8List seed;
  if (seedFile.existsSync()) {
    seed = _bytes(seedFile.readAsStringSync().trim());
  } else {
    seed = Uint8List.fromList(
        List.generate(32, (_) => Random.secure().nextInt(256)));
    seedFile.writeAsStringSync(_hex(seed));
    stdout.writeln('Created a NEW signing seed at $_kSecretPath.');
    stdout.writeln('⚠  BACK IT UP (e.g. print it / save offline). If you '
        'lose it you cannot make more codes, and the app must be rebuilt '
        'with a new public key.');
    stdout.writeln('');
  }

  // ── parse arguments ──────────────────────────────────────────────────────
  var months = 1;
  var days = 0;
  String? deviceArg;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--months=')) {
      months = int.tryParse(arg.substring(9)) ?? months;
    } else if (arg == '--months' && i + 1 < args.length) {
      months = int.tryParse(args[++i]) ?? months;
    } else if (arg.startsWith('--days=')) {
      days = int.tryParse(arg.substring(6)) ?? days;
    } else if (arg == '--days' && i + 1 < args.length) {
      days = int.tryParse(args[++i]) ?? days;
    } else if (!arg.startsWith('--')) {
      deviceArg = arg;
    }
  }
  if (deviceArg == null) {
    stdout.writeln('Usage: dart run tool/make_license.dart <device-code> '
        '[--months N] [--days N]');
    stdout.writeln('  device-code  the MAH-XXXXXXX shown on the customer\'s '
        'paywall');
    stdout.writeln('  --months N   plan length in months (default 1 = 31 '
        'days)');
    stdout.writeln('  --days N     exact length in days (overrides '
        '--months)');
    exit(2);
  }

  final deviceHash = deviceHashFromCode(deviceArg);
  if (deviceHash == null) {
    stderr.writeln('✗ "$deviceArg" is not a valid device code — copy it '
        'exactly from the customer\'s paywall (MAH-XXXXXXX).');
    exit(2);
  }

  final planDays = days > 0 ? days : months * 31;
  final expiry =
      DateTime.now().toUtc().add(Duration(days: planDays));

  final token = await makeLicenseToken(
    seed: seed,
    expiryUtc: expiry,
    deviceHash: deviceHash,
  );

  stdout.writeln('');
  stdout.writeln('✓ License ready — send this to the customer:');
  stdout.writeln('');
  stdout.writeln(token);
  stdout.writeln('');
  stdout.writeln('Device ${deviceCodeFor(deviceHash)} · valid until '
      '${expiry.toLocal()} ($planDays days)');
}

Uint8List _bytes(String hex) => Uint8List.fromList(List.generate(
    hex.length ~/ 2,
    (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
