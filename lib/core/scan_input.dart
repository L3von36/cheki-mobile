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
