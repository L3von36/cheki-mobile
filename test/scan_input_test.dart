import 'dart:ui' show Offset, Rect, Size;

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

  group('stripTrailingCeJunk — Telebirr invoice decoder junk', () {
    test('strips a decoder-appended trailing c', () {
      expect(stripTrailingCeJunk('CHQ261Z4AB2C'), 'CHQ261Z4AB2');
      expect(stripTrailingCeJunk('CHQ261Z4AB2c'), 'CHQ261Z4AB2');
    });

    test('strips trailing c/e runs', () {
      expect(stripTrailingCeJunk('CHQ261Z4ABce'), 'CHQ261Z4AB');
      expect(stripTrailingCeJunk('DET8FJGUJeE'), 'DET8FJGUJ');
    });

    test('never strips below the 8-char invoice minimum', () {
      expect(stripTrailingCeJunk('CHQ261ZC'), 'CHQ261ZC'); // already 8
      expect(stripTrailingCeJunk('CHQ261ZCC'), 'CHQ261ZC'); // 9 → 8
    });

    test('leaves references that do not end in c/e untouched', () {
      expect(stripTrailingCeJunk('FT26140P01YB'), 'FT26140P01YB');
      expect(stripTrailingCeJunk('CHQ261Z4AB2'), 'CHQ261Z4AB2');
    });
  });

  group('numberScanViewfinderRect', () {
    test('matches the painted overlay geometry', () {
      final rect = numberScanViewfinderRect(const Size(400, 800));
      expect(rect.width, closeTo(400 * 0.82, 1e-9));
      expect(rect.height, 130);
      expect(rect.top, closeTo(800 * 0.26, 1e-9));
      expect(rect.center.dx, closeTo(200, 1e-9));
    });

    test('stays inside the screen on odd shapes', () {
      for (final size in const [
        Size(320, 640),
        Size(412, 915),
        Size(600, 800),
      ]) {
        final rect = numberScanViewfinderRect(size);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
    });
  });

  group('uprightImageSize', () {
    test('swaps dimensions for 90/270-degree sensors', () {
      expect(
        uprightImageSize(
            frameWidth: 1280, frameHeight: 720, sensorOrientation: 90),
        const Size(720, 1280),
      );
      expect(
        uprightImageSize(
            frameWidth: 1280, frameHeight: 720, sensorOrientation: 270),
        const Size(720, 1280),
      );
    });

    test('keeps dimensions for 0/180-degree sensors', () {
      expect(
        uprightImageSize(
            frameWidth: 640, frameHeight: 480, sensorOrientation: 0),
        const Size(640, 480),
      );
      expect(
        uprightImageSize(
            frameWidth: 640, frameHeight: 480, sensorOrientation: 180),
        const Size(640, 480),
      );
    });
  });

  group('ScanRegionMapper — viewfinder-only OCR', () {
    // Portrait phone, 400x800 logical; camera frame 1280x720 at 90°
    // sensor orientation → upright image 720x1280. The cover-fit scale
    // is 800/1280 = 0.625 with the image overflowing 25 px per side.
    const screen = Size(400, 800);
    const upright = Size(720, 1280);

    ScanRegionMapper mapper() =>
        ScanRegionMapper(screenSize: screen, uprightImageSize: upright);

    test('cover-fit scale and centered mapping', () {
      final m = mapper();
      expect(m.scale, closeTo(0.625, 1e-9));
      // The viewfinder is horizontally centered on screen, so its image
      // counterpart is horizontally centered in the image too.
      final region = m.regionInImage(numberScanViewfinderRect(screen));
      expect(region.center.dx, closeTo(upright.width / 2, 1e-9));
      // A known screen point maps to (screen - offset) / scale.
      final p = m.regionInImage(const Rect.fromLTRB(199, 272, 201, 274));
      expect(p.center.dx, closeTo((200 + 25) / 0.625, 1e-9));
      expect(p.center.dy, closeTo(273 / 0.625, 1e-9));
    });

    test('a line centered in the frame is read', () {
      final m = mapper();
      final viewfinder = numberScanViewfinderRect(screen);
      final region = m.regionInImage(viewfinder);
      final line = Rect.fromCenter(
        center: region.center,
        width: 300,
        height: 30,
      );
      expect(m.containsCenterOf(viewfinder, line), isTrue);
    });

    test('lines elsewhere on the receipt are ignored', () {
      final m = mapper();
      final viewfinder = numberScanViewfinderRect(screen);
      final region = m.regionInImage(viewfinder);
      Rect lineAt(Offset c) =>
          Rect.fromCenter(center: c, width: 300, height: 30);
      // Far above the frame (merchant name, amount).
      expect(
        m.containsCenterOf(
            viewfinder, lineAt(Offset(360, region.top - 80))),
        isFalse,
      );
      // Far below the frame (date, footer).
      expect(
        m.containsCenterOf(
            viewfinder, lineAt(Offset(360, region.bottom + 80))),
        isFalse,
      );
      // Deep in the cropped-out side of the image.
      expect(
        m.containsCenterOf(
            viewfinder, lineAt(Offset(40, region.center.dy))),
        isFalse,
      );
    });

    test('the forgiveness margin covers small preview drift', () {
      final m = mapper();
      final viewfinder = numberScanViewfinderRect(screen);
      final region = m.regionInImage(viewfinder);
      Rect lineAt(Offset c) =>
          Rect.fromCenter(center: c, width: 300, height: 30);
      // 8 logical px of drift ≈ 12.8 image px at this scale — the
      // default margin absorbs it so a slightly misaligned preview
      // still reads the aimed-at line.
      final justOutside = lineAt(Offset(360, region.bottom + 10));
      expect(m.containsCenterOf(viewfinder, justOutside), isTrue);
      // A clearly-outside line stays out even with margin.
      final wayOutside = lineAt(Offset(360, region.bottom + 60));
      expect(m.containsCenterOf(viewfinder, wayOutside), isFalse);
    });
  });
}
