/// Tests for the app-side extra banks (Wegagen, Amhara) — URL detection,
/// JSON parsing against REAL API payloads captured from the banks'
/// endpoints, HTTP-failure mapping, catalog wiring and controller routing.
library;

import 'dart:convert';
import 'dart:io';

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
      expect(isExtraBank('awash'), isTrue); // engine entry, app-layer verifier
      expect(isExtraBank('cbe'), isTrue); // engine entry, hardened app flow
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

    test('reads the Amhara QR JSON payload — the real scanned text', () {
      // Decoded from the QR on the user's Amhara web receipt screenshots.
      final d = detectExtraBankFromUrl(
          '{"transactionId":"FT262507XG9T","creditAccountNo":"ETB1756000010003"}');
      expect(d!.bank, 'amhara');
      expect(d.reference, 'FT262507XG9T');

      final d2 = detectExtraBankFromUrl(
          '{"transactionId":"FT26248K7Q1P","creditAccountNo":"9900050363768"}');
      expect(d2!.bank, 'amhara');
      expect(d2.reference, 'FT26248K7Q1P');
    });

    test('reads the Wegagen QR prose — the real scanned text', () {
      // Decoded from the QR on the user's Wegagen receipt screenshot: the
      // link sits inside SMS prose, so the payload is NOT a bare URL.
      const prose = 'Amount ETB-2000 is Transferred From : FIREHIWOT KEBEDE '
          'MENGESHA 1*****4231701 To --- (2519*****45), with transaction ID: '
          '150TBAW262622115 on date Sat Sep 19 2026. For more information, '
          'click here: https://transinfo.wegagenbanksc.com.et:8183/'
          '?id=150TBAW2626221151113DAAT - Wegagen Bank.';
      final d = detectExtraBankFromUrl(prose);
      expect(d!.bank, 'wegagen');
      expect(d.reference, '150TBAW2626221151113DAAT');
    });

    test('JSON without a usable transactionId stays undetected', () {
      expect(detectExtraBankFromUrl('{"amount":100}'), isNull);
      expect(detectExtraBankFromUrl('{"transactionId":""}'), isNull);
      expect(detectExtraBankFromUrl('{"transactionId":12345}'), isNull);
      expect(detectExtraBankFromUrl('{ broken json'), isNull);
    });

    test('leaves every other bank to the engine detector', () {
      expect(detectExtraBankFromUrl(
          'https://mbreciept.cbe.com.et/abc123'), isNull);
      expect(detectExtraBankFromUrl('FT262507XG9T'), isNull);
      expect(detectExtraBankFromUrl(''), isNull);
    });

    test('reads the Awash share link and KEEPS the leading dash', () {
      final d = detectExtraBankFromUrl(
          'https://awashpay.awashbank.com:8225/-2KHIQYW30P-5VQUNG');
      expect(d!.bank, 'awash');
      // The dash is part of the token — stripping it makes the bank 403.
      expect(d.reference, '-2KHIQYW30P-5VQUNG');
    });

    test('reads a dash-less Awash token and trims prose punctuation', () {
      final d = detectExtraBankFromUrl(
          'Payment done https://awashpay.awashbank.com:8225/2KHIQYW30P5VQUNG.');
      expect(d!.bank, 'awash');
      expect(d.reference, '2KHIQYW30P5VQUNG');
    });

    test('Awash detection also works via the host fallback', () {
      final d = detectExtraBankFromUrl(
          'https://awashpay.awashbank.com/-3ABCDEF123456');
      expect(d!.bank, 'awash');
      expect(d.reference, '-3ABCDEF123456');
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

  group('verifyExtraBank — Awash', () {
    // Real page captured from awashpay.awashbank.com:8225 (Sep 2026).
    final awashHtml =
        File('test/fixtures/awash_receipt.html').readAsStringSync();

    test('parses the real receipt page end-to-end', () async {
      final seen = <Uri?>[];
      final res = await verifyExtraBank(
        const VerifyInput(
            bankId: 'awash', reference: '-2KHIQYW30P-5VQUNG'),
        httpFn: (uri, headers) async {
          seen.add(uri);
          return ExtraHttpResponse(200, utf8.encode(awashHtml));
        },
      );
      expect(res.ok, isTrue);
      final r = res.receipt!;
      expect(r.bankCode, 'awash');
      expect(r.bankName, 'Awash Bank');
      expect(r.reference, '260915115082057'); // Transaction ID on the page
      expect(r.senderName, 'SERAWIT ASEBELIGN MOKONNEN');
      expect(r.senderAccount, '01320******402/BANK');
      expect(r.receiverName, 'FIREHIWOT KEBEDE'); // Merchant
      expect(r.receiverAccount, '68048000'); // Till Number
      expect(r.amount, 100.0);
      expect(r.currency, 'ETB');
      expect(r.date, '2026-09-15 11:50:07');
      expect(r.transactionType, 'Merchant Payment');
      // The request must carry the token EXACTLY as shared (dash kept).
      expect(
          seen.single!.toString(),
          'https://awashpay.awashbank.com:8225/-2KHIQYW30P-5VQUNG');
    });

    test('a dash-less token retries once with the dash prepended', () async {
      final urls = <Uri>[];
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'awash', reference: '2KHIQYW30P5VQUNG'),
        httpFn: (uri, headers) async {
          urls.add(uri);
          if (uri.pathSegments.last == '-2KHIQYW30P5VQUNG') {
            return ExtraHttpResponse(200, utf8.encode(awashHtml));
          }
          return const ExtraHttpResponse(403, []); // dash-less: 403
        },
      );
      expect(res.ok, isTrue);
      expect(res.receipt!.amount, 100.0);
      expect(urls, hasLength(2));
      expect(urls.last.pathSegments.last, '-2KHIQYW30P5VQUNG');
    });

    test('403 for both dash shapes maps to not-found', () async {
      var calls = 0;
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'awash', reference: '-UNKNOWN000000'),
        httpFn: (uri, headers) async {
          calls++;
          return const ExtraHttpResponse(403, []);
        },
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
      expect(res.failure!.message, contains('No receipt found'));
      expect(calls, 2); // as-shared then flipped — no 5xx retry storm
    });
  });

  group('verifyExtraBank — Amhara service rejections', () {
    test('HTTP 500 status:false maps to an honest message, no retries',
        () async {
      var calls = 0;
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'amhara', reference: 'FT262478FQ3P'),
        httpFn: (uri, headers) async {
          calls++;
          return ExtraHttpResponse(
              500,
              utf8.encode(
                  '{"status":false,"message":"Internal server error."}'));
        },
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
      expect(res.failure!.message,
          contains('receipt service could not return this transaction'));
      expect(res.failure!.message, contains('Internal server error.'));
      expect(res.failure!.message, contains('never got a web receipt'));
      expect(calls, 1); // definitive answer — no retry storm
    });

    test('a 5xx without the status:false JSON keeps the retry path',
        () async {
      var calls = 0;
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'amhara', reference: 'FT262507XG9T'),
        httpFn: (uri, headers) async {
          calls++;
          return ExtraHttpResponse(500, utf8.encode('<html>boom</html>'));
        },
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.network);
      expect(calls, 3);
    });
  });

  group('verifyExtraBank — CBE', () {
    // Real payload captured live from Mb.cbe.com.et's transaction-detail
    // API (Sep 2026) — the receipt behind the mbreciept.cbe.com.et link on
    // the user's CBE app screenshot.
    final cbeJson = File('test/fixtures/cbe_receipt.json').readAsStringSync();

    test('parses the real receipt end-to-end with the app headers', () async {
      final seen = <Uri?>[];
      Map<String, String>? seenHeaders;
      final res = await verifyExtraBank(
        const VerifyInput(
            bankId: 'cbe', reference: 'v2-hfHCxGKF1KZsUlmmWpFL'),
        httpFn: (uri, headers) async {
          seen.add(uri);
          seenHeaders = headers;
          return ExtraHttpResponse(200, utf8.encode(cbeJson));
        },
      );
      expect(res.ok, isTrue);
      final r = res.receipt!;
      expect(r.bankCode, 'cbe');
      expect(r.bankName, 'Commercial Bank of Ethiopia');
      expect(r.reference, 'FT262478FQ3P');
      expect(r.senderName, 'Lidya Michael Tezera');
      expect(r.senderAccount, '1********5276');
      expect(r.receiverName, 'Abdulrehim Mohammed Usman');
      expect(r.receiverAccount, '1********2206');
      expect(r.amount, 5100.00);
      expect(r.currency, 'ETB');
      // 2026-09-04T10:59:00Z → Ethiopia wall time (UTC+3)
      expect(r.date, '2026-09-04 13:59');
      expect(r.reason, 'MB Transfer');
      expect(r.transactionStatus, isNull); // parseCbeNewJson maps no status
      // The API needs the app-identity headers or it refuses.
      expect(seenHeaders!['X-App-ID'], 'd1292e42-7400-49de-a2d3-9731caa4c819');
      expect(seenHeaders!['X-App-Version'],
          '0a01980b-9859-1369-8198-59f403820000');
      expect(seen.single!.path,
          '/api/v1/transactions/public/transaction-detail/v2-hfHCxGKF1KZsUlmmWpFL');
    });

    test('a transient 400 is retried and the retry verifies', () async {
      var calls = 0;
      final res = await verifyExtraBank(
        const VerifyInput(
            bankId: 'cbe', reference: 'v2-hfHCxGKF1KZsUlmmWpFL'),
        httpFn: (uri, headers) async {
          calls++;
          if (calls == 1) {
            // Observed live: 400 “transaction not found with id:
            // FT262478FQ3P” followed by 200 for the SAME request.
            return ExtraHttpResponse(
                400,
                utf8.encode(
                    '{"status":400,"detail":"transaction not found with id: FT262478FQ3P"}'));
          }
          return ExtraHttpResponse(200, utf8.encode(cbeJson));
        },
      );
      expect(res.ok, isTrue);
      expect(res.receipt!.amount, 5100.00);
      expect(calls, 2);
    });

    test('a persistent 400 maps to an honest not-found', () async {
      var calls = 0;
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'cbe', reference: 'v2-doesnotexist0000'),
        httpFn: (uri, headers) async {
          calls++;
          return ExtraHttpResponse(
              400,
              utf8.encode(
                  '{"status":400,"detail":"transaction not found with id: X"}'));
        },
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
      expect(res.failure!.message, contains('No receipt found'));
      expect(calls, 3); // retried like a 5xx before giving up
    });

    test('a 200 without a usable record maps to not-found', () async {
      final res = await verifyExtraBank(
        const VerifyInput(bankId: 'cbe', reference: 'v2-emptyrecord0000'),
        httpFn: (uri, headers) async =>
            ExtraHttpResponse(200, utf8.encode('{"detail":"nope"}')),
      );
      expect(res.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
    });
  });

  group('controller routing — scan payload shapes from the real QRs', () {
    test('scanning the Wegagen receipt QR (prose) auto-detects Wegagen',
        () async {
      VerifyInput? seen;
      final c = VerifyController(
        extraVerifyFn: (input) async {
          seen = input;
          return VerifyResult.receipt(
            parseWegagenReceiptJson(_wegagenJson)!,
            5,
          );
        },
      );
      c.applyScan(
          'Amount ETB-1000 is Transferred From : FIREHIWOT KEBEDE MENGESHA '
          '1*****4231701 To --- (2519*****45), with transaction ID: '
          '150TBAW262612099 on date Fri Sep 18 2026. For more information, '
          'click here: https://transinfo.wegagenbanksc.com.et:8183/'
          '?id=150TBAW2626120991113DAAT - Wegagen Bank.');
      expect(c.detectedBank!.id, 'wegagen');
      expect(c.reference, '150TBAW2626120991113DAAT');
      expect(c.canVerify, isTrue);

      final res = await c.verify();
      expect(seen!.bankId, 'wegagen');
      expect(res!.ok, isTrue);
    });

    test('scanning the Amhara receipt QR (bare JSON) auto-detects Amhara',
        () async {
      VerifyInput? seen;
      final c = VerifyController(
        extraVerifyFn: (input) async {
          seen = input;
          return VerifyResult.receipt(
            parseAmharaReceiptJson(_amharaOutgoingJson).receipt!,
            5,
          );
        },
      );
      c.applyScan(
          '{"transactionId":"FT262507XG9T","creditAccountNo":"ETB1756000010003"}');
      expect(c.detectedBank!.id, 'amhara');
      expect(c.reference, 'FT262507XG9T');
      expect(c.canVerify, isTrue);

      final res = await c.verify();
      expect(seen!.bankId, 'amhara');
      expect(seen!.reference, 'FT262507XG9T');
      expect(res!.ok, isTrue);
    });

    test('pasting the Amhara QR JSON into the field detects Amhara too',
        () {
      final c = VerifyController();
      c.setReference(
          '{"transactionId":"FT26248K7Q1P","creditAccountNo":"9900050363768"}');
      expect(c.detectedBank!.id, 'amhara');
      expect(c.reference, 'FT26248K7Q1P');
    });

    test('scanning the CBE app QR routes to the extra verifier', () async {
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
      c.applyScan('https://mbreciept.cbe.com.et/v2-hfHCxGKF1KZsUlmmWpFL');
      expect(c.detectedBank!.id, 'cbe');
      expect(c.reference, 'v2-hfHCxGKF1KZsUlmmWpFL');
      await c.verify();
      expect(seen!.bankId, 'cbe'); // extra verifier (engine stays verbatim)
    });

    test('an unknown link still falls back to the manual-bank flow', () {
      final c = VerifyController();
      c.applyScan('https://example.com/receipt/123');
      expect(c.detectedBank, isNull);
      expect(c.reference, 'https://example.com/receipt/123');
    });
  });

  group('controller routing — pasted links (v1.5.1 regressions)', () {
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

    test('a pasted Awash link auto-detects; the verifier extracts the token',
        () async {
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
      // setReference (the paste path) keeps the URL as typed — the bank is
      // detected and the EXTRA VERIFIER extracts the token from it.
      c.setReference(
          'https://awashpay.awashbank.com:8225/-2KHIQYW30P-5VQUNG');
      expect(c.detectedBank!.id, 'awash');
      expect(c.canVerify, isTrue);

      await c.verify();
      expect(seen!.bankId, 'awash');
      expect(seen!.reference, '-2KHIQYW30P-5VQUNG');
      expect(c.result!.failure!.kind, VerifyErrorKind.notFound);
    });

    test('a pasted Wegagen link verifies even with the full URL in the field',
        () async {
      // Regression: the home-screen paste path used to hand the FULL URL to
      // the verifier, which then called …/txn/https://… and always failed.
      VerifyInput? seen;
      final c = VerifyController(
        extraVerifyFn: (input) async {
          seen = input;
          return VerifyResult.receipt(
            parseWegagenReceiptJson(_wegagenJson)!,
            5,
          );
        },
      );
      c.setReference(
          'https://transinfo.wegagenbanksc.com.et:8183/?id=150TBAW2626221151113DAAT');
      expect(c.detectedBank!.id, 'wegagen');
      expect(c.canVerify, isTrue);

      final res = await c.verify();
      expect(seen!.bankId, 'wegagen');
      expect(seen!.reference, '150TBAW2626221151113DAAT');
      expect(res!.ok, isTrue);
    });

    test('a pasted Amhara link verifies even with the full URL in the field',
        () async {
      VerifyInput? seen;
      final c = VerifyController(
        extraVerifyFn: (input) async {
          seen = input;
          return VerifyResult.receipt(
            parseAmharaReceiptJson(_amharaOutgoingJson).receipt!,
            5,
          );
        },
      );
      c.setReference('https://receipt.amharabank.com.et/?trx=FT262507XG9T');
      expect(c.detectedBank!.id, 'amhara');

      final res = await c.verify();
      expect(seen!.reference, 'FT262507XG9T');
      expect(res!.ok, isTrue);
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
