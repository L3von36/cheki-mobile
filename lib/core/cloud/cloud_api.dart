/// HTTP client for the Mahtem Cloud API (Cloudflare Worker `mahtem-api`,
/// v1.13.0). Thin, typed, and offline-graceful: every failure becomes a
/// [CloudApiException] carrying the server's error code so the controller
/// and UI can react specifically.
///
/// The base URL is public information (the API is public); no secrets
/// live in this file. Every request carries the `X-Mahtem-Client` header
/// the server requires as a cheap bot screen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String kCloudApiBaseUrl = 'https://mahtem-api.mahtem.workers.dev';

/// Errors surfaced to the controller layer.
enum CloudApiError {
  network,
  badInput,
  exists,
  noAccount,
  badCredentials,
  unauthorized,
  conflict,
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

class CloudSession {
  final String sessionToken;
  final String userId;
  final int expiresAtMs;
  const CloudSession({
    required this.sessionToken,
    required this.userId,
    required this.expiresAtMs,
  });
}

class CloudVaultRemote {
  final String blob;
  final int revision;
  final int updatedAtMs;
  const CloudVaultRemote({
    required this.blob,
    required this.revision,
    required this.updatedAtMs,
  });
}

class CloudApi {
  CloudApi({http.Client? client, String baseUrl = kCloudApiBaseUrl})
      : _client = client ?? http.Client(),
        baseUrl = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri baseUrl;

  static const Duration _timeout = Duration(seconds: 25);
  static const Map<String, String> _clientHeader = {
    'X-Mahtem-Client': 'mahtem-android',
  };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async {
    final http.Response resp;
    try {
      final request = http.Request(method, baseUrl.replace(path: path))
        ..headers.addAll(_clientHeader);
      if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      resp = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_timeout);
    } on TimeoutException {
      throw const CloudApiException(CloudApiError.network, 0);
    } catch (_) {
      throw const CloudApiException(CloudApiError.network, 0);
    }

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
  Future<void> createAccount({
    required String identifierHash,
    required String authKey,
  }) =>
      _send('POST', '/v1/accounts', body: {
        'identifierHash': identifierHash,
        'authKey': authKey,
      });

  Future<bool> lookupAccount({required String identifierHash}) async {
    final r = await _send('POST', '/v1/accounts/lookup',
        body: {'identifierHash': identifierHash});
    return r['exists'] == true;
  }

  Future<CloudSession> createSession({
    required String identifierHash,
    required String authKey,
  }) async {
    final r = await _send('POST', '/v1/session', body: {
      'identifierHash': identifierHash,
      'authKey': authKey,
    });
    return CloudSession(
      sessionToken: r['sessionToken'] as String? ?? '',
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

  /// Uploads the encrypted vault. When [baseRevision] is given the write
  /// is optimistic: a newer stored revision raises
  /// [CloudApiError.conflict] (with `serverRevision`).
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
  Future<CloudVaultRemote?> getVault(String sessionToken) async {
    try {
      final r = await _send('GET', '/v1/vault', bearer: sessionToken);
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
}
