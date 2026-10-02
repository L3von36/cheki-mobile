import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/parsers.dart';

/// v1.11.0 — Coopay tenant (Cooperative Bank of Oromia via the eBirr
/// platform) and the Siinqee host migration off the dead eBirr route.
void main() {
  group('buildCoopayUri', () {
    test('bare token lands on the coopay tenant', () {
      expect(
        buildCoopayUri('AB12CD34EF').toString(),
        'https://receipt.ebirr.com/coopay/AB12CD34EF',
      );
    });

    test('tenant/token pair passes through', () {
      expect(
        buildCoopayUri('coopay/AB12CD34EF').toString(),
        'https://receipt.ebirr.com/coopay/AB12CD34EF',
      );
    });

    test('a full URL is used verbatim', () {
      const url = 'https://receipt.ebirr.com/coopay/AB12CD34EF';
      expect(buildCoopayUri(url).toString(), url);
    });
  });

  group('buildSiinqeeUri — host migration', () {
    test('bare reference goes to the bank\u2019s own host', () {
      expect(
        buildSiinqeeUri('FT262507XG9T').toString(),
        'https://siinqeebank.com/receipt/FT262507XG9T',
      );
    });

    test('old dead eBirr siinqee links are re-routed', () {
      expect(
        buildSiinqeeUri('https://receipt.ebirr.com/siinqee/AB12CD34EF')
            .toString(),
        'https://siinqeebank.com/receipt/AB12CD34EF',
      );
    });

    test('the siinqee/{token} pair form is re-routed too', () {
      expect(
        buildSiinqeeUri('siinqee/AB12CD34EF').toString(),
        'https://siinqeebank.com/receipt/AB12CD34EF',
      );
    });

    test('non-eBirr URLs pass through untouched', () {
      const url = 'https://siinqeebank.com/receipt/FT262507XG9T';
      expect(buildSiinqeeUri(url).toString(), url);
    });
  });

  group('looksLikeTelebirrReference', () {
    test('accepts the known invoice prefixes', () {
      expect(looksLikeTelebirrReference('CHQ261Z4AB2C'), isTrue);
      expect(looksLikeTelebirrReference('DET261Z4AB2C'), isTrue);
      expect(looksLikeTelebirrReference('ADQ12345678'), isTrue);
      expect(looksLikeTelebirrReference('DF12345678'), isTrue);
      expect(looksLikeTelebirrReference('chq261z4ab2c'), isTrue); // case-free
    });

    test('rejects other shapes', () {
      expect(looksLikeTelebirrReference('FT26140P01YB'), isFalse); // FT core
      expect(looksLikeTelebirrReference('123456789012'), isFalse); // bare RRN
      expect(looksLikeTelebirrReference('CHQ123'), isFalse); // too short
      expect(looksLikeTelebirrReference('CHQ261Z4AB2CXY'), isFalse); // 13
      expect(looksLikeTelebirrReference(''), isFalse);
    });
  });

  group('Coopay catalog entry', () {
    test('ships in the live catalog as a wallet', () {
      final coopay = bankById('coopay');
      expect(coopay, isNotNull);
      expect(coopay!.name, 'Cooperative Bank of Oromia');
      expect(coopay.isWallet, isTrue);
      expect(kVerifyBanks.indexOf(bankById('coopay')!),
          greaterThan(kVerifyBanks.indexOf(bankById('siinqee')!)));
      expect(kVerifyBanks.indexOf(bankById('coopay')!),
          lessThan(kVerifyBanks.indexOf(bankById('ebirr')!)));
    });

    test('siinqee catalog entry points at the new host', () {
      expect(
        bankById('siinqee')!.referenceHint,
        contains('siinqeebank.com'),
      );
    });
  });

  group('URL detection for the migrated hosts', () {
    test('new siinqeebank.com links detect as the siinqee bank', () {
      final hit = detectBankFromUrl(
          'https://siinqeebank.com/receipt/FT262507XG9T');
      expect(hit, isNotNull);
      expect(hit!.bank, 'siinqee');
      expect(hit.reference, 'FT262507XG9T');
    });

    test('old eBirr siinqee links still detect as the eBirr family', () {
      final hit = detectBankFromUrl(
          'https://receipt.ebirr.com/siinqee/AB12CD34EF');
      expect(hit!.bank, 'ebirr');
      expect(hit.reference, 'siinqee/AB12CD34EF');
    });
  });
}
