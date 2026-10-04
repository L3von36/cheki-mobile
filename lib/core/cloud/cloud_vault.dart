/// Vault payload encode/decode + the offline merge used by Mahtem Cloud
/// Backup (v1.13.0). Pure functions — no I/O, fully unit-tested.
///
/// The vault is a JSON snapshot of the local verification history. The
/// merge is a union keyed first by entry id and second by a natural
/// signature (bank ‖ reference ‖ checkedAt ‖ status) so the same check
/// recorded on two different devices collapses into one row; the local
/// copy always wins a signature conflict.
library;

import 'dart:convert';

import '../auth/remote_account.dart';
import '../verify_history.dart';

// v1.14.4: the payload gained an OPTIONAL 'account' profile (display
// name + identifier as typed) so a fresh device can restore the account
// after a cloud sign-in. The format version STAYS 1 on purpose — already-
// shipped v1.14.x clients reject unknown versions, but they do ignore
// unknown FIELDS, so they keep decoding v1+profile payloads fine (they
// just skip the profile; their next whole-payload upload drops it until
// an upgraded device re-writes it).
const int kVaultFormatVersion = 1;
const int kVaultMaxEntries = 100;

/// Serializes [entries] (already newest-first) into the plaintext vault
/// JSON that [encryptVaultBlob] will encrypt. When [account] is given,
/// the profile rides along inside the same encrypted blob (v1.14.4).
String encodeVaultPayload(List<HistoryEntry> entries,
    {RemoteAccountProfile? account}) {
  final capped = entries.length > kVaultMaxEntries
      ? entries.sublist(0, kVaultMaxEntries)
      : entries;
  return jsonEncode(<String, dynamic>{
    'v': kVaultFormatVersion,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'entries': capped.map((e) => e.toJson()).toList(),
    if (account != null) 'account': <String, dynamic>{
      'identifier': account.identifier,
      'displayName': account.displayName,
      if (account.createdAtMs != null) 'createdAtMs': account.createdAtMs,
    },
  });
}

/// A decoded vault: the history entries plus, when present, the account
/// profile that lets a fresh device restore the account after a
/// cloud-proven sign-in.
class VaultDocument {
  final List<HistoryEntry> entries;
  final RemoteAccountProfile? account;
  const VaultDocument({required this.entries, this.account});
}

/// Decodes a vault plaintext into a [VaultDocument]. Throws
/// [FormatException] on malformed payloads; unknown/extra fields are
/// ignored for forward compatibility, and a malformed 'account' profile
/// is dropped rather than poisoning the entries (it is cosmetic).
VaultDocument decodeVaultDocument(String plaintext) {
  final decoded = jsonDecode(plaintext);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('vault payload is not an object');
  }
  if (decoded['v'] != kVaultFormatVersion) {
    throw const FormatException('unsupported vault version');
  }
  final list = decoded['entries'];
  if (list is! List) {
    throw const FormatException('vault entries missing');
  }
  final entries = list
      .whereType<Map<String, dynamic>>()
      .map(HistoryEntry.fromJson)
      .where((e) => e.id.isNotEmpty)
      .toList();
  entries.sort((a, b) => b.verifiedAt.compareTo(a.verifiedAt));

  RemoteAccountProfile? account;
  final rawAccount = decoded['account'];
  if (rawAccount is Map<String, dynamic>) {
    final identifier = rawAccount['identifier'];
    final displayName = rawAccount['displayName'];
    if (identifier is String &&
        identifier.isNotEmpty &&
        displayName is String &&
        displayName.trim().isNotEmpty) {
      account = RemoteAccountProfile(
        identifier: identifier,
        displayName: displayName.trim(),
        createdAtMs: (rawAccount['createdAtMs'] as num?)?.toInt(),
      );
    }
  }
  return VaultDocument(entries: entries, account: account);
}

/// Decodes a vault plaintext into entries (newest first). Throws
/// [FormatException] on malformed payloads.
List<HistoryEntry> decodeVaultPayload(String plaintext) =>
    decodeVaultDocument(plaintext).entries;

String _signature(HistoryEntry e) =>
    '${e.bankId}|${e.reference}|${e.verifiedAt}|${e.status}';

/// Union merge: remote entries first, local entries overlaid. Dedupe by
/// id, then by natural signature (same bank/reference/time/status).
/// Result is newest-first and capped at [kVaultMaxEntries].
List<HistoryEntry> mergeHistoryEntries(
  List<HistoryEntry> local,
  List<HistoryEntry> remote,
) {
  final byId = <String, HistoryEntry>{};
  final bySignature = <String, HistoryEntry>{};

  void addAll(List<HistoryEntry> entries) {
    for (final e in entries) {
      final sig = _signature(e);
      if (byId.containsKey(e.id)) continue;
      if (bySignature.containsKey(sig)) continue;
      byId[e.id] = e;
      bySignature[sig] = e;
    }
  }

  addAll(local); // local first — the local copy wins every conflict
  addAll(remote);

  final merged = byId.values.toList()
    ..sort((a, b) => b.verifiedAt.compareTo(a.verifiedAt));
  if (merged.length > kVaultMaxEntries) {
    merged.removeRange(kVaultMaxEntries, merged.length);
  }
  return merged;
}
