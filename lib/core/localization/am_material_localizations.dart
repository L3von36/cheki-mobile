import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Material localizations for Amharic — Flutter's built-in
/// [DefaultMaterialLocalizations] only speaks English, and `am` is not
/// in flutter_localizations' supported list. Without this delegate every
/// boot in Amharic logs "locale am is not supported" and system menus
/// (copy / paste / select) render in English inside an Amharic UI.
///
/// Everything we don't override falls back to the English defaults —
/// harmless, because Mahtem shows its own localized strings everywhere.
class _AmMaterialLocalizations extends DefaultMaterialLocalizations {
  const _AmMaterialLocalizations();

  // ── text-selection toolbar (the strings users actually see) ─────────
  @override
  String get copyButtonLabel => 'ቅዳ';
  @override
  String get cutButtonLabel => 'ቁረጥ';
  @override
  String get pasteButtonLabel => 'ለጥፍ';
  @override
  String get selectAllButtonLabel => 'ሁሉንም ምረጥ';
  @override
  String get lookUpButtonLabel => 'ፈልግ';
  @override
  String get searchWebButtonLabel => 'በድረ-ገጽ ፈልግ';
  @override
  String get shareButtonLabel => 'አጋራ';

  // ── common tooltips ─────────────────────────────────────────────────
  @override
  String get backButtonTooltip => 'ተመለስ';
  @override
  String get closeButtonTooltip => 'ዝጋ';
}

/// Same idea for Cupertino localizations — nothing Amharic-specific to
/// override (no cupertino surfaces in Mahtem), but claiming support for
/// `am` keeps the localization warning out of every boot.
class MahtemCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const MahtemCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'am'}.contains(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) async =>
      const DefaultCupertinoLocalizations();

  @override
  bool shouldReload(MahtemCupertinoLocalizationsDelegate old) => false;
}

/// Ships English (Flutter defaults) and the Amharic overrides above, so
/// MaterialApp.locale = am no longer warns and selection menus localize.
class MahtemLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const MahtemLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'am'}.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) async =>
      locale.languageCode == 'am'
      ? const _AmMaterialLocalizations()
      : const DefaultMaterialLocalizations();

  @override
  bool shouldReload(MahtemLocalizationsDelegate old) => false;
}
