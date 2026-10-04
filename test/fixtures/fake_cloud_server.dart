import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory twin of the deployed mahtem-api Worker: accounts, sessions
/// and vaults with the same routes and status codes the real server uses.
/// Shared by the cloud controller and cloud account directory tests.
class FakeCloudServer {
  final users = <String, Map<String, dynamic>>{};
  final vaults = <String, Map<String, dynamic>>{};
  int revisionBumps = 0;
  int putAttempts = 0; // every vault PUT, successful or not
  int requests = 0; // every request that reached the client at all
  int sessionDeletes = 0; // hygiene: throwaway sessions dropped
  int refreshCalls = 0; // /v1/session/refresh hits
  bool failVaultPut = false; // 500 on vault writes
  bool unauthorizedVault = false; // 401 on vault writes
  bool down = false; // when true the network itself is unreachable
  Map<String, dynamic>? vaultBeforeNextPut;

  /// Access-token expiry handed out by /v1/session (ms epoch).
  int sessionExpiresAt = 9999999999999;

  /// When true, /v1/session/refresh answers 401 invalid_grant.
  bool rejectRefresh = false;

  /// refresh token -> userId; rotated on every refresh.
  final Map<String, String> refreshTokens = {};

  /// The most recent vault PUT body that reached the server.
  Map<String, dynamic>? lastVaultPut;

  http.Client client() => MockClient((request) async {
        requests++;
        if (down) throw http.ClientException('offline');
        final path = request.url.path;
        if (request.method == 'POST' && path == '/v1/accounts') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final idh = body['identifierHash'] as String;
          if (users.containsKey(idh)) {
            return http.Response(jsonEncode({'error': 'exists'}), 409);
          }
          users[idh] = {
            'id': 'u-${users.length}',
            'authKey': body['authKey'],
          };
          return http.Response(jsonEncode({'userId': users[idh]!['id']}), 201);
        }
        if (request.method == 'POST' && path == '/v1/accounts/lookup') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
              jsonEncode({'exists': users.containsKey(body['identifierHash'])}),
              200);
        }
        if (request.method == 'POST' && path == '/v1/session') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final user = users[body['identifierHash'] as String];
          if (user == null) {
            return http.Response(jsonEncode({'error': 'no_account'}), 404);
          }
          if (user['authKey'] != body['authKey']) {
            return http.Response(jsonEncode({'error': 'bad_credentials'}), 401);
          }
          final refresh = 'ref-${user['id']}-${refreshTokens.length}';
          refreshTokens[refresh] = user['id'] as String;
          return http.Response(jsonEncode({
            'sessionToken': 'tok-${user['id']}',
            'refreshToken': refresh,
            'userId': user['id'],
            'expiresAt': sessionExpiresAt,
          }), 200);
        }
        if (request.method == 'POST' && path == '/v1/session/refresh') {
          refreshCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final token = body['refreshToken'] as String?;
          final uid = refreshTokens[token];
          if (rejectRefresh || token == null || uid == null) {
            refreshTokens.remove(token);
            return http.Response(
                jsonEncode({'error': 'invalid_grant'}), 401);
          }
          // Single-use rotation: burn the old grant, issue a fresh pair.
          refreshTokens.remove(token);
          final refresh = 'ref-$uid-${refreshTokens.length}';
          refreshTokens[refresh] = uid;
          return http.Response(jsonEncode({
            'accessToken': 'tok-$uid',
            'refreshToken': refresh,
            'sessionToken': 'tok-$uid',
            'userId': uid,
            'expiresAt': 9999999999999,
          }), 200);
        }
        if (request.method == 'GET' && path == '/v1/vault') {
          final v = vaults[_uid(request)];
          if (v == null) return http.Response(jsonEncode({'error': 'empty'}), 404);
          final since = request.url.queryParameters['sinceRevision'];
          if (since != null && int.tryParse(since) == v['revision']) {
            return http.Response(
                jsonEncode({'notModified': true, 'revision': v['revision']}), 200);
          }
          return http.Response(jsonEncode(v), 200);
        }
        if (request.method == 'PUT' && path == '/v1/vault') {
          putAttempts++;
          final parsed = jsonDecode(request.body) as Map<String, dynamic>;
          lastVaultPut = parsed;
          if (unauthorizedVault) {
            return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
          }
          if (failVaultPut) {
            return http.Response(jsonEncode({'error': 'internal'}), 500);
          }
          final body = parsed;
          final uid = _uid(request);
          final concurrentVault = vaultBeforeNextPut;
          if (concurrentVault != null) {
            vaults[uid] = concurrentVault;
            vaultBeforeNextPut = null;
            revisionBumps++;
          }
          final existing = vaults[uid];
          if (existing != null &&
              body['baseRevision'] != null &&
              (existing['revision'] as int) > (body['baseRevision'] as int)) {
            return http.Response(jsonEncode({
              'error': 'conflict',
              'revision': existing['revision'],
            }), 409);
          }
          revisionBumps++;
          vaults[uid] = body;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.method == 'DELETE' && path == '/v1/vault') {
          vaults.remove(_uid(request));
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.method == 'DELETE' && path == '/v1/session') {
          sessionDeletes++;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response(jsonEncode({'error': 'not_found'}), 404);
      });

  final Map<String, String> _tokens = {};
  String _uid(http.Request request) {
    final token =
        (request.headers['Authorization'] ?? '').replaceAll('Bearer ', '');
    return _tokens.putIfAbsent(token, () => token.replaceAll('tok-', 'u-'));
  }
}
