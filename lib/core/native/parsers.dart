import 'dart:convert';
import 'dart:typed_data';

import 'pdf_text.dart';

// Per-bank receipt parsers — Mahtem's own implementation.
///
/// Each bank exposes a public receipt endpoint with its own response shape:
///   * CBE (new mbreciept system) ........ JSON
///   * Bank of Abyssinia ................. JSON
///   * M-Pesa Ethiopia ................... JSON
///   * Telebirr .......................... HTML tables
///   * Awash Bank ........................ HTML tables (self-signed TLS)
///   * CBE Birr .......................... HTML (ASP.NET report page)
///   * eBirr / Siinqee ................... HTML tables
///   * Dashen Bank ....................... PDF (text extraction)
///   * Zemen Bank ........................ PDF (text extraction)
///
/// Every parser fills a [ParsedReceipt]; `verified` is true only when the
/// response clearly belongs to a real receipt of that bank.

/// Bank-agnostic receipt data extracted from a bank endpoint response.
class ParsedReceipt {
  final bool verified;
  final String? senderName;
  final String? senderAccount;
  final String? receiverName;
  final String? receiverAccount;
  final double? amount;
  final String currency;
  final String? date;
  final String? reference;
  final String? branch;
  final String? reason;
  final String? transactionStatus;
  final String? transactionType;

  const ParsedReceipt({
    required this.verified,
    this.senderName,
    this.senderAccount,
    this.receiverName,
    this.receiverAccount,
    this.amount,
    this.currency = 'ETB',
    this.date,
    this.reference,
    this.branch,
    this.reason,
    this.transactionStatus,
    this.transactionType,
  });
}

// ===========================================================================
// Shared helpers
// ===========================================================================

double? _toDouble(String? raw) {
  if (raw == null) return null;
  // Amounts arrive as "1,250.50", "300.00 Birr", "ETB 4,500.00", ...
  final m = RegExp(r'[0-9][0-9,]*(?:\.\d+)?').firstMatch(raw);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(',', ''));
}

/// Converts an HTML document into trimmed text lines, preserving table cell
/// boundaries so label/value pairs stay adjacent.
List<String> htmlToLines(String html) {
  return html
      .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</td>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</tr>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '\n')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\r'), '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Looks up the value belonging to a label within [lines].
///
/// Handles the three layouts these receipts use:
///   1. label alone on a line, value on the next line
///   2. "Label: value" / "Label=value" on one line
///   3. label followed by other text, value on the next line
String? findLabelValue(List<String> lines, String label, {int startAt = 0}) {
  final needle = label.toLowerCase();

  // Pass 1: exact label line (optionally ending in "." or ":"), value on
  // the next line.
  for (var i = startAt; i < lines.length; i++) {
    final line = lines[i].toLowerCase();
    if (line == needle ||
        line == '$needle:' ||
        line == '$needle.' ||
        line == '$needle =') {
      if (i + 1 < lines.length) {
        var j = i + 1;
        if (lines[j] == ':' && j + 1 < lines.length) j++;
        return lines[j];
      }
    }
  }

  // Pass 2: same-line "Label: value" / "Label= value".
  for (var i = startAt; i < lines.length; i++) {
    final line = lines[i];
    if (line.toLowerCase().contains(needle)) {
      final m = RegExp('${RegExp.escape(label)}\\s*[.:=]\\s*(.+)\$', caseSensitive: false)
          .firstMatch(line);
      if (m != null) return m.group(1)!.trim();
    }
  }

  // Pass 3: label line (compound labels rejected), value on the next line.
  for (var i = startAt; i < lines.length; i++) {
    final line = lines[i];
    if (line.toLowerCase().contains(needle)) {
      final remainder =
          line.replaceFirst(RegExp('^.*?${RegExp.escape(label)}', caseSensitive: false), '').trim();
      // Anything that is not just punctuation after the label means this
      // line is a compound heading like "Merchant Payment", not a label.
      if (remainder.isNotEmpty &&
          !remainder.startsWith(':') &&
          !RegExp(r'^[.:=]*$').hasMatch(remainder)) {
        continue;
      }
      if (i + 1 < lines.length) {
        var j = i + 1;
        if (lines[j] == ':' && j + 1 < lines.length) j++;
        return lines[j];
      }
    }
  }
  return null;
}

/// First "N,NNN.NN Birr/ETB" amount found at or after a label line.
double? findBirrAmount(List<String> lines, String label) {
  final pattern = RegExp(r'([0-9][0-9,]*\.?\d*)\s*(?:Birr|ETB)', caseSensitive: false);
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].toLowerCase().contains(label.toLowerCase())) continue;
    final m = pattern.firstMatch(lines[i]);
    if (m != null) return _toDouble(m.group(1));
    for (var j = i + 1; j < (i + 4).clamp(0, lines.length); j++) {
      final m2 = pattern.firstMatch(lines[j]);
      if (m2 != null) return _toDouble(m2.group(1));
    }
  }
  return null;
}

/// Generic "Label: value" field extraction for the simpler receipt pages
/// (CBE Birr, eBirr tenants). Handles both layouts these pages use:
/// "Label: value" on one line, or label and value in adjacent cells/lines.
Map<String, String> extractKvFields(List<String> lines) {
  final fields = <String, String>{};
  void put(String key, String value) {
    final k = key.trim().toLowerCase();
    final v = value.trim();
    if (k.isNotEmpty && v.isNotEmpty && !fields.containsKey(k)) {
      fields[k] = v;
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final sepIdx = line.indexOf(':');
    if (sepIdx > 0 && sepIdx < line.length - 1) {
      put(line.substring(0, sepIdx), line.substring(sepIdx + 1));
      continue;
    }

    // Label on its own line → value on the next line (skipping ":" rows).
    if (i + 1 < lines.length) {
      var j = i + 1;
      if (lines[j] == ':' && j + 1 < lines.length) j++;
      put(line, lines[j]);
      i = j;
    }
  }
  return fields;
}

// ===========================================================================
// CBE — new mbreciept JSON API
// ===========================================================================

/// Parses the JSON returned by Mb.cbe.com.et transaction-detail.
ParsedReceipt parseCbeNew(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return const ParsedReceipt(verified: false);
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return const ParsedReceipt(verified: false);

    final amountStr = (json['amountCredited'] ?? json['amountDebited']) as String?;
    final dateTimes = json['dateTimes'] as List?;
    final paymentDetails = json['paymentDetails'] as List?;

    return ParsedReceipt(
      verified: true,
      senderName: json['debitAccountHolder'] as String?,
      senderAccount: json['debitAccountNo'] as String?,
      receiverName: json['creditAccountHolder'] as String?,
      receiverAccount: json['creditAccountNo'] as String?,
      amount: _toDouble(amountStr),
      currency: (json['creditCurrency'] as String?) ?? 'ETB',
      date: dateTimes != null && dateTimes.isNotEmpty ? dateTimes.first as String? : null,
      reference: id,
      reason: paymentDetails != null && paymentDetails.isNotEmpty
          ? paymentDetails.first as String?
          : null,
    );
  } catch (_) {
    return const ParsedReceipt(verified: false);
  }
}

// ===========================================================================
// Bank of Abyssinia — online slip JSON
// ===========================================================================

/// Parses the JSON returned by cs.bankofabyssinia.com getDetails.
ParsedReceipt parseBoa(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return const ParsedReceipt(verified: false);
    final body_ = json['body'];
    if (body_ is! List || body_.isEmpty) return const ParsedReceipt(verified: false);
    final row = body_.first;
    if (row is! Map<String, dynamic>) return const ParsedReceipt(verified: false);
    if (row["Payer's Name"] == 'Invalid reference number') {
      return const ParsedReceipt(verified: false);
    }
    double? amount;
    final amountRaw = (row['Transferred Amount'] ?? '').toString();
    final amountMatch = RegExp(r'[0-9][0-9,]*(?:\.\d+)?').firstMatch(amountRaw);
    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(0)!.replaceAll(',', ''));
    }
    return ParsedReceipt(
      verified: true,
      senderName: row['Source Account Name'] as String?,
      senderAccount: row['Source Account'] as String?,
      receiverName: row["Receiver's Name"] as String?,
      receiverAccount: row["Receiver's Account"] as String?,
      amount: amount,
      currency: (row['currency'] as String?) ?? 'ETB',
      date: row['Transaction Date'] as String?,
      reference: row['Transaction Reference'] as String?,
    );
  } catch (_) {
    return const ParsedReceipt(verified: false);
  }
}

// ===========================================================================
// M-Pesa — Safaricom Ethiopia receipt JSON
// ===========================================================================

/// Parses the JSON returned by m-pesabusiness.safaricom.et getReceipt.
ParsedReceipt parseMpesa(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return const ParsedReceipt(verified: false);
    final code = json['responseCode'];
    if (code != null && code.toString() != '0') {
      return const ParsedReceipt(verified: false);
    }
    return ParsedReceipt(
      verified: true,
      senderName: (json['senderName'] ?? json['payerName']) as String?,
      receiverName: (json['receiverName'] ?? json['creditPartyName']) as String?,
      amount: _toDouble((json['amount'] ?? '').toString()),
      currency: (json['currency'] as String?) ?? 'ETB',
      date: (json['transactionDate'] ?? json['date']) as String?,
      reference: (json['transactionId'] ?? json['trxNo']) as String?,
    );
  } catch (_) {
    return const ParsedReceipt(verified: false);
  }
}

// ===========================================================================
// Telebirr — HTML receipt tables
// ===========================================================================

/// Decodes a Telebirr receipt QR payload into its invoice number.
///
/// These QR codes are NOT links: the payload is a base64-encoded UTF-8
/// hex string whose bytes (read as latin1) hold printable text containing
/// the invoice number as an 8-12 character A-Z0-9 run. Returns null for
/// anything that does not follow that exact encoding chain.
String? extractTelebirrInvoiceFromQr(String qrData) {
  try {
    var b64 = qrData.trim().replaceAll(RegExp(r'\s'), '');
    // Tolerate unpadded base64 (the camera payload often drops '=').
    final pad = b64.length % 4;
    if (pad == 2) b64 = '$b64==';
    if (pad == 3) b64 = '$b64=';
    if (pad == 1) return null;
    final hexCandidate = utf8.decode(base64Decode(b64), allowMalformed: true);
    if (hexCandidate.isEmpty ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hexCandidate)) {
      return null;
    }
    final bytes = <int>[];
    for (var i = 0; i + 1 < hexCandidate.length; i += 2) {
      bytes.add(int.parse(hexCandidate.substring(i, i + 2), radix: 16));
    }
    final text = latin1.decode(bytes, allowInvalid: true).toUpperCase();
    return RegExp(r'[A-Z0-9]{8,12}').firstMatch(text)?.group(0);
  } catch (_) {
    return null;
  }
}

/// Parses the transactioninfo.ethiotelecom.et receipt HTML.
ParsedReceipt parseTelebirr(String html) {
  if (html.contains('This request is not correct') ||
      !html.toLowerCase().contains('telebirr')) {
    return const ParsedReceipt(verified: false);
  }
  final lines = htmlToLines(html);

  String? value(String en, String? am) =>
      findLabelValue(lines, en) ?? (am != null ? findLabelValue(lines, am) : null);

  // Pick the transfer amount: Settled Amount first, else any Birr value.
  var amount = findBirrAmount(lines, 'Settled Amount');
  amount ??= findBirrAmount(lines, 'Total Paid Amount');

  String? date;
  for (final line in lines) {
    final m = RegExp(r'(\d{2}-\d{2}-\d{4}\s+\d{2}:\d{2}:\d{2})').firstMatch(line);
    if (m != null) {
      date = m.group(1);
      break;
    }
  }

  // The real recipient bank account line packs "1000370251685   Mr Name".
  String? bankAccountNo;
  String? bankAccountName;
  final bankAccountRaw = value('Bank account number', 'የባንክ አካውንት ቁጥር');
  if (bankAccountRaw != null) {
    final m = RegExp(r'^(\d{10,})\s+(.+)$').firstMatch(bankAccountRaw);
    if (m != null) {
      bankAccountNo = m.group(1);
      bankAccountName = m.group(2);
    } else {
      bankAccountNo = bankAccountRaw;
    }
  }

  final senderName = value('Payer Name', 'የከፋፋይ ስም');
  final receiverName =
      value('Credited Party name', 'የገንዘብ ተቀባዩ ስም') ?? bankAccountName;
  final invoiceNumber = value('Invoice No', 'የክፍያ ማስረጃ ቁጥር');

  return ParsedReceipt(
    verified: senderName != null || receiverName != null || amount != null,
    senderName: senderName,
    senderAccount: value('Payer telebirr no', 'የከፋፋይ ቴሌብር ቁጥር'),
    receiverName: receiverName,
    receiverAccount: bankAccountNo ?? value('Credited party account no', null),
    amount: amount,
    date: date,
    reference: invoiceNumber,
    reason: value('Payment Reason', 'የክፍያ ምክንያት'),
    transactionStatus: value('transaction status', 'የክፍያ ሁኔታ'),
    transactionType: value('Payment Mode', 'የክፍያ ዓይነት'),
  );
}

// ===========================================================================
// Awash — HTML receipt (awashpay.awashbank.com:8225)
// ===========================================================================

/// Parses the Awash share-link receipt HTML.
ParsedReceipt parseAwash(String html) {
  if (html.contains('Invalid receipt id') ||
      html.toLowerCase().contains('invalid receipt')) {
    return const ParsedReceipt(verified: false);
  }
  final lines = htmlToLines(html);

  final senderName = findLabelValue(lines, 'Sender Name') ?? findLabelValue(lines, 'Customer Name');
  final senderAccount = findLabelValue(lines, 'Sender Account') ??
      findLabelValue(lines, 'Source Account') ??
      findLabelValue(lines, 'Account No');
  final receiverName = findLabelValue(lines, 'Receiver Name') ??
      findLabelValue(lines, 'Beneficiary name') ??
      findLabelValue(lines, 'Merchant') ??
      findLabelValue(lines, 'Recipient');
  final receiverAccount = findLabelValue(lines, 'Receiver Account') ??
      findLabelValue(lines, 'Beneficiary Account') ??
      findLabelValue(lines, 'Till Number') ??
      findLabelValue(lines, 'Phone Number');
  final date = findLabelValue(lines, 'Transaction Date') ??
      findLabelValue(lines, 'Transaction Time');

  double? amount;
  final amountStr = findLabelValue(lines, 'Amount');
  if (amountStr != null) {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(amountStr.replaceAll(',', ''));
    if (m != null) amount = double.tryParse(m.group(1)!);
  }

  final verified = senderName != null &&
      senderAccount != null &&
      (receiverName != null || receiverAccount != null) &&
      amount != null &&
      date != null;

  return ParsedReceipt(
    verified: verified,
    senderName: senderName,
    senderAccount: senderAccount,
    receiverName: receiverName,
    receiverAccount: receiverAccount,
    amount: amount,
    date: date,
    reference: findLabelValue(lines, 'Transaction ID'),
    branch: findLabelValue(lines, 'Branch'),
    reason: findLabelValue(lines, 'Reason'),
    transactionType: findLabelValue(lines, 'Transaction Type'),
  );
}

// ===========================================================================
// CBE Birr — ASP.NET aureceipt page
// ===========================================================================

/// Parses the cbepay1.cbe.com.et aureceipt HTML.
ParsedReceipt parseCbeBirr(String html) {
  if (html.length < 500) return const ParsedReceipt(verified: false);
  final fields = extractKvFields(htmlToLines(html));
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = fields[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  final senderName = pick(['sender name', 'payer name', 'sender', 'payer']);
  final receiverName =
      pick(['receiver name', 'beneficiary name', 'receiver', 'beneficiary']);
  final amount = _toDouble(pick(['amount', 'transaction amount', 'transferred amount']));
  if (senderName == null && receiverName == null && amount == null) {
    return const ParsedReceipt(verified: false);
  }
  return ParsedReceipt(
    verified: true,
    senderName: senderName,
    receiverName: receiverName,
    senderAccount: pick(['sender account', 'payer account', 'phone', 'mobile']),
    receiverAccount: pick(['receiver account', 'beneficiary account']),
    amount: amount,
    date: pick(['date', 'transaction date', 'time']),
    reference: pick(['reference', 'transaction id', 'transaction reference', 'receipt no']),
    transactionStatus: pick(['status', 'transaction status']),
  );
}

// ===========================================================================
// eBirr platform — Siinqee, Nib, Wegagen, Ahadu, KAAFI receipts
// ===========================================================================

/// Parses a receipt.ebirr.com HTML page.
ParsedReceipt parseEbirr(String html) {
  if (html.contains('Not Found Page') || html.contains('color: red')) {
    return const ParsedReceipt(verified: false);
  }
  final fields = extractKvFields(htmlToLines(html));
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = fields[k];
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  final senderName = pick(['sender', 'payer', 'from', 'sender name', 'payer name']);
  final receiverName = pick(['receiver', 'payee', 'to', 'receiver name', 'beneficiary']);
  final amount = _toDouble(pick(['amount', 'transferred amount', 'transfer amount']));
  if (senderName == null && receiverName == null && amount == null) {
    return const ParsedReceipt(verified: false);
  }
  return ParsedReceipt(
    verified: true,
    senderName: senderName,
    receiverName: receiverName,
    senderAccount: pick(['sender account', 'from account', 'phone', 'mobile']),
    receiverAccount: pick(['receiver account', 'to account']),
    amount: amount,
    date: pick(['date', 'transaction date', 'time']),
    reference: pick(['reference', 'transaction id', 'transaction reference']),
    transactionStatus: pick(['status', 'transaction status']),
  );
}

// ===========================================================================
// Dashen — PDF receipt
// ===========================================================================

/// Extracts text from a Dashen receipt PDF and parses it.
ParsedReceipt parseDashenPdf(Uint8List bytes) {
  final text = extractPdfText(bytes);
  if (!text.contains('Dashen Bank')) return const ParsedReceipt(verified: false);
  return _parseLabeledPdf(
    text,
    labels: const [
      'Sender Name:',
      'Sender Account Number:',
      'Transaction Channel:',
      'Service Type:',
      'Narrative:',
      'Receiver Name:',
      'Receiver Account Number:',
      'Instituton Name:',
      'Transaction Reference:',
      'Transfer Reference:',
      'Transaction Date:',
      'Transaction Amount',
      'Service Charge',
      'VAT (15%):',
      'Stamp Duty',
      'Total',
    ],
    amountLabel: 'Transaction Amount',
    requiredForVerify: const ['Sender Name:', 'Receiver Name:', 'Transaction Reference:'],
    datePattern: RegExp(r'[A-Z][a-z]{2}\s+\d{1,2},\s+\d{4},?\s+\d{1,2}:\d{2}:\d{2}\s*(?:am|pm)',
        caseSensitive: false),
  );
}

// ===========================================================================
// Zemen — PDF receipt
// ===========================================================================

/// Extracts text from a Zemen receipt PDF and parses it.
ParsedReceipt parseZemenPdf(Uint8List bytes) {
  final text = extractPdfText(bytes);
  if (!text.contains('Zemen') && !text.contains('ETTB')) {
    return const ParsedReceipt(verified: false);
  }
  return _parseLabeledPdf(
    text,
    labels: const [
      'Transaction Reference:',
      'Transaction Date:',
      'Transaction Amount:',
      'Service Charge',
      'VAT',
      'Total Amount',
      'Sender Name:',
      'Sender Account:',
      'Receiver Name:',
      'Receiver Account:',
      'Receiver Bank:',
      'Narrative:',
      'Payment Reason:',
      'Status:',
      'Currency:',
    ],
    amountLabel: 'Transaction Amount:',
    requiredForVerify: const ['Transaction Reference:'],
    fallbackVerify: (values, amount) =>
        (values['Sender Name:'] != null || values['Receiver Name:'] != null) &&
        amount != null,
    datePattern: null,
  );
}

/// Generic label-position parser shared by the Dashen and Zemen PDF layouts:
/// each label's value is the text between it and the next known label.
ParsedReceipt _parseLabeledPdf(
  String text, {
  required List<String> labels,
  required String amountLabel,
  required List<String> requiredForVerify,
  bool Function(Map<String, String>, double?)? fallbackVerify,
  RegExp? datePattern,
}) {
  final values = <String, String>{};
  for (var i = 0; i < labels.length; i++) {
    final label = labels[i];
    final startIdx = text.indexOf(label);
    if (startIdx < 0) continue;
    final valueStart = startIdx + label.length;
    var valueEnd = text.length;
    for (var j = i + 1; j < labels.length; j++) {
      final nextIdx = text.indexOf(labels[j], valueStart);
      if (nextIdx >= 0) {
        valueEnd = nextIdx;
        break;
      }
    }
    values[label] = text.substring(valueStart, valueEnd).trim();
  }

  double? amount;
  final amountRaw = values[amountLabel] ?? values['Total Amount'];
  if (amountRaw != null) {
    final m = RegExp(r'(?:ETB\s*)?([0-9,]+\.\d{2})').firstMatch(amountRaw);
    if (m != null) amount = double.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  final dateRaw = values['Transaction Date:'];
  String? date;
  if (dateRaw != null && dateRaw.isNotEmpty) {
    date = dateRaw;
    if (datePattern != null) {
      final m = datePattern.firstMatch(dateRaw);
      if (m != null) date = m.group(0);
    }
  }

  final requiredOk = requiredForVerify.every((k) => (values[k] ?? '').isNotEmpty);
  final verified = amount != null && (requiredOk || (fallbackVerify?.call(values, amount) ?? false));

  return ParsedReceipt(
    verified: verified,
    senderName: values['Sender Name:'],
    senderAccount: values['Sender Account Number:'] ?? values['Sender Account:'],
    receiverName: values['Receiver Name:'],
    receiverAccount: values['Receiver Account Number:'] ?? values['Receiver Account:'],
    amount: amount,
    currency: values['Currency:'] ?? 'ETB',
    date: date,
    reference: values['Transaction Reference:'],
    branch: values['Instituton Name:'],
    reason: values['Narrative:'] ?? values['Payment Reason:'],
    transactionStatus: values['Status:'],
  );
}
