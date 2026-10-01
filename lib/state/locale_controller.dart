import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/localization/app_strings.dart';

/// App-wide language state: English or Amharic (አማርኛ), persisted in
/// [SharedPreferences] and exposed through `provider`. Screens read
/// localized strings from [strings] — switch the language and every
/// listening screen rebuilds in the new language.
class LocaleController extends ChangeNotifier {
  LocaleController({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;

  static const String _kKey = 'mahtem.locale';

  AppLocale _locale = AppLocale.english;

  AppLocale get locale => _locale;

  bool get isAmharic => _locale == AppLocale.amharic;

  /// The string catalog for the current language.
  AppStrings get strings => AppStrings.of(_locale);

  Locale get materialLocale => _locale.materialLocale;

  /// Restores the persisted choice (defaults to English for a fresh
  /// install). Safe to call more than once.
  void ensureLoaded() {
    final code = _prefs?.getString(_kKey);
    final restored = AppLocale.fromCode(code);
    if (restored != _locale) {
      _locale = restored;
      notifyListeners();
    }
  }

  Future<void> setLocale(AppLocale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
    try {
      await _prefs?.setString(_kKey, locale.code);
    } catch (_) {
      // Persistence failed — the choice still applies for this session.
    }
  }

  /// Toggles between English and Amharic — the switcher's fast path.
  Future<void> toggle() =>
      setLocale(isAmharic ? AppLocale.english : AppLocale.amharic);
}
