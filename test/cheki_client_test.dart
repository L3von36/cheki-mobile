import 'dart:convert';

import 'package:cheki_mobile/core/cheki_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ChekiClient.verify', () {
    test('returns parsed result on success', () async {
      final client = ChekiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/verify');
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['bank'], 'cbe');
          expect(body['reference'], 'FT26140P01YB');
          expect(body['accountNumber'], '60536171');
          return http.Response(
            jsonEncode({
              'success': true,
              'verified': true,
              'bank': 'cbe',
              'reference': 'FT26140P01YB',
              'amount': 20000.0,
              'currency': 'ETB',
              'senderName': 'Mr Mohammed',
              'receiverName': 'SAMI ADIL ZEKARIA',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.verify(
        bank: 'cbe',
        reference: 'FT26140P01YB',
        accountNumber: '60536171',
      );
      expect(result.success, isTrue);
      expect(result.isVerified, isTrue);
      expect(result.amount, 20000.0);
      expect(result.senderName, 'Mr Mohammed');
      client.close();
    });

    test('retries on 502 then succeeds', () async {
      var attempts = 0;
      final client = ChekiClient(
        client: MockClient((request) async {
          attempts++;
          if (attempts < 3) {
            return http.Response('{"success":false,"error":"bad gateway"}', 502);
          }
          return http.Response(
            jsonEncode({'success': true, 'verified': true, 'amount': 5}),
            200,
          );
        }),
      );

      final result = await client.verify(bank: 'dashen', reference: 'D1');
      expect(attempts, 3);
      expect(result.isVerified, isTrue);
      client.close();
    });

    test('throws ChekiException with API error on 400', () async {
      final client = ChekiClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'success': false,
              'error': 'Receipt not found. Check the reference number.',
            }),
            404,
          );
        }),
      );

      await expectLater(
        client.verify(bank: 'cbe', reference: 'FT000'),
        throwsA(
          isA<ChekiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('not found')),
        ),
      );
      client.close();
    });

    test('omits empty account/phone fields from the payload', () async {
      String? capturedBody;
      final client = ChekiClient(
        client: MockClient((request) async {
          capturedBody = request.body;
          return http.Response(
            jsonEncode({'success': true, 'verified': false}),
            200,
          );
        }),
      );

      await client.verify(bank: 'telebirr', reference: 'DET8FJGUJ4');
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body.containsKey('accountNumber'), isFalse);
      expect(body.containsKey('phoneNumber'), isFalse);
      client.close();
    });
  });

  group('ChekiClient.receiptUrl', () {
    test('builds the public receipt URL', () {
      final client = ChekiClient();
      expect(
        client.receiptUrl('cbe', 'FT26140P01YB'),
        'https://chekiapp.vercel.app/receipt/cbe/FT26140P01YB',
      );
      client.close();
    });
  });
}
