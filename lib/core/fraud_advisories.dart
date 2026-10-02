/// Local anti-fraud advisories — computed entirely on-device.
///
/// Two checks run after a successful verification, before the result
/// screen slides in:
///
///  * [freshnessAdvisory] — a receipt presented as today's payment but
///    dated days ago is the classic replayed-receipt scam (a real receipt
///    reused at the wrong moment). The age is computed from the receipt's
///    own printed date against the device clock.
///
///  * [duplicateAdvisory] — the same reference verified here before means
///    a customer is walking an old receipt around. Lookup is strictly
///    local history; nothing ever leaves the device.
///
/// Both return a finished, localized advisory sentence (built through the
/// injected [note] builders) or null — null means "no concern", never an
/// error. Pure Dart, fully unit-tested without a device.
library;

import 'verify_history.dart';

/// Best-effort parse of the date strings Ethiopian receipt endpoints
/// return. Shapes seen in the wild:
///
///  * ISO 8601 — some JSON APIs
///  * `dd-MM-yyyy HH:mm:ss` — Telebirr, Awash pay pages
///  * `M/d/yyyy, h:mm:ss AM/PM` — CBE PDF / new JSON
///  * `Mon d, yyyy, h:mm:ss am` — Dashen SuperApp PDF
///
/// Returns null for anything unparseable — an advisory must never fire
/// from a guessed date.
DateTime? tryParseReceiptDate(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;

  final iso = DateTime.tryParse(t);
  if (iso != null) return iso;

  // dd-MM-yyyy HH:mm:ss
  var m = RegExp(
    r'^(\d{1,2})-(\d{1,2})-(\d{4})[ T](\d{1,2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(t);
  if (m != null) {
    return _safe(
      int.parse(m.group(3)!),
      int.parse(m.group(2)!),
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      m.group(6),
    );
  }

  // M/d/yyyy, h:mm:ss AM/PM (also tolerates the reversed d/M order)
  m = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?$',
  ).firstMatch(t);
  if (m != null) {
    var hour = int.parse(m.group(4)!);
    final ap = m.group(7)?.toUpperCase();
    if (ap == 'PM' && hour < 12) hour += 12;
    if (ap == 'AM' && hour == 12) hour = 0;
    final first = int.parse(m.group(1)!);
    final second = int.parse(m.group(2)!);
    var month = first, day = second;
    if (first > 12 && second <= 12) {
      month = second;
      day = first;
    }
    return _safe(
      int.parse(m.group(3)!),
      month,
      day,
      hour,
      int.parse(m.group(5)!),
      m.group(6),
    );
  }

  // Mon d, yyyy, h:mm:ss am
  m = RegExp(
    r'^([A-Za-z]{3,})\s+(\d{1,2}),?\s+(\d{4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?$',
  ).firstMatch(t);
  if (m != null) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[m.group(1)!.toLowerCase()];
    if (month != null) {
      var hour = int.parse(m.group(4)!);
      final ap = m.group(7)?.toUpperCase();
      if (ap == 'PM' && hour < 12) hour += 12;
      if (ap == 'AM' && hour == 12) hour = 0;
      return _safe(
        int.parse(m.group(3)!),
        month,
        int.parse(m.group(2)!),
        hour,
        int.parse(m.group(5)!),
        m.group(6),
      );
    }
  }

  return null;
}

DateTime? _safe(int y, int mo, int d, int h, int mi, String? sec) {
  try {
    return DateTime(y, mo, d, h, mi, sec == null ? 0 : int.parse(sec));
  } catch (_) {
    return null;
  }
}

/// Advisory for a receipt older than a day. Advance payments are legit —
/// the wording asks the merchant to confirm, it never blocks. Returns
/// null for fresh receipts, future dates (clock skew) and unparseable
/// dates.
String? freshnessAdvisory({
  String? receiptDate,
  required DateTime now,
  required String Function(int days) note,
}) {
  final when = tryParseReceiptDate(receiptDate);
  if (when == null) return null;
  final age = now.difference(when);
  if (age.inMinutes < 0) return null; // clock skew — never scold
  if (age.inHours < 24) return null;
  return note(age.inDays);
}

/// Advisory when this exact bank + reference already produced a verified
/// check in local history. A check performed moments ago is the user
/// re-running their own lookup and is ignored. [when] receives a compact
/// locale-neutral timestamp of the earlier check.
String? duplicateAdvisory({
  required List<HistoryEntry> entries,
  required String bankId,
  required String reference,
  required DateTime now,
  required String Function(String when) note,
}) {
  final ref = reference.trim().toUpperCase();
  if (ref.isEmpty) return null;

  HistoryEntry? latest;
  for (final e in entries) {
    if (e.reference.trim().toUpperCase() != ref) continue;
    if (bankId.isNotEmpty && e.bankId.isNotEmpty && e.bankId != bankId) {
      continue;
    }
    if (!e.isVerified) continue;
    if (latest == null || e.verifiedAt > latest.verifiedAt) latest = e;
  }
  if (latest == null) return null;

  final checked = DateTime.fromMillisecondsSinceEpoch(latest.verifiedAt);
  if (now.difference(checked).inMinutes.abs() < 2) return null;

  final two = (int v) => v.toString().padLeft(2, '0');
  final sameDay = now.year == checked.year &&
      now.month == checked.month &&
      now.day == checked.day;
  final stamp = sameDay
      ? '${two(checked.hour)}:${two(checked.minute)}'
      : '${checked.year}-${two(checked.month)}-${two(checked.day)} '
          '${two(checked.hour)}:${two(checked.minute)}';
  return note(stamp);
}
