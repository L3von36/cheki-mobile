part of 'app_strings.dart';

/// Amharic (አማርኛ) catalog — polite plural forms throughout, matching
/// Ethiopian app conventions. Phrasing is idiomatic Amharic the way
/// people actually say it (everyday loanwords like ሊንክ / ኮፒ / ስካን
/// included) — never a word-for-word rendering of the English source.
final class AmharicStrings extends AppStrings {
  const AmharicStrings();

  @override
  AppLocale get locale => AppLocale.amharic;

  // ---------------------------------------------------------------- shell

  @override
  String get verifyTab => 'ማረጋገጫ';

  @override
  String historyTab(int count) => count > 0 ? 'ታሪክ ($count)' : 'ታሪክ';

  // ---------------------------------------------------------------- home

  @override
  String get referenceLabel => 'የደረሰኝ ቁጥር ወይም ሊንክ';

  @override
  String get referenceHint => 'የደረሰኙን ሊንክ ይለጥፉ ወይም ቁጥሩን ይጻፉ';

  @override
  String get pickBankHint =>
      'ደረሰኙ የወጣበትን ባንክ ወይም ዋሌት ይምረጡ — '
      'በሊንክና በQR ስካን ባንኩ በራስ-ሰር ይታወቃል።';

  @override
  String get phoneOnWallet => 'የዋሌቱ ስልክ ቁጥር';

  @override
  String lastDigitsOnly(int digits) => 'የመጨረሻ $digits አሃዞች ብቻ';

  @override
  String get clipboardEmpty => 'ኮፒ የተደረገ ነገር የለም።';

  @override
  String get verifyReceiptButton => 'ደረሰኙን አረጋግጡ';

  @override
  String get stopVerifying => 'ማረጋገጡን ያቁሙ';

  @override
  String get autoDetectBank => 'ባንክ በራስ-ሰር ይታወቃል';

  @override
  String detected(String bankName) => 'ተገኝቷል፦ $bankName';

  @override
  String get pasteTooltip => 'ለጥፍ';

  @override
  String get scanQrInstead => 'የQR ኮዱን ይስካኑ';

  @override
  String freeChecksLeft(int count) => '$count ነጻ ቀርተዋል';

  @override
  String get upgrade => 'አባል ይሁኑ';

  @override
  String proDaysLeft(int days) => 'PRO · $days ቀን';

  // ---------------------------------------------------------------- auth

  @override
  String get welcomeBack => 'እንኳን ደህና መጡ';

  @override
  String get signInSubtitle => 'ደረሰኞችዎን ማረጋገጥን ለመቀጠል ይግቡ';

  @override
  String get createAccountTitle => 'መለያዎን ይክፈቱ';

  @override
  String get createAccountSubtitle => 'በሁለት ደቂቃ ውስጥ ይፈጠራል — ለዚህ መሣሪያ ብቻ።';

  @override
  String get fullName => 'ሙሉ ስም';

  @override
  String get fullNameHint => 'ለምሳሌ፦ አበበ ከበደ';

  @override
  String get identifierLabel => 'ስልክ ቁጥር ወይም ኢሜይል';

  @override
  String get identifierHint => '09xxxxxxxx ወይም you@mail.com';

  @override
  String get passwordLabel => 'የይለፍ ቃል';

  @override
  String get passwordHint => 'ቢያንስ 6 ቁምፊዎች';

  @override
  String get confirmPasswordLabel => 'የይለፍ ቃል ያረጋግጡ';

  @override
  String get signInButton => 'ግቡ';

  @override
  String get signInLink => 'ግቡ';

  @override
  String get createAccountButton => 'መለያ ይክፈቱ';

  @override
  String get createAccountLink => 'መለያ ይክፈቱ';

  @override
  String get noAccountPrompt => 'መለያ የለዎትም?';

  @override
  String get haveAccountPrompt => 'መለያ አለዎት?';

  @override
  String get forgotPassword => 'የይለፍ ቃል ረስተዋል?';

  @override
  String get resetAccountsTitle => 'መለያዎችን ዳግም ይጀምሩ?';

  @override
  String get resetAccountsBody =>
      'በዚህ መሣሪያ ላይ ያሉት መለያዎች ሁሉ ይሰረዛሉ፤ ከዚያም አዲስ መለያ ይከፍታሉ። '
      'የማረጋገጫ ታሪክዎም ሆነ የPro እቅድዎ አይነኩም።';

  @override
  String get resetAccountsConfirm => 'አጥፋ';

  @override
  String get cancel => 'ሰርዝ';

  @override
  String get ok => 'እሺ';

  @override
  String get showPassword => 'የይለፍ ቃል አሳይ';

  @override
  String get hidePassword => 'የይለፍ ቃል ደብቅ';

  @override
  String get signingIn => 'በመግባት ላይ…';

  @override
  String get creatingAccount => 'መለያ በመክፈት ላይ…';

  @override
  String get authPrivacyNote =>
      'መለያዎ ተመስጥሮ በዚህ መሣሪያ ላይ ብቻ ይቀመጣል — ወደ ውጭ በጭራሽ አይላክም። '
      'የማረጋገጫ ታሪክዎ የግል ይቆያል።';

  @override
  String errorAuth(AuthError error) => switch (error) {
    AuthError.invalidName => 'ሙሉ ስምዎን ያስገቡ (ቢያንስ 2 ፊደላት)።',
    AuthError.invalidIdentifier =>
      'ትክክለኛ የኢትዮጵያ ስልክ ቁጥር (09xxxxxxxx) ወይም ኢሜይል ያስገቡ።',
    AuthError.invalidEmail => 'ኢሜይሉ ትክክል አይመስልም።',
    AuthError.invalidPassword => 'የይለፍ ቃል ቢያንስ 6 ቁምፊዎች መሆን አለበት።',
    AuthError.passwordMismatch => 'የይለፍ ቃሎቹ አይመሳሰሉም።',
    AuthError.alreadyExists => 'በዚህ ስልክ/ኢሜይል መለያ ቀድሞ አለ — እባክዎ ይግቡ።',
    AuthError.accountNotFound =>
      'በዚህ ስልክ/ኢሜይል መለያ አልተገኘም — መጀመሪያ መለያ ይክፈቱ።',
    AuthError.wrongPassword => 'የይለፍ ቃሉ ተሳስቷል። እንደገና ይሞክሩ።',
    AuthError.storageFailed => 'መለያውን ማስቀመጥ አልተቻለም። እንደገና ይሞክሩ።',
  };

  @override
  String get genericAuthError => 'ችግር አጋጥሟል። እባክዎ እንደገና ይሞክሩ።';

  // ---------------------------------------------------------------- settings

  @override
  String get settingsTitle => 'ቅንብሮች';

  @override
  String get accountSection => 'መለያ';

  @override
  String get signedInAs => 'የገቡበት መለያ';

  @override
  String get appearanceSection => 'ገጽታ';

  @override
  String get themeSystem => 'ስርዓት';

  @override
  String get themeLight => 'ብርሃናማ';

  @override
  String get themeDark => 'ጨለማ';

  @override
  String get languageSection => 'ቋንቋ';

  @override
  String get signOut => 'ይውጡ';

  @override
  String get signOutConfirmTitle => 'ይውጡ?';

  @override
  String get signOutConfirmBody =>
      'መልሰው ሲገቡ የይለፍ ቃልዎን ይጠቀማሉ — መለያዎ በዚህ መሣሪያ ላይ ሆኖ ይቆያል።';

  @override
  String get versionLabel => 'ስሪት';

  @override
  String get deviceCodeLabel => 'የመሣሪያ ኮድ';

  @override
  String get copiedToClipboard => 'ኮፒ ተደርጓል።';

  @override
  String get close => 'ዝጋ';

  @override
  String get loading => 'በመጫን ላይ…';
}
