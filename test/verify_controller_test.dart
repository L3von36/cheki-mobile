import 'dart:convert';

import 'package:cheki_mobile/core/banks_registry.dart';
import 'package:cheki_mobile/core/cheki_client.dart';
import 'package:cheki_mobile/core/models.dart';
import 'package:cheki_mobile/state/verify_controller.dart';
import 'package:cheki_mobile/util/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('VerifyController', () {
    VerifyController makeController(http.Client mock) =>
        VerifyController(client: ChekiClient(client: mock));

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

    test('manual bank selection overrides auto-detect', () {
      final controller = VerifyController();
      controller.setReference('DET8FJGUJ4');
      expect(controller.effectiveBank?.id, 'telebirr');

      controller.selectBank(bankById('dashen'));
      expect(controller.effectiveBank?.id, 'dashen');
      expect(controller.canVerify, isTrue);
      controller.dispose();
    });

    test('verify() surfaces friendly errors and sets error status', () async {
      final controller = makeController(
        MockClient((request) async =>
            http.Response(jsonEncode({'success': false, 'error': 'nope'}), 404)),
      );
      controller.applyDetection(
        const BankDetection(bank: 'telebirr', reference: 'DET8FJGUJ4'),
      );
      final result = await controller.verify();
      expect(result, isNull);
      expect(controller.status, VerifyStatus.error);
      expect(controller.errorMessage, isNotNull);
      controller.dispose();
    });

    test('verify() returns a successful result end-to-end', () async {
      final controller = makeController(
        MockClient((request) async => http.Response(
              jsonEncode({
                'success': true,
                'verified': true,
                'bank': 'telebirr',
                'reference': 'DET8FJGUJ4',
                'amount': 1500,
                'currency': 'ETB',
                'senderName': 'Test Sender',
              }),
              200,
            )),
      );
      controller.applyDetection(
        const BankDetection(bank: 'telebirr', reference: 'DET8FJGUJ4'),
      );
      final result = await controller.verify();
      expect(result, isNotNull);
      expect(result!.isVerified, isTrue);
      expect(controller.status, VerifyStatus.done);
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
