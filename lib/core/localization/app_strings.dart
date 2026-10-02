/// App-wide strings for English and Amharic (አማርኛ).
///
/// Design: [AppStrings] is an abstract catalog; [EnglishStrings] and
/// [AmharicStrings] must implement EVERY getter, so adding a string
/// without translating it is a compile error — translations can never
/// silently drift. Look strings up through the [LocaleController]:
///
/// ```dart
/// final s = context.watch<LocaleController>().strings;
/// Text(s.verifyReceiptButton)
/// ```
library;

import 'dart:ui';

import '../../state/auth_controller.dart';
import '../licensing/receipt_activation.dart' show ActivationRejectReason;
import '../receipt_verify/models.dart' show VerifyErrorKind;

/// Why a sign-up / sign-in attempt was refused — shared with
/// [AppStrings.errorAuth] for localized messages.
/// (Re-exported here so screens only import this file.)
export '../../state/auth_controller.dart' show AuthError;

/// Re-exported so screens can map verify failures / activation
/// rejections through the catalog without extra imports.
export '../licensing/receipt_activation.dart' show ActivationRejectReason;
export '../receipt_verify/models.dart' show VerifyErrorKind;

part 'english_strings.dart';
part 'amharic_strings.dart';

/// Languages Mahtem ships with.
enum AppLocale {
  english('en'),
  amharic('am');

  const AppLocale(this.code);

  /// BCP-47 language code — also the persisted value.
  final String code;

  Locale get materialLocale => Locale(code);

  /// Human name shown in the language switcher (always in its own
  /// language, like native language pickers).
  String get label => switch (this) {
    AppLocale.english => 'English',
    AppLocale.amharic => 'አማርኛ',
  };

  static AppLocale fromCode(String? code) => switch (code) {
    'am' => AppLocale.amharic,
    _ => AppLocale.english,
  };
}

/// Locales the MaterialApp declares.
const List<Locale> kSupportedLocales = <Locale>[Locale('en'), Locale('am')];

abstract base class AppStrings {
  const AppStrings();

  factory AppStrings.of(AppLocale locale) => switch (locale) {
    AppLocale.amharic => const AmharicStrings(),
    AppLocale.english => const EnglishStrings(),
  };

  AppLocale get locale;

  // ---------------------------------------------------------------- shell

  String get verifyTab;
  String historyTab(int count);

  // ---------------------------------------------------------------- home

  String get referenceLabel;
  String get referenceHint;
  String get pickBankHint;
  String get phoneOnWallet;
  String lastDigitsOnly(int digits);
  String get clipboardEmpty;
  String get verifyReceiptButton;
  String get stopVerifying;
  String get autoDetectBank;
  String detected(String bankName);
  String get pasteTooltip;
  String get scanQrInstead;
  String freeChecksLeft(int count);
  String get upgrade;
  String proDaysLeft(int days);

  // ---------------------------------------------------------------- auth

  String get welcomeBack;
  String get signInSubtitle;
  String get createAccountTitle;
  String get createAccountSubtitle;
  String get fullName;
  String get fullNameHint;
  String get identifierLabel;
  String get identifierHint;
  String get passwordLabel;
  String get passwordHint;
  String get confirmPasswordLabel;
  String get signInButton;
  String get signInLink;
  String get createAccountButton;
  String get createAccountLink;
  String get noAccountPrompt;
  String get haveAccountPrompt;
  String get forgotPassword;
  String get resetAccountsTitle;
  String get resetAccountsBody;
  String get resetAccountsConfirm;
  String get cancel;
  String get ok;
  String get showPassword;
  String get hidePassword;
  String get signingIn;
  String get creatingAccount;
  String get authPrivacyNote;
  String errorAuth(AuthError error);
  String get genericAuthError;

  // ---------------------------------------------------------------- settings

  String get settingsTitle;
  String get accountSection;
  String get signedInAs;
  String get appearanceSection;
  String get themeSystem;
  String get themeLight;
  String get themeDark;
  String get languageSection;
  String get signOut;
  String get signOutConfirmTitle;
  String get signOutConfirmBody;
  String get versionLabel;
  String get deviceCodeLabel;
  String get copiedToClipboard;
  String get close;
  String get loading;

  // ---------------------------------------------------------------- scan

  String get scanTitle;
  String get scanPositionHint;
  String get scanUsageHint;
  String get scanFlash;
  String get scanGallery;
  String get scanNoQrFound;
  String get scanImageUnreadable;
  String scanCameraError(String code);
  String get scanRetry;
  String get scanCameraPermissionNeeded;
  String get scanGrantPermission;
  String get scanCameraOff;
  String get scanOpenSettings;
  String get scanCameraUnavailable;

  // ---------------------------------------------------------------- result

  String get resultTitle;
  String get resultNothingToShow;
  String get resultVerifiedTitle;
  String get resultFailedTitle;
  String get resultVerifiedBody;
  String get resultFailedBody;
  String get resultDone;
  String get resultShare;
  String get resultTryAgain;
  String get senderLabel;
  String get senderAccountLabel;
  String get receiverLabel;
  String get receiverAccountLabel;
  String get dateLabel;
  String get referenceShortLabel;
  String get reasonLabel;
  String get statusLabel;
  String get bankShortLabel;

  /// The multi-line text the share sheet receives after a verified
  /// receipt.
  String shareText({
    required String bankName,
    required String reference,
    required String amount,
    required String sender,
    required String receiver,
    required String date,
  });

  // ------------------------------------------------------- verify failures

  /// Localized replacement for the engine's [VerifyFailure.message].
  /// English returns [fallback] unchanged (the engine's specific wording
  /// is already English); Amharic maps [kind] to native copy.
  String failureMessage(VerifyErrorKind kind, String fallback);

  /// Localized replacement for the engine's [VerifyFailure.tips].
  List<String> failureTips(VerifyErrorKind kind, List<String> fallback);

  // ---------------------------------------------------------------- history

  String get historyTitle;
  String get clearHistoryTooltip;
  String get clearHistoryTitle;
  String get clearHistoryBody;
  String get clearButton;
  String get noChecksTitle;
  String get noChecksBody;
  String get verifiedPaymentLabel;
  String get notVerifiedLabel;
  String get checkedLabel;
  String get noteLabel;

  // ---------------------------------------------------------------- paywall

  String get paywallTitle;
  String get pasteReceiptFromSms;
  String get pasteActivationCode;
  String get codeBadFormat;
  String get codeBadSignature;
  String get codeWrongDevice;
  String codeExpired(String date);
  String get codeNotAccepted;
  String proActivatedToast(String date);
  String get clipboardEmptyForPaste;
  String telebirrNumberCopied(String number);
  String amountCopied(String amount);
  String get stackingNote;
  String get hideActivationCode;
  String get haveActivationCode;
  String get deviceCodeCopied;
  String get proActiveTitle;
  String proUnlimitedUntil(String date);
  String trialsLeftTitle(int count);
  String get trialsLeftBody;
  String get trialsGoneTitle;
  String get trialsGoneBody;
  String get pricePerMonth;
  String get priceUnlimitedBody;
  String priceYearlyOnce(String price);
  String get howToActivate;
  String step1Title(String monthly, String yearly);
  String get step1Body;
  String copyAmountChip(String amount);
  String get step2Title;
  String step2Body(String monthly);
  String get telebirrReceiptNumber;
  String get receiptNumberHint;
  String get checkingWithTelebirr;
  String get verifyAndActivate;
  String get activationCodeTitle;
  String get codeBoundNote;
  String get activate;

  /// Localized replacement for [ReceiptActivationRejected.message].
  /// [amount] is the formatted receipt amount when the rejection is
  /// about a mismatched plan price.
  String activationRejection(
    ActivationRejectReason reason,
    String fallback, {
    String amount = '',
  });
}
