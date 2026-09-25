import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// One saved verification in the local history.
///
/// Persisted as JSON in shared_preferences so users can look up past
/// checks even offline (the design's "Payment History" screen).
class HistoryEntry {
  final String id;
  final String bankId;
  final String bankName;
  final String reference;

  final String? senderName;
  final String? receiverName;
  final double? amount;
  final String? currency;

  /// Receipt date as reported by the bank.
  final String? receiptDate;

  /// When the check was performed (epoch ms).
  final int verifiedAt;

  /// `verified` | `failed`
  final String status;

  /// Error / failure message for failed checks.
  final String? message;

  /// Direct receipt URL when the bank endpoint was unreachable.
  final String? fallbackUrl;

  const HistoryEntry({
    required this.id,
    required this.bankId,
    required this.bankName,
    required this.reference,
    this.senderName,
    this.receiverName,
    this.amount,
    this.currency,
    this.receiptDate,
    required this.verifiedAt,
    required this.status,
    this.message,
    this.fallbackUrl,
  });

  bool get isVerified => status == 'verified';

  /// Best display title: sender, falling back to the receiver then bank.
  String get title {
    final t = (senderName ?? '').trim();
    if (t.isNotEmpty) return t;
    final r = (receiverName ?? '').trim();
    if (r.isNotEmpty) return r;
    return bankName;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bankId': bankId,
        'bankName': bankName,
        'reference': reference,
        if (senderName != null) 'senderName': senderName,
        if (receiverName != null) 'receiverName': receiverName,
        if (amount != null) 'amount': amount,
        if (currency != null) 'currency': currency,
        if (receiptDate != null) 'receiptDate': receiptDate,
        'verifiedAt': verifiedAt,
        'status': status,
        if (message != null) 'message': message,
        if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String? ?? '',
        bankId: json['bankId'] as String? ?? '',
        bankName: json['bankName'] as String? ?? '',
        reference: json['reference'] as String? ?? '',
        senderName: json['senderName'] as String?,
        receiverName: json['receiverName'] as String?,
        amount: (json['amount'] as num?)?.toDouble(),
        currency: json['currency'] as String?,
        receiptDate: json['receiptDate'] as String?,
        verifiedAt: json['verifiedAt'] as int? ?? 0,
        status: json['status'] as String? ?? 'failed',
        message: json['message'] as String?,
        fallbackUrl: json['fallbackUrl'] as String?,
      );

  /// Builds an entry from an API verification result.
  factory HistoryEntry.fromResult({
    required VerifyResult result,
    required String bankId,
    required String bankName,
    required String referenceFallback,
  }) {
    final verified = result.isVerified;
    return HistoryEntry(
      id: 'v${DateTime.now().microsecondsSinceEpoch}',
      bankId: bankId,
      bankName: result.bankName ?? bankName,
      reference: result.reference ?? referenceFallback,
      senderName: result.senderName,
      receiverName: result.receiverName,
      amount: result.amount,
      currency: result.currency,
      receiptDate: result.date,
      verifiedAt: DateTime.now().millisecondsSinceEpoch,
      status: verified ? 'verified' : 'failed',
      message: verified ? null : (result.error ?? result.reason),
      fallbackUrl: result.fallbackUrl,
    );
  }
}

/// ChangeNotifier that persists the last 100 verifications locally.
class VerifyHistory extends ChangeNotifier {
  static const String _key = 'mahtem.history.v1';
  static const int _maxEntries = 100;

  final List<HistoryEntry> _entries = [];
  bool _loaded = false;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  HistoryEntry? getById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _entries
          ..clear()
          ..addAll(list
              .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList());
      }
    } catch (_) {
      // Corrupt storage — start fresh rather than crash.
    }
    notifyListeners();
  }

  /// Prepends a new entry and persists.
  Future<void> add(HistoryEntry entry) async {
    await _ensureLoaded();
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) _entries.removeRange(_maxEntries, _entries.length);
    notifyListeners();
    await _persist();
  }

  /// Convenience: record straight from a [VerifyResult].
  Future<void> record(
    VerifyResult result, {
    required String bankId,
    required String bankName,
    required String referenceFallback,
  }) =>
      add(HistoryEntry.fromResult(
        result: result,
        bankId: bankId,
        bankName: bankName,
        referenceFallback: referenceFallback,
      ));

  Future<void> remove(String id) async {
    await _ensureLoaded();
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _entries.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Storage full/unavailable — keep the in-memory list working.
    }
  }
}
