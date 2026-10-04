import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem_admin/format.dart';

void main() {
  group('timeAgo', () {
    final now = DateTime.utc(2026, 10, 4, 20, 0).millisecondsSinceEpoch;

    test('null/zero renders an em dash', () {
      expect(timeAgo(null, now), '—');
      expect(timeAgo(0, now), '—');
    });

    test('under 45s is "just now"', () {
      expect(timeAgo(now - 1000, now), 'just now');
      expect(timeAgo(now - 44000, now), 'just now');
    });

    test('minutes / hours / days', () {
      expect(timeAgo(now - 5 * 60000, now), '5m ago');
      expect(timeAgo(now - 3 * 3600000, now), '3h ago');
      expect(timeAgo(now - 2 * 86400000, now), '2d ago');
    });

    test('beyond 30 days falls back to a date', () {
      expect(timeAgo(now - 45 * 86400000, now), contains('2026'));
    });

    test('future timestamps clamp to "just now"', () {
      expect(timeAgo(now + 3600000, now), 'just now');
    });
  });

  group('fmtDate', () {
    test('formats a UTC date', () {
      final ts = DateTime.utc(2026, 10, 4).millisecondsSinceEpoch;
      expect(fmtDate(ts), 'Oct 4, 2026');
    });

    test('null/zero renders an em dash', () {
      expect(fmtDate(null), '—');
      expect(fmtDate(0), '—');
    });
  });

  group('fmtDayLabel', () {
    test('converts ISO day to a short label', () {
      expect(fmtDayLabel('2026-09-21'), 'Sep 21');
      expect(fmtDayLabel('2026-10-04'), 'Oct 4');
    });

    test('passes through garbage untouched', () {
      expect(fmtDayLabel('not-a-day'), 'not-a-day');
    });
  });

  group('rate', () {
    test('percentage rounding', () {
      expect(rate(35, 42), 83);
      expect(rate(1, 3), 33);
      expect(rate(0, 0), 0);
      expect(rate(5, 0), 0);
    });
  });

  group('thousands', () {
    test('separates groups of three', () {
      expect(thousands(0), '0');
      expect(thousands(999), '999');
      expect(thousands(1000), '1,000');
      expect(thousands(1234567), '1,234,567');
      expect(thousands(-9876), '-9,876');
    });
  });
}
