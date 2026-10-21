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
  String get referenceHint => 'የደረሰኝ ሊንኩን እዚህ ይለጥፉ ወይም ቁጥሩን ይጻፉ';

  @override
  String get pickBankHint =>
      'ደረሰኙ የተላከበትን ባንክ ወይም ዋሌት ይምረጡ — '
      'በሊንክና በQR ስካን ባንኩ በራስ-ሰር ይታወቃል።';

  @override
  String get phoneOnWallet => 'የዋሌቱ ስልክ ቁጥር';

  @override
  String lastDigitsOnly(int digits) => 'የመጨረሻዎቹን $digits አሃዞች ብቻ';

  @override
  String get clipboardEmpty => 'በክሊፕቦርዱ ላይ ምንም የለም።';

  @override
  String get verifyReceiptButton => 'ደረሰኙን ያረጋግጡ';

  @override
  String get stopVerifying => 'ማረጋገጫውን አቁም';

  @override
  String get autoDetectBank => 'ባንኩን በራሱ ይወቅ';

  @override
  String detected(String bankName) => 'ተገኝቷል፦ $bankName';

  @override
  String get pasteTooltip => 'ለጥፍ';

  @override
  String get scanQrInstead => 'የQR ኮዱን ስካን ያድርጉ';

  @override
  String freeChecksLeft(int count) => count == 1
      ? 'አንድ ነፃ ማረጋገጫ ቀርቷል'
      : '$count ነፃ ማረጋገጫዎች ቀርተዋል';

  @override
  String get upgrade => 'ወደ Pro ያሻሽሉ';

  @override
  String proDaysLeft(int days) => 'PRO · $days ቀን';

  // ---------------------------------------------------------------- auth

  @override
  String get welcomeBack => 'እንኳን ደህና መጡ';

  @override
  String get signInSubtitle => 'ደረሰኞችዎን ማረጋገጥ ለመቀጠል ይግቡ';

  @override
  String get createAccountTitle => 'መለያ ይፍጠሩ';

  @override
  String get createAccountSubtitle => 'ለዚህ መሣሪያ ብቻ የሚሆን መለያ በጥቂት ሰከንዶች ውስጥ ይፍጠሩ።';

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
  String get signInButton => 'በመለያ ግባ';

  @override
  String get signInLink => 'በመለያ ግባ';

  @override
  String get createAccountButton => 'መለያ ይፍጠሩ';

  @override
  String get createAccountLink => 'መለያ ይፍጠሩ';

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
  String get cancel => 'ተመለስ';

  @override
  String get ok => 'እሺ';

  @override
  String get showPassword => 'የይለፍ ቃል አሳይ';

  @override
  String get hidePassword => 'የይለፍ ቃል ደብቅ';

  @override
  String get signingIn => 'በመግባት ላይ…';

  @override
  String get creatingAccount => 'መለያ በመፍጠር ላይ…';

  @override
  String get accountCreatedSuccess => 'መለያዎ በተሳካ ሁኔታ ተፈጥሯል!';

  @override
  String get authPrivacyNote =>
      'መለያዎ ተመስጥሮ በዚህ መሣሪያ ላይ ይቀመጣል — የይለፍ ቃልዎ ግን ወደ ውጭ አይላክም። '
      'በአዲስ መሣሪያ ላይ ሲገቡ ከይለፍ ቃልዎ የተሰራ አንድ-አቅጣጫ ቁልፍ ብቻ ይላካል፤ '
      'የማረጋገጫ ታሪክ ምትኬዎችም ተመስጥረው ብቻ ይላካሉ።';

  @override
  String errorAuth(AuthError error) => switch (error) {
    AuthError.invalidName => 'ሙሉ ስምዎን ያስገቡ (ቢያንስ 2 ቁምፊዎች)።',
    AuthError.invalidIdentifier =>
      'ትክክለኛ የኢትዮጵያ ስልክ ቁጥር (09xxxxxxxx) ወይም ኢሜይል ያስገቡ።',
    AuthError.invalidEmail => 'ኢሜይሉ ትክክል አይመስልም።',
    AuthError.invalidPassword => 'የይለፍ ቃል ቢያንስ 6 ቁምፊዎች መሆን አለበት።',
    AuthError.passwordMismatch => 'የይለፍ ቃሎቹ አይዛመዱም።',
    AuthError.alreadyExists => 'በዚህ ስልክ/ኢሜይል የተመዘገበ መለያ አስቀድሞ አለ፤ እባክዎ ይግቡ።',
    AuthError.accountNotFound =>
      'በዚህ ስልክ/ኢሜይል የተመዘገበ መለያ የለም — መጀመሪያ መለያ ይፍጠሩ።',
    AuthError.wrongPassword => 'የይለፍ ቃሉ ተሳስቷል። እንደገና ይሞክሩ።',
    AuthError.network =>
      'የመለያ አገልግሎቱን ማግኘት አልተቻለም። የበይነመረብ ግንኙነትዎን ያረጋግጡ።',
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
  String get themeLight => 'ብሩህ';

  @override
  String get themeDark => 'ጨለማ';

  @override
  String get languageSection => 'ቋንቋ';

  @override
  String get signOut => 'ከመለያ ውጣ';

  @override
  String get signOutConfirmTitle => 'ከመለያ ይውጡ?';

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
  String get scanTitle => 'ደረሰኝ ይስካኑ';

  @override
  String get scanPositionHint => 'QR ኮዱን በሳጥኑ ውስጥ ያስገቡ';

  @override
  String get scanUsageHint =>
      'በደረሰኙ ላይ ያለውን QR ይጠቀሙ — '
      'የክፍያ መላኪያ ወይም የመቀበያ QR አይደለም';

  @override
  String get scanFlash => 'ፍላሽ';

  @override
  String get scanGallery => 'ጋለሪ';

  @override
  String get scanNoQrFound => 'በዚያ ምስል ውስጥ የደረሰኝ QR አልተገኘም።';

  @override
  String get scanImageUnreadable => 'ያንን ምስል ማንበብ አልተቻለም።';

  @override
  String get scanNoReceiptFound =>
      'በዚያ ምስል ውስጥ የደረሰኝ QR ወይም ቁጥር አልተገኘም።';

  @override
  String scanCameraError(String code) =>
      'ካሜራውን ማስነሳት አልተቻለም ($code)። ይህን ገጽ ይዝጉና እንደገና ይሞክሩ።';

  @override
  String get scanRetry => 'እንደገና ይሞክሩ';

  @override
  String get scanCameraPermissionNeeded =>
      'የደረሰኝ QR ኮድ ለመስካን የካሜራ ፈቃድ ያስፈልጋል።';

  @override
  String get scanGrantPermission => 'ፈቃድ ስጥ';

  @override
  String get scanCameraOff =>
      'ለማህተም የካሜራ መዳረሻ ተዘግቷል። በስልኩ ቅንብሮች ውስጥ ያብሩት፣ '
      'ወይም የደረሰኙን ሊንክ ይለጥፉ።';

  @override
  String get scanOpenSettings => 'ቅንብሮችን ክፈት';

  @override
  String get scanCameraUnavailable => 'ካሜራ አይገኝም';

  @override
  String get typeSheetTitle => 'የግብይት ወይም የማጣቀሻ ቁጥር ያስገቡ';

  @override
  String get typeSheetHint =>
      'ለምሳሌ FT2614G2P01YB — ወይም የማረጋገጫ ሊንክ ይለጥፉ';

  @override
  String get typeSheetRecent => 'የቅርብ ጊዜ ፍተሻዎች';

  // ------------------------------------- reference number scanner (v1.10.0)

  @override
  String get scanNumberAction => 'ቁጥሩን ስካን ያድርጉ';

  @override
  String get refScanTitle => 'የደረሰኝ ቁጥር ይስካኑ';

  @override
  String get refScanHint =>
      'ካሜራውን በደረሰኙ ላይ ያለው የግብይት ወይም የማጣቀሻ ቁጥር ላይ ያቅኑ '
      '— በፍሬሙ ውስጥ ያሉ ቁጥሮች ብቻ ይነበባሉ';

  @override
  String get refScanLooking => 'ቁጥሩን በመፈለግ ላይ…';

  @override
  String get refScanFoundTitle => 'የተገኙ ቁጥሮች — አንዱን ለማረጋገጥ ይንኩ';

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
      'ይህ ክፍያ እውነተኛ መሆኑ በባንኩ ተረጋግጧል።';

  @override
  String get resultFailedBody => 'ይህ ደረሰኝ ማረጋገጥ አልተቻለም።';

  @override
  String get resultDone => 'ተጠናቋል';

  @override
  String get resultShare => 'አጋራ';

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
  String get statusLabel => 'ሁኔታ';

  @override
  String get bankShortLabel => 'ባንክ';

  @override
  String get addReasonAction => 'ምክንያት ይጨምሩ';

  @override
  String get editReasonAction => 'ምክንያት ያስተካክሉ';

  @override
  String get reasonSheetTitle => 'ይህ ፍተሻ ለምን ተደረገ?';

  @override
  String get reasonSheetHint => 'ለምሳሌ፡ የቤት ኪራይ፣ ግዥ፣ ትእዛዝ #12';

  @override
  String get reasonSaveButton => 'አስቀምጥ';

  @override
  String get reasonSavedToast => 'ምክንያቱ ወደ ታሪክ ተቀምጧል።';

  @override
  String get yourReasonLabel => 'የእርስዎ ምክንያት';

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
          'ሞባይል ዳታ ወይም Wi-Fi መብራቱን ያረጋግጡ።',
          'አገልግሎቱ ጊዜያዊ ሊሆን ይችላል — ጥቂት ቆይተው እንደገና ይሞክሩ።',
        ],
        VerifyErrorKind.notFound => const [
          'ቁጥሩን በትክክል እንዳስገቡ እንደገና ያረጋግጡ።',
          'ሊንክ ከለጠፉ ሙሉው እንደሆነ ያረጋግጡ።',
        ],
        VerifyErrorKind.badInput => const [
          'ሊንኩን እንደተላከልዎ በትክክል ይለጥፉ።',
        ],
        VerifyErrorKind.unreadable => const [
          'ሙሉውን QR በብርሃን ውስጥ በፍሬሙ ውስጥ ያስቀምጡ።',
          'ከኤስኤምኤሱ የደረሰኙን ቁጥር ይለጥፉ።',
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
  String get clearHistoryTooltip => 'ታሪክ አጽዳ';

  @override
  String get clearHistoryTitle => 'ሁሉንም ታሪክ ያጽዱ?';

  @override
  String get clearHistoryBody =>
      'የተቀመጡ ማረጋገጫዎች ሁሉ ከዚህ መሣሪያ ይሰረዛሉ።';

  @override
  String get clearButton => 'አጽዳ';

  @override
  String get noChecksTitle => 'እስካሁን ማረጋገጫ የለም';

  @override
  String get noChecksBody => 'የሚያረጋግጧቸው ደረሰኞች እዚህ ይታያሉ።';

  @override
  String get verifiedPaymentLabel => 'ክፍያ ተረጋግጧል';

  @override
  String get notVerifiedLabel => 'አልተረጋገጠም';

  @override
  String get checkedLabel => 'የተፈተሸ';

  @override
  String get noteLabel => 'ማስታወሻ';

  @override
  String get historySearchTooltip => 'በታሪክ ውስጥ ፈልግ';

  @override
  String get historySearchHint => 'የደረሰኝ ቁጥር፣ ስም ወይም ባንክ ይፈልጉ';

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
      'ከፍለጋዎ ወይም ከማጣሪያዎ ጋር የሚስማማ ፍተሻ የለም።';

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
      'ከተሌብር ኤስኤምኤስ የደረሰኙን ቁጥር ይለጥፉ።';

  @override
  String get pasteActivationCode =>
      'የተላከልዎትን የማንቃት ኮድ ይለጥፉ።';

  @override
  String get codeBadFormat =>
      'ይህ የማህተም ማንቃት ኮድ አይመስልም።';

  @override
  String get codeBadSignature =>
      'ኮዱ ትክክል አይደለም — ላኪው እንደገና እንዲልከው ይጠይቁ።';

  @override
  String get codeWrongDevice =>
      'ኮዱ ለሌላ መሣሪያ የተዘጋጀ ነው። ከክፍያዎ ጋር ከታች '
      'የሚታየውን የመሣሪያ ኮድ ይላኩ።';

  @override
  String codeExpired(String date) =>
      'ኮዱ በ$date አብቅቷል። ለማደስ አዲስ ይግዙ።';

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
      'አንድ ደረሰኝ ለአንድ የMahtem መለያ ብቻ ይሰራል። ለመቀጠል '
      'እንደገና ክፍያ አድርገው አዲሱን የደረሰኝ ቁጥር ይለጥፉ — '
      'የተከፈሉ ቀናት ይደመራሉ።';

  @override
  String get hideActivationCode => 'የማንቃት ኮዱን ደብቅ';

  @override
  String get haveActivationCode => 'የማንቃት ኮድ አለዎት?';

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
      'ካለቀ በኋላ ከታች Mahtem Pro ያንቁ — ታሪክዎና '
      'ቅንብሮችዎ ሳይነኩ ይቆያሉ።';

  @override
  String get trialsGoneTitle => 'ነጻ ማረጋገጫዎች አልቀዋል';

  @override
  String get trialsGoneBody =>
      'ደረሰኞችዎን ማረጋገጥ ለመቀጠል ከታች ያንቁ — '
      'በአንድ ደቂቃ ውስጥ ይጠናቀቃል።';

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
  String get howToActivate => 'እንዴት ማንቃት ይቻላል?';

  @override
  String step1Title(String monthly, String yearly) =>
      'በየወሩ በተሌብር $monthly ብር ይክፈሉ';

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
  String get verifyAndActivate => 'ያረጋግጡና ያንቁ';

  @override
  String get activationCodeTitle => 'የማንቃት ኮድ';

  @override
  String get codeBoundNote =>
      'ኮዶች ለአንድ መሣሪያ ብቻ ይሰራሉ። የደረሰኝ ማረጋገጫ ካልተሳካ፣ '
      'ከክፍያዎ ጋር ይህን የመሣሪያ ኮድ ይላኩ — ለዚህ ስልክ '
      'ተዘጋጅቶ ይላክልዎታል።';

  @override
  String get activate => 'ያንቁ';

  @override
  String activationRejection(
    ActivationRejectReason reason,
    String fallback, {
    String amount = '',
  }) =>
      switch (reason) {
        ActivationRejectReason.emptyInput =>
          'ከተሌብር ኤስኤምኤስ የደረሰኙን ቁጥር ይለጥፉ።',
        ActivationRejectReason.notTelebirr =>
          'ለMahtem Pro የሚያነቃው የተሌብር ደረሰኝ ብቻ ነው።',
        ActivationRejectReason.transactionFailed =>
          'ያ የተሌብር ግብይት አልተጠናቀቀም — ማንቃት አልተቻለም።',
        ActivationRejectReason.wrongAmount =>
          'ይህ ደረሰኝ የተላከው በተለየ መጠን ነው — ማንቃት '
              'ትክክለኛውን የእቅዱን ዋጋ ይጠይቃል (ከታች ይመልከቱ)።',
        ActivationRejectReason.wrongReceiver =>
          'ክፍያው ለመመሪያው ውስጥ ካለው የተሌብር መለያ አልተላከም። '
              'የእቅዱን ዋጋ ለዚያ መለያ መላክና አዲሱን ደረሰኝ '
              'መለጠፍ ያስፈልጋል።',
        ActivationRejectReason.receiptTooOld =>
          'ይህ ደረሰኝ በጣም የቆየ ነው። እንደገና ክፍያ አድርገው '
              'ከአዲሱ ኤስኤምኤስ ያለውን ደረሰኝ ይጠቀሙ።',
        ActivationRejectReason.alreadyUsed =>
          'ይህ የክፍያ ደረሰኝ ቀድሞ በሌላ መለያ ተጠቅሟል። አንድ ደረሰኝ '
              'ለአንድ መለያ ብቻ ይሰራል። እቅዱ ሲያልቅ አዲስ ክፍያ አድርገው '
              'ይለጥፉ።',
      };

  @override
  String get crashReportsNote =>
      'መተግበሪያው ሲበላሽ ችግሩን የሚገልጽ ስም-አልባ ሪፖርት '
      'ይላካል — ደረሰኝም ሆነ የመለያ መረጃ አያካትትም።';

  // ------------------------------------------------ error safety net (v1.12.1)

  @override
  String get somethingWentWrongScreen =>
      'ይህንን ክፍል ለማሳየት ችግር ተፈጥሯል። ተመልሰው ይሞክሩ።';

  @override
  String get reportProblemTile => 'ችግር ያሳውቁ';

  @override
  String get reportProblemTitle => 'በዚህ መሣሪያ ላይ የተመዘገቡ ችግሮች';

  @override
  String get reportProblemEmpty =>
      'እስካሁን ምንም ችግር አልተመዘገበም። መተግበሪያው ችግር ካስከተለ፣ ዝርዝሮቹ '
      'እዚህ ይታያሉ፤ እንዲያጋሯቸውም ይችላሉ።';

  @override
  String get reportProblemHint =>
      'እነዚህ ዝርዝሮች በመሣሪያዎ ውስጥ ብቻ ይቆያሉ። ችግር ሲያሳውቁ፣ ኮፒ አድርገው '
      'አብረው ይላኩ።';

  @override
  String get reportProblemCopy => 'ዝርዝሮቹን ኮፒ ያድርጉ';

  // --------------------------------------------- cloud backup (v1.13.0)

  @override
  String get cloudBackupSection => 'የደመና ምትኬ';

  @override
  String get cloudBackupTileOff => 'የደመና ምትኬ — ገና አልበራም';

  @override
  String get cloudBackupBetaNote =>
      'የማረጋገጫ ታሪክዎን በራስዎ መለያ ላይ ያስቀምጡ — ስልክዎ ቢጠፋም እንዳይጠፋ። ሁሉም ነገር '
      'በዚህ መሣሪያ ላይ መጀመሪያ ይመሰጠራል — ሰርቨሩ ሊያነበብ የማይችል መረጃ ብቻ ይይዛል፣ '
      'የይለፍ ቃልዎም መሣሪያዎን አይለቅም።';

  @override
  String get cloudBackupPasswordFieldHint => 'የመለያዎ የይለፍ ቃል';

  @override
  String get cloudBackupEnable => 'ምትኬን ያብሩ';

  @override
  String get cloudBackupWrongPassword => 'የተሳሳተ የይለፍ ቃል።';

  @override
  String get cloudBackupNetworkError =>
      'የምትኬ አገልግሎቱን ማግኘት አልተቻለም። የኢንተርኔት ግንኙነትዎን ያረጋግጡ።';

  @override
  String get cloudBackupServerError =>
      'የምትኬ አገልግሎቱ ችግር አለበት። እባክዎ ቆይተው ይሞክሩ።';

  @override
  String get cloudBackupSessionExpired =>
      'የምትኬ ክፍለ-ጊዜዎ አብቅቷል። ለመቀጠል ምትኬን እንደገና ያብሩ።';

  @override
  String get cloudBackupDecryptError =>
      'የደመና ቅጂው በዚህ የይለፍ ቃል መከፈት አልተቻለም።';

  @override
  String get cloudBackupLastNever => 'ገና አልተጠበቀም';

  @override
  String get cloudBackupLastAt => 'የመጨረሻ ምትኬ፦';

  @override
  String get cloudBackupNow => 'አሁን ምትኬ ያድርጉ';

  @override
  String get cloudBackupDone => 'ምትኬ ተጠናቋል።';

  @override
  String get cloudBackupRestore => 'ከደመና ይመልሱ';

  @override
  String cloudBackupRestored(int n) => n == 1
      ? '1 አዲስ ፍተሻ ከደመናው ተመልሷል።'
      : '$n አዲስ ፍተሻዎች ከደመናው ተመልሰዋል።';

  @override
  String get cloudBackupNothingToRestore =>
      'የደመና ምትኬው ባዶ ነው — የሚመለስ ነገር የለም።';

  @override
  String get cloudBackupTurnOff => 'ምትኬን ያጥፉ';

  @override
  String get cloudBackupTurnedOff =>
      'ምትኬ ጠፍቷል። በደመና ላይ የነበረው ቅጂዎ ተሰርዟል።';

  @override
  String cloudBackupEntryCount(int n) => n == 1
      ? '1 ፍተሻ ተጠብቋል'
      : '$n ፍተሻዎች ተጠብቀዋል';

  @override
  String get cloudAutoBackupTitle => 'ራስ-ሰር ምትኬ';

  @override
  String get cloudAutoBackupSubtitle =>
      'ከእያንዳንዱ ማረጋገጫ በኋላ በራስ-ሰር ያመሳስራል።';

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
  String get undo => 'ተመልስ';

  @override
  String get emptyCta => 'የመጀመሪያዎን ደረሰኝ ያረጋግጡ';

  @override
  String get exportTooltip => 'ታሪክ አጋራ';

  @override
  String get cbeNeedsCodeTitle => 'ሲቢኤ የደረሰኝ ኮድ ያስፈልገዋል';

  @override
  String get cbeNeedsCodeBody =>
      'በደረሰኙ ላይ የሚታየው የFT ቁጥር የሲቢኤ ውስጣዊ ቁጥር ነው — ባንኩ የሚያረጋግጠው ከተሰራጨው '
      'የደረሰኝ ሊንክ ወይም ከQR ውስጥ ያለውን ኮድ ብቻ ነው። እባክዎ ሊንኩን ይለጥፉ ወይም በሲቢኤ '
      'መተግበሪያው ውስጥ የሚታየውን QR ይስካኑ።';

  @override
  String failureBlockedMessage() =>
      'የሲንቄ ባንክ ደረሰኝ አገልግሎት ከዚህ ኔትወርክ የሚመጡ አውቶማቲክ ፍተሻዎችን ለጊዜው እየከለከለ ነው።';

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
  String get batchTitle => 'ብዙ ደረሰኞችን ማረጋገጥ';

  @override
  String get batchIntro =>
      'ብዙ የደረሰኝ ሊንኮችን ወይም ቁጥሮችን ይለጥፉ — በእያንዳንዱ መስመር አንድ — ሁሉንም '
      'ይረጋግጡ። ለዕለታዊ የገበያ ሂሳብ ማስተካከያ የተዘጋጀ ነው።';

  @override
  String get batchInputHint =>
      'አንድ የደረሰኝ ሊንክ ወይም ቁጥር በአንድ መስመር…\n'
      'https://mbreciept.cbe.com.et/…\n'
      'CHQ261Z4AB2C\n'
      'FT26140P01YB';

  @override
  String get batchBankLabel => 'ለሊንክ ያልሆኑ የማጣቀሻ ቁጥሮች ባንክ';

  @override
  String batchStart(int count) => count == 1
      ? '1 ደረሰኝ ይረጋግጡ'
      : '$count ደረሰኞችን ይረጋግጡ';

  @override
  String batchNeedMore(int have, int need) =>
      'ይህን ቡድን ለማጠናቀቅ $need ማረጋገጫዎች ያስፈልጋሉ — $have ብቻ ቀርተዋል። '
      'ለመቀጠል ወደ Pro ያሻሽሉ።';

  @override
  String batchNeedsPhone(String bank) =>
      'ብዙ ደረሰኞችን የ$bank ማረጋገጥ አይቻልም፦ እያንዳንዱ ደረሰኝ የራሱ የመላኪያ ስልክ ቁጥር '
      'ይፈልጋል።';

  @override
  String batchNeedsBank(int count) => count == 1
      ? 'መጀመሪያ ለሊንክ ላልሆነው የማጣቀሻ ቁጥር ባንኩን ይምረጡ'
      : 'መጀመሪያ ለ$count ሊንክ ላልሆኑ የማጣቀሻ ቁጥሮች ባንኩን ይምረጡ';

  @override
  String batchDuplicates(int count) =>
      count == 1
          ? '1 ተደጋጋሚ መስመር ተዘልሏል'
          : '$count ተደጋጋሚ መስመሮች ተዘለሉ';

  @override
  String batchProgress(int done, int total) =>
      'በማረጋገጥ ላይ… $done ከ$total';

  @override
  String batchDoneCounts(int verified, int failed) =>
      '✓ $verified ተረጋግጠዋል · ✗ $failed አልተረጋገጡም';

  @override
  String batchRemaining(int count) => count == 1
      ? 'ቀሪውን 1 ደረሰኝ ይረጋግጡ'
      : 'ቀሪዎቹን $count ደረሰኞች ይረጋግጡ';

  @override
  String get batchShareTooltip => 'ውጤቶችን አጋራ';

  @override
  String get batchEmpty =>
      'እስካሁን ምንም የሚረጋገጥ የለም — ከላይ ቁጥሮችን ይለጥፉ ወይም ይጻፉ።';

  @override
  String get batchSkipDuplicate => 'በዚህ ቡድን ውስጥ የተደገመ';

  @override
  String get batchSkipCbe => 'የሲቢኤ የታተመ ቁጥር — የደረሰኝ ኮድ ያስፈልገዋል';

  @override
  String get batchSkipUnknown => 'ሊንኩ አልታወቀም';

  @override
  String get batchSkipOverLimit => 'የ50 መስመር ገደብን አልፏል።';
}
