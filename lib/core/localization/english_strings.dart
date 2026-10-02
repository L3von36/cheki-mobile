part of 'app_strings.dart';

/// English catalog — the source of truth the Amharic catalog mirrors.
final class EnglishStrings extends AppStrings {
  const EnglishStrings();

  @override
  AppLocale get locale => AppLocale.english;

  // ---------------------------------------------------------------- shell

  @override
  String get verifyTab => 'Verify';

  @override
  String historyTab(int count) => count > 0 ? 'History ($count)' : 'History';

  // ---------------------------------------------------------------- home

  @override
  String get referenceLabel => 'Reference number or receipt link';

  @override
  String get referenceHint => 'Paste a receipt link or type the number';

  @override
  String get pickBankHint =>
      'Pick the bank or wallet that issued the receipt — '
      'receipt links and QR scans pick it automatically.';

  @override
  String get phoneOnWallet => 'Phone number on the wallet';

  @override
  String lastDigitsOnly(int digits) => 'Last $digits digits only';

  @override
  String get clipboardEmpty => 'Clipboard is empty.';

  @override
  String get verifyReceiptButton => 'VERIFY RECEIPT';

  @override
  String get stopVerifying => 'Stop verifying';

  @override
  String get autoDetectBank => 'Auto-detect bank';

  @override
  String detected(String bankName) => 'Detected: $bankName';

  @override
  String get pasteTooltip => 'Paste';

  @override
  String get scanQrInstead => 'Scan the QR code instead';

  @override
  String freeChecksLeft(int count) => '$count free left';

  @override
  String get upgrade => 'Upgrade';

  @override
  String proDaysLeft(int days) => 'PRO · ${days}d';

  // ---------------------------------------------------------------- auth

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get signInSubtitle => 'Sign in to keep verifying receipts';

  @override
  String get createAccountTitle => 'Create your account';

  @override
  String get createAccountSubtitle =>
      'One account for this device — takes seconds';

  @override
  String get fullName => 'Full name';

  @override
  String get fullNameHint => 'e.g. Abebe Kebede';

  @override
  String get identifierLabel => 'Phone number or email';

  @override
  String get identifierHint => '09xxxxxxxx or you@mail.com';

  @override
  String get passwordLabel => 'Password';

  @override
  String get passwordHint => 'At least 6 characters';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get signInButton => 'SIGN IN';

  @override
  String get signInLink => 'Sign in';

  @override
  String get createAccountButton => 'CREATE ACCOUNT';

  @override
  String get createAccountLink => 'Create account';

  @override
  String get noAccountPrompt => "Don't have an account?";

  @override
  String get haveAccountPrompt => 'Already have an account?';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetAccountsTitle => 'Reset accounts?';

  @override
  String get resetAccountsBody =>
      'All accounts on this device will be removed and you will create a '
      'new one. Your verification history and Pro plan are not affected.';

  @override
  String get resetAccountsConfirm => 'Reset';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get creatingAccount => 'Creating account…';

  @override
  String get authPrivacyNote =>
      'Accounts live only on this device — encrypted, and never sent '
      'anywhere. Your verification history stays private.';

  @override
  String errorAuth(AuthError error) => switch (error) {
    AuthError.invalidName =>
      'Please enter your full name (at least 2 characters).',
    AuthError.invalidIdentifier =>
      'Enter a valid Ethiopian phone number (09xxxxxxxx) or email.',
    AuthError.invalidEmail => "That email address doesn't look right.",
    AuthError.invalidPassword => 'Password must be at least 6 characters.',
    AuthError.passwordMismatch => "Passwords don't match.",
    AuthError.alreadyExists =>
      'An account with this phone/email already exists — sign in '
          'instead.',
    AuthError.accountNotFound =>
      'No account found for this phone/email — create one first.',
    AuthError.wrongPassword => 'Wrong password. Try again.',
    AuthError.storageFailed =>
      'Could not save the account on this device. Try again.',
  };

  @override
  String get genericAuthError => 'Something went wrong. Try again.';

  // ---------------------------------------------------------------- settings

  @override
  String get settingsTitle => 'Settings';

  @override
  String get accountSection => 'Account';

  @override
  String get signedInAs => 'Signed in as';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageSection => 'Language';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirmTitle => 'Sign out?';

  @override
  String get signOutConfirmBody =>
      'You can sign back in with your password — your account stays on '
      'this device.';

  @override
  String get versionLabel => 'Version';

  @override
  String get deviceCodeLabel => 'Device code';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get close => 'Close';

  @override
  String get loading => 'Loading…';

  // ---------------------------------------------------------------- scan

  @override
  String get scanTitle => 'Scan Payment';

  @override
  String get scanPositionHint => 'Position the QR code within the frame';

  @override
  String get scanUsageHint =>
      'Use the QR printed on a payment receipt — '
      'not a pay or receive-money QR';

  @override
  String get scanFlash => 'Flash';

  @override
  String get scanGallery => 'Gallery';

  @override
  String get scanNoQrFound => 'No receipt QR code found in that image.';

  @override
  String get scanImageUnreadable => 'Could not read that image.';

  @override
  String scanCameraError(String code) =>
      'The camera could not start ($code). Close this screen and try again.';

  @override
  String get scanRetry => 'Retry';

  @override
  String get scanCameraPermissionNeeded =>
      'Camera permission is needed to scan receipt QR codes.';

  @override
  String get scanGrantPermission => 'Grant permission';

  @override
  String get scanCameraOff =>
      'Camera access is turned off for Mahtem. Enable it in system '
      'settings, or paste the receipt link instead.';

  @override
  String get scanOpenSettings => 'Open settings';

  @override
  String get scanCameraUnavailable => 'Camera unavailable';

  @override
  String get scanTypeAction => 'Type number';

  @override
  String get typeSheetTitle =>
      'Type the transaction or reference number';

  @override
  String get typeSheetHint =>
      'e.g. FT2614G2P01YB — or paste a receipt link';

  @override
  String get typeSheetRecent => 'Recent checks';

  // ------------------------------------- reference number scanner (v1.10.0)

  @override
  String get scanNumberAction => 'Scan number';

  @override
  String get refScanTitle => 'Scan Receipt Number';

  @override
  String get refScanHint =>
      'Point the camera at the transaction or reference number '
      'printed on the receipt';

  @override
  String get refScanLooking => 'Looking for the number…';

  @override
  String get refScanFoundTitle => 'Numbers found — tap one to verify';

  @override
  String get refScanTypeInstead => 'Type instead';

  @override
  String get refScanNoNumberFound =>
      'No number found. Move closer, add light, or type it instead.';

  // ---------------------------------------------------------------- result

  @override
  String get resultTitle => 'Verification Result';

  @override
  String get resultNothingToShow => 'No receipt to display.';

  @override
  String get resultVerifiedTitle => 'Payment Verified!';

  @override
  String get resultFailedTitle => 'Verification Failed';

  @override
  String get resultVerifiedBody =>
      'This payment is real and confirmed by the bank.';

  @override
  String get resultFailedBody => 'This receipt could not be verified.';

  @override
  String get resultDone => 'Done';

  @override
  String get resultShare => 'Share';

  @override
  String get resultTryAgain => 'Try again';

  @override
  String get senderLabel => 'From';

  @override
  String get senderAccountLabel => 'From account';

  @override
  String get receiverLabel => 'To';

  @override
  String get receiverAccountLabel => 'To account';

  @override
  String get dateLabel => 'Date';

  @override
  String get referenceShortLabel => 'Reference';

  @override
  String get reasonLabel => 'Reason';

  @override
  String get statusLabel => 'Status';

  @override
  String get bankShortLabel => 'Bank';

  @override
  String shareText({
    required String bankName,
    required String reference,
    required String amount,
    required String sender,
    required String receiver,
    required String date,
  }) {
    final buffer = StringBuffer()
      ..writeln('Payment verified via Mahtem')
      ..writeln('Bank: $bankName')
      ..writeln('Reference: $reference')
      ..writeln('Amount: $amount')
      ..writeln('Sender: $sender')
      ..writeln('Receiver: $receiver')
      ..write('Date: $date');
    return buffer.toString();
  }

  // ------------------------------------------------------- verify failures

  @override
  String failureMessage(VerifyErrorKind kind, String fallback) => fallback;

  @override
  List<String> failureTips(VerifyErrorKind kind, List<String> fallback) =>
      fallback;

  // ---------------------------------------------------------------- history

  @override
  String get historyTitle => 'History';

  @override
  String get clearHistoryTooltip => 'Clear history';

  @override
  String get clearHistoryTitle => 'Clear history?';

  @override
  String get clearHistoryBody =>
      'All saved checks will be removed from this device.';

  @override
  String get clearButton => 'Clear';

  @override
  String get noChecksTitle => 'No checks yet';

  @override
  String get noChecksBody => 'Verified receipts will appear here.';

  @override
  String get verifiedPaymentLabel => 'Verified payment';

  @override
  String get notVerifiedLabel => 'Not verified';

  @override
  String get checkedLabel => 'Checked';

  @override
  String get noteLabel => 'Note';

  @override
  String get historySearchTooltip => 'Search history';

  @override
  String get historySearchHint => 'Search reference, name or bank';

  @override
  String get filterAll => 'All';

  @override
  String get filterVerified => 'Verified';

  @override
  String get filterFailed => 'Not verified';

  @override
  String get noMatchesTitle => 'No matches';

  @override
  String get noMatchesBody =>
      'No check matches your search or filter.';

  @override
  String get verifyAgain => 'Verify again';

  @override
  String get prefilledToast =>
      'Details filled in — review and verify.';

  // ---------------------------------------------------------------- paywall

  @override
  String get paywallTitle => 'Mahtem Pro';

  @override
  String get pasteReceiptFromSms =>
      'Paste the receipt number from the Telebirr SMS.';

  @override
  String get pasteActivationCode =>
      'Paste the activation code you received.';

  @override
  String get codeBadFormat =>
      "That doesn't look like a Mahtem activation code.";

  @override
  String get codeBadSignature =>
      'This code is not valid — ask the sender to resend it.';

  @override
  String get codeWrongDevice =>
      'This code was issued for a different device. Send the device code '
      'shown below with your payment.';

  @override
  String codeExpired(String date) =>
      'This code expired on $date. Buy a new one to renew.';

  @override
  String get codeNotAccepted => 'This code could not be accepted.';

  @override
  String proActivatedToast(String date) =>
      'Mahtem Pro is active until $date 🎉';

  @override
  String get clipboardEmptyForPaste =>
      'Your clipboard is empty — copy the number first.';

  @override
  String telebirrNumberCopied(String number) =>
      'Telebirr number $number copied — paste it into the Telebirr app.';

  @override
  String amountCopied(String amount) => 'Amount $amount ETB copied.';

  @override
  String get stackingNote =>
      'One receipt activates one plan on this device. To renew, pay again '
      'and paste the fresh receipt number — paid days always stack.';

  @override
  String get hideActivationCode => 'Hide activation code';

  @override
  String get haveActivationCode => 'Have an activation code instead?';

  @override
  String get deviceCodeCopied => 'Device code copied.';

  @override
  String get proActiveTitle => 'Mahtem Pro is active';

  @override
  String proUnlimitedUntil(String date) =>
      'Unlimited checks until $date.';

  @override
  String trialsLeftTitle(int count) =>
      '$count free check${count == 1 ? '' : 's'} left';

  @override
  String get trialsLeftBody =>
      'After that, activate Mahtem Pro below — your history and settings '
      'stay untouched.';

  @override
  String get trialsGoneTitle => 'Free checks used up';

  @override
  String get trialsGoneBody =>
      'Activate below to keep verifying receipts — it takes a minute.';

  @override
  String get pricePerMonth => 'ETB / month';

  @override
  String get priceUnlimitedBody =>
      'Unlimited receipt checks on every bank and wallet — CBE, Telebirr, '
      'BOA, M-Pesa and more.';

  @override
  String priceYearlyOnce(String price) =>
      'Or pay $price ETB once for a whole year.';

  @override
  String get howToActivate => 'How to activate';

  @override
  String step1Title(String monthly, String yearly) =>
      'Pay $monthly ETB (or $yearly ETB / year) via Telebirr';

  @override
  String get step1Body =>
      'Send the exact amount to this Telebirr account:';

  @override
  String copyAmountChip(String amount) => 'Copy amount — $amount ETB';

  @override
  String get step2Title => 'Paste the receipt number below';

  @override
  String step2Body(String monthly) =>
      'Telebirr sends a confirmation SMS with a receipt number '
      '(e.g. CHQ261Z4AB2C) — paste it here and the app checks it with '
      'Telebirr itself. If it is a real $monthly ETB payment to the '
      'account above, Mahtem Pro unlocks instantly.';

  @override
  String get telebirrReceiptNumber => 'Telebirr receipt number';

  @override
  String get receiptNumberHint => 'e.g. CHQ261Z4AB2C';

  @override
  String get checkingWithTelebirr => 'Checking with Telebirr…';

  @override
  String get verifyAndActivate => 'Verify & Activate';

  @override
  String get activationCodeTitle => 'Activation code';

  @override
  String get codeBoundNote =>
      'Codes are bound to one device. If a receipt check ever fails, send '
      'this device code with your payment and a code is minted for this '
      'phone.';

  @override
  String get activate => 'Activate';

  @override
  String activationRejection(
    ActivationRejectReason reason,
    String fallback, {
    String amount = '',
  }) =>
      fallback;

  @override
  String get crashReportsNote =>
      'If the app ever crashes, it sends an anonymous report — no receipt '
      'or account data — so problems get fixed faster.';

  // ------------------------------------------------- history upgrade (v1.9.0)

  @override
  String get statsChecks => 'Checks';

  @override
  String get statsVerified => 'Verified';

  @override
  String get statsTotal => 'Total';

  @override
  String get groupToday => 'Today';

  @override
  String get groupYesterday => 'Yesterday';

  @override
  String get groupThisWeek => 'This week';

  @override
  String get groupEarlier => 'Earlier';

  @override
  String get removedToast => 'Removed from history';

  @override
  String get undo => 'Undo';

  @override
  String get emptyCta => 'Verify your first receipt';

  @override
  String get exportTooltip => 'Share history';

  @override
  String get cbeNeedsCodeTitle => 'CBE needs the receipt code';

  @override
  String get cbeNeedsCodeBody =>
      'The FT number printed on the slip is CBE-internal — the bank only '
      'verifies the code inside a shared receipt link or QR. Paste the '
      'receipt link or scan the QR shown in the CBE app instead.';
}
