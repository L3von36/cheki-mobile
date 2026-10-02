import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mahtem/core/auth/account.dart';
import 'package:mahtem/core/auth/password_hasher.dart';
import 'package:mahtem/core/cloud/cloud_api.dart';
import 'package:mahtem/core/cloud/cloud_keys.dart';
import 'package:mahtem/core/cloud/cloud_vault.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/cloud_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory twin of the deployed mahtem-api Worker: accounts, sessions
/// and vaults with the same routes and status codes the real server uses.
class FakeCloudServer {
  final users = <String, Map<String, dynamic>>{};
  final vaults = <String, Map<String, dynamic>>{};
  int revisionBumps = 0;

  http.Client client() => MockClient((request) async {
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
          return http.Response(jsonEncode({
            'sessionToken': 'tok-${user['id']}',
            'userId': user['id'],
            'expiresAt': 9999999999999,
          }), 200);
        }
        if (request.method == 'GET' && path == '/v1/vault') {
          final v = vaults[_uid(request)];
          if (v == null) return http.Response(jsonEncode({'error': 'empty'}), 404);
          return http.Response(jsonEncode(v), 200);
        }
        if (request.method == 'PUT' && path == '/v1/vault') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final existing = vaults[_uid(request)];
          if (existing != null &&
              body['baseRevision'] != null &&
              (existing['revision'] as int) > (body['baseRevision'] as int)) {
            return http.Response(jsonEncode({
              'error': 'conflict',
              'revision': existing['revision'],
            }), 409);
          }
          revisionBumps++;
          vaults[_uid(request)] = body;
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.method == 'DELETE' && path == '/v1/vault') {
          vaults.remove(_uid(request));
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        if (request.method == 'DELETE' && path == '/v1/session') {
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

Future<AccountRecord> _account(PasswordHasher hasher) async {
  final hash = await hasher.hash('correct-horse');
  return AccountRecord(
    id: 'user@example.com',
    identifier: 'user@example.com',
    displayName: 'Test User',
    passwordHash: hash.encode(),
    createdAtUtc: DateTime(2026),
  );
}

HistoryEntry _entry(String id, {int verifiedAt = 1000}) => HistoryEntry(
      id: id,
      bankId: 'cbe',
      bankName: 'CBE',
      reference: 'FT$id',
      verifiedAt: verifiedAt,
      status: 'verified',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCloudServer server;
  late PasswordHasher hasher;
  late AccountRecord account;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = FakeCloudServer();
    hasher = PasswordHasher(iterations: 1000);
    account = await _account(hasher);
  });

  test('wrong password fails locally without any network call', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
    );
    final history = VerifyHistory();
    await history.add(_entry('h1'));

    final ok = await controller.enable(
      password: 'wrong-password',
      account: account,
      history: history,
    );

    expect(ok, isFalse);
    expect(controller.failure, CloudFailure.wrongPassword);
    expect(controller.enabled, isFalse);
    expect(server.users, isEmpty); // no cloud account created
  });

  test('enable creates cloud account, uploads encrypted merge, persists',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
      revisionClock: () => 12345,
    );
    final history = VerifyHistory();
    await history.add(_entry('h1'));
    await history.add(_entry('h2'));

    final ok = await controller.enable(
      password: 'correct-horse',
      account: account,
      history: history,
    );

    expect(ok, isTrue);
    expect(controller.enabled, isTrue);
    expect(controller.failure, CloudFailure.none);
    expect(server.users, hasLength(1));

    // Vault content is ENCRYPTED — the fake server only ever sees a blob.
    final stored = server.vaults.values.single;
    final blob = stored['blob'] as String;
    expect(blob, isNot(contains('FT')));
    expect(blob.length, greaterThan(16));

    // Decryption with the derived key yields exactly our history.
    final key = await deriveVaultKey('correct-horse', 'user@example.com');
    final plain = await decryptVaultBlob(key, blob);
    final entries = jsonDecode(plain)['entries'] as List;
    expect(entries, hasLength(2));

    // State persists for the next boot.
    expect(prefs.getBool('cloud.enabled'), isTrue);
    expect(prefs.getString('cloud.sessionToken'), isNotNull);
  });

  test('backupNow merges remote + local and uploads the union', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
      revisionClock: () => 20000,
    );
    final history = VerifyHistory();
    await history.add(_entry('h1', verifiedAt: 5000));

    await controller.enable(
      password: 'correct-horse',
      account: account,
      history: history,
    );

    // Simulate another device's backup: craft a vault with a distinct id
    // but different signature so the merge keeps both.
    final key = await deriveVaultKey('correct-horse', 'user@example.com');
    final otherDevice = encodeVaultPayload([
      HistoryEntry(
        id: 'other-device-1',
        bankId: 'telebirr',
        bankName: 'telebirr',
        reference: 'CHQ999',
        verifiedAt: 8000,
        status: 'verified',
      ),
    ]);
    final serverVault = server.vaults.values.single;
    final baseRevision = serverVault['revision'] as int;
    serverVault['blob'] = await encryptVaultBlob(key, otherDevice);

    await history.add(_entry('h2', verifiedAt: 6000));
    final ok = await controller.backupNow(history);

    expect(ok, isTrue);
    expect(controller.lastSyncAt, isNotNull);
    final merged = decodeVaultPayload(
      await decryptVaultBlob(key, server.vaults.values.single['blob'] as String),
    );
    expect(merged, hasLength(3)); // h1 + h2 + other-device-1
    expect(merged.first.id, 'other-device-1'); // newest first
    // The optimistic baseRevision path was exercised (no blind writes).
    expect(server.revisionBumps, 2);
    expect(baseRevision, greaterThan(0));
  });

  test('restore merges cloud entries into local history', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
      revisionClock: () => 30000,
    );
    final history = VerifyHistory();
    await history.add(_entry('h1', verifiedAt: 1000));

    await controller.enable(
      password: 'correct-horse',
      account: account,
      history: history,
    );

    // Push a foreign vault onto the server (as if from another device).
    final key = await deriveVaultKey('correct-horse', 'user@example.com');
    final remoteVault = server.vaults.values.single;
    remoteVault['blob'] = await encryptVaultBlob(
      key,
      encodeVaultPayload([_entry('remote-1', verifiedAt: 9000)]),
    );

    final added = await controller.restore(history);
    expect(added, 1);
    expect(history.entries.map((e) => e.id), containsAll(['h1', 'remote-1']));
    expect(history.entries.first.id, 'remote-1'); // newest first

    // Restoring again adds nothing (id dedupe).
    expect(await controller.restore(history), 0);
  });

  test('disable deletes the cloud copy and clears local state', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
      revisionClock: () => 40000,
    );
    final history = VerifyHistory();
    await controller.enable(
      password: 'correct-horse',
      account: account,
      history: history,
    );
    expect(server.vaults, hasLength(1));

    await controller.disable();

    expect(controller.enabled, isFalse);
    expect(server.vaults, isEmpty); // cloud copy deleted
    expect(prefs.getBool('cloud.enabled'), isFalse);
    expect(prefs.getString('cloud.sessionToken'), isNull);
  });

  test('enable is idempotent across boots via ensureLoaded', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
      revisionClock: () => 50000,
    );
    await first.enable(
      password: 'correct-horse',
      account: account,
      history: VerifyHistory(),
    );

    final second = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
    );
    await second.ensureLoaded();
    expect(second.enabled, isTrue);
    expect(second.hasSession, isTrue);
  });
}
