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
}
