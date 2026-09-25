import 'package:flutter/material.dart';

/// Persists the user's theme choice across the app session.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode != ThemeMode.light;

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void set(ThemeMode value) {
    _mode = value;
    notifyListeners();
  }
}
