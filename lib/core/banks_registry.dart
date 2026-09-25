import 'models.dart';
import 'native/parsers.dart';
import 'native/verifier.dart';

/// Static registry of the 10 live banks supported by Mahtem.
///
/// Original detection rules, tuned for offline-first UX
/// (kept offline-first so the UI renders instantly and works in low
/// connectivity without a /api/banks round-trip).
const List<MahtemBank> kMahtemBanks = [
  MahtemBank(
    id: 'cbe',
    name: 'Commercial Bank of Ethiopia',
    shortName: 'CBE',
    type: BankType.bank,
    requiresAccount: true,
    accountLabel: 'Receiving account number',
    accountDigits: 8,
    requiresPhone: false,
    geoBlocked: false,
    colorValue: 0xFF502878,
    initials: 'CBE',
    referenceFormat: 'FT followed by 10 alphanumeric characters',
    referenceExample: 'FT26140P01YB',
    notes:
        'Legacy PDF system needs the last 8 digits of the receiving account. '
        'Newer receipts (mbreciept.cbe.com.et links) verify with the receipt ID alone.',
  ),
  MahtemBank(
    id: 'telebirr',
    name: 'Telebirr (Ethio Telecom)',
    shortName: 'Telebirr',
    type: BankType.mobile,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: false,
    geoBlocked: true,
    colorValue: 0xFF00A0DC,
    initials: 'TB',
    referenceFormat: '2-3 letter prefix + 6-8 alphanumeric characters',
    referenceExample: 'DET8FJGUJ4',
    notes: 'Verified directly on the device — works on Ethiopian networks.',
  ),
  MahtemBank(
    id: 'boa',
    name: 'Bank of Abyssinia',
    shortName: 'BOA',
    type: BankType.bank,
    requiresAccount: true,
    accountLabel: 'Receiving account number',
    accountDigits: 5,
    requiresPhone: false,
    geoBlocked: false,
    colorValue: 0xFF0E4D92,
    initials: 'BOA',
    referenceFormat: 'Reference starting with 2 letters (varies by type)',
    referenceExample: 'AB12345678',
    notes: 'Needs the last 5 digits of the receiving account number.',
  ),
  MahtemBank(
    id: 'mpesa',
    name: 'M-Pesa Ethiopia',
    shortName: 'M-Pesa',
    type: BankType.mobile,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: false,
    geoBlocked: true,
    colorValue: 0xFF00A651,
    initials: 'MP',
    referenceFormat: 'Typically 2 letters followed by 6+ digits',
    referenceExample: 'SE12345678',
    notes: 'Verified directly on the device — works on Ethiopian networks.',
  ),
  MahtemBank(
    id: 'dashen',
    name: 'Dashen Bank',
    shortName: 'Dashen',
    type: BankType.bank,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: false,
    geoBlocked: false,
    colorValue: 0xFF0066B3,
    initials: 'DB',
    referenceFormat: 'Dashen Transaction Reference (not the Transfer Reference)',
    referenceExample: 'D31OBTI251720001',
    notes: 'Works for both within-Dashen and other-bank transfer receipts.',
  ),
  MahtemBank(
    id: 'awash',
    name: 'Awash Bank',
    shortName: 'Awash',
    type: BankType.bank,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: false,
    geoBlocked: false,
    colorValue: 0xFFE2231A,
    initials: 'AB',
    referenceFormat: 'Share link segment, e.g. 2KDL95Z0NR-4U61O6',
    referenceExample: '2KDL95Z0NR-4U61O6',
    notes: 'Paste the link the Awash app sends by SMS, or the segment after "/-".',
  ),
  MahtemBank(
    id: 'zemen',
    name: 'Zemen Bank',
    shortName: 'Zemen',
    type: BankType.bank,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: false,
    geoBlocked: false,
    colorValue: 0xFF1B75BB,
    initials: 'ZB',
    referenceFormat: 'Alphanumeric transaction reference',
    referenceExample: 'ZM12345678',
    notes: 'Paste the share.zemenbank.com link or the reference alone.',
  ),
  MahtemBank(
    id: 'cbebirr',
    name: 'CBE Birr',
    shortName: 'CBE Birr',
    type: BankType.wallet,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: true,
    geoBlocked: false,
    colorValue: 0xFF502878,
    initials: 'CB',
    referenceFormat: 'Alphanumeric transaction reference',
    referenceExample: 'CB12345678',
    notes: 'Requires the phone number tied to the wallet.',
  ),
  MahtemBank(
    id: 'siinqee',
    name: 'Siinqee Bank',
    shortName: 'Siinqee',
    type: BankType.bank,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: false,
    geoBlocked: false,
    colorValue: 0xFF006A4E,
    initials: 'SQ',
    referenceFormat: 'Alphanumeric transaction reference',
    referenceExample: 'SQ12345678',
    notes: 'Routed through the eBirr receipt platform.',
  ),
  MahtemBank(
    id: 'ebirr',
    name: 'eBirr',
    shortName: 'eBirr',
    type: BankType.mobile,
    requiresAccount: false,
    accountLabel: '',
    accountDigits: null,
    requiresPhone: false,
    geoBlocked: false,
    colorValue: 0xFF059669,
    initials: 'eB',
    referenceFormat: 'receipt.ebirr.com/{tenant}/{token} URL or tenant/token',
    referenceExample: 'nib/abc123def',
    notes: 'Also covers Nib, Wegagen, Ahadu and KAAFI receipts.',
  ),
];

/// Convenience alias kept for the CBE new QR system (receipt IDs from
/// mbreciept.cbe.com.et). Maps to the `cbe-new` parser on the API side.
const String kCbeNewId = 'cbe-new';

/// Looks up a bank by its registry id.
MahtemBank? bankById(String id) {
  for (final b in kMahtemBanks) {
    if (b.id == id) return b;
  }
  return null;
}

/// Result of auto-detecting a bank from a raw reference string.
class ReferenceDetection {
  final MahtemBank bank;
  final String reference;
  const ReferenceDetection(this.bank, this.reference);
}

/// Detects the bank purely from the reference format — mirrors
/// `detectBank()` in the web project's `src/lib/banks.ts`.
ReferenceDetection? detectBankFromReference(String input) {
  final upper = input.toUpperCase().trim();
  if (upper.isEmpty) return null;

  // CBE legacy: FT prefix.
  if (upper.startsWith('FT')) {
    return ReferenceDetection(bankById('cbe')!, upper);
  }

  // Telebirr references — classic prefixes (DET, CHQ, DAB, DE*, ADQ, DF...)
  // and the newer TPS refs which may carry dots, e.g. TPS25191.1430.A4001234.
  final telebirr = RegExp(
    r'^(TPS\d[\dA-Z.\-]{5,}|(DET|CHQ|DAB|DEL|ADQ|DEP|CHG|DF|DE[A-Z]|CH[A-F])\d*[A-Z0-9]*)$',
  );
  if (telebirr.hasMatch(upper) && upper.length >= 6) {
    return ReferenceDetection(
      bankById('telebirr')!,
      upper.replaceAll(RegExp(r'[.\-]+$'), ''),
    );
  }

  // eBirr receipt URL or tenant/token strings.
  if (RegExp(r'receipt\.ebirr\.com', caseSensitive: false).hasMatch(input)) {
    return ReferenceDetection(bankById('ebirr')!, input.trim());
  }
  if (RegExp(r'^(NIB|WEGAGEN|AHADU|KAAFIMF)/', caseSensitive: false)
      .hasMatch(upper)) {
    return ReferenceDetection(bankById('ebirr')!, input.trim());
  }

  // Awash share segment: BASE36-BASE36 (two groups separated by a dash).
  if (RegExp(r'^-?[A-Z0-9]{6,}-[A-Z0-9]{3,}$').hasMatch(upper)) {
    return ReferenceDetection(bankById('awash')!, upper.replaceFirst('-', ''));
  }

  // Zemen share links.
  if (RegExp(r'share\.zemenbank\.com', caseSensitive: false).hasMatch(input)) {
    return ReferenceDetection(bankById('zemen')!, input.trim());
  }

  return null;
}

/// Parses a receipt URL / QR payload and extracts the bank + reference.
///
/// Mirrors `src/lib/adapters/url-detector.ts` from the web project, then
/// hardens it: case-insensitive scheme, hash-route and query-only Telebirr
/// links, and the whole ethiotelecom.et / ethiomobilemoney.et host family.
BankDetection? detectBankFromUrl(String input) {
  final trimmed = input.trim();
  final Uri url;
  try {
    url = Uri.parse(trimmed);
  } on FormatException {
    return null;
  }
  final scheme = url.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final host = url.host.toLowerCase();
  if (host.isEmpty) return null;

  // Telebirr receipt links come in several shapes:
  //   https://transactioninfo.ethiotelecom.et/receipt/{REF}
  //   https://transactioninfo.ethiotelecom.et/#/receipt/{REF}  (hash route)
  //   https://transactioninfo.ethiotelecom.et/receipt?id={REF} (query form)
  // Legacy wallet hosts on ethiomobilemoney.et are accepted too.
  if (_isTelebirrHost(host)) {
    final ref = _extractTelebirrRef(url);
    if (ref != null) {
      return BankDetection(bank: 'telebirr', reference: ref);
    }
    // A telebirr link we cannot read a reference from — guide the user
    // instead of pretending nothing was detected.
    return BankDetection(
      bank: null,
      reference: trimmed,
      hint: kTelebirrLinkHint,
    );
  }

  // CBE new: https://mbreciept.cbe.com.et/{id}
  if (host.contains('mbreciept.cbe.com.et') || host.contains('mb.cbe.com.et')) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      return BankDetection(
        bank: kCbeNewId,
        reference: parts.last,
      );
    }
  }

  // CBE legacy: https://apps.cbe.com.et:100/?id=FT26140P01YB60536171
  if (host.contains('apps.cbe.com.et')) {
    final id = url.queryParameters['id'];
    if (id != null && id.toUpperCase().startsWith('FT') && id.length > 10) {
      final accountSuffix = id.substring(id.length - 8);
      final ref = id.substring(0, id.length - 8);
      if (ref.length > 2) {
        return BankDetection(
          bank: 'cbe',
          reference: ref,
          accountNumber: accountSuffix,
        );
      }
    }
  }

  // Telebirr: https://transactioninfo.ethiotelecom.et/receipt/{REF}
  if (host.contains('transactioninfo.ethiotelecom.et')) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      return BankDetection(bank: 'telebirr', reference: parts.last);
    }
  }

  // BOA: ?trx={REF} or ?id={REF}{5 digits}
  if (host.contains('bankofabyssinia.com')) {
    final trx = url.queryParameters['trx'];
    final id = url.queryParameters['id'];
    if (trx != null && trx.isNotEmpty) {
      return BankDetection(bank: 'boa', reference: trx);
    }
    if (id != null && id.length > 5) {
      final accountSuffix = id.substring(id.length - 5);
      final ref = id.substring(0, id.length - 5);
      if (ref.isNotEmpty) {
        return BankDetection(
          bank: 'boa',
          reference: ref,
          accountNumber: accountSuffix,
        );
      }
      return BankDetection(bank: 'boa', reference: id);
    }
  }

  // Dashen: https://receipt.dashensuperapp.com/receipt/{REF}
  //         https://api.dashensuperapp.com/receipts/Within-Dashen-Transfer-{REF}.pdf
  if (host.contains('dashensuperapp.com')) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final last = parts.isNotEmpty ? parts.last : '';
    final pdfMatch =
        RegExp(r'Within-Dashen-Transfer-(.+?)\.pdf$', caseSensitive: false)
            .firstMatch(last);
    if (pdfMatch != null) {
      return BankDetection(bank: 'dashen', reference: pdfMatch.group(1)!);
    }
    if (last.isNotEmpty) {
      return BankDetection(bank: 'dashen', reference: last);
    }
  }

  // Awash: https://awashpay.awashbank.com:8225/-{REF}
  if (host.contains('awashbank.com')) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      final ref = parts.last
          .replaceFirst(RegExp(r'^-'), '')
          .replaceAll(RegExp(r'[.,;:!?]+$'), '');
      return BankDetection(bank: 'awash', reference: ref);
    }
  }

  // Zemen: https://share.zemenbank.com/rt/{REF}/pdf
  if (host.contains('zemenbank.com')) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return BankDetection(bank: 'zemen', reference: parts[1]);
    }
    if (parts.length == 1) {
      return BankDetection(bank: 'zemen', reference: parts[0]);
    }
  }

  // M-Pesa: https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo={REF}
  if (host.contains('safaricom.et')) {
    final trx = url.queryParameters['trxNo'];
    if (trx != null && trx.isNotEmpty) {
      return BankDetection(bank: 'mpesa', reference: trx);
    }
  }

  // eBirr: https://receipt.ebirr.com/{tenant}/{token}
  if (host.contains('receipt.ebirr.com')) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return BankDetection(
        bank: 'ebirr',
        reference: '${parts[0]}/${parts[1]}',
      );
    }
    if (parts.isNotEmpty) {
      return BankDetection(bank: 'ebirr', reference: parts.last);
    }
  }

  return null;
}

/// One-shot detector used by the home screen and QR scanner:
/// 1. try URL/QR detection (all known bank receipt link formats)
/// 2. fall back to reference-format detection
/// 3. otherwise return `null` and let the user pick a bank manually.
BankDetection? detectReceipt(String input) {
  return detectBankFromUrl(input) ?? _detectFromPlainPayload(input);
}

BankDetection? _detectFromPlainPayload(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  // Bare phone-number codes ("receive money" personal QRs) — checked
  // FIRST because a 12-digit 2519XXXXXXXX number is valid hex and would
  // otherwise collide with the CBE 12-character receipt-id rule below.
  if (_isPhoneQrPayload(trimmed)) {
    return BankDetection(bank: null, reference: trimmed, hint: kPhoneQrHint);
  }

  // CBE new QR receipts encode a bare receipt ID (12 hex chars).
  final cbeNew = RegExp(r'^[0-9a-f]{12}$', caseSensitive: false);
  if (cbeNew.hasMatch(trimmed)) {
    return BankDetection(bank: kCbeNewId, reference: trimmed);
  }

  // Bank of Abyssinia receipt QR codes are AES-encrypted CSV payloads —
  // the full receipt (names, amount, reference) is embedded in the code
  // itself, so we decrypt it on the spot. Telebirr receipt QRs are ALSO
  // base64 blobs, but a different encoding: base64 → hex → latin1 text
  // carrying the invoice number. When BOA decryption fails we try that
  // before giving up; only then do we remember the blob as unreadable.
  var unreadableBlob = false;
  final base64ish = RegExp(r'^[A-Za-z0-9+/=]{24,}$');
  if (base64ish.hasMatch(trimmed)) {
    final decrypted = BoaQrDecryptor.decrypt(trimmed);
    if (decrypted.verified && decrypted.reference != null) {
      return BankDetection(
        bank: 'boa',
        reference: decrypted.reference!,
        accountNumber: decrypted.receiverAccount,
      );
    }
    final invoice = extractTelebirrInvoiceFromQr(trimmed);
    if (invoice != null) {
      return BankDetection(
        bank: 'telebirr',
        reference: _stripTrailingCeJunk(invoice),
      );
    }
    unreadableBlob = true;
  }

  // Direct reference formats (CBE FT, Telebirr, eBirr, Awash, Zemen).
  final byRef = detectBankFromReference(trimmed);
  if (byRef != null) {
    return BankDetection(bank: byRef.bank.id, reference: byRef.reference);
  }

  // Share text / JSON / SMS payloads that WRAP a Telebirr reference
  // ("...transaction TPS25191.1430.A4001234 of 500.00 ETB...").
  final embedded = _embeddedTelebirrRef(trimmed);
  if (embedded != null) {
    return BankDetection(bank: 'telebirr', reference: embedded);
  }

  // Payment-request / phone-number / structured QRs are NOT receipts —
  // explain that instead of a dead end.
  final payHint = _paymentRequestHint(trimmed);
  if (payHint != null) {
    return BankDetection(bank: null, reference: trimmed, hint: payHint);
  }

  // Foreign links (a URL host we don't recognize) get targeted guidance.
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://').hasMatch(trimmed) ||
      RegExp(r'^www\.', caseSensitive: false).hasMatch(trimmed)) {
    return BankDetection(
      bank: null,
      reference: trimmed,
      hint: kForeignLinkHint,
    );
  }

  // Long unreadable base64-shaped blobs (BOA QR we could not decrypt).
  if (unreadableBlob) {
    return BankDetection(
      bank: null,
      reference: trimmed,
      hint: kEncryptedQrHint,
    );
  }

  // Generic reference-shaped QR payload: accept it and let the user pick
  // the bank manually, so scanning NEVER feels like a dead end. Whitespace
  // is collapsed and pure-numeric ids are allowed too (some wallets use
  // numeric transaction numbers).
  final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
  final hasLetter = RegExp(r'[A-Za-z]').hasMatch(compact);
  final digitsOnly = RegExp(r'^\d+$').hasMatch(compact);
  if (compact.length >= 5 &&
      compact.length <= 120 &&
      (hasLetter || (digitsOnly && compact.length >= 8))) {
    return BankDetection(bank: null, reference: compact);
  }
  return null;
}

/// Strips decoder junk letters from an extracted Telebirr invoice number.
///
/// The camera sometimes appends a stray 'c' (or 'e') while the QR leaves
/// the frame. On link payloads that junk sits at the very end and the
/// scanner's sanitizer removes it — but Telebirr SuperApp receipt QRs
/// are base64 blobs, and the junk lands INSIDE the decoded text right
/// after the invoice number. The 8-12 character A-Z0-9 run then swallows
/// the uppercased junk letter and the extracted reference ends with a
/// bogus 'C' that no bank knows.
///
/// Trailing c/e runs are removed while at least 8 characters remain (the
/// invoice format's minimum length). When a removed letter was genuine —
/// invoices may legitimately end in C/E — the raw-scan retry net in
/// VerifyController.verify re-verifies with the untouched blob, which
/// decodes back to the unstripped invoice.
String _stripTrailingCeJunk(String invoice) {
  var ref = invoice.trim();
  while (ref.length > 8 && RegExp(r'[cCeE]$').hasMatch(ref)) {
    ref = ref.substring(0, ref.length - 1);
  }
  return ref;
}

/// Finds a Telebirr reference embedded inside a larger payload.
///
/// Requires a digit right after the prefix so ordinary words ("DEPARTMENT")
/// never trigger a false match.
final RegExp _tpsInText = RegExp(r'\bTPS\d[\dA-Za-z.\-]{5,}');
final RegExp _tbPrefixInText =
    RegExp(r'\b(DET|CHQ|DAB|DEL|ADQ|DEP|CHG|DF)\d[\dA-Za-z]{4,}');

String? _embeddedTelebirrRef(String input) {
  for (final re in [_tpsInText, _tbPrefixInText]) {
    for (final m in re.allMatches(input)) {
      final ref = m.group(0)!.replaceAll(RegExp(r'[.\-]+$'), '');
      if (ref.length >= 6) return ref.toUpperCase();
    }
  }
  return null;
}

/// Returns guidance text when the payload is clearly NOT a verifiable
/// receipt (pay/request QRs, structured non-receipt payloads...).
String? _paymentRequestHint(String input) {
  final compact = input.replaceAll(RegExp(r'\s+'), '');

  // EMVCo-style payment QR (EthSwitch / telebirr / M-Pesa receive & pay
  // codes): TLV records starting with the "00 02 .." payload-format tag
  // and mostly digits.
  final digits = RegExp(r'\d').allMatches(compact).length;
  final digitRatio = compact.isEmpty ? 0.0 : digits / compact.length;
  if (compact.length >= 24 && compact.startsWith('0002') && digitRatio >= 0.6) {
    return kPayRequestHint;
  }

  // Clearly structured non-receipt payloads.
  if (RegExp(
    r'^(WIFI:|MEBKM:|BEGIN:VCARD|otpauth://|mailto:|tel:|smsto:|sms:|geo:|bitcoin:|ethereum:)',
    caseSensitive: false,
  ).hasMatch(input)) {
    return kNotReceiptHint;
  }

  return null;
}

/// Ethiopian phone numbers as they appear in "receive money" QR codes:
/// 09XX / 07XX local or +2519XX / 2519XX / 25107X international formats.
bool _isPhoneQrPayload(String input) {
  final compact = input.replaceAll(RegExp(r'\s+'), '');
  return RegExp(r'^\+?(2519\d{8}|25107\d{7}|09\d{8}|07\d{8})$')
      .hasMatch(compact);
}

bool _isTelebirrHost(String host) {
  for (final domain in const ['ethiotelecom.et', 'ethiomobilemoney.et']) {
    if (host == domain || host.endsWith('.$domain')) return true;
  }
  return false;
}

/// Extracts the transaction reference from any Telebirr receipt link shape:
/// path (`/receipt/{REF}`), hash route (`#/receipt/{REF}`) or query
/// (`?id={REF}`, `?ref={REF}`, `?trx={REF}`...).
String? _extractTelebirrRef(Uri url) {
  // 1. Hash routes — Dart's Uri.fragment is already percent-decoded.
  final fragment = url.fragment.trim().replaceFirst(RegExp(r'^#+/?'), '');
  if (fragment.isNotEmpty) {
    final ref = _refFromSegments(fragment.split('/'));
    if (ref != null) return ref;
  }

  // 2. Query parameters: ?id= ?ref= ?reference= ?trx= ?trxNo= ...
  for (final entry in url.queryParameters.entries) {
    if (const ['id', 'ref', 'reference', 'trx', 'trxno', 'no', 'number']
        .contains(entry.key.toLowerCase())) {
      final v = entry.value.trim();
      if (_isPlausibleRef(v)) return v;
    }
  }

  // 3. Path segments: /receipt/{REF} or the last reference-looking segment.
  return _refFromSegments(url.pathSegments);
}

String? _refFromSegments(List<String> segments) {
  final segs = segments.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  for (var i = 0; i < segs.length; i++) {
    if (segs[i].toLowerCase() == 'receipt' && i + 1 < segs.length) {
      final cand = segs[i + 1];
      if (_isPlausibleRef(cand)) return cand;
    }
  }
  for (final s in segs.reversed) {
    if (s.toLowerCase() == 'receipt') continue;
    if (_isPlausibleRef(s)) return s;
  }
  return null;
}

/// A plausible transaction reference: 4-64 chars, alphanumeric with . _ -
/// and at least one digit (rules out path words like "receipt" or "api").
bool _isPlausibleRef(String v) {
  final t = v.trim();
  if (t.length < 4 || t.length > 64) return false;
  if (!RegExp(r'^[A-Za-z0-9._\-]+$').hasMatch(t)) return false;
  return RegExp(r'[0-9]').hasMatch(t);
}

// ---------------------------------------------------------------------
// Scanner guidance messages — shown for QR payloads that are real but
// NOT verifiable receipts, so scanning always teaches, never dead-ends.
// ---------------------------------------------------------------------

const String kPayRequestHint =
    'That is a pay / request QR — it tells a wallet where to send money, '
    'not proof of a payment. Scan the QR printed on the payment receipt, '
    'or paste the transaction number.';

const String kPhoneQrHint =
    'That QR only holds a phone number — it is for sending money, not a '
    'receipt. Scan the QR on the payment receipt, or paste the transaction '
    'number.';

const String kNotReceiptHint =
    'That QR is not a payment receipt. Scan the QR printed on the payment '
    'receipt, or paste the transaction number.';

const String kForeignLinkHint =
    'That link is not a supported receipt link. Paste the transaction '
    'number shown on the receipt instead.';

const String kTelebirrLinkHint =
    'That Telebirr link has no readable receipt reference. Open it and copy '
    'the transaction number, then paste it here.';

const String kEncryptedQrHint =
    'This looks like an encrypted receipt QR we could not read. Try the '
    'receipt link or the transaction number instead.';
