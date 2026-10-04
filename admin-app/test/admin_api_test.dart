import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mahtem_admin/admin_api.dart';

const _validBody = '''
{
  "generatedAt": 1791144413801,
  "totals": {
    "accounts": 19, "vaults": 10, "scans": 42, "verified": 35,
    "scansToday": 3, "scans7d": 17, "scanningAccounts7d": 5
  },
  "banks": [
    {"id": "cbe", "name": "Commercial Bank of Ethiopia", "count": 20},
    {"id": "telebirr", "name": "Telebirr", "count": 12}
  ],
  "days": [
    {"day": "2026-10-03", "count": 7},
    {"day": "2026-10-04", "count": 3}
  ],
  "accounts": [
    {"id": "0c2be7ce", "createdAt": 1791112376385, "revision": 1791116029043,
     "updatedAt": 1791116051918, "scans": 9, "lastScanAt": 1791144000000,
     "topBank": "Telebirr"},
    {"id": "1a972d49", "createdAt": null, "revision": null, "updatedAt": null,
     "scans": 0, "lastScanAt": null, "topBank": null}
  ],
  "recent": [
    {"t": 1791144000000, "b": "cbe", "n": "CBE", "v": 1, "u": "0c2be7ce"},
    {"t": 1791143900000, "b": "telebirr", "n": "Telebirr", "v": 0, "u": "1a972d49"}
  ]
}
''';

void main() {
  group('AdminApi.overview', () {
    test('parses the full overview document and sends the right headers', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(_validBody, 200);
        }),
      );

      final overview = await api.overview('a' * 32);

      expect(captured.method, 'GET');
      expect(captured.url.host, 'mahtem-api.mahtem.workers.dev');
      expect(captured.url.path, '/v1/admin/overview');
      expect(captured.headers['Authorization'], 'Bearer ${'a' * 32}');
      expect(captured.headers['X-Mahtem-Client'], 'mahtem-admin-app');

      expect(overview.generatedAt, 1791144413801);
      expect(overview.totals.accounts, 19);
      expect(overview.totals.vaults, 10);
      expect(overview.totals.scans, 42);
      expect(overview.totals.verified, 35);
      expect(overview.totals.scansToday, 3);
      expect(overview.totals.scans7d, 17);
      expect(overview.totals.scanningAccounts7d, 5);
      expect(overview.banks.length, 2);
      expect(overview.banks.first.name, 'Commercial Bank of Ethiopia');
      expect(overview.banks.first.count, 20);
      expect(overview.days.length, 2);
      expect(overview.days.last.day, '2026-10-04');
      expect(overview.days.last.count, 3);
      expect(overview.accounts.length, 2);
      expect(overview.accounts.first.id, '0c2be7ce');
      expect(overview.accounts.first.scans, 9);
      expect(overview.accounts.first.topBank, 'Telebirr');
      expect(overview.accounts.last.createdAt, isNull);
      expect(overview.accounts.last.topBank, isNull);
      expect(overview.recent.length, 2);
      expect(overview.recent.first.verified, 1);
      expect(overview.recent.last.verified, 0);
      expect(overview.recent.last.userId, '1a972d49');
    });

    test('401 maps to badKey', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'admin_required', 'message': 'Invalid admin key.'}), 401),
        ),
      );
      await expectLater(
        api.overview('wrong-key-value-123456'),
        throwsA(
          isA<AdminException>()
              .having((e) => e.type, 'type', AdminErrorType.badKey)
              .having((e) => e.status, 'status', 401),
        ),
      );
    });

    test('503 maps to disabled', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'admin_disabled'}), 503),
        ),
      );
      await expectLater(
        api.overview('a' * 32),
        throwsA(
          isA<AdminException>()
              .having((e) => e.type, 'type', AdminErrorType.disabled)
              .having((e) => e.status, 'status', 503),
        ),
      );
    });

    test('500 maps to server', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      await expectLater(
        api.overview('a' * 32),
        throwsA(
          isA<AdminException>()
              .having((e) => e.type, 'type', AdminErrorType.server)
              .having((e) => e.status, 'status', 500),
        ),
      );
    });

    test('non-JSON 200 maps to invalidResponse', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response('<html>gateway</html>', 200)),
      );
      await expectLater(
        api.overview('a' * 32),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.invalidResponse)),
      );
    });

    test('unexpected 200 shape maps to invalidResponse', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(jsonEncode({'nope': 1}), 200)),
      );
      await expectLater(
        api.overview('a' * 32),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.invalidResponse)),
      );
    });

    test('socket failure maps to network', () async {
      final api = AdminApi(
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      await expectLater(
        api.overview('a' * 32),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.network)),
      );
    });

    test('corrupt entries inside lists are skipped, not fatal', () async {
      final body = jsonEncode({
        'generatedAt': 1,
        'totals': {
          'accounts': 2, 'vaults': 1, 'scans': 1, 'verified': 1,
          'scansToday': 0, 'scans7d': 1, 'scanningAccounts7d': 1,
        },
        'banks': [
          {'id': 'cbe', 'name': 'CBE', 'count': 1},
          'garbage',
        ],
        'days': [
          {'day': '2026-10-04', 'count': 1},
          42,
        ],
        'accounts': [
          {'id': '0c2be7ce', 'createdAt': null, 'revision': null,
           'updatedAt': null, 'scans': 1, 'lastScanAt': null, 'topBank': null},
        ],
        'recent': [
          {'t': 1, 'b': 'cbe', 'n': 'CBE', 'v': 1, 'u': '0c2be7ce'},
        ],
      });
      final api = AdminApi(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      final overview = await api.overview('a' * 32);
      expect(overview.banks.length, 1);
      expect(overview.days.length, 1);
      expect(overview.accounts.length, 1);
      expect(overview.recent.length, 1);
    });
  });
}
