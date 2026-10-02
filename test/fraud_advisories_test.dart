import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/fraud_advisories.dart';
import 'package:mahtem/core/verify_history.dart';

HistoryEntry _entry({
  required String id,
  String bankId = 'telebirr',
  required String reference,
  required String status,
  required int verifiedAt,
}) =>
    HistoryEntry(
      id: id,
      bankId: bankId,
      bankName: 'Bank',
      reference: reference,
      verifiedAt: verifiedAt,
      status: status,
    );

void main() {
  group('tryParseReceiptDate', () {
    test('ISO 8601', () {
      expect(
        tryParseReceiptDate('2026-10-01T09:15:00'),
        DateTime(2026, 10, 1, 9, 15),
      );
    });

    test('dd-MM-yyyy HH:mm:ss (telebirr / awashpay)', () {
      expect(
        tryParseReceiptDate('02-10-2026 14:30:07'),
        DateTime(2026, 10, 2, 14, 30, 7),
      );
    });

    test('M/d/yyyy, h:mm:ss AM/PM (CBE)', () {
      expect(
        tryParseReceiptDate('5/20/2026, 7:29:00 PM'),
        DateTime(2026, 5, 20, 19, 29),
      );
      expect(
        tryParseReceiptDate('5/20/2026, 12:05:00 AM'),
        DateTime(2026, 5, 20, 0, 5),
      );
    });

    test('reversed d/M order is tolerated', () {
      expect(
        tryParseReceiptDate('25/6/2026, 1:00:00 PM'),
        DateTime(2026, 6, 25, 13, 0),
      );
    });

    test('Mon d, yyyy, h:mm:ss am (Dashen PDF)', () {
      expect(
        tryParseReceiptDate('Mar 12, 2026, 9:05:30 am'),
        DateTime(2026, 3, 12, 9, 5, 30),
      );
      expect(
        tryParseReceiptDate('Sep 30, 2026, 11:59:59 pm'),
        DateTime(2026, 9, 30, 23, 59, 59),
      );
    });

    test('garbage and null return null — never guess', () {
      expect(tryParseReceiptDate('yesterday maybe'), isNull);
      expect(tryParseReceiptDate(''), isNull);
      expect(tryParseReceiptDate(null), isNull);
    });
  });

  group('freshnessAdvisory', () {
    final now = DateTime(2026, 10, 2, 12, 0);

    test('fires for a receipt older than a day, with the day count', () {
      final note = freshnessAdvisory(
        receiptDate: '30-09-2026 11:00:00',
        now: now,
        note: (days) => 'stale:$days',
      );
      expect(note, 'stale:2');
    });

    test('silent for fresh receipts, future dates and bad dates', () {
      expect(
        freshnessAdvisory(
          receiptDate: '02-10-2026 11:00:00',
          now: now,
          note: (days) => 'stale:$days',
        ),
        isNull,
      );
      expect(
        freshnessAdvisory(
          receiptDate: '05-10-2026 11:00:00', // ahead of the clock
          now: now,
          note: (days) => 'stale:$days',
        ),
        isNull,
      );
      expect(
        freshnessAdvisory(
          receiptDate: 'not a date',
          now: now,
          note: (days) => 'stale:$days',
        ),
        isNull,
      );
      expect(
        freshnessAdvisory(
          receiptDate: null,
          now: now,
          note: (days) => 'stale:$days',
        ),
        isNull,
      );
    });

    test('a 25-hour-old receipt warns with 1 day', () {
      final note = freshnessAdvisory(
        receiptDate: '01-10-2026 11:00:00',
        now: now,
        note: (days) => 'stale:$days',
      );
      expect(note, 'stale:1');
    });
  });

  group('duplicateAdvisory', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1_800_000_000_000);

    test('fires for the same bank + reference verified earlier', () {
      final note = duplicateAdvisory(
        entries: [
          _entry(
            id: 'a',
            reference: 'FT26140P01YB',
            status: 'verified',
            verifiedAt: now.millisecondsSinceEpoch - const Duration(days: 1).inMilliseconds,
          ),
        ],
        bankId: 'telebirr',
        reference: 'FT26140P01YB',
        now: now,
        note: (when) => 'dup:$when',
      );
      expect(note, isNotNull);
      expect(note, startsWith('dup:'));
    });

    test('matching is case-insensitive and bank-scoped', () {
      final entries = [
        _entry(
          id: 'a',
          reference: 'ft26140p01yb',
          status: 'verified',
          verifiedAt: now.millisecondsSinceEpoch - 3_600_000,
        ),
      ];
      expect(
        duplicateAdvisory(
          entries: entries,
          bankId: 'telebirr',
          reference: 'FT26140P01YB',
          now: now,
          note: (when) => 'dup:$when',
        ),
        isNotNull,
      );
      expect(
        duplicateAdvisory(
          entries: entries,
          bankId: 'cbe',
          reference: 'FT26140P01YB',
          now: now,
          note: (when) => 'dup:$when',
        ),
        isNull,
      );
    });

    test('failed checks and empty references never fire', () {
      expect(
        duplicateAdvisory(
          entries: [
            _entry(
              id: 'a',
              reference: 'FT26140P01YB',
              status: 'failed',
              verifiedAt: now.millisecondsSinceEpoch - 3_600_000,
            ),
          ],
          bankId: 'telebirr',
          reference: 'FT26140P01YB',
          now: now,
          note: (when) => 'dup:$when',
        ),
        isNull,
      );
      expect(
        duplicateAdvisory(
          entries: [],
          bankId: 'telebirr',
          reference: '   ',
          now: now,
          note: (when) => 'dup:$when',
        ),
        isNull,
      );
    });

    test('a check performed seconds ago is the user re-running it', () {
      expect(
        duplicateAdvisory(
          entries: [
            _entry(
              id: 'a',
              reference: 'FT26140P01YB',
              status: 'verified',
              verifiedAt: now.millisecondsSinceEpoch - 30_000,
            ),
          ],
          bankId: 'telebirr',
          reference: 'FT26140P01YB',
          now: now,
          note: (when) => 'dup:$when',
        ),
        isNull,
      );
    });
  });
}
