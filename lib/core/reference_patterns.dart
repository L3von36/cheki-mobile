/// Reads transaction / reference numbers out of raw OCR text.
///
/// The camera scanner (`ui/screens/reference_scan_screen.dart`) runs ML Kit
/// text recognition on-device and hands every recognized line here. Receipts
/// are noisy — prices, dates, phone numbers, account numbers and TINs all
/// sit next to the one number that matters — so this engine ranks every
/// candidate and keeps the shortlist small:
///
///   rank 1  explicitly labeled (`Ref:`, `RRN:`, `Transaction No`, `FT#…`)
///   rank 2  bare 12-digit number (the RRN shape banks print)
///   rank 3  other bare numbers 10–16 digits long
///   rank 4  alphanumeric token (letters + digits, telebirr-style)
///
/// Ethiopian mobile numbers (`09…`, `07…`, `+251 9…`) are filtered out so a
/// customer-care line printed on the receipt never becomes a candidate.
/// Pure Dart — fully unit-tested without a device.
library;

/// One candidate reference read from OCR text.
class ReferenceCandidate {
  /// The reference exactly as it should be verified (separators removed).
  final String value;

  /// 1 = strongest (labeled), 4 = weakest (loose alphanumeric token).
  final int rank;

  const ReferenceCandidate(this.value, this.rank);

  @override
  String toString() => 'ReferenceCandidate($value, rank $rank)';
}

/// Candidates at this rank or better may be auto-accepted after repeated
/// camera agreement. Weaker candidates (bare numbers, loose tokens) wait
/// for an explicit tap — auto-accepting a price or account number read
/// from a busy receipt would be worse than one extra tap.
const int autoAcceptMaxRank = 2;

/// Labels that mark a transaction / reference number on a receipt.
final RegExp _labeled = RegExp(
  r'\b(?:reference|ref|transaction|txn|rrn|trn|receipt)\s*'
  r'(?:no\.?|number|#)?\s*'
  r'[-:#=]?\s*'
  r'([A-Za-z0-9][A-Za-z0-9/\-]{5,23})',
  caseSensitive: false,
);

/// Ethiopian fiscal-machine numbers: the `FT…` printed on every tax
/// receipt. The FT prefix is part of the reference, never a separator.
final RegExp _fiscal = RegExp(
  r'\bFT\s*[#:]?\s*([A-Za-z0-9][A-Za-z0-9/\-]{5,23})',
  caseSensitive: false,
);

/// A bare number, 10–16 digits, optionally grouped with single spaces or
/// dashes (`1234 5678 9012`). The word boundaries keep it from matching
/// inside a longer run — every shorter prefix would end next to another
/// digit, which is not a boundary, so a 26-digit blob yields nothing.
final RegExp _numericRun = RegExp(r'\b\d(?:[ \-]?\d){9,15}\b');

/// A loose token 8–24 characters long starting and ending with an
/// alphanumeric character — kept only when it mixes letters and digits.
final RegExp _alnumRun =
    RegExp(r'\b[A-Za-z0-9][A-Za-z0-9\-/]{6,22}[A-Za-z0-9]\b');

/// Ethiopian mobile numbers: 09…/07… (10), 2519…/2517… (12) and the
/// +251 form. Applied after separators are stripped.
final RegExp _phoneLike = RegExp(r'^(?:\+?251|0)?(?:9|7)\d{8}$');

/// Receipt fields whose long numbers are NEVER a transaction reference:
/// sender/receiver account numbers, TINs, phone lines, CIF ids. The whole
/// "label + number" span is masked out before any pattern runs, so a
/// 13-digit CBE account printed under "Sender Acc" can't become a
/// candidate even though it has RRN-like length.
final RegExp _nonReferenceField = RegExp(
  r'\b(?:acc(?:oun)?t?|tin|tel(?:ephone)?|phone|call|mobile|cif|recipient|receiver)'
  r'\s*[:#=.]?\s*\d[\d \-]{8,18}',
  caseSensitive: false,
);

String _clean(String raw) {
  var value = raw.trim();
  while (value.isNotEmpty && '-/:#=. '.contains(value[value.length - 1])) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

bool _allSameCharacter(String value) {
  if (value.length <= 1) return true;
  final first = value[0].toUpperCase();
  for (var i = 1; i < value.length; i++) {
    if (value[i].toUpperCase() != first) return false;
  }
  return true;
}

/// Merges a list of candidates into a ranked shortlist: deduped by value
/// (case-insensitive) keeping the best rank, sorted by rank, capped at
/// [max] entries.
List<ReferenceCandidate> dedupeAndRank(
  List<ReferenceCandidate> candidates, {
  int max = 5,
}) {
  final best = <String, ReferenceCandidate>{};
  final order = <String>[];
  for (final candidate in candidates) {
    final key = candidate.value.toUpperCase();
    final existing = best[key];
    if (existing == null) {
      best[key] = candidate;
      order.add(key);
    } else if (candidate.rank < existing.rank) {
      best[key] = candidate;
    }
  }
  // Stable order: rank first, then first-seen order (Dart's List.sort is
  // not stable, and equal-rank candidates must keep their reading order).
  final position = <String, int>{
    for (var i = 0; i < order.length; i++) order[i]: i,
  };
  final ranked = best.values.toList()..sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    return position[a.value.toUpperCase()]!
        .compareTo(position[b.value.toUpperCase()]!);
  });
  if (ranked.length > max) ranked.removeRange(max, ranked.length);
  return ranked;
}

/// Extracts ranked reference candidates from one piece of OCR text (a
/// line, a block, or a whole frame). Returns at most [max] candidates.
List<ReferenceCandidate> extractReferenceCandidates(
  String text, {
  int max = 5,
}) {
  final found = <ReferenceCandidate>[];
  var source = text.trim();
  if (source.isEmpty) return found;

  // 0) Mask fields that carry long numbers which are never references
  //    (accounts, TINs, phone lines) before any pattern sees them.
  source = source.replaceAllMapped(
    _nonReferenceField,
    (m) => ' ' * m.group(0)!.length,
  );

  // 1) Explicitly labeled numbers — the strongest signal on a receipt.
  for (final match in _labeled.allMatches(source)) {
    final value = _clean(match.group(1) ?? '');
    if (value.length >= 6 && !_allSameCharacter(value)) {
      found.add(ReferenceCandidate(value, 1));
    }
  }

  // 2) Fiscal-machine FT numbers — the FT prefix belongs to the value.
  for (final match in _fiscal.allMatches(source)) {
    final value = _clean('FT${match.group(1) ?? ''}');
    if (value.length >= 7 && !_allSameCharacter(value)) {
      found.add(ReferenceCandidate(value, 1));
    }
  }

  // 3) Bare numeric runs (RRN shape ranks higher than other lengths).
  for (final match in _numericRun.allMatches(source)) {
    final value = _clean(match.group(0) ?? '').replaceAll(RegExp(r'[ \-]'), '');
    if (value.length < 10 || value.length > 16) continue;
    if (_phoneLike.hasMatch(value)) continue;
    if (_allSameCharacter(value)) continue;
    found.add(ReferenceCandidate(value, value.length == 12 ? 2 : 3));
  }

  // 4) Loose alphanumeric tokens — telebirr-style references with no
  //    label. Must mix letters and digits so prices, dates and words
  //    never qualify.
  for (final match in _alnumRun.allMatches(source)) {
    final value = _clean(match.group(0) ?? '');
    if (value.length < 8) continue;
    final hasLetter = value.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = value.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasDigit) continue;
    if (_allSameCharacter(value)) continue;
    found.add(ReferenceCandidate(value, 4));
  }

  return dedupeAndRank(found, max: max);
}

/// Convenience: the single best candidate, or null when nothing usable
/// was read.
String? bestReferenceCandidate(String text) {
  final candidates = extractReferenceCandidates(text);
  return candidates.isEmpty ? null : candidates.first.value;
}
