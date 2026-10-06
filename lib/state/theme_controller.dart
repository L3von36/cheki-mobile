import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide theme mode state: follow system, force light or force dark,
/// persisted in [SharedPreferences] and exposed through `provider`.
/// The switcher lives in the settings sheet.
class ThemeController extends ChangeNotifier {
  ThemeController({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;

  static const String _kKey = 'mahtem.theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  /// Restores the persisted choice; with nothing saved yet the app
  /// defaults to light mode (System is only used when explicitly picked).
  /// Safe to call more than once.
  void ensureLoaded() {
    final raw = _prefs?.getString(_kKey);
    final restored = _decode(raw);
    if (restored != _mode) {
      _mode = restored;
      notifyListeners();
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      await _prefs?.setString(_kKey, _encode(mode));
    } catch (_) {
      // Persistence failed — the choice still applies for this session.
    }
  }

  /// Cycles system → light → dark → system (handy for a quick toggle).
  Future<void> cycle() => switch (_mode) {
    ThemeMode.system => setMode(ThemeMode.light),
    ThemeMode.light => setMode(ThemeMode.dark),
    ThemeMode.dark => setMode(ThemeMode.system),
  };

  static String _encode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };

  static ThemeMode _decode(String? raw) => switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    // First launch / no saved choice: ship light by default.
    _ => ThemeMode.light,
  };
}
