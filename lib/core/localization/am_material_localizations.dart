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

/// Same idea for Afaan Oromoo (om) — Qubee is Latin script, so the
/// default fonts already render it; only the labels need overriding.
class _OmMaterialLocalizations extends DefaultMaterialLocalizations {
  const _OmMaterialLocalizations();

  // ── text-selection toolbar (the strings users actually see) ─────────
  @override
  String get copyButtonLabel => 'Kopii godhi';
  @override
  String get cutButtonLabel => 'Ciniini';
  @override
  String get pasteButtonLabel => 'Dabi';
  @override
  String get selectAllButtonLabel => 'Hunda fili';
  @override
  String get lookUpButtonLabel => 'Barbaadi';
  @override
  String get searchWebButtonLabel => 'Interneetii barbaadi';
  @override
  String get shareButtonLabel => 'Qoodi';

  // ── common tooltips ─────────────────────────────────────────────────
  @override
  String get backButtonTooltip => "Deebi'i";
  @override
  String get closeButtonTooltip => 'Cufi';
}

/// Same idea for Cupertino localizations — nothing Amharic-specific to
/// override (no cupertino surfaces in Mahtem), but claiming support for
/// `am` keeps the localization warning out of every boot.
class MahtemCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const MahtemCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      const {'en', 'am', 'om'}.contains(locale.languageCode);

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
      const {'en', 'am', 'om'}.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) async =>
      switch (locale.languageCode) {
        'am' => const _AmMaterialLocalizations(),
        'om' => const _OmMaterialLocalizations(),
        _ => const DefaultMaterialLocalizations(),
      };

  @override
  bool shouldReload(MahtemLocalizationsDelegate old) => false;
}
