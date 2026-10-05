/// Batch-check input parsing (v1.12.0).
///
/// A merchant pastes the day's references — one per line — and the app
/// checks them all. This module turns the raw text into clean rows BEFORE
/// anything is charged:
///   * numbered / bulleted lines ("1. FT…", "- CHQ…") are unwrapped,
///   * receipt links embedded on a line auto-detect their bank and the
///     reference is extracted (same detectors as the single flow),
///   * BOA encrypted slip QRs and Telebirr SuperApp QR blobs pasted as
///     lines are recognized,
///   * exact duplicates inside the batch are collapsed (one check each),
///   * a CBE printed FT number is skipped when CBE is its effective bank —
///     CBE's API can never look it up (same gate as the single flow),
///   * the batch is capped at [kBatchMaxLines] to stay polite to the
///     bank endpoints.
///
/// Pure and unit-tested; the batch screen only renders the outcome.
library;

import 'receipt_verify/extra_banks.dart'
    show detectExtraBankFromUrl;
import 'receipt_verify/models.dart';
import 'receipt_verify/parsers.dart';
import 'receipt_verify/reference_shape.dart';

/// Safety cap — an end-of-day till rarely exceeds this, and banks
/// rate-limit aggressive clients.
const int kBatchMaxLines = 50;

/// Why a parsed line will NOT be checked (no attempt is ever charged for
/// a skipped row).
enum BatchSkipReason {
  /// Exact duplicate of an earlier line in the same batch.
  duplicate,

  /// CBE printed FT-shaped number against the CBE endpoint — the bank's
  /// receipt API only accepts its shared receipt codes, so this can only
  /// fail (and would burn a check).
  cbePrinted,

  /// A link we don't recognize — almost certainly a wrong paste.
  unknownLink,

  /// The line overflowed [kBatchMaxLines] and was dropped.
  overLimit,
}

/// One parsed batch line, ready for the runner.
class BatchLine {
  /// The cleaned line as it will be shown (numbering stripped).
  final String input;

  /// Bank resolved from the line itself (link / QR payload / Telebirr
  /// prefix). Null for plain references — they take the batch bank.
  final String? bankId;

  /// Reference extracted from a link (null → use [input] as reference).
  final String? reference;

  /// Account digits carried by a link (CBE legacy, BOA).
  final String? account;

  /// Raw QR payload when the line is an encrypted BOA slip QR or a
  /// Telebirr SuperApp QR blob — the verifier handles it untouched.
  final String? scannedQr;

  /// Present when the row will NOT be checked.
  final BatchSkipReason? skipReason;

  const BatchLine({
    required this.input,
    this.bankId,
    this.reference,
    this.account,
    this.scannedQr,
    this.skipReason,
  });

  bool get isSkipped => skipReason != null;

  /// The value the verifier will receive as the reference.
  String get effectiveReference => reference ?? input;
}

/// Parses the whole pasted text into batch rows.
///
/// [bank] is the user-chosen batch bank — it applies to every plain
/// reference (and to Telebirr-prefix numbers only when no bank is chosen,
/// mirroring the single flow's auto-detect). Lines that carry their own
/// bank (links, QR payloads) always keep it. [account] is the shared
/// receiving-account suffix banks like BOA require on bare references —
/// it is attached to plain rows of [bank] only, never to link rows that
/// carry their own account.
List<BatchLine> parseBatchLines(
  String text, {
  BankInfo? bank,
  String? account,
}) {
  final lines = text.split('\n');
  final seen = <String>{};
  final rows = <BatchLine>[];
  final sharedAccount =
      (account ?? '').trim().isEmpty ? null : account!.trim();

  for (final rawLine in lines) {
    final line = _stripListDecoration(rawLine);
    if (line.isEmpty) continue;

    if (rows.length >= kBatchMaxLines) {
      rows.add(BatchLine(
        input: line,
        skipReason: BatchSkipReason.overLimit,
      ));
      continue;
    }

    // Exact duplicates collapse — the second check would return the same
    // answer and burn a licensed attempt for nothing.
    final dedupeKey = line.trim().toUpperCase();
    if (!seen.add(dedupeKey)) {
      rows.add(BatchLine(
        input: line,
        skipReason: BatchSkipReason.duplicate,
      ));
      continue;
    }

    rows.add(_parseLine(line, bank, sharedAccount));
  }
  return rows;
}

/// Removes leading list decoration: "1." "1)" "2 -" "•" "*" "-".
String _stripListDecoration(String raw) {
  var line = raw.trim();
  // "1. ", "12) ", "3 - "
  line = line.replaceFirst(RegExp(r'^\d{1,3}\s*[.)\-]\s+'), '');
  // "- ", "• ", "* "
  line = line.replaceFirst(RegExp(r'^[-•*]\s+'), '');
  return line.trim();
}

BatchLine _parseLine(String line, BankInfo? bank, String? sharedAccount) {
  // 1) Receipt links — bare or embedded in SMS prose (the Wegagen QR
  //    carries prose around the link). Extra banks first, hosts never
  //    overlap.
  final detected =
      detectExtraBankFromUrl(line) ?? detectBankFromUrl(line);
  if (detected != null) {
    // The CBE gate applies per line too: a retired cbe-legacy link gets
    // the same treatment as the single flow — keep it so the runner can
    // still surface the dedicated guidance? No: batch skips it — the
    // dedicated screen explains, batch stays a table.
    return BatchLine(
      input: line,
      bankId: detected.bank == 'cbe-legacy' ? null : detected.bank,
      reference: detected.reference,
      account: detected.account,
      skipReason:
          detected.bank == 'cbe-legacy' ? BatchSkipReason.cbePrinted : null,
    );
  }

  // 2) A link we cannot recognize — wrong paste; skip it rather than
  //    burn a check on a page no parser can read.
  if (looksLikeUrl(line)) {
    return BatchLine(
      input: line,
      skipReason: BatchSkipReason.unknownLink,
    );
  }

  // 3) BOA encrypted slip QR — verifies offline inside the verifier,
  //    no account suffix needed.
  final boa = decryptBoaQr(line);
  if (boa != null && (boa.reference?.isNotEmpty ?? false)) {
    return BatchLine(
      input: line,
      bankId: 'boa',
      scannedQr: line,
    );
  }

  // 4) Telebirr SuperApp QR blob → invoice number. The RAW invoice is
  //    kept: decoder junk ('c'/'e' swallowed by the camera) cannot occur
  //    in a pasted payload, but a genuine invoice ending in C/E would be
  //    corrupted by stripTrailingCeJunk — and a batch has no raw-retry
  //    net to recover it.
  final invoice = extractTelebirrInvoiceFromQr(line);
  if (invoice != null) {
    return BatchLine(
      input: line,
      bankId: 'telebirr',
      reference: invoice,
    );
  }

  // 5) Plain reference.
  //    CBE printed FT numbers can never verify against CBE — same gate
  //    as the single flow. Note the shape is legitimate for CBE Birr
  //    (its TID looks identical), so the gate only fires on CBE itself.
  final effectiveBank = bank?.id;
  if (effectiveBank == 'cbe' && _cbePrintedShape.hasMatch(line)) {
    return BatchLine(
      input: line,
      bankId: 'cbe',
      skipReason: BatchSkipReason.cbePrinted,
    );
  }

  //    Shape auto-detect only when nothing else claimed the line — same
  //    rule as the single flow (a manual pick always wins): a reference
  //    whose shape belongs to exactly one bank (Telebirr invoice, Zemen
  //    ETTB…, Dashen digits, M-Pesa code…) takes that bank. Ambiguous
  //    shapes (FT…) stay with the batch bank / need-one accounting.
  String? autoBank;
  if (bank == null) {
    autoBank = autoDetectBankForReference(line);
  }

  return BatchLine(
    input: line,
    bankId: bank?.id ?? autoBank,
    // The shared receiving-account suffix rides along only on plain
    // rows of the chosen bank (BOA last-5 — the merchant's own account,
    // identical for every row of an end-of-day batch).
    account: bank != null && bank.accountDigits > 0 ? sharedAccount : null,
  );
}

/// The FT reference printed on a CBE slip (mirrors flow.dart's gate).
final RegExp _cbePrintedShape = RegExp(r'^FT[0-9A-Za-z]{5,}$');

/// Rows the user will actually be charged for.
int countChargeable(List<BatchLine> rows) =>
    rows.where((r) => !r.isSkipped).length;

/// Rows that still need a bank before the batch can start (plain
/// references with no batch bank chosen and no auto-detect).
int countNeedingBank(List<BatchLine> rows) =>
    rows.where((r) => !r.isSkipped && r.bankId == null && r.scannedQr == null)
        .length;
