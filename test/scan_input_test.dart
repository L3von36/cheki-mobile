import 'package:mahtem/core/scan_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanStabilizer', () {
    test('does not accept a single reading', () {
      final s = ScanStabilizer();
      expect(s.feed('DET8FJGUJ4'), isNull);
    });

    test('accepts when two consecutive readings agree', () {
      final s = ScanStabilizer();
      expect(s.feed('DET8FJGUJ4'), isNull);
      expect(s.feed('DET8FJGUJ4'), 'DET8FJGUJ4');
      // Accepted values reset the tracker — a fresh code needs 2 again.
      expect(s.feed('DET8FJGUJ4'), isNull);
      expect(s.feed('DET8FJGUJ4'), 'DET8FJGUJ4');
    });

    test('junk-appended reading then clean reading accepts the shorter', () {
      // The user-reported Telebirr case: the decoder appends a trailing
      // 'c' while the QR leaves the frame.
      final s = ScanStabilizer();
      expect(s.feed('CFG6W10BEIc'), isNull);
      expect(s.feed('CFG6W10BEI'), 'CFG6W10BEI');
    });

    test('clean reading then junk-appended reading accepts the shorter', () {
      final s = ScanStabilizer();
      expect(s.feed('CFG6W10BEI'), isNull);
      expect(s.feed('CFG6W10BEIc'), 'CFG6W10BEI');
    });

    test('unrelated readings reset — a different QR entered the frame', () {
      final s = ScanStabilizer();
      expect(s.feed('DET8FJGUJ4'), isNull);
      expect(s.feed('CHQ261Z4AB2C'), isNull);
      // The pending tracker now holds CHQ…, so one more CHQ… accepts it.
      expect(s.feed('CHQ261Z4AB2C'), 'CHQ261Z4AB2C');
    });

    test('noisy code still accepts the best candidate after maxWait', () {
      var clock = DateTime(2026, 1, 1, 12);
      final s = ScanStabilizer(now: () => clock);
      expect(s.feed('AAAAAAAAAA'), isNull);
      clock = clock.add(const Duration(milliseconds: 200));
      // Unrelated readings keep the tracker busy but never agree.
      expect(s.feed('BBBBBBBBBB'), isNull);
      // Past the 1500 ms deadline the best (first) read wins.
      clock = clock.add(const Duration(milliseconds: 1400));
      expect(s.feed('CCCCCCCCCC'), 'AAAAAAAAAA');
    });

    test('reset clears pending state', () {
      final s = ScanStabilizer();
      expect(s.feed('DET8FJGUJ4'), isNull);
      s.reset();
      // After a reset a single reading is not enough again.
      expect(s.feed('DET8FJGUJ4'), isNull);
    });

    test('whitespace is trimmed before comparison', () {
      final s = ScanStabilizer();
      expect(s.feed('  DET8FJGUJ4 '), isNull);
      expect(s.feed('DET8FJGUJ4'), 'DET8FJGUJ4');
    });
  });
}
