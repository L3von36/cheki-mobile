import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/cheki_client.dart';

/// Live status of the verification backend, used by the home screen's
/// "System Online" banner and the bank picker's availability dots.
class SystemStatus extends ChangeNotifier {
  SystemStatus({ChekiClient? client}) : _client = client ?? ChekiClient();

  final ChekiClient _client;

  bool loading = false;
  bool online = false;
  String? version;

  /// Live per-bank availability, keyed by bank id
  /// (`reachable` / `geo-blocked` / `unreachable` / `in-development`).
  Map<String, String> bankStatus = {};

  DateTime? lastChecked;

  /// Overall status for the home banner: `online` | `degraded` | `offline`.
  String get level {
    if (!online) return 'offline';
    final live = bankStatus.values
        .where((s) => s == 'reachable' || s == 'geo-blocked')
        .length;
    if (live == 0) return 'degraded';
    return 'online';
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final response = await _client.httpClient
          .get(Uri.parse('${_client.baseUrl}/api/health'))
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      online = (json['status'] as String? ?? '') == 'ok';
      version = json['version'] as String?;
      final banks = json['banks'] as List? ?? const [];
      bankStatus = {
        for (final b in banks)
          if (b is Map &&
              (b['id'] as String? ?? b['code'] as String?) != null)
            (b['id'] ?? b['code']) as String: (b['status'] as String? ?? 'unknown'),
      };
    } catch (_) {
      online = false;
    }
    loading = false;
    lastChecked = DateTime.now();
    notifyListeners();
  }

  /// Status label for one bank, e.g. for a picker dot tooltip.
  String? statusFor(String bankId) => bankStatus[bankId];

  /// True when the bank is currently usable end-to-end.
  bool bankUsable(String bankId) {
    final s = bankStatus[bankId];
    return s == null || s == 'reachable' || s == 'live';
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
