/// Geo-block relay — the app-side path that fetches Telebirr / M-Pesa
/// receipts through Mahtem's own Worker when the device looks abroad.
/// The relay answers only with DEFINITE results; everything else falls
/// back to the direct path unchanged.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/receipt_verify/geo_relay.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';

/// The Telebirr receipt page shape the engine's parser accepts (same
/// fixture as receipt_verify_test).
const _telebirrHtml = '''
<html><head><title>telebirr receipt</title></head><body>
<table>
  <tr><td>Payer Name</td><td>MOHAMMED A RESHID</td></tr>
  <tr><td>Payer telebirr no</td><td>0712345678</td></tr>
  <tr><td>Credited Party name</td><td>SAMI CLOTHING</td></tr>
  <tr><td>Bank account number</td><td>1000370251685</td></tr>
  <tr><td>transaction status</td><td>Successful</td></tr>
  <tr><td>Invoice No.</td><td>CHQ261Z4AB2C</td></tr>
  <tr><td>Payment date</td><td>18-09-2026 14:22:10</td></tr>
  <tr><td>Settled Amount</td><td>2,450.00 Birr</td></tr>
  <tr><td>Payment Mode</td><td>Mobile App</td></tr>
  <tr><td>Payment Reason</td><td>Clothes purchase</td></tr>
</table></body></html>
''';

const _mpesaJson =
    '{"responseCode":"0","senderName":"HALLELUJAH","receiverName":"SAMI",'
    '"amount":"320.50","currency":"ETB","transactionDate":"2026-09-18",'
    '"transactionId":"SJ72HK3YZ9"}';

void main() {
  group('looksOutsideEthiopia', () {
    test('UTC+3..+5 (Ethiopia and neighbours) reads as inside', () {
      expect(looksOutsideEthiopia(const Duration(hours: 3)), isFalse);
      expect(looksOutsideEthiopia(const Duration(hours: 4)), isFalse);
      expect(looksOutsideEthiopia(const Duration(hours: 5)), isFalse);
      expect(looksOutsideEthiopia(const Duration(hours: 1)), isFalse);
    });

    test('far offsets (VPN abroad) read as outside', () {
      expect(looksOutsideEthiopia(Duration.zero), isTrue);
      expect(looksOutsideEthiopia(const Duration(hours: -5)), isTrue);
      expect(looksOutsideEthiopia(const Duration(hours: 8)), isTrue);
      expect(looksOutsideEthiopia(const Duration(hours: 6)), isTrue);
    });
  });

  group('shouldUseGeoRelay', () {
    test('hermetic by default in tests (non-product builds never relay)',
        () {
      expect(shouldUseGeoRelay('telebirr'), isFalse);
      expect(shouldUseGeoRelay('mpesa'), isFalse);
    });

    test('only the two allowlisted banks', () {
      expect(
        shouldUseGeoRelay('cbe',
            productMode: true, web: false, utcOffset: const Duration(hours: -5)),
        isFalse,
      );
      expect(
        shouldUseGeoRelay('telebirr',
            productMode: true, web: false, utcOffset: const Duration(hours: -5)),
        isTrue,
      );
      expect(
        shouldUseGeoRelay('mpesa',
            productMode: true, web: false, utcOffset: const Duration(hours: -5)),
        isTrue,
      );
    });

    test('product build inside Ethiopia goes direct', () {
      expect(
        shouldUseGeoRelay('telebirr',
            productMode: true, web: false, utcOffset: const Duration(hours: 3)),
        isFalse,
      );
    });

    test('web always relays — the browser blocks the direct call', () {
      expect(
        shouldUseGeoRelay('telebirr',
            productMode: true, web: true, utcOffset: const Duration(hours: 3)),
        isTrue,
      );
    });
  });

  group('resolveRelayReference / relayReceiptUrl', () {
    test('bare references and the banks’ own links resolve', () {
      expect(
        resolveRelayReference(const VerifyInput(
            bankId: 'telebirr', reference: 'CHQ261Z4AB2C')),
        'CHQ261Z4AB2C',
      );
      expect(
        resolveRelayReference(const VerifyInput(
            bankId: 'telebirr',
            reference: 'https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C')),
        'CHQ261Z4AB2C',
      );
      // A link belonging to another bank never resolves.
      expect(
        resolveRelayReference(const VerifyInput(
            bankId: 'mpesa',
            reference: 'https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C')),
        isNull,
      );
      // Empty input defers to the direct path's richer errors.
      expect(
        resolveRelayReference(
            const VerifyInput(bankId: 'telebirr', reference: '  ')),
        isNull,
      );
    });

    test('an M-Pesa QR payload IS the reference', () {
      expect(
        resolveRelayReference(const VerifyInput(
            bankId: 'mpesa', reference: '', qrData: 'SJ72HK3YZ9')),
        'SJ72HK3YZ9',
      );
    });

    test('URLs mirror the engine’s _buildUri exactly', () {
      expect(relayReceiptUrl('telebirr', 'CHQ261Z4AB2C'),
          'https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C');
      expect(
          relayReceiptUrl('mpesa', 'SJ72HK3YZ9'),
          'https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=SJ72HK3YZ9');
      expect(relayReceiptUrl('cbe', 'x'), isNull);
    });
  });

  group('verifyViaGeoRelay', () {
    test('Telebirr: worker 200 parses into the same receipt the direct '
        'path would build', () async {
      Uri? seenUri;
      Map<String, String>? seenHeaders;
      String? seenBody;
      final res = await verifyViaGeoRelay(
        const VerifyInput(bankId: 'telebirr', reference: 'CHQ261Z4AB2C'),
        postFn: (uri, headers, body) async {
          seenUri = uri;
          seenHeaders = headers;
          seenBody = body;
          return RelayResponse(200, jsonEncode({
            'ok': true,
            'status': 200,
            'body': _telebirrHtml,
          }));
        },
      );
      expect(seenUri!.path, '/v1/relay');
      expect(seenHeaders!['X-Mahtem-Client'], isNotNull);
      final payload = jsonDecode(seenBody!) as Map<String, dynamic>;
      expect(payload['bank'], 'telebirr');
      expect(payload['url'],
          'https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C');

      expect(res, isNotNull);
      expect(res!.ok, isTrue);
      final r = res.receipt!;
      expect(r.bankCode, 'telebirr');
      expect(r.bankName, 'Telebirr');
      expect(r.reference, 'CHQ261Z4AB2C');
      expect(r.senderName, 'MOHAMMED A RESHID');
      expect(r.receiverName, 'SAMI CLOTHING');
      expect(r.amount, 2450.00);
      expect(r.date, '18-09-2026 14:22:10');
      expect(r.fromQr, isFalse);
    });

    test('M-Pesa: worker 200 parses; QR input keeps the fromQr note',
        () async {
      final res = await verifyViaGeoRelay(
        const VerifyInput(
            bankId: 'mpesa', reference: '', qrData: 'SJ72HK3YZ9'),
        postFn: (uri, headers, body) async {
          final payload = jsonDecode(body) as Map<String, dynamic>;
          expect(payload['url'], contains('trxNo=SJ72HK3YZ9'));
          return RelayResponse(200, jsonEncode({
            'ok': true,
            'status': 200,
            'body': _mpesaJson,
          }));
        },
      );
      expect(res, isNotNull);
      expect(res!.ok, isTrue);
      final r = res.receipt!;
      expect(r.bankCode, 'mpesa');
      expect(r.reference, 'SJ72HK3YZ9');
      expect(r.amount, 320.50);
      expect(r.fromQr, isTrue);
      expect(r.note, 'Scanned from the QR on the receipt.');
    });

    test('bank 404 maps to the engine’s not-found message', () async {
      final res = await verifyViaGeoRelay(
        const VerifyInput(bankId: 'telebirr', reference: 'CHQ261Z4AB2C'),
        postFn: (uri, headers, body) async =>
            RelayResponse(200, jsonEncode({'ok': true, 'status': 404, 'body': ''})),
      );
      expect(res, isNotNull);
      expect(res!.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
      expect(res.failure!.message, contains('not found'));
    });

    test('bank 200 with a non-receipt page maps to not-found', () async {
      final res = await verifyViaGeoRelay(
        const VerifyInput(bankId: 'telebirr', reference: 'CHQ261Z4AB2C'),
        postFn: (uri, headers, body) async => RelayResponse(
            200, jsonEncode({'ok': true, 'status': 200, 'body': '<html>error</html>'})),
      );
      expect(res, isNotNull);
      expect(res!.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.notFound);
      expect(res.failure!.message, contains('No receipt found'));
    });

    test('bank 5xx maps to a network failure, no retries', () async {
      var calls = 0;
      final res = await verifyViaGeoRelay(
        const VerifyInput(bankId: 'mpesa', reference: 'SJ72HK3YZ9'),
        postFn: (uri, headers, body) async {
          calls++;
          return RelayResponse(
              200, jsonEncode({'ok': true, 'status': 500, 'body': ''}));
        },
      );
      expect(calls, 1);
      expect(res, isNotNull);
      expect(res!.ok, isFalse);
      expect(res.failure!.kind, VerifyErrorKind.network);
      expect(res.failure!.message, contains('HTTP 500'));
    });

    test('relay infrastructure failures return null (fall back to direct)',
        () async {
      Future<VerifyResult?> run(RelayPostFn fn) => verifyViaGeoRelay(
          const VerifyInput(bankId: 'telebirr', reference: 'CHQ261Z4AB2C'),
          postFn: fn);

      // Worker unreachable / error status.
      expect(
        await run((u, h, b) async => RelayResponse(500, 'oops')),
        isNull,
      );
      // Worker-level error payload.
      expect(
        await run((u, h, b) async =>
            RelayResponse(200, jsonEncode({'error': 'relay_failed'}))),
        isNull,
      );
      // Malformed payload.
      expect(await run((u, h, b) async => RelayResponse(200, 'not json')),
          isNull);
      // Thrown network error.
      expect(await run((u, h, b) async => throw Exception('offline')), isNull);
    });

    test('unresolvable input returns null without calling the Worker',
        () async {
      var calls = 0;
      final res = await verifyViaGeoRelay(
        const VerifyInput(bankId: 'telebirr', reference: ''),
        postFn: (u, h, b) async {
          calls++;
          throw StateError('must not be called');
        },
      );
      expect(res, isNull);
      expect(calls, 0);
    });
  });
}
