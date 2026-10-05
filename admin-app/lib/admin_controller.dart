import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api.dart';

/// Drives the whole console: owner session persistence, sign-in / first-run
/// setup, refresh, live auto-refresh, password change and sign-out.
/// UI listens via ChangeNotifier.
class AdminController extends ChangeNotifier {
  AdminController({AdminApiClient? api, Future<SharedPreferences>? prefs})
      : api = api ?? AdminApi(),
        _prefsFuture = prefs ?? SharedPreferences.getInstance();

  static const _tokenPref = 'mahtem.admin.token';
  static const _emailPref = 'mahtem.admin.email';
  static const _autoPref = 'mahtem.admin.autorefresh';

  /// v1.0.0 stored a static ADMIN_KEY — sessions replace it; retired on boot.
  static const _legacyKeyPref = 'mahtem.admin.key';

  /// The app always sends this header so the Worker can distinguish it.
  static const clientHeader = 'mahtem-admin-app';

  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  final AdminApiClient api;
  final Future<SharedPreferences> _prefsFuture;

  /// null while the session is being restored from storage.
  bool? unlocked;
  bool busy = false;
  String? error;

  /// Machine-readable twin of [error] — used by [restore] to decide
  /// between "stale session" (sign in again) and "network blip" (retry).
  AdminErrorType? lastErrorType;

  /// True when a boot restore failed for a non-auth reason (network /
  /// server): the shell shows a retry screen instead of an endless splash.
  bool restoreFailed = false;
  AdminOverview? overview;
  int? lastUpdatedMs;
  bool autoRefresh = true;

  /// The signed-in owner's email (null on the login screen).
  String? email;

  String? _token;
  Timer? _timer;

  /// Restore a persisted session at boot. A session the API no longer
  /// accepts is removed (the owner lands on the sign-in screen). A network
  /// or server failure keeps the session and surfaces [restoreFailed] so
  /// the user can retry — it never logs the owner out.
  Future<void> restore() async {
    final prefs = await _prefsFuture;
    final storedAuto = prefs.getBool(_autoPref);
    if (storedAuto != null) autoRefresh = storedAuto;

    // v1.0.0 upgrades: the static admin key is no longer used.
    if (prefs.getString(_legacyKeyPref) != null) {
      await prefs.remove(_legacyKeyPref);
    }

    final stored = prefs.getString(_tokenPref);
    if (stored == null || stored.isEmpty) {
      unlocked = false;
      notifyListeners();
      return;
    }
    _token = stored;
    email = prefs.getString(_emailPref);
    unlocked = null; // deciding…
    restoreFailed = false;
    notifyListeners();

    final ok = await _load(stored, silent: true);
    if (ok) {
      unlocked = true;
    } else if (lastErrorType == AdminErrorType.sessionExpired ||
        lastErrorType == AdminErrorType.disabled) {
      await _clearSession(prefs);
      unlocked = false;
    } else {
      restoreFailed = true;
    }
    notifyListeners();
  }

  /// Retry a failed boot restore.
  Future<void> retryRestore() async {
    if (_token == null) {
      unlocked = false;
      notifyListeners();
      return;
    }
    restoreFailed = false;
    notifyListeners();
    await restore();
  }

  /// Whether an owner account already exists server-side. Null when the
  /// answer is unknown (offline) — the login screen then shows sign-in and
  /// lets setup fail with the server's own message if it comes to that.
  Future<bool?> fetchHasAdmin() async {
    try {
      return await api.hasAdmin();
    } on AdminException catch (e) {
      return e.type == AdminErrorType.disabled ? false : null;
    }
  }

  /// Sign in with the owner's email + password. Returns true on success;
  /// on failure [error] explains why and nothing is persisted.
  Future<bool> signIn(String emailInput, String password) async {
    final normalized = emailInput.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) {
      error = 'Enter your email and password to continue.';
      notifyListeners();
      return false;
    }
    if (!_emailRe.hasMatch(normalized)) {
      error = 'That does not look like a valid email address.';
      notifyListeners();
      return false;
    }
    error = null;
    busy = true;
    notifyListeners();

    try {
      final session = await api.signIn(normalized, password);
      await _adoptSession(session);
      busy = false;
      unlocked = true;
      _ensureTimer();
      notifyListeners();
      return true;
    } on AdminException catch (e) {
      busy = false;
      error = e.message;
      lastErrorType = e.type;
      notifyListeners();
      return false;
    }
  }

  /// First run: create THE owner account and sign in with it.
  Future<bool> signUpOwner(String emailInput, String password) async {
    final normalized = emailInput.trim().toLowerCase();
    if (!_emailRe.hasMatch(normalized)) {
      error = 'Enter a valid email address — this becomes the owner account.';
      notifyListeners();
      return false;
    }
    if (password.length < 10) {
      error = 'Choose a password of at least 10 characters.';
      notifyListeners();
      return false;
    }
    error = null;
    busy = true;
    notifyListeners();

    try {
      final session = await api.signUpOwner(normalized, password);
      await _adoptSession(session);
      busy = false;
      unlocked = true;
      _ensureTimer();
      notifyListeners();
      return true;
    } on AdminException catch (e) {
      busy = false;
      error = e.message;
      lastErrorType = e.type;
      notifyListeners();
      return false;
    }
  }

  /// Change the owner password. The Worker rotates every session and
  /// returns a fresh one for this device; other devices must sign in again.
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final token = _token;
    if (token == null) return false;
    if (newPassword.length < 10) {
      error = 'New password must be at least 10 characters.';
      notifyListeners();
      return false;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final session = await api.changePassword(token, currentPassword, newPassword);
      _token = session.token;
      final prefs = await _prefsFuture;
      await prefs.setString(_tokenPref, session.token);
      busy = false;
      notifyListeners();
      return true;
    } on AdminException catch (e) {
      busy = false;
      error = e.message;
      lastErrorType = e.type;
      notifyListeners();
      return false;
    }
  }

  /// Manual or silent refresh of the overview. Returns true on success.
  /// On failure the previous snapshot is kept and [error] explains why.
  Future<bool> refresh({bool silent = false}) async {
    final token = _token;
    if (token == null) return false;
    return _load(token, silent: silent);
  }

  static const _detailCacheTtlMs = 60 * 1000;

  final Map<String, AdminAccountDetail> _detailCache = {};
  final Map<String, int> _detailFetchedAt = {};

  /// Per-account drill-down with a 60s per-account cache.
  /// Throws [AdminException] on failure (session expired, not found, …).
  Future<AdminAccountDetail> accountDetail(String uid) async {
    final token = _token;
    if (token == null) {
      throw const AdminException(
        AdminErrorType.sessionExpired,
        401,
        'Session expired — sign in again.',
      );
    }
    final fresh = _detailCache[uid];
    final at = _detailFetchedAt[uid] ?? 0;
    if (fresh != null &&
        DateTime.now().millisecondsSinceEpoch - at < _detailCacheTtlMs) {
      return fresh;
    }
    final detail = await api.accountDetail(token, uid);
    _detailCache[uid] = detail;
    _detailFetchedAt[uid] = DateTime.now().millisecondsSinceEpoch;
    return detail;
  }

  /// Drop cached drill-downs (used when the session rotates).
  void clearDetailCache() {
    _detailCache.clear();
    _detailFetchedAt.clear();
  }

  Future<bool> _load(String token, {bool silent = false}) async {
    if (!silent) {
      busy = true;
      error = null;
      notifyListeners();
    }
    try {
      overview = await api.overview(token);
      lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
      _ensureTimer();
      return true;
    } on AdminException catch (e) {
      error = e.message;
      lastErrorType = e.type;
      return false;
    } finally {
      if (!silent) {
        busy = false;
        notifyListeners();
      } else {
        notifyListeners();
      }
    }
  }

  Future<void> _adoptSession(AdminSession session) async {
    _token = session.token;
    email = session.email;
    clearDetailCache();
    error = null;
    lastErrorType = null;
    final prefs = await _prefsFuture;
    await prefs.setString(_tokenPref, session.token);
    await prefs.setString(_emailPref, session.email);
    await _load(session.token, silent: true);
  }

  /// Toggle the 30s live auto-refresh; the preference persists.
  Future<void> setAutoRefresh(bool on) async {
    autoRefresh = on;
    notifyListeners();
    final prefs = await _prefsFuture;
    await prefs.setBool(_autoPref, on);
    _ensureTimer();
  }

  /// Sign out: revoke the session server-side (best effort), forget
  /// everything local and return to the sign-in screen.
  Future<void> signOut() async {
    _clearTimer();
    final token = _token;
    if (token != null) {
      unawaited(api.logout(token).catchError((_) {}));
    }
    _token = null;
    email = null;
    overview = null;
    lastUpdatedMs = null;
    clearDetailCache();
    error = null;
    lastErrorType = null;
    restoreFailed = false;
    unlocked = false;
    final prefs = await _prefsFuture;
    await _clearSession(prefs);
    notifyListeners();
  }

  void _clearTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _ensureTimer() {
    if (!autoRefresh || _token == null || overview == null) {
      _clearTimer();
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove(_tokenPref);
    await prefs.remove(_emailPref);
  }

  @override
  void dispose() {
    _clearTimer();
    super.dispose();
  }
}
