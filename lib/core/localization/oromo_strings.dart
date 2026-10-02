part of 'app_strings.dart';

/// Afaan Oromoo catalog — polite plural imperatives throughout, matching
/// the register of the Amharic catalog. Phrasing is the Afaan Oromoo
/// people actually use on phones: standard Oromo terms where they are
/// the everyday word (kaffaltii, bay'ina, bilbilaa, mirkaneessaa,
/// herrega, jecha icciitii) and natural Qubee loanwords where the
/// borrowed word IS the word (iskaanii, liinkii, kopii, QR, SMS,
/// Telebirr) — never a stiff word-for-word rendering of the English.
final class OromoStrings extends AppStrings {
  const OromoStrings();

  @override
  AppLocale get locale => AppLocale.oromo;

  // ---------------------------------------------------------------- shell

  @override
  String get verifyTab => 'Mirkaneessa';

  @override
  String historyTab(int count) => count > 0 ? 'Seenaa ($count)' : 'Seenaa';

  // ---------------------------------------------------------------- home

  @override
  String get referenceLabel => 'Lakkoofsa referensii ykn liinkii risiitii';

  @override
  String get referenceHint =>
      'Liinkii risiitii dabalaa ykn lakkoofsicha barreessaa';

  @override
  String get pickBankHint =>
      'Baankii ykn waaleetii risiitiin sun isii irraa bahu filadhaa — '
      'liinkiin fi iskaaniin QR baankii ofumaan ni beeksisu.';

  @override
  String get phoneOnWallet => 'Lakkoofsa bilbilaa waaleetii irratti jiru';

  @override
  String lastDigitsOnly(int digits) => 'Lakkoofsota dhuma $digits qofa';

  @override
  String get clipboardEmpty => 'Kopii ta\u2019e hin jiru.';

  @override
  String get verifyReceiptButton => 'Risiitii mirkaneessaa';

  @override
  String get stopVerifying => 'Mirkaneessuu dhaabaa';

  @override
  String get autoDetectBank => 'Baankiin ofumaan beekama';

  @override
  String detected(String bankName) => 'Argameera: $bankName';

  @override
  String get pasteTooltip => 'Dabi';

  @override
  String get scanQrInstead => 'Koodii QR iskaanii godhaa';

  @override
  String freeChecksLeft(int count) => '$count bilisaa hafa';

  @override
  String get upgrade => 'Miseensa ta\u2019aa';

  @override
  String proDaysLeft(int days) => 'PRO · $days guyyaa';

  // ---------------------------------------------------------------- auth

  @override
  String get welcomeBack => "Baga nagaan deebi'tan";

  @override
  String get signInSubtitle =>
      'Risiitiiwwan mirkaneessuu itti fufuuf galmaa\u2019aa';

  @override
  String get createAccountTitle => 'Herrega keessan uumaa';

  @override
  String get createAccountSubtitle =>
      'Herrega tokko meeshaa kanaafuu — sekoondii muraasa fudhata.';

  @override
  String get fullName => 'Maqaa guutuu';

  @override
  String get fullNameHint => 'Fkn. Abebe Kebede';

  @override
  String get identifierLabel => 'Lakkoofsa bilbilaa ykn imiyeelii';

  @override
  String get identifierHint => '09xxxxxxxx ykn you@mail.com';

  @override
  String get passwordLabel => 'Jecha icciitii';

  @override
  String get passwordHint => 'Qubee 6 ykn caalaa';

  @override
  String get confirmPasswordLabel => 'Jecha icciitii mirkaneessaa';

  @override
  String get signInButton => "Galmaa'aa";

  @override
  String get signInLink => "Galmaa'aa";

  @override
  String get createAccountButton => 'Herrega uumaa';

  @override
  String get createAccountLink => 'Herrega uumaa';

  @override
  String get noAccountPrompt => 'Herrega hin qabdanuu?';

  @override
  String get haveAccountPrompt => 'Duraan herrega qabdanuu?';

  @override
  String get forgotPassword => 'Jecha icciitii dagattanii bittuu?';

  @override
  String get resetAccountsTitle => 'Herregoota haaraa jalqabuu?';

  @override
  String get resetAccountsBody =>
      'Herregoota meeshaa kana irratti jiran hundi ni haqamu; '
      'ittiinsaanu herrega haaraa uumatta. Seenaa mirkaneessaa fi '
      'karoora Pro keessan hin tuqamu.';

  @override
  String get resetAccountsConfirm => 'Jalqabaa';

  @override
  String get cancel => 'Dhisaa';

  @override
  String get ok => 'Eeyyee';

  @override
  String get showPassword => 'Jecha icciitii agarsiisaa';

  @override
  String get hidePassword => 'Jecha icciitii dhoksaa';

  @override
  String get signingIn => "Galmaa'aa jira\u2026";

  @override
  String get creatingAccount => 'Herrega uumaa jira\u2026';

  @override
  String get authPrivacyNote =>
      "Herregoonni meeshaa kana irratti qofa jiraatu — iccitii ta'ee "
      'bakka kamiyyuu hin eramamu. Seenaa mirkaneessaa keessas akkasuma '
      'iccitiidhaan eegama.';

  @override
  String errorAuth(AuthError error) => switch (error) {
    AuthError.invalidName =>
      'Maqaa guutuu keessan galchaa (qubee 2 ykn caalaa).',
    AuthError.invalidIdentifier =>
      'Lakkoofsa bilbilaa Itoophiyaa sirrii ta\u2019e (09xxxxxxxx) ykn '
          'imiyeelii galchaa.',
    AuthError.invalidEmail => 'Teessoon imiyeelii sun sirrii hin fakkaattu.',
    AuthError.invalidPassword =>
      'Jechi icciitii qubee 6 ykn caalaa ta\u2019uu qaba.',
    AuthError.passwordMismatch => 'Jechi icciitii lamaan wal hin simu.',
    AuthError.alreadyExists =>
      "Herregni bilbila/imiyeelii kanaan duraanuu jira — maaloo "
          "galmaa'aa.",
    AuthError.accountNotFound =>
      'Bilbila/imiyeelii kanaan herregan hin argamne — dursa herrega '
          'uumaa.',
    AuthError.wrongPassword =>
      'Jechi icciitii dogoggora dha. Irra deebi\u2019anii yaalaa.',
    AuthError.storageFailed =>
      'Herregi meeshaa kana irratti olkaa\u2019amu hin dandeenye. Irra '
          'deebi\u2019anii yaalaa.',
  };

  @override
  String get genericAuthError =>
      'Rakkoon tokko uumeera. Maaloo irra deebi\u2019anii yaalaa.';

  // ---------------------------------------------------------------- settings

  @override
  String get settingsTitle => 'Karoora';

  @override
  String get accountSection => 'Herrega';

  @override
  String get signedInAs => "Galmaa'ee jira";

  @override
  String get appearanceSection => "Mul'ata";

  @override
  String get themeSystem => 'Sirna';

  @override
  String get themeLight => 'Ifa';

  @override
  String get themeDark => 'Dukkaa';

  @override
  String get languageSection => 'Afaan';

  @override
  String get signOut => "Ba'aa";

  @override
  String get signOutConfirmTitle => "Ba'uu barbaaddanuu?";

  @override
  String get signOutConfirmBody =>
      "Jecha icciitii keessaniin deebi'anii galmaa'uu dandeessu — "
      'herregni keessan meeshaa kana irratti hafa.';

  @override
  String get versionLabel => 'Veerzhinii';

  @override
  String get deviceCodeLabel => 'Koodii meeshaa';

  @override
  String get copiedToClipboard => 'Kopii ta\u2019eera.';

  @override
  String get close => 'Cufaa';

  @override
  String get loading => 'Fe\u2019aa jira\u2026';

  // ---------------------------------------------------------------- scan

  @override
  String get scanTitle => 'Kaffaltii iskaanii godhaa';

  @override
  String get scanPositionHint => 'Koodii QR fureemii keessatti qabaa';

  @override
  String get scanUsageHint =>
      'QR risiitii kaffaltii irra cuunfame fayyadamaa — '
      'QR kaffaltii erguu ykn fudhachuu miti';

  @override
  String get scanFlash => 'Ifa';

  @override
  String get scanGallery => 'Gaaleryii';

  @override
  String get scanNoQrFound => 'Suuricha sanatti QR risiitii hin argamne.';

  @override
  String get scanImageUnreadable => 'Suuricha san dubbisuu hin dandeenye.';

  @override
  String scanCameraError(String code) =>
      'Kaameeraan hin banamne ($code). Fuula kana cufuudhaan irra '
      'deebi\u2019anii yaalaa.';

  @override
  String get scanRetry => 'Irra deebi\u2019anii yaalaa';

  @override
  String get scanCameraPermissionNeeded =>
      'QR risiitii iskaanii gochuuf hayyama kaameeraa barbaachisa.';

  @override
  String get scanGrantPermission => 'Hayyama kennaa';

  @override
  String get scanCameraOff =>
      'Mahtemaf kaameeraan cufameera. Sirna karoora keessaa banaa, '
      'ykn liinkii risiitii dabalaa.';

  @override
  String get scanOpenSettings => 'Karoora banaa';

  @override
  String get scanCameraUnavailable => 'Kaameeraan hin jiru';

  @override
  String get scanTypeAction => 'Lakkoofsa galchaa';

  @override
  String get typeSheetTitle =>
      'Lakkoofsa kaffaltii ykn referensii barreessaa';

  @override
  String get typeSheetHint =>
      'Fakkeenyaaf FT2614G2P01YB — ykn liinkii risiitii dabi';

  @override
  String get typeSheetRecent => 'Yaalii dhiyoo';

  // ---------------------------------------------------------------- result

  @override
  String get resultTitle => 'Bu\u2019aa Mirkaneessaa';

  @override
  String get resultNothingToShow => 'Risiitiin agarsiisu hin jiru.';

  @override
  String get resultVerifiedTitle => 'Kaffaltiin mirkaneeffameera!';

  @override
  String get resultFailedTitle => 'Mirkaneessiin hin milkoofne';

  @override
  String get resultVerifiedBody =>
      'Kaffaltiin kun dhugaa dha — baankiin mirkaneesseera.';

  @override
  String get resultFailedBody =>
      'Risiitiin kun mirkaneessuu hin dandeenye.';

  @override
  String get resultDone => 'Xumureera';

  @override
  String get resultShare => 'Qoodaa';

  @override
  String get resultTryAgain => 'Irra deebi\u2019anii yaalaa';

  @override
  String get senderLabel => 'Ergamaa';

  @override
  String get senderAccountLabel => 'Herrega ergamaa';

  @override
  String get receiverLabel => 'Fudhataa';

  @override
  String get receiverAccountLabel => 'Herrega fudhataa';

  @override
  String get dateLabel => 'Guyyaa';

  @override
  String get referenceShortLabel => 'Referensii';

  @override
  String get reasonLabel => 'Sababa';

  @override
  String get statusLabel => 'Haala';

  @override
  String get bankShortLabel => 'Baankii';

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
      ..writeln('Kaffaltiin Mahtemtiin mirkaneeffame')
      ..writeln('Baankii: $bankName')
      ..writeln('Referensii: $reference')
      ..writeln("Bay'ina: $amount")
      ..writeln('Ergamaa: $sender')
      ..writeln('Fudhataa: $receiver')
      ..write('Guyyaa: $date');
    return buffer.toString();
  }

  // ------------------------------------------------------- verify failures

  @override
  String failureMessage(VerifyErrorKind kind, String fallback) =>
      switch (kind) {
        VerifyErrorKind.network =>
          'Tajaajilaan hin argamne. Interneetiin kee banamee jiruu '
              'mirkaneessaa.',
        VerifyErrorKind.notFound => 'Lakkoofsa kanaan risiitiin hin argamne.',
        VerifyErrorKind.badInput =>
          'Lakkoofsa risiitii ykn liinkii sirrii ta\u2019e galchaa.',
        VerifyErrorKind.unreadable =>
          'QR risiitii dubbisuu hin dandeenye — irra deebi\u2019anii '
              'yaalaa.',
        VerifyErrorKind.unsupported =>
          'Baankiin ykn gosi risiitii kun ammaatti hin deeggaramu.',
      };

  @override
  List<String> failureTips(VerifyErrorKind kind, List<String> fallback) =>
      switch (kind) {
        VerifyErrorKind.network => const [
          'Daataa mobaa\u2019ilii ykn Wi-Fi baneemuu mirkaneessaa.',
          'Tajaajiliin yeroo gabaabaa dha — booda irra deebi\u2019anii '
              'yaalaa.',
        ],
        VerifyErrorKind.notFound => const [
          'Lakkoofsicha haqamee hin jiruu galchuu kee mirkaneessaa.',
          'Yoo liinkii dabaltan, guutu ta\u2019uu isaa mirkaneessaa.',
        ],
        VerifyErrorKind.badInput => const [
          'Liinkii akkuma ergamtan sirriitti dabalaa.',
        ],
        VerifyErrorKind.unreadable => const [
          'QR guutun ifatti fureemii keessatti qabaa.',
          'Lakkoofsa risiitii SMS irraa harkaan dabalaa.',
        ],
        VerifyErrorKind.unsupported => const [
          'Baankiiwwan deeggaraman fuula duraa irratti ilaalaa.',
        ],
      };

  // ---------------------------------------------------------------- history

  @override
  String get historyTitle => 'Seenaa';

  @override
  String get clearHistoryTooltip => 'Seenaa haqaa';

  @override
  String get clearHistoryTitle => 'Seenaa haqamuu?';

  @override
  String get clearHistoryBody =>
      'Mirkaneessoota olkaa\u2019aman hundi meeshaa kanaa ni haqamu.';

  @override
  String get clearButton => 'Haqaa';

  @override
  String get noChecksTitle => 'Ammaattanuu mirkaneessiin hin jiru';

  @override
  String get noChecksBody => 'Risiitiiwwan mirkaneeffaman asitti mul\u2019atu.';

  @override
  String get verifiedPaymentLabel => 'Kaffaltii mirkaneeffame';

  @override
  String get notVerifiedLabel => 'Hin mirkaneeffamne';

  @override
  String get checkedLabel => 'Yaalameera';

  @override
  String get noteLabel => 'Yaada';

  @override
  String get historySearchTooltip => 'Seenaa keessaa barbaadaa';

  @override
  String get historySearchHint =>
      'Referensii, maqaa ykn baankii barbaadaa';

  @override
  String get filterAll => 'Hunda';

  @override
  String get filterVerified => 'Mirkaneffame';

  @override
  String get filterFailed => 'Hin mirkaneeffamne';

  @override
  String get noMatchesTitle => 'Kan hin argamne';

  @override
  String get noMatchesBody =>
      'Yaaliin barbaacha ykn filannoo waliin walsimu hin jiru.';

  @override
  String get verifyAgain => 'Irra deebi\u2019anii mirkaneessaa';

  @override
  String get prefilledToast =>
      'Odeeffannoon guutameera — ilaalaa fi mirkaneessaa.';

  // ---------------------------------------------------------------- paywall

  @override
  String get paywallTitle => 'Mahtem Pro';

  @override
  String get pasteReceiptFromSms =>
      'Lakkoofsa risiitii SMS Telebirr irraa dabalaa.';

  @override
  String get pasteActivationCode =>
      'Koodii aaktiveeshinii argattan dabalaa.';

  @override
  String get codeBadFormat => 'Kun koodii aaktiveeshinii Mahtem hin fakkaatu.';

  @override
  String get codeBadSignature =>
      "Koodiin kun sirrii miti — kan ergaa akka irra deebi'ee isin ergu "
      'himaa.';

  @override
  String get codeWrongDevice =>
      'Koodiin kun meeshaa biraatiif kennameera. Kaffaltii keessan waliin '
      'koodii meeshaa armaan gadii agarsiifame ergaa.';

  @override
  String codeExpired(String date) =>
      'Koodiin kun guyyaa $date irratti dhumeera. Itti fufuuf haaraa '
      'bitaa.';

  @override
  String get codeNotAccepted => 'Koodiin kun fudhatamuu hin dandeenye.';

  @override
  String proActivatedToast(String date) =>
      'Mahtem Pro hanga guyyaa $date banameera \u{1F389}';

  @override
  String get clipboardEmptyForPaste =>
      'Kopii ta\u2019e hin jiru — dursa lakkoofsicha kopii godhaa.';

  @override
  String telebirrNumberCopied(String number) =>
      'Lakkoofsi Telebirr $number kopii ta\u2019eera — appii Telebirr '
      'keessatti dabalaa.';

  @override
  String amountCopied(String amount) =>
      "Bay'inni $amount ETB kopii ta\u2019eera.";

  @override
  String get stackingNote =>
      "Risiitiin tokko meeshaa kana irratti karoora tokko banuu danda'a. "
      "Itti fufuuf irra deebi'ee kaffalaa — lakkoofsa risiitii haaraa "
      'dabalaa; guyyoonni kaffaltii yeroo hunda walitti dabalamu.';

  @override
  String get hideActivationCode => 'Koodii aaktiveeshinii dhoksaa';

  @override
  String get haveActivationCode => 'Koodii aaktiveeshinii qabdanuu?';

  @override
  String get deviceCodeCopied => 'Koodiin meeshaa kopii ta\u2019eera.';

  @override
  String get proActiveTitle => 'Mahtem Pro banameera';

  @override
  String proUnlimitedUntil(String date) =>
      'Hanga guyyaa $date mirkaneessuu daangaa hin qabu.';

  @override
  String trialsLeftTitle(int count) => count == 1
      ? 'Mirkaneessi bilisaa tokko hafa.'
      : '$count mirkaneessoota bilisaa hafa.';

  @override
  String get trialsLeftBody =>
      'Erga sun xumuramee booda Mahtem Pro armaan gadiin banaa — seenaan '
      'keessan fi karoorni keessan hin tuqamu.';

  @override
  String get trialsGoneTitle => 'Mirkaneessi bilisaa dhumeera';

  @override
  String get trialsGoneBody =>
      'Risiitiiwwan itti fufuuf mirkaneessuuf armaan gadii banaa — '
      'daqiiqaa tokkoo fudhata.';

  @override
  String get pricePerMonth => 'ETB / ji\u2019a';

  @override
  String get priceUnlimitedBody =>
      'Baankii fi waaleetii hundaan risiitii mirkaneessuu daangaa hin '
      'qabne — CBE, Telebirr, BOA, M-Pesa fi kkf.';

  @override
  String priceYearlyOnce(String price) =>
      'Yookiin waggaa guutuuf yeroo tokkootti $price ETB kaffalaa.';

  @override
  String get howToActivate => 'Akkaataa itti banuu';

  @override
  String step1Title(String monthly, String yearly) =>
      '$monthly ETB (yookiin waggatti $yearly ETB) Telebirr tiin kaffalaa';

  @override
  String get step1Body =>
      "Bay'inni sirrii ta'e herrega Telebirr kanaatti ergaa:";

  @override
  String copyAmountChip(String amount) => "Bay'ina kopii godhaa — $amount ETB";

  @override
  String get step2Title => 'Lakkoofsa risiitii armaan gadii dabalaa';

  @override
  String step2Body(String monthly) =>
      'Telebirriin SMS mirkaneessaa lakkoofsa risiitii waliin erga '
      '(fkn. CHQ261Z4AB2C) — asitti dabalaa; appiin Telebirr ofumaan '
      'waliin mirkaneessa. Yoo kaffaltiin $monthly ETB dhugumatti '
      'herrega armaan olatti godhame ta\u2019e, Mahtem Pro yeroo sanatti '
      'ni banama.';

  @override
  String get telebirrReceiptNumber => 'Lakkoofsa risiitii Telebirr';

  @override
  String get receiptNumberHint => 'Fkn. CHQ261Z4AB2C';

  @override
  String get checkingWithTelebirr => 'Telebirr waliin mirkaneessaa jira\u2026';

  @override
  String get verifyAndActivate => 'Mirkaneessuudhaan banaa';

  @override
  String get activationCodeTitle => 'Koodii aaktiveeshinii';

  @override
  String get codeBoundNote =>
      'Koodoonni meeshaa tokkoof qofa hojjeta. Mirkaneessiin risiitii '
      'yeroo kamuu yoo hin milkoofne, kaffaltii keessan waliin koodii '
      'meeshaa kanaa ergaa — koodiin bilbilaa kanaaf uumameera.';

  @override
  String get activate => 'Banaa';

  @override
  String activationRejection(
    ActivationRejectReason reason,
    String fallback, {
    String amount = '',
  }) =>
      switch (reason) {
        ActivationRejectReason.emptyInput =>
          'Lakkoofsa risiitii SMS Telebirr irraa dabalaa.',
        ActivationRejectReason.notTelebirr =>
          'Kan Mahtem Pro banuu danda\u2019u risiitiin Telebirr qofa dha.',
        ActivationRejectReason.transactionFailed =>
          'Geejjibni Telebirr sun hin xumuramne — koodiin banuu hin '
              'dandeenye.',
        ActivationRejectReason.wrongAmount =>
          "Risiitiin kun bay'ina addaatiin ergameera — Mahtem Pro banuuf "
              "bay'inni karoora guutuu ta'uu qaba (armaan gadii ilaalaa).",
        ActivationRejectReason.wrongReceiver =>
          'Kaffaltiin kun herrega Telebirr qajeelfama keessatti jiru hin '
              'geesse. Bay\u2019ina karooraatiif herrega sanaatti irra '
              'deebi\u2019ee erguun, risiitii haaraa dabalaa.',
        ActivationRejectReason.receiptTooOld =>
          'Risiitiin kun bayyee moofadha. Irra deebi\u2019ee kaffalaa — '
          'risiitii SMS haaraa irraa fayyadamaa.',
        ActivationRejectReason.alreadyUsed =>
          'Risiitiin kun duraanuu meeshaa kana irratti fayyadameera. '
          'Yeroo karoorni xumuramu irra deebi\u2019ee kaffalaa — risiitii '
          'haaraa dabalaa.',
      };

  @override
  String get crashReportsNote =>
      'Appiin yeroo dhabeessu gabaasa maqaa hin qabne ni erama — '
      'risiitii fi odeeffannoo keessan isa keessatti hin jiru; '
      'saffisaan fooyyessuuf qofa.';

  // ------------------------------------------------- history upgrade (v1.9.0)

  @override
  String get statsChecks => 'Mirkaneessota';

  @override
  String get statsVerified => 'Mirkaneefaman';

  @override
  String get statsTotal => 'Waliigalaa';

  @override
  String get groupToday => 'Har\u2019aa';

  @override
  String get groupYesterday => 'Kaleessa';

  @override
  String get groupThisWeek => 'Torban kana';

  @override
  String get groupEarlier => 'Kan duraan';

  @override
  String get removedToast => 'Seenaa irraa haqameera.';

  @override
  String get undo => 'Deebi\u2019i';

  @override
  String get emptyCta => 'Risiitii kee jalqabaa mirkaneessi';

  @override
  String get exportTooltip => 'Seenaa qoodi';
}
