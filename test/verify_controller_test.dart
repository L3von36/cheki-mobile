import 'dart:async';
import 'dart:convert';

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
        verifyFn: (input) async {
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
      c.selectBank(bankById('cbe'));
      c.setReference('fHCx8QmLpZ1');

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
}
