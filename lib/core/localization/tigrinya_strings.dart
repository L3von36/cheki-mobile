part of 'app_strings.dart';

/// Tigrinya (ትግርኛ) catalog — polite plural forms throughout, matching
/// the register of the Amharic catalog. Phrasing is idiomatic Tigrinya
/// the way people actually say it (standard Tigrinya terms like መሕለፊ
/// ቃል, ክፍሊት, ዕለት, ምርግጋጽ and natural loanwords where the borrowed
/// word IS the word — ሊንክ, ኮፒ, ስካን, ካሜራ, ሪፈረንስ, ኣፕሊኬሽን, QR, SMS,
/// Telebirr) — never a stiff word-for-word rendering of the English.
final class TigrinyaStrings extends AppStrings {
  const TigrinyaStrings();

  @override
  AppLocale get locale => AppLocale.tigrinya;

  // ---------------------------------------------------------------- shell

  @override
  String get verifyTab => 'ምርግጋጽ';

  @override
  String historyTab(int count) => count > 0 ? 'ታሪኽ ($count)' : 'ታሪኽ';

  // ---------------------------------------------------------------- home

  @override
  String get referenceLabel => 'ቁጽሪ ሰርተፊኬት ወይ ሊንክ';

  @override
  String get referenceHint => 'ሊንክ ሰርተፊኬት ኣቐምጡ ወይ ቁጽሪኡ ጽሓፉ';

  @override
  String get pickBankHint =>
      'እቲ ሰርተፊኬት ካብ ዝወጣሉ ባንክ ወይ ዋሌት ተምረጹ — '
      'ብሊንክ ወይ ብስካን QR እቲ ባንክ ብውሱን ይፍለጥ።';

  @override
  String get phoneOnWallet => 'ቁጽሪ ተሌፎን ናይቲ ዋሌት';

  @override
  String lastDigitsOnly(int digits) => 'ንመወዳእታ $digits ቁጽርታት ጥራይ';

  @override
  String get clipboardEmpty => 'ኮፒ ዝተገበረ ነገር የሎን።';

  @override
  String get verifyReceiptButton => 'ሰርተፊኬት ኣረጋግጹ';

  @override
  String get stopVerifying => 'ምርግጋጽ ኣቐርጹ';

  @override
  String get autoDetectBank => 'እቲ ባንክ ብውሱን ይፍለጥ';

  @override
  String detected(String bankName) => 'ተረኺቡ: $bankName';

  @override
  String get pasteTooltip => 'ኣቐምጡ';

  @override
  String get scanQrInstead => 'እቲ QR ኮድ ስካኑ';

  @override
  String freeChecksLeft(int count) => '$count ናጻ ተሪ';

  @override
  String get upgrade => 'Pro ክፉቱ';

  @override
  String proDaysLeft(int days) => 'PRO · $days መዓልታት';

  // ---------------------------------------------------------------- auth

  @override
  String get welcomeBack => 'ብደሓን ተመሊስኩም';

  @override
  String get signInSubtitle => 'ሰርተፊኬታትኩም ምርግጋጽ ንምቕጻል ኣቱዎ';

  @override
  String get createAccountTitle => 'ሕሳብኩም ክፉቱ';

  @override
  String get createAccountSubtitle =>
      'ኣብ ውሽጢ ክልተ ደቂቃ ይፍጠር — ንእዚ ተሌፎን እዚ ጥራይ።';

  @override
  String get fullName => 'ምሉእ ሽም';

  @override
  String get fullNameHint => 'ለምሳሌ፦ ኣበበ ከበደ';

  @override
  String get identifierLabel => 'ቁጽሪ ተሌፎን ወይ ኢመይል';

  @override
  String get identifierHint => '09xxxxxxxx ወይ you@mail.com';

  @override
  String get passwordLabel => 'መሕለፊ ቃል';

  @override
  String get passwordHint => '6 ፊደላት ወይ ንዕሊ';

  @override
  String get confirmPasswordLabel => 'መሕለፊ ቃል ኣረጋግጹ';

  @override
  String get signInButton => 'ኣቱዎ';

  @override
  String get signInLink => 'ኣቱዎ';

  @override
  String get createAccountButton => 'ሕሳብ ክፉቱ';

  @override
  String get createAccountLink => 'ሕሳብ ክፉቱ';

  @override
  String get noAccountPrompt => 'ሕሳብ የብልኩምን ዶ?';

  @override
  String get haveAccountPrompt => 'ሕሳብ ኣለኩም ዶ?';

  @override
  String get forgotPassword => 'መሕለፊ ቃል ረሲእኩም ዶ?';

  @override
  String get resetAccountsTitle => 'ሕሳባት ዳግም ጅምሩ?';

  @override
  String get resetAccountsBody =>
      'ኩሉ ሕሳባት እዚ ተሌፎን እዚ ዝርከቡ ይሰርዙ፤ ድሕሪኡ ድማ '
      'ሓድሽ ሕሳብ ክፍቱ። ታሪኽ ምርግጋጽኩምን እቲ Pro መደብኩምን '
      'ከም ዘለው ይቕጽሉ።';

  @override
  String get resetAccountsConfirm => 'ጅምሩ';

  @override
  String get cancel => 'ሰርዝ';

  @override
  String get ok => 'ሕርያን';

  @override
  String get showPassword => 'መሕለፊ ቃል ኣርእዩ';

  @override
  String get hidePassword => 'መሕለፊ ቃል ደብቁ';

  @override
  String get signingIn => 'ይኣቱ ኣሎ…';

  @override
  String get creatingAccount => 'ሕሳብ ይኽፈል ኣሎ…';

  @override
  String get authPrivacyNote =>
      'ሕሳብኩም ኣብዚ ተሌፎን እዚ ጥራይ ይቐመጥ — ናብ ወጻኢ '
      'ኣይሓድግን። ታሪኽ ምርግጋጽኩም ውልቃዊ ክኾን ይቕጽል።';

  @override
  String errorAuth(AuthError error) => switch (error) {
    AuthError.invalidName =>
      'ምሉእ ሽምኩም ጽሓፉ (2 ፊደላት ወይ ንዕሊ)።',
    AuthError.invalidIdentifier =>
      'ቅኑዕ ቁጽሪ ተሌፎን ኢትዮጵያ (09xxxxxxxx) ወይ ኢመይል '
          'ኣእቱ።',
    AuthError.invalidEmail => 'እቲ ኢመይል ቅኑዕ ኣይምስዓብን።',
    AuthError.invalidPassword =>
      'መሕለፊ ቃል 6 ፊደላት ወይ ንዕሊ ክኾን ኣለዎ።',
    AuthError.passwordMismatch =>
      'እቲ ክልተ መሕለፊ ቃላት ኣይተዋሓቡን።',
    AuthError.alreadyExists =>
      'ብእዚ ቁጽሪ ተሌፎን/ኢመይል ሕሳብ ቅድሚ ዘሎ — በዝሕቲ '
          'ኣቱዎ።',
    AuthError.accountNotFound =>
      'ብእዚ ቁጽሪ ተሌፎን/ኢመይል ሕሳብ ኣይተረኽበን — ቅድሚ '
          'ሕሳብ ክፉቱ።',
    AuthError.wrongPassword =>
      'እቲ መሕለፊ ቃል ጌጋ እዩ። ደጊምኩም ፈትሹ።',
    AuthError.storageFailed =>
      'ሕሳብ ምዕቃብ ኣይተኻእለን። ደጊምኩም ፈትሹ።',
  };

  @override
  String get genericAuthError =>
      'ጸገም ወጺኡ ኣሎ። በዝሕቲ ደጊምኩም ፈትሹ።';

  // ---------------------------------------------------------------- settings

  @override
  String get settingsTitle => 'ቅጥዕታት';

  @override
  String get accountSection => 'ሕሳብ';

  @override
  String get signedInAs => 'እቲ ኣተኩምዎ ሕሳብ';

  @override
  String get appearanceSection => 'ገጽታ';

  @override
  String get themeSystem => 'ስርዓት';

  @override
  String get themeLight => 'ብርሃን';

  @override
  String get themeDark => 'ጽልማት';

  @override
  String get languageSection => 'ቋንቋ';

  @override
  String get signOut => 'ውጻኡ';

  @override
  String get signOutConfirmTitle => 'ክትውጻኡ ትደልዩ ዶ?';

  @override
  String get signOutConfirmBody =>
      'ደጊምኩም ክትኣቱ መሕለፊ ቃልኩም ክትጥቀሙሉ እዩ — '
      'ሕሳብኩም ኣብዚ ተሌፎን እዚ ክኾን ይቕጽል።';

  @override
  String get versionLabel => 'ስሪት';

  @override
  String get deviceCodeLabel => 'ኮድ ተሌፎን';

  @override
  String get copiedToClipboard => 'ኮፒ ተገቢሩ።';

  @override
  String get close => 'ዕጉቡ';

  @override
  String get loading => 'ይጽዓን ኣሎ…';

  // ---------------------------------------------------------------- scan

  @override
  String get scanTitle => 'ክፍሊት ስካኑ';

  @override
  String get scanPositionHint => 'እቲ QR ኮድ ኣብ ውሽጢ እቲ ፍሬም ኣቐምጡ';

  @override
  String get scanUsageHint =>
      'ኣብ ሰርተፊኬት ዝተሓተመ QR ጥራይ ተጠቀሙ — '
      'QR ናይ ክፍሊት መልእኽቲ ወይ መቐበሊ ኣይኮነን';

  @override
  String get scanFlash => 'ብርሃን';

  @override
  String get scanGallery => 'ጋለሪ';

  @override
  String get scanNoQrFound => 'ኣብቲ ስእሊ ሰርተፊኬት QR ኣይተረኽበን።';

  @override
  String get scanImageUnreadable => 'እቲ ስእሊ ክንብቦ ኣይኽእልን።';

  @override
  String scanCameraError(String code) =>
      'እቲ ካሜራ ኣይተከፈተን ($code)። ዕጉቡዎ ደጊምኩም '
      'ፈትሹ።';

  @override
  String get scanRetry => 'ደጊምኩም ፈትሹ';

  @override
  String get scanCameraPermissionNeeded =>
      'QR ሰርተፊኬት ንምስካን ፈቃድ ካሜራ ይደሊ።';

  @override
  String get scanGrantPermission => 'ፈቃድ ሃቡ';

  @override
  String get scanCameraOff =>
      'ንMahtem እቲ ካሜራ ጠፊኡ ኣሎ። ካብ ቅጥዕታት ስርዓት '
      'ክፉቱዎ፣ ወይ ድማ ሊንክ ሰርተፊኬት ኣቐምጡ።';

  @override
  String get scanOpenSettings => 'ቅጥዕታት ክፉቱ';

  @override
  String get scanCameraUnavailable => 'ካሜራ ኣይተረኽበን';

  @override
  String get scanTypeAction => 'ቁጽሪ ጽሓፉ';

  @override
  String get typeSheetTitle => 'ቁጽሪ ክፍሊት ወይ ሪፈረንስ ጽሓፉ';

  @override
  String get typeSheetHint =>
      'ለምሳሌ FT2614G2P01YB — ወይ ሊንክ ሰርተፊኬት ኣቐምጡ';

  @override
  String get typeSheetRecent => 'ናይ ቅሩብ እዋን ፍተሻታት';

  // ---------------------------------------------------------------- result

  @override
  String get resultTitle => 'ውጽኢት ምርግጋጽ';

  @override
  String get resultNothingToShow => 'ንምርኢት ሰርተፊኬት የሎን።';

  @override
  String get resultVerifiedTitle => 'እቲ ክፍሊት ተረጋገጸ!';

  @override
  String get resultFailedTitle => 'ምርግጋጽ ኣይሰኣነን';

  @override
  String get resultVerifiedBody =>
      'እዚ ክፍሊት ሓቀኛ እዩ — ብባንኩ ተረጋገጸ።';

  @override
  String get resultFailedBody => 'እዚ ሰርተፊኬት ምርግጋጽ ኣይተኻእለን።';

  @override
  String get resultDone => 'ተውዳእ';

  @override
  String get resultShare => 'ኣካፍሉ';

  @override
  String get resultTryAgain => 'ደጊምኩም ፈትሹ';

  @override
  String get senderLabel => 'መልኣኺ';

  @override
  String get senderAccountLabel => 'ሕሳብ መልኣኺ';

  @override
  String get receiverLabel => 'ተቐባይ';

  @override
  String get receiverAccountLabel => 'ሕሳብ ተቐባይ';

  @override
  String get dateLabel => 'ዕለት';

  @override
  String get referenceShortLabel => 'ሪፈረንስ';

  @override
  String get reasonLabel => 'ምኽንያት';

  @override
  String get statusLabel => 'ኹነት';

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
      ..writeln('ክፍሊት ብMahtem ተረጋገጸ')
      ..writeln('ባንክ: $bankName')
      ..writeln('ሪፈረንስ: $reference')
      ..writeln('መጠን: $amount')
      ..writeln('መልኣኺ: $sender')
      ..writeln('ተቐባይ: $receiver')
      ..write('ዕለት: $date');
    return buffer.toString();
  }

  // ------------------------------------------------------- verify failures

  @override
  String failureMessage(VerifyErrorKind kind, String fallback) =>
      switch (kind) {
        VerifyErrorKind.network =>
          'እቲ ኣገልግሎት ምርካብ ኣይተኻእለን። ኣብ ኢንተርኔት '
              'ምኾኑኩም ኣረጋግጹ።',
        VerifyErrorKind.notFound =>
          'ብእዚ ቁጽሪ ሰርተፊኬት ኣይተረኽበን።',
        VerifyErrorKind.badInput =>
          'ቅኑዕ ቁጽሪ ሰርተፊኬት ወይ ሊንክ ኣእቱ።',
        VerifyErrorKind.unreadable =>
          'እቲ QR ሰርተፊኬት ክንብቦ ኣይኽእልን — ደጊምኩም '
              'ፈትሹ።',
        VerifyErrorKind.unsupported =>
          'እዚ ባንክ ወይ ዓይነት ሰርተፊኬት ክሳብ ሕጂ '
              'ኣይድገፍን።',
      };

  @override
  List<String> failureTips(VerifyErrorKind kind, List<String> fallback) =>
      switch (kind) {
        VerifyErrorKind.network => const [
          'ዳታ ሞባይል ወይ Wi-Fi ብሩሕ ምኺድኩም ኣረጋግጹ።',
          'እቲ ኣገልግሎት ንግዜያዊ ክኾን ይኽእል — ገለ ግዜ '
              'ተጸበቑ ደጊምኩም ፈትሹ።',
        ],
        VerifyErrorKind.notFound => const [
          'እቲ ቁጽሪ ብዘይ ምስራዝ ከም ዝኣተ ደጊምኩም '
              'ኣረጋግጹ።',
          'ሊንክ ኣቐምጡ እንተወሲድኩም ምሉእ ምኾኑ '
              'ኣረጋግጹ።',
        ],
        VerifyErrorKind.badInput => const [
          'እቲ ሊንክ ከም ዝተላኣኽልኩም ብቕኑዕ ኣቐምጡ።',
        ],
        VerifyErrorKind.unreadable => const [
          'እቲ ምሉእ QR ብብርሃን ኣብ ውሽጢ እቲ ፍሬም '
              'ኣቐምጡ።',
          'ካብ ኤስኤምኤስ እቲ ቁጽሪ ሰርተፊኬት ብኢድኩም '
              'ኣቐምጡ።',
        ],
        VerifyErrorKind.unsupported => const [
          'እቲ ኣፕሊኬሽን ዝድግፎም ባንኻት ኣብ ቅድሚቲ '
              'ገጽ ርኣዩ።',
        ],
      };

  // ---------------------------------------------------------------- history

  @override
  String get historyTitle => 'ታሪኽ';

  @override
  String get clearHistoryTooltip => 'ታሪኽ ኣጥፍኡ';

  @override
  String get clearHistoryTitle => 'ታሪኽ ክጥፋእ ዶ?';

  @override
  String get clearHistoryBody =>
      'ኩሉ ዝተዕቀበ ምርግጋጽ ካብዚ ተሌፎን እዚ ይጥፋእ።';

  @override
  String get clearButton => 'ኣጥፍኡ';

  @override
  String get noChecksTitle => 'ክሳብ ሕጂ ምርግጋጽ የሎን';

  @override
  String get noChecksBody => 'ዝተረጋገጸ ሰርተፊኬታት ኣብዚ ይርኣዩ።';

  @override
  String get verifiedPaymentLabel => 'ክፍሊት ተረጋገጸ';

  @override
  String get notVerifiedLabel => 'ኣይተረጋገጸን';

  @override
  String get checkedLabel => 'ተፈትሸ';

  @override
  String get noteLabel => 'ሓበሬታ';

  @override
  String get historySearchTooltip => 'ኣብ ታሪኽ ሕፉስ';

  @override
  String get historySearchHint => 'ብቁጽሪ፣ ብስም ወይ ብባንክ ሕፉስ';

  @override
  String get filterAll => 'ኩሉ';

  @override
  String get filterVerified => 'ተረጋገጸ';

  @override
  String get filterFailed => 'ኣይተረጋገጸን';

  @override
  String get noMatchesTitle => 'ዝተረኸበ የሎን';

  @override
  String get noMatchesBody =>
      'ምስ ሕፉስኩም ወይ ምስ ምርጫኹም ዝስማዓ ምርግጋጽ የሎን።';

  @override
  String get verifyAgain => 'ደጊምኩም ኣረጋግጹ';

  @override
  String get prefilledToast =>
      'ሓበሬታታት ተመሊኡ — ፈትሹን ኣረጋግጡን።';

  // ---------------------------------------------------------------- paywall

  @override
  String get paywallTitle => 'Mahtem Pro';

  @override
  String get pasteReceiptFromSms =>
      'ካብ ኤስኤምኤስ Telebirr እቲ ቁጽሪ ሰርተፊኬት ኣቐምጡ።';

  @override
  String get pasteActivationCode =>
      'እቲ ንኩም ዝተላኣኽ ኮድ ኣክቲቬሽን ኣቐምጡ።';

  @override
  String get codeBadFormat =>
      'እዚ ኮድ ኣክቲቬሽን Mahtem ኣይምስዓብን።';

  @override
  String get codeBadSignature =>
      'እዚ ኮድ ቅኑዕ ኣይኮነን — ንዓቲ መልኣኺኡ ደጊምኡ '
      'ክልኣኾልኩም ይንገሩ።';

  @override
  String get codeWrongDevice =>
      'እዚ ኮድ ንካልእ ተሌፎን ተዳልዩ እዩ። ምስ ክፍሊትኩም '
      'ኣብ ታሕቲ ዝርአ ኮድ ተሌፎን ለኣኽዎ።';

  @override
  String codeExpired(String date) =>
      'እዚ ኮድ ኣብ $date ወዲኡ ኣሎ። ንምቕጻል ሓድሽ '
      'ግዝኡ።';

  @override
  String get codeNotAccepted => 'እዚ ኮድ ክትቐበሎ ኣይተኻእለን።';

  @override
  String proActivatedToast(String date) =>
      'Mahtem Pro ክሳብ $date ንቁ እዩ 🎉';

  @override
  String get clipboardEmptyForPaste =>
      'ኮፒ ዝተገበረ ነገር የሎን — ቅድሚ ሕጂ እቲ ቁጽሪ '
      'ኮፒ ግበሩ።';

  @override
  String telebirrNumberCopied(String number) =>
      'እቲ ቁጽሪ Telebirr $number ኮፒ ተገቢሩ — ኣብ '
      'ውሽጢ ኣፕሊኬሽን Telebirr ኣቐምጡዎ።';

  @override
  String amountCopied(String amount) => '$amount ብር ኮፒ ተገቢሩ።';

  @override
  String get stackingNote =>
      'ሓደ ሰርተፊኬት ኣብዚ ተሌፎን እዚ ሓደ መደብ '
      'ይከፉት። ንምቕጻል ደጊምኩም ክፍሊት ገብሩ እቲ '
      'ሓድሽ ቁጽሪ ሰርተፊኬት ኣቐምጡ — እቶም ዝተከፍሉ '
      'መዓልታት ይተውሰኹ።';

  @override
  String get hideActivationCode => 'ኮድ ኣክቲቬሽን ደብቁ';

  @override
  String get haveActivationCode => 'ኮድ ኣክቲቬሽን ኣለኩም ዶ?';

  @override
  String get deviceCodeCopied => 'ኮድ ተሌፎን ኮፒ ተገቢሩ።';

  @override
  String get proActiveTitle => 'Mahtem Pro ንቁ እዩ';

  @override
  String proUnlimitedUntil(String date) =>
      'ክሳብ $date ብዘይ ውሱን ምርግጋጽ።';

  @override
  String trialsLeftTitle(int count) => count == 1
      ? 'ሓደ ናጻ ምርግጋጽ ተሪ ኣሎ።'
      : '$count ናጻ ምርግጋጽ ተሪ ኣሎው።';

  @override
  String get trialsLeftBody =>
      'ድሕሪ ምውዳእ ካብ ታሕቲ Mahtem Pro ክፉቱ — '
      'ታሪኽኩምን ቅጥዕታትኩምን ከም ዘለው ይቕጽሉ።';

  @override
  String get trialsGoneTitle => 'ናጻ ምርግጋጽ ወዲኡ';

  @override
  String get trialsGoneBody =>
      'ሰርተፊኬታትኩም ንምርግጋጽ ካብ ታሕቲ ክፉቱ — '
      'ብሓደ ደቂቃ ይውዳእ።';

  @override
  String get pricePerMonth => 'ብር / ወርሒ';

  @override
  String get priceUnlimitedBody =>
      'ኣብ ኩሉ ባንክን ዋሌትን ብዘይ ውሱን ምርግጋጽ '
      'ሰርተፊኬት — CBE፣ Telebirr፣ BOA፣ M-Pesa ከምኡ '
      'ውን ካልኦት።';

  @override
  String priceYearlyOnce(String price) =>
      'ወይ ድማ ንሓንሳብታ ዓመት ብሓደ ግዜ $price ብር '
      'ክፈሉ።';

  @override
  String get howToActivate => 'ከመይ ይከፈት';

  @override
  String step1Title(String monthly, String yearly) =>
      'ብTelebirr $monthly ብር (ወይ ብዓመት $yearly ብር) '
      'ክፈሉ';

  @override
  String get step1Body =>
      'እቲ ቅኑዕ መጠን ናብዚ Telebirr ሕሳብ ለኣኽዎ፦';

  @override
  String copyAmountChip(String amount) => 'እቲ መጠን ኮፒ ግበሩ — $amount ብር';

  @override
  String get step2Title => 'እቲ ቁጽሪ ሰርተፊኬት ካብ ታሕቲ ኣቐምጡ';

  @override
  String step2Body(String monthly) =>
      'Telebirr ምስ ቁጽሪ ሰርተፊኬት ኤስኤምኤስ ምርግጋጽ ይለኣኽ '
      '(ለምሳሌ CHQ261Z4AB2C) — ኣብዚ ኣቐምጡዎ፤ እቲ '
      'ኣፕሊኬሽን ምስ Telebirr ብውሱኑ ይረጋግጦ። እቲ ክፍሊት '
      'ሓቀኛ $monthly ብር እንተኾይኑ፣ Mahtem Pro ብዘይ '
      'መዘይ ይከፈት።';

  @override
  String get telebirrReceiptNumber => 'ቁጽሪ ሰርተፊኬት Telebirr';

  @override
  String get receiptNumberHint => 'ለምሳሌ CHQ261Z4AB2C';

  @override
  String get checkingWithTelebirr => 'ምስ Telebirr ይረጋግጥ ኣሎ…';

  @override
  String get verifyAndActivate => 'ኣረጋግጹን ክፉቱን';

  @override
  String get activationCodeTitle => 'ኮድ ኣክቲቬሽን';

  @override
  String get codeBoundNote =>
      'ኮዳት ንሓደ ተሌፎን ጥራይ ይሰርሑ። ምርግጋጽ '
      'ሰርተፊኬት እንተሳዕረ፣ ምስ ክፍሊትኩም እዚ ኮድ '
      'ተሌፎን ለኣኽዎ — ንእዚ ተሌፎን ተዳልዩ '
      'ክርከብልኩም እዩ።';

  @override
  String get activate => 'ክፉቱ';

  @override
  String activationRejection(
    ActivationRejectReason reason,
    String fallback, {
    String amount = '',
  }) =>
      switch (reason) {
        ActivationRejectReason.emptyInput =>
          'ካብ ኤስኤምኤስ Telebirr እቲ ቁጽሪ ሰርተፊኬት '
              'ኣቐምጡ።',
        ActivationRejectReason.notTelebirr =>
          'እቲ ዝከፍቶ Mahtem Pro ሰርተፊኬት Telebirr '
              'ጥራይ እዩ።',
        ActivationRejectReason.transactionFailed =>
          'እቲ ግብሪ Telebirr ኣይውዳእን — ምርግጋጽ '
              'ኣይተኻእለን።',
        ActivationRejectReason.wrongAmount =>
          'እዚ ሰርተፊኬት ብካልእ መጠን እዩ ዝተላኣኽ — '
              'ምርግጋጽ እቲ ቅኑዕ ዋጋ መደብ ይጠልብ '
              '(ካብ ታሕቲ ርኣዩ)።',
        ActivationRejectReason.wrongReceiver =>
          'እቲ ክፍሊት ናብቲ ኣብ መምርሒ ዝርከብ ሕሳብ '
              'Telebirr ኣይተላኣኽን። እቲ ዋጋ መደብ ናብቲ '
              'ሕሳብ ምልኣኽን እቲ ሓድሽ ሰርተፊኬት ምእታይን '
              'ይደሊ።',
        ActivationRejectReason.receiptTooOld =>
          'እዚ ሰርተፊኬት በዝሑ ጥንታዊ እዩ። ደጊምኩም '
          'ክፍሊት ገብሩ ካብ ሓድሽ ኤስኤምኤስ እቲ '
          'ሰርተፊኬት ተጠቐሙ።',
        ActivationRejectReason.alreadyUsed =>
          'እዚ ሰርተፊኬት ቅድሚ እዋን ኣብዚ ተሌፎን እዚ '
          'ተጠቂሙ ኣሎ። እቲ መደብ እንተወዲኡ ደጊምኩም '
          'ክፍሊት ገብሩ እቲ ሓድሽ ሰርተፊኬት ኣቐምጡ።',
      };

  @override
  String get crashReportsNote =>
      'እቲ ኣፕሊኬሽን ምስ ዝወድቕ፣ ብዘይ ስም ሪፖርት ይለኣኽ — '
      'ሰርተፊኬትኩም ወይ መረዳዕታኩም ኣብ ውሽጡ '
      'የብሉን፤ ንምቕሓስ ጥራይ እዩ።';

  // ------------------------------------------------- history upgrade (v1.9.0)

  @override
  String get statsChecks => 'ፍተሻታት';

  @override
  String get statsVerified => 'ዝተረጋገጸ';

  @override
  String get statsTotal => 'ጠቕላላ';

  @override
  String get groupToday => 'ሎሚ';

  @override
  String get groupYesterday => 'ትማሊ';

  @override
  String get groupThisWeek => 'ኣብዚ ሰሙን';

  @override
  String get groupEarlier => 'ቅድሚ';

  @override
  String get removedToast => 'ካብ ታሪኽ ተወጊዱ።';

  @override
  String get undo => 'መልሲ';

  @override
  String get emptyCta => 'እቲ ቀዳማይ ሰርተፊኬትኩም ኣረጋግጹ';

  @override
  String get exportTooltip => 'ታሪኽ ኣካፍሉ';
}
