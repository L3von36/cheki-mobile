import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cheki_mobile/core/banks_registry.dart';
import 'package:cheki_mobile/core/native/parsers.dart';
import 'package:cheki_mobile/core/native/pdf_text.dart';
import 'package:cheki_mobile/core/native/verifier.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha1.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/dashen_fixture.dart';
import 'fixtures/zemen_fixture.dart';

void main() {
  group('buildReceiptUrl', () {
    test('builds every bank endpoint', () {
      expect(
        buildReceiptUrl(bank: 'cbe-new', reference: 'a1b2c3d4e5f6'),
        'https://Mb.cbe.com.et/api/v1/transactions/public/transaction-detail/a1b2c3d4e5f6',
      );
      expect(
        buildReceiptUrl(bank: 'telebirr', reference: 'DET8FJGUJ4'),
        'https://transactioninfo.ethiotelecom.et/receipt/DET8FJGUJ4',
      );
      expect(
        buildReceiptUrl(
          bank: 'boa',
          reference: 'FT26167ZVPCJ',
          accountNumber: '10023456789',
        ),
        'https://cs.bankofabyssinia.com/api/onlineSlip/getDetails/?id=FT26167ZVPCJ56789',
      );
      expect(
        buildReceiptUrl(bank: 'mpesa', reference: 'SLCC71ABC'),
        'https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=SLCC71ABC',
      );
      expect(
        buildReceiptUrl(bank: 'dashen', reference: 'B22WDTI261620001'),
        'https://receipt.dashensuperapp.com/receipt/B22WDTI261620001',
      );
      expect(
        buildReceiptUrl(bank: 'awash', reference: '2KDL95Z0NR-4U61O6'),
        'https://awashpay.awashbank.com:8225/-2KDL95Z0NR-4U61O6',
      );
      expect(
        buildReceiptUrl(bank: 'zemen', reference: 'ZMTX2400011223'),
        'https://share.zemenbank.com/rt/ZMTX2400011223/pdf',
      );
      expect(
        buildReceiptUrl(bank: 'siinqee', reference: 'ABC123def'),
        'https://receipt.ebirr.com/siinqee/ABC123def',
      );
      expect(
        buildReceiptUrl(bank: 'ebirr', reference: 'nib/abc123def'),
        'https://receipt.ebirr.com/nib/abc123def',
      );
      expect(
        buildReceiptUrl(
          bank: 'cbebirr',
          reference: 'CB12345678',
          phoneNumber: '0911001122',
        ),
        'https://cbepay1.cbe.com.et/aureceipt?TID=CB12345678&PH=0911001122',
      );
    });
  });

  group('CBE new parser', () {
    test('parses a transaction-detail JSON', () {
      final json = jsonEncode({
        'id': 'fHCxyV4mg5p',
        'debitAccountHolder': 'MOHAMMED ABDULWASI',
        'debitAccountNo': '1000234567890',
        'creditAccountHolder': 'SAMI ADIL ZEKARIA',
        'creditAccountNo': '1000987654321',
        'amountCredited': '20000.00',
        'creditCurrency': 'ETB',
        'dateTimes': ['5/20/2026, 7:29:00 PM'],
        'paymentDetails': ['rent'],
      });
      final r = parseCbeNew(json);
      expect(r.verified, isTrue);
      expect(r.senderName, 'MOHAMMED ABDULWASI');
      expect(r.receiverName, 'SAMI ADIL ZEKARIA');
      expect(r.amount, 20000);
      expect(r.reference, 'fHCxyV4mg5p');
      expect(r.reason, 'rent');
    });

    test('rejects error payloads', () {
      expect(parseCbeNew('{"title":"Internal Server Error"}').verified, isFalse);
      expect(parseCbeNew('not json').verified, isFalse);
    });
  });

  group('BOA parser', () {
    test('parses getDetails JSON', () {
      final json = jsonEncode({
        'body': [
          {
            "Payer's Name": 'TEST PAYER',
            'Source Account Name': 'ABEBE KEbede',
            'Source Account': '1234567890',
            "Receiver's Name": 'CORNER SHOP',
            "Receiver's Account": '9876543210',
            'Transferred Amount': '1,250.50 ETB',
            'Transaction Date': '2026-06-01',
            'Transaction Reference': 'FT26167ZVPCJ',
          }
        ]
      });
      final r = parseBoa(json);
      expect(r.verified, isTrue);
      expect(r.senderName, 'ABEBE KEbede');
      expect(r.amount, 1250.50);
      expect(r.reference, 'FT26167ZVPCJ');
    });

    test('rejects invalid reference responses', () {
      final json =
          jsonEncode({'body': [{"Payer's Name": 'Invalid reference number'}]});
      expect(parseBoa(json).verified, isFalse);
    });
  });

  group('M-Pesa parser', () {
    test('parses getReceipt JSON', () {
      final r = parseMpesa(jsonEncode({
        'responseCode': '0',
        'senderName': 'JANE DOO',
        'receiverName': 'MERCHANT X',
        'amount': '500',
        'currency': 'ETB',
        'transactionDate': '2026-06-02 10:00:00',
        'transactionId': 'SLCC71ABC',
      }));
      expect(r.verified, isTrue);
      expect(r.senderName, 'JANE DOO');
      expect(r.amount, 500);
      expect(r.reference, 'SLCC71ABC');
    });

    test('rejects non-zero response codes', () {
      expect(parseMpesa('{"responseCode":"1"}').verified, isFalse);
    });
  });

  group('Telebirr parser', () {
    test('parses the HTML receipt tables', () {
      const html = '''
<html><body><div>telebirr receipt</div>
<table>
<tr><td>Payer Name</td><td>Mr Mohammed Abdulwasi Reshid</td></tr>
<tr><td>Payer telebirr no</td><td>0712345678</td></tr>
<tr><td>Credited Party name</td><td>SAMI ADIL ZEKARIA</td></tr>
<tr><td>Bank account number</td><td>1000370251685&nbsp;&nbsp;&nbsp;Mr Sami Adil</td></tr>
<tr><td>transaction status</td><td>Successful</td></tr>
<tr><td>Invoice No.</td><td>CHQ0FJ403O</td></tr>
<tr><td>Payment date</td><td>12-06-2026 13:45:10</td></tr>
<tr><td>Settled Amount</td><td>1,500.00 Birr</td></tr>
<tr><td>Payment Reason</td><td>Transfer to bank</td></tr>
<tr><td>Payment Mode</td><td>Mobile App</td></tr>
</table></body></html>''';
      final r = parseTelebirr(html);
      expect(r.verified, isTrue);
      expect(r.senderName, 'Mr Mohammed Abdulwasi Reshid');
      expect(r.senderAccount, '0712345678');
      expect(r.receiverName, 'SAMI ADIL ZEKARIA');
      expect(r.receiverAccount, '1000370251685');
      expect(r.amount, 1500);
      expect(r.reference, 'CHQ0FJ403O');
      expect(r.date, '12-06-2026 13:45:10');
      expect(r.reason, 'Transfer to bank');
    });

    test('rejects error pages', () {
      expect(
        parseTelebirr('<html>This request is not correct</html>').verified,
        isFalse,
      );
    });
  });

  group('Awash parser (real fixtures)', () {
    test('parses a Send Money receipt', () {
      final html = utf8.decode(readFixture('awash_send_money.html'));
      final r = parseAwash(html);
      expect(r.verified, isTrue);
      expect(r.senderName, 'MEDINA  KASSAHUN  MOHAMMED');
      expect(r.senderAccount, '01425******7400/BANK');
      expect(r.amount, 100);
      expect(r.date, '2026-05-14 12:05:55');
      expect(r.transactionType, 'Send Money');
      expect(r.reference, '260514120550963');
    });
  });

  group('eBirr parser', () {
    test('parses a tenant receipt page', () {
      const html = '''
<html><body><table>
<tr><td>Sender</td><td>NIB CUSTOMER</td></tr>
<tr><td>Receiver</td><td>TOKEN STATION</td></tr>
<tr><td>Amount</td><td>300.00 Birr</td></tr>
<tr><td>Date</td><td>2026-06-03</td></tr>
<tr><td>Reference</td><td>EB123456</td></tr>
</table></body></html>''';
      final r = parseEbirr(html);
      expect(r.verified, isTrue);
      expect(r.senderName, 'NIB CUSTOMER');
      expect(r.amount, 300);
    });

    test('rejects Not Found pages', () {
      expect(
        parseEbirr('<h1 style="color: red">Not Found Page</h1>').verified,
        isFalse,
      );
    });
  });

  group('CBE Birr parser', () {
    test('parses label/value HTML', () {
      final html = '''
<html><body>${'<div>padding</div>' * 30}
<table>
<tr><td>Sender name</td><td>ABEBE BIKILA</td></tr>
<tr><td>Amount</td><td>750.00</td></tr>
<tr><td>Date</td><td>2026-06-05</td></tr>
<tr><td>Reference</td><td>CBB123456</td></tr>
</table></body></html>''';
      final r = parseCbeBirr(html);
      expect(r.verified, isTrue);
      expect(r.senderName, 'ABEBE BIKILA');
      expect(r.amount, 750);
    });
  });

  group('PDF text extractor', () {
    test('extracts Dashen receipt text and parses it', () {
      final bytes = Uint8List.fromList(base64Decode(kDashenPdfBase64));
      final r = parseDashenPdf(bytes);
      expect(r.verified, isTrue, reason: extractPdfText(bytes));
      expect(r.senderName, 'Akrem Yusuf Ali');
      expect(r.receiverName, contains('Arkan International Plc'));
      expect(r.amount, 20475);
      expect(r.reference, 'B22WDTI261620001');
      expect(r.date, contains('Jun 11, 2026'));
      expect(r.reason, 'transfer to dashen');
    });

    test('extracts Zemen receipt text and parses it', () {
      final bytes = Uint8List.fromList(base64Decode(kZemenPdfBase64));
      final r = parseZemenPdf(bytes);
      expect(r.verified, isTrue, reason: extractPdfText(bytes));
      expect(r.senderName, 'KALKIDAN ABEBE TESFAYE');
      expect(r.receiverName, 'SAMI ADIL ZEKARIA');
      expect(r.amount, 4500);
      expect(r.reference, 'ZMTX2400011223');
      expect(r.transactionStatus, 'SUCCESS');
    });

    test('returns empty text for non-PDF bytes', () {
      expect(extractPdfText(Uint8List.fromList(utf8.encode('<html>hi'))), '');
      expect(extractPdfText(Uint8List(0)), '');
    });
  });

  group('BOA QR decryptor', () {
    test('round-trips an encrypted receipt payload', () {
      final csv =
          '1000123456789,ABEBE KEPLER,1250.50,FT26167ZVPCJ,2026-06-01,1000987654321,CORNER SHOP';
      final encrypted = _encryptForTest(csv);
      final r = BoaQrDecryptor.decrypt(encrypted);
      expect(r.verified, isTrue);
      expect(r.senderAccount, '1000123456789');
      expect(r.senderName, 'ABEBE KEPLER');
      expect(r.amount, 1250.5);
      expect(r.reference, 'FT26167ZVPCJ');
      expect(r.receiverName, 'CORNER SHOP');
    });

    test('rejects junk payloads', () {
      expect(BoaQrDecryptor.decrypt('not-base64!!').verified, isFalse);
      expect(BoaQrDecryptor.decrypt('').verified, isFalse);
    });
  });

  group('QR payload detection', () {
    test('detects every receipt URL shape', () {
      expect(
        detectReceipt('https://mbreciept.cbe.com.et/fHCxyV4mg5p')?.bank,
        'cbe-new',
      );
      expect(
        detectReceipt(
                'https://transactioninfo.ethiotelecom.et/receipt/CHQ0FJ403O')
            ?.bank,
        'telebirr',
      );
      expect(
        detectReceipt('https://awashpay.awashbank.com:8225/-2KCEJ93MLV-4LDO6R')
            ?.reference,
        '2KCEJ93MLV-4LDO6R',
      );
      expect(
        detectReceipt('https://share.zemenbank.com/rt/ZMTX1/pdf')?.bank,
        'zemen',
      );
      expect(
        detectReceipt(
            'https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=SLCC71ABC')
            ?.reference,
        'SLCC71ABC',
      );
      expect(
        detectReceipt('https://receipt.ebirr.com/nib/abc123')?.bank,
        'ebirr',
      );
    });

    test('generic reference QR payloads keep bank open for manual pick', () {
      final detection = detectReceipt('PAYOUT99231X');
      expect(detection, isNotNull);
      expect(detection!.bank, isNull);
      expect(detection.reference, 'PAYOUT99231X');
    });

    test('unrelated QR content is rejected', () {
      expect(detectReceipt('WIFI:S:HomeNet;T:WPA;P:hunter2;;'), isNull);
      expect(detectReceipt('BEGIN:VCARD'), isNull);
    });
  });
}

/// Encrypts with the same scheme BOA's web app uses, for round-trip tests.
String _encryptForTest(String plaintext) {
  const password =
      'ELqVy2g4pGWLUIKSa+1ijwpPy6eDxBFBLBPrJ24v/IA=';
  const iv = '1234567890123456';

  final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
    ..init(Pbkdf2Parameters(utf8.encode('salt'), 10000, 32));
  final key = derivator.process(utf8.encode(password));

  final plain = utf8.encode(plaintext);
  final padLen = 16 - (plain.length % 16);
  final padded = Uint8List(plain.length + padLen)..setAll(0, plain);
  for (var i = plain.length; i < padded.length; i++) {
    padded[i] = padLen;
  }

  final cbc = CBCBlockCipher(AESEngine())
    ..init(true, pc.ParametersWithIV<pc.KeyParameter>(
        pc.KeyParameter(key), Uint8List.fromList(utf8.encode(iv))));

  final out = Uint8List(padded.length);
  for (var offset = 0; offset < padded.length; offset += 16) {
    out.setRange(
      offset,
      offset + 16,
      cbc.process(Uint8List.sublistView(padded, offset, offset + 16)),
    );
  }
  return base64Encode(out);
}

List<int> readFixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();
