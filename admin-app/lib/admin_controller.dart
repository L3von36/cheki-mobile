import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_api.dart';

/// Drives the whole console: key persistence, unlock, refresh, live
/// auto-refresh and sign-out. UI listens via ChangeNotifier.
class AdminController extends ChangeNotifier {
  AdminController({AdminApiClient? api, Future<SharedPreferences>? prefs})
      : api = api ?? AdminApi(),
        _prefsFuture = prefs ?? SharedPreferences.getInstance();

  static const _keyPref = 'mahtem.admin.key';
  static const _autoPref = 'mahtem.admin.autorefresh';

  /// The app always sends this header so the Worker can distinguish it.
  static const clientHeader = 'mahtem-admin-app';

  final AdminApiClient api;
  final Future<SharedPreferences> _prefsFuture;

  /// null while the key is being restored from storage.
  bool? unlocked;
  bool busy = false;
  String? error;

  /// True when a boot restore failed for a non-key reason (network/server):
  /// the shell shows a retry screen instead of an endless splash.
  bool restoreFailed = false;
  AdminOverview? overview;
  int? lastUpdatedMs;
  bool autoRefresh = true;

  String? _key;
  Timer? _timer;

  /// Restore a persisted session at boot. A stale key that the API
  /// rejects is removed (the user lands on the login screen). A network
  /// or server failure keeps the key and surfaces [restoreFailed] so the
  /// user can retry — it never logs the owner out.
  Future<void> restore() async {
    final prefs = await _prefsFuture;
    final stored = prefs.getString(_keyPref);
    final storedAuto = prefs.getBool(_autoPref);
    if (storedAuto != null) autoRefresh = storedAuto;

    if (stored == null || stored.isEmpty) {
      unlocked = false;
      notifyListeners();
      return;
    }
    _key = stored;
    unlocked = null; // deciding…
    restoreFailed = false;
    notifyListeners();

    final ok = await _load(stored, silent: true);
    if (ok) {
      unlocked = true;
    } else if (error?.contains('Invalid admin key') == true) {
      await _clearKey(prefs);
      unlocked = false;
    } else {
      restoreFailed = true;
    }
    notifyListeners();
  }

  /// Retry a failed boot restore.
  Future<void> retryRestore() async {
    if (_key == null) {
      unlocked = false;
      notifyListeners();
      return;
    }
    restoreFailed = false;
    notifyListeners();
    await restore();
  }

  /// Unlock with a typed key. Returns true on success; on failure [error]
  /// explains why and a bad key is NOT persisted.
  Future<bool> unlock(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      error = 'Enter the admin key to continue.';
      notifyListeners();
      return false;
    }
    if (trimmed.length < 16) {
      error = "That doesn't look like a valid ADMIN_KEY (too short).";
      notifyListeners();
      return false;
    }
    error = null;
    busy = true;
    notifyListeners();

    final ok = await _load(trimmed);
    busy = false;
    if (ok) {
      _key = trimmed;
      final prefs = await _prefsFuture;
      await prefs.setString(_keyPref, trimmed);
      unlocked = true;
      _ensureTimer();
    } else if (error?.contains('Invalid admin key') == true) {
      _key = null;
      unlocked = false;
    }
    notifyListeners();
    return ok;
  }

  /// Manual or silent refresh of the overview. Returns true on success.
  /// On failure the previous snapshot is kept and [error] explains why.
  Future<bool> refresh({bool silent = false}) async {
    final key = _key;
    if (key == null) return false;
    return _load(key, silent: silent);
  }

  Future<bool> _load(String key, {bool silent = false}) async {
    if (!silent) {
      busy = true;
      error = null;
      notifyListeners();
    }
    try {
      overview = await api.overview(key);
      lastUpdatedMs = DateTime.now().millisecondsSinceEpoch;
      _ensureTimer();
      return true;
    } on AdminException catch (e) {
      error = e.message;
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

  /// Toggle the 30s live auto-refresh; the preference persists.
  Future<void> setAutoRefresh(bool on) async {
    autoRefresh = on;
    notifyListeners();
    final prefs = await _prefsFuture;
    await prefs.setBool(_autoPref, on);
    _ensureTimer();
  }

  /// Sign out: forget the key and the snapshot, return to login.
  Future<void> signOut() async {
    _timer?.cancel();
    _timer = null;
    _key = null;
    overview = null;
    lastUpdatedMs = null;
    error = null;
    restoreFailed = false;
    unlocked = false;
    final prefs = await _prefsFuture;
    await _clearKey(prefs);
    notifyListeners();
  }

  void _clearTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _ensureTimer() {
    if (!autoRefresh || _key == null || overview == null) {
      _clearTimer();
      return;
    }
    if (_timer != null) return;
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  Future<void> _clearKey(SharedPreferences prefs) async {
    await prefs.remove(_keyPref);
  }

  @override
  void dispose() {
    _clearTimer();
    super.dispose();
  }
}
