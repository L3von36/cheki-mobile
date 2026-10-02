/// Camera-input hardening: QR readings are stabilized before use.
///
/// [ScanStabilizer] is the same approach our POS app (stylepos) uses at the
/// counter: never trust a single camera emission. The accepted payload is
/// then handed over untouched — bank detection, BOA QR decryption and
/// Telebirr invoice extraction are owned by the stylepos receipt verifier
/// (`core/receipt_verify`), which knows every payload shape it supports.
///
/// One decoder quirk survives that hand-off: junk letters ('c' / 'e') that
/// land INSIDE the decoded Telebirr blob, right after the invoice number,
/// get uppercased and swallowed by the invoice's 8-12 character A-Z0-9
/// run — so the extracted reference ends with a bogus 'C' no bank knows.
/// [stripTrailingCeJunk] removes those (never below the invoice format's
/// 8-character minimum); the controller's raw-scan retry net covers the
/// rare invoice that legitimately ends in C/E.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

// ---------------------------------------------------------------------
// ScanStabilizer
// ---------------------------------------------------------------------

/// Turns a stream of camera detections into one trusted code.
///
/// While a QR is in frame the decoder emits a reading almost every frame,
/// and imperfect reads happen — the classic symptom is the same payload
/// re-emitted with an extra trailing character. A code is accepted when:
///
///   * two consecutive readings agree exactly, or
///   * a reading arrives that is a strict prefix of the pending one (or
///     vice versa) — the shorter reading is a complete decode, the longer
///     one merely has junk appended, so the shorter wins immediately, or
///   * [maxWait] has elapsed since the first reading of this session —
///     dense codes whose readings never repeat exactly still accept the
///     best (shortest) candidate instead of stalling forever.
///
/// Readings that share nothing with the pending code reset the tracker:
/// a different QR entered the frame.
class ScanStabilizer {
  ScanStabilizer({
    this.maxWait = const Duration(milliseconds: 1500),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long the stream may keep disagreeing before the best candidate
  /// seen so far is accepted anyway.
  final Duration maxWait;
  final DateTime Function() _now;

  DateTime? _sessionStart;
  String? _pending;
  String? _best;
  int _agreements = 0;

  /// Feeds one raw camera reading. Returns the accepted, trimmed code —
  /// or null while more confidence is needed.
  String? feed(String rawReading) {
    final code = rawReading.trim();
    if (code.isEmpty) return null;

    final sessionStart = _sessionStart ??= _now();
    final best = _best;
    if (best == null || code.length < best.length) _best = code;

    final pending = _pending;
    if (pending == null) {
      _pending = code;
      _agreements = 1;
      return null;
    }

    if (pending == code) {
      _agreements++;
      if (_agreements >= 2) {
        reset();
        return code;
      }
      return null;
    }

    // Same payload family? QR decoding never truncates — a shorter read
    // is a complete decode and the longer one carries appended junk.
    final shorter = pending.length <= code.length ? pending : code;
    final longer = shorter == pending ? code : pending;
    if (longer.startsWith(shorter)) {
      reset();
      return shorter;
    }

    // Unrelated reading — a different code entered the frame.
    _pending = code;
    _agreements = 1;

    // Deadline: never keep the user waiting on a noisy code.
    if (_now().difference(sessionStart) >= maxWait && _best != null) {
      final accepted = _best!;
      reset();
      return accepted;
    }
    return null;
  }

  /// Forgets all state (e.g. when the scanner reopens).
  void reset() {
    _sessionStart = null;
    _pending = null;
    _best = null;
    _agreements = 0;
  }
}

// ---------------------------------------------------------------------
// stripTrailingCeJunk
// ---------------------------------------------------------------------

/// Strips decoder junk letters from an extracted Telebirr invoice number.
///
/// The camera sometimes appends a stray 'c' (or 'e') while the QR leaves
/// the frame. On link payloads that junk sits at the very end and the
/// stabilizer's shorter-read rule removes it — but Telebirr SuperApp
/// receipt QRs are base64 blobs, and the junk lands INSIDE the decoded
/// text right after the invoice number. The 8-12 character A-Z0-9 run
/// then swallows the uppercased junk letter and the extracted reference
/// ends with a bogus 'C' that no bank knows.
///
/// Trailing c/e runs are removed while at least 8 characters remain (the
/// invoice format's minimum length). When a removed letter was genuine —
/// invoices may legitimately end in C/E — the raw-scan retry net in
/// VerifyController.verify re-verifies with the untouched value.
String stripTrailingCeJunk(String invoice) {
  var ref = invoice.trim();
  while (ref.length > 8 && RegExp(r'[cCeE]$').hasMatch(ref)) {
    ref = ref.substring(0, ref.length - 1);
  }
  return ref;
}

// ---------------------------------------------------------------------
// Scan region (viewfinder) geometry
// ---------------------------------------------------------------------

/// The number scanner's viewfinder rectangle in screen coordinates —
/// 82% of the screen width, 130 logical pixels tall, its top edge at
/// 26% of the screen height. The painted overlay and the OCR filter
/// both derive their geometry from this one function, so the window
/// the user aims at is exactly the window the app reads.
Rect numberScanViewfinderRect(Size screenSize) {
  final width = screenSize.width * 0.82;
  const height = 130.0;
  final top = screenSize.height * 0.26;
  final left = (screenSize.width - width) / 2;
  return Rect.fromLTWH(left, top, width, height);
}

/// The upright (rotation-corrected) size of a camera frame.
///
/// ML Kit reports bounding boxes in the rotation-corrected space: a
/// 1280x720 sensor frame captured in portrait at 90° sensor orientation
/// is reported as if the image were 720x1280.
Size uprightImageSize({
  required int frameWidth,
  required int frameHeight,
  required int sensorOrientation,
}) {
  final swap = sensorOrientation == 90 || sensorOrientation == 270;
  return swap
      ? Size(frameHeight.toDouble(), frameWidth.toDouble())
      : Size(frameWidth.toDouble(), frameHeight.toDouble());
}

/// Maps between the screen (what the user sees) and the upright camera
/// image (the space ML Kit reports bounding boxes in).
///
/// The camera preview covers the screen: the frame is scaled uniformly
/// until both of its dimensions cover the view, then the overflow is
/// cropped equally on the edges that stick out. One scale factor and
/// one offset therefore connect the two coordinate spaces:
///
///     image = (screen - offset) / scale
///
/// Preview pipelines differ slightly between devices (a few pixels of
/// correspondence drift); [containsCenterOf] absorbs that with its
/// margin instead of pretending pixel-exactness we cannot guarantee.
class ScanRegionMapper {
  ScanRegionMapper({
    required this.screenSize,
    required this.uprightImageSize,
  });

  /// Logical size of the preview surface (the whole screen here).
  final Size screenSize;

  /// Rotation-corrected size of the camera frame.
  final Size uprightImageSize;

  late final double scale = math.max(
    screenSize.width / uprightImageSize.width,
    screenSize.height / uprightImageSize.height,
  );

  late final Offset _offset = Offset(
    (screenSize.width - uprightImageSize.width * scale) / 2,
    (screenSize.height - uprightImageSize.height * scale) / 2,
  );

  /// [screenRect] expressed in upright image coordinates.
  Rect regionInImage(Rect screenRect) => Rect.fromLTRB(
        (screenRect.left - _offset.dx) / scale,
        (screenRect.top - _offset.dy) / scale,
        (screenRect.right - _offset.dx) / scale,
        (screenRect.bottom - _offset.dy) / scale,
      );

  /// True when the CENTER of an OCR line ([lineBox], upright image
  /// coordinates) falls inside [screenRegion] (screen coordinates),
  /// allowing [screenMargin] logical pixels of forgiveness.
  ///
  /// The center is what the user aims the frame at. A line whose center
  /// is outside the window — the amount line above, the date line
  /// below, the bank footer — stays out of the candidate list even when
  /// its edges clip the window. The margin is converted into image
  /// pixels so its meaning is the same on every device.
  bool containsCenterOf(
    Rect screenRegion,
    Rect lineBox, {
    double screenMargin = 8,
  }) {
    final region = regionInImage(screenRegion).inflate(screenMargin / scale);
    return region.contains(lineBox.center);
  }
}
