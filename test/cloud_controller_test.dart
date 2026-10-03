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
  int putAttempts = 0; // every vault PUT, successful or not
  bool failVaultPut = false; // 500 on vault writes
  bool unauthorizedVault = false; // 401 on vault writes

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
          putAttempts++;
          if (unauthorizedVault) {
            return http.Response(jsonEncode({'error': 'unauthorized'}), 401);
          }
          if (failVaultPut) {
            return http.Response(jsonEncode({'error': 'internal'}), 500);
          }
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

/// Tiny auto-sync windows so tests exercise the real timers quickly.
const _kDebounce = Duration(milliseconds: 30);
const _kRetry = Duration(milliseconds: 40);
const _kBackoff = Duration(milliseconds: 300);
const _kCatchUp = Duration(milliseconds: 10);

CloudController _tuned(FakeCloudServer server, PasswordHasher hasher,
        SharedPreferences prefs,
        {int Function()? revisionClock}) =>
    CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      prefs: prefs,
      revisionClock: revisionClock,
      autoSyncDebounce: _kDebounce,
      autoSyncRetry: _kRetry,
      autoSyncBackoff: _kBackoff,
      bootCatchUpDelay: _kCatchUp,
    );

Future<(CloudController, VerifyHistory)> _enabledSession(
    FakeCloudServer server, PasswordHasher hasher, AccountRecord account,
    {int revision = 60000}) async {
  final prefs = await SharedPreferences.getInstance();
  final controller = _tuned(server, hasher, prefs,
      revisionClock: () => revision);
  final history = VerifyHistory();
  await controller.enable(
    password: 'correct-horse',
    account: account,
    history: history,
  );
  controller.observe(history);
  return (controller, history);
}

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

  // ------------------------------------------- auto-sync (v1.13.1)

  test('auto-syncs a change after the debounce window', () async {
    final (controller, history) = await _enabledSession(server, hasher, account);
    expect(server.revisionBumps, 1); // the enable-time upload
    expect(controller.hasUnsyncedChanges, isFalse);

    await history.add(_entry('auto-1', verifiedAt: 2000));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(server.revisionBumps, 2); // pushed by itself
    expect(controller.hasUnsyncedChanges, isFalse);
    final key = await deriveVaultKey('correct-horse', 'user@example.com');
    final merged = decodeVaultPayload(await decryptVaultBlob(
        key, server.vaults.values.single['blob'] as String));
    expect(merged.map((e) => e.id), contains('auto-1'));
  });

  test('coalesces a burst of changes into a single upload', () async {
    final (controller, history) = await _enabledSession(server, hasher, account);
    for (var i = 0; i < 10; i++) {
      await history.add(_entry('b$i', verifiedAt: 3000 + i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(controller.hasUnsyncedChanges, isFalse);
    expect(server.putAttempts, 2); // enable + exactly one auto push
  });

  test('toggle off pauses pushes; toggling on flushes pending changes',
      () async {
    final (controller, history) = await _enabledSession(server, hasher, account);

    await controller.setAutoSync(false);
    await history.add(_entry('paused-1', verifiedAt: 4000));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(server.putAttempts, 1); // nothing pushed while paused
    expect(controller.hasUnsyncedChanges, isTrue); // but flagged

    await controller.setAutoSync(true);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(server.putAttempts, 2); // pending change flushed
    expect(controller.hasUnsyncedChanges, isFalse);
  });

  test('auto-sync retries, then backs off, then recovers', () async {
    final (controller, history) = await _enabledSession(server, hasher, account);
    server.failVaultPut = true;

    await history.add(_entry('f1', verifiedAt: 5000));
    // attempt 1 after debounce, attempts 2+3 after retry windows
    await Future<void>.delayed(const Duration(milliseconds: 160));
    expect(server.putAttempts, 4); // enable + 3 failed auto attempts
    expect(controller.hasUnsyncedChanges, isTrue);
    expect(controller.failure, CloudFailure.server);

    // Inside the backoff window further changes stay local.
    await history.add(_entry('f2', verifiedAt: 5100));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(server.putAttempts, 4);

    // Server recovers and the backoff elapses — the push lands.
    server.failVaultPut = false;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(server.putAttempts, 5);
    expect(controller.hasUnsyncedChanges, isFalse);
  });

  test('expired session stops auto-sync until re-enable', () async {
    final (controller, history) = await _enabledSession(server, hasher, account);
    server.unauthorizedVault = true;

    await history.add(_entry('x1', verifiedAt: 6000));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.enabled, isFalse);
    expect(controller.failure, CloudFailure.sessionExpired);
    final deadAttempts = server.putAttempts;

    await history.add(_entry('x2', verifiedAt: 6100));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(server.putAttempts, deadAttempts); // no pushes while dead
  });

  test('boot catch-up pushes changes lost mid-debounce', () async {
    final (first, history) = await _enabledSession(server, hasher, account);
    await history.add(_entry('lost-1', verifiedAt: 7000));
    first.dispose(); // app dies before the debounce window elapses

    // Next boot: same prefs, fresh controller over the same server.
    final prefs = await SharedPreferences.getInstance();
    final second = _tuned(server, hasher, prefs);
    await second.ensureLoaded();
    second.observe(history);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(server.revisionBumps, 2); // enable + catch-up push
    expect(second.hasUnsyncedChanges, isFalse);
    final key = await deriveVaultKey('correct-horse', 'user@example.com');
    final merged = decodeVaultPayload(await decryptVaultBlob(
        key, server.vaults.values.single['blob'] as String));
    expect(merged.map((e) => e.id), contains('lost-1'));
  });
}
