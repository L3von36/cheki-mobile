/// Remote account authentication contract (v1.14.4).
///
/// Mahtem accounts are born on-device, but they are also PROVISIONED in
/// the user-hosted zero-knowledge cloud (`mahtem-api`) — since v1.14.0
/// every sign-up/sign-in arms the backup, which creates the cloud
/// account. This interface abstracts the reverse trip so sign-in can
/// survive a cleared app or a brand-new phone: when the device has never
/// heard of an identifier, [RemoteAccountDirectory.authenticate] asks
/// the cloud "does this account exist, and does this password prove
/// it?". The implementation derives the identifier hash + auth key from
/// the typed credentials — the raw password never leaves the device,
/// exactly like backup arming.
///
/// Kept free of cloud/HTTP/crypto imports so [AuthController] (and its
/// tests) depend on this contract only.
library;

import 'account.dart';

/// Account fields that survive on the cloud side — stored ONLY inside
/// the AES-GCM encrypted vault, never as server-visible plaintext — and
/// can be restored onto a fresh device after a successful remote
/// authentication.
class RemoteAccountProfile {
  /// What the user typed at account creation (display form).
  final String identifier;

  /// The name entered at sign-up; shown in the avatar + settings.
  final String displayName;

  /// When the account was created (epoch ms, UTC), if known.
  final int? createdAtMs;

  const RemoteAccountProfile({
    required this.identifier,
    required this.displayName,
    this.createdAtMs,
  });

  factory RemoteAccountProfile.fromAccount(AccountRecord account) =>
      RemoteAccountProfile(
        identifier: account.identifier,
        displayName: account.displayName,
        createdAtMs: account.createdAtUtc.millisecondsSinceEpoch,
      );
}

/// Outcome of asking the cloud about an identifier + password.
sealed class RemoteAuthOutcome {
  const RemoteAuthOutcome();
}

/// The cloud recognized the identifier and the password proved it.
/// [profile] is null when the cloud vault predates profiles (or holds
/// no vault at all) — the caller falls back to safe display defaults.
class RemoteAuthConfirmed extends RemoteAuthOutcome {
  final RemoteAccountProfile? profile;
  const RemoteAuthConfirmed(this.profile);
}

/// No cloud account exists for this identifier: the account genuinely
/// does not exist anywhere this device can see.
class RemoteAuthUnknownAccount extends RemoteAuthOutcome {
  const RemoteAuthUnknownAccount();
}

/// The cloud knows the identifier but this password does not prove it.
class RemoteAuthBadPassword extends RemoteAuthOutcome {
  const RemoteAuthBadPassword();
}

/// The check was INCONCLUSIVE — network down, timeout or server trouble.
/// Nothing can be concluded about the account's existence.
class RemoteAuthUnreachable extends RemoteAuthOutcome {
  const RemoteAuthUnreachable();
}

/// Asks the hosted backend whether an identifier + password pair
/// matches a provisioned account. Implementations must derive all
/// secrets from [password] on-device and never transmit the password
/// itself.
abstract class RemoteAccountDirectory {
  Future<RemoteAuthOutcome> authenticate({
    required String accountId,
    required String password,
  });
}
