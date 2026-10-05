/// Geo-block relay for the two catalog banks that refuse requests from
/// non-Ethiopian IPs (`geoBlocked: true`: Telebirr and M-Pesa).
///
/// The stylepos engine files stay VERBATIM. When the device looks abroad
/// (the same clock heuristic the engine uses to blame the geo-block in its
/// error message) the controller asks this module FIRST: the receipt is
/// fetched by Mahtem's own Cloudflare Worker (`POST /v1/relay` on
/// `mahtem-api`), which is not subject to the user's VPN exit IP, and the
/// bank's answer is parsed here with the engine's own public parsers —
/// byte-for-byte the same interpretation the direct path would apply.
///
/// The relay answers only when it has something DEFINITIVE: a receipt, a
/// bank not-found, or a bank error page. Anything else (worker down, bad
/// payload, unresolvable input) returns null and the caller falls back to
/// the direct path unchanged — this module can never make a verification
/// worse than it was before it existed.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, kProfileMode, kReleaseMode;

import '../cloud/cloud_api.dart' show kCloudApiBaseUrl;
import 'http_client_factory.dart';
import 'models.dart';
import 'parsers.dart';
import 'verifier.dart';

/// The relay-eligible banks. MUST match the Worker's host allowlist
/// exactly — the Worker rejects any other bank id outright.
const Set<String> kGeoRelayBanks = {'telebirr', 'mpesa'};

/// POSTs JSON to the Worker. Tests inject their own implementation.
typedef RelayPostFn = Future<RelayResponse> Function(
    Uri url, Map<String, String> headers, String body);

/// Plain HTTP response carrier so tests can fake the Worker.
class RelayResponse {
  final int statusCode;
  final String body;
  const RelayResponse(this.statusCode, this.body);
}

Future<RelayResponse> _postJson(
    Uri url, Map<String, String> headers, String body) async {
  final client = createVerifyClient();
  try {
    final resp = await client
        .post(url, headers: headers, body: body)
        .timeout(const Duration(seconds: 20));
    return RelayResponse(
        resp.statusCode, utf8.decode(resp.bodyBytes, allowMalformed: true));
  } finally {
    client.close();
  }
}

/// The engine's geo heuristic, as a pure function: far from Ethiopia's
/// UTC+3 means the device looks abroad (VPN user, traveller).
bool looksOutsideEthiopia(Duration offset) {
  final h = offset.inHours;
  return h < 1 || h > 5;
}

/// Whether [bankId] should try the Worker relay before going direct.
///
///   * only the relay-allowlisted banks,
///   * product builds only (release/profile) — a debug/VM test machine's
///     clock must never trigger a live Worker call, so tests stay hermetic,
///   * on web the browser blocks the direct bank call outright, so the
///     relay is the only path that works,
///   * elsewhere: the bank geo-blocks AND the clock says abroad — the
///     exact condition under which the engine would otherwise show its
///     "blocks requests from outside Ethiopia" dead end after ~45s of
///     timeouts.
///
/// The three override parameters exist for tests.
bool shouldUseGeoRelay(
  String bankId, {
  bool? productMode,
  bool? web,
  Duration? utcOffset,
}) {
  if (!kGeoRelayBanks.contains(bankId)) return false;
  final product = productMode ?? (kReleaseMode || kProfileMode);
  if (!product) return false;
  if (web ?? kIsWeb) return true;
  final bank = bankById(bankId);
  if (bank == null || !bank.geoBlocked) return false;
  return looksOutsideEthiopia(utcOffset ?? DateTime.now().timeZoneOffset);
}

/// Resolves the input to the bare reference the bank's endpoint expects —
/// the same QR / link resolution the engine's `_resolve` performs for the
/// two relayable banks. Null when the input needs the direct path's richer
/// error shapes (unrecognized QR, wrong bank's link, empty everything).
String? resolveRelayReference(VerifyInput input) {
  final bankId = input.bankId;
  String? ref = input.reference.trim();
  final qr = input.qrData?.trim();
  if (qr != null && qr.isNotEmpty) {
    if (looksLikeUrl(qr)) {
      final detected = detectBankFromUrl(qr);
      if (detected == null || detected.bank != bankId) return null;
      ref = detected.reference;
    } else if (bankId == 'telebirr') {
      ref = extractTelebirrInvoiceFromQr(qr);
    } else {
      ref = qr;
    }
  } else if (ref.isNotEmpty && looksLikeUrl(ref)) {
    final detected = detectBankFromUrl(ref);
    if (detected == null || detected.bank != bankId) return null;
    ref = detected.reference;
  }
  if (ref == null || ref.isEmpty) return null;
  return ref;
}

/// The exact receipt URL the engine's `_buildUri` would fetch, for the
/// two relayable banks only (kept in lockstep with verifier.dart).
String? relayReceiptUrl(String bankId, String reference) {
  switch (bankId) {
    case 'telebirr':
      return 'https://transactioninfo.ethiotelecom.et/receipt/$reference';
    case 'mpesa':
      return 'https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=$reference';
  }
  return null;
}

/// Fetches [input]'s receipt through the Mahtem Worker relay.
///
/// Null means "the relay has no definitive answer" — the caller falls back
/// to the direct path. Every answer the bank's page produced maps to a
/// [VerifyResult] with the same messages, tips and field mapping the
/// engine's direct path uses.
Future<VerifyResult?> verifyViaGeoRelay(VerifyInput input,
    {RelayPostFn? postFn}) async {
  final reference = resolveRelayReference(input);
  if (reference == null) return null;
  final target = relayReceiptUrl(input.bankId, reference);
  if (target == null) return null;

  final bank = bankById(input.bankId);
  if (bank == null) return null;

  final post = postFn ?? _postJson;
  final sw = Stopwatch()..start();
  int? status;
  String? bodyText;
  try {
    final resp = await post(
      Uri.parse('$kCloudApiBaseUrl/v1/relay'),
      const {
        'X-Mahtem-Client': 'mahtem-android',
        'Content-Type': 'application/json',
      },
      jsonEncode({'bank': input.bankId, 'url': target}),
    );
    if (resp.statusCode != 200) return null; // worker down / screen
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    if (decoded['ok'] != true) return null; // worker-level error
    status = (decoded['status'] as num?)?.toInt();
    final body = decoded['body'];
    if (body is! String) return null;
    bodyText = body;
  } catch (_) {
    return null;
  }
  if (status == null) return null;

  if (status == 404) {
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
  if (status != 200) {
    return VerifyResult.failed(
      VerifyFailure(
        VerifyErrorKind.network,
        '${bank.name} answered with an unexpected response (HTTP $status).',
        tips: const ['Try again in a moment.'],
      ),
      sw.elapsedMilliseconds,
    );
  }

  final parsed = input.bankId == 'telebirr'
      ? parseTelebirrHtml(bodyText)
      : parseMpesaJson(bodyText);
  if (!parsed.verified) {
    return VerifyResult.failed(
      VerifyFailure(
        VerifyErrorKind.notFound,
        'No receipt found for “$reference” at ${bank.name}.',
        tips: const [
          'Double-check every character of the reference.',
          'Ask the sender to re-share the receipt link or show the QR.',
        ],
      ),
      sw.elapsedMilliseconds,
    );
  }

  // Mirrors the engine's `_receiptFrom` field-for-field.
  final fromQr = (input.qrData?.trim().isNotEmpty ?? false);
  var note = parsed.note;
  if (fromQr && note == null) note = 'Scanned from the QR on the receipt.';
  return VerifyResult.receipt(
    ReceiptData(
      verified: true,
      bankCode: bank.id,
      bankName: bank.name,
      reference: parsed.reference ?? reference,
      senderName: parsed.senderName,
      senderAccount: parsed.senderAccount,
      receiverName: parsed.receiverName,
      receiverAccount: parsed.receiverAccount,
      amount: parsed.amount,
      currency: parsed.currency,
      date: parsed.date,
      branch: parsed.branch,
      reason: parsed.reason,
      transactionType: parsed.transactionType,
      transactionStatus: parsed.transactionStatus,
      invoiceNumber: parsed.invoiceNumber,
      bankAccountNumber: parsed.bankAccountNumber,
      bankAccountName: parsed.bankAccountName,
      note: note,
      fromQr: fromQr,
    ),
    sw.elapsedMilliseconds,
  );
}
