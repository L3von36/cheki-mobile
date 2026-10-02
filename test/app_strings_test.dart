import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/localization/app_strings.dart';

bool _hasEthiopic(String text) =>
    text.runes.any((r) => r >= 0x1200 && r <= 0x137F);

void main() {
  // Both catalogs must implement EVERY getter — that's enforced at
  // compile time by the abstract base. These tests guard the content:
  // non-empty strings, the right script per language, and total coverage
  // of the auth error mapping.

  test('every catalog string is non-empty in all three languages', () {
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

      // v1.6.6: scan / result / history / paywall catalogs.
      expect(s.scanTitle, isNotEmpty);
      expect(s.scanPositionHint, isNotEmpty);
      expect(s.scanCameraError('x'), contains('x'));
      expect(s.scanCameraOff, isNotEmpty);
      expect(s.resultTitle, isNotEmpty);
      expect(s.resultVerifiedTitle, isNotEmpty);
      expect(s.resultFailedBody, isNotEmpty);
      expect(s.senderAccountLabel, isNotEmpty);
      expect(
        s.shareText(
          bankName: 'CBE',
          reference: 'r1',
          amount: 'a1',
          sender: 's1',
          receiver: 'r2',
          date: 'd1',
        ),
        contains('CBE'),
      );
      for (final kind in VerifyErrorKind.values) {
        expect(
          s.failureMessage(kind, 'fallback'),
          isNotEmpty,
          reason: '${locale.code} failureMessage($kind)',
        );
        expect(
          s.failureTips(kind, const ['fallback']),
          isNotEmpty,
          reason: '${locale.code} failureTips($kind)',
        );
      }
      expect(s.historyTitle, isNotEmpty);
      expect(s.clearHistoryBody, isNotEmpty);
      expect(s.verifiedPaymentLabel, isNotEmpty);
      expect(s.checkedLabel, isNotEmpty);
      expect(s.paywallTitle, isNotEmpty);
      expect(s.codeExpired('1 Jan 2026'), contains('1 Jan 2026'));
      expect(s.proActivatedToast('1 Feb 2026'), contains('1 Feb 2026'));
      expect(s.trialsLeftTitle(1), isNotEmpty);
      expect(s.trialsLeftTitle(3), isNotEmpty);
      expect(s.priceYearlyOnce('900'), contains('900'));
      expect(s.step1Title('99', '900'), contains('900'));
      expect(s.step2Body('99'), contains('99'));
      expect(s.verifyAndActivate, isNotEmpty);
      for (final reason in ActivationRejectReason.values) {
        expect(
          s.activationRejection(reason, 'fallback'),
          isNotEmpty,
          reason: '${locale.code} activationRejection($reason)',
        );
      }
    }
  });

  test('the English catalog uses the Latin script', () {
    final s = AppStrings.of(AppLocale.english);
    expect(_hasEthiopic(s.welcomeBack), isFalse);
    expect(_hasEthiopic(s.verifyReceiptButton), isFalse);
    expect(_hasEthiopic(s.resultVerifiedTitle), isFalse);
    expect(_hasEthiopic(s.failureMessage(VerifyErrorKind.network, 'fb')),
        isFalse);
    expect(s.locale, AppLocale.english);
  });

  test('the Amharic catalog renders Ge\u2019ez (Ethiopic) glyphs', () {
    final s = AppStrings.of(AppLocale.amharic);
    expect(_hasEthiopic(s.welcomeBack), isTrue);
    expect(_hasEthiopic(s.verifyTab), isTrue);
    expect(_hasEthiopic(s.verifyReceiptButton), isTrue);
    expect(_hasEthiopic(s.authPrivacyNote), isTrue);
    expect(_hasEthiopic(s.resultVerifiedTitle), isTrue);
    expect(
      _hasEthiopic(s.failureMessage(VerifyErrorKind.network, 'fb')),
      isTrue,
    );
    expect(_hasEthiopic(s.trialsGoneTitle), isTrue);
    expect(s.locale, AppLocale.amharic);
  });

  test('the Afaan Oromoo catalog uses the Latin (Qubee) script', () {
    final s = AppStrings.of(AppLocale.oromo);
    // Qubee is Latin — no Ethiopic block glyphs may leak in.
    expect(_hasEthiopic(s.welcomeBack), isFalse);
    expect(_hasEthiopic(s.verifyTab), isFalse);
    expect(_hasEthiopic(s.verifyReceiptButton), isFalse);
    expect(_hasEthiopic(s.authPrivacyNote), isFalse);
    expect(_hasEthiopic(s.resultVerifiedTitle), isFalse);
    expect(
      _hasEthiopic(s.failureMessage(VerifyErrorKind.network, 'fb')),
      isFalse,
    );
    expect(_hasEthiopic(s.trialsGoneTitle), isFalse);
    // Spot-check a few translations so a placeholder can't sneak in.
    expect(s.welcomeBack, "Baga nagaan deebi'tan");
    expect(s.verifyTab, 'Mirkaneessa');
    expect(s.historyTab(2), contains('Seenaa'));
    expect(s.locale, AppLocale.oromo);
  });

  test('every AuthError maps to a localized message in all languages', () {
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
    expect(AppLocale.fromCode('om'), AppLocale.oromo);
    expect(AppLocale.fromCode('en'), AppLocale.english);
    expect(AppLocale.fromCode(null), AppLocale.english);
    expect(AppLocale.fromCode('zz'), AppLocale.english);
    expect(AppLocale.amharic.materialLocale.languageCode, 'am');
    expect(AppLocale.oromo.materialLocale.languageCode, 'om');
    expect(AppLocale.amharic.label, 'አማርኛ');
    expect(AppLocale.english.label, 'English');
    expect(AppLocale.oromo.label, 'Afaan Oromoo');
    expect(kSupportedLocales.map((l) => l.languageCode),
        containsAll(['en', 'am', 'om']));
  });
}
