import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Typed client for the Mahtem Worker admin API.
///
///   GET https://mahtem-api.mahtem.workers.dev/v1/admin/overview
///   Authorization: Bearer `ADMIN_KEY`
///   X-Mahtem-Client: mahtem-admin-app
///
/// The Worker answers 401 for a wrong key, 503 when the ADMIN_KEY secret
/// is not configured, and otherwise a JSON overview document (see
/// cloud/worker.js → buildAdminOverview). Native HTTP — no CORS involved.

// ── Models ──────────────────────────────────────────────────────────────────

class AdminTotals {
  const AdminTotals({
    required this.accounts,
    required this.vaults,
    required this.scans,
    required this.verified,
    required this.scansToday,
    required this.scans7d,
    required this.scanningAccounts7d,
  });

  final int accounts;
  final int vaults;
  final int scans;
  final int verified;
  final int scansToday;
  final int scans7d;
  final int scanningAccounts7d;

  factory AdminTotals.fromJson(Map<String, dynamic> j) => AdminTotals(
        accounts: _int(j['accounts']),
        vaults: _int(j['vaults']),
        scans: _int(j['scans']),
        verified: _int(j['verified']),
        scansToday: _int(j['scansToday']),
        scans7d: _int(j['scans7d']),
        scanningAccounts7d: _int(j['scanningAccounts7d']),
      );
}

class AdminBank {
  const AdminBank({required this.id, required this.name, required this.count});

  final String id;
  final String name;
  final int count;

  factory AdminBank.fromJson(Map<String, dynamic> j) => AdminBank(
        id: _str(j['id']),
        name: _str(j['name']),
        count: _int(j['count']),
      );
}

class AdminDay {
  const AdminDay({required this.day, required this.count});

  /// UTC date, YYYY-MM-DD.
  final String day;
  final int count;

  factory AdminDay.fromJson(Map<String, dynamic> j) => AdminDay(
        day: _str(j['day']),
        count: _int(j['count']),
      );
}

class AdminAccountRow {
  const AdminAccountRow({
    required this.id,
    required this.createdAt,
    required this.revision,
    required this.updatedAt,
    required this.scans,
    required this.lastScanAt,
    required this.topBank,
  });

  /// 8-hex prefix — the server never exposes full identifier digests.
  final String id;
  final int? createdAt;
  final int? revision;
  final int? updatedAt;
  final int scans;
  final int? lastScanAt;
  final String? topBank;

  factory AdminAccountRow.fromJson(Map<String, dynamic> j) => AdminAccountRow(
        id: _str(j['id']),
        createdAt: _intOrNull(j['createdAt']),
        revision: _intOrNull(j['revision']),
        updatedAt: _intOrNull(j['updatedAt']),
        scans: _int(j['scans']),
        lastScanAt: _intOrNull(j['lastScanAt']),
        topBank: _strOrNull(j['topBank']),
      );
}

class AdminRecentEvent {
  const AdminRecentEvent({
    required this.t,
    required this.bankId,
    required this.bankName,
    required this.verified,
    required this.userId,
  });

  final int t;
  final String bankId;
  final String bankName;

  /// 1 = receipt verified, 0 = verification failed.
  final int verified;

  /// 8-hex account prefix.
  final String userId;

  factory AdminRecentEvent.fromJson(Map<String, dynamic> j) =>
      AdminRecentEvent(
        t: _int(j['t']),
        bankId: _str(j['b']),
        bankName: _str(j['n']),
        verified: _int(j['v']),
        userId: _str(j['u']),
      );
}

class AdminOverview {
  const AdminOverview({
    required this.generatedAt,
    required this.totals,
    required this.banks,
    required this.days,
    required this.accounts,
    required this.recent,
  });

  final int generatedAt;
  final AdminTotals totals;
  final List<AdminBank> banks;
  final List<AdminDay> days;
  final List<AdminAccountRow> accounts;
  final List<AdminRecentEvent> recent;

  factory AdminOverview.fromJson(Map<String, dynamic> j) => AdminOverview(
        generatedAt: _int(j['generatedAt']),
        totals: AdminTotals.fromJson(_map(j['totals'])),
        banks: _list(j['banks']).map(AdminBank.fromJson).toList(),
        days: _list(j['days']).map(AdminDay.fromJson).toList(),
        accounts: _list(j['accounts']).map(AdminAccountRow.fromJson).toList(),
        recent: _list(j['recent']).map(AdminRecentEvent.fromJson).toList(),
      );
}

// ── Errors ──────────────────────────────────────────────────────────────────

enum AdminErrorType { badKey, disabled, network, server, invalidResponse }

class AdminException implements Exception {
  const AdminException(this.type, this.status, this.message);

  final AdminErrorType type;
  final int status;
  final String message;

  @override
  String toString() => 'AdminException($type, $status): $message';
}

// ── Client ──────────────────────────────────────────────────────────────────

abstract class AdminApiClient {
  Future<AdminOverview> overview(String key);
}

class AdminApi implements AdminApiClient {
  AdminApi({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        base = baseUri ??
            Uri.parse('https://mahtem-api.mahtem.workers.dev/v1/admin/overview');

  final http.Client _client;
  final Uri base;

  static const timeout = Duration(seconds: 25);
  static const clientHeader = 'mahtem-admin-app';

  @override
  Future<AdminOverview> overview(String key) async {
    final http.Response res;
    try {
      res = await _client
          .get(
            base,
            headers: {
              'Authorization': 'Bearer $key',
              'X-Mahtem-Client': clientHeader,
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AdminException(
        AdminErrorType.network,
        0,
        "Can't reach the Mahtem API — request timed out.",
      );
    } on SocketException {
      throw const AdminException(
        AdminErrorType.network,
        0,
        "Can't reach the Mahtem API. Check your connection and try again.",
      );
    } on http.ClientException {
      throw const AdminException(
        AdminErrorType.network,
        0,
        "Can't reach the Mahtem API. Check your connection and try again.",
      );
    }

    if (res.statusCode == 401) {
      throw const AdminException(
        AdminErrorType.badKey,
        401,
        'Invalid admin key. Check the ADMIN_KEY and try again.',
      );
    }
    if (res.statusCode == 503) {
      throw const AdminException(
        AdminErrorType.disabled,
        503,
        'Admin access is not configured on this deployment '
        '(ADMIN_KEY secret missing).',
      );
    }
    if (res.statusCode != 200) {
      throw AdminException(
        AdminErrorType.server,
        res.statusCode,
        'Mahtem API error (HTTP ${res.statusCode}). Try again shortly.',
      );
    }

    final Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('expected a JSON object');
      }
      body = decoded;
    } on FormatException {
      throw const AdminException(
        AdminErrorType.invalidResponse,
        200,
        'Unexpected response from the Mahtem API.',
      );
    }

    try {
      _validateShape(body);
      return AdminOverview.fromJson(body);
    } on AdminException {
      rethrow;
    } on Object {
      throw const AdminException(
        AdminErrorType.invalidResponse,
        200,
        'Unexpected response from the Mahtem API.',
      );
    }
  }

  /// The Worker contract is explicit — reject documents that are missing
  /// any section instead of silently rendering zeros.
  void _validateShape(Map<String, dynamic> body) {
    if (body['generatedAt'] is! int ||
        body['totals'] is! Map<String, dynamic> ||
        body['banks'] is! List ||
        body['days'] is! List ||
        body['accounts'] is! List ||
        body['recent'] is! List) {
      throw const AdminException(
        AdminErrorType.invalidResponse,
        200,
        'Unexpected response from the Mahtem API.',
      );
    }
  }
}

// ── JSON helpers (strict-cast friendly) ─────────────────────────────────────

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

int? _intOrNull(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

String _str(Object? v) => v is String ? v : '';

String? _strOrNull(Object? v) => v is String ? v : null;

Map<String, dynamic> _map(Object? v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

List<Map<String, dynamic>> _list(Object? v) => v is List
    ? v
        .whereType<Map<String, dynamic>>()
        .toList() // skip corrupt entries instead of crashing the console
    : const <Map<String, dynamic>>[];
