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

import '../verify_history.dart';

const int kVaultFormatVersion = 1;
const int kVaultMaxEntries = 100;

/// Serializes [entries] (already newest-first) into the plaintext vault
/// JSON that [encryptVaultBlob] will encrypt.
String encodeVaultPayload(List<HistoryEntry> entries) {
  final capped = entries.length > kVaultMaxEntries
      ? entries.sublist(0, kVaultMaxEntries)
      : entries;
  return jsonEncode(<String, dynamic>{
    'v': kVaultFormatVersion,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'entries': capped.map((e) => e.toJson()).toList(),
  });
}

/// Decodes a vault plaintext into entries (newest first). Throws
/// [FormatException] on malformed payloads; unknown/extra fields are
/// ignored for forward compatibility.
List<HistoryEntry> decodeVaultPayload(String plaintext) {
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
  return entries;
}

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

  addAll(remote);
  addAll(local);

  final merged = byId.values.toList()
    ..sort((a, b) => b.verifiedAt.compareTo(a.verifiedAt));
  if (merged.length > kVaultMaxEntries) {
    merged.removeRange(kVaultMaxEntries, merged.length);
  }
  return merged;
}
