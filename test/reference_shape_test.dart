import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/receipt_verify/reference_shape.dart';

/// Bare-reference shape detection — which bank(s) a reference plausibly
/// belongs to when no link/QR identified it, and when that shape is
/// unambiguous enough to pre-select.
void main() {
  group('bankCandidatesForReference', () {
    test('Telebirr invoice prefixes (case-insensitive)', () {
      expect(bankCandidatesForReference('CHQ261Z4AB2C'), ['telebirr']);
      expect(bankCandidatesForReference('chq261z4ab2c'), ['telebirr']);
      expect(bankCandidatesForReference('DET261Z4AB2D'), ['telebirr']);
      expect(bankCandidatesForReference('ADQ9Z4AB2C1'), ['telebirr']);
    });

    test('Zemen share references', () {
      expect(bankCandidatesForReference('ETTB123456789'), ['zemen']);
      expect(bankCandidatesForReference('ETTBA1B2C3'), ['zemen']);
    });

    test('FT references are ambiguous across Amhara / BOA / CBE Birr', () {
      expect(
        bankCandidatesForReference('FT26140P01YB'),
        ['amhara', 'boa', 'cbebirr'],
      );
      expect(
        bankCandidatesForReference('ft26140p01yb'),
        ['amhara', 'boa', 'cbebirr'],
      );
      // CBE itself is deliberately NOT a candidate — its API refuses
      // printed FT numbers (500 "Security Alert").
      expect(bankCandidatesForReference('FT26140P01YB'), isNot(contains('cbe')));
    });

    test('CBE receipt codes — mixed case, digit-bearing', () {
      expect(bankCandidatesForReference('fHCx8QmLpZ1'), ['cbe']);
      expect(bankCandidatesForReference('fHCxyV4mg5pRIwEkJO'), ['cbe']);
      expect(bankCandidatesForReference('v2-hfHCxGKF1KZsUlmmWpFL'), ['cbe']);
      // Never a CBE claim: after normalization a lowercase code is just
      // an M-Pesa-shaped token; all-digit / too-short values match nothing.
      expect(bankCandidatesForReference('abcdefgh12'), isNot(contains('cbe')));
      expect(bankCandidatesForReference('fHCx8Qm'), isEmpty);
      expect(bankCandidatesForReference('12345678'), isEmpty);
    });

    test('Dashen — pure digits 14–16 long', () {
      expect(bankCandidatesForReference('26010805472123'), ['dashen']);
      expect(bankCandidatesForReference('26010805472123456789'), isEmpty);
      expect(bankCandidatesForReference('1234567890123'), isEmpty);
    });

    test('M-Pesa — exactly 10 characters mixing letters and digits', () {
      expect(bankCandidatesForReference('SJ72HK3YZ9'), ['mpesa']);
      expect(bankCandidatesForReference('SJ72HK3YZ'), isEmpty); // 9
      expect(bankCandidatesForReference('SJ72HK3YZ90'), isEmpty); // 11
      expect(bankCandidatesForReference('ABCDEFGHIJ'), isEmpty); // no digit
      expect(bankCandidatesForReference('1234567890'), isEmpty); // no letter
    });

    test('Awash share tokens keep the leading dash; a dashed FT is not '
        'Awash', () {
      expect(bankCandidatesForReference('-2KHIQYW30P-5VQUNG'), ['awash']);
      // A dash inside an FT-shaped token rules out both the FT rule (no
      // separators allowed) and Awash (FT-led tokens are excluded) — the
      // shape claims nothing and the manual picker keeps working.
      expect(bankCandidatesForReference('FT26140P01-YB'), isEmpty);
    });

    test('Wegagen — `150TBAW` prefixed ids', () {
      expect(
        bankCandidatesForReference('150TBAW2626221151113DAAT'),
        ['wegagen'],
      );
      // Letter-led tokens are not Wegagen.
      expect(bankCandidatesForReference('TBAW150150150150150150150'),
          isEmpty);
      // The rule is prefix-pinned: some other digit-led token (e.g. an
      // unknown bank's) no longer pre-selects Wegagen.
      expect(bankCandidatesForReference('9999AAAABBBBCCCCDDDDEEEE'), isEmpty);
    });

    test('Abay — `135FT…` receipt codes, never mistaken for Wegagen', () {
      expect(
        bankCandidatesForReference('135FTRM25044000119176773010'),
        ['abay'],
      );
      // The Abay code used to fall into the old digit-led Wegagen rule.
      expect(
        bankCandidatesForReference('135FTRM25044000119176773010'),
        isNot(contains('wegagen')),
      );
      // A bare `135FT` with nothing behind it is too short to claim.
      expect(bankCandidatesForReference('135FT'), isEmpty);
    });

    test('links, empty and unknown shapes yield no candidates', () {
      expect(
        bankCandidatesForReference('https://mbreciept.cbe.com.et/fHCx8QmLpZ1'),
        isEmpty,
      );
      expect(bankCandidatesForReference(''), isEmpty);
      expect(bankCandidatesForReference('   '), isEmpty);
      expect(bankCandidatesForReference('REFERENCE99'), isEmpty);
      expect(bankCandidatesForReference('123456789012'), isEmpty);
    });
  });

  group('autoDetectBankForReference', () {
    test('returns the bank for unambiguous shapes', () {
      expect(autoDetectBankForReference('CHQ261Z4AB2C'), 'telebirr');
      expect(autoDetectBankForReference('ETTB123456789'), 'zemen');
      expect(autoDetectBankForReference('fHCx8QmLpZ1'), 'cbe');
      expect(autoDetectBankForReference('26010805472123'), 'dashen');
      expect(autoDetectBankForReference('SJ72HK3YZ9'), 'mpesa');
      expect(autoDetectBankForReference('-2KHIQYW30P-5VQUNG'), 'awash');
      expect(
          autoDetectBankForReference('150TBAW2626221151113DAAT'), 'wegagen');
      expect(autoDetectBankForReference('135FTRM25044000119176773010'), 'abay');
    });

    test('never guesses ambiguous or unknown shapes', () {
      expect(autoDetectBankForReference('FT26140P01YB'), isNull);
      expect(autoDetectBankForReference('REFERENCE99'), isNull);
      expect(autoDetectBankForReference(''), isNull);
    });
  });
}
