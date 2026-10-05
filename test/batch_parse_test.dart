import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/batch_parse.dart';
import 'package:mahtem/core/receipt_verify/models.dart';

import 'fixtures/boa_qr.dart';

BankInfo? _bank(String id) => bankById(id);

void main() {
  group('parseBatchLines — plain references', () {
    test('splits lines, trims, drops empties, takes the chosen bank', () {
      final rows = parseBatchLines(
        'CHQ261Z4AB2C\n\n  \nFT26140P01YB\n',
        bank: _bank('telebirr'),
      );
      expect(rows, hasLength(2));
      expect(rows.every((r) => !r.isSkipped), isTrue);
      expect(rows.every((r) => r.bankId == 'telebirr'), isTrue);
      expect(rows[0].effectiveReference, 'CHQ261Z4AB2C');
      expect(rows[1].effectiveReference, 'FT26140P01YB');
    });

    test('strips list numbering and bullets', () {
      final rows = parseBatchLines(
        '1. CHQ261Z4AB2C\n2) DET261Z4AB2D\n- FT26140P01YB\n• SJ72HK3YZ9\n',
        bank: _bank('telebirr'),
      );
      expect(rows, hasLength(4));
      expect(rows[0].input, 'CHQ261Z4AB2C');
      expect(rows[1].input, 'DET261Z4AB2D');
      expect(rows[2].input, 'FT26140P01YB');
      expect(rows[3].input, 'SJ72HK3YZ9');
    });

    test('in-batch duplicates collapse (case-insensitive), only the '
        'first is charged', () {
      final rows = parseBatchLines(
        'CHQ261Z4AB2C\nchq261z4ab2c\nCHQ261Z4AB2C\n',
        bank: _bank('telebirr'),
      );
      expect(rows, hasLength(3));
      expect(rows[0].isSkipped, isFalse);
      expect(rows[1].skipReason, BatchSkipReason.duplicate);
      expect(rows[2].skipReason, BatchSkipReason.duplicate);
      expect(countChargeable(rows), 1);
    });

    test('a bare unambiguous shape auto-detects when no bank is chosen, '
        'but a chosen bank always wins', () {
      final auto = parseBatchLines('CHQ261Z4AB2C');
      expect(auto.single.bankId, 'telebirr');

      final shaped = parseBatchLines('ETTB123456789');
      expect(shaped.single.bankId, 'zemen');

      final forced = parseBatchLines(
        'CHQ261Z4AB2C',
        bank: _bank('mpesa'),
      );
      expect(forced.single.bankId, 'mpesa');
    });

    test('bare references without a bank need one — unless their shape '
        'belongs to exactly one bank', () {
      // FT is genuinely ambiguous (Amhara / BOA / CBE Birr) and
      // REFERENCE99 matches no known shape — both need a bank pick.
      final shapeless = parseBatchLines('FT26140P01YB\nREFERENCE99');
      expect(countNeedingBank(shapeless), 2);

      // An M-Pesa transaction number is unambiguous — auto-detected.
      final rows = parseBatchLines('FT26140P01YB\nSJ72HK3YZ9');
      expect(countNeedingBank(rows), 1);
      expect(rows[1].bankId, 'mpesa');
    });
  });

  group('parseBatchLines — links and QR payloads', () {
    test('CBE link carries its own bank and ignores the chosen one', () {
      final rows = parseBatchLines(
        'https://mbreciept.cbe.com.et/AB12CD34\nCHQ261Z4AB2C',
        bank: _bank('telebirr'),
      );
      expect(rows[0].bankId, 'cbe');
      expect(rows[0].reference, 'AB12CD34');
      expect(rows[0].isSkipped, isFalse);
      expect(rows[1].bankId, 'telebirr'); // plain line still batch bank
    });

    test('a link embedded in prose still detects (Wegagen QR shape)', () {
      final rows = parseBatchLines(
        'Your receipt https://transinfo.wegagenbanksc.com.et:8183/'
        '?id=FT26140P01YB thanks',
      );
      expect(rows.single.bankId, 'wegagen');
      expect(rows.single.reference, 'FT26140P01YB');
    });

    test('unknown link is skipped, never charged', () {
      final rows = parseBatchLines('https://example.com/receipt/123');
      expect(rows.single.skipReason, BatchSkipReason.unknownLink);
    });

    test('BOA encrypted slip QR pasted as a line → scannedQr row', () {
      final qr = base64Encode(encryptBoaQrForTests(
          '1000****2211,ABEBE KEbede,1500,FT26140P01YB,18-09-2026 10:11,'
          '1000****8348,SAMI CLOTHING'));
      final rows = parseBatchLines('$qr\nCHQ261Z4AB2C',
          bank: _bank('telebirr'));
      expect(rows[0].bankId, 'boa');
      expect(rows[0].scannedQr, qr);
      expect(rows[0].isSkipped, isFalse);
      expect(countNeedingBank(rows), 0); // QR rows never need a bank
    });

    test('telebirr SuperApp QR blob decodes to the invoice', () {
      // latin1("ok CHQ261Z4AB2C end") → hex → base64.
      const invoice = 'CHQ261Z4AB2C';
      final text = 'ok $invoice end';
      final hex = latin1.encode(text).map((b) {
        final s = b.toRadixString(16);
        return s.length == 1 ? '0$s' : s;
      }).join();
      final blob = base64Encode(utf8.encode(hex));

      final rows = parseBatchLines(blob);
      expect(rows.single.bankId, 'telebirr');
      expect(rows.single.effectiveReference, invoice);
    });

    test('CBE printed FT number against CBE is skipped; the same shape '
        'against CBE Birr is NOT', () {
      final cbe = parseBatchLines('FT2614977L8S', bank: _bank('cbe'));
      expect(cbe.single.skipReason, BatchSkipReason.cbePrinted);

      final cbebirr = parseBatchLines('FT26140P01YB', bank: _bank('cbebirr'));
      expect(cbebirr.single.isSkipped, isFalse);
      expect(cbebirr.single.bankId, 'cbebirr');
    });

    test('CBE-legacy retired link is skipped', () {
      // Old shape: apps.cbe.com.et/?id=FT{ref}{last8} — decommissioned;
      // the batch skips it instead of burning a doomed check.
      final rows = parseBatchLines(
        'https://apps.cbe.com.et:100/?id=FT26140P01YB12345678',
      );
      expect(rows.single.skipReason, BatchSkipReason.cbePrinted);
    });
  });

  group('parseBatchLines — limits', () {
    test('over the cap the extra lines are skipped, not charged', () {
      final buf = StringBuffer();
      for (var i = 0; i < kBatchMaxLines + 5; i++) {
        buf.writeln('CHQ261Z4AB${i.toString().padLeft(2, '0')}');
      }
      final rows = parseBatchLines(buf.toString(), bank: _bank('telebirr'));
      expect(rows, hasLength(kBatchMaxLines + 5));
      expect(countChargeable(rows), kBatchMaxLines);
      expect(
        rows.skip(kBatchMaxLines).map((r) => r.skipReason),
        everyElement(BatchSkipReason.overLimit),
      );
    });

    test('countChargeable / countNeedingBank totals', () {
      final rows = parseBatchLines(
        'CHQ261Z4AB2C\n'
        'CHQ261Z4AB2C\n' // dup
        'https://example.com/x\n' // unknown link
        'FT26140P01YB', // plain, needs bank
      );
      expect(countChargeable(rows), 2);
      expect(countNeedingBank(rows), 1);
    });
  });

  group('parseBatchLines — Amhara bare JSON', () {
    test('Amhara QR payload (bare JSON) detects per line', () {
      final rows = parseBatchLines(
        '{"transactionId":"FT2614ABC123","amount":500}',
        bank: _bank('telebirr'),
      );
      expect(rows.single.bankId, 'amhara');
      expect(rows.single.effectiveReference, 'FT2614ABC123');
    });
  });
}
