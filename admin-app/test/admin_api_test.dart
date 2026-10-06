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
  group('AdminApi.accountDetail', () {
    const detailBody = '''
{
  "id": "89da157c",
  "createdAt": 1791112376385,
  "revision": 1791116029043,
  "updatedAt": 1791116051918,
  "scans": 8,
  "verified": 6,
  "lastScanAt": 1791144000000,
  "banks": [
    {"id": "cbe", "name": "CBE", "count": 5, "verified": 5},
    {"id": "telebirr", "name": "Telebirr", "count": 2, "verified": 1}
  ],
  "days": [
    {"day": "2026-10-04", "count": 1},
    {"day": "2026-10-05", "count": 2}
  ],
  "events": [
    {"t": 1791144000000, "b": "cbe", "n": "CBE", "v": 1},
    {"t": 1791143900000, "b": "telebirr", "n": "Telebirr", "v": 0}
  ]
}
''';

    test('parses the drill-down document and hits the right path', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(detailBody, 200);
        }),
      );

      final detail = await api.accountDetail('a' * 32, '89DA157C');

      expect(captured.url.path, '/v1/admin/account/89da157c');
      expect(detail.id, '89da157c');
      expect(detail.scans, 8);
      expect(detail.verified, 6);
      expect(detail.banks.first.verified, 5);
      expect(detail.banks.last.count, 2);
      expect(detail.days.last.count, 2);
      expect(detail.events.first.bankName, 'CBE');
      expect(detail.events.first.verified, 1);
      expect(detail.events.last.verified, 0);
    });

    test('rejects malformed prefixes locally', () async {
      var called = false;
      final api = AdminApi(
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.accountDetail('a' * 32, 'xyz'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.badInput)),
      );
      expect(called, isFalse, reason: 'no network round-trip for bad input');
    });

    test('404 maps to notFound', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'not_found', 'message': 'No account matches this prefix.'}),
            404)),
      );
      await expectLater(
        api.accountDetail('a' * 32, '89da157c'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.notFound)
            .having((e) => e.status, 'status', 404)),
      );
    });

    test('401 maps to sessionExpired', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'admin_session_expired', 'message': 'Sign in again.'}),
            401)),
      );
      await expectLater(
        api.accountDetail('a' * 32, '89da157c'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.sessionExpired)),
      );
    });
  });

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

    test('401 maps to sessionExpired (overview rejects dead sessions)', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'admin_required', 'message': 'Invalid admin key.'}), 401),
        ),
      );
      await expectLater(
        api.overview('stale-token-1234567890'),
        throwsA(
          isA<AdminException>()
              .having((e) => e.type, 'type', AdminErrorType.sessionExpired)
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

  group('AdminApi.auth', () {
    test('hasAdmin() reads the status endpoint', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'hasAdmin': true}), 200);
        }),
      );

      expect(await api.hasAdmin(), isTrue);
      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/admin/auth/status');
      expect(captured.headers['X-Mahtem-Client'], 'mahtem-admin-app');
    });

    test('signIn() posts credentials and parses the session', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'ok': true,
              'token': 'tok-abc123',
              'email': 'owner@mahtem.app',
              'expiresAt': 1799000000000,
            }),
            200,
          );
        }),
      );

      final session = await api.signIn('Owner@Mahtem.App', 'long-pass-1234');

      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/admin/auth/login');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent['email'], 'Owner@Mahtem.App');
      expect(sent['password'], 'long-pass-1234');

      expect(session.token, 'tok-abc123');
      expect(session.email, 'owner@mahtem.app');
      expect(session.expiresAt, 1799000000000);
    });

    test('signIn() 401 bad_credentials maps to badCredentials', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'bad_credentials', 'message': 'Wrong email or password.'}),
            401)),
      );
      await expectLater(
        api.signIn('owner@mahtem.app', 'wrong'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.badCredentials)
            .having((e) => e.message, 'message', 'Wrong email or password.')),
      );
    });

    test('signIn() 429 maps to rateLimited', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'rate_limited'}), 429)),
      );
      await expectLater(
        api.signIn('owner@mahtem.app', 'whatever'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.rateLimited)),
      );
    });

    test('signIn() 404 no_admin maps to noAdmin', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'no_admin'}), 404)),
      );
      await expectLater(
        api.signIn('owner@mahtem.app', 'whatever'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.noAdmin)),
      );
    });

    test('signUpOwner() posts to setup; 409 maps to alreadyExists', () async {
      late http.Request captured;
      var call = 0;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          call++;
          if (call == 1) {
            return http.Response(
              jsonEncode({
                'ok': true,
                'token': 'tok-first',
                'email': 'me@mahtem.app',
                'expiresAt': 1799000000000,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'error': 'exists', 'message': 'An owner account already exists.'}),
            409,
          );
        }),
      );

      final session = await api.signUpOwner('me@mahtem.app', 'first-password-1');
      expect(captured.url.path, '/v1/admin/auth/setup');
      expect(session.token, 'tok-first');

      await expectLater(
        api.signUpOwner('someone@else.app', 'another-password'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.alreadyExists)),
      );
    });

    test('signUpOwner() 400 weak_password maps to badInput', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'weak_password', 'message': 'Password must be at least 10 characters.'}),
            400)),
      );
      await expectLater(
        api.signUpOwner('me@mahtem.app', 'short'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.badInput)),
      );
    });

    test('me() parses the profile; 401 maps to sessionExpired', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          if (captured.headers['Authorization'] == 'Bearer tok-live') {
            return http.Response(
              jsonEncode({'email': 'owner@mahtem.app', 'expiresAt': 1}),
              200,
            );
          }
          return http.Response(
            jsonEncode({'error': 'admin_session_expired'}),
            401,
          );
        }),
      );

      final me = await api.me('tok-live');
      expect(captured.url.path, '/v1/admin/auth/me');
      expect(me.email, 'owner@mahtem.app');

      await expectLater(
        api.me('tok-dead'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.sessionExpired)),
      );
    });

    test('logout() posts and accepts 200', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );

      await api.logout('tok-xyz');
      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/admin/auth/logout');
      expect(captured.headers['Authorization'], 'Bearer tok-xyz');
    });

    test('changePassword() posts and parses the rotated session', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'ok': true,
              'token': 'tok-rotated',
              'email': 'owner@mahtem.app',
              'expiresAt': 1799500000000,
            }),
            200,
          );
        }),
      );

      final session = await api.changePassword('tok-live', 'old-pass', 'new-pass-9876');
      expect(captured.url.path, '/v1/admin/auth/change-password');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent['currentPassword'], 'old-pass');
      expect(sent['newPassword'], 'new-pass-9876');
      expect(session.token, 'tok-rotated');
    });

    test('changePassword() 401 maps to badCredentials', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'bad_credentials', 'message': 'Current password is incorrect.'}),
            401)),
      );
      await expectLater(
        api.changePassword('tok-live', 'nope', 'new-pass-9876'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.badCredentials)),
      );
    });

    test('network failures map to network for auth endpoints too', () async {
      final api = AdminApi(
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      await expectLater(
        api.signIn('owner@mahtem.app', 'whatever'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.network)),
      );
    });
  });

  group('AdminApi.management', () {
    test('settings() parses the switches; updateSettings() PUTs only deltas',
        () async {
      late http.Request captured;
      var call = 0;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          call++;
          return http.Response(
            jsonEncode(call == 1
                ? {
                    'signupsEnabled': false,
                    'maintenanceMode': true,
                    'updatedAt': 1799000000000,
                    'updatedBy': 'owner@mahtem.app',
                  }
                : {
                    'signupsEnabled': true,
                    'maintenanceMode': false,
                    'updatedAt': 1799000001000,
                    'updatedBy': 'owner@mahtem.app',
                  }),
            200,
          );
        }),
      );

      final current = await api.settings('a' * 32);
      expect(captured.method, 'GET');
      expect(captured.url.path, '/v1/admin/settings');
      expect(current.signupsEnabled, isFalse);
      expect(current.maintenanceMode, isTrue);
      expect(current.updatedBy, 'owner@mahtem.app');

      final next = await api.updateSettings('a' * 32, signupsEnabled: true);
      expect(captured.method, 'PUT');
      expect(captured.url.path, '/v1/admin/settings');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent.keys, ['signupsEnabled'], reason: 'untouched switches are not sent');
      expect(sent['signupsEnabled'], isTrue);
      expect(next.signupsEnabled, isTrue);
      expect(next.maintenanceMode, isFalse);
    });

    test('updateSettings() 403 forbidden maps to the forbidden type',
        () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'forbidden', 'message': 'Only the owner account can do this.'}),
            403)),
      );
      await expectLater(
        api.updateSettings('a' * 32, maintenanceMode: true),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.forbidden)
            .having((e) => e.status, 'status', 403)),
      );
    });

    test('users() parses the owner and admin list', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'owner': {'email': 'owner@mahtem.app', 'createdAt': 1791112376385},
              'admins': [
                {'id': 'a1b2c3d4', 'email': 'helper@mahtem.app',
                 'createdAt': 1791200000000, 'createdBy': 'owner@mahtem.app'},
                'garbage',
              ],
            }),
            200)),
      );
      final doc = await api.users('a' * 32);
      expect(doc.ownerEmail, 'owner@mahtem.app');
      expect(doc.ownerCreatedAt, 1791112376385);
      expect(doc.admins, hasLength(1), reason: 'corrupt entries are skipped');
      expect(doc.admins.first.email, 'helper@mahtem.app');
      expect(doc.admins.first.createdBy, 'owner@mahtem.app');
    });

    test('addUser() posts to /users and accepts 201', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'id': 'a1b2c3d4',
              'email': 'helper@mahtem.app',
              'createdAt': 1791200000000,
              'createdBy': 'owner@mahtem.app',
            }),
            201,
          );
        }),
      );
      final user = await api.addUser('a' * 32, 'helper@mahtem.app', 'helper-pass-1');
      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/admin/users');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent['email'], 'helper@mahtem.app');
      expect(sent['password'], 'helper-pass-1');
      expect(user.id, 'a1b2c3d4');
    });

    test('resetUserPassword / removeUser hit their exact paths and methods',
        () async {
      final captured = <http.Request>[];
      final api = AdminApi(
        client: MockClient((request) async {
          captured.add(request);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      await api.resetUserPassword('a' * 32, 'a1b2c3d4', 'fresh-pass-99');
      await api.removeUser('a' * 32, 'a1b2c3d4');

      expect(captured[0].method, 'POST');
      expect(captured[0].url.path, '/v1/admin/users/a1b2c3d4/reset-password');
      final sent = jsonDecode(captured[0].body) as Map<String, dynamic>;
      expect(sent['newPassword'], 'fresh-pass-99');

      expect(captured[1].method, 'DELETE');
      expect(captured[1].url.path, '/v1/admin/users/a1b2c3d4');
    });

    test('announcements: list parses, create posts message+level at 201',
        () async {
      late http.Request captured;
      var call = 0;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          call++;
          return http.Response(
            call == 1
                ? jsonEncode({
                    'announcements': [
                      {'id': 'ann1', 'message': 'Service degraded',
                       'level': 'warn', 'active': true,
                       'createdAt': 1791200000000, 'createdBy': 'owner@mahtem.app'},
                      {'id': 'ann2', 'message': 'All clear', 'level': 'info',
                       'active': true, 'createdAt': 1791200001000},
                    ],
                  })
                : jsonEncode({
                    'id': 'ann3',
                    'message': 'Emergency maintenance',
                    'level': 'critical',
                    'active': true,
                    'createdAt': 1791200002000,
                    'createdBy': 'owner@mahtem.app',
                  }),
            call == 1 ? 200 : 201,
          );
        }),
      );

      final list = await api.announcements('a' * 32);
      expect(captured.url.path, '/v1/admin/announcements');
      expect(list, hasLength(2));
      expect(list.first.isWarn, isTrue);
      expect(list.first.message, 'Service degraded');
      expect(list.last.isCritical, isFalse);

      final created =
          await api.createAnnouncement('a' * 32, 'Emergency maintenance', 'critical');
      expect(captured.method, 'POST');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent['message'], 'Emergency maintenance');
      expect(sent['level'], 'critical');
      expect(created.isCritical, isTrue);
      expect(created.createdBy, 'owner@mahtem.app');
    });

    test('deleteAnnouncement() DELETEs the exact id path', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      await api.deleteAnnouncement('a' * 32, 'ann1');
      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/v1/admin/announcements/ann1');
    });

    test('audit() parses the trail (corrupt entries skipped)', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'entries': [
                {'t': 1791200000000, 'actor': 'owner@mahtem.app',
                 'action': 'account_suspended', 'target': '89da157c', 'detail': null},
                'garbage',
                {'t': 1791190000000, 'actor': 'owner@mahtem.app',
                 'action': 'settings_updated', 'target': null,
                 'detail': 'signups=on, maintenance=off'},
              ],
            }),
            200)),
      );
      final entries = await api.audit('a' * 32);
      expect(entries, hasLength(2));
      expect(entries.first.action, 'account_suspended');
      expect(entries.first.target, '89da157c');
      expect(entries.last.detail, contains('maintenance=off'));
    });

    test('setAccountSuspended() PATCHes the flag body', () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
              jsonEncode({'ok': true, 'id': '89da157c', 'suspended': true}),
              200);
        }),
      );
      await api.setAccountSuspended('a' * 32, '89DA157C', true);
      expect(captured.method, 'PATCH');
      expect(captured.url.path, '/v1/admin/account/89da157c');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent['suspended'], isTrue);
    });

    test('deleteAccount() DELETEs with the typed confirm and parses the wipe',
        () async {
      late http.Request captured;
      final api = AdminApi(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'ok': true,
              'id': '89da157c',
              'userRemoved': true,
              'sessions': 3,
              'refreshTokens': 2,
            }),
            200,
          );
        }),
      );
      final result = await api.deleteAccount('a' * 32, '89da157c', '89DA157C');
      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/v1/admin/account/89da157c');
      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent['confirm'], '89da157c', reason: 'confirm is lowercased to the prefix');
      expect(result.userRemoved, isTrue);
      expect(result.sessions, 3);
      expect(result.refreshTokens, 2);
    });

    test('deleteAccount() 400 confirm_required maps to badInput', () async {
      final api = AdminApi(
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'confirm_required', 'message': 'Type "89da157c" in the confirm field.'}),
            400)),
      );
      await expectLater(
        api.deleteAccount('a' * 32, '89da157c', 'nope'),
        throwsA(isA<AdminException>()
            .having((e) => e.type, 'type', AdminErrorType.badInput)),
      );
    });
  });
}
