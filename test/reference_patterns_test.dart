import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/reference_patterns.dart';

void main() {
  group('labeled numbers rank first', () {
    test('RRN label with 12 digits', () {
      final candidates =
          extractReferenceCandidates('RRN: 123456789012 Amount 250.00');
      expect(candidates, isNotEmpty);
      expect(candidates.first.value, '123456789012');
      expect(candidates.first.rank, 1);
    });

    test('Ref label with an alphanumeric reference', () {
      final candidates = extractReferenceCandidates('Ref: GT8842ABCD12');
      expect(candidates.first.value, 'GT8842ABCD12');
      expect(candidates.first.rank, 1);
    });

    test('Transaction No. label with spacing variants', () {
      expect(
        extractReferenceCandidates('Transaction No 987654321012').first.value,
        '987654321012',
      );
      expect(
        extractReferenceCandidates('txn-AB12CD34EF56').first.value,
        'AB12CD34EF56',
      );
      expect(
        extractReferenceCandidates('RECEIPT #445566778899').first.value,
        '445566778899',
      );
    });

    test('FT fiscal numbers keep the FT prefix', () {
      final candidates = extractReferenceCandidates('FT#12345678901234');
      expect(candidates.first.value, 'FT12345678901234');
      expect(candidates.first.rank, 1);

      // telebirr-style FT references are alphanumeric.
      expect(
        extractReferenceCandidates('FT2614G2P01YB').first.value,
        'FT2614G2P01YB',
      );
    });

    test('a labeled number beats the same value read bare', () {
      final candidates =
          extractReferenceCandidates('RRN 123456789012 123456789012');
      expect(candidates, hasLength(1));
      expect(candidates.first.rank, 1);
    });
  });

  group('bare numbers', () {
    test('a bare 12-digit number is rank 2', () {
      final candidates = extractReferenceCandidates('TOTAL 1,234.56');
      expect(candidates, isEmpty); // price must not qualify

      final rrn = extractReferenceCandidates('123456789012');
      expect(rrn.first.rank, 2);
      expect(rrn.first.value, '123456789012');
    });

    test('other lengths are rank 3', () {
      expect(extractReferenceCandidates('1234567890').first.rank, 3);
      expect(extractReferenceCandidates('1234567890123456').first.rank, 3);
    });

    test('grouped digits are joined', () {
      final candidates = extractReferenceCandidates('1234 5678 9012');
      expect(candidates.first.value, '123456789012');
    });

    test('numbers inside a longer run are not matched', () {
      expect(extractReferenceCandidates('12345678901234567890123456'), isEmpty);
    });
  });

  group('phone numbers never become candidates', () {
    test('Ethiopian mobile shapes are filtered', () {
      expect(extractReferenceCandidates('Call 0912345678'), isEmpty);
      expect(extractReferenceCandidates('0712345678'), isEmpty);
      expect(extractReferenceCandidates('251912345678'), isEmpty);
      expect(extractReferenceCandidates('+251712345678'), isEmpty);
    });

    test('similar-but-not-phone numbers survive', () {
      // 25 then 1… is not the 251 international prefix shape.
      expect(extractReferenceCandidates('2512345678'), isNotEmpty);
      // A labeled phone-looking value is an explicit reference.
      expect(
        extractReferenceCandidates('Ref: 0912345678').first.value,
        '0912345678',
      );
    });
  });

  group('alphanumeric tokens', () {
    test('telebirr-style tokens rank 4', () {
      final candidates = extractReferenceCandidates('GA8412NK34');
      expect(candidates.first.value, 'GA8412NK34');
      expect(candidates.first.rank, 4);
    });

    test('words and prices do not qualify', () {
      expect(extractReferenceCandidates('TOTAL ETB'), isEmpty);
      expect(extractReferenceCandidates('1,234.56'), isEmpty);
      expect(extractReferenceCandidates('15/01/2025'), isEmpty);
      expect(extractReferenceCandidates('Thank you'), isEmpty);
    });

    test('lowercase ocr output still qualifies', () {
      expect(extractReferenceCandidates('ref: ga8412nk34').first.value,
          'ga8412nk34');
    });
  });

  group('a realistic receipt page', () {
    test('picks the labeled reference, not the noise', () {
      const receipt = '''
COMMERCIAL BANK OF ETHIOPIA
Payment Confirmation
Date: 15/01/2025 10:32
Amount: ETB 4,500.00
Sender Acc: 1000123456789
Recipient: 1000987654321
Telephone: 0911234567
RRN: 340512987654
Ref No: CBE20250115AX
Status: SUCCESS
''';
      final candidates = extractReferenceCandidates(receipt);
      expect(candidates.first.value, '340512987654');
      expect(candidates.first.rank, 1);
      // The labeled CBE reference is right behind it.
      expect(
        candidates.map((c) => c.value),
        contains('CBE20250115AX'),
      );
      // Noise stayed out.
      expect(candidates.map((c) => c.value), isNot(contains('0911234567')));
      expect(candidates.map((c) => c.value), isNot(contains('1000123456789')));
      expect(candidates.map((c) => c.value), isNot(contains('1000987654321')));
      expect(candidates.length, lessThanOrEqualTo(5));
    });
  });

  group('edge cases', () {
    test('empty and garbage input', () {
      expect(extractReferenceCandidates(''), isEmpty);
      expect(extractReferenceCandidates('   '), isEmpty);
      expect(extractReferenceCandidates('...—:-'), isEmpty);
    });

    test('same-character runs are rejected', () {
      expect(extractReferenceCandidates('000000000000'), isEmpty);
      expect(extractReferenceCandidates('AAAAAAAA1234'), isNotEmpty);
    });

    test('shortlist is capped at five', () {
      const many =
          'RRN 340512987654\n'
          'Ref ABCDEF234567\n'
          '222233334444\n'
          '333344445555\n'
          '444455556666\n'
          '555566667777\n'
          '666677778888\n';
      expect(extractReferenceCandidates(many), hasLength(5));
    });

    test('sender account, TIN and phone fields are masked out', () {
      const page = '''
Sender Acc: 1000123456789
TIN: 0045239678
Tel 0911234567
Ref: CBE20250115AX
''';
      final candidates = extractReferenceCandidates(page);
      expect(candidates, hasLength(1));
      expect(candidates.single.value, 'CBE20250115AX');
    });

    test('dedupeAndRank keeps the best rank per value', () {
      final merged = dedupeAndRank(const [
        ReferenceCandidate('AB12CD34EF56', 4),
        ReferenceCandidate('ab12cd34ef56', 1),
        ReferenceCandidate('123456789012', 3),
      ]);
      expect(merged, hasLength(2));
      expect(merged.first.value, 'ab12cd34ef56');
      expect(merged.first.rank, 1);
    });

    test('bestReferenceCandidate returns the top pick or null', () {
      expect(bestReferenceCandidate('RRN: 123456789012'), '123456789012');
      expect(bestReferenceCandidate('no numbers here'), isNull);
    });
  });

  group('ambiguityVariants (OCR misreads)', () {
    test('swaps confusable characters both ways', () {
      final variants = ambiguityVariants('LO0');
      expect(variants, contains('100')); // L→1, O stays, 0 stays? L→1 only
      expect(variants, contains('1O0')); // L→1
      expect(variants, contains('LOO')); // 0→O
    });

    test('never includes the original value', () {
      for (final v in ambiguityVariants('FT26140P01YB')) {
        expect(v, isNot('FT26140P01YB'));
      }
    });

    test('is capped and stable', () {
      final variants = ambiguityVariants('O1B5Z2');
      expect(variants.length, lessThanOrEqualTo(12));
      expect(variants.toSet().length, variants.length);
    });

    test('empty when nothing is confusable or too much explodes', () {
      expect(ambiguityVariants('AHKMQRTUWY'), isEmpty);
      expect(ambiguityVariants('OOOOOOOOOO'), isEmpty);
    });
  });

  group('extractReceiptFromText (SMS / chat paste)', () {
    test('pulls a telebirr link out of a full SMS body', () {
      const sms =
          'Dear customer, you have paid 500.00 ETB. Receipt CHQ261Z4AB2C. '
          'Details: https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C';
      final hit = extractReceiptFromText(sms);
      expect(hit, isNotNull);
      expect(hit!.isUrl, isTrue);
      expect(
        hit.value,
        'https://transactioninfo.ethiotelecom.et/receipt/CHQ261Z4AB2C',
      );
    });

    test('pulls an FT reference from prose without a link', () {
      final hit =
          extractReceiptFromText('Payment done, ref FT26140P01YB, thanks');
      expect(hit, isNotNull);
      expect(hit!.isUrl, isFalse);
      expect(hit.value, 'FT26140P01YB');
    });

    test('pulls a telebirr-shaped invoice from prose', () {
      final hit = extractReceiptFromText('kaffaltii CHQ261Z4AB2C ta\u2019eera');
      expect(hit!.value, 'CHQ261Z4AB2C');
    });

    test('falls back to a bare 12-digit number', () {
      final hit = extractReceiptFromText('here is the number 123456789012 ok');
      expect(hit!.value, '123456789012');
    });

    test('never adopts a phone number as the receipt', () {
      expect(extractReceiptFromText('call me 0912345678'), isNull);
    });

    test('ignores random web links inside prose', () {
      expect(
        extractReceiptFromText(
            'see https://example.com/some/page for the product'),
        isNull,
      );
    });

    test('a bare unknown link is handed over for the honest error', () {
      final hit = extractReceiptFromText('https://unknown.example.com/r/xyz');
      expect(hit!.isUrl, isTrue);
      expect(hit.value, 'https://unknown.example.com/r/xyz');
    });

    test('an already-clean value returns itself unchanged', () {
      final hit = extractReceiptFromText('FT26140P01YB');
      expect(hit!.value, 'FT26140P01YB');
    });
  });
}
