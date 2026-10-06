import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/localization/app_strings.dart';
import 'package:mahtem/state/locale_controller.dart';
import 'package:mahtem/state/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('theme mode persists across controllers', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final controller = ThemeController(prefs: prefs)..ensureLoaded();
    expect(controller.mode, ThemeMode.light); // default with nothing saved

    await controller.setMode(ThemeMode.dark);
    expect(controller.mode, ThemeMode.dark);

    final restored = ThemeController(prefs: prefs)..ensureLoaded();
    expect(restored.mode, ThemeMode.dark);
  });

  test('theme cycle walks light → dark → system → light', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs: prefs)..ensureLoaded();

    await controller.cycle();
    expect(controller.mode, ThemeMode.dark);
    await controller.cycle();
    expect(controller.mode, ThemeMode.system);
    await controller.cycle();
    expect(controller.mode, ThemeMode.light);
  });

  test('explicit system choice still restores as system', () async {
    SharedPreferences.setMockInitialValues({'mahtem.theme_mode': 'system'});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs: prefs)..ensureLoaded();
    expect(controller.mode, ThemeMode.system);
  });

  test('locale persists and the string catalog follows', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final controller = LocaleController(prefs: prefs)..ensureLoaded();
    expect(controller.locale, AppLocale.english);
    expect(controller.isAmharic, isFalse);
    expect(controller.strings.verifyReceiptButton, 'VERIFY RECEIPT');

    await controller.setLocale(AppLocale.amharic);
    expect(controller.isAmharic, isTrue);
    expect(controller.materialLocale, const Locale('am'));
    expect(controller.strings.welcomeBack, 'እንኳን ደህና መጡ');

    final restored = LocaleController(prefs: prefs)..ensureLoaded();
    expect(restored.locale, AppLocale.amharic);
    expect(restored.strings.locale, AppLocale.amharic);
  });

  test('toggle flips between English and Amharic', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = LocaleController(prefs: prefs)..ensureLoaded();

    await controller.toggle();
    expect(controller.locale, AppLocale.amharic);
    await controller.toggle();
    expect(controller.locale, AppLocale.english);
  });

  test('Tigrinya persists and uses the Ethiopic script flag', () async {
    SharedPreferences.setMockInitialValues({'mahtem.locale': 'ti'});
    final prefs = await SharedPreferences.getInstance();
    final controller = LocaleController(prefs: prefs)..ensureLoaded();

    expect(controller.locale, AppLocale.tigrinya);
    expect(controller.usesEthiopicScript, isTrue);
    expect(controller.materialLocale, const Locale('ti'));
    expect(controller.strings.welcomeBack, 'ብደሓን ተመሊስኩም');

    // Oromo stays Latin-script: the flag is Ethiopic-only.
    await controller.setLocale(AppLocale.oromo);
    expect(controller.usesEthiopicScript, isFalse);
  });

  test('controllers without prefs still work (in-memory only)', () async {
    final theme = ThemeController()..ensureLoaded();
    await theme.setMode(ThemeMode.light);
    expect(theme.mode, ThemeMode.light);

    final locale = LocaleController()..ensureLoaded();
    await locale.setLocale(AppLocale.amharic);
    expect(locale.isAmharic, isTrue);
  });
}
