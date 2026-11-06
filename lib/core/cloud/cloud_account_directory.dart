/// [RemoteAccountDirectory] + [BetterAuthLink] backed by BetterAuth
/// (v1.19.0) on mahtem.com.et.
///
/// Cross-device sign-in runs through BetterAuth's email+password endpoints:
/// the identifier (phone or email) maps onto the email Better Auth stores
/// (`<intl>@phone.mahtem.et` for phones), the typed password travels over
/// TLS and is hashed (scrypt) server-side.
///
/// Two-tier fallback keeps older installs working:
///   1. BetterAuth sign-in — the normal path once the identity exists.
///   2. A 401 can ALSO mean "legacy account, never migrated" (Better Auth
///      answers the same enumeration-safe 401 for unknown users and wrong
///      passwords). The zero-knowledge proof (identifierHash + PBKDF2
///      authKey, exactly what the old /v1/session handshake sent) upgrades
///      the account in one call (/v1/auth/legacy-migrate): the server
///      re-proves it, creates/links the BetterAuth user and returns a
///      bearer session — same user_id, vault/ledger/Pro all carry over.
///      A 404 there means the account truly does not exist anywhere.
///
/// After a confirmation the directory makes one best-effort attempt to
/// read the account profile (display name + identifier as typed at
/// creation) out of the ENCRYPTED vault — same as the pre-BetterAuth
/// directory; the backup controller re-arms right after sign-in anyway.
library;

import 'dart:async';
import 'dart:typed_data';

import '../auth/remote_account.dart';
import 'cloud_api.dart';
import 'cloud_keys.dart';
import 'cloud_vault.dart';

class CloudAccountDirectory implements RemoteAccountDirectory, BetterAuthLink {
  CloudAccountDirectory({CloudApi? api}) : _api = api ?? CloudApi();

  final CloudApi _api;

  @override
  Future<RemoteAuthOutcome> authenticate({
    required String accountId,
    required String password,
  }) async {
    // The vault key needs only the typed credentials, not the session —
    // derive it while the network round trip is in flight instead of
    // adding another PBKDF2 stall after the answer arrives.
    final vaultKeyFuture = deriveVaultKey(password, accountId);

    BetterAuthSession session;
    try {
      session = await _api.betterAuthSignIn(
        identifier: accountId,
        password: password,
      );
    } on CloudApiException catch (e) {
      switch (e.error) {
        case CloudApiError.badCredentials:
          // Unknown BetterAuth identity OR wrong password. The legacy
          // migration disambiguates: a proven legacy account upgrades
          // here on the first sign-in of the new client.
          return await _migrateLegacy(
            accountId: accountId,
            password: password,
            vaultKeyFuture: vaultKeyFuture,
          );
        case CloudApiError.exists:
          return const RemoteAuthBadPassword();
        default:
          return const RemoteAuthUnreachable();
      }
    } catch (_) {
      return const RemoteAuthUnreachable();
    }

    return await _confirmed(session, vaultKeyFuture);
  }

  /// Legacy-account upgrade path — see the library doc comment.
  Future<RemoteAuthOutcome> _migrateLegacy({
    required String accountId,
    required String password,
    required Future<Uint8List> vaultKeyFuture,
  }) async {
    final identifierHash = await cloudIdentifierHash(accountId);
    final authKey = await deriveCloudAuthKey(password);
    final BetterAuthSession session;
    try {
      session = await _api.betterAuthMigrateLegacy(
        identifierHash: identifierHash,
        authKey: authKey,
        identifier: accountId,
        password: password,
      );
    } on CloudApiException catch (e) {
      return switch (e.error) {
        CloudApiError.noAccount || CloudApiError.notFound =>
          const RemoteAuthUnknownAccount(),
        CloudApiError.badCredentials || CloudApiError.exists =>
          const RemoteAuthBadPassword(),
        _ => const RemoteAuthUnreachable(),
      };
    } catch (_) {
      return const RemoteAuthUnreachable();
    }
    return await _confirmed(session, vaultKeyFuture);
  }

  /// Proven. Best-effort profile read out of the encrypted vault, then
  /// hand the outcome (with the BetterAuth bearer token) to the caller.
  Future<RemoteAuthOutcome> _confirmed(
    BetterAuthSession session,
    Future<Uint8List> vaultKeyFuture,
  ) async {
    RemoteAccountProfile? profile;
    try {
      final remote = await _api.getVault(session.token);
      if (remote != null) {
        final key = await vaultKeyFuture;
        profile = decodeVaultDocument(
          await decryptVaultBlob(key, remote.blob),
        ).account;
      }
    } catch (_) {
      profile = null;
    }

    // Prefer the profile's identifier (what the user TYPED at creation);
    // fall back to the normalized identifier Better Auth knows.
    final effectiveProfile = RemoteAccountProfile(
      identifier: profile?.identifier.trim().isNotEmpty == true
          ? profile!.identifier
          : identifierFromBetterAuthEmail(session.user.email),
      displayName: profile?.displayName ?? session.user.name,
      createdAtMs: profile?.createdAtMs,
    );
    return RemoteAuthConfirmed(effectiveProfile, sessionToken: session.token);
  }

  @override
  Future<String?> linkAccount({
    required String accountId,
    required String identifier,
    required String displayName,
    required String password,
  }) async {
    final identifierHash = await cloudIdentifierHash(accountId);
    final authKey = await deriveCloudAuthKey(password);
    try {
      final session = await _api.betterAuthMigrateLegacy(
        identifierHash: identifierHash,
        authKey: authKey,
        identifier: identifier,
        password: password,
        displayName: displayName,
      );
      return session.token;
    } catch (_) {
      return null; // best-effort — retried on a later sign-in
    }
  }
}
