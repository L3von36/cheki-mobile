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

  // ---------------------------------------------------------------- scan

  @override
  String get scanTitle => 'ክፍያ ይስካኑ';

  @override
  String get scanPositionHint => 'QR ኮዱን በፍሬሙ ውስጥ ያስቀምጡ';

  @override
  String get scanUsageHint =>
      'በደረሰኙ ላይ የታተመውን QR ተጠቀሙ — '
      'የክፍያ መላኪያ ወይም የመቀበያ QR አይደለም';

  @override
  String get scanFlash => 'ብርሃን';

  @override
  String get scanGallery => 'ጋለሪ';

  @override
  String get scanNoQrFound => 'በዚያ ምስል ውስጥ የደረሰኝ QR አልተገኘም።';

  @override
  String get scanImageUnreadable => 'ያንን ምስል ማንበብ አልተቻለም።';

  @override
  String scanCameraError(String code) =>
      'ካሜራው አልተከፈተም ($code)። ይዝጉትና እንደገና ይሞክሩ።';

  @override
  String get scanRetry => 'እንደገና ይሞክሩ';

  @override
  String get scanCameraPermissionNeeded =>
      'የደረሰኝ QR ለመስካን የካሜራ ፈቃድ ያስፈልጋል።';

  @override
  String get scanGrantPermission => 'ፈቃድ ይስጡ';

  @override
  String get scanCameraOff =>
      'ለማህተም የካሜራ መዳረሻ ጠፍቷል። ከስርዓቱ ቅንብሮች ይክፈቱት፣ '
      'ወይም የደረሰኙን ሊንክ ይለጥፉ።';

  @override
  String get scanOpenSettings => 'ቅንብሮችን ይክፈቱ';

  @override
  String get scanCameraUnavailable => 'ካሜራ አይገኝም';

  @override
  String get typeSheetTitle => 'የግብይት ወይም የማጣቀሻ ቁጥር ይጻፉ';

  @override
  String get typeSheetHint =>
      'ለምሳሌ FT2614G2P01YB — ወይም የማረጋገጫ ሊንክ ይለጥፉ';

  @override
  String get typeSheetRecent => 'የቅርብ ጊዜ ፍተሻዎች';

  // ------------------------------------- reference number scanner (v1.10.0)

  @override
  String get scanNumberAction => 'ቁጥር ይስካኑ';

  @override
  String get refScanTitle => 'የደረሰኝ ቁጥር ይስካኑ';

  @override
  String get refScanHint =>
      'ካሜራውን በደረሰኙ ላይ ያለው የግብይት ወይም የማጣቀሻ ቁጥር ላይ ያነጣጥሉ '
      '— በፍሬሙ ውስጥ ያሉ ቁጥሮች ብቻ ይነበባሉ';

  @override
  String get refScanLooking => 'ቁጥሩን በመፈለግ ላይ…';

  @override
  String get refScanFoundTitle => 'የተገኙ ቁጥሮች — ለማረጋገጥ ይንኩ';

  @override
  String get refScanTypeInstead => 'በእጅ ይጻፉ';

  @override
  String get refScanNoNumberFound =>
      'ቁጥር አልተገኘም። ተቃርበው፣ ብርሃን ይጨምሩ ወይም በእጅ ይጻፉ።';

  // ---------------------------------------------------------------- result

  @override
  String get resultTitle => 'የማረጋገጫ ውጤት';

  @override
  String get resultNothingToShow => 'ለማሳየት ደረሰኝ የለም።';

  @override
  String get resultVerifiedTitle => 'ክፍያው ተረጋግጧል!';

  @override
  String get resultFailedTitle => 'ማረጋገጫው አልተሳካም';

  @override
  String get resultVerifiedBody =>
      'ክፍያው እውነተኛ ነው — በባንኩ ተረጋግጧል።';

  @override
  String get resultFailedBody => 'ይህ ደረሰኝ ማረጋገጥ አልተቻለም።';

  @override
  String get resultDone => 'ተጠናቋል';

  @override
  String get resultShare => 'ያጋሩ';

  @override
  String get resultTryAgain => 'እንደገና ይሞክሩ';

  @override
  String get senderLabel => 'ላኪ';

  @override
  String get senderAccountLabel => 'የላኪ መለያ';

  @override
  String get receiverLabel => 'ተቀባይ';

  @override
  String get receiverAccountLabel => 'የተቀባይ መለያ';

  @override
  String get dateLabel => 'ቀን';

  @override
  String get referenceShortLabel => 'ማጣቀሻ';

  @override
  String get reasonLabel => 'ምክንያት';

  @override
  String get statusLabel => 'ኹኔታ';

  @override
  String get bankShortLabel => 'ባንክ';

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
      ..writeln('ክፍያ በማህተም ተረጋግጧል')
      ..writeln('ባንክ፦ $bankName')
      ..writeln('ማጣቀሻ፦ $reference')
      ..writeln('መጠን፦ $amount')
      ..writeln('ላኪ፦ $sender')
      ..writeln('ተቀባይ፦ $receiver')
      ..write('ቀን፦ $date');
    return buffer.toString();
  }

  // ------------------------------------------------------- verify failures

  @override
  String failureMessage(VerifyErrorKind kind, String fallback) =>
      switch (kind) {
        VerifyErrorKind.network =>
          'አገልግሎቱን ማግኘት አልተቻለም። በመስመር ላይ መሆንዎን ያረጋግጡ።',
        VerifyErrorKind.notFound => 'በዚህ ቁጥር ደረሰኝ አልተገኘም።',
        VerifyErrorKind.badInput =>
          'ትክክለኛ የደረሰኝ ቁጥር ወይም ሊንክ ያስገቡ።',
        VerifyErrorKind.unreadable =>
          'የደረሰኙን QR ማንበብ አልተቻለም — እንደገና ይሞክሩ።',
        VerifyErrorKind.unsupported =>
          'ይህ ባንክ ወይም የደረሰኝ ዓይነት እስካሁን አይደገፍም።',
        VerifyErrorKind.blocked => failureBlockedMessage(),
      };

  @override
  List<String> failureTips(VerifyErrorKind kind, List<String> fallback) =>
      switch (kind) {
        VerifyErrorKind.network => const [
          'ሞባይል ዳታ ወይም Wi-Fi በርቷል ያረጋግጡ።',
          'አገልግሎቱ ጊዜያዊ ሊሆን ይችላል — ጥቂት ቆይተው እንደገና ይሞክሩ።',
        ],
        VerifyErrorKind.notFound => const [
          'ቁጥሩ ሳይሰረዝ እንዲገባ እንደገና ያረጋግጡ።',
          'ሊንክ ከለጠፉ ሙሉው እንደሆነ ያረጋግጡ።',
        ],
        VerifyErrorKind.badInput => const [
          'ሊንኩን እንደተላከልዎ በትክክል ይለጥፉ።',
        ],
        VerifyErrorKind.unreadable => const [
          'ሙሉውን QR በብርሃን ውስጥ በፍሬሙ ውስጥ ያስቀምጡ።',
          'ከኤስኤምኤሱ የደረሰኙን ቁጥር በእጅ ይለጥፉ።',
        ],
        VerifyErrorKind.unsupported => const [
          'መተግበሪያው የሚደግፋቸውን ባንኮች በመጀመሪያው ገጽ ላይ ይመልከቱ።',
        ],
        VerifyErrorKind.blocked => failureBlockedTips(),
      };

  // ---------------------------------------------------------------- history

  @override
  String get historyTitle => 'ታሪክ';

  @override
  String get clearHistoryTooltip => 'ታሪክ አጥፋ';

  @override
  String get clearHistoryTitle => 'ታሪክ ይጥፋ?';

  @override
  String get clearHistoryBody =>
      'የተቀመጡ ማረጋገጫዎች ሁሉ ከዚህ መሣሪያ ይሰረዛሉ።';

  @override
  String get clearButton => 'አጥፋ';

  @override
  String get noChecksTitle => 'እስካሁን ማረጋገጫ የለም';

  @override
  String get noChecksBody => 'የተረጋገጡ ደረሰኞች እዚህ ይታያሉ።';

  @override
  String get verifiedPaymentLabel => 'ክፍያ ተረጋግጧል';

  @override
  String get notVerifiedLabel => 'አልተረጋገጠም';

  @override
  String get checkedLabel => 'ተፈትሿል';

  @override
  String get noteLabel => 'ማስታወሻ';

  @override
  String get historySearchTooltip => 'ታሪክ ይፈልጉ';

  @override
  String get historySearchHint => 'በቁጥር፣ በስም ወይም በባንክ ይፈልጉ';

  @override
  String get filterAll => 'ሁሉም';

  @override
  String get filterVerified => 'የተረጋገጠ';

  @override
  String get filterFailed => 'ያልተረጋገጠ';

  @override
  String get noMatchesTitle => 'አልተገኘም';

  @override
  String get noMatchesBody =>
      'ከፍለጋው ወይም ከማጣሪያው ጋር የሚስማማ ፍተሻ የለም።';

  @override
  String get verifyAgain => 'እንደገና ይረጋግጡ';

  @override
  String get prefilledToast =>
      'መረጃው ተሞልቷል — ይመልከቱና ያረጋግጡ።';

  // ---------------------------------------------------------------- paywall

  @override
  String get paywallTitle => 'Mahtem Pro';

  @override
  String get pasteReceiptFromSms =>
      'ከተሌብር ኤስኤምኤሱ የደረሰኙን ቁጥር ይለጥፉ።';

  @override
  String get pasteActivationCode =>
      'የተላከልዎትን አክቲቬሽን ኮድ ይለጥፉ።';

  @override
  String get codeBadFormat =>
      'ይህ የማህተም አክቲቬሽን ኮድ አይመስልም።';

  @override
  String get codeBadSignature =>
      'ኮዱ ትክክል አይደለም — እንዲላክልዎ ለላኪው ይንገሩ።';

  @override
  String get codeWrongDevice =>
      'ኮዱ ለሌላ መሣሪያ የተዘጋጀ ነው። ከክፍያዎ ጋር ከታች '
      'የሚታየውን የመሣሪያ ኮድ ይላኩ።';

  @override
  String codeExpired(String date) =>
      'ኮዱ በ$date አብቅቷል። ለመቀጠል አዲስ ይግዙ።';

  @override
  String get codeNotAccepted => 'ኮዱን መቀበል አልተቻለም።';

  @override
  String proActivatedToast(String date) =>
      'Mahtem Pro እስከ $date ድረስ ንቁ ነው 🎉';

  @override
  String get clipboardEmptyForPaste =>
      'ኮፒ የተደረገ ነገር የለም — መጀመሪያ ቁጥሩን ኮፒ ያድርጉ።';

  @override
  String telebirrNumberCopied(String number) =>
      'የተሌብር ቁጥር $number ኮፒ ተደርጓል — በተሌብር '
      'መተግበሪያው ውስጥ ይለጥፉት።';

  @override
  String amountCopied(String amount) => '$amount ብር ኮፒ ተደርጓል።';

  @override
  String get stackingNote =>
      'አንድ ደረሰኝ በዚህ መሣሪያ ላይ አንድ እቅድ ይከፍታል። ለመቀጠል '
      'እንደገና ክፍያ አድርገው አዲሱን የደረሰኝ ቁጥር ይለጥፉ — '
      'የተከፈሉ ቀናት ይተራረፋሉ።';

  @override
  String get hideActivationCode => 'አክቲቬሽን ኮዱን ደብቅ';

  @override
  String get haveActivationCode => 'የአክቲቬሽን ኮድ አለዎት?';

  @override
  String get deviceCodeCopied => 'የመሣሪያ ኮድ ኮፒ ተደርጓል።';

  @override
  String get proActiveTitle => 'Mahtem Pro ንቁ ነው';

  @override
  String proUnlimitedUntil(String date) =>
      'እስከ $date ድረስ ያለገደብ ማረጋገጫ።';

  @override
  String trialsLeftTitle(int count) => count == 1
      ? 'አንድ ነጻ ማረጋገጫ ቀሪ ነው'
      : '$count ነጻ ማረጋገጫዎች ቀሪ አሉ';

  @override
  String get trialsLeftBody =>
      'ካለቀ በኋላ ከታች Mahtem Pro ይክፈቱ — ታሪክዎና '
      'ቅንብሮችዎ ሳይነኩ ይቆያሉ።';

  @override
  String get trialsGoneTitle => 'ነጻ ማረጋገጫዎች አልቀዋል';

  @override
  String get trialsGoneBody =>
      'ደረሰኞችዎን ማረጋገጥን ለመቀጠል ከታች ይክፈቱ — '
      'በአንድ ደቂቃ ይጨርሳሉ።';

  @override
  String get pricePerMonth => 'ብር / ወር';

  @override
  String get priceUnlimitedBody =>
      'በሁሉም ባንኮችና ዋሌቶች ያለገደብ የደረሰኝ ማረጋገጫ — '
      'CBE፣ ተሌብር፣ BOA፣ M-Pesa እና ሌሎችም።';

  @override
  String priceYearlyOnce(String price) =>
      'ወይም ለአንድ ዓመት በአንድ ጊዜ $price ብር ይክፈሉ።';

  @override
  String get howToActivate => 'መመሪያ';

  @override
  String step1Title(String monthly, String yearly) =>
      'በተሌብር $monthly ብር (ወይም በዓመት $yearly ብር) ይክፈሉ';

  @override
  String get step1Body => 'ትክክለኛውን መጠን ለዚህ የተሌብር መለያ ይላኩ፦';

  @override
  String copyAmountChip(String amount) => 'መጠኑን ኮፒ ያድርጉ — $amount ብር';

  @override
  String get step2Title => 'የደረሰኙን ቁጥር ከታች ይለጥፉ';

  @override
  String step2Body(String monthly) =>
      'ተሌብር ከደረሰኝ ቁጥር ጋር የማረጋገጫ ኤስኤምኤስ ይልካል '
      '(ለምሳሌ CHQ261Z4AB2C) — እዚህ ይለጥፉትና መተግበሪያው '
      'በተሌብር ራሱ ያረጋግጠዋል። እውነተኛ $monthly ብር ክፍያ '
      'ከሆነ፣ Mahtem Pro ወዲያውኑ ይከፈታል።';

  @override
  String get telebirrReceiptNumber => 'የተሌብር ደረሰኝ ቁጥር';

  @override
  String get receiptNumberHint => 'ለምሳሌ CHQ261Z4AB2C';

  @override
  String get checkingWithTelebirr => 'ተሌብር እያረጋገጠ ነው…';

  @override
  String get verifyAndActivate => 'ያረጋግጡና ይክፈቱ';

  @override
  String get activationCodeTitle => 'አክቲቬሽን ኮድ';

  @override
  String get codeBoundNote =>
      'ኮዶች ለአንድ መሣሪያ ብቻ ይሰራሉ። የደረሰኝ ማረጋገጫ ከሳሳ፣ '
      'ከክፍያዎ ጋር ይህን የመሣሪያ ኮድ ይላኩ — ለዚህ ስልክ '
      'ተዘጋጅቶ ይላክልዎታል።';

  @override
  String get activate => 'ይክፈቱ';

  @override
  String activationRejection(
    ActivationRejectReason reason,
    String fallback, {
    String amount = '',
  }) =>
      switch (reason) {
        ActivationRejectReason.emptyInput =>
          'ከተሌብር ኤስኤምኤሱ የደረሰኙን ቁጥር ይለጥፉ።',
        ActivationRejectReason.notTelebirr =>
          'ለMahtem Pro የሚያነቃው የተሌብር ደረሰኝ ብቻ ነው።',
        ActivationRejectReason.transactionFailed =>
          'ያ የተሌብር ግብይት አልተጠናቀቀም — ማንቃት አልተቻለም።',
        ActivationRejectReason.wrongAmount =>
          'ይህ ደረሰኝ የተላከው በተለየ መጠን ነው — ማንቃት የሚጠይቀው '
              'ትክክለኛውን የእቅድ ዋጋ ነው (ከታች ይመልከቱ)።',
        ActivationRejectReason.wrongReceiver =>
          'ክፍያው ለመመሪያው ውስጥ ካለው የተሌብር መለያ አልተላከም። '
              'የእቅዱን ዋጋ ለዚያ መለያ መላክና አዲሱን ደረሰኝ '
              'መለጠፍ ያስፈልጋል።',
        ActivationRejectReason.receiptTooOld =>
          'ይህ ደረሰኝ በጣም ጥንታዊ ነው። እንደገና ክፍያ አድርገው '
              'ከአዲሱ ኤስኤምኤስ ያለውን ደረሰኝ ይጠቀሙ።',
        ActivationRejectReason.alreadyUsed =>
          'ይህ ደረሰኝ ቀድሞ በዚህ መሣሪያ ላይ ተጠቅሟል። እቅዱ '
              'ሲያልቅ እንደገና ክፍያ አድርገው አዲሱን ደረሰኝ '
              'ይለጥፉ።',
      };

  @override
  String get crashReportsNote =>
      'መተግበሪያው ሲበላሽ ችግሩን የሚገልጽ መረጃ ያለ ስምዎ '
      'ይላካል — ደረሰኝም ሆነ የመለያ መረጃዎ አያካትቱም።';

  // ------------------------------------------------ error safety net (v1.12.1)

  @override
  String get somethingWentWrongScreen =>
      'ይህንን ክፍል በማሳየት ላይ ችግር በገጠመ። ተመልሰው እንደገና ይሞክሩ።';

  @override
  String get reportProblemTile => 'ችግር ይመዝግቡ';

  @override
  String get reportProblemTitle => 'በዚህ መሣሪያ ላይ የተመዘገቡ ችግሮች';

  @override
  String get reportProblemEmpty =>
      'እስካሁን ምንም ችግር አልተመዘገበም። መተግበሪያው ችግር ከፈጠረ ዝርዝሮቹ '
      'እዚህ ይታያሉ — ችግሩን ስያዘው እንዲጋሩዎት ይቻላል።';

  @override
  String get reportProblemHint =>
      'እነዚህ ዝርዝሮች በመሣሪያዎ ውስጥ ብቻ ይቆያሉ። ችግር ስያስቡ ቅጂያቸውን '
      'አውጥተው አብረው ይላኩ።';

  @override
  String get reportProblemCopy => 'ዝርዝሮቹን ቅጂ';

  // ------------------------------------------------- history upgrade (v1.9.0)

  @override
  String get statsChecks => 'ፍተሻዎች';

  @override
  String get statsVerified => 'የተረጋገጡ';

  @override
  String get statsTotal => 'ጠቅላላ';

  @override
  String get groupToday => 'ዛሬ';

  @override
  String get groupYesterday => 'ትናንት';

  @override
  String get groupThisWeek => 'በዚህ ሳምንት';

  @override
  String get groupEarlier => 'ከዚያ በፊት';

  @override
  String get removedToast => 'ከታሪክ ተወግዷል።';

  @override
  String get undo => 'መልስ';

  @override
  String get emptyCta => 'የመጀመሪያውን ደረሰኝዎን ያረጋግጡ';

  @override
  String get exportTooltip => 'ታሪክ ያጋሩ';

  @override
  String get cbeNeedsCodeTitle => 'ሲቢኤ የደረሰኝ ኮድ ያስፈልገዋል';

  @override
  String get cbeNeedsCodeBody =>
      'በደረሰኙ ላይ የሚታየው የFT ቁጥር የሲቢኤ ውስጣዊ ቁጥር ነው — ባንኩ የሚያረጋግጠው ከተሰራጨው '
      'የደረሰኝ ሊንክ ወይም ከQR ውስጥ ያለውን ኮድ ብቻ ነው። እባክዎ ሊንኩን ይለጥፉ ወይም በሲቢኤ '
      'መተግበሪያው ውስጥ የሚታየውን QR ይስካኑ።';

  @override
  String failureBlockedMessage() =>
      'የሲንቄ ባንክ ደረሰኝ አገልግሎት ለወዲሁን ከዚህ ኔትወርክ ራሱን እየከላከለ ነው።';

  @override
  List<String> failureBlockedTips() => const [
        'የደረሰኙን ሊንክ በብራውዘርዎ ይክፈቱ።',
        'ከላኪው የደረሰኙ ስክሪንሾት ጠይቁ።',
      ];

  @override
  String staleReceiptNote(int days) => days == 1
      ? 'ደረሰኙ ከአንድ ቀን በፊት የተፈጠረ ነው። ከዛሬ ሽያጭዎ ጋር መዛመዱን እስከማረጋገጥዎ እባክዎ '
          'እቃውን አይስጡ።'
      : 'ደረሰኙ ከ$days ቀናት በፊት የተፈጠረ ነው። ከዛሬ ሽያጭዎ ጋር መዛመዱን እስከማረጋገጥዎ '
          'እባክዎ እቃውን አይስጡ።';

  @override
  String duplicateReceiptNote(String when) =>
      'ይህን ትክክለኛ ደረሰኝ ከዚህ በፊት ($when) አረጋግጠዋል። ደጋግሞ የሚያሳዩ ደረሰኞች '
      'የተለመደ ማጭበርከር ነው — አዲስ ክፍያ መሆኑን ያረጋግጡ።';

  @override
  String get pasteExtractedToast => 'የደረሰኝ ቁጥር ከጽሑፉ ውስጥ ተገኝቷል።';

  @override
  String get batchTitle => 'በብዛት ማረጋገጫ';

  @override
  String get batchIntro =>
      'ብዙ የደረሰኝ ሊንኮችን ወይም ቁጥሮችን ይለጥፉ — አንድ በአንድ መስመር ላይ — አንድላይ '
      'ይረጋግጡ። ለዕለታዊ የገበያ ሂሳብ ማስተካከያ የተዘጋጀ ነው።';

  @override
  String get batchInputHint =>
      'አንድ የደረሰኝ ሊንክ ወይም ቁጥር በአንድ መስመር…\n'
      'https://mbreciept.cbe.com.et/…\n'
      'CHQ261Z4AB2C\n'
      'FT26140P01YB';

  @override
  String get batchBankLabel => 'የተለመዱ ቁጥሮች ባንክ';

  @override
  String batchStart(int count) => count == 1
      ? '1 ደረሰኝ ይረጋግጡ'
      : '$count ደረሰኞችን ይረጋግጡ';

  @override
  String batchNeedMore(int have, int need) =>
      'ይህ ቡድን $need ማረጋገጫዎችን ይፈልጋል — $have ብቻ ቀርተዋል። '
      'ለመቀጠል ደረጃ ያሳልፉ።';

  @override
  String batchNeedsPhone(String bank) =>
      'በብዛት $bank ማረጋገጥ አይቻልም፦ እያንዳንዱ ደረሰኝ የራሱ የመላኪያ ስልክ ቁጥር '
      'ይፈልጋል።';

  @override
  String batchNeedsBank(int count) => count == 1
      ? 'መጀመሪያ ለመሰረታዊው ቁጥር ባንክ ይምረጡ'
      : 'መጀመሪያ ለ$count መሰረታዊ ቁጥሮች ባንክ ይምረጡ';

  @override
  String batchDuplicates(int count) =>
      count == 1 ? '1 ተደጋጋሚ ተዝሏል' : '$count ተደጋጋሚዎች ተዝለዋል';

  @override
  String batchProgress(int done, int total) =>
      'በመረጋገጥ ላይ… $done ከ$total';

  @override
  String batchDoneCounts(int verified, int failed) =>
      '✓ $verified ተረጋግጠዋል · ✗ $failed አልተረጋገጠም';

  @override
  String batchRemaining(int count) => count == 1
      ? 'ቀሪውን 1 ደረሰኝ ይረጋግጡ'
      : 'ቀሪዎቹን $count ደረሰኞች ይረጋግጡ';

  @override
  String get batchShareTooltip => 'ውጤቶችን ያጋሩ';

  @override
  String get batchEmpty =>
      'እስካሁን ምንም የሚረጋገጥ የለም — ከላይ ቁጥሮችን ይለጥፉ ወይም ይጻፉ።';

  @override
  String get batchSkipDuplicate => 'በዚህ ቡድን ውስጥ ተደጋጋሚ';

  @override
  String get batchSkipCbe => 'የሲቢኤ የታተመ ቁጥር — የደረሰኝ ኮድ ያስፈልገዋል';

  @override
  String get batchSkipUnknown => 'ሊንኩ አልታወቀም';

  @override
  String get batchSkipOverLimit => 'ከ50 መስመር በላይ ነው';
}
