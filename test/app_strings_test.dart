import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/localization/app_strings.dart';

bool _hasEthiopic(String text) =>
    text.runes.any((r) => r >= 0x1200 && r <= 0x137F);

void main() {
  // Both catalogs must implement EVERY getter — that's enforced at
  // compile time by the abstract base. These tests guard the content:
  // non-empty strings, the right script per language, and total coverage
  // of the auth error mapping.

  test('every catalog string is non-empty in all four languages', () {
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

      // v1.7.0: manual reference entry + history search.
      expect(s.typeSheetTitle, isNotEmpty);
      expect(s.typeSheetHint, isNotEmpty);
      expect(s.typeSheetRecent, isNotEmpty);
      expect(s.historySearchTooltip, isNotEmpty);
      expect(s.historySearchHint, isNotEmpty);
      expect(s.filterAll, isNotEmpty);
      expect(s.filterVerified, isNotEmpty);
      expect(s.filterFailed, isNotEmpty);
      expect(s.noMatchesTitle, isNotEmpty);
      expect(s.noMatchesBody, isNotEmpty);
      expect(s.verifyAgain, isNotEmpty);
      expect(s.prefilledToast, isNotEmpty);
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

      // v1.8.0: crash reporting disclosure.
      expect(s.crashReportsNote, isNotEmpty,
          reason: '${locale.code} crashReportsNote');

      // v1.12.1: error safety net + report-a-problem flow.
      expect(s.somethingWentWrongScreen, isNotEmpty,
          reason: '${locale.code} somethingWentWrongScreen');
      expect(s.reportProblemTile, isNotEmpty,
          reason: '${locale.code} reportProblemTile');
      expect(s.reportProblemTitle, isNotEmpty,
          reason: '${locale.code} reportProblemTitle');
      expect(s.reportProblemEmpty, isNotEmpty,
          reason: '${locale.code} reportProblemEmpty');
      expect(s.reportProblemHint, isNotEmpty,
          reason: '${locale.code} reportProblemHint');
      expect(s.reportProblemCopy, isNotEmpty,
          reason: '${locale.code} reportProblemCopy');

      // v1.9.0: history upgrade.
      expect(s.statsChecks, isNotEmpty, reason: '${locale.code} statsChecks');
      expect(s.statsVerified, isNotEmpty,
          reason: '${locale.code} statsVerified');
      expect(s.statsTotal, isNotEmpty, reason: '${locale.code} statsTotal');
      expect(s.groupToday, isNotEmpty, reason: '${locale.code} groupToday');
      expect(s.groupYesterday, isNotEmpty,
          reason: '${locale.code} groupYesterday');
      expect(s.groupThisWeek, isNotEmpty,
          reason: '${locale.code} groupThisWeek');
      expect(s.groupEarlier, isNotEmpty, reason: '${locale.code} groupEarlier');
      expect(s.removedToast, isNotEmpty, reason: '${locale.code} removedToast');
      expect(s.undo, isNotEmpty, reason: '${locale.code} undo');
      expect(s.emptyCta, isNotEmpty, reason: '${locale.code} emptyCta');
      expect(s.exportTooltip, isNotEmpty,
          reason: '${locale.code} exportTooltip');

      // v1.10.0: reference number scanner.
      expect(s.scanNumberAction, isNotEmpty,
          reason: '${locale.code} scanNumberAction');
      expect(s.refScanTitle, isNotEmpty, reason: '${locale.code} refScanTitle');
      expect(s.refScanHint, isNotEmpty, reason: '${locale.code} refScanHint');
      expect(s.refScanLooking, isNotEmpty,
          reason: '${locale.code} refScanLooking');
      expect(s.refScanFoundTitle, isNotEmpty,
          reason: '${locale.code} refScanFoundTitle');
      expect(s.refScanTypeInstead, isNotEmpty,
          reason: '${locale.code} refScanTypeInstead');
      expect(s.refScanNoNumberFound, isNotEmpty,
          reason: '${locale.code} refScanNoNumberFound');

      // v1.10.1: CBE printed-number gate.
      expect(s.cbeNeedsCodeTitle, isNotEmpty,
          reason: '${locale.code} cbeNeedsCodeTitle');
      expect(s.cbeNeedsCodeBody, isNotEmpty,
          reason: '${locale.code} cbeNeedsCodeBody');

      // v1.11.0: blocked-bank failure + anti-fraud advisories + smart paste.
      expect(s.failureBlockedMessage(), isNotEmpty,
          reason: '${locale.code} failureBlockedMessage');
      expect(s.failureBlockedTips(), isNotEmpty,
          reason: '${locale.code} failureBlockedTips');
      for (final tip in s.failureBlockedTips()) {
        expect(tip, isNotEmpty, reason: '${locale.code} blocked tip');
      }
      expect(s.staleReceiptNote(1), isNotEmpty,
          reason: '${locale.code} staleReceiptNote(1)');
      expect(s.staleReceiptNote(3), isNotEmpty,
          reason: '${locale.code} staleReceiptNote(3)');
      expect(s.staleReceiptNote(3), contains('3'),
          reason: '${locale.code} staleReceiptNote embeds the count');
      expect(s.duplicateReceiptNote('10:30'), isNotEmpty,
          reason: '${locale.code} duplicateReceiptNote');
      expect(s.duplicateReceiptNote('10:30'), contains('10:30'),
          reason: '${locale.code} duplicateReceiptNote embeds the stamp');
      expect(s.pasteExtractedToast, isNotEmpty,
          reason: '${locale.code} pasteExtractedToast');

      // v1.12.0 batch-check catalog.
      expect(s.batchTitle, isNotEmpty, reason: '${locale.code} batchTitle');
      expect(s.batchIntro, isNotEmpty, reason: '${locale.code} batchIntro');
      expect(s.batchInputHint, isNotEmpty,
          reason: '${locale.code} batchInputHint');
      expect(s.batchBankLabel, isNotEmpty,
          reason: '${locale.code} batchBankLabel');
      expect(s.batchStart(1), isNotEmpty,
          reason: '${locale.code} batchStart(1)');
      expect(s.batchStart(3), contains('3'),
          reason: '${locale.code} batchStart embeds the count');
      expect(s.batchNeedMore(2, 5), contains('5'),
          reason: '${locale.code} batchNeedMore embeds the need');
      expect(s.batchNeedMore(2, 5), contains('2'),
          reason: '${locale.code} batchNeedMore embeds the have');
      expect(s.batchNeedsPhone('CBE Birr'), contains('CBE Birr'),
          reason: '${locale.code} batchNeedsPhone embeds the bank');
      expect(s.batchNeedsBank(1), isNotEmpty,
          reason: '${locale.code} batchNeedsBank(1)');
      expect(s.batchNeedsBank(3), contains('3'),
          reason: '${locale.code} batchNeedsBank embeds the count');
      expect(s.batchDuplicates(1), isNotEmpty,
          reason: '${locale.code} batchDuplicates(1)');
      expect(s.batchDuplicates(4), contains('4'),
          reason: '${locale.code} batchDuplicates embeds the count');
      expect(s.batchProgress(2, 9), contains('2'),
          reason: '${locale.code} batchProgress embeds done');
      expect(s.batchProgress(2, 9), contains('9'),
          reason: '${locale.code} batchProgress embeds total');
      expect(s.batchDoneCounts(1, 2), contains('1'),
          reason: '${locale.code} batchDoneCounts embeds verified');
      expect(s.batchDoneCounts(1, 2), contains('2'),
          reason: '${locale.code} batchDoneCounts embeds failed');
      expect(s.batchRemaining(1), isNotEmpty,
          reason: '${locale.code} batchRemaining(1)');
      expect(s.batchRemaining(4), contains('4'),
          reason: '${locale.code} batchRemaining embeds the count');
      expect(s.batchShareTooltip, isNotEmpty,
          reason: '${locale.code} batchShareTooltip');
      expect(s.batchEmpty, isNotEmpty, reason: '${locale.code} batchEmpty');
      expect(s.batchSkipDuplicate, isNotEmpty,
          reason: '${locale.code} batchSkipDuplicate');
      expect(s.batchSkipCbe, isNotEmpty,
          reason: '${locale.code} batchSkipCbe');
      expect(s.batchSkipUnknown, isNotEmpty,
          reason: '${locale.code} batchSkipUnknown');
      expect(s.batchSkipOverLimit, isNotEmpty,
          reason: '${locale.code} batchSkipOverLimit');
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
    expect(_hasEthiopic(s.typeSheetTitle), isTrue);
    expect(_hasEthiopic(s.verifyAgain), isTrue);
    expect(_hasEthiopic(s.noMatchesBody), isTrue);
    expect(_hasEthiopic(s.crashReportsNote), isTrue);
    expect(_hasEthiopic(s.groupToday), isTrue);
    expect(_hasEthiopic(s.refScanTitle), isTrue);
    expect(_hasEthiopic(s.refScanNoNumberFound), isTrue);
    expect(_hasEthiopic(s.cbeNeedsCodeTitle), isTrue);
    expect(_hasEthiopic(s.cbeNeedsCodeBody), isTrue);
    expect(_hasEthiopic(s.failureBlockedMessage()), isTrue);
    for (final tip in s.failureBlockedTips()) {
      expect(_hasEthiopic(tip), isTrue);
    }
    expect(_hasEthiopic(s.staleReceiptNote(3)), isTrue);
    expect(_hasEthiopic(s.duplicateReceiptNote('10:30')), isTrue);
    expect(_hasEthiopic(s.pasteExtractedToast), isTrue);
    expect(_hasEthiopic(s.somethingWentWrongScreen), isTrue);
    expect(_hasEthiopic(s.reportProblemTile), isTrue);
    expect(_hasEthiopic(s.reportProblemTitle), isTrue);
    expect(_hasEthiopic(s.reportProblemCopy), isTrue);
    expect(s.undo, 'መልስ');
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
    expect(s.filterAll, 'Hunda');
    expect(s.filterFailed, 'Hin mirkaneeffamne');
    expect(s.verifyAgain, contains('mirkaneessaa'));
    expect(_hasEthiopic(s.crashReportsNote), isFalse);
    expect(_hasEthiopic(s.statsChecks), isFalse);
    expect(_hasEthiopic(s.refScanTitle), isFalse);
    expect(s.groupToday, 'Har\u2019aa');
    expect(s.scanNumberAction, 'Lakkoofsa iskaanii godhaa');
    expect(s.cbeNeedsCodeTitle, 'CBE-n koodii risiitii barbaada');
    expect(s.failureBlockedMessage(), contains('Siinqee'));
    expect(s.reportProblemTile, 'Rakkoo gabaasi');
    expect(_hasEthiopic(s.somethingWentWrongScreen), isFalse);
    expect(_hasEthiopic(s.reportProblemEmpty), isFalse);
    expect(s.pasteExtractedToast,
        'Lakkoofsi risitii barreeffamicha keessaa argameera.');
    expect(s.locale, AppLocale.oromo);
  });

  test('the Tigrinya catalog renders Ge’ez (Ethiopic) glyphs', () {
    final s = AppStrings.of(AppLocale.tigrinya);
    // Tigrinya shares the Ethiopic block with Amharic.
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
    expect(_hasEthiopic(s.typeSheetTitle), isTrue);
    expect(_hasEthiopic(s.verifyAgain), isTrue);
    expect(_hasEthiopic(s.noMatchesBody), isTrue);
    expect(_hasEthiopic(s.crashReportsNote), isTrue);
    expect(_hasEthiopic(s.groupToday), isTrue);
    expect(_hasEthiopic(s.refScanTitle), isTrue);
    expect(s.groupYesterday, 'ትማሊ');
    expect(s.scanNumberAction, 'ቍጽሪ ስካኑ');
    expect(s.cbeNeedsCodeTitle, 'ሲቢኤ ኮድ ሰርተፊኬት ይደሊ');
    expect(_hasEthiopic(s.somethingWentWrongScreen), isTrue);
    expect(_hasEthiopic(s.reportProblemTile), isTrue);
    expect(s.reportProblemCopy, 'ቅጂ ሓበሬታ');
    expect(s.pasteExtractedToast, 'ቍጽሪ ሪሲት ካብቲ ጽሑፍ ተረኺቡ ኣሎ።');
    // Spot-check a few translations so a placeholder can't sneak in.
    expect(s.welcomeBack, 'ብደሓን ተመሊስኩም');
    expect(s.verifyTab, 'ምርግጋጽ');
    expect(s.historyTab(2), contains('ታሪኽ'));
    expect(s.passwordLabel, 'መሕለፊ ቃል');
    expect(s.filterAll, 'ኩሉ');
    expect(s.locale, AppLocale.tigrinya);
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
    expect(AppLocale.fromCode('ti'), AppLocale.tigrinya);
    expect(AppLocale.fromCode('en'), AppLocale.english);
    expect(AppLocale.fromCode(null), AppLocale.english);
    expect(AppLocale.fromCode('zz'), AppLocale.english);
    expect(AppLocale.amharic.materialLocale.languageCode, 'am');
    expect(AppLocale.oromo.materialLocale.languageCode, 'om');
    expect(AppLocale.tigrinya.materialLocale.languageCode, 'ti');
    expect(AppLocale.amharic.label, 'አማርኛ');
    expect(AppLocale.english.label, 'English');
    expect(AppLocale.oromo.label, 'Afaan Oromoo');
    expect(AppLocale.tigrinya.label, 'ትግርኛ');
    expect(kSupportedLocales.map((l) => l.languageCode),
        containsAll(['en', 'am', 'om', 'ti']));
  });
}
