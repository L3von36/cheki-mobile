import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pointycastle/api.dart' as pc;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/digests/sha1.dart';

import '../models.dart';
import 'parsers.dart';

// Native verification engine — Mahtem's own implementation.
///
/// Talks to each bank's public receipt endpoint directly from the device:
///   * no middleman server, no API key, no rate limits beyond the bank's own
///   * geo-restricted wallets (Telebirr, M-Pesa) work because the phone is
///     on an Ethiopian network — the old hosted API could never reach them
///
/// Flow: build the bank URL → fetch (retries + backoff + per-bank TLS
/// policy) → parse into a [VerifyResult]. Failures always resolve to a
/// failed [VerifyResult] so the UI can show something actionable.

/// Bank receipt URL builders + endpoint metadata.
const String _cbeNewApi = 'https://Mb.cbe.com.et/api/v1/transactions/public/transaction-detail';

String buildReceiptUrl({
  required String bank,
  required String reference,
  String? accountNumber,
  String? phoneNumber,
}) {
  switch (bank) {
    case 'cbe-new':
      return '$_cbeNewApi/$reference';
    case 'cbe':
      // Legacy FT system was decommissioned; point at the new API anyway —
      // some newer FT refs resolve there.
      return '$_cbeNewApi/$reference';
    case 'telebirr':
      final ref = reference.trim();
      if (ref.toLowerCase().startsWith('http')) {
        // A full receipt link was pasted as the reference — pull the
        // transaction number out of any link shape we know.
        final m = RegExp(r'/receipt/([^/?#]+)', caseSensitive: false)
            .firstMatch(ref);
        if (m != null) {
          return 'https://transactioninfo.ethiotelecom.et/receipt/${m.group(1)}';
        }
        return ref;
      }
      return 'https://transactioninfo.ethiotelecom.et/receipt/$ref';
    case 'boa':
      final suffix = (accountNumber ?? '').trim();
      final last5 = suffix.length >= 5 ? suffix.substring(suffix.length - 5) : suffix;
      return 'https://cs.bankofabyssinia.com/api/onlineSlip/getDetails/?id=$reference$last5';
    case 'mpesa':
      return 'https://m-pesabusiness.safaricom.et/api/receipt/getReceipt?trxNo=$reference';
    case 'dashen':
      return 'https://receipt.dashensuperapp.com/receipt/$reference';
    case 'awash':
      final token = reference.replaceFirst(RegExp(r'^-'), '');
      return 'https://awashpay.awashbank.com:8225/-$token';
    case 'zemen':
      return 'https://share.zemenbank.com/rt/$reference/pdf';
    case 'cbebirr':
      return 'https://cbepay1.cbe.com.et/aureceipt?TID=$reference&PH=$phoneNumber';
    case 'siinqee':
      final ref = reference.trim();
      if (ref.startsWith('http')) return ref;
      if (ref.contains('/')) return 'https://receipt.ebirr.com/$ref';
      return 'https://receipt.ebirr.com/siinqee/$ref';
    case 'ebirr':
      final ref = reference.trim();
      if (ref.startsWith('http')) return ref;
      return 'https://receipt.ebirr.com/$ref';
    default:
      return '';
  }
}

/// Result contract so tests can stub the engine.
abstract class VerifyEngine {
  Future<VerifyResult> verify({
    required String bank,
    required String reference,
    String? accountNumber,
    String? phoneNumber,
  });
}

/// The real engine — fetches and parses bank endpoints natively.
class NativeVerifier implements VerifyEngine {
  NativeVerifier({http.Client? client, this.timeout = const Duration(seconds: 25)})
      : _ownedClient = client == null,
        _client = client ?? http.Client();

  final bool _ownedClient;
  final http.Client _client;
  final Duration timeout;

  static const int _maxAttempts = 3;
  static const Duration _backoff = Duration(milliseconds: 600);

  void dispose() {
    if (_ownedClient) _client.close();
  }

  // ------------------------------------------------------------- verification

  @override
  Future<VerifyResult> verify({
    required String bank,
    required String reference,
    String? accountNumber,
    String? phoneNumber,
  }) async {
    final started = DateTime.now();
    final url = buildReceiptUrl(
      bank: bank,
      reference: reference,
      accountNumber: accountNumber,
      phoneNumber: phoneNumber,
    );

    if (url.isEmpty) {
      return _failure(bank, reference, 'Unsupported bank.', started);
    }

    final fetch = await _fetchWithRetry(bank, url);
    if (!fetch.ok) {
      return VerifyResult(
        success: false,
        verified: false,
        bank: bank,
        reference: reference,
        sourceUrl: url,
        error: fetch.error,
        fallbackUrl: url,
        durationMs: _elapsed(started),
      );
    }

    final parsed = _parse(bank, fetch.body, fetch.bytes);
    if (!parsed.verified) {
      return VerifyResult(
        success: true,
        verified: false,
        bank: bank,
        bankName: _bankName(bank),
        reference: reference,
        sourceUrl: url,
        reason: _notFoundMessage(bank),
        fallbackUrl: url,
        durationMs: _elapsed(started),
      );
    }

    return VerifyResult(
      success: true,
      verified: true,
      bank: bank,
      bankName: _bankName(bank),
      reference: parsed.reference ?? reference,
      sourceUrl: url,
      senderName: parsed.senderName,
      senderAccount: parsed.senderAccount,
      receiverName: parsed.receiverName,
      receiverAccount: parsed.receiverAccount,
      amount: parsed.amount,
      currency: parsed.currency,
      date: parsed.date,
      branch: parsed.branch,
      reason: parsed.reason,
      transactionStatus: parsed.transactionStatus,
      fallbackUrl: url,
      durationMs: _elapsed(started),
    );
  }

  // ------------------------------------------------------------------- fetch

  Future<_FetchOutcome> _fetchWithRetry(String bank, String url) async {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
      'Accept': 'application/json, text/html, application/pdf, */*',
    };
    if (bank == 'cbe' || bank == 'cbe-new') {
      headers['X-App-ID'] = 'd1292e42-7400-49de-a2d3-9731caa4c819';
      headers['X-App-Version'] = '0a01980b-9859-1369-8198-59f403820000';
      headers['Accept'] = 'application/json';
    }

    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        final request = http.Request('GET', Uri.parse(url))..followRedirects = true;
        request.headers.addAll(headers);

        final streamed = await _send(request, trustAll: bank == 'awash');
        final response = await http.Response.fromStream(streamed)
            .timeout(timeout);

        if (response.statusCode == 404) {
          return _FetchOutcome.error(_notFoundMessage(bank));
        }
        if (response.statusCode == 200 || response.statusCode == 202) {
          return _FetchOutcome.ok(response.body, response.bodyBytes);
        }
        lastError = _statusMessage(bank, response.statusCode);
      } on TimeoutException {
        lastError = 'The bank took too long to respond. Try again.';
      } on SocketException {
        lastError = 'No connection. Check your internet and try again.';
      } on HandshakeException {
        lastError = 'Could not establish a secure connection to the bank.';
      } on http.ClientException catch (e) {
        lastError = 'Network error: ${e.message}';
      } catch (e) {
        lastError = 'Unexpected error: $e';
      }
      if (attempt < _maxAttempts - 1) {
        await Future<void>.delayed(_backoff * (1 << attempt));
      }
    }
    return _FetchOutcome.error(
      lastError is String ? lastError : 'Could not reach the bank. Try again.',
    );
  }

  Future<http.StreamedResponse> _send(
    http.Request request, {
    required bool trustAll,
  }) async {
    if (!trustAll) return _client.send(request);
    // Awash serves its receipt portal on a non-publicly-trusted certificate.
    final ioClient = HttpClient()..badCertificateCallback = ((cert, host, port) => true);
    final trusting = IOClient(ioClient);
    try {
      return await trusting.send(request).timeout(timeout);
    } finally {
      // Close on a microtask so the streamed response can finish reading.
      Future<void>.delayed(const Duration(minutes: 2), trusting.close);
    }
  }

  // ------------------------------------------------------------------- parse

  ParsedReceipt _parse(String bank, String body, Uint8List bytes) {
    switch (bank) {
      case 'cbe':
      case 'cbe-new':
        return parseCbeNew(body);
      case 'boa':
        return parseBoa(body);
      case 'mpesa':
        return parseMpesa(body);
      case 'telebirr':
        return parseTelebirr(body);
      case 'awash':
        return parseAwash(body);
      case 'cbebirr':
        return parseCbeBirr(body);
      case 'siinqee':
      case 'ebirr':
        return parseEbirr(body);
      case 'dashen':
        return parseDashenPdf(bytes);
      case 'zemen':
        return parseZemenPdf(bytes);
      default:
        return const ParsedReceipt(verified: false);
    }
  }

  // ------------------------------------------------------------------ helpers

  String _bankName(String bank) {
    const names = {
      'cbe': 'Commercial Bank of Ethiopia',
      'cbe-new': 'Commercial Bank of Ethiopia',
      'telebirr': 'Telebirr',
      'boa': 'Bank of Abyssinia',
      'mpesa': 'M-Pesa Ethiopia',
      'dashen': 'Dashen Bank',
      'awash': 'Awash Bank',
      'zemen': 'Zemen Bank',
      'cbebirr': 'CBE Birr',
      'siinqee': 'Siinqee Bank',
      'ebirr': 'eBirr',
    };
    return names[bank] ?? bank;
  }

  String _notFoundMessage(String bank) {
    switch (bank) {
      case 'cbe':
        return 'Receipt not found. CBE legacy FT references are no longer '
            'supported — ask the sender for the new receipt link '
            '(mbreciept.cbe.com.et) or scan the QR code on the receipt.';
      case 'telebirr':
        return 'Receipt not found. Double-check the transaction number '
            'shown on the Telebirr receipt.';
      case 'boa':
        return 'Receipt not found. Check the reference and the last 5 '
            'digits of the receiving account.';
      default:
        return 'Receipt not found. Double-check the reference number.';
    }
  }

  String _statusMessage(String bank, int statusCode) {
    if (statusCode == 429) {
      return 'Too many requests. Wait a moment and try again.';
    }
    if (statusCode >= 500) {
      return 'The bank service is temporarily unavailable. Try again shortly.';
    }
    return 'Request failed (HTTP $statusCode).';
  }

  VerifyResult _failure(String bank, String reference, String message, DateTime started) {
    return VerifyResult(
      success: false,
      verified: false,
      bank: bank,
      reference: reference,
      error: message,
      durationMs: _elapsed(started),
    );
  }

  int _elapsed(DateTime started) => DateTime.now().difference(started).inMilliseconds;
}

class _FetchOutcome {
  final bool ok;
  final String? error;
  final String body;
  final Uint8List bytes;

  _FetchOutcome.ok(this.body, this.bytes)
      : ok = true,
        error = null;
  _FetchOutcome.error(this.error)
      : ok = false,
        body = '',
        bytes = Uint8List(0);
}

// ===========================================================================
// BOA QR decryption
// ===========================================================================

/// Bank of Abyssinia receipt QR codes carry an AES-256-CBC encrypted CSV.
/// Key material is embedded in BOA's own receipt web app.
class BoaQrDecryptor {
  static const _password =
      'ELqVy2g4pGWLUIKSa+1ijwpPy6eDxBFBLBPrJ24v/IA='; // used as UTF-8 text
  static const _salt = 'salt';
  static const _iv = '1234567890123456';
  static const _iterations = 10000;

  /// Decrypts a scanned BOA QR payload into a [ParsedReceipt].
  /// Returns `verified: false` when the payload is not a BOA receipt.
  static ParsedReceipt decrypt(String qrPayload) {
    try {
      final cipherBytes = base64Decode(qrPayload.trim());
      if (cipherBytes.isEmpty || cipherBytes.length % 16 != 0) {
        return const ParsedReceipt(verified: false);
      }
      final key = _deriveKey();
      final cbc = CBCBlockCipher(AESEngine())
        ..init(false, pc.ParametersWithIV<pc.KeyParameter>(
            pc.KeyParameter(key), Uint8List.fromList(utf8.encode(_iv))));

      final plain = Uint8List(cipherBytes.length);
      for (var offset = 0; offset < cipherBytes.length; offset += 16) {
        final block = Uint8List.sublistView(cipherBytes, offset, offset + 16);
        plain.setRange(offset, offset + 16, cbc.process(block));
      }

      final csv = utf8.decode(_stripPkcs7(plain), allowMalformed: true).trim();
      return _parseCsv(csv);
    } catch (_) {
      return const ParsedReceipt(verified: false);
    }
  }

  /// Removes PKCS#7 padding (Node's createDecipheriv does this implicitly).
  static Uint8List _stripPkcs7(Uint8List data) {
    if (data.isEmpty) return data;
    final pad = data.last;
    if (pad >= 1 && pad <= 16 && pad <= data.length) {
      var clean = true;
      for (var i = data.length - pad; i < data.length; i++) {
        if (data[i] != pad) {
          clean = false;
          break;
        }
      }
      if (clean) return Uint8List.sublistView(data, 0, data.length - pad);
    }
    return data;
  }

  static Uint8List _deriveKey() {
    final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))
      ..init(Pbkdf2Parameters(utf8.encode(_salt), _iterations, 32));
    final password = utf8.encode(_password);
    return derivator.process(password);
  }

  static ParsedReceipt _parseCsv(String csv) {
    final parts = csv.split(',').map((s) => s.trim()).toList();
    if (parts.length < 7) return const ParsedReceipt(verified: false);
    final amount = double.tryParse(parts[2].replaceAll(',', ''));
    return ParsedReceipt(
      verified: parts[3].isNotEmpty,
      senderAccount: parts[0],
      senderName: parts[1],
      receiverAccount: parts[5],
      receiverName: parts[6],
      amount: amount,
      date: parts[4],
      reference: parts[3],
    );
  }
}
