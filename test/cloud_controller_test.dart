import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/auth/account.dart';
import 'package:mahtem/core/auth/password_hasher.dart';
import 'package:mahtem/core/cloud/cloud_api.dart';
import 'package:mahtem/core/cloud/cloud_keys.dart';
import 'package:mahtem/core/cloud/cloud_vault.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/cloud_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures/fake_cloud_server.dart';

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

Future<AccountRecord> _secondAccount(PasswordHasher hasher) async {
  final hash = await hasher.hash('other-pass');
  return AccountRecord(
    id: 'other@example.com',
    identifier: 'other@example.com',
    displayName: 'Other User',
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

/// Real-time polling helper. Each enable() attempt runs two 120k-iteration
/// PBKDF2 derivations which take seconds under the debug VM — fixed sleeps
/// cannot straddle a retry, so every retry test polls for its condition.
Future<bool> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return cond();
}

/// Tiny auto-sync windows so tests exercise the real timers quickly.
const _kDebounce = Duration(milliseconds: 30);
const _kRetry = Duration(milliseconds: 40);
const _kBackoff = Duration(milliseconds: 300);
const _kCatchUp = Duration(milliseconds: 10);
const _kArmDelay = Duration(milliseconds: 25);

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
      autoArmRetries: 3,
      autoArmRetryDelay: _kArmDelay,
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
    expect(base64Encode(base64Decode(blob)), blob);
    expect(() => jsonDecode(blob), throwsFormatException);

    // Decryption with the derived key yields exactly our history.
    final key = await deriveVaultKey('correct-horse', 'user@example.com');
    final plain = await decryptVaultBlob(key, blob);
    final entries = jsonDecode(plain)['entries'] as List;
    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry['id']), containsAll(['h1', 'h2']));

    // State persists for the next boot.
    expect(prefs.getBool('cloud.enabled'), isTrue);
    expect(prefs.getString('cloud.sessionToken'), isNotNull);
  });

  test('enable writes the account profile into the vault (v1.14.4)',
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

    final ok = await controller.enable(
      password: 'correct-horse',
      account: account,
      history: history,
    );
    expect(ok, isTrue);

    // The profile is inside the ENCRYPTED blob, never as plaintext.
    final blob = server.vaults.values.single['blob'] as String;
    expect(blob, isNot(contains('Test User')));
    final doc = decodeVaultDocument(
      await decryptVaultBlob(
        await deriveVaultKey('correct-horse', 'user@example.com'),
        blob,
      ),
    );
    expect(doc.account, isNotNull);
    expect(doc.account!.displayName, 'Test User');
    expect(doc.account!.identifier, 'user@example.com');

    // The profile persists so auto-sync keeps writing it after a reboot.
    expect(prefs.getString('cloud.accountProfile'), isNotNull);
    expect(prefs.getString('cloud.accountProfile')!, contains('Test User'));

    // Turning the backup off clears the stored profile too.
    await controller.disable();
    expect(prefs.getString('cloud.accountProfile'), isNull);
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

  test('a revision conflict re-reads and preserves concurrent cloud data',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _tuned(server, hasher, prefs, revisionClock: () => 21000);
    final history = VerifyHistory();
    await history.add(_entry('local-1', verifiedAt: 5000));
    await controller.enable(
      password: 'correct-horse',
      account: account,
      history: history,
    );

    final key = await deriveVaultKey('correct-horse', account.id);
    final existing = server.vaults.values.single;
    server.vaultBeforeNextPut = {
      'blob': await encryptVaultBlob(
        key,
        encodeVaultPayload([
          _entry('local-1', verifiedAt: 5000),
          _entry('concurrent-1', verifiedAt: 7000),
        ]),
      ),
      'revision': (existing['revision'] as int) + 1,
      'updatedAt': 22000,
    };
    await history.add(_entry('local-2', verifiedAt: 6000));

    expect(await controller.backupNow(history), isTrue);
    final merged = decodeVaultPayload(
      await decryptVaultBlob(key, server.vaults.values.single['blob'] as String),
    );
    expect(
      merged.map((entry) => entry.id),
      containsAll(['local-1', 'local-2', 'concurrent-1']),
    );
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

  test('boot catch-up pulls recent changes from another device', () async {
    final (first, _) = await _enabledSession(server, hasher, account);
    final key = await deriveVaultKey('correct-horse', account.id);
    server.vaults.values.single['blob'] = await encryptVaultBlob(
      key,
      encodeVaultPayload([_entry('from-other-device', verifiedAt: 9000)]),
    );

    final prefs = await SharedPreferences.getInstance();
    final second = _tuned(server, hasher, prefs);
    await second.ensureLoaded();
    final history = VerifyHistory();
    second.observe(history);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(history.entries.map((entry) => entry.id),
        contains('from-other-device'));
    first.dispose();
    second.dispose();
  });

  test('resuming the app pulls changes made on another device', () async {
    final (controller, history) = await _enabledSession(server, hasher, account);
    final key = await deriveVaultKey('correct-horse', account.id);
    server.vaults.values.single['blob'] = await encryptVaultBlob(
      key,
      encodeVaultPayload([_entry('from-resumed-device', verifiedAt: 9000)]),
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(history.entries.map((entry) => entry.id),
        contains('from-resumed-device'));
    controller.dispose();
  });

  test('unreadable remote vault is not overwritten by local history', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _tuned(server, hasher, prefs);
    final history = VerifyHistory();
    await history.add(_entry('local-safe', verifiedAt: 1000));
    await controller.enable(
      password: 'correct-horse',
      account: account,
      history: history,
    );
    server.vaults.values.single['blob'] = 'unreadable-ciphertext';

    expect(await controller.backupNow(history), isFalse);
    expect(controller.failure, CloudFailure.decrypt);
    expect(server.vaults.values.single['blob'], 'unreadable-ciphertext');
    controller.dispose();
  });

  // ------------------------------------------- auto-enable (v1.14.0)

  test('autoEnable arms backup at sign-up with no manual step', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _tuned(server, hasher, prefs,
        revisionClock: () => 70000);
    final history = VerifyHistory();
    await history.add(_entry('s1', verifiedAt: 100));

    await controller.autoEnable(
      password: 'correct-horse',
      account: account,
      history: history,
    );

    expect(controller.enabled, isTrue);
    expect(controller.failure, CloudFailure.none);
    expect(server.users, hasLength(1)); // cloud account created by itself
    expect(server.revisionBumps, 1); // first merge upload ran by itself
    expect(prefs.getBool('cloud.enabled'), isTrue);
  });

  test('sign-in on a new device restores cloud history automatically',
      () async {
    // Device 1 backs up one entry.
    SharedPreferences.setMockInitialValues({});
    final d1 = _tuned(server, hasher, await SharedPreferences.getInstance(),
        revisionClock: () => 80000);
    final h1 = VerifyHistory();
    await h1.add(_entry('from-phone-1', verifiedAt: 9000));
    await d1.enable(password: 'correct-horse', account: account, history: h1);

    // Device 2: no persisted state at all (fresh install), empty local
    // history — the user just signs in with the same credentials.
    final d2 = CloudController(
      api: CloudApi(client: server.client()),
      hasher: hasher,
      revisionClock: () => 81000,
      autoSyncDebounce: _kDebounce,
      autoSyncRetry: _kRetry,
      autoSyncBackoff: _kBackoff,
      bootCatchUpDelay: _kCatchUp,
    );
    final h2 = VerifyHistory();

    await d2.autoEnable(
      password: 'correct-horse',
      account: account,
      history: h2,
    );

    expect(d2.enabled, isTrue);
    expect(h2.entries.map((e) => e.id), contains('from-phone-1'),
        reason: 'the cloud copy must come down with no manual restore');
  });

  test('autoEnable refreshes remote history when this account already syncs',
      () async {
    final (controller, history) = await _enabledSession(server, hasher, account);
    final putsBefore = server.putAttempts;
    final usersBefore = server.users.length;
    final key = await deriveVaultKey('correct-horse', account.id);
    server.vaults.values.single['blob'] = await encryptVaultBlob(
      key,
      encodeVaultPayload([_entry('from-second-device', verifiedAt: 9000)]),
    );

    await controller.autoEnable(
      password: 'correct-horse',
      account: account,
      history: history,
    );

    expect(controller.enabled, isTrue);
    expect(server.putAttempts, putsBefore); // refresh must not upload/churn
    expect(server.users.length, usersBefore);
    expect(history.entries.map((entry) => entry.id),
      contains('from-second-device'));
  });

  test('autoEnable retries an offline sign-up and arms when the net returns',
      () async {
    final controller = _tuned(server, hasher,
        await SharedPreferences.getInstance(),
        revisionClock: () => 70000);
    final history = VerifyHistory();
    await history.add(_entry('n1'));

    // The sign-up lands while the phone cannot reach the worker at all.
    server.down = true;
    await controller.autoEnable(
      password: 'correct-horse',
      account: account,
      history: history,
    );
    expect(controller.enabled, isFalse);
    expect(controller.failure, CloudFailure.network);
    expect(server.users, isEmpty);

    // The connection returns while the retry window is still open — the
    // next scheduled attempt must arm with ZERO user action.
    server.down = false;
    final armed = await _waitFor(
      () => controller.enabled && !controller.isWorking,
    );
    expect(armed, isTrue,
        reason: 'the cloud account must be created by itself the moment '
            'the network returns');
    expect(controller.failure, CloudFailure.none);
    expect(server.users, hasLength(1));
    expect(controller.hasUnsyncedChanges, isFalse,
        reason: 'the pending local change rides along with the '
            'successful arm');
  });

  test('autoEnable retry window expires and drops the credentials', () async {
    final controller = _tuned(server, hasher,
        await SharedPreferences.getInstance());
    final history = VerifyHistory();
    await history.add(_entry('n2'));

    server.down = true;
    await controller.autoEnable(
      password: 'correct-horse',
      account: account,
      history: history,
    );

    // Every scheduled attempt hits the wire: initial + 3 retries.
    final allAttempts = await _waitFor(() => server.requests >= 4);
    expect(allAttempts, isTrue, reason: 'initial attempt + every retry '
        'must hit the wire while the window is open');

    // The window then closes for good — no growth once attempts settle.
    final settled = server.requests;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(server.requests, settled,
        reason: 'attempts stop once the window closes');
    expect(controller.enabled, isFalse);
    expect(controller.failure, CloudFailure.network);

    // Credentials are dropped: the network returning changes nothing.
    server.down = false;
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(server.requests, settled,
        reason: 'no further attempts after the window closed');
    expect(controller.enabled, isFalse);
  });

  test('a server-side credential rejection never retries (deterministic)',
      () async {
    final controller = _tuned(server, hasher,
        await SharedPreferences.getInstance());
    final history = VerifyHistory();
    await history.add(_entry('n3'));

    // The cloud account exists but was created with a DIFFERENT authKey —
    // session creation 401s → wrongPassword, a failure no retry can fix.
    final idHash = await cloudIdentifierHash(account.id);
    server.users[idHash] = {'id': 'u-foreign', 'authKey': 'deadbeef'};

    await controller.autoEnable(
      password: 'correct-horse',
      account: account,
      history: history,
    );
    expect(controller.enabled, isFalse);
    expect(controller.failure, CloudFailure.wrongPassword);
    expect(server.requests, 2,
        reason: 'exactly ONE attempt = lookup + session rejection; a '
            'deterministic 401 must NOT schedule retries');

    await Future<void>.delayed(const Duration(seconds: 1));
    expect(server.requests, 2,
        reason: 'still one attempt after several backoff windows');
    expect(controller.enabled, isFalse);
  });

  test('disable() cancels a pending auto-arm retry for good', () async {
    final controller = _tuned(server, hasher,
        await SharedPreferences.getInstance());
    final history = VerifyHistory();
    await history.add(_entry('n4'));

    server.down = true;
    await controller.autoEnable(
      password: 'correct-horse',
      account: account,
      history: history,
    );
    expect(controller.enabled, isFalse);

    await controller.disable();

    // Settle the entire window — whatever interleaving happened, disable
    // must stick and no retry may resurrect the connection.
    await Future<void>.delayed(const Duration(seconds: 2));
    server.down = false;
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(controller.enabled, isFalse,
        reason: 'a pending retry must never re-arm after disable');
    expect(server.users, isEmpty,
        reason: 'no cloud account may be created after disable');
  });

  test('account switch re-arms sync but leaves the old vault alone',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller = _tuned(server, hasher, await SharedPreferences.getInstance(),
        revisionClock: () => 90000);
    final history = VerifyHistory();
    await history.add(_entry('a1', verifiedAt: 100));
    await controller.autoEnable(
      password: 'correct-horse',
      account: account,
      history: history,
    );
    final firstVaultKeys = List.of(server.vaults.keys);

    final other = await _secondAccount(hasher);
    await controller.autoEnable(
      password: 'other-pass',
      account: other,
      history: history,
    );

    expect(controller.enabled, isTrue);
    expect(controller.failure, CloudFailure.none);
    expect(server.users, hasLength(2));
    expect(server.vaults.keys, containsAll(firstVaultKeys),
        reason: 'the previous account cloud copy must survive the switch');
    expect(server.vaults, hasLength(2)); // new account has its own vault
  });
}
