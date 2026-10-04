library;

/// Formatting helpers for the Mahtem Admin console.

const _minute = 60000;
const _hour = 3600000;
const _day = 86400000;

/// Compact relative time: "just now", "5m ago", "3h ago", "2d ago", date.
String timeAgo(int? ts, [int? now]) {
  if (ts == null || ts <= 0) return '—';
  final n = now ?? DateTime.now().millisecondsSinceEpoch;
  final d = n - ts > 0 ? n - ts : 0;
  if (d < 45000) return 'just now';
  if (d < _hour) return '${(d / _minute).round()}m ago';
  if (d < _day) return '${(d / _hour).round()}h ago';
  if (d < 30 * _day) return '${(d / _day).round()}d ago';
  return fmtDate(ts);
}

/// "Oct 4, 2026"
String fmtDate(int? ts) {
  if (ts == null || ts <= 0) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final dt = DateTime.fromMillisecondsSinceEpoch(ts).toUtc();
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

/// "2026-09-21" → "Sep 21"
String fmtDayLabel(String isoDay) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final parts = isoDay.split('-');
  if (parts.length != 3) return isoDay;
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (m == null || d == null || m < 1 || m > 12) return isoDay;
  return '${months[m - 1]} $d';
}

/// Percentage of [part] in [total], 0 when total is 0.
int rate(int part, int total) {
  if (total <= 0) return 0;
  return ((part / total) * 100).round();
}

/// "1,234" — thousands separator without pulling in intl.
String thousands(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    buf.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return n < 0 ? '-${buf.toString()}' : buf.toString();
}
