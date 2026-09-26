/// App-side bank additions: Wegagen Bank and Amhara Bank.
///
/// The stylepos engine files (`verifier.dart`, `parsers.dart`, `models.dart`)
/// stay VERBATIM — this additive module extends them without touching a
/// line:
///
///   * two extra [BankInfo] catalog entries + a combined catalog
///     ([kAllVerifyBanks] / [bankByIdAll]),
///   * URL detection for the banks' own share links
///     ([detectExtraBankFromUrl], runs before the engine detector),
///   * a verifier ([verifyExtraBank]) the controller routes `wegagen` /
///     `amhara` inputs to, using the same HTTP client factory.
///
/// Endpoints (both behind the banks' own React receipt pages — we call the
/// JSON APIs the pages themselves call):
///
///   * Wegagen  — `https://transinfo.wegagenbanksc.com.et:8011/sms_wega/txn/{id}`
///     where `{id}` is the full token in the shared
///     `transinfo.wegagenbanksc.com.et:8183/?id=…` receipt link.
///   * Amhara   — `https://transaction.amharabank.com.et/{trx}` where `{trx}`
///     is the `FT…` number of the `receipt.amharabank.com.et/?trx=…` link.
library;

import 'dart:convert';

import 'http_client_factory.dart';
import 'models.dart';
import 'parsers.dart';
import 'verifier.dart';

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

/// Wegagen Bank — receipts are shared as transinfo links (SMS / app).
const BankInfo kWegagenBank = BankInfo(
  id: 'wegagen',
  name: 'Wegagen Bank',
  shortName: 'Wegagen',
  isWallet: false,
  referenceLabel: 'Receipt link or transaction ID',
  referenceHint: 'Paste the transinfo.wegagenbanksc.com.et:8183/?id=… link',
  helper:
      'Tap Share on the Wegagen receipt and paste the link — the full '
      'transaction ID after “?id=” works too.',
);

/// Amhara Bank (ABa) — web receipts keyed by the FT… transaction number.
const BankInfo kAmharaBank = BankInfo(
  id: 'amhara',
  name: 'Amhara Bank',
  shortName: 'Amhara',
  isWallet: false,
  referenceLabel: 'Transaction number',
  referenceHint: 'e.g. FT262507XG9T or the receipt.amharabank.com.et link',
  helper:
      'The FT… transaction number from the ABa web receipt — or just paste '
      'the shared receipt link.',
);

/// The two new entries, appended after the stylepos catalog.
const List<BankInfo> kExtraBanks = [kWegagenBank, kAmharaBank];

/// Full catalog: the verbatim stylepos list first, then the extras.
const List<BankInfo> kAllVerifyBanks = [...kVerifyBanks, ...kExtraBanks];

/// Catalog lookup across both lists (engine ids keep their meaning).
BankInfo? bankByIdAll(String id) {
  for (final b in kAllVerifyBanks) {
    if (b.id == id) return b;
  }
  return null;
}

/// True when [id] must be verified by [verifyExtraBank] instead of the
/// stylepos verifier.
bool isExtraBank(String id) => id == 'wegagen' || id == 'amhara';

// ---------------------------------------------------------------------------
// URL detection
// ---------------------------------------------------------------------------

/// Detects Wegagen / Amhara receipt links, returning the engine's own
/// [UrlDetection] shape so callers can chain:
/// `detectExtraBankFromUrl(x) ?? detectBankFromUrl(x)`.
///
/// The marker regexes also catch links embedded INSIDE pasted SMS text —
/// Wegagen's SMS arrives as prose with the link at the end.
UrlDetection? detectExtraBankFromUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  // Wegagen: https://transinfo.wegagenbanksc.com.et:8183/?id=150TBAW2626221151113DAAT
  final wg = RegExp(
    r'transinfo\.wegagenbanksc\.com\.et(?::\d+)?/\?id=([A-Za-z0-9]{8,})',
    caseSensitive: false,
  ).firstMatch(text);
  if (wg != null) return UrlDetection('wegagen', wg.group(1)!);

  // Amhara: https://receipt.amharabank.com.et/?trx=FT262507XG9T
  final am = RegExp(
    r'amharabank\.com\.et/\?trx=([A-Za-z0-9]{6,})',
    caseSensitive: false,
  ).firstMatch(text);
  if (am != null) return UrlDetection('amhara', am.group(1)!);

  if (!looksLikeUrl(text)) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();

  if (host.endsWith('.wegagenbanksc.com.et') ||
      host == 'wegagenbanksc.com.et') {
    final id = uri.queryParameters['id'];
    if (id != null && id.trim().isNotEmpty) {
      return UrlDetection('wegagen', id.trim());
    }
  }

  if (host.endsWith('.amharabank.com.et') || host == 'amharabank.com.et') {
    final trx = uri.queryParameters['trx'];
    if (trx != null && trx.trim().isNotEmpty) {
      return UrlDetection('amhara', trx.trim());
    }
    // API-style share: transaction.amharabank.com.et/FT262507XG9T
    final segments = uri.pathSegments;
    if (segments.isNotEmpty &&
        RegExp(r'^[A-Za-z0-9]{6,}$').hasMatch(segments.last)) {
      return UrlDetection('amhara', segments.last);
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// JSON parsing
// ---------------------------------------------------------------------------

String? _clean(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty || t == '---' || t == '-') return null;
  return t;
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.replaceAll('ETB', '').replaceAll(',', '').trim();
    return double.tryParse(t);
  }
  return null;
}

/// Formats a UTC ISO timestamp in Ethiopia wall time (UTC+3).
String? _fmtIsoAddis(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;
  final clean = iso.trim().replaceFirst(RegExp(r'\.\d+'), '');
  final dt = DateTime.tryParse(clean)?.toUtc();
  if (dt == null) return null;
  final a = dt.add(const Duration(hours: 3));
  String p(int n) => n.toString().padLeft(2, '0');
  return '${a.year.toString().padLeft(4, '0')}-${p(a.month)}-${p(a.day)} '
      '${p(a.hour)}:${p(a.minute)}';
}

/// `yyMMddHHmm` (e.g. 2609060908) → `2026-09-06 09:08`; falls back to the
/// `yyyyMMdd` booking date (20260907 → 2026-09-07).
String? _fmtAmharaDate(String? dateTime, String? bookingDate) {
  final dt = (dateTime ?? '').trim();
  if (RegExp(r'^\d{10}$').hasMatch(dt)) {
    return '20${dt.substring(0, 2)}-${dt.substring(2, 4)}-${dt.substring(4, 6)} '
        '${dt.substring(6, 8)}:${dt.substring(8, 10)}';
  }
  final bd = (bookingDate ?? '').trim();
  if (RegExp(r'^\d{8}$').hasMatch(bd)) {
    return '${bd.substring(0, 4)}-${bd.substring(4, 6)}-${bd.substring(6, 8)}';
  }
  return null;
}

/// Parses the Wegagen `sms_wega/txn/{id}` JSON into a [ReceiptData].
/// Returns null when the body is not a usable Wegagen transaction record.
ReceiptData? parseWegagenReceiptJson(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final ref = _clean(decoded['trnRefNo'] as String?);
  final amount = _num(decoded['txnAmount']);
  if (ref == null || amount == null) return null;

  final bank = bankByIdAll('wegagen')!;
  return ReceiptData(
    verified: true,
    bankCode: bank.id,
    bankName: bank.name,
    reference: ref,
    senderName: _clean(decoded['sender_name'] as String?),
    senderAccount: _clean(decoded['sender_account'] as String?) ??
        _clean(decoded['accNo'] as String?),
    receiverName: _clean(decoded['receiver_name'] as String?),
    // Wallet transfers carry the credited wallet number; when the bank
    // masks everything the receiving phone is the best identifier left.
    receiverAccount: _clean(decoded['receiver_account'] as String?) ??
        _clean(decoded['phoneNumber'] as String?),
    amount: amount,
    currency: _clean(decoded['currency'] as String?) ?? 'ETB',
    date: _fmtIsoAddis(decoded['txnTimestamp'] as String?) ??
        _fmtIsoAddis(decoded['trnDt'] as String?),
    transactionType: _clean(decoded['narrative'] as String?) ??
        _clean(decoded['paymentMethod'] as String?),
    transactionStatus: _clean(decoded['messageStatus'] as String?),
    invoiceNumber: ref,
  );
}

/// Outcome of [parseAmharaReceiptJson]: either a receipt, or a rejection
/// reason the verifier surfaces verbatim (a receipt that exists but shows a
/// non-completed status must NOT verify).
class AmharaParse {
  final ReceiptData? receipt;
  final String? rejectReason;
  const AmharaParse(this.receipt, [this.rejectReason]);
}

/// Parses the Amhara Bank `transaction.amharabank.com.et/{trx}` JSON.
///
/// `{"status": true, "data": {…}}` — the data payload's own `status`
/// (`"MAT"` = matched/completed) gates verification: any other explicit
/// status rejects with its reason. Returns `AmharaParse(null)` when the
/// body is not a usable record (the verifier maps that to not-found).
AmharaParse parseAmharaReceiptJson(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const AmharaParse(null);
  }
  if (decoded is! Map) return const AmharaParse(null);
  final statusFlag = decoded['status'];
  final ok = statusFlag == true || statusFlag.toString().toLowerCase() == 'true';
  final data = decoded['data'];
  if (!ok || data is! Map) return const AmharaParse(null);

  final st = (data['status'] as String?)?.trim().toUpperCase();
  if (st != null && st.isNotEmpty && st != 'MAT') {
    return AmharaParse(null,
        'This Amhara Bank transaction shows status “$st” — it did not '
        'complete successfully.');
  }

  final bank = bankByIdAll('amhara')!;
  final reference = _clean(data['transactionReference'] as String?);
  if (reference == null) return const AmharaParse(null);

  return AmharaParse(ReceiptData(
    verified: true,
    bankCode: bank.id,
    bankName: bank.name,
    reference: reference,
    // Their API misspells the fields per direction: outgoing receipts name
    // the payer debitorName/debitAccount, incoming ones sendorName /
    // sendorAccount; receivers appear as receiverName/reveiverAccount or
    // creditorName/creditAccountId. Accept both spellings everywhere.
    senderName: _clean(data['sendorName'] as String?) ??
        _clean(data['debitorName'] as String?),
    senderAccount: _clean(data['sendorAccount'] as String?) ??
        _clean(data['debitAccount'] as String?),
    receiverName: _clean(data['receiverName'] as String?) ??
        _clean(data['creditorName'] as String?),
    receiverAccount: _clean(data['reveiverAccount'] as String?) ??
        _clean(data['creditAccountId'] as String?),
    amount: _num(data['amount']) ?? _num(data['totalAmount']),
    currency: _clean(data['currencyId'] as String?) ?? 'ETB',
    date: _fmtAmharaDate(data['dateTime'] as String?,
        data['bookingDate'] as String?),
    branch: _clean(data['branchName'] as String?),
    transactionType: _clean(data['transactionDesc'] as String?),
    transactionStatus: st,
    invoiceNumber: reference,
  ));
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

/// Plain HTTP response carrier so tests can fake the network.
class ExtraHttpResponse {
  final int statusCode;
  final List<int> bodyBytes;
  const ExtraHttpResponse(this.statusCode, this.bodyBytes);
}

typedef ExtraHttpFn = Future<ExtraHttpResponse> Function(
    Uri uri, Map<String, String> headers);

Future<ExtraHttpResponse> _defaultHttp(Uri uri, Map<String, String> headers) async {
  final client = createVerifyClient();
  try {
    final resp =
        await client.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    return ExtraHttpResponse(resp.statusCode, resp.bodyBytes);
  } finally {
    client.close();
  }
}

/// Verifies Wegagen / Amhara receipts — the controller routes inputs whose
/// bankId passes [isExtraBank] here, everything else stays in the verbatim
/// stylepos verifier. Failure shapes (not-found messages, tips, retries)
/// mirror the engine's behaviour so the UI needs no special cases.
Future<VerifyResult> verifyExtraBank(
  VerifyInput input, {
  ExtraHttpFn? httpFn,
}) async {
  final sw = Stopwatch()..start();
  final bankId = input.bankId;
  final bank = bankByIdAll(bankId);
  final reference = input.reference.trim();

  VerifyFailure failure(String message, {List<String> tips = const []}) =>
      VerifyFailure(VerifyErrorKind.network, message, tips: tips);

  if (bank == null || !isExtraBank(bankId)) {
    return VerifyResult.failed(
      const VerifyFailure(
        VerifyErrorKind.unsupported,
        'That bank is not supported yet.',
      ),
      sw.elapsedMilliseconds,
    );
  }
  if (reference.isEmpty) {
    return VerifyResult.failed(
      VerifyFailure(
        VerifyErrorKind.badInput,
        'Enter the reference number, receipt link, or scan the QR.',
      ),
      sw.elapsedMilliseconds,
    );
  }

  final uri = bankId == 'wegagen'
      ? Uri.parse(
          'https://transinfo.wegagenbanksc.com.et:8011/sms_wega/txn/$reference')
      : Uri.parse(
          'https://transaction.amharabank.com.et/${Uri.encodeQueryComponent(reference)}');

  final fetch = httpFn ?? _defaultHttp;
  final headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Accept': 'application/json',
  };

  for (var attempt = 0; attempt <= 2; attempt++) {
    try {
      final resp = await fetch(uri, headers);
      if (resp.statusCode == 404) {
        return VerifyResult.failed(
          VerifyFailure(
            VerifyErrorKind.notFound,
            'The ${bank.name} receipt service says “not found”.',
            tips: const [
              'Check the reference for typos.',
              'If you pasted a link, make sure nothing was cut off.',
            ],
          ),
          sw.elapsedMilliseconds,
        );
      }
      if (resp.statusCode == 200) {
        final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
        if (bankId == 'wegagen') {
          final receipt = parseWegagenReceiptJson(body);
          if (receipt == null) {
            return VerifyResult.failed(
              VerifyFailure(
                VerifyErrorKind.notFound,
                'No receipt found for “$reference” at ${bank.name}.',
                tips: const [
                  'Double-check every character of the reference.',
                  'Ask the sender to re-share the receipt link.',
                ],
              ),
              sw.elapsedMilliseconds,
            );
          }
          return VerifyResult.receipt(receipt, sw.elapsedMilliseconds);
        }

        final out = parseAmharaReceiptJson(body);
        if (out.rejectReason != null) {
          return VerifyResult.failed(
            VerifyFailure(
              VerifyErrorKind.notFound,
              out.rejectReason!,
              tips: const [
                'Ask the sender to confirm the transfer went through.',
              ],
            ),
            sw.elapsedMilliseconds,
          );
        }
        if (out.receipt == null) {
          return VerifyResult.failed(
            VerifyFailure(
              VerifyErrorKind.notFound,
              'No receipt found for “$reference” at ${bank.name}.',
              tips: const [
                'Double-check every character of the reference.',
                'Ask the sender to re-share the receipt link.',
              ],
            ),
            sw.elapsedMilliseconds,
          );
        }
        return VerifyResult.receipt(out.receipt!, sw.elapsedMilliseconds);
      }
      if (resp.statusCode >= 500 && attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 800 << attempt));
        continue;
      }
      return VerifyResult.failed(
        failure('${bank.name} answered with an unexpected response '
            '(HTTP ${resp.statusCode}).', tips: const ['Try again in a moment.']),
        sw.elapsedMilliseconds,
      );
    } catch (_) {
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 800 << attempt));
        continue;
      }
    }
  }

  return VerifyResult.failed(
    failure('Could not reach ${bank.name}. Check your internet connection.',
        tips: const [
          'Mobile data or Wi-Fi must be on.',
          'The bank service may be down — try again in a minute.',
        ]),
    sw.elapsedMilliseconds,
  );
}
