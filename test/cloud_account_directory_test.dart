import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/auth/remote_account.dart';
import 'package:mahtem/core/cloud/cloud_account_directory.dart';
import 'package:mahtem/core/cloud/cloud_api.dart';
import 'package:mahtem/core/cloud/cloud_keys.dart';
import 'package:mahtem/core/cloud/cloud_vault.dart';
import 'package:mahtem/core/verify_history.dart';

import 'fixtures/fake_cloud_server.dart';

/// End-to-end twin of the "cleared app data / second phone" path:
/// provision a cloud account the way backup arming does, then prove the
/// credentials the way sign-in's remote fallback does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCloudServer server;
  late CloudApi api;
  late CloudAccountDirectory directory;

  const accountId = '251911223344';
  const password = 'secret1';

  setUp(() {
    server = FakeCloudServer();
    api = CloudApi(client: server.client());
    directory = CloudAccountDirectory(api: api);
  });

  Future<void> provisionCloudAccount() async {
    await api.createAccount(
      identifierHash: await cloudIdentifierHash(accountId),
      authKey: await deriveCloudAuthKey(password),
    );
  }

  /// Uploads a vault for the account with the given profile, exactly the
  /// way CloudController.enable() does.
  Future<void> uploadVaultWithProfile(RemoteAccountProfile? profile) async {
    final session = await api.createSession(
      identifierHash: await cloudIdentifierHash(accountId),
      authKey: await deriveCloudAuthKey(password),
    );
    final key = await deriveVaultKey(password, accountId);
    final blob = await encryptVaultBlob(
      key,
      encodeVaultPayload([
        HistoryEntry(
          id: 'h1',
          bankId: 'cbe',
          bankName: 'CBE',
          reference: 'FT1',
          verifiedAt: 1000,
          status: 'verified',
        ),
      ], account: profile),
    );
    await api.putVault(
      sessionToken: session.sessionToken,
      blob: blob,
      revision: 1000,
    );
  }

  test('unknown identifier is reported as no account', () async {
    final outcome = await directory.authenticate(
      accountId: accountId,
      password: password,
    );
    expect(outcome, isA<RemoteAuthUnknownAccount>());
  });

  test('wrong password is reported as bad password', () async {
    await provisionCloudAccount();
    final outcome = await directory.authenticate(
      accountId: accountId,
      password: 'wrong-pass',
    );
    expect(outcome, isA<RemoteAuthBadPassword>());
  });

  test('unreachable server is reported as inconclusive', () async {
    server.down = true;
    final outcome = await directory.authenticate(
      accountId: accountId,
      password: password,
    );
    expect(outcome, isA<RemoteAuthUnreachable>());
  });

  test('correct credentials confirm even with no vault yet', () async {
    await provisionCloudAccount();
    final outcome = await directory.authenticate(
      accountId: accountId,
      password: password,
    );
    expect(outcome, isA<RemoteAuthConfirmed>());
    expect((outcome as RemoteAuthConfirmed).profile, isNull);
  });

  test(
    'confirmed profile restores the display name from the encrypted vault',
    () async {
      await provisionCloudAccount();
      await uploadVaultWithProfile(
        const RemoteAccountProfile(
          identifier: '0911223344',
          displayName: 'Abebe Kebede',
          createdAtMs: 1700000000000,
        ),
      );
      final outcome = await directory.authenticate(
        accountId: accountId,
        password: password,
      );
      expect(outcome, isA<RemoteAuthConfirmed>());
      final profile = (outcome as RemoteAuthConfirmed).profile!;
      expect(profile.identifier, '0911223344');
      expect(profile.displayName, 'Abebe Kebede');
      expect(profile.createdAtMs, 1700000000000);
    },
  );

  test('the throwaway session is deleted after the profile read', () async {
    await provisionCloudAccount();
    await uploadVaultWithProfile(null);
    await directory.authenticate(accountId: accountId, password: password);
    expect(server.sessionDeletes, 1);
  });

  test('identifier hashing matches the backup arming path', () async {
    // The auth controller always passes the NORMALIZED id (the same
    // string validation.normalized produced at sign-up), and backup
    // arming hashes that exact string — so both paths hit one cloud
    // account. Prove the contract end-to-end:
    await provisionCloudAccount();
    expect(
      await cloudIdentifierHash(accountId),
      await cloudIdentifierHash('251911223344'),
    );
    final outcome = await directory.authenticate(
      accountId: accountId,
      password: password,
    );
    expect(outcome, isA<RemoteAuthConfirmed>());
  });

  test('server payload survives a real JSON round-trip', () async {
    // Sanity: the fake stores the raw PUT body — decode what the
    // directory would read back, proving codec + encryption compose.
    await provisionCloudAccount();
    await uploadVaultWithProfile(
      const RemoteAccountProfile(
        identifier: '0911223344',
        displayName: 'Abebe',
      ),
    );
    final stored = server.vaults.values.single;
    final key = await deriveVaultKey(password, accountId);
    final doc = decodeVaultDocument(
      await decryptVaultBlob(key, stored['blob'] as String),
    );
    expect(doc.account!.displayName, 'Abebe');
    expect(doc.entries, hasLength(1));
    expect(jsonDecode(jsonEncode(doc.entries.first.toJson()))['id'], 'h1');
  });
}
