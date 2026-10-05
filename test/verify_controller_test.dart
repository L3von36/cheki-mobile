import 'dart:async';
import 'dart:convert';

import 'package:mahtem/core/receipt_verify/extra_banks.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';
import 'package:mahtem/state/verify_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable verifier stub — mirrors the stylepos [VerifyResult] contract.
VerifyResult _receiptOk({String bank = 'cbe', double amount = 2450}) {
  return VerifyResult.receipt(
    ReceiptData(
      verified: true,
      bankCode: bank,
      bankName: 'Test Bank',
      reference: 'REF123',
      senderName: 'Alice',
      receiverName: 'Sami Shop',
      amount: amount,
      date: '2026-09-25 10:00:00',
    ),
    120,
  );
}

VerifyResult _notFound(String message) => VerifyResult.failed(
      VerifyFailure(VerifyErrorKind.notFound, message,
          tips: const ['Check the reference for typos.']),
      90,
    );

void main() {
  group('applyScan — link / QR resolution', () {
    test('CBE mbreciept link detects the bank and extracts the id', () {
      final c = VerifyController();
      c.applyScan('https://mbreciept.cbe.com.et/fHCx8QmLpZ1');
      expect(c.detectedBank?.id, 'cbe');
      expect(c.reference, 'fHCx8QmLpZ1');
      expect(c.canVerify, isTrue);
    });

    test('CBE legacy link maps to the dedicated guidance path', () {
      final c = VerifyController();
      c.applyScan('https://apps.cbe.com.et:100/?id=FT26140P01YB60536171');
      expect(c.detectedBank, isNull);
      expect(c.forcedBankId, 'cbe-legacy');
      expect(c.reference, 'FT26140P01YB');
      expect(c.accountNumber, '60536171');
      // The controller passes cbe-legacy through to the verifier.
      expect(c.canVerify, isTrue);
    });

    test('Telebirr receipt link detects the bank', () {
      final c = VerifyController();
      c.applyScan('https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C');
      expect(c.detectedBank?.id, 'telebirr');
      expect(c.reference, 'CHQ261Z4AB2C');
    });

    test('unknown link keeps the URL as reference without a bank', () {
      final c = VerifyController();
      c.applyScan('https://example.com/receipt/123');
      expect(c.detectedBank, isNull);
      expect(c.reference, 'https://example.com/receipt/123');
      expect(c.canVerify, isFalse); // needs a bank pick
    });

    test('plain reference needs a bank pick', () {
      final c = VerifyController();
      c.applyScan('FT26140P01YB');
      expect(c.detectedBank, isNull);
      expect(c.reference, 'FT26140P01YB');
      expect(c.canVerify, isFalse);
      c.selectBank(bankById('cbe'));
      expect(c.canVerify, isTrue);
    });
  });

  group('verify() through the stylepos verifier contract', () {
    test('receipt result lands in state and status becomes done', () async {
      late VerifyInput captured;
      final c = VerifyController(
        // CBE now routes to the extra verifier (transient-400 hardening).
        extraVerifyFn: (input) async {
          captured = input;
          return _receiptOk();
        },
      );
      c.applyScan('https://mbreciept.cbe.com.et/fHCx8QmLpZ1');
      final res = await c.verify();
      expect(res, isNotNull);
      expect(res!.ok, isTrue);
      expect(res.receipt!.amount, 2450);
      expect(c.status, VerifyStatus.done);
      expect(captured.bankId, 'cbe');
      expect(captured.reference, 'fHCx8QmLpZ1');
    });

    test('failure result carries the verifier message and tips', () async {
      final c = VerifyController(
        verifyFn: (_) async => _notFound('No receipt found.'),
      );
      c.selectBank(bankById('telebirr'));
      c.setReference('CHQ261Z4AB2C');
      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(res.failure!.message, 'No receipt found.');
      expect(res.failure!.tips, isNotEmpty);
    });

    test('thrown errors become a friendly unreadable failure', () async {
      final c = VerifyController(
        verifyFn: (_) async => throw Exception('boom'),
      );
      c.selectBank(bankById('telebirr'));
      c.setReference('CHQ261Z4AB2C');
      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.unreadable);
    });

    test('VerifyInput carries account / phone / qrData', () async {
      late VerifyInput captured;
      final c = VerifyController(
        verifyFn: (input) async {
          captured = input;
          return _receiptOk(bank: 'boa');
        },
      );
      c.selectBank(bankById('boa'));
      c.setReference('FT26140P01YB');
      c.setAccount('60536171');
      c.setPhone('0911000000'); // ignored for BOA, but must not crash
      await c.verify();
      expect(captured.bankId, 'boa');
      expect(captured.account, '60536171');
      expect(captured.qrData, isNull);
    });
  });

  group('canVerify rules (stylepos catalog)', () {
    test('CBE needs no account digits anymore', () {
      final c = VerifyController();
      c.selectBank(bankById('cbe'));
      c.setReference('fHCx8QmLpZ1');
      expect(c.canVerify, isTrue);
    });

    test('BOA typed reference needs the account suffix', () {
      final c = VerifyController();
      c.selectBank(bankById('boa'));
      c.setReference('FT26140P01YB');
      expect(c.canVerify, isFalse);
      c.setAccount('60536171');
      expect(c.canVerify, isTrue);
    });

    test('CBE Birr needs the payer phone number', () {
      final c = VerifyController();
      c.selectBank(bankById('cbebirr'));
      c.setReference('FT26140P01YB');
      expect(c.canVerify, isFalse);
      c.setPhone('0911000000');
      expect(c.canVerify, isTrue);
    });
  });

  group('stopVerify', () {
    test('an in-flight verification is discarded when stopped', () async {
      final gate = Completer<void>();
      VerifyResult? delivered;
      final c = VerifyController(
        verifyFn: (input) async {
          await gate.future;
          delivered = _receiptOk();
          return delivered!;
        },
      );
      c.selectBank(bankById('telebirr'));
      c.setReference('CHQ261Z4AB2C');

      final future = c.verify();
      await pumpEventQueue();
      expect(c.isVerifying, isTrue);

      c.stopVerify();
      expect(c.isVerifying, isFalse);

      gate.complete();
      final res = await future;
      expect(res, isNull); // abandoned — no result delivered
      expect(c.result, isNull);
      expect(c.status, VerifyStatus.idle);
      expect(delivered, isNotNull); // the fetch itself did finish
    });
  });

  group('reset / resetAll', () {
    test('resetAll clears the whole form', () {
      final c = VerifyController();
      c.applyScan('https://mbreciept.cbe.com.et/fHCx8QmLpZ1');
      c.resetAll();
      expect(c.reference, isEmpty);
      expect(c.detectedBank, isNull);
      expect(c.scannedQr, isNull);
      expect(c.status, VerifyStatus.idle);
    });

    test('editing the reference clears a failed attempt', () async {
      final c = VerifyController(
        verifyFn: (_) async => _notFound('No receipt found.'),
      );
      c.selectBank(bankById('telebirr'));
      c.setReference('CHQ261Z4AB2C');
      await c.verify();
      expect(c.status, VerifyStatus.done);
      c.setReference('CHQ261Z4AB2D');
      expect(c.status, VerifyStatus.idle);
      expect(c.result, isNull);
    });

    test('editing the reference after a scan drops the raw scan payload',
        () async {
      final c = VerifyController(verifyFn: (_) async => _receiptOk());
      c.selectBank(bankById('telebirr'));
      c.setReference('CHQ261Z4AB2C');
      // Simulate a scan having been applied, then the user editing.
      c.applyScan('CHQ261Z4AB2C');
      c.setReference('CHQ261Z4AB2C');
      expect(c.scannedQr, isNull);
    });
  });

  group('Telebirr scan — decoder junk-c strip + raw retry net', () {
    // Builds a Telebirr SuperApp QR payload: latin1 text → hex → base64,
    // the exact shape extractTelebirrInvoiceFromQr decodes.
    String telebirrQr(String innerText) {
      final blob = latin1.encode(innerText);
      final hexStr =
          blob.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      return base64Encode(utf8.encode(hexStr));
    }

    test('applyScan strips the junk-c the decoder appended inside the blob',
        () {
      final c = VerifyController();
      c.applyScan(telebirrQr('\x02\x9f\x00CHQ261Z4AB2c\x01\xffinvoice'));
      expect(c.detectedBank?.id, 'telebirr');
      expect(c.reference, 'CHQ261Z4AB2'); // trailing junk C gone
      expect(c.rawScannedReference, 'CHQ261Z4AB2C'); // net keeps the raw
      expect(c.canVerify, isTrue);
    });

    test('applyScan arms no net when nothing was stripped', () {
      final c = VerifyController();
      c.applyScan(telebirrQr('\x02\x9f\x00CHQ261Z4AB2\x01\xffinvoice'));
      expect(c.reference, 'CHQ261Z4AB2');
      expect(c.rawScannedReference, isNull);
    });

    test('editing the reference disarms the retry net', () {
      final c = VerifyController();
      c.applyScan(telebirrQr('\x02\x9f\x00CHQ261Z4AB2c\x01\xffinvoice'));
      expect(c.rawScannedReference, isNotNull);
      c.setReference('CHQ261Z4AB2');
      expect(c.rawScannedReference, isNull);
    });

    test('verify retries with the raw invoice when the stripped ref is '
        'not-found, and adopts it when it verifies', () async {
      final inputs = <VerifyInput>[];
      final c = VerifyController(
        verifyFn: (input) async {
          inputs.add(input);
          if (input.reference == 'CHQ261Z4AB2') {
            return _notFound('No receipt found.');
          }
          return _receiptOk(bank: 'telebirr');
        },
      );
      c.applyScan(telebirrQr('\x02\x9f\x00CHQ261Z4AB2c\x01\xffinvoice'));

      final res = await c.verify();
      expect(res!.ok, isTrue);
      expect(inputs, hasLength(2));
      expect(inputs[0].bankId, 'telebirr');
      expect(inputs[0].reference, 'CHQ261Z4AB2'); // cleaned first
      expect(inputs[1].reference, 'CHQ261Z4AB2C'); // raw retry
      // The form shows the value that actually verified.
      expect(c.reference, 'CHQ261Z4AB2C');
      expect(c.status, VerifyStatus.done);
    });

    test('a clean scan never triggers the retry net', () async {
      var calls = 0;
      final c = VerifyController(
        verifyFn: (input) async {
          calls++;
          return _notFound('No receipt found.');
        },
      );
      c.applyScan(telebirrQr('\x02\x9f\x00CHQ261Z4AB2\x01\xffinvoice'));
      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(calls, 1);
    });

    test('a failed raw retry keeps the first not-found result', () async {
      final inputs = <VerifyInput>[];
      final c = VerifyController(
        verifyFn: (input) async {
          inputs.add(input);
          return _notFound('No receipt found.');
        },
      );
      c.applyScan(telebirrQr('\x02\x9f\x00CHQ261Z4AB2c\x01\xffinvoice'));
      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
      expect(inputs, hasLength(2)); // retry happened but did not verify
      expect(c.reference, 'CHQ261Z4AB2'); // cleaned value stays shown
    });
  });

  group('telebirr bare-reference auto-detection (v1.11.0)', () {
    test('a typed telebirr-shaped number pre-selects Telebirr', () {
      final c = VerifyController();
      c.setReference('CHQ261Z4AB2C');
      expect(c.effectiveBank?.id, 'telebirr');
      expect(c.reference, 'CHQ261Z4AB2C');
      expect(c.canVerify, isTrue);
    });

    test('applyScan with a plain telebirr number does the same', () {
      final c = VerifyController();
      c.applyScan('DET261Z4AB2C');
      expect(c.detectedBank?.id, 'telebirr');
    });

    test('a manual bank choice always wins', () {
      final c = VerifyController();
      c.selectBank(bankById('cbe'));
      c.setReference('CHQ261Z4AB2C');
      expect(c.effectiveBank?.id, 'cbe');
    });

    test('non-telebirr shapes stay undetected', () {
      final c = VerifyController();
      c.setReference('123456789012');
      expect(c.effectiveBank, isNull);
    });

    test('URLs keep their own detection', () {
      final c = VerifyController();
      c.setReference('https://mbreciept.cbe.com.et/fHCx8QmLpZ1');
      expect(c.effectiveBank?.id, 'cbe');
    });
  });

  group('bare-reference shape auto-detection', () {
    test('an unambiguous shape pre-selects its bank', () {
      final mpesa = VerifyController()..setReference('SJ72HK3YZ9');
      expect(mpesa.effectiveBank?.id, 'mpesa');

      final cbe = VerifyController()..setReference('fHCx8QmLpZ1');
      expect(cbe.effectiveBank?.id, 'cbe');

      final dashen = VerifyController()..setReference('26010805472123');
      expect(dashen.effectiveBank?.id, 'dashen');

      final zemen = VerifyController()..setReference('ETTB123456789');
      expect(zemen.effectiveBank?.id, 'zemen');
    });

    test('ambiguous FT stays unselected and arms the candidate list', () {
      final c = VerifyController()..applyScan('FT26140P01YB');
      expect(c.detectedBank, isNull);
      expect(c.canVerify, isFalse); // the picker still decides
      expect(c.shapeCandidates, ['amhara', 'boa', 'cbebirr']);
    });

    test('link / QR references carry no shape candidates', () {
      final c = VerifyController()
        ..applyScan('https://mbreciept.cbe.com.et/fHCx8QmLpZ1');
      expect(c.detectedBank?.id, 'cbe');
      expect(c.shapeCandidates, isEmpty); // the link is authoritative
    });

    test('candidates follow the reference through edits and resets', () {
      final c = VerifyController()..setReference('SJ72HK3YZ9');
      expect(c.shapeCandidates, ['mpesa']);
      c.setReference('REFERENCE99');
      expect(c.shapeCandidates, isEmpty);
      c.setReference('FT26140P01YB');
      expect(c.shapeCandidates, ['amhara', 'boa', 'cbebirr']);
      c.resetAll();
      expect(c.shapeCandidates, isEmpty);
    });
  });

  group('wrong-bank retry net', () {
    test('a not-found on one FT candidate tries the others and adopts the '
        'one that verifies', () async {
      final engineInputs = <VerifyInput>[];
      final extraInputs = <VerifyInput>[];
      final c = VerifyController(
        verifyFn: (input) async {
          engineInputs.add(input);
          return _notFound('Receipt not found.');
        },
        extraVerifyFn: (input) async {
          extraInputs.add(input);
          return input.bankId == 'amhara'
              ? _receiptOk(bank: 'amhara')
              : _notFound('Receipt not found.');
        },
      );
      c.selectBank(bankById('boa'));
      c.setReference('FT26140P01YB');
      c.setAccount('60536171');

      final res = await c.verify();
      expect(res!.ok, isTrue);
      // Primary BOA asked first, Amhara (the first viable candidate)
      // second — CBE Birr never asked (it needs a phone we never had).
      expect(engineInputs.map((i) => i.bankId), ['boa']);
      expect(extraInputs.map((i) => i.bankId), ['amhara']);
      // The form now shows the bank that actually verified.
      expect(c.effectiveBank?.id, 'amhara');
      expect(c.manualBank?.id, 'amhara');
      expect(c.status, VerifyStatus.done);
    });

    test('when no candidate verifies, the PRIMARY failure message is kept '
        'and skipped candidates are named in the tips', () async {
      final asked = <String>[];
      final c = VerifyController(
        verifyFn: (input) async {
          asked.add(input.bankId);
          return _notFound('should not run');
        },
        // The primary here IS Amhara — an extra bank — so it answers
        // through this fn; no other candidate is viable without fields.
        extraVerifyFn: (input) async {
          asked.add(input.bankId);
          return _notFound('Receipt not found.');
        },
      );
      c.selectBank(bankByIdAll('amhara'));
      c.setReference('FT26140P01YB'); // BOA + CBE Birr lack their fields

      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(asked, ['amhara']); // every other candidate needs a field
      expect(res.failure!.message, 'Receipt not found.');
      // The skipped banks are the user's next move.
      final tips = res.failure!.tips.join(' ');
      expect(tips, contains('Bank of Abyssinia'));
      expect(tips, contains('CBE Birr'));
    });

    test('a non-not-failure does not trigger the net', () async {
      final asked = <String>[];
      final c = VerifyController(
        verifyFn: (input) async {
          asked.add(input.bankId);
          return VerifyResult.failed(
            const VerifyFailure(
                VerifyErrorKind.network, 'Check your connection.'),
            5,
          );
        },
        extraVerifyFn: (input) async {
          asked.add(input.bankId);
          return _notFound('should not run');
        },
      );
      c.selectBank(bankById('boa'));
      c.setReference('FT26140P01YB');
      c.setAccount('60536171');

      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.network);
      expect(asked, ['boa']); // network errors keep their own message
    });

    test('single-candidate shapes never retry — the only candidate is the '
        'bank already asked', () async {
      var calls = 0;
      final c = VerifyController(
        verifyFn: (input) async {
          calls++;
          return _notFound('Receipt not found.');
        },
        extraVerifyFn: (input) async {
          calls++;
          return _notFound('Receipt not found.');
        },
      );
      // SJ72… auto-detects M-Pesa — its shape has no other owner.
      c.applyScan('SJ72HK3YZ9');
      expect(c.effectiveBank?.id, 'mpesa');

      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(calls, 1);
      // No shape tip: there is no other bank this shape could belong to.
      expect(
        res.failure!.tips.any((t) => t.contains('actually from')),
        isFalse,
      );
    });

    test('a broken alternative never masks the primary answer', () async {
      final c = VerifyController(
        verifyFn: (_) async => _notFound('Receipt not found.'),
        extraVerifyFn: (_) async => throw Exception('boom'),
      );
      c.selectBank(bankById('boa'));
      c.setReference('FT26140P01YB');
      c.setAccount('60536171');

      final res = await c.verify();
      expect(res!.ok, isFalse);
      expect(res.failure!.message, 'Receipt not found.');
      expect(res.failure!.kind, VerifyErrorKind.notFound);
    });

    test('an abandoned run delivers nothing even if a candidate answers',
        () async {
      final gate = Completer<void>();
      final c = VerifyController(
        // Primary (Amhara) fails fast; the retry net reaches BOA, which
        // hangs on the gate until the run is abandoned.
        verifyFn: (_) async {
          await gate.future;
          return _receiptOk(bank: 'boa');
        },
        extraVerifyFn: (_) async => _notFound('Receipt not found.'),
      );
      c.selectBank(bankByIdAll('amhara'));
      c.setReference('FT26140P01YB');
      c.setAccount('60536171'); // makes BOA viable for the retry net

      final future = c.verify();
      await pumpEventQueue();
      expect(c.isVerifying, isTrue);
      c.stopVerify();

      gate.complete();
      final res = await future;
      expect(res, isNull); // the candidate's answer is discarded
      expect(c.result, isNull);
      expect(c.status, VerifyStatus.idle);
    });
  });

  group('applyAdvisoryNote (v1.11.0)', () {
    test('merges into a successful result, appending to existing notes', () {
      final c = VerifyController(verifyFn: (input) async => _receiptOk());
      c.setReference('REF123');
      c.selectBank(bankById('cbe'));
      // Simulate a finished run.
      c.result = _receiptOk();
      c.applyAdvisoryNote('stale note');
      expect(c.result!.receipt!.note, 'stale note');
      c.applyAdvisoryNote('dup note');
      expect(c.result!.receipt!.note, 'stale note · dup note');
    });

    test('no-op on failures', () {
      final c = VerifyController();
      c.result = _notFound('No receipt found.');
      c.applyAdvisoryNote('stale note');
      expect(c.result!.receipt, isNull);
    });
  });
}
