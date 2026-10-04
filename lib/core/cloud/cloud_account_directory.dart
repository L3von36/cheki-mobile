/// [RemoteAccountDirectory] backed by the mahtem-api Cloudflare Worker
/// (v1.14.4).
///
/// Authentication is the ordinary zero-knowledge session handshake:
/// derive `identifierHash` + `authKey` from the typed credentials and
/// POST /v1/session. The worker answers 404 `no_account` (unknown
/// identifier), 401 `bad_credentials` (wrong password) or 200 with a
/// session token — a remote password check that never transmits the
/// password. After a confirmation the directory makes one best-effort
/// attempt to read the account profile (display name + identifier as
/// typed at creation) out of the ENCRYPTED vault, then drops the
/// throwaway session — the backup controller opens its own session
/// when the auth screens arm it right after sign-in.
library;

import '../auth/remote_account.dart';
import 'cloud_api.dart';
import 'cloud_keys.dart';
import 'cloud_vault.dart';

class CloudAccountDirectory implements RemoteAccountDirectory {
  CloudAccountDirectory({CloudApi? api}) : _api = api ?? CloudApi();

  final CloudApi _api;

  @override
  Future<RemoteAuthOutcome> authenticate({
    required String accountId,
    required String password,
  }) async {
    final identifierHash = await cloudIdentifierHash(accountId);
    final authKey = await deriveCloudAuthKey(password);
    final CloudSession session;
    try {
      session = await _api.createSession(
        identifierHash: identifierHash,
        authKey: authKey,
      );
    } on CloudApiException catch (e) {
      return switch (e.error) {
        CloudApiError.noAccount => const RemoteAuthUnknownAccount(),
        CloudApiError.badCredentials => const RemoteAuthBadPassword(),
        _ => const RemoteAuthUnreachable(),
      };
    } catch (_) {
      return const RemoteAuthUnreachable();
    }

    // Proven. Best-effort profile read — authentication already
    // succeeded, so a missing/unreadable vault only means the fresh
    // local record starts from display fallbacks and the next sync
    // re-writes the profile.
    RemoteAccountProfile? profile;
    try {
      final remote = await _api.getVault(session.sessionToken);
      if (remote != null) {
        final key = await deriveVaultKey(password, accountId);
        profile = decodeVaultDocument(
          await decryptVaultBlob(key, remote.blob),
        ).account;
      }
    } catch (_) {
      profile = null;
    }

    // Hygiene: this session was only needed for the profile read.
    try {
      await _api.deleteSession(session.sessionToken);
    } catch (_) {/* ignore — the session expires on its own */}

    return RemoteAuthConfirmed(profile);
  }
}
