import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Typed client for the Mahtem Worker admin API.
///
/// Auth (v1.1.0): a real owner account — email + password.
///
///   GET  /v1/admin/auth/status          → {hasAdmin}           (no auth)
///   POST /v1/admin/auth/setup           → AdminSession         (first run)
///   POST /v1/admin/auth/login           → AdminSession
///   GET  /v1/admin/auth/me              → {email,…}            (session)
///   POST /v1/admin/auth/logout          → {ok}                 (session)
///   POST /v1/admin/auth/change-password → AdminSession (rotated)
///   GET  /v1/admin/overview             → overview document    (session)
///
/// Authenticated calls carry `Authorization: Bearer <session token>` plus
/// the `X-Mahtem-Client` bot-screen header. Native HTTP — no CORS involved.
/// The password is only ever sent to the auth endpoints; the Worker stores
/// it as a salted PBKDF2-SHA-256 hash and nothing reversible ever exists.

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
    this.scans30d = 0,
  });

  final int accounts;
  final int vaults;
  final int scans;
  final int verified;
  final int scansToday;
  final int scans7d;
  final int scanningAccounts7d;

  /// v1.17+ API — rolling 30-day scan count.
  final int scans30d;

  factory AdminTotals.fromJson(Map<String, dynamic> j) => AdminTotals(
        accounts: _int(j['accounts']),
        vaults: _int(j['vaults']),
        scans: _int(j['scans']),
        verified: _int(j['verified']),
        scansToday: _int(j['scansToday']),
        scans7d: _int(j['scans7d']),
        scanningAccounts7d: _int(j['scanningAccounts7d']),
        scans30d: _intOrNull(j['scans30d']) ?? 0,
      );
}

class AdminBank {
  const AdminBank({
    required this.id,
    required this.name,
    required this.count,
    this.verified = 0,
  });

  final String id;
  final String name;
  final int count;

  /// Verified scan count for this bank (v1.17+ API).
  final int verified;

  factory AdminBank.fromJson(Map<String, dynamic> j) => AdminBank(
        id: _str(j['id']),
        name: _str(j['name']),
        count: _int(j['count']),
        verified: _intOrNull(j['verified']) ?? 0,
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

/// Returned by setup, login and change-password. The token is the session
/// credential sent as `Authorization: Bearer <token>` afterwards.
class AdminSession {
  const AdminSession({
    required this.token,
    required this.email,
    required this.expiresAt,
  });

  final String token;
  final String email;

  /// Epoch ms.
  final int expiresAt;

  factory AdminSession.fromJson(Map<String, dynamic> j) => AdminSession(
        token: _str(j['token']),
        email: _str(j['email']),
        expiresAt: _intOrNull(j['expiresAt']) ?? 0,
      );
}

class AdminMe {
  const AdminMe({
    required this.email,
    required this.expiresAt,
    this.ownerCreatedAt,
  });

  final String email;

  /// Epoch ms, when this session dies.
  final int? expiresAt;
  final int? ownerCreatedAt;

  factory AdminMe.fromJson(Map<String, dynamic> j) => AdminMe(
        email: _str(j['email']),
        expiresAt: _intOrNull(j['expiresAt']),
        ownerCreatedAt: _intOrNull(j['ownerCreatedAt']),
      );
}

/// Per-account drill-down (GET /v1/admin/account/<8-hex prefix>, v1.17+).
class AdminAccountDetail {
  const AdminAccountDetail({
    required this.id,
    required this.createdAt,
    required this.revision,
    required this.updatedAt,
    required this.scans,
    required this.verified,
    required this.lastScanAt,
    required this.banks,
    required this.days,
    required this.events,
  });

  /// 8-hex prefix.
  final String id;
  final int? createdAt;
  final int? revision;
  final int? updatedAt;
  final int scans;
  final int verified;
  final int? lastScanAt;
  final List<AdminBank> banks;
  final List<AdminDay> days;
  final List<AdminEventDetail> events;

  factory AdminAccountDetail.fromJson(Map<String, dynamic> j) =>
      AdminAccountDetail(
        id: _str(j['id']),
        createdAt: _intOrNull(j['createdAt']),
        revision: _intOrNull(j['revision']),
        updatedAt: _intOrNull(j['updatedAt']),
        scans: _int(j['scans']),
        verified: _int(j['verified']),
        lastScanAt: _intOrNull(j['lastScanAt']),
        banks: (j['banks'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdminBank.fromJson)
            .toList(),
        days: (j['days'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdminDay.fromJson)
            .toList(),
        events: (j['events'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AdminEventDetail.fromJson)
            .toList(),
      );
}

/// One scan event inside [AdminAccountDetail] (no account prefix — implicit).
class AdminEventDetail {
  const AdminEventDetail({
    required this.t,
    required this.bankId,
    required this.bankName,
    required this.verified,
  });

  final int t;
  final String bankId;
  final String bankName;
  final int verified;

  factory AdminEventDetail.fromJson(Map<String, dynamic> j) => AdminEventDetail(
        t: _int(j['t']),
        bankId: _str(j['b']),
        bankName: _str(j['n']),
        verified: _int(j['v']),
      );
}

// ── Errors ──────────────────────────────────────────────────────────────────

enum AdminErrorType {
  /// Overview rejected the stored session — sign in again.
  sessionExpired,

  /// Wrong email or password on login / change-password.
  badCredentials,

  /// Too many failed logins for this email (429).
  rateLimited,

  /// The owner account already exists (setup).
  alreadyExists,

  /// No owner account exists yet (login / me-ish operations).
  noAdmin,

  /// Password shorter than 10 chars or invalid email shape.
  badInput,

  /// No account matches the requested prefix (404).
  notFound,

  /// Admin never configured on this deployment (503).
  disabled,

  /// Socket / timeout / unreachable.
  network,

  /// 5xx from the Worker.
  server,

  /// 2xx but not the JSON document we expect.
  invalidResponse,
}

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
  Future<AdminOverview> overview(String token);

  Future<AdminAccountDetail> accountDetail(String token, String uid);

  Future<bool> hasAdmin();

  Future<AdminSession> signIn(String email, String password);

  Future<AdminSession> signUpOwner(String email, String password);

  Future<AdminMe> me(String token);

  Future<void> logout(String token);

  Future<AdminSession> changePassword(
    String token,
    String currentPassword,
    String newPassword,
  );
}

class AdminApi implements AdminApiClient {
  AdminApi({http.Client? client, Uri? baseUri})
      : _client = client ?? http.Client(),
        base = baseUri ?? Uri.parse('https://mahtem-api.mahtem.workers.dev');

  final http.Client _client;

  /// Root of the Worker deployment — auth + data endpoints hang off it.
  final Uri base;

  static const timeout = Duration(seconds: 25);
  static const clientHeader = 'mahtem-admin-app';

  Uri _uri(String path) => base.replace(path: path);

  Map<String, String> _headers({String? token}) {
    final h = <String, String>{'X-Mahtem-Client': clientHeader};
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  Future<http.Response> _send(Future<http.Response> Function() fn) async {
    try {
      return await fn().timeout(timeout);
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
  }

  Future<Map<String, dynamic>> _safeBody(http.Response res) async {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      /* fall through — non-JSON error body */
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _readJson(http.Response res) async {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      /* fall through */
    }
    throw const AdminException(
      AdminErrorType.invalidResponse,
      200,
      'Unexpected response from the Mahtem API.',
    );
  }

  AdminErrorType _typeFor(int status, Map<String, dynamic> body) {
    switch (body['error']) {
      case 'weak_password':
        return AdminErrorType.badInput;
      case 'bad_input':
        return AdminErrorType.badInput;
      case 'bad_credentials':
        return AdminErrorType.badCredentials;
      case 'admin_session_expired':
        return AdminErrorType.sessionExpired;
      case 'rate_limited':
        return AdminErrorType.rateLimited;
      case 'exists':
        return AdminErrorType.alreadyExists;
      case 'no_admin':
        return AdminErrorType.noAdmin;
      case 'not_found':
        return AdminErrorType.notFound;
      case 'ambiguous':
        return AdminErrorType.badInput;
      case 'admin_disabled':
        return AdminErrorType.disabled;
      case 'admin_required':
        return status == 503
            ? AdminErrorType.disabled
            : AdminErrorType.sessionExpired;
      default:
        return AdminErrorType.server;
    }
  }

  Never _throwHttp(
    int status,
    Map<String, dynamic> body,
    AdminErrorType fallback,
  ) {
    final type = status == 200 ? fallback : _typeFor(status, body);
    var message = (body['message'] as String?)?.trim() ?? '';
    if (message.isEmpty) message = _defaultMessage(type, status);
    throw AdminException(type, status, message);
  }

  String _defaultMessage(AdminErrorType type, int status) {
    switch (type) {
      case AdminErrorType.sessionExpired:
        return 'Session expired — sign in again.';
      case AdminErrorType.badCredentials:
        return 'Wrong email or password.';
      case AdminErrorType.rateLimited:
        return 'Too many attempts. Try again in a few minutes.';
      case AdminErrorType.alreadyExists:
        return 'An owner account already exists. Please sign in.';
      case AdminErrorType.noAdmin:
        return 'No owner account exists yet. Create one first.';
      case AdminErrorType.badInput:
        return 'Check the fields and try again.';
      case AdminErrorType.notFound:
        return 'No account matches this prefix.';
      case AdminErrorType.disabled:
        return 'Admin access is not configured on this deployment.';
      case AdminErrorType.network:
        return "Can't reach the Mahtem API.";
      case AdminErrorType.invalidResponse:
        return 'Unexpected response from the Mahtem API.';
      case AdminErrorType.server:
        return 'Mahtem API error (HTTP $status). Try again shortly.';
    }
  }

  // ── data ────────────────────────────────────────────────────────────────

  @override
  Future<AdminOverview> overview(String token) async {
    final res = await _send(
      () => _client.get(_uri('/v1/admin/overview'), headers: _headers(token: token)),
    );
    if (res.statusCode != 200) {
      _throwHttp(
        res.statusCode,
        await _safeBody(res),
        res.statusCode == 401
            ? AdminErrorType.sessionExpired
            : AdminErrorType.server,
      );
    }

    final body = await _readJson(res);
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

  @override
  Future<AdminAccountDetail> accountDetail(String token, String uid) async {
    final prefix = uid.toLowerCase();
    if (prefix.length < 8 || prefix.length > 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(prefix)) {
      throw const AdminException(
        AdminErrorType.badInput,
        0,
        'Account prefix must be 8-64 hex characters.',
      );
    }
    final res = await _send(
      () => _client.get(
            _uri('/v1/admin/account/$prefix'),
            headers: _headers(token: token),
          ),
    );
    if (res.statusCode != 200) {
      _throwHttp(
        res.statusCode,
        await _safeBody(res),
        res.statusCode == 401
            ? AdminErrorType.sessionExpired
            : res.statusCode == 404
                ? AdminErrorType.notFound
                : AdminErrorType.server,
      );
    }
    final body = await _readJson(res);
    try {
      if (body['id'] is! String ||
          body['scans'] is! int ||
          body['banks'] is! List ||
          body['days'] is! List ||
          body['events'] is! List) {
        throw const AdminException(
          AdminErrorType.invalidResponse,
          200,
          'Unexpected response from the Mahtem API.',
        );
      }
      return AdminAccountDetail.fromJson(body);
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

  // ── auth ────────────────────────────────────────────────────────────────

  @override
  Future<bool> hasAdmin() async {
    final res = await _send(
      () => _client.get(_uri('/v1/admin/auth/status'), headers: _headers()),
    );
    if (res.statusCode != 200) {
      _throwHttp(res.statusCode, await _safeBody(res), AdminErrorType.server);
    }
    final body = await _readJson(res);
    return body['hasAdmin'] == true;
  }

  @override
  Future<AdminSession> signIn(String email, String password) async {
    final res = await _send(
      () => _client.post(
        _uri('/v1/admin/auth/login'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{'email': email, 'password': password}),
      ),
    );
    if (res.statusCode != 200) {
      _throwHttp(res.statusCode, await _safeBody(res), AdminErrorType.server);
    }
    final body = await _readJson(res);
    final session = AdminSession.fromJson(body);
    if (session.token.isEmpty) {
      throw const AdminException(
        AdminErrorType.invalidResponse,
        200,
        'Unexpected response from the Mahtem API.',
      );
    }
    return session;
  }

  @override
  Future<AdminSession> signUpOwner(String email, String password) async {
    final res = await _send(
      () => _client.post(
        _uri('/v1/admin/auth/setup'),
        headers: {..._headers(), 'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{'email': email, 'password': password}),
      ),
    );
    if (res.statusCode != 200) {
      _throwHttp(res.statusCode, await _safeBody(res), AdminErrorType.server);
    }
    final body = await _readJson(res);
    final session = AdminSession.fromJson(body);
    if (session.token.isEmpty) {
      throw const AdminException(
        AdminErrorType.invalidResponse,
        200,
        'Unexpected response from the Mahtem API.',
      );
    }
    return session;
  }

  @override
  Future<AdminMe> me(String token) async {
    final res = await _send(
      () => _client.get(_uri('/v1/admin/auth/me'), headers: _headers(token: token)),
    );
    if (res.statusCode != 200) {
      _throwHttp(
        res.statusCode,
        await _safeBody(res),
        AdminErrorType.sessionExpired,
      );
    }
    return AdminMe.fromJson(await _readJson(res));
  }

  @override
  Future<void> logout(String token) async {
    final res = await _send(
      () => _client.post(
        _uri('/v1/admin/auth/logout'),
        headers: _headers(token: token),
      ),
    );
    if (res.statusCode != 200) {
      _throwHttp(res.statusCode, await _safeBody(res), AdminErrorType.server);
    }
  }

  @override
  Future<AdminSession> changePassword(
    String token,
    String currentPassword,
    String newPassword,
  ) async {
    final res = await _send(
      () => _client.post(
        _uri('/v1/admin/auth/change-password'),
        headers: {..._headers(token: token), 'Content-Type': 'application/json'},
        body: jsonEncode(<String, String>{
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      ),
    );
    if (res.statusCode != 200) {
      _throwHttp(res.statusCode, await _safeBody(res), AdminErrorType.server);
    }
    final body = await _readJson(res);
    final session = AdminSession.fromJson(body);
    if (session.token.isEmpty) {
      throw const AdminException(
        AdminErrorType.invalidResponse,
        200,
        'Unexpected response from the Mahtem API.',
      );
    }
    return session;
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
