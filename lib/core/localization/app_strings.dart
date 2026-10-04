/// App-wide strings for English, Amharic (አማርኛ), Afaan Oromoo and
/// Tigrinya (ትግርኛ).
///
/// Design: [AppStrings] is an abstract catalog; [EnglishStrings],
/// [AmharicStrings], [OromoStrings] and [TigrinyaStrings] must implement
/// EVERY getter, so
/// adding a string without translating it is a compile error —
/// translations can never silently drift. Look strings up through the [LocaleController]:
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
part 'oromo_strings.dart';
part 'tigrinya_strings.dart';

/// Languages Mahtem ships with.
enum AppLocale {
  english('en'),
  amharic('am'),
  oromo('om'),
  tigrinya('ti');

  const AppLocale(this.code);

  /// BCP-47 language code — also the persisted value.
  final String code;

  Locale get materialLocale => Locale(code);

  /// Human name shown in the language switcher (always in its own
  /// language, like native language pickers).
  String get label => switch (this) {
    AppLocale.english => 'English',
    AppLocale.amharic => 'አማርኛ',
    AppLocale.oromo => 'Afaan Oromoo',
    AppLocale.tigrinya => 'ትግርኛ',
  };

  static AppLocale fromCode(String? code) => switch (code) {
    'am' => AppLocale.amharic,
    'om' => AppLocale.oromo,
    'ti' => AppLocale.tigrinya,
    _ => AppLocale.english,
  };
}

/// Locales the MaterialApp declares.
const List<Locale> kSupportedLocales = <Locale>[
  Locale('en'),
  Locale('am'),
  Locale('om'),
  Locale('ti'),
];

abstract base class AppStrings {
  const AppStrings();

  factory AppStrings.of(AppLocale locale) => switch (locale) {
    AppLocale.amharic => const AmharicStrings(),
    AppLocale.oromo => const OromoStrings(),
    AppLocale.tigrinya => const TigrinyaStrings(),
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
  String get accountCreatedSuccess;
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

  // ---------------------------------------------------- manual entry (v1.7.0)

  /// Title of the manual-entry sheet.
  String get typeSheetTitle;

  /// Hint inside the entry field — shows a realistic reference shape.
  String get typeSheetHint;

  /// Section header above the recent-reference chips.
  String get typeSheetRecent;

  // ------------------------------------- reference number scanner (v1.10.0)

  /// Label under the camera icon on the scan screen — opens the OCR
  /// scanner that reads the number printed on a paper receipt.
  String get scanNumberAction;

  /// App-bar title of the reference-number OCR scanner.
  String get refScanTitle;

  /// Instruction shown under the title while the scanner is open —
  /// only numbers inside the viewfinder frame are read.
  String get refScanHint;

  /// Status line shown while no candidate number has been read yet.
  String get refScanLooking;

  /// Header above the chips listing the numbers found in the frame.
  String get refScanFoundTitle;

  /// Label under the keyboard icon on the OCR screen — opens the manual
  /// entry sheet when the camera cannot read the print.
  String get refScanTypeInstead;

  /// Shown when the gallery image contains no readable number.
  String get refScanNoNumberFound;

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

  // ------------------------------------------------- history search (v1.7.0)

  String get historySearchTooltip;
  String get historySearchHint;
  String get filterAll;
  String get filterVerified;
  String get filterFailed;
  String get noMatchesTitle;
  String get noMatchesBody;

  /// Button in a history entry's details sheet: prefill the verify form
  /// with this entry's bank + reference and jump to the Verify tab.
  String get verifyAgain;

  /// Toast shown after the prefill.
  String get prefilledToast;

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

  // ------------------------------------------------- crash reporting (v1.8.0)

  /// Fine print at the bottom of the settings sheet: crash reports are
  /// anonymous and contain no receipt or account data.
  String get crashReportsNote;

  // ------------------------------------------------ error safety net (v1.12.1)

  /// Release-mode error card shown when a screen fails to build — calm,
  /// no technical detail, points the user back.
  String get somethingWentWrongScreen;

  /// Settings tile that opens the on-device diagnostics trail.
  String get reportProblemTile;

  /// Title of the diagnostics dialog.
  String get reportProblemTitle;

  /// Empty state: no problems have been recorded on this device yet.
  String get reportProblemEmpty;

  /// Fine print under the tile: the trail is local-only, sharing happens
  /// only when the user copies it.
  String get reportProblemHint;

  /// Copy button inside the diagnostics dialog.
  String get reportProblemCopy;

  // --------------------------------------------- cloud backup (v1.13.0)

  /// Section/tile title when backup is enabled.
  String get cloudBackupSection;

  /// Settings tile label when backup is off.
  String get cloudBackupTileOff;

  /// Privacy explainer at the top of the backup sheet.
  String get cloudBackupBetaNote;

  /// Password field hint in the enable flow.
  String get cloudBackupPasswordFieldHint;

  /// Enable button.
  String get cloudBackupEnable;

  /// Local password verification failed.
  String get cloudBackupWrongPassword;

  /// Network failure.
  String get cloudBackupNetworkError;

  /// 5xx / server-side failure.
  String get cloudBackupServerError;

  /// Stored session no longer valid — re-enable required.
  String get cloudBackupSessionExpired;

  /// Cloud ciphertext cannot be opened with this password.
  String get cloudBackupDecryptError;

  /// Status line when no successful backup has happened yet.
  String get cloudBackupLastNever;

  /// Prefix before the formatted last-backup timestamp.
  String get cloudBackupLastAt;

  /// Back up now button.
  String get cloudBackupNow;

  /// Backup success toast.
  String get cloudBackupDone;

  /// Restore button.
  String get cloudBackupRestore;

  /// Restore success with [n] new entries.
  String cloudBackupRestored(int n);

  /// Restore found nothing new.
  String get cloudBackupNothingToRestore;

  /// Turn off button.
  String get cloudBackupTurnOff;

  /// Turned-off toast (cloud copy deleted).
  String get cloudBackupTurnedOff;

  /// Status line with [n] entries currently backed up.
  String cloudBackupEntryCount(int n);

  /// Auto-backup toggle title (v1.13.1) — pushes each change by itself.
  String get cloudAutoBackupTitle;

  /// Auto-backup toggle subtitle.
  String get cloudAutoBackupSubtitle;

  // ------------------------------------------------- history upgrade (v1.9.0)

  /// Labels of the three summary cells at the top of the history list.
  String get statsChecks;
  String get statsVerified;
  String get statsTotal;

  /// Date-group headers inside the history list (entries are bucketed by
  /// the day they were checked).
  String get groupToday;
  String get groupYesterday;
  String get groupThisWeek;
  String get groupEarlier;

  /// Snackbar after a swipe/long-press delete, plus its undo action.
  String get removedToast;
  String get undo;

  /// Button on the "no checks yet" empty state — jumps to the Verify tab.
  String get emptyCta;

  /// App-bar action: share the whole history as CSV text.
  String get exportTooltip;

  // --------------------------------------- CBE printed-number gate (v1.10.1)

  /// Dialog shown instead of running a doomed check: CBE's receipt API only
  /// accepts the code inside a shared receipt link / QR, so the FT number
  /// read off the slip can never verify. (Acknowledged with [ok].)
  String get cbeNeedsCodeTitle;
  String get cbeNeedsCodeBody;

  // --------------------------------------- competition-pass items (v1.11.0)

  /// Localized failure message for [VerifyErrorKind.blocked]: the bank's
  /// receipt service is refusing automated checks from this network
  /// (anti-bot interstitial) — currently only Siinqee's own host.
  String failureBlockedMessage();
  List<String> failureBlockedTips();

  /// Advisory appended to a verified receipt older than [days]: the
  /// classic replayed-receipt scam is a real receipt presented late.
  String staleReceiptNote(int days);

  /// Advisory appended when this exact bank + reference already verified
  /// here before — [when] is a compact timestamp of that earlier check.
  String duplicateReceiptNote(String when);

  /// Toast after a pasted SMS / chat message collapses to the receipt
  /// value it carries.
  String get pasteExtractedToast;

  // ------------------------------------------------- batch check (v1.12.0)

  /// Screen title of the batch checker.
  String get batchTitle;

  /// One-liner under the title explaining the paste-many flow.
  String get batchIntro;

  /// Hint inside the multiline batch input.
  String get batchInputHint;

  /// Chip label for choosing the bank that plain references belong to.
  String get batchBankLabel;

  /// Start button — [count] chargeable receipts.
  String batchStart(int count);

  /// Refused pre-flight: the batch needs [need] checks but only [have]
  /// free ones remain.
  String batchNeedMore(int have, int need);

  /// Start disabled: each [bank] receipt needs its payer phone number,
  /// which a batch cannot supply.
  String batchNeedsPhone(String bank);

  /// Start disabled: [count] plain references still need a batch bank.
  String batchNeedsBank(int count);

  /// Pre-flight note: [count] duplicate line(s) collapsed.
  String batchDuplicates(int count);

  /// Live progress while the batch runs.
  String batchProgress(int done, int total);

  /// Final counts after the batch finishes.
  String batchDoneCounts(int verified, int failed);

  /// Button to resume the rows left pending after a stop.
  String batchRemaining(int count);

  /// App-bar action: share the batch results as text.
  String get batchShareTooltip;

  /// Empty state under the input: nothing usable parsed yet.
  String get batchEmpty;

  /// Row skip reason — same line already appears earlier in the batch.
  String get batchSkipDuplicate;

  /// Row skip reason — CBE printed FT number, needs the receipt code.
  String get batchSkipCbe;

  /// Row skip reason — a link none of the detectors recognize.
  String get batchSkipUnknown;

  /// Row skip reason — past the [kBatchMaxLines] cap.
  String get batchSkipOverLimit;
}
