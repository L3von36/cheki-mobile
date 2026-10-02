import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mahtem/core/cloud/cloud_api.dart';

final String _idh = 'a' * 64;
final String _auth = 'b' * 64;

void main() {
  test('createAccount + session + vault round-trip against a fake server',
      () async {
    final vaults = <String, Map<String, dynamic>>{};
    final client = MockClient((request) async {
      expect(request.headers['X-Mahtem-Client'], isNotNull);
      if (request.url.path == '/v1/accounts' && request.method == 'POST') {
        return http.Response(
            jsonEncode({'userId': 'u1', 'createdAt': 1}), 201);
      }
      if (request.url.path == '/v1/session' && request.method == 'POST') {
        return http.Response(jsonEncode({
          'sessionToken': 'tok-1',
          'userId': 'u1',
          'expiresAt': 9999999999999,
        }), 200);
      }
      if (request.url.path == '/v1/vault' && request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        vaults['u1'] = body;
        return http.Response(
            jsonEncode({'ok': true, 'revision': body['revision']}), 200);
      }
      if (request.url.path == '/v1/vault' && request.method == 'GET') {
        final v = vaults['u1'];
        if (v == null) return http.Response(jsonEncode({'error': 'empty'}), 404);
        return http.Response(jsonEncode(v), 200);
      }
      return http.Response(jsonEncode({'error': 'not_found'}), 404);
    });

    final api = CloudApi(client: client);
    await api.createAccount(identifierHash: _idh, authKey: _auth);
    final session = await api.createSession(
      identifierHash: _idh,
      authKey: _auth,
    );
    expect(session.sessionToken, 'tok-1');
    expect(session.userId, 'u1');

    await api.putVault(
      sessionToken: session.sessionToken,
      blob: 'QUJD',
      revision: 42,
    );
    final vault = await api.getVault(session.sessionToken);
    expect(vault, isNotNull);
    expect(vault!.blob, 'QUJD');
    expect(vault.revision, 42);
  });

  test('getVault returns null on empty', () async {
    final api = CloudApi(
      client: MockClient((request) async =>
          http.Response(jsonEncode({'error': 'empty'}), 404)),
    );
    expect(await api.getVault('tok'), isNull);
  });

  test('conflict carries the server revision', () async {
    final api = CloudApi(
      client: MockClient((request) async => http.Response(
          jsonEncode({'error': 'conflict', 'revision': 77}), 409)),
    );
    try {
      await api.putVault(sessionToken: 't', blob: 'x1xxxxxxxxxxxxx', revision: 1);
      fail('should have thrown');
    } on CloudApiException catch (e) {
      expect(e.error, CloudApiError.conflict);
      expect(e.serverRevision, 77);
    }
  });

  test('error mapping: bad_credentials → 401', () async {
    final api = CloudApi(
      client: MockClient((request) async =>
          http.Response(jsonEncode({'error': 'bad_credentials'}), 401)),
    );
    try {
      await api.createSession(identifierHash: _idh, authKey: _auth);
      fail('should have thrown');
    } on CloudApiException catch (e) {
      expect(e.error, CloudApiError.badCredentials);
      expect(e.statusCode, 401);
    }
  });

  test('network failure maps to CloudApiError.network', () async {
    final api = CloudApi(
      client: MockClient((request) async => throw Exception('offline')),
    );
    try {
      await api.checkSession('tok');
      fail('should have thrown');
    } on CloudApiException catch (e) {
      expect(e.error, CloudApiError.network);
    }
  });

  test('checkSession distinguishes valid vs unauthorized', () async {
    var status = 200;
    final api = CloudApi(
      client: MockClient((request) async =>
          http.Response(jsonEncode({'ok': true}), status)),
    );
    expect(await api.checkSession('t'), isTrue);

    status = 401;
    expect(await api.checkSession('t'), isFalse);
  });

  test('lookupAccount parses exists flag', () async {
    var exists = false;
    final api = CloudApi(
      client: MockClient((request) async =>
          http.Response(jsonEncode({'exists': exists}), 200)),
    );
    expect(await api.lookupAccount(identifierHash: _idh), isFalse);

    exists = true;
    expect(await api.lookupAccount(identifierHash: _idh), isTrue);
  });

  test('client header is always sent', () async {
    String? header;
    final api = CloudApi(
      client: MockClient((request) async {
        header = request.headers['X-Mahtem-Client'];
        return http.Response(jsonEncode({}), 200);
      }),
    );
    await api.deleteSession('t');
    expect(header, 'mahtem-android');
  });
}
