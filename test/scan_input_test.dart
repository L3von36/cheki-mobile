import 'package:mahtem/core/banks_registry.dart';
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
      expect(s.feed('CFG6W10BEIe'), 'CFG6W10BEI');
    });

    test('unrelated reading resets the tracker', () {
      final s = ScanStabilizer();
      expect(s.feed('CODEONE1'), isNull);
      expect(s.feed('CODETWO2'), isNull); // reset — unrelated
      expect(s.feed('CODETWO2'), 'CODETWO2');
    });

    test('whitespace-only readings are ignored', () {
      final s = ScanStabilizer();
      expect(s.feed('   '), isNull);
      expect(s.feed('\n'), isNull);
      expect(s.feed(' DET8FJGUJ4 '), isNull);
      expect(s.feed('DET8FJGUJ4'), 'DET8FJGUJ4');
    });
  });

  group('sanitizeScannedCode', () {
    test('strips a decoder-added trailing c from a Telebirr receipt link',
        () {
      final clean = sanitizeScannedCode(
        'https://transactioninfo.ethiotelecom.et/receipt/CFG6W10BEIc',
      );
      expect(clean,
          'https://transactioninfo.ethiotelecom.et/receipt/CFG6W10BEI');

      final detection = detectReceipt(clean);
      expect(detection?.bank, 'telebirr');
      expect(detection?.reference, 'CFG6W10BEI');
    });

    test('strips a decoder-added trailing e from a Telebirr TPS reference',
        () {
      expect(
        sanitizeScannedCode('TPS25191.1430.A4001234e'),
        'TPS25191.1430.A4001234',
      );
    });

    test('leaves a clean Telebirr link untouched', () {
      const link =
          'https://transactioninfo.ethiotelecom.et/receipt/CFG6W10BEI';
      expect(sanitizeScannedCode(link), link);
    });

    test('never corrupts a CBE 12-hex receipt id ending in c', () {
      const id = 'a1b2c3d4e5fC';
      expect(sanitizeScannedCode(id), id);
    });

    test('never corrupts a CBE 12-hex receipt id ending in E', () {
      const id = 'a1b2c3d4e5fE';
      expect(sanitizeScannedCode(id), id);
    });

    test('trims whitespace and newlines around the payload', () {
      expect(sanitizeScannedCode('  DET8FJGUJ4 \n'), 'DET8FJGUJ4');
    });

    test('strips trailing punctuation from shared links', () {
      expect(
        sanitizeScannedCode(
            'https://transactioninfo.ethiotelecom.et/receipt/DET8FJGUJ4.'),
        'https://transactioninfo.ethiotelecom.et/receipt/DET8FJGUJ4',
      );
    });

    test('removes zero-width characters', () {
      expect(sanitizeScannedCode('DET8FJGUJ\u200b4'), 'DET8FJGUJ4');
    });

    test('plain values keep their trailing letters when nothing better '
        'is recognized either way', () {
      // A generic payload with no bank attribution — the junk-letter rule
      // still applies (cleaned value is at least as recognizable).
      expect(sanitizeScannedCode('PAYOUT99231Xc'), 'PAYOUT99231X');
    });
  });
}
