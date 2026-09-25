import 'package:intl/intl.dart';

/// Formats an amount as `ETB 12,345.00` (or the given currency code).
String formatAmount(double? amount, String? currency) {
  if (amount == null) return '—';
  final code = (currency == null || currency.isEmpty) ? 'ETB' : currency;
  final formatted = NumberFormat.currency(
    symbol: '',
    decimalDigits: 2,
  ).format(amount);
  return '$code $formatted';
}

/// Formats an amount number only (used inside the big receipt hero).
String formatAmountPlain(double? amount) {
  if (amount == null) return '—';
  return NumberFormat.currency(symbol: '', decimalDigits: 2).format(amount);
}

/// Best-effort date prettifier. Bank dates come in many shapes
/// ("5/20/2026, 7:29:00 PM", "2026-05-20 19:29:00", "20 May 2026"...).
String formatReceiptDate(String? raw) {
  if (raw == null || raw.trimmedIsEmpty) return '—';
  final value = raw.trim();
  final dt = DateTime.tryParse(value);
  if (dt != null) {
    return DateFormat('d MMM yyyy · h:mm a').format(dt);
  }
  // Try "M/d/yyyy, h:mm:ss AM"
  final mdy = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4}),?\s+(\d{1,2}):(\d{2}):(\d{2})\s*(AM|PM)?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (mdy != null) {
    try {
      var hour = int.parse(mdy.group(4)!);
      final suffix = mdy.group(7)?.toUpperCase();
      if (suffix == 'PM' && hour < 12) hour += 12;
      if (suffix == 'AM' && hour == 12) hour = 0;
      final dt2 = DateTime(
        int.parse(mdy.group(3)!),
        int.parse(mdy.group(1)!),
        int.parse(mdy.group(2)!),
        hour,
        int.parse(mdy.group(5)!),
        int.parse(mdy.group(6)!),
      );
      return DateFormat('d MMM yyyy · h:mm a').format(dt2);
    } on FormatException {
      // fall through
    }
  }
  return value;
}

/// Copies-friendly multiline summary of a verified receipt.
String receiptSummary({
  required String bankName,
  required String reference,
  double? amount,
  String? currency,
  String? sender,
  String? receiver,
  String? date,
  required bool verified,
  required String url,
}) {
  final buf = StringBuffer()
    ..writeln(verified ? '✅ VERIFIED — verified on cheki' : '❌ NOT VERIFIED');
  buf.writeln('Bank: $bankName');
  buf.writeln('Reference: $reference');
  if (amount != null) buf.writeln('Amount: ${formatAmount(amount, currency)}');
  if (sender != null && sender.isNotEmpty) buf.writeln('From: $sender');
  if (receiver != null && receiver.isNotEmpty) buf.writeln('To: $receiver');
  if (date != null && date.isNotEmpty) buf.writeln('Date: $date');
  buf.writeln('Official source: $url');
  buf.writeln();
  buf.write('Verified free with cheki — chekiapp.vercel.app');
  return buf.toString();
}

extension on String {
  bool get trimmedIsEmpty => trim().isEmpty;
}
