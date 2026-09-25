import 'package:cheki_mobile/core/banks_registry.dart';
import 'package:cheki_mobile/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bank registry', () {
    test('has 10 live banks with unique ids', () {
      expect(kChekiBanks.length, 10);
      final ids = kChekiBanks.map((b) => b.id).toSet();
      expect(ids.length, 10);
    });

    test('CBE requires last 8 account digits', () {
      final cbe = bankById('cbe')!;
      expect(cbe.requiresAccount, isTrue);
      expect(cbe.accountDigits, 8);
    });

    test('BOA requires last 5 account digits', () {
      final boa = bankById('boa')!;
      expect(boa.accountDigits, 5);
    });

    test('CBE Birr requires phone', () {
      expect(bankById('cbebirr')!.requiresPhone, isTrue);
    });

    test('telebirr and mpesa are geo-blocked', () {
      expect(bankById('telebirr')!.geoBlocked, isTrue);
      expect(bankById('mpesa')!.geoBlocked, isTrue);
    });
  });

  group('detectBankFromReference', () {
    test('detects CBE FT references', () {
      final d = detectBankFromReference('FT26140P01YB');
      expect(d, isNotNull);
      expect(d!.bank.id, 'cbe');
    });

    test('detects Telebirr DET references', () {
      final d = detectBankFromReference('DET8FJGUJ4');
      expect(d, isNotNull);
      expect(d!.bank.id, 'telebirr');
    });

    test('detects Telebirr CHQ references', () {
      final d = detectBankFromReference('CHQ0FJ403O');
      expect(d, isNotNull);
      expect(d!.bank.id, 'telebirr');
    });

    test('detects eBirr tenant/token', () {
      final d = detectBankFromReference('nib/abc123def');
      expect(d, isNotNull);
      expect(d!.bank.id, 'ebirr');
    });

    test('detects eBirr receipt URL as reference', () {
      final d = detectBankFromReference('https://receipt.ebirr.com/nib/tok123');
      expect(d, isNotNull);
      expect(d!.bank.id, 'ebirr');
    });

    test('returns null for unknown references', () {
      expect(detectBankFromReference('XY12345'), isNull);
      expect(detectBankFromReference(''), isNull);
    });
  });

  group('detectBankFromUrl', () {
    test('parses CBE legacy URL with account suffix', () {
      final d = detectBankFromUrl(
        'https://apps.cbe.com.et:100/?id=FT26140P01YB60536171',
      );
      expect(d, isNotNull);
      expect(d!.bank, 'cbe');
      expect(d.reference, 'FT26140P01YB');
      expect(d.accountNumber, '60536171');
    });

    test('parses CBE new receipt URL', () {
      final d = detectBankFromUrl('https://mbreciept.cbe.com.et/abc123def456');
      expect(d, isNotNull);
      expect(d!.bank, 'cbe-new');
      expect(d.reference, 'abc123def456');
    });

    test('parses Telebirr receipt URL', () {
      final d = detectBankFromUrl(
        'https://transactioninfo.ethiotelecom.et/receipt/DET8FJGUJ4',
      );
      expect(d!.bank, 'telebirr');
      expect(d.reference, 'DET8FJGUJ4');
    });

    test('parses BOA trx URL', () {
      final d = detectBankFromUrl(
        'https://cs.bankofabyssinia.com/slip/?trx=AB12345678',
      );
      expect(d!.bank, 'boa');
      expect(d.reference, 'AB12345678');
    });

    test('parses BOA id URL with suffix', () {
      final d = detectBankFromUrl(
        'https://cs.bankofabyssinia.com/api/onlineSlip/getDetails/?id=AB1234567812345',
      );
      expect(d!.bank, 'boa');
      expect(d.reference, 'AB12345678');
      expect(d.accountNumber, '12345');
    });

    test('parses Dashen receipt URL', () {
      final d = detectBankFromUrl(
        'https://receipt.dashensuperapp.com/receipt/D31OBTI251720001',
      );
      expect(d!.bank, 'dashen');
      expect(d.reference, 'D31OBTI251720001');
    });

    test('parses Dashen PDF filename URL', () {
      final d = detectBankFromUrl(
        'https://api.dashensuperapp.com/receipts/Within-Dashen-Transfer-REF123.pdf',
      );
      expect(d!.bank, 'dashen');
      expect(d.reference, 'REF123');
    });

    test('parses Awash share URL', () {
      final d = detectBankFromUrl(
        'https://awashpay.awashbank.com:8225/-2KDL95Z0NR-4U61O6',
      );
      expect(d!.bank, 'awash');
      expect(d.reference, '2KDL95Z0NR-4U61O6');
    });

    test('parses Zemen share URL', () {
      final d = detectBankFromUrl(
        'https://share.zemenbank.com/rt/ZM12345678/pdf',
      );
      expect(d!.bank, 'zemen');
      expect(d.reference, 'ZM12345678');
    });

    test('parses M-Pesa trxNo URL', () {
      final d = detectBankFromUrl(
        'https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=SE12345678',
      );
      expect(d!.bank, 'mpesa');
      expect(d.reference, 'SE12345678');
    });

    test('parses eBirr receipt URL', () {
      final d = detectBankFromUrl('https://receipt.ebirr.com/nib/tok123abc');
      expect(d!.bank, 'ebirr');
      expect(d.reference, 'nib/tok123abc');
    });

    test('returns null for foreign URLs', () {
      expect(
        detectBankFromUrl('https://example.com/receipt/123'),
        isNull,
      );
      expect(detectBankFromUrl('not a url'), isNull);
    });
  });

  group('detectReceipt', () {
    test('treats 12-hex payloads as CBE new QR ids', () {
      final d = detectReceipt('a1b2c3d4e5f6');
      expect(d, isNotNull);
      expect(d!.bank, 'cbe-new');
    });

    test('falls back to reference detection', () {
      final d = detectReceipt('ft26140p01yb');
      expect(d!.bank, 'cbe');
      expect(d.reference, 'FT26140P01YB');
    });
  });

  group('ChekiException.friendly', () {
    test('maps status codes to friendly copy', () {
      const notFound = ChekiException('x', statusCode: 404);
      expect(notFound.friendly, contains('not found'));

      const server = ChekiException('x', statusCode: 502);
      expect(server.friendly, contains('unavailable'));
    });
  });
}
