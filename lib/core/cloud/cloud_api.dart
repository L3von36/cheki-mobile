/// HTTP client for the Mahtem Cloud API (Cloudflare Worker `mahtem-api`,
/// v1.13.0). Thin, typed, and offline-graceful: every failure becomes a
/// [CloudApiException] carrying the server's error code so the controller
/// and UI can react specifically.
///
/// The base URL is public information (the API is public); no secrets
/// live in this file. Every request carries the `X-Mahtem-Client` header
/// the server requires as a cheap bot screen.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

const String kCloudApiBaseUrl = 'https://mahtem.com.et';

/// Errors surfaced to the controller layer.
enum CloudApiError {
  network,
  badInput,
  exists,
  noAccount,
  badCredentials,
  unauthorized,
  conflict,
  receiptUsed,
  empty,
  notFound,
  server,
}

class CloudApiException implements Exception {
  final CloudApiError error;
  final int statusCode;

  /// Server-provided revision for [CloudApiError.conflict].
  final int? serverRevision;
  const CloudApiException(this.error, this.statusCode, {this.serverRevision});

  @override
  String toString() => 'CloudApiException(${error.name}, $statusCode)';
}

class CloudReceiptClaim {
  final int expiresAtMs;
  final bool alreadyClaimed;

  const CloudReceiptClaim({
    required this.expiresAtMs,
    required this.alreadyClaimed,
  });
}

/// Reply from POST /v1/trials/sync — the server's authoritative free-trial
/// budget for this device (and account, when signed in).
class TrialSyncInfo {
  final int used;
  final int freeChecks;
  final int trialsRemaining;
  final bool proActive;
  final int? proUntilMs;

  /// v1.19.3 — which budget `used` belongs to: 'account' when a session
  /// gated the reply, 'device' otherwise. Absent on pre-v1.19.3 servers
  /// (treated as device scope by the license controller).
  final String? scope;

  /// v1.19.3 — the DEVICE ledger number, always present in an `account`
  /// reply. The device budget keeps absorbing every usage server-side;
  /// the signed-out counter gates on this when the backup session is
  /// still live.
  final int? deviceUsed;

  const TrialSyncInfo({
    required this.used,
    required this.freeChecks,
    required this.trialsRemaining,
    required this.proActive,
    this.proUntilMs,
    this.scope,
    this.deviceUsed,
  });
}

/// One verification mirrored to the server-side receipt ledger
/// (POST /v1/receipts). Built from a local [HistoryEntry] by the cloud
/// controller; the server dedupes per (account, entryId).
class CloudReceiptRecord {
  final String entryId;
  final String bankId;
  final String bankName;
  final String reference;

  /// The untouched scan input the check ran with — QR payload, receipt
  /// link or the OCR'd reference (what the receipt was verified BY).
  final String? rawPayload;
  final String? senderName;
  final String? receiverName;
  final double? amount;
  final String? currency;
  final String? receiptDate;

  /// 'verified' | 'failed'
  final String status;
  final String? message;
  final String? reason;
  final int verifiedAtMs;

  const CloudReceiptRecord({
    required this.entryId,
    required this.bankId,
    required this.bankName,
    required this.reference,
    this.rawPayload,
    this.senderName,
    this.receiverName,
    this.amount,
    this.currency,
    this.receiptDate,
    required this.status,
    this.message,
    this.reason,
    required this.verifiedAtMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entryId': entryId,
        'bankId': bankId,
        'bankName': bankName,
        'reference': reference,
        if (rawPayload != null) 'rawPayload': rawPayload,
        if (senderName != null) 'senderName': senderName,
        if (receiverName != null) 'receiverName': receiverName,
        if (amount != null) 'amount': amount,
        if (currency != null) 'currency': currency,
        if (receiptDate != null) 'receiptDate': receiptDate,
        'status': status,
        if (message != null) 'message': message,
        if (reason != null) 'reason': reason,
        'verifiedAt': verifiedAtMs,
      };

  factory CloudReceiptRecord.fromJson(Map<String, dynamic> json) =>
      CloudReceiptRecord(
        entryId: json['entryId'] as String? ?? '',
        bankId: json['bankId'] as String? ?? '',
        bankName: json['bankName'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        rawPayload: json['rawPayload'] as String?,
        senderName: json['senderName'] as String?,
        receiverName: json['receiverName'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        receiptDate: json['receiptDate'] as String?,
        status: json['status'] as String? ?? 'failed',
        message: json['message'] as String?,
        reason: json['reason'] as String?,
        verifiedAtMs: json['verifiedAt'] as int? ?? 0,
      );
}

class CloudSession {
  /// The access token (JWT or legacy session token).
  final String sessionToken;

  /// Rotating refresh token for renewing the access token.
  final String? refreshToken;

  final String userId;
  final int expiresAtMs;

  const CloudSession({
    required this.sessionToken,
    required this.refreshToken,
    required this.userId,
    required this.expiresAtMs,
  });

  /// Alias for OAuth 2.0 terminology.
  String get accessToken => sessionToken;
}

class CloudVaultRemote {
  final String blob;
  final int revision;
  final int updatedAtMs;
  final bool notModified;

  const CloudVaultRemote({
    required this.blob,
    required this.revision,
    required this.updatedAtMs,
    this.notModified = false,
  });
}

/// A BetterAuth identity (v1.19.0). [email] is what Better Auth stores —
/// for phone-number accounts it is the synthetic `<intl>@phone.mahtem.et`
/// mapping (see [betterAuthEmailFor]); reverse it with
/// [identifierFromBetterAuthEmail].
class BetterAuthUser {
  final String id;
  final String email;
  final String name;

  const BetterAuthUser({required this.id, required this.email, required this.name});
}

/// A BetterAuth session: the raw session token used as
/// `Authorization: Bearer <token>` everywhere (the server's bearer plugin
/// and the /v1 bridge both accept it).
class BetterAuthSession {
  final String token;
  final BetterAuthUser user;

  const BetterAuthSession({required this.token, required this.user});
}

/// Reply from POST /api/auth/device/code — the OAuth 2.0 device grant.
class BetterAuthDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String? verificationUriComplete;
  final int expiresInSeconds;
  final int intervalSeconds;

  const BetterAuthDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    this.verificationUriComplete,
    required this.expiresInSeconds,
    required this.intervalSeconds,
  });
}

/// Outcome of one /api/auth/device/token poll — see
/// [BetterAuthPollOutcome] at the bottom of this file.

/// The email Better Auth sees for a normalized account identifier.
/// Phone numbers map onto a reserved synthetic domain the server maps
/// straight back; emails pass through 1:1.
String betterAuthEmailFor(String normalizedIdentifier) {
  final id = normalizedIdentifier.trim().toLowerCase();
  if (id.contains('@')) return id;
  return '$id@phone.mahtem.et';
}

/// Inverse of [betterAuthEmailFor] — the readable identifier (normalized)
/// behind a Better Auth email.
String identifierFromBetterAuthEmail(String email) {
  final value = email.trim().toLowerCase();
  final at = value.lastIndexOf('@');
  if (at <= 0) return value;
  final local = value.substring(0, at);
  if (value.endsWith('@phone.mahtem.et') && RegExp(r'^[0-9]+$').hasMatch(local)) {
    return local;
  }
  return value;
}

class CloudApi {
  CloudApi({http.Client? client, String baseUrl = kCloudApiBaseUrl})
      : _client = client ?? http.Client(),
        baseUrl = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri baseUrl;

  static const Duration _timeout = Duration(seconds: 25);
  static const Duration _retryDelay = Duration(milliseconds: 600);
  static const Map<String, String> _clientHeader = {
    'X-Mahtem-Client': 'mahtem-android',
  };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
    Map<String, String>? queryParameters,
  }) async {
    final baseUri = baseUrl.replace(path: path);
    final uri = queryParameters != null && queryParameters.isNotEmpty
        ? baseUri.replace(queryParameters: queryParameters)
        : baseUri;

    // Transport failures get one quiet second attempt. Mobile networks blip
    // constantly (tower handoffs, radios waking from idle), and a first
    // sign-in on a new device chains 4-5 sequential calls — without this,
    // a single blip aborts the whole flow and the user must retype their
    // password. Only transport errors retry; an HTTP status is an answer,
    // never a failure. /v1/session/refresh rotates a single-use token, so
    // a possibly-consumed attempt must never be replayed.
    final retriable = path != '/v1/session/refresh';
    for (var attempt = 1;; attempt++) {
      http.Response resp;
      try {
        resp = await _transmit(method, uri, body: body, bearer: bearer);
      } catch (_) {
        if (!retriable || attempt >= 2) {
          throw const CloudApiException(CloudApiError.network, 0);
        }
        await Future<void>.delayed(_retryDelay);
        continue;
      }
      return _decode(resp);
    }
  }

  Future<http.Response> _transmit(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(_clientHeader);
    if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(_timeout);
  }

  Map<String, dynamic> _decode(http.Response resp) {
    Map<String, dynamic>? decoded;
    try {
      if (resp.body.isNotEmpty) {
        final d = jsonDecode(resp.body);
        if (d is Map<String, dynamic>) decoded = d;
      }
    } catch (_) {
      decoded = null;
    }

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return decoded ?? const {};
    }
    throw CloudApiException(
      _errorFor(resp.statusCode, decoded?['error'] as String?),
      resp.statusCode,
      serverRevision: (decoded?['revision'] as num?)?.toInt(),
    );
  }

  static CloudApiError _errorFor(int status, String? code) {
    switch (code) {
      case 'exists':
        return CloudApiError.exists;
      case 'no_account':
        return CloudApiError.noAccount;
      case 'bad_credentials':
        return CloudApiError.badCredentials;
      case 'unauthorized':
        return CloudApiError.unauthorized;
      case 'conflict':
        return CloudApiError.conflict;
      case 'receipt_used':
        return CloudApiError.receiptUsed;
      case 'empty':
        return CloudApiError.empty;
      case 'bad_input':
        return CloudApiError.badInput;
      case 'not_found':
        return CloudApiError.notFound;
    }
    // Status-code fallbacks — the error code can be missing when a proxy,
    // CDN or gateway answers instead of the Worker itself.
    if (status == 401) return CloudApiError.unauthorized;
    if (status == 409) return CloudApiError.conflict;
    if (status == 404) return CloudApiError.notFound;
    return status >= 500 || status == 0
        ? CloudApiError.server
        : CloudApiError.network;
  }

  // ── endpoints ──────────────────────────────────────────────────────────

  /// Creates the cloud account. [identifierHash] and [authKey] are both
  /// 64-hex digests derived on-device.
  ///
  /// [identifier] (the readable phone/email the user typed, normalized) and
  /// [displayName] ride along so the account is recognizable in the admin
  /// database (v1.18.9). Both optional: older servers ignore them, and
  /// omitting them keeps the legacy hash-only behavior. The password itself
  /// is never sent — only the derived digests.
  Future<void> createAccount({
    required String identifierHash,
    required String authKey,
    String? identifier,
    String? displayName,
  }) =>
      _send('POST', '/v1/accounts', body: {
        'identifierHash': identifierHash,
        'authKey': authKey,
        if (identifier != null && identifier.isNotEmpty) 'identifier': identifier,
        if (displayName != null && displayName.isNotEmpty)
          'displayName': displayName,
      });

  Future<bool> lookupAccount({required String identifierHash}) async {
    final r = await _send('POST', '/v1/accounts/lookup',
        body: {'identifierHash': identifierHash});
    return r['exists'] == true;
  }

  /// Server view of this device's free-trial budget
  /// (POST /v1/trials/sync). No session required — pre-sign-up devices
  /// sync keyed by [deviceHashHex] alone; a [sessionToken] adds the
  /// account-level budget (v1.19.3: gated on the ACCOUNT's own ledger,
  /// never the device's). [accountScope] declares which account the
  /// client's [used] belongs to — only then may the server count it
  /// against that account (legacy clients' device-global numbers are
  /// ignored server-side). Returns null on a malformed reply.
  Future<TrialSyncInfo?> syncTrials({
    String? sessionToken,
    required String deviceHashHex,
    int? used,
    String? accountScope,
  }) async {
    final r = await _send('POST', '/v1/trials/sync',
        bearer:
            (sessionToken == null || sessionToken.isEmpty) ? null : sessionToken,
        body: {
          'deviceHash': deviceHashHex,
          if (used != null) 'used': used,
          if (accountScope != null && accountScope.isNotEmpty)
            'accountScope': accountScope,
        });
    final pro = r['pro'];
    if (pro is! Map) return null;
    return TrialSyncInfo(
      used: (r['used'] as num?)?.toInt() ?? 0,
      freeChecks: (r['freeChecks'] as num?)?.toInt() ?? 0,
      trialsRemaining: (r['trialsRemaining'] as num?)?.toInt() ?? 0,
      proActive: pro['active'] == true,
      proUntilMs: (pro['until'] as num?)?.toInt(),
      scope: r['scope'] is String ? r['scope'] as String? : null,
      deviceUsed: (r['deviceUsed'] as num?)?.toInt(),
    );
  }

  Future<CloudSession> createSession({
    required String identifierHash,
    required String authKey,
    String? identifier,
    String? displayName,
  }) async {
    final r = await _send('POST', '/v1/session', body: {
      'identifierHash': identifierHash,
      'authKey': authKey,
      if (identifier != null && identifier.isNotEmpty) 'identifier': identifier,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    });
    return CloudSession(
      sessionToken:
          r['accessToken'] as String? ?? r['sessionToken'] as String? ?? '',
      refreshToken: r['refreshToken'] as String?,
      userId: r['userId'] as String? ?? '',
      expiresAtMs: (r['expiresAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// Exchanges a valid [refreshToken] for a new short-lived access token
  /// (JWT) and a newly rotated refresh token.
  Future<CloudSession> refreshSession(String refreshToken) async {
    final r = await _send('POST', '/v1/session/refresh', body: {
      'refreshToken': refreshToken,
    });
    return CloudSession(
      sessionToken:
          r['accessToken'] as String? ?? r['sessionToken'] as String? ?? '',
      refreshToken: r['refreshToken'] as String?,
      userId: r['userId'] as String? ?? '',
      expiresAtMs: (r['expiresAt'] as num?)?.toInt() ?? 0,
    );
  }

  Future<bool> checkSession(String sessionToken) async {
    try {
      await _send('GET', '/v1/session', bearer: sessionToken);
      return true;
    } on CloudApiException catch (e) {
      if (e.error == CloudApiError.unauthorized) return false;
      rethrow;
    }
  }

  Future<void> deleteSession(String sessionToken) =>
      _send('DELETE', '/v1/session', bearer: sessionToken);

  /// Revokes a refresh token and session.
  Future<void> revokeSession({
    String? sessionToken,
    String? refreshToken,
  }) =>
      _send('POST', '/v1/auth/revoke', bearer: sessionToken, body: {
        if (refreshToken != null) 'refreshToken': refreshToken,
      });

  /// Uploads the encrypted vault. When [baseRevision] is given the write
  /// is optimistic: a newer stored revision raises
  /// [CloudApiError.conflict] (with `serverRevision`).
  ///
  Future<void> putVault({
    required String sessionToken,
    required String blob,
    required int revision,
    int? baseRevision,
  }) =>
      _send('PUT', '/v1/vault', bearer: sessionToken, body: {
        'blob': blob,
        'revision': revision,
        if (baseRevision != null) 'baseRevision': baseRevision,
      });

  /// Returns null when the server holds no vault yet (404 `empty`).
  Future<CloudVaultRemote?> getVault(
    String sessionToken, {
    int? sinceRevision,
  }) async {
    try {
      final r = await _send(
        'GET',
        '/v1/vault',
        bearer: sessionToken,
        queryParameters: sinceRevision != null
            ? {'sinceRevision': '$sinceRevision'}
            : null,
      );
      if (r['notModified'] == true) {
        return CloudVaultRemote(
          blob: '',
          revision: (r['revision'] as num?)?.toInt() ?? sinceRevision ?? 0,
          updatedAtMs: 0,
          notModified: true,
        );
      }
      return CloudVaultRemote(
        blob: r['blob'] as String? ?? '',
        revision: (r['revision'] as num?)?.toInt() ?? 0,
        updatedAtMs: (r['updatedAt'] as num?)?.toInt() ?? 0,
      );
    } on CloudApiException catch (e) {
      if (e.error == CloudApiError.empty) return null;
      rethrow;
    }
  }

  Future<void> deleteVault(String sessionToken) =>
      _send('DELETE', '/v1/vault', bearer: sessionToken);

  Future<CloudReceiptClaim> claimProReceipt({
    required String sessionToken,
    required String receiptHash,
    required double amountEtb,
    required int planDays,
    int? paidAtMs,
  }) async {
    final r = await _send('POST', '/v1/pro/claim', bearer: sessionToken, body: {
      'receiptHash': receiptHash,
      'amountEtb': amountEtb,
      'planDays': planDays,
      if (paidAtMs != null) 'paidAtMs': paidAtMs,
    });
    return CloudReceiptClaim(
      expiresAtMs: (r['expiresAt'] as num?)?.toInt() ?? 0,
      alreadyClaimed: r['alreadyClaimed'] == true,
    );
  }

  Future<DateTime?> getProExpiry(String sessionToken) async {
    final r = await _send('GET', '/v1/pro/status', bearer: sessionToken);
    final expiresAt = (r['expiresAt'] as num?)?.toInt();
    return expiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true);
  }

  /// Records one verification in the server-side receipt ledger. The
  /// server dedupes per (account, entryId), so retries are idempotent —
  /// a later retry with a reason note only moves the note.
  Future<void> putReceipt({
    required String sessionToken,
    required CloudReceiptRecord receipt,
  }) =>
      _send('POST', '/v1/receipts', bearer: sessionToken, body: receipt.toJson());

  /// Erases the account's whole server-side receipt ledger. Privacy twin
  /// of [deleteVault]: disconnecting the cloud account also removes the
  /// readable receipt history.
  Future<void> deleteReceipts(String sessionToken) =>
      _send('DELETE', '/v1/receipts', bearer: sessionToken);

  // ── BetterAuth identity layer (v1.19.0) ─────────────────────────────

  /// Fixed OAuth device-grant client id the app presents to
  /// /api/auth/device/*. The server does not validate it (no client
  /// registry) but binds it to the grant, so it must match at poll time.
  static const String betterAuthClientId = 'mahtem-app';

  static const Map<String, String> _originHeader = {
    // Better Auth CSRF protection requires state-changing POSTs to carry a
    // trusted Origin. Native apps are exempt once they hold a bearer token
    // — but sign-up/sign-in happen before any token exists, so the client
    // presents its own API origin, which the server trusts.
    'Origin': kCloudApiBaseUrl,
  };

  /// Thin sender for /api/auth/* endpoints: same transport retry as
  /// [_send], but Better Auth-aware decoding (its error bodies carry
  /// `code`/`message`, and unauthenticated get-session replies 200/null).
  Future<({int status, Map<String, dynamic>? body})> _sendBa(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async {
    final uri = baseUrl.replace(path: path);
    for (var attempt = 1;; attempt++) {
      http.Response resp;
      try {
        final request = http.Request(method, uri)
          ..headers.addAll(_clientHeader)
          ..headers.addAll(_originHeader);
        if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
        if (body != null) {
          request.headers['Content-Type'] = 'application/json';
          request.body = jsonEncode(body);
        }
        resp = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(_timeout);
      } catch (_) {
        if (attempt >= 2) {
          throw const CloudApiException(CloudApiError.network, 0);
        }
        await Future<void>.delayed(_retryDelay);
        continue;
      }
      Map<String, dynamic>? decoded;
      try {
        final d = jsonDecode(resp.body);
        if (d is Map<String, dynamic>) decoded = d;
      } catch (_) {
        decoded = null;
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return (status: resp.statusCode, body: decoded);
      }
      throw CloudApiException(_betterAuthErrorFor(resp.statusCode, decoded), resp.statusCode);
    }
  }

  static CloudApiError _betterAuthErrorFor(
    int status,
    Map<String, dynamic>? body,
  ) {
    final code = (body?['code'] ?? body?['error'])?.toString().toUpperCase();
    switch (code) {
      case 'USER_ALREADY_EXISTS':
      case 'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL':
        return CloudApiError.exists;
      case 'INVALID_EMAIL_OR_PASSWORD':
      case 'INVALID_PASSWORD':
      case 'BAD_CREDENTIALS':
        return CloudApiError.badCredentials;
      case 'AUTHORIZATION_PENDING':
        return CloudApiError.empty; // still pending — poll again
      case 'SLOW_DOWN':
        return CloudApiError.conflict;
      case 'EXPIRED_TOKEN':
      case 'ACCESS_DENIED':
        return CloudApiError.notFound;
    }
    if (status == 401) return CloudApiError.badCredentials;
    if (status == 422) return CloudApiError.exists;
    if (status == 404) return CloudApiError.notFound;
    if (status == 403) return CloudApiError.unauthorized;
    return status >= 500 || status == 0
        ? CloudApiError.server
        : CloudApiError.network;
  }

  static BetterAuthSession _sessionFrom(Map<String, dynamic> body) {
    final user = body['user'];
    final userMap = user is Map<String, dynamic> ? user : const <String, dynamic>{};
    return BetterAuthSession(
      token: body['token']?.toString() ?? '',
      user: BetterAuthUser(
        id: userMap['id']?.toString() ?? '',
        email: userMap['email']?.toString() ?? '',
        name: userMap['name']?.toString() ?? '',
      ),
    );
  }

  /// Creates the BetterAuth identity for [identifier] (a NORMALIZED
  /// account identifier — phone numbers ride the synthetic-email mapping).
  Future<BetterAuthSession> betterAuthSignUp({
    required String identifier,
    required String displayName,
    required String password,
  }) async {
    final r = await _sendBa('POST', '/api/auth/sign-up/email', body: {
      'name': displayName,
      'email': betterAuthEmailFor(identifier),
      'password': password,
    });
    return _sessionFrom(r.body ?? const <String, dynamic>{});
  }

  /// Signs in through BetterAuth. Unknown identity and wrong password are
  /// the same 401 server-side (enumeration-safe) — the directory layer
  /// distinguishes them with the legacy-migration fallback.
  Future<BetterAuthSession> betterAuthSignIn({
    required String identifier,
    required String password,
  }) async {
    final r = await _sendBa('POST', '/api/auth/sign-in/email', body: {
      'email': betterAuthEmailFor(identifier),
      'password': password,
    });
    return _sessionFrom(r.body ?? const <String, dynamic>{});
  }

  /// Returns null when the token is dead (get-session answers 200/null).
  Future<BetterAuthSession?> betterAuthGetSession(String token) async {
    final r = await _sendBa('GET', '/api/auth/get-session', bearer: token);
    final body = r.body;
    if (body == null || body.isEmpty || body['user'] == null) return null;
    return _sessionFrom(<String, dynamic>{
      'token': token,
      'user': body['user'],
    });
  }

  Future<void> betterAuthSignOut(String token) =>
      _sendBa('POST', '/api/auth/sign-out', bearer: token);

  /// Which social providers the server has configured — the sign-in UI
  /// hides the GitHub entry when it is not enabled yet.
  Future<bool> githubSignInEnabled() async {
    try {
      final r = await _send('GET', '/v1/auth/providers');
      return r['github'] == true;
    } on CloudApiException {
      return false;
    }
  }

  /// Starts the GitHub device flow (RFC 8628): open
  /// [BetterAuthDeviceCode.verificationUriComplete] in a browser, then poll
  /// [betterAuthDeviceToken].
  Future<BetterAuthDeviceCode> betterAuthDeviceCode() async {
    final r = await _sendBa('POST', '/api/auth/device/code', body: {
      'client_id': betterAuthClientId,
    });
    final body = r.body ?? const <String, dynamic>{};
    final interval = (body['interval'] as num?)?.toInt() ?? 5;
    return BetterAuthDeviceCode(
      deviceCode: body['device_code']?.toString() ?? '',
      userCode: body['user_code']?.toString() ?? '',
      verificationUri: body['verification_uri']?.toString() ?? '',
      verificationUriComplete:
          body['verification_uri_complete']?.toString(),
      expiresInSeconds: (body['expires_in'] as num?)?.toInt() ?? 900,
      intervalSeconds: interval < 3 ? 3 : interval,
    );
  }

  /// One device-grant poll. Throws [CloudApiException] for transport
  /// trouble; every RFC 8628 answer comes back as a status instead.
  Future<(BetterAuthPollOutcome, BetterAuthSession?)> betterAuthDeviceToken(
    String deviceCode,
  ) async {
    final r = await _sendBa('POST', '/api/auth/device/token', body: {
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      'device_code': deviceCode,
      'client_id': betterAuthClientId,
    });
    if (r.status == 200 && r.body != null && r.body!['access_token'] != null) {
      final body = r.body!;
      final user = body['user'];
      final userMap = user is Map<String, dynamic> ? user : const <String, dynamic>{};
      return (
        BetterAuthPollOutcome.success,
        BetterAuthSession(
          token: body['access_token'].toString(),
          user: BetterAuthUser(
            id: userMap['id']?.toString() ?? '',
            email: userMap['email']?.toString() ?? '',
            name: userMap['name']?.toString() ?? '',
          ),
        ),
      );
    }
    final code = (r.body?['error'] ?? '').toString();
    switch (code) {
      case 'authorization_pending':
        return (BetterAuthPollOutcome.pending, null);
      case 'slow_down':
        return (BetterAuthPollOutcome.slowDown, null);
      case 'expired_token':
        return (BetterAuthPollOutcome.expired, null);
      case 'access_denied':
        return (BetterAuthPollOutcome.denied, null);
    }
    throw CloudApiException(CloudApiError.network, r.status);
  }

  /// Upgrades a proven legacy (zero-knowledge) account to BetterAuth: the
  /// server re-checks the PBKDF2 proof, creates/links the BetterAuth user
  /// with [password] and returns the new bearer session. The user_id —
  /// and with it the vault, ledger, Pro plan and trial budget — carries
  /// over untouched.
  Future<BetterAuthSession> betterAuthMigrateLegacy({
    required String identifierHash,
    required String authKey,
    required String identifier,
    required String password,
    String? displayName,
  }) async {
    final r = await _sendBa('POST', '/v1/auth/legacy-migrate', body: {
      'identifierHash': identifierHash,
      'authKey': authKey,
      'identifier': identifier,
      'password': password,
      if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
    });
    return _sessionFrom(r.body ?? const <String, dynamic>{});
  }
}

/// Outcome buckets for [CloudApi.betterAuthDeviceToken] polling.
enum BetterAuthPollOutcome { pending, slowDown, expired, denied, success }
