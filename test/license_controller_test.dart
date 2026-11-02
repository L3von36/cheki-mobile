import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/cloud/cloud_api.dart';
import 'package:mahtem/core/licensing/license.dart';
import 'package:mahtem/core/licensing/license_store.dart';
import 'package:mahtem/core/licensing/paywall_config.dart';
import 'package:mahtem/core/licensing/receipt_activation.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';
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

/// A verified Telebirr receipt the fake engine hands back: a genuine
/// 300 ETB payment to the owner, paid 2026-09-20 (fresh vs the clock).
ReceiptData _paidReceipt({
  double amount = 300,
  String invoice = 'CHQ261Z4AB2C',
  String receiverAccount = '989680816',
  String receiverName = 'NOVEL WOLDE MICHAEL',
  String? date = '20-09-2026 12:00:00',
  String? status = 'Successful',
}) {
  return ReceiptData(
    verified: true,
    bankCode: 'telebirr',
    bankName: 'Telebirr',
    reference: invoice,
    receiverName: receiverName,
    receiverAccount: receiverAccount,
    amount: amount,
    date: date,
    transactionStatus: status,
    invoiceNumber: invoice,
  );
}

LicenseController _receiptController(
  MemoryLicenseStore store, {
  required DateTime Function() now,
  required String publicKeyHex,
  required Future<VerifyResult> Function(VerifyInput input) verifier,
  String deviceKey = 'device-1',
}) {
  return LicenseController(
    store: store,
    deviceKeySource: () async => deviceKey,
    now: now,
    publicKeyHex: publicKeyHex,
    receiptVerifier: verifier,
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

  group('server trial clamp (v1.18.10)', () {
    test('sends a full SHA-256 device hash to the server', () async {
      final (store, now) = fixtures();
      String? sentHash;
      final c = LicenseController(
        store: store,
        deviceKeySource: () async => 'device-1',
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        trialSync: ({required String deviceHashHex, int? used}) async {
          sentHash = deviceHashHex;
          return TrialSyncInfo(
            used: 0,
            freeChecks: kFreeTrialChecks,
            trialsRemaining: kFreeTrialChecks,
            proActive: false,
          );
        },
      );

      await c.ensureLoaded();

      final expected = deviceTrialHashFor('device-1')
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(sentHash, hasLength(64));
      expect(sentHash, expected);
    });

    test('cleared storage cannot mint trials back — server counter wins',
        () async {
      final (store, now) = fixtures();
      // The device burned 3 checks before the wipe; the server remembers.
      var serverUsed = 3;
      Future<TrialSyncInfo?> syncFn(
          {required String deviceHashHex, int? used}) async {
        if (used != null && used > serverUsed) serverUsed = used;
        return TrialSyncInfo(
          used: serverUsed,
          freeChecks: kFreeTrialChecks,
          trialsRemaining:
              (kFreeTrialChecks - serverUsed).clamp(0, kFreeTrialChecks),
          proActive: false,
        );
      }

      // A wiped install: local counter is back to 0.
      final c = LicenseController(
        store: store,
        deviceKeySource: () async => 'device-1',
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        trialSync: syncFn,
      );
      await c.ensureLoaded();
      await pumpEventQueue();
      expect(c.trialsLeft, kFreeTrialChecks - 3,
          reason: 'the server restores the burned budget');
      expect(c.canVerifyNow, isTrue);

      // One more check burns #4 and reports it; the server keeps counting.
      await c.consumeAttempt();
      await pumpEventQueue();
      expect(c.trialsLeft, 1);
      expect(serverUsed, 4);
    });

    test('offline sync (null) leaves the local counter alone', () async {
      final (store, now) = fixtures();
      final c = LicenseController(
        store: store,
        deviceKeySource: () async => 'device-1',
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        trialSync: ({required String deviceHashHex, int? used}) async => null,
      );
      await c.ensureLoaded();
      await pumpEventQueue();
      expect(c.trialsLeft, kFreeTrialChecks);
      await c.consumeAttempt();
      expect(c.trialsLeft, kFreeTrialChecks - 1);
    });

    test('launch clamp is awaited — counter is server-accurate the moment '
        'ensureLoaded returns', () async {
      final (store, now) = fixtures();
      // This device burned 4 checks before the wipe.
      const serverUsed = 4;
      final c = LicenseController(
        store: store,
        deviceKeySource: () async => 'device-1',
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        trialSync: ({required String deviceHashHex, int? used}) async =>
            TrialSyncInfo(
          used: serverUsed,
          freeChecks: kFreeTrialChecks,
          trialsRemaining: kFreeTrialChecks - serverUsed,
          proActive: false,
        ),
      );
      // Deliberately NO pumpEventQueue: the gate awaits ensureLoaded, so
      // the clamp must already be applied when it returns.
      await c.ensureLoaded();
      expect(c.trialsLeft, kFreeTrialChecks - 4);
      expect(c.canVerifyNow, isTrue);
    });
  });

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

  group('receipt self-activation', () {
    test('a genuine 300 ETB receipt to the owner unlocks instantly',
        () async {
      final (store, now) = fixtures();
      VerifyInput? seen;
      final c = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (input) async {
          seen = input;
          return VerifyResult.receipt(_paidReceipt(), 10);
        },
      );
      await c.ensureLoaded();

      final out = await c.activateWithReceipt(' CHQ261Z4AB2C ');
      expect(out, isA<ReceiptActivationSuccess>());
      final ok = out as ReceiptActivationSuccess;
      expect(ok.alreadyActive, isFalse);
      expect(ok.expiryUtc, start.add(const Duration(days: 31)));
      expect(c.isEntitled, isTrue);
      expect(c.canVerifyNow, isTrue);
      expect(c.daysLeft, inInclusiveRange(30, 31));

      // Entitlement means verifications no longer burn trials.
      await c.consumeAttempt();
      expect(c.trialsLeft, kFreeTrialChecks);

      // The engine ran the pasted reference against Telebirr.
      expect(seen!.bankId, 'telebirr');
      expect(seen!.reference, 'CHQ261Z4AB2C');
    });

    test('receipt activation survives a restart', () async {
      final (store, now) = fixtures();
      Future<VerifyResult> ok(VerifyInput _) async =>
          VerifyResult.receipt(_paidReceipt(), 10);
      final c = _receiptController(store,
          now: now, publicKeyHex: await publicKeyHexFuture, verifier: ok);
      await c.ensureLoaded();
      await c.activateWithReceipt('CHQ261Z4AB2C');

      final c2 = _receiptController(store,
          now: now, publicKeyHex: await publicKeyHexFuture, verifier: ok);
      await c2.ensureLoaded();
      expect(c2.isEntitled, isTrue);
      expect(c2.expiresAt, start.add(const Duration(days: 31)));
    });

    test('a wrong amount is rejected and stores nothing', () async {
      final (store, now) = fixtures();
      final c = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (_) async =>
            VerifyResult.receipt(_paidReceipt(amount: 50), 10),
      );
      await c.ensureLoaded();

      final out = await c.activateWithReceipt('CHQ261Z4AB2C');
      expect(out, isA<ReceiptActivationRejected>());
      expect((out as ReceiptActivationRejected).message,
          contains('exactly 300 ETB'));
      expect(c.isEntitled, isFalse);
      // Trials were untouched — the user can still fall back to them.
      expect(c.canVerifyNow, isTrue);

      final c2 = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (_) async =>
            VerifyResult.receipt(_paidReceipt(amount: 50), 10),
      );
      await c2.ensureLoaded();
      expect(c2.isEntitled, isFalse);
    });

    test('money sent to another account is rejected', () async {
      final (store, now) = fixtures();
      final c = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (_) async => VerifyResult.receipt(
            _paidReceipt(
                receiverAccount: '0911223344',
                receiverName: 'Someone Else'),
            10),
      );
      await c.ensureLoaded();

      final out = await c.activateWithReceipt('CHQ261Z4AB2C');
      expect(out, isA<ReceiptActivationRejected>());
      expect(c.isEntitled, isFalse);
    });

    test('a network failure is retryable and leaves state untouched',
        () async {
      final (store, now) = fixtures();
      final c = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (_) async => VerifyResult.failed(
          const VerifyFailure(VerifyErrorKind.network,
              'Could not reach Telebirr.'),
          10,
        ),
      );
      await c.ensureLoaded();

      final out = await c.activateWithReceipt('CHQ261Z4AB2C');
      expect(out, isA<ReceiptActivationError>());
      expect(c.isEntitled, isFalse);
    });

    test('resubmitting the same receipt while active is idempotent',
        () async {
      final (store, now) = fixtures();
      var calls = 0;
      final c = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (_) async {
          calls += 1;
          return VerifyResult.receipt(_paidReceipt(), 10);
        },
      );
      await c.ensureLoaded();
      final first = await c.activateWithReceipt('CHQ261Z4AB2C')
          as ReceiptActivationSuccess;

      final again = await c.activateWithReceipt('CHQ261Z4AB2C')
          as ReceiptActivationSuccess;
      expect(again.alreadyActive, isTrue);
      expect(again.expiryUtc, first.expiryUtc); // no extra days
      expect(calls, 2); // the engine ran, but nothing was re-granted
    });

    test('a used receipt cannot grant a second month after expiry',
        () async {
      final (store, _) = fixtures();
      var now = start;
      Future<VerifyResult> ok(VerifyInput _) async =>
          VerifyResult.receipt(_paidReceipt(), 10);
      final c = _receiptController(store,
          now: () => now, publicKeyHex: await publicKeyHexFuture, verifier: ok);
      await c.ensureLoaded();
      await c.activateWithReceipt('CHQ261Z4AB2C');
      expect(c.isEntitled, isTrue);

      now = start.add(const Duration(days: 40)); // plan expired
      expect(c.isEntitled, isFalse);

      final replay = await c.activateWithReceipt('CHQ261Z4AB2C');
      expect(replay, isA<ReceiptActivationRejected>());
      expect((replay as ReceiptActivationRejected).message,
          contains('already been used'));

      // And the refusal persists across a restart.
      final c2 = _receiptController(store,
          now: () => now, publicKeyHex: await publicKeyHexFuture, verifier: ok);
      await c2.ensureLoaded();
      final replay2 = await c2.activateWithReceipt('CHQ261Z4AB2C');
      expect(replay2, isA<ReceiptActivationRejected>());
    });

    test('a second receipt stacks on top of the running plan', () async {
      final (store, _) = fixtures();
      var now = start;
      final c = _receiptController(
        store,
        now: () => now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (input) async => VerifyResult.receipt(
          _paidReceipt(
            invoice: input.reference,
            date: input.reference == 'CHQ261Z4AB2C'
                ? '20-09-2026 12:00:00'
                : '30-09-2026 12:00:00',
          ),
          10,
        ),
      );
      await c.ensureLoaded();
      await c.activateWithReceipt('CHQ261Z4AB2C');
      expect(c.expiresAt, start.add(const Duration(days: 31)));

      now = start.add(const Duration(days: 5)); // renew 5 days in
      final out = await c.activateWithReceipt('TBX9Q2KLM44');
      expect(out, isA<ReceiptActivationSuccess>());
      // Paid days stack on the current plan end, never on the clock.
      expect(
          c.expiresAt,
          start
              .add(const Duration(days: 31))
              .add(const Duration(days: 31)));
      expect(c.isEntitled, isTrue);
    });

    test('code months and receipt months stack', () async {
      final (store, now) = fixtures();
      final c = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (_) async => VerifyResult.receipt(_paidReceipt(), 10),
      );
      await c.ensureLoaded();
      await c.activate(
          await mintFor('device-1', expiry: DateTime.utc(2026, 12, 1)));
      await c.activateWithReceipt('CHQ261Z4AB2C');

      // Receipt month rides on top of the token's December expiry.
      expect(c.expiresAt, DateTime.utc(2026, 12, 1)
          .add(const Duration(days: 31)));
      expect(c.isEntitled, isTrue);
    });

    test('an empty paste is rejected without calling the engine', () async {
      final (store, now) = fixtures();
      var calls = 0;
      final c = _receiptController(
        store,
        now: now,
        publicKeyHex: await publicKeyHexFuture,
        verifier: (_) async {
          calls += 1;
          return VerifyResult.receipt(_paidReceipt(), 10);
        },
      );
      await c.ensureLoaded();
      final out = await c.activateWithReceipt('   ');
      expect(out, isA<ReceiptActivationRejected>());
      expect(calls, 0);
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
