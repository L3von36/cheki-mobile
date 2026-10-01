import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/localization/app_strings.dart';

bool _hasEthiopic(String text) =>
    text.runes.any((r) => r >= 0x1200 && r <= 0x137F);

void main() {
  // Both catalogs must implement EVERY getter — that's enforced at
  // compile time by the abstract base. These tests guard the content:
  // non-empty strings, the right script per language, and total coverage
  // of the auth error mapping.

  test('every catalog string is non-empty in both languages', () {
    for (final locale in AppLocale.values) {
      final s = AppStrings.of(locale);
      expect(s.verifyTab, isNotEmpty, reason: '${locale.code} verifyTab');
      expect(s.historyTab(0), isNotEmpty);
      expect(s.historyTab(3), contains('3'));
      expect(s.referenceLabel, isNotEmpty);
      expect(s.referenceHint, isNotEmpty);
      expect(s.pickBankHint, isNotEmpty);
      expect(s.phoneOnWallet, isNotEmpty);
      expect(s.lastDigitsOnly(5), contains('5'));
      expect(s.clipboardEmpty, isNotEmpty);
      expect(s.verifyReceiptButton, isNotEmpty);
      expect(s.stopVerifying, isNotEmpty);
      expect(s.autoDetectBank, isNotEmpty);
      expect(s.detected('CBE'), contains('CBE'));
      expect(s.pasteTooltip, isNotEmpty);
      expect(s.scanQrInstead, isNotEmpty);
      expect(s.freeChecksLeft(4), contains('4'));
      expect(s.upgrade, isNotEmpty);
      expect(s.proDaysLeft(12), contains('12'));
      expect(s.welcomeBack, isNotEmpty);
      expect(s.signInSubtitle, isNotEmpty);
      expect(s.createAccountTitle, isNotEmpty);
      expect(s.createAccountSubtitle, isNotEmpty);
      expect(s.fullName, isNotEmpty);
      expect(s.fullNameHint, isNotEmpty);
      expect(s.identifierLabel, isNotEmpty);
      expect(s.identifierHint, isNotEmpty);
      expect(s.passwordLabel, isNotEmpty);
      expect(s.passwordHint, isNotEmpty);
      expect(s.confirmPasswordLabel, isNotEmpty);
      expect(s.signInButton, isNotEmpty);
      expect(s.signInLink, isNotEmpty);
      expect(s.createAccountButton, isNotEmpty);
      expect(s.createAccountLink, isNotEmpty);
      expect(s.noAccountPrompt, isNotEmpty);
      expect(s.haveAccountPrompt, isNotEmpty);
      expect(s.forgotPassword, isNotEmpty);
      expect(s.resetAccountsTitle, isNotEmpty);
      expect(s.resetAccountsBody, isNotEmpty);
      expect(s.resetAccountsConfirm, isNotEmpty);
      expect(s.cancel, isNotEmpty);
      expect(s.ok, isNotEmpty);
      expect(s.showPassword, isNotEmpty);
      expect(s.hidePassword, isNotEmpty);
      expect(s.signingIn, isNotEmpty);
      expect(s.creatingAccount, isNotEmpty);
      expect(s.authPrivacyNote, isNotEmpty);
      expect(s.genericAuthError, isNotEmpty);
      expect(s.settingsTitle, isNotEmpty);
      expect(s.accountSection, isNotEmpty);
      expect(s.signedInAs, isNotEmpty);
      expect(s.appearanceSection, isNotEmpty);
      expect(s.themeSystem, isNotEmpty);
      expect(s.themeLight, isNotEmpty);
      expect(s.themeDark, isNotEmpty);
      expect(s.languageSection, isNotEmpty);
      expect(s.signOut, isNotEmpty);
      expect(s.signOutConfirmTitle, isNotEmpty);
      expect(s.signOutConfirmBody, isNotEmpty);
      expect(s.versionLabel, isNotEmpty);
      expect(s.deviceCodeLabel, isNotEmpty);
      expect(s.copiedToClipboard, isNotEmpty);
      expect(s.close, isNotEmpty);
      expect(s.loading, isNotEmpty);
    }
  });

  test('the English catalog uses the Latin script', () {
    final s = AppStrings.of(AppLocale.english);
    expect(_hasEthiopic(s.welcomeBack), isFalse);
    expect(_hasEthiopic(s.verifyReceiptButton), isFalse);
    expect(s.locale, AppLocale.english);
  });

  test('the Amharic catalog renders Ge\u2019ez (Ethiopic) glyphs', () {
    final s = AppStrings.of(AppLocale.amharic);
    expect(_hasEthiopic(s.welcomeBack), isTrue);
    expect(_hasEthiopic(s.verifyTab), isTrue);
    expect(_hasEthiopic(s.verifyReceiptButton), isTrue);
    expect(_hasEthiopic(s.authPrivacyNote), isTrue);
    expect(s.locale, AppLocale.amharic);
  });

  test('every AuthError maps to a localized message in both languages', () {
    for (final error in AuthError.values) {
      for (final locale in AppLocale.values) {
        final message = AppStrings.of(locale).errorAuth(error);
        expect(
          message,
          isNotEmpty,
          reason: '${locale.code} missing text for $error',
        );
      }
    }
  });

  test('AppLocale round-trips through its persisted code', () {
    expect(AppLocale.fromCode('am'), AppLocale.amharic);
    expect(AppLocale.fromCode('en'), AppLocale.english);
    expect(AppLocale.fromCode(null), AppLocale.english);
    expect(AppLocale.fromCode('zz'), AppLocale.english);
    expect(AppLocale.amharic.materialLocale.languageCode, 'am');
    expect(AppLocale.amharic.label, 'አማርኛ');
    expect(AppLocale.english.label, 'English');
  });
}
