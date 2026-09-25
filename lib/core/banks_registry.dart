import 'models.dart';

/// Static registry of the 10 live banks supported by cheki.
///
/// Mirrors `src/lib/manifest/banks.json` from the cheki web project
/// (kept offline-first so the UI renders instantly and works in low
/// connectivity without a /api/banks round-trip).
const List<ChekiBank> kChekiBanks = [
  ChekiBank(
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
  ChekiBank(
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
    notes: 'Verification runs through cheki servers, so it works worldwide.',
  ),
  ChekiBank(
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
  ChekiBank(
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
    notes: 'Verification runs through cheki servers, so it works worldwide.',
  ),
  ChekiBank(
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
  ChekiBank(
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
  ChekiBank(
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
  ChekiBank(
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
  ChekiBank(
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
  ChekiBank(
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
ChekiBank? bankById(String id) {
  for (final b in kChekiBanks) {
    if (b.id == id) return b;
  }
  return null;
}

/// Result of auto-detecting a bank from a raw reference string.
class ReferenceDetection {
  final ChekiBank bank;
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

  // Telebirr prefixes (DET, CHQ, DAB, DE*, ADQ, DF...).
  final telebirr =
      RegExp(r'^(DET|CHQ|DAB|DEL|ADQ|DEP|CHG|DF|DE[A-Z]|CH[A-F])\d*[A-Z0-9]*$');
  if (telebirr.hasMatch(upper) && upper.length >= 6) {
    return ReferenceDetection(bankById('telebirr')!, upper);
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
/// Mirrors `src/lib/adapters/url-detector.ts` from the web project.
BankDetection? detectBankFromUrl(String input) {
  final trimmed = input.trim();
  if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
    return null;
  }
  final Uri url;
  try {
    url = Uri.parse(trimmed);
  } on FormatException {
    return null;
  }
  final host = url.host.toLowerCase();

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

  // CBE new QR receipts encode a bare receipt ID (12 hex chars).
  final cbeNew = RegExp(r'^[0-9a-f]{12}$', caseSensitive: false);
  if (cbeNew.hasMatch(trimmed)) {
    return BankDetection(bank: kCbeNewId, reference: trimmed);
  }

  final byRef = detectBankFromReference(trimmed);
  if (byRef != null) {
    return BankDetection(bank: byRef.bank.id, reference: byRef.reference);
  }
  return null;
}
