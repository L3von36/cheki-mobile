import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

export 'models.dart' show ChekiException, VerifyResult;

/// A client for the free cheki receipt verification API.
///
/// Wraps the four REST endpoints exposed by https://chekiapp.vercel.app:
///  * `POST /api/verify`        — verify a single receipt
///  * `POST /api/verify/batch`  — verify up to 50 receipts
///  * `GET  /api/banks`         — live bank list
///  * `GET  /api/health`        — service health
///
/// Retries transient failures (429 / 5xx) with exponential backoff and
/// enforces a per-request timeout (CBE's legacy PDF endpoint can take
/// 10-30 seconds, hence the generous default).
class ChekiClient {
  /// Base URL of the cheki API (no trailing slash).
  final String baseUrl;

  /// Underlying HTTP client — injectable for tests.
  final http.Client httpClient;

  /// Per-attempt timeout. Defaults to 60s (CBE PDFs are slow).
  final Duration? timeout;

  static const int _maxRetries = 3;
  static const Duration _baseBackoff = Duration(milliseconds: 200);

  static const Map<String, String> _defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': 'cheki-mobile/1.0.0 (Flutter; Android)',
  };

  ChekiClient({
    String? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  })  : baseUrl =
            (baseUrl ?? 'https://chekiapp.vercel.app').replaceAll(RegExp(r'/+$'), ''),
        httpClient = client ?? http.Client();

  /// Verifies a single receipt.
  ///
  /// [bank] is a bank code from the registry (`cbe`, `telebirr`, ...).
  /// [reference] is the transaction reference. Some banks additionally
  /// require [accountNumber] (CBE: last 8 digits, BOA: last 5 digits) or
  /// [phoneNumber] (CBE Birr).
  Future<VerifyResult> verify({
    required String bank,
    required String reference,
    String? accountNumber,
    String? phoneNumber,
  }) async {
    final response = await _send(
      () => httpClient.post(
        Uri.parse('$baseUrl/api/verify'),
        headers: _defaultHeaders,
        body: jsonEncode({
          'bank': bank,
          'reference': reference,
          if (accountNumber != null && accountNumber.isNotEmpty)
            'accountNumber': accountNumber,
          if (phoneNumber != null && phoneNumber.isNotEmpty)
            'phoneNumber': phoneNumber,
        }),
      ),
      path: '/api/verify',
    );
    return VerifyResult.fromJson(_decode(response));
  }

  /// Verifies up to 50 receipts in one request.
  Future<BatchResult> verifyBatch(List<BatchReceipt> receipts) async {
    final response = await _send(
      () => httpClient.post(
        Uri.parse('$baseUrl/api/verify/batch'),
        headers: _defaultHeaders,
        body: jsonEncode({
          'receipts': receipts.map((r) => r.toJson()).toList(),
        }),
      ),
      path: '/api/verify/batch',
    );
    return BatchResult.fromJson(_decode(response));
  }

  /// Live list of supported banks from the API.
  Future<List<BankInfo>> getBanks() async {
    final response = await _send(
      () => httpClient.get(
        Uri.parse('$baseUrl/api/banks'),
        headers: _defaultHeaders,
      ),
      path: '/api/banks',
    );
    final json = _decode(response);
    final banks = json['banks'] as List? ?? const [];
    return banks
        .map((e) => BankInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Service health check.
  Future<HealthInfo> getHealth() async {
    final response = await _send(
      () => httpClient.get(
        Uri.parse('$baseUrl/api/health'),
        headers: _defaultHeaders,
      ),
      path: '/api/health',
    );
    final json = _decode(response);
    return HealthInfo(
      status: json['status'] as String? ?? 'unknown',
      version: json['version'] as String?,
    );
  }

  /// Builds the public web URL for a verified receipt (viewable/shareable).
  String receiptUrl(String bank, String reference) =>
      '$baseUrl/receipt/$bank/$reference';

  void close() => httpClient.close();

  // ---------------------------------------------------------------------

  Future<http.Response> _send(
    Future<http.Response> Function() requestFn, {
    required String path,
  }) async {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      http.Response response;
      try {
        final future = requestFn();
        response = timeout != null ? await future.timeout(timeout!) : await future;
      } on http.ClientException catch (e) {
        throw ChekiException('Network error: ${e.message}');
      } on TimeoutException {
        throw ChekiException(
          'The bank is taking too long to respond. Try again.',
          statusCode: 408,
        );
      }

      final retryable = response.statusCode == 429 || response.statusCode >= 500;
      if (retryable && attempt < _maxRetries) {
        await Future<void>.delayed(_baseBackoff * (1 << attempt));
        continue;
      }
      _checkStatus(response, path);
      return response;
    }
    throw ChekiException('Max retries exceeded');
  }

  void _checkStatus(http.Response response, String path) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) return;

    String? apiError;
    String? fallbackUrl;
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        apiError = json['error'] as String?;
        fallbackUrl = json['fallbackUrl'] as String?;
      }
    } on FormatException {
      // body wasn't JSON — fall through
    }
    if (response.statusCode == 502 && fallbackUrl != null) {
      throw ChekiException(
        'Geo-blocked endpoint. Try verifying from the web: $fallbackUrl',
        statusCode: code,
      );
    }
    throw ChekiException(
      apiError ?? 'Request failed (HTTP $code)',
      statusCode: code,
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ChekiException(
        'Unexpected API response format',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}

/// A single receipt in a batch verification request.
class BatchReceipt {
  final String bank;
  final String reference;
  final String? accountNumber;
  final String? phoneNumber;

  const BatchReceipt({
    required this.bank,
    required this.reference,
    this.accountNumber,
    this.phoneNumber,
  });

  Map<String, dynamic> toJson() => {
        'bank': bank,
        'reference': reference,
        if (accountNumber != null) 'accountNumber': accountNumber,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
      };
}

/// Aggregate result of a batch verification.
class BatchResult {
  final bool success;
  final int total;
  final int verified;
  final int failed;
  final List<VerifyResult> results;

  const BatchResult({
    required this.success,
    required this.total,
    required this.verified,
    required this.failed,
    required this.results,
  });

  factory BatchResult.fromJson(Map<String, dynamic> json) {
    final results = json['results'] as List? ?? const [];
    return BatchResult(
      success: json['success'] as bool? ?? false,
      total: json['total'] as int? ?? 0,
      verified: json['verified'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
      results: results
          .map((e) => VerifyResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Bank info as returned by `GET /api/banks`.
class BankInfo {
  final String code;
  final String name;
  final String status;
  final String? type;
  final bool requiresAccount;
  final int? accountDigits;
  final bool? requiresPhone;
  final String? color;
  final String? initials;
  final String? notes;

  const BankInfo({
    required this.code,
    required this.name,
    required this.status,
    this.type,
    required this.requiresAccount,
    this.accountDigits,
    this.requiresPhone,
    this.color,
    this.initials,
    this.notes,
  });

  factory BankInfo.fromJson(Map<String, dynamic> json) => BankInfo(
        code: json['code'] as String? ?? json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        status: json['status'] as String? ?? 'unknown',
        type: json['type'] as String?,
        requiresAccount: json['requiresAccount'] as bool? ?? false,
        accountDigits: json['accountDigits'] as int?,
        requiresPhone: json['requiresPhone'] as bool?,
        color: json['color'] as String?,
        initials: json['initials'] as String?,
        notes: json['notes'] as String?,
      );

  bool get isLive => status == 'live';
}

/// Compact health status.
class HealthInfo {
  final String status;
  final String? version;
  const HealthInfo({required this.status, this.version});
}
