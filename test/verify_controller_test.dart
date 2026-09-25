import 'dart:async';
import 'dart:convert';

import 'package:mahtem/core/banks_registry.dart';
import 'package:mahtem/core/models.dart';
import 'package:mahtem/core/native/verifier.dart';
import 'package:mahtem/state/verify_controller.dart';
import 'package:mahtem/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable engine stub for controller tests.
class FakeEngine implements VerifyEngine {
  VerifyResult? nextResult;
  Object? nextError;
  String? lastBank;
  String? lastReference;
  String? lastAccount;

  /// Optional scripted results consumed in order before [nextResult].
  final List<VerifyResult> script = [];
  final List<String> calls = [];

  @override
  Future<VerifyResult> verify({
    required String bank,
    required String reference,
    String? accountNumber,
    String? phoneNumber,
  }) async {
    calls.add(reference);
    lastBank = bank;
    lastReference = reference;
    lastAccount = accountNumber;
    if (nextError != null) throw nextError!;
    if (script.isNotEmpty) return script.removeAt(0);
    return nextResult ??
        VerifyResult(success: true, verified: true, bank: bank, reference: reference);
  }
}

/// Engine whose calls suspend until explicitly completed — lets tests
/// hold a verification in flight to exercise stopVerify().
class GatedEngine implements VerifyEngine {
  final List<String> calls = [];
  final List<Completer<VerifyResult>> _pending = [];

  int get pendingCount => _pending.length;

  void completeNext(VerifyResult result) =>
      _pending.removeAt(0).complete(result);

  void completeAll(VerifyResult result) {
    for (final c in _pending) {
      c.complete(result);
    }
    _pending.clear();
  }

  @override
  Future<VerifyResult> verify({
    required String bank,
    required String reference,
    String? accountNumber,
    String? phoneNumber,
  }) {
    calls.add(reference);
    final completer = Completer<VerifyResult>();
    _pending.add(completer);
    return completer.future;
  }
}

void main() {
  group('VerifyController', () {
    test('auto-detects bank while typing a reference', () {
      final controller = VerifyController();
      controller.setReference('FT26140P01YB');
      expect(controller.detectedBank?.id, 'cbe');
      expect(controller.canVerify, isFalse); // CBE needs account digits

      controller.setAccount('60536171');
      expect(controller.canVerify, isTrue);
      controller.dispose();
    });

    test('cbe-new QR ids map to the CBE bank with usingCbeNew flag', () {
      final controller = VerifyController();
      controller.applyDetection(
        const BankDetection(bank: 'cbe-new', reference: 'a1b2c3d4e5f6'),
      );
      expect(controller.effectiveBank?.id, 'cbe');
      expect(controller.usingCbeNew, isTrue);
      expect(controller.canVerify, isTrue); // no account needed for new API
      controller.dispose();
    });

    test('applyDetection fills account from URL payload', () {
      final controller = VerifyController();
      controller.applyDetection(
        const BankDetection(
          bank: 'cbe',
          reference: 'FT26140P01YB',
          accountNumber: '60536171',
        ),
      );
      expect(controller.reference, 'FT26140P01YB');
      expect(controller.accountNumber, '60536171');
      expect(controller.effectiveBank?.id, 'cbe');
      controller.dispose();
    });

    test('applyDetection keeps bank open for generic QR payloads', () {
      final controller = VerifyController();
      controller.applyDetection(
        const BankDetection(bank: null, reference: 'PAYOUT99231X'),
      );
      expect(controller.reference, 'PAYOUT99231X');
      expect(controller.effectiveBank, isNull);
      expect(controller.canVerify, isFalse);

      // Picking a bank manually completes the form.
      controller.selectBank(bankById('mpesa'));
      expect(controller.canVerify, isTrue);
      controller.dispose();
    });

    test('manual bank selection overrides auto-detect', () {
      final controller = VerifyController();
      controller.setReference('DET8FJGUJ4');
      expect(controller.effectiveBank?.id, 'telebirr');

      controller.selectBank(bankById('dashen'));
      expect(controller.effectiveBank?.id, 'dashen');
      expect(controller.canVerify, isTrue);
      controller.dispose();
    });

    test('verify() passes the cbe-new id to the engine', () async {
      final engine = FakeEngine();
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(bank: 'cbe-new', reference: 'a1b2c3d4e5f6'),
      );
      await controller.verify();
      expect(engine.lastBank, 'cbe-new');
      expect(engine.lastReference, 'a1b2c3d4e5f6');
      expect(engine.lastAccount, isNull);
      controller.dispose();
    });

    test('verify() surfaces engine failures as a failed result', () async {
      final engine = FakeEngine()
        ..nextResult = const VerifyResult(
          success: false,
          verified: false,
          bank: 'telebirr',
          reference: 'DET8FJGUJ4',
          error: 'No connection. Check your internet and try again.',
        );
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(bank: 'telebirr', reference: 'DET8FJGUJ4'),
      );
      final result = await controller.verify();
      // Failures are first-class results — no silent errors.
      expect(result, isNotNull);
      expect(result!.isVerified, isFalse);
      expect(result.error, isNotNull);
      expect(controller.status, VerifyStatus.done);
      controller.dispose();
    });

    test('verify() survives engine exceptions', () async {
      final engine = FakeEngine()..nextError = Exception('boom');
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(bank: 'telebirr', reference: 'DET8FJGUJ4'),
      );
      final result = await controller.verify();
      expect(result, isNotNull);
      expect(result!.isVerified, isFalse);
      expect(result.error, contains('Something went wrong'));
      expect(controller.status, VerifyStatus.done);
      controller.dispose();
    });

    test('verify() retries with the raw scan when the cleaned reference is '
        'not-found', () async {
      final engine = FakeEngine()
        ..script.addAll([
          // First attempt: the sanitized reference comes back not-found.
          const VerifyResult(
            success: true,
            verified: false,
            bank: 'telebirr',
            reference: 'DET8FJGUJ4',
            reason: 'Receipt not found. Double-check the reference number.',
          ),
          // Retry with the untouched scan: the receipt exists.
          const VerifyResult(
            success: true,
            verified: true,
            bank: 'telebirr',
            reference: 'DET8FJGUJ4c',
          ),
        ]);
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(
          bank: 'telebirr',
          reference: 'DET8FJGUJ4',
          rawPayload: 'DET8FJGUJ4c',
        ),
      );
      final result = await controller.verify();
      expect(engine.calls, ['DET8FJGUJ4', 'DET8FJGUJ4c']);
      expect(result!.isVerified, isTrue);
      expect(controller.reference, 'DET8FJGUJ4c'); // shows what verified
      controller.dispose();
    });

    test('verify() does not retry when there is no raw scan or it matches',
        () async {
      final engine = FakeEngine()
        ..nextResult = const VerifyResult(
          success: true,
          verified: false,
          bank: 'telebirr',
          reference: 'DET8FJGUJ4',
        );
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(bank: 'telebirr', reference: 'DET8FJGUJ4'),
      );
      final result = await controller.verify();
      expect(engine.calls, ['DET8FJGUJ4']); // single attempt
      expect(result!.isVerified, isFalse);

      // With a raw payload identical to the reference, still one attempt.
      controller.applyDetection(
        const BankDetection(
          bank: 'telebirr',
          reference: 'DET8FJGUJ4',
          rawPayload: 'DET8FJGUJ4',
        ),
      );
      await controller.verify();
      expect(engine.calls, ['DET8FJGUJ4', 'DET8FJGUJ4']);
      controller.dispose();
    });

    test('verify() keeps the first result when the retry is also not-found',
        () async {
      final engine = FakeEngine()
        ..script.addAll([
          const VerifyResult(
            success: true,
            verified: false,
            bank: 'telebirr',
            reference: 'DET8FJGUJ4',
            reason: 'Receipt not found.',
          ),
          const VerifyResult(
            success: true,
            verified: false,
            bank: 'telebirr',
            reference: 'DET8FJGUJ4c',
            reason: 'Receipt not found.',
          ),
        ]);
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(
          bank: 'telebirr',
          reference: 'DET8FJGUJ4',
          rawPayload: 'DET8FJGUJ4c',
        ),
      );
      final result = await controller.verify();
      expect(engine.calls.length, 2);
      expect(result!.isVerified, isFalse);
      expect(controller.reference, 'DET8FJGUJ4'); // unchanged
      controller.dispose();
    });

    test('editing the reference clears the raw scan retry value', () {
      final controller = VerifyController();
      controller.applyDetection(
        const BankDetection(
          bank: 'telebirr',
          reference: 'DET8FJGUJ4',
          rawPayload: 'DET8FJGUJ4c',
        ),
      );
      expect(controller.rawScannedReference, 'DET8FJGUJ4c');
      controller.setReference('DET8FJGUJ4X');
      expect(controller.rawScannedReference, isNull);
      controller.dispose();
    });

    test('a stripped telebirr blob invoice retries with the raw scan',
        () async {
      // The registry strips decoder junk ('c') swallowed into the decoded
      // invoice; when the stripped invoice is not found, the untouched QR
      // blob is retried and its unstripped invoice still verifies.
      String blobOf(String text) => base64Encode(utf8.encode(latin1
          .encode(text)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()));
      final blob = blobOf('\x02\x9f\x00DET8FJGUJ4C\x01\xff');

      final engine = FakeEngine()
        ..script.addAll([
          const VerifyResult(
            success: true,
            verified: false,
            bank: 'telebirr',
            reference: 'DET8FJGUJ4',
            reason: 'Receipt not found. Double-check the reference number.',
          ),
          VerifyResult(
            success: true,
            verified: true,
            bank: 'telebirr',
            reference: 'DET8FJGUJ4C',
          ),
        ]);
      final controller = VerifyController(engine: engine);
      controller.applyDetection(BankDetection(
        bank: 'telebirr',
        reference: 'DET8FJGUJ4',
        rawPayload: blob,
      ));
      final result = await controller.verify();
      expect(engine.calls, ['DET8FJGUJ4', blob]);
      expect(result!.isVerified, isTrue);
      expect(controller.reference, blob); // shows the value that verified
      controller.dispose();
    });

    test('resetAll clears everything', () {
      final controller = VerifyController();
      controller.setReference('FT26140P01YB');
      controller.setAccount('60536171');
      controller.resetAll();
      expect(controller.reference, '');
      expect(controller.accountNumber, '');
      expect(controller.effectiveBank, isNull);
      expect(controller.status, VerifyStatus.idle);
      controller.dispose();
    });
  });

  group('VerifyController.stopVerify', () {
    test('aborts an in-flight check and discards the late result', () async {
      final engine = GatedEngine();
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(bank: 'telebirr', reference: 'DET8FJGUJ4'),
      );

      final inFlight = controller.verify();
      expect(controller.status, VerifyStatus.verifying);

      controller.stopVerify();
      expect(controller.status, VerifyStatus.idle);

      // The engine eventually answers — the abandoned run ignores it.
      engine.completeNext(const VerifyResult(
        success: true,
        verified: true,
        bank: 'telebirr',
        reference: 'DET8FJGUJ4',
      ));
      expect(await inFlight, isNull);
      expect(controller.status, VerifyStatus.idle);
      expect(controller.result, isNull);
      controller.dispose();
    });

    test('is a no-op when nothing is running', () {
      final controller = VerifyController(engine: GatedEngine());
      controller.stopVerify();
      expect(controller.status, VerifyStatus.idle);
      controller.dispose();
    });

    test('a verification can start again after a stop', () async {
      final engine = GatedEngine();
      final controller = VerifyController(engine: engine);
      controller.applyDetection(
        const BankDetection(bank: 'telebirr', reference: 'DET8FJGUJ4'),
      );

      final stopped = controller.verify();
      controller.stopVerify();
      engine.completeNext(const VerifyResult(
        success: true,
        verified: true,
        bank: 'telebirr',
        reference: 'DET8FJGUJ4',
      ));
      expect(await stopped, isNull);

      final restarted = controller.verify();
      expect(controller.status, VerifyStatus.verifying);
      engine.completeNext(const VerifyResult(
        success: true,
        verified: true,
        bank: 'telebirr',
        reference: 'DET8FJGUJ4',
      ));
      final result = await restarted;
      expect(result!.isVerified, isTrue);
      expect(controller.status, VerifyStatus.done);
      expect(controller.result!.isVerified, isTrue);
      controller.dispose();
    });

    test('stopping during the raw-scan retry keeps the form idle', () async {
      final engine = GatedEngine();
      final controller = VerifyController(engine: engine);
      controller.applyDetection(const BankDetection(
        bank: 'telebirr',
        reference: 'DET8FJGUJ4',
        rawPayload: 'DET8FJGUJ4c',
      ));

      final inFlight = controller.verify();
      // First attempt comes back not-found, which fires the retry net.
      engine.completeNext(const VerifyResult(
        success: true,
        verified: false,
        bank: 'telebirr',
        reference: 'DET8FJGUJ4',
      ));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls.length, 2);

      controller.stopVerify();
      engine.completeNext(const VerifyResult(
        success: true,
        verified: true,
        bank: 'telebirr',
        reference: 'DET8FJGUJ4c',
      ));
      expect(await inFlight, isNull);
      expect(controller.status, VerifyStatus.idle);
      expect(controller.result, isNull);
      expect(controller.reference, 'DET8FJGUJ4'); // raw not adopted
      controller.dispose();
    });
  });

  group('format helpers', () {
    test('formatAmount renders ETB with thousands separators', () {
      expect(formatAmount(20000, 'ETB'), 'ETB 20,000.00');
      expect(formatAmount(null, 'ETB'), '—');
    });

    test('formatReceiptDate parses M/D/YYYY h:mm:ss AM', () {
      expect(
        formatReceiptDate('5/20/2026, 7:29:00 PM'),
        '20 May 2026 · 7:29 PM',
      );
      expect(formatReceiptDate('2026-05-20 19:29:00'), contains('2026'));
      expect(formatReceiptDate(null), '—');
    });
  });
}
