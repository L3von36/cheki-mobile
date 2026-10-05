/// Bare-reference shape detection: which bank(s) plausibly issued a
/// reference that arrived WITHOUT a receipt link (typed by hand, read by
/// the camera, or pasted from an SMS).
///
/// A receipt link identifies its bank outright — this module only runs
/// for bare references, where the shape is the only signal. Two callers:
///
///   * [autoDetectBankForReference] — pre-selects the bank when the shape
///     is UNAMBIGUOUS (exactly one bank's receipts look like this), so the
///     user can verify without opening the picker,
///   * [bankCandidatesForReference] — the ordered candidate list the
///     verify controller walks after a definitive not-found: an FT number
///     may be Amhara's, BOA's or CBE Birr's, and only the issuing bank
///     can answer. Multi-candidate shapes NEVER auto-select (a wrong
///     pre-selection could burn a licensed check on a doomed call).
///
/// Shapes are the ones published by the banks' own receipt hints and
/// observed across the supported catalog. Conservative by design: an
/// unknown shape returns an empty list and the manual picker keeps
/// working exactly as before.
library;

import 'parsers.dart';

/// Zemen share references — `ETTB` + digits (their PDF receipts carry the
/// same prefix, see `parseZemenPdfText`).
final RegExp _zemenRef = RegExp(r'^ETTB[0-9A-Z]{5,}$');

/// The `FT…` fiscal-machine reference printed on Amhara, BOA and CBE Birr
/// slips (and on retired CBE slips). Genuinely ambiguous across those
/// banks — CBE itself is excluded because its receipt API only accepts
/// shared receipt codes, never a printed FT number (verified live: the
/// API answers 500 "Security Alert" for this shape).
final RegExp _ftRef = RegExp(r'^FT[0-9A-Z]{5,}$');

/// A CBE mobile receipt code — mixed-case, digit-bearing, no separators
/// (`fHCx8QmLpZ1`, `fHCxyV4mg5pRIwEkJO`), optionally the `v2-` prefixed
/// variant the encoded-receipt links carry. Case-SENSITIVE: every other
/// Ethiopian reference in the catalog is uppercase or digits, so mixed
/// case is CBE's signature.
final RegExp _cbeCode = RegExp(
  r'^(?:v2-)?(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z0-9]{8,20}$',
);

/// Dashen SuperApp references — pure digits, 14–16 long (the shape their
/// own hint and the live receipt samples carry).
final RegExp _pureDigits = RegExp(r'^\d+$');

/// M-Pesa transaction numbers — exactly 10 uppercase characters mixing
/// letters and digits (`SJ72HK3YZ9`).
final RegExp _tenChar = RegExp(r'^[A-Z0-9]{10}$');

/// Awash share tokens — dash-separated uppercase runs with an optional
/// leading dash (`-2KHIQYW30P-5VQUNG`); the leading dash is part of the
/// token the bank's endpoint expects.
final RegExp _awashToken = RegExp(r'^-?[A-Z0-9]+(?:-[A-Z0-9]+)+$');

/// Abay Bank receipt codes — `135FT` + a long uppercase run
/// (`135FTRM25044000119176773010`, 30 chars on the sample receipt).
final RegExp _abayRef = RegExp(r'^135FT[0-9A-Z]{20,}$');

/// Wegagen transaction ids — `150TBAW` + a long run
/// (`150TBAW2626221151113DAAT`). Deliberately prefix-pinned: before Abay
/// Bank existed here, the digit-led rule happily claimed Abay's `135FT…`
/// codes and pre-selected the wrong bank.
final RegExp _wegagenToken = RegExp(r'^150TBAW[0-9A-Z]{10,}$');

final RegExp _hasUpper = RegExp('[A-Z]');
final RegExp _hasDigit = RegExp(r'[0-9]');

/// Ordered bank ids whose receipt endpoints plausibly serve [reference],
/// most likely first. Empty for links (their bank is detected elsewhere)
/// and for shapes no supported bank prints — the caller falls back to the
/// manual picker.
List<String> bankCandidatesForReference(String reference) {
  final raw = reference.trim();
  if (raw.isEmpty || looksLikeUrl(raw)) return const [];

  final ref = raw.toUpperCase();

  // 1) Telebirr service-code invoices (CHQ… / DET… / ADQ…) — the
  //    distinctive two/three-letter service prefix decides it alone.
  if (looksLikeTelebirrReference(ref)) return const ['telebirr'];

  // 2) Zemen share references.
  if (_zemenRef.hasMatch(ref)) return const ['zemen'];

  // 3) FT fiscal references — Amhara verifies a bare FT number with no
  //    extra fields, BOA needs the receiver's last-5, CBE Birr the payer
  //    phone. Ordered by "works with nothing else provided" first; the
  //    verify controller skips candidates whose fields are missing.
  if (_ftRef.hasMatch(ref)) return const ['amhara', 'boa', 'cbebirr'];

  // 4) CBE receipt codes — mixed-case check runs on the ORIGINAL casing
  //    (after `ref` uppercase it would look like any other token).
  if (_cbeCode.hasMatch(raw)) return const ['cbe'];

  // 5) Dashen — pure digits of the right length (checked before the
  //    digit-led Wegagen token so a numeric Dashen ref never routes
  //    there; a Wegagen id always carries letters).
  if (raw.length >= 14 && raw.length <= 16 && _pureDigits.hasMatch(ref)) {
    return const ['dashen'];
  }

  // 6) M-Pesa — exactly 10 uppercase characters mixing letters/digits.
  if (_tenChar.hasMatch(ref) &&
      _hasUpper.hasMatch(ref) &&
      _hasDigit.hasMatch(ref)) {
    return const ['mpesa'];
  }

  // 7) Awash share tokens. FT / ETTB-shaped tokens stay out even when
  //    they carry a dash (`FT26140P01-YB`) — Awash never prints them,
  //    and claiming them here would pre-select the wrong bank; they end
  //    up with no candidates and the manual picker decides.
  if (raw.length >= 12 &&
      raw.length <= 24 &&
      _awashToken.hasMatch(ref) &&
      _hasUpper.hasMatch(ref) &&
      !ref.startsWith('FT') &&
      !ref.startsWith('ETTB')) {
    return const ['awash'];
  }

  // 8) Abay — `135FT…` receipt codes. Checked before Wegagen (whose
  //    tightened rule below no longer overlaps) so a pasted Abay code
  //    pre-selects Abay instead of Wegagen.
  if (_abayRef.hasMatch(ref)) return const ['abay'];

  // 9) Wegagen — long, digit-led, letter-bearing.
  if (_wegagenToken.hasMatch(ref) && _hasUpper.hasMatch(ref)) {
    return const ['wegagen'];
  }

  return const [];
}

/// The bank to pre-select for a bare reference — non-null only when the
/// shape is unambiguous ([bankCandidatesForReference] yields exactly one
/// bank). Ambiguous shapes (FT…) return null and leave the picker in
/// charge: guessing there could spend a licensed check on the wrong bank.
String? autoDetectBankForReference(String reference) {
  final candidates = bankCandidatesForReference(reference);
  return candidates.length == 1 ? candidates.first : null;
}
