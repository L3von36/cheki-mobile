part of 'app_strings.dart';

/// Amharic (አማርኛ) catalog — polite plural forms throughout, matching
/// Ethiopian app conventions.
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
  String get referenceLabel => 'የደረሰኝ ቁጥር ወይም ትስስር';

  @override
  String get referenceHint => 'የደረሰኝ ትስስር ይለጥፉ ወይም ቁጥሩን ይጻፉ';

  @override
  String get pickBankHint =>
      'ደረሰኙን ያዘጋጀውን ባንክ ወይም ዋሌት ይምረጡ — '
      'ትስስርና QR ቅኝቶች በራስ-ሰር ይለዩታል።';

  @override
  String get phoneOnWallet => 'የዋሌቱ ስልክ ቁጥር';

  @override
  String lastDigitsOnly(int digits) => 'የመጨረሻ $digits አሃዞች ብቻ';

  @override
  String get clipboardEmpty => 'የቅጂ ሰሌዳው ባዶ ነው።';

  @override
  String get verifyReceiptButton => 'ደረሰኙን አረጋግጡ';

  @override
  String get stopVerifying => 'ማረጋገጥ አቁም';

  @override
  String get autoDetectBank => 'ባንክ በራስ-ሰር ይለያል';

  @override
  String detected(String bankName) => 'ተለይቷል፦ $bankName';

  @override
  String get pasteTooltip => 'ለጥፍ';

  @override
  String get scanQrInstead => 'የQR ኮዱን ይቃኙ';

  @override
  String freeChecksLeft(int count) => '$count ነጻ ይቀራሉ';

  @override
  String get upgrade => 'ደረጃ አሳድግ';

  @override
  String proDaysLeft(int days) => 'PRO · $days ቀን';

  // ---------------------------------------------------------------- auth

  @override
  String get welcomeBack => 'እንኳን ደህና መጡ';

  @override
  String get signInSubtitle => 'ደረሰኞችን ለመቀጠል ይግቡ';

  @override
  String get createAccountTitle => 'መለያዎን ይክፈቱ';

  @override
  String get createAccountSubtitle => 'በሁለት ደቂቃ ውስጥ — ለዚህ መሣሪያ ብቻ';

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
  String get passwordHint => 'ቢያንስ 6 ፊደላት';

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
  String get resetAccountsTitle => 'መለያዎችን እንደገና ይጀምሩ?';

  @override
  String get resetAccountsBody =>
      'በዚህ መሣሪያ ላይ ያሉ መለያዎች ሁሉ ይሰረዛሉ፤ አዲስ መለያ ይከፍታሉ። '
      'የማረጋገጫ ታሪክዎና የPro እቅድዎ አይነኩም።';

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
  String get creatingAccount => 'በመክፈት ላይ…';

  @override
  String get authPrivacyNote =>
      'መለያዎ በዚህ መሣሪያ ላይ ብቻ ይቀመጣል — ተመስጥሮ ወደ ውጭ አይላክም። '
      'የማረጋገጫ ታሪክዎ የግል ነው።';

  @override
  String errorAuth(AuthError error) => switch (error) {
    AuthError.invalidName => 'ሙሉ ስምዎን ያስገቡ (ቢያንስ 2 ፊደላት)።',
    AuthError.invalidIdentifier =>
      'ትክክለኛ የኢትዮጵያ ስልክ ቁጥር (09xxxxxxxx) ወይም ኢሜይል ያስገቡ።',
    AuthError.invalidEmail => 'ኢሜይሉ ትክክል አይመስልም።',
    AuthError.invalidPassword => 'የይለፍ ቃል ቢያንስ 6 ፊደላት መሆን አለበት።',
    AuthError.passwordMismatch => 'የይለፍ ቃሎቹ አይመሳሰሉም።',
    AuthError.alreadyExists => 'በዚህ ስልክ/ኢሜይል መለያ ቀድሞ አለ — ይግቡ።',
    AuthError.accountNotFound => 'በዚህ ስልክ/ኢሜይል መለያ አልተገኘም — መጀመሪያ ይክፈቱ።',
    AuthError.wrongPassword => 'የይለፍ ቃሉ ስህተት ነው። እንደገና ይሞክሩ።',
    AuthError.storageFailed => 'መለያውን ማስቀመጥ አልተቻለም። እንደገና ይሞክሩ።',
  };

  @override
  String get genericAuthError => 'ችግር አጋጥሟል። እንደገና ይሞክሩ።';

  // ---------------------------------------------------------------- settings

  @override
  String get settingsTitle => 'ቅንብሮች';

  @override
  String get accountSection => 'መለያ';

  @override
  String get signedInAs => 'የገቡት እንደ';

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
      'ለመመለስ የይለፍ ቃልዎን መጠቀም ይችላሉ — መለያዎ በዚህ መሣሪያ ላይ ይቆያል።';

  @override
  String get versionLabel => 'ስሪት';

  @override
  String get deviceCodeLabel => 'የመሣሪያ ኮድ';

  @override
  String get copiedToClipboard => 'ተቀድቷል።';

  @override
  String get close => 'ዝጋ';

  @override
  String get loading => 'በመጫን ላይ…';
}
