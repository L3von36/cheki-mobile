/// Scan-input hardening: camera readings are stabilized before use and the
/// accepted payload is cleaned before receipt detection runs.
///
/// The approach follows what our own POS app (stylepos) does at the counter:
/// never trust a single camera emission (it gates duplicate readings and
/// trims the code before handing it on). Mahtem goes a step further:
///
///  1. [ScanStabilizer] — a QR is only accepted once the camera stream
///     agrees with itself. Two identical readings accept immediately, and
///     when readings differ only at the tail the shorter one wins (QR
///     payloads decode all-or-nothing, so the extra character is decoder
///     junk, e.g. `…BEI` vs `…BEIc`).
///  2. [sanitizeScannedCode] — the accepted payload is trimmed of
///     zero-width characters and trailing punctuation, and decoder-added
///     trailing letters ('c' / 'e' reported on real Telebirr scans) are
///     removed — but only when the shortened value is still recognized at
///     least as strongly as the original, so a genuine CBE 12-hex receipt
///     id ending in c/e is never corrupted.
library;

import 'banks_registry.dart';

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
// sanitizeScannedCode
// ---------------------------------------------------------------------

/// Characters some cameras / share sheets inject invisibly.
final RegExp _zeroWidth =
    RegExp('[\u200b\u200c\u200d\u2060\ufeff]');

/// Punctuation copy/share actions love to append after a link or code.
final RegExp _trailingJunk = RegExp(r'[\s.,;:!?()\[\]{}…—–|-]+$');

/// The trailing letters reported by real scans: the decoder sometimes
/// appends a final 'c' or 'e' while the QR leaves the frame.
final RegExp _trailingCe = RegExp(r'[cCeE]+$');

String? _bankIdOf(String payload) => detectReceipt(payload)?.bank;

/// Cleans a scanned (or pasted) payload before receipt detection:
///
///  1. removes zero-width characters and trailing whitespace,
///  2. strips trailing punctuation,
///  3. drops a decoder-appended trailing 'c' / 'e' run — but ONLY when the
///     shortened payload still detects a bank, or the original detected
///     none. This keeps genuine references that legitimately end in
///     c/e (like CBE 12-hex receipt ids) untouched, while the reported
///     Telebirr `…BEI` → `…BEIc` junk is removed.
String sanitizeScannedCode(String raw) {
  var code = raw.replaceAll(_zeroWidth, '').trim();
  if (code.isEmpty) return code;

  // 1 + 2: whitespace / punctuation tail, repeated for "…" runs.
  while (true) {
    final next = code.replaceFirst(_trailingJunk, '').trim();
    if (next.isEmpty || next == code) break;
    code = next;
  }

  // 3: trailing decoder junk letters, guarded by re-recognition.
  final candidate = code.replaceFirst(_trailingCe, '').trim();
  if (candidate.length < code.length && candidate.isNotEmpty) {
    final originalBank = _bankIdOf(code);
    final candidateBank = _bankIdOf(candidate);
    if (candidateBank != null || originalBank == null) {
      return candidate;
    }
  }
  return code;
}
