import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/licensing/license.dart';
import 'package:mahtem/core/licensing/license_store.dart';
import 'package:mahtem/core/licensing/paywall_config.dart';
import 'package:mahtem/state/license_controller.dart';

Uint8List _seed() => Uint8List.fromList(List.generate(32, (i) => i));

Future<String> _publicKeyHex() async {
  final pair =
      await Ed25519().newKeyPairFromSeed(_seed());
  final pub = await pair.extractPublicKey();
  return pub.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Controller wired to in-memory storage, a fake device and a fixed clock.
LicenseController _controller(
  MemoryLicenseStore store, {
  String deviceKey = 'device-1',
  required DateTime Function() now,
  required String publicKeyHex,
}) {
  return LicenseController(
    store: store,
    deviceKeySource: () async => deviceKey,
    now: now,
    publicKeyHex: publicKeyHex,
  );
}

void main() {
  final publicKeyHexFuture = _publicKeyHex();
  final start = DateTime.utc(2026, 9, 26);

  // Fresh fixtures each test: store + clock that advances on demand.
  (MemoryLicenseStore, DateTime Function()) fixtures() {
    final clockNow = start;
    return (MemoryLicenseStore(), () => clockNow);
  }

  Future<String> mintFor(String deviceKey, {DateTime? expiry}) async {
    final expiryUtc = expiry ?? DateTime.utc(2026, 10, 27);
    return makeLicenseToken(
      seed: _seed(),
      expiryUtc: expiryUtc,
      deviceHash: deviceHashFor(deviceKey),
    );
  }

  group('free trial', () {
    test('starts with 5 checks and blocks when used up', () async {
      final (store, now) = fixtures();
      final c = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c.ensureLoaded();
      expect(c.trialsLeft, kFreeTrialChecks);
      expect(c.canVerifyNow, isTrue);

      for (var i = 0; i < kFreeTrialChecks; i++) {
        await c.consumeAttempt();
      }
      expect(c.trialsLeft, 0);
      expect(c.canVerifyNow, isFalse);
    });

    test('trial usage survives a restart (persisted)', () async {
      final (store, now) = fixtures();
      final c = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c.ensureLoaded();
      await c.consumeAttempt();
      await c.consumeAttempt();
      expect(c.trialsLeft, kFreeTrialChecks - 2);

      // Fresh controller over the same storage — e.g. app relaunch.
      final c2 = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c2.ensureLoaded();
      expect(c2.trialsLeft, kFreeTrialChecks - 2);
      expect(c2.canVerifyNow, isTrue);
    });
  });

  group('activation', () {
    test('a valid device-bound code unlocks without touching trials',
        () async {
      final (store, now) = fixtures();
      final c = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c.ensureLoaded();
      await c.consumeAttempt(); // 1 free check burned

      final result =
          await c.activate(await mintFor('device-1'));
      expect(result, isA<LicenseValid>());
      expect(c.isEntitled, isTrue);
      expect(c.canVerifyNow, isTrue);

      // Entitled users do not burn trials.
      await c.consumeAttempt();
      expect(c.trialsLeft, kFreeTrialChecks - 1);

      // Expiry is ~31 days out.
      expect(c.daysLeft, greaterThanOrEqualTo(30));
      expect(c.daysLeft, lessThanOrEqualTo(31));
    });

    test('a code for another device is refused with the right reason',
        () async {
      final (store, now) = fixtures();
      final c = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c.ensureLoaded();
      final result = await c.activate(await mintFor('other-phone'));
      expect(result, isA<LicenseWrongDevice>());
      expect(c.isEntitled, isFalse);
    });

    test('an expired code is refused with the right reason', () async {
      final (store, now) = fixtures();
      final c = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c.ensureLoaded();
      final result = await c.activate(
          await mintFor('device-1', expiry: DateTime.utc(2026, 3, 1)));
      expect(result, isA<LicenseExpired>());
      expect(c.isEntitled, isFalse);
    });

    test('an activated license survives a restart', () async {
      final (store, now) = fixtures();
      final c = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c.ensureLoaded();
      await c.activate(await mintFor('device-1'));

      final c2 = _controller(store,
          now: now, publicKeyHex: await publicKeyHexFuture);
      await c2.ensureLoaded();
      expect(c2.isEntitled, isTrue);
      expect(c2.canVerifyNow, isTrue);
    });

    test('a license expiring while the app runs stops verifying', () async {
      final (store, _) = fixtures();
      var now = start;
      final c = _controller(store,
          now: () => now, publicKeyHex: await publicKeyHexFuture);
      await c.ensureLoaded();
      await c.activate(await mintFor('device-1'));
      expect(c.isEntitled, isTrue);

      now = DateTime.utc(2026, 12, 1); // past the 2026-10-27 expiry
      expect(c.isEntitled, isFalse);
      // Trials were never used — the user falls back to them.
      expect(c.canVerifyNow, isTrue);
    });
  });

  group('device identity fallback', () {
    test('without SSAID a persisted fallback key is used', () async {
      final store = MemoryLicenseStore();
      final c = LicenseController(
        store: store,
        deviceKeySource: () async => null,
        now: () => start,
        publicKeyHex: await publicKeyHexFuture,
      );
      await c.ensureLoaded();
      expect(c.deviceCode, startsWith('MAH-'));
      expect(c.deviceCode.length, 'MAH-'.length + 7);

      // The fallback key persists — the same "device" comes back.
      final c2 = LicenseController(
        store: store,
        deviceKeySource: () async => null,
        now: () => start,
        publicKeyHex: await publicKeyHexFuture,
      );
      await c2.ensureLoaded();
      expect(c2.deviceCode, c.deviceCode);
    });
  });
}
