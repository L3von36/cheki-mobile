/// Tests for the app-side extra banks (Wegagen, Amhara) — URL detection,
/// JSON parsing against REAL API payloads captured from the banks'
/// endpoints, HTTP-failure mapping, catalog wiring and controller routing.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/receipt_verify/extra_banks.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';
import 'package:mahtem/state/verify_controller.dart';

const _wegagenJson = '''
{"master_id":"---","billing_period":"---","account_number":"---",
 "receiver_account":"251911648945","currBalance":4028.7,
 "messageSentTimestamp":"2026-09-19T12:37:34.603Z",
 "sender_name":"FIREHIWOT KEBEDE MENGESHA","biller_account":"---",
 "trnRefNo":"150TBAW262622115","receiver_name":"---","currency":"ETB",
 "id":"031b3d96-ffe4-430c-b63f-0a778add9792","event":"INIT      ",
 "timestamp":"2026-09-20T10:30:43.726950900Z","charge":0.3,
 "biller_name":"---","eventSrNo":1,"accNo":"1113594231701","module":"TBAW",
 "narrative":"Telebirr transfer from account to wallet","vat":0.05,
 "message":"Dear FIREHIWOT, A Withdrawal of ETB 2,000 ...",
 "version":"1","txnTimestamp":"2026-09-19T15:37:32.507Z",
 "messageStatus":"sent","drCr":"D","phoneNumber":"0911648945",
 "trnCode":"AAT","srNo":"2879739769","sender_account":"1113594231701",
 "trnDt":"2026-09-18T21:00:00.000Z","amount_in_words":"Two Thousand  Birr",
 "payer_name":"---","txnAmount":2000,
 "paymentType":"SERVICE CHARGE ON TOP UP AIR TIME",
 "paymentMethod":"Account To Account Transfer","userId":"MBUSER",
 "authId":"MBUSER"}
''';

const _amharaOutgoingJson = '''
{"status":true,"data":{"netChargeAmount":"ETB30","dateTime":"2609060908",
 "amount":"5000.00","debitAccount":"9900050363768",
 "creditorName":"A2A Transfer - ETH Outgoing",
 "transactionReference":"FT262507XG9T","city":"ADDIS ABABA",
 "otherBankName":"COMMERCIAL BANK OF ETHIOPIA",
 "receiverName":"Miss Firehiwot Kebede Mengesha","drChargeAmount":"ETB1.50",
 "branchName":"AMHARA BANK S.C.","woreda":"WOREDA -8",
 "transactionDesc":"IPS Outgoing Txn","totalAmount":"ETB5036.00",
 "subCity":"Arada","otherBankBic":"CBETETAA",
 "creditAccountId":"ETB1756000010003","reveiverAccount":"1000217529647",
 "currencyId":"ETB","taxAmount":"ETB4.50","bookingDate":"20260907",
 "debitorName":"Firehiwot Kebede Mengesha","status":"MAT"}}
''';

const _amharaIncomingJson = '''
{"status":true,"data":{"netChargeAmount":"ETB0","dateTime":"2609051714",
 "amount":"5000.00","debitAccount":"ETB1251700010003",
 "creditorName":"Firehiwot Kebede Mengesha",
 "transactionReference":"FT26248K7Q1P","city":"ADDIS ABABA",
 "otherBankName":"COMMERCIAL BANK OF ETHIOPIA",
 "sendorAccount":"1000217529647","branchName":"AMHARA BANK S.C.",
 "woreda":"WOREDA -8","transactionDesc":"IPS Incoming Txn",
 "totalAmount":"ETB5000.00","subCity":"Arada","otherBankBic":"CBETETAA",
 "sendorName":"Firehiwot Kebede Mengesha","street":"WOREDA -8",
 "bookingDate":"20260905","creditAccountId":"9900050363768",
 "currencyId":"ETB","debitorName":"A2A Transfer - ETH Incoming",
 "status":"MAT"}}
''';

void main() {
  group('catalog', () {
    test('the combined catalog carries the two extras', () {
      expect(kAllVerifyBanks.length, kVerifyBanks.length + 2);
      expect(bankByIdAll('wegagen')!.name, 'Wegagen Bank');
      expect(bankByIdAll('amhara')!.name, 'Amhara Bank');
      expect(bankByIdAll('telebirr')!.id, 'telebirr'); // engine ids intact
      expect(bankByIdAll('nope'), isNull);
      expect(isExtraBank('wegagen'), isTrue);
      expect(isExtraBank('amhara'), isTrue);
      expect(isExtraBank('cbe'), isFalse);
    });
  });

  group('detectExtraBankFromUrl', () {
    test('reads the Wegagen transinfo link', () {
      final d = detectExtraBankFromUrl(
          'https://transinfo.wegagenbanksc.com.et:8183/?id=150TBAW2626221151113DAAT');
      expect(d!.bank, 'wegagen');
      expect(d.reference, '150TBAW2626221151113DAAT');
    });

    test('reads the Wegagen link embedded in the SMS prose', () {
      final d = detectExtraBankFromUrl(
          'Dear Customer, thank you for choosing Wegagen Bank. '
          'https://transinfo.wegagenbanksc.com.et:8183/?id=150TBAW2626120991113DAAT');
      expect(d!.bank, 'wegagen');
      expect(d.reference, '150TBAW2626120991113DAAT');
    });

    test('reads the Amhara receipt link', () {
      final d = detectExtraBankFromUrl(
          'https://receipt.amharabank.com.et/?trx=FT262507XG9T');
      expect(d!.bank, 'amhara');
      expect(d.reference, 'FT262507XG9T');
    });

    test('reads an API-style Amhara share (path, no query)', () {
      final d = detectExtraBankFromUrl(
          'https://transaction.amharabank.com.et/FT26248K7Q1P');
      expect(d!.bank, 'amhara');
      expect(d.reference, 'FT26248K7Q1P');
    });

    test('leaves every other bank to the engine detector', () {
      expect(detectExtraBankFromUrl(
          'https://awashpay.awashbank.com:8225/-2KHIQYW30P-5VQUNG'), isNull);
      expect(detectExtraBankFromUrl(
          'https://mbreciept.cbe.com.et/abc123'), isNull);
      expect(detectExtraBankFromUrl('FT262507XG9T'), isNull);
      expect(detectExtraBankFromUrl(''), isNull);
    });
  });

  group('parseWegagenReceiptJson', () {
    test('parses the real payload', () {
      final r = parseWegagenReceiptJson(_wegagenJson)!;
      expect(r.verified, isTrue);
      expect(r.bankCode, 'wegagen');
      expect(r.bankName, 'Wegagen Bank');
      expect(r.reference, '150TBAW262622115');
      expect(r.senderName, 'FIREHIWOT KEBEDE MENGESHA');
      expect(r.senderAccount, '1113594231701');
      expect(r.receiverName, isNull); // '---' masked by the bank
      expect(r.receiverAccount, '251911648945'); // credited wallet number
      expect(r.amount, 2000);
      expect(r.currency, 'ETB');
      // 15:37:32.507Z + 3h → Ethiopia wall time
      expect(r.date, '2026-09-19 18:37');
      expect(r.transactionType, 'Telebirr transfer from account to wallet');
      expect(r.transactionStatus, 'sent');
      expect(r.invoiceNumber, '150TBAW262622115');
    });

    test('falls back to the receiving phone when everything is masked', () {
      final stripped = _wegagenJson
          .replaceAll('"receiver_account":"251911648945"', '"receiver_account":"---"');
      final r = parseWegagenReceiptJson(stripped)!;
      expect(r.receiverAccount, '0911648945');
      expect(r.receiverName, isNull);
    });

    test('returns null for garbage or non-records', () {
      expect(parseWegagenReceiptJson('not json'), isNull);
      expect(parseWegagenReceiptJson('[]'), isNull);
      expect(parseWegagenReceiptJson('{"charge":0.3}'), isNull);
      expect(parseWegagenReceiptJson('{"trnRefNo":"X"}'), isNull);
    });
  });

  group('parseAmharaReceiptJson', () {
    test('parses an outgoing (IPS) receipt', () {
      final out = parseAmharaReceiptJson(_amharaOutgoingJson);
      expect(out.rejectReason, isNull);
      final r = out.receipt!;
      expect(r.verified, isTrue);
      expect(r.bankCode, 'amhara');
      expect(r.reference, 'FT262507XG9T');
      expect(r.senderName, 'Firehiwot Kebede Mengesha'); // debitorName
      expect(r.senderAccount, '9900050363768'); // debitAccount
      expect(r.receiverName, 'Miss Firehiwot Kebede Mengesha');
      expect(r.receiverAccount, '1000217529647'); // the mislabelled field
      expect(r.amount, 5000.00);
      expect(r.currency, 'ETB');
      expect(r.date, '2026-09-06 09:08'); // yyMMddHHmm
      expect(r.branch, 'AMHARA BANK S.C.');
      expect(r.transactionType, 'IPS Outgoing Txn');
      expect(r.transactionStatus, 'MAT');
    });

    test('parses an incoming receipt via the sendor* misspellings', () {
      final out = parseAmharaReceiptJson(_amharaIncomingJson);
      final r = out.receipt!;
      expect(r.reference, 'FT26248K7Q1P');
      expect(r.senderName, 'Firehiwot Kebede Mengesha'); // sendorName
      expect(r.senderAccount, '1000217529647'); // sendorAccount
      expect(r.receiverName, 'Firehiwot Kebede Mengesha'); // creditorName
      expect(r.receiverAccount, '9900050363768'); // creditAccountId
      expect(r.date, '2026-09-05 17:14');
    });

    test('falls back to the booking date when dateTime is missing', () {
      final stripped = _amharaOutgoingJson
          .replaceAll('"dateTime":"2609060908"', '"dateTime":""');
      final r = parseAmharaReceiptJson(stripped).receipt!;
      expect(r.date, '2026-09-07');
    });

    test('a not-found body yields no receipt', () {
      expect(parseAmharaReceiptJson('garbage').receipt, isNull);
      expect(parseAmharaReceiptJson('{"status":false}').receipt, isNull);
      expect(
          parseAmharaReceiptJson('{"status":true,"data":{"status":"MAT"}}')
              .receipt,
          isNull); // no transaction reference → not a record
    });

    test('a non-MAT status rejects with its reason', () {
      final out = parseAmharaReceiptJson(
          _amharaOutgoingJson.replaceAll('"status":"MAT"', '"status":"RET"'));
      expect(out.receipt, isNull);
      expect(out.rejectReason, contains('RET'));
    });
  });

  group('verifyExtraBank', () {
    ExtraHttpFn ok(String body, {List<Uri?>? seen}) => (uri, headers) async {
          seen?.add(uri);
          return ExtraHttpResponse(200, utf8.encode(body));
        };

    test('Wegagen happy path hits the sms_wega endpoint', () async {
      final seen = <Uri?>[];
      final res = await verifyExtraBank(
        const VerifyInput(
            bankId: 'wegagen', reference: '150TBAW2626221151113DAAT'),
        httpFn: ok(_wegagenJson, seen: seen),
      );
      expect(res.ok, isTrue);
      expect(res.receipt!.bankCode, 'wegagen');
      expect(res.receipt!.amount, 2000);
      expect(seen.single!.port, 8011);
      expect(seen.single!.path, '/sms_wega/txn/150TBAW2626221151113DAAT');
    });

    test('Amhara happy path hits the transaction endpoint', () async {
      final seen = <Uri?>[];
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'amhara', reference: 'FT262507XG9T'),
        httpFn: ok(_amharaOutgoingJson, seen: seen),
      );
      expect(res.ok, isTrue);
      expect(res.receipt!.amount, 5000.00);
      expect(seen.single!.host, 'transaction.amharabank.com.et');
      expect(seen.single!.path, '/FT262507XG9T');
    });

    test('404 maps to not-found', () async {
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'amhara', reference: 'FT0000000000'),
        httpFn: (uri, headers) async => const ExtraHttpResponse(404, []),
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
    });

    test('a 200 with an unknown reference maps to not-found', () async {
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'wegagen', reference: '150BADRECEIPT0000X'),
        httpFn: ok('{"master_id":"---"}'),
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
    });

    test('5xx answers retry then map to a network failure', () async {
      var calls = 0;
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'amhara', reference: 'FT262507XG9T'),
        httpFn: (uri, headers) async {
          calls++;
          return ExtraHttpResponse(503, utf8.encode('busy'));
        },
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.network);
      expect(res.failure!.message, contains('503'));
      expect(calls, 3); // initial + 2 retries, like the engine
    });

    test('thrown errors map to a network failure', () async {
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'wegagen', reference: '150TBAW2626221151'),
        httpFn: (uri, headers) async => throw Exception('offline'),
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.network);
      expect(res.failure!.message, contains('Could not reach Wegagen Bank'));
    });

    test('empty reference is bad input without touching the network', () async {
      var called = false;
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'amhara', reference: '  '),
        httpFn: (uri, headers) async {
          called = true;
          return const ExtraHttpResponse(200, []);
        },
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.badInput);
      expect(called, isFalse);
    });
  });

  group('controller routing', () {
    test('a pasted Wegagen link auto-detects and verifies through the '
        'extra verifier', () async {
      VerifyInput? seen;
      final c = VerifyController(
        extraVerifyFn: (input) async {
          seen = input;
          return VerifyResult.failed(
            const VerifyFailure(VerifyErrorKind.notFound, 'x'),
            5,
          );
        },
      );
      c.applyScan(
          'https://transinfo.wegagenbanksc.com.et:8183/?id=150TBAW2626221151113DAAT');
      expect(c.detectedBank!.id, 'wegagen');
      expect(c.reference, '150TBAW2626221151113DAAT');
      expect(c.canVerify, isTrue);

      await c.verify();
      expect(seen!.bankId, 'wegagen');
      expect(seen!.reference, '150TBAW2626221151113DAAT');
      expect(c.result!.failure!.kind, VerifyErrorKind.notFound);
    });

    test('a manually picked Amhara bank routes to the extra verifier',
        () async {
      VerifyInput? seen;
      final c = VerifyController(
        extraVerifyFn: (input) async {
          seen = input;
          return VerifyResult.receipt(
            parseAmharaReceiptJson(_amharaOutgoingJson).receipt!,
            7,
          );
        },
      );
      c.selectBank(bankByIdAll('amhara'));
      c.setReference('FT262507XG9T');
      expect(c.canVerify, isTrue);

      final res = await c.verify();
      expect(seen!.bankId, 'amhara');
      expect(res!.ok, isTrue);
      expect(res.receipt!.bankCode, 'amhara');
      expect(res.receipt!.amount, 5000.00);
    });

    test('engine banks still route to the injected engine verifier',
        () async {
      var extraCalled = false;
      var engineCalled = false;
      final c = VerifyController(
        verifyFn: (input) async {
          engineCalled = true;
          return VerifyResult.failed(
            const VerifyFailure(VerifyErrorKind.notFound, 'x'),
            5,
          );
        },
        extraVerifyFn: (input) async {
          extraCalled = true;
          return VerifyResult.failed(
            const VerifyFailure(VerifyErrorKind.notFound, 'x'),
            5,
          );
        },
      );
      c.selectBank(bankByIdAll('telebirr'));
      c.setReference('CHQ261Z4AB2C');
      await c.verify();
      expect(engineCalled, isTrue);
      expect(extraCalled, isFalse);
    });
  });
}
