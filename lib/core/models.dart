/// Cheki core models — mirrors the JSON contract of the cheki REST API
/// (https://chekiapp.vercel.app) plus the bank registry entry shape.
library;

/// Result of a single receipt verification (`POST /api/verify`).
class VerifyResult {
  /// Whether the API request itself succeeded at the HTTP level.
  final bool success;

  /// Whether the receipt was found and verified as legitimate.
  final bool? verified;

  /// Bank code, e.g. `cbe`, `telebirr`.
  final String? bank;

  /// Bank display name returned by the API, e.g. `Commercial Bank of Ethiopia`.
  final String? bankName;

  /// Transaction reference number.
  final String? reference;

  /// The bank endpoint URL the receipt was fetched from.
  final String? sourceUrl;

  final String? senderName;
  final String? senderAccount;
  final String? receiverName;
  final String? receiverAccount;

  final double? amount;
  final String? currency;
  final String? date;
  final String? branch;

  /// Failure reason when [verified] is false.
  final String? reason;

  /// Server-side verification duration in milliseconds.
  final int? durationMs;

  // Wallet-specific fields (Telebirr, CBE Birr, eBirr...).
  final String? invoiceNumber;
  final String? transactionStatus;
  final double? settledAmount;
  final double? stampDuty;
  final double? serviceFee;
  final double? serviceFeeVat;
  final double? totalPaid;
  final String? amountInWords;
  final String? paymentMode;
  final String? paymentChannel;

  /// API error message when [success] is false.
  final String? error;

  /// Fallback URL hint for geo-blocked banks (telebirr / M-Pesa).
  final String? fallbackUrl;

  const VerifyResult({
    required this.success,
    this.verified,
    this.bank,
    this.bankName,
    this.reference,
    this.sourceUrl,
    this.senderName,
    this.senderAccount,
    this.receiverName,
    this.receiverAccount,
    this.amount,
    this.currency,
    this.date,
    this.branch,
    this.reason,
    this.durationMs,
    this.invoiceNumber,
    this.transactionStatus,
    this.settledAmount,
    this.stampDuty,
    this.serviceFee,
    this.serviceFeeVat,
    this.totalPaid,
    this.amountInWords,
    this.paymentMode,
    this.paymentChannel,
    this.error,
    this.fallbackUrl,
  });

  factory VerifyResult.fromJson(Map<String, dynamic> json) {
    return VerifyResult(
      success: json['success'] as bool? ?? false,
      verified: json['verified'] as bool?,
      bank: json['bank'] as String?,
      bankName: json['bankName'] as String?,
      reference: json['reference'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      senderName: json['senderName'] as String?,
      senderAccount: json['senderAccount'] as String?,
      receiverName: json['receiverName'] as String?,
      receiverAccount: json['receiverAccount'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      currency: json['currency'] as String?,
      date: json['date'] as String?,
      branch: json['branch'] as String?,
      reason: json['reason'] as String?,
      durationMs: json['durationMs'] as int?,
      invoiceNumber: json['invoiceNumber'] as String?,
      transactionStatus: json['transactionStatus'] as String?,
      settledAmount: (json['settledAmount'] as num?)?.toDouble(),
      stampDuty: (json['stampDuty'] as num?)?.toDouble(),
      serviceFee: (json['serviceFee'] as num?)?.toDouble(),
      serviceFeeVat: (json['serviceFeeVat'] as num?)?.toDouble(),
      totalPaid: (json['totalPaid'] as num?)?.toDouble(),
      amountInWords: json['amountInWords'] as String?,
      paymentMode: json['paymentMode'] as String?,
      paymentChannel: json['paymentChannel'] as String?,
      error: json['error'] as String?,
      fallbackUrl: json['fallbackUrl'] as String?,
    );
  }

  /// True when the receipt was fetched and its data extracted successfully.
  bool get isVerified => verified == true;
}

/// Error thrown by [ChekiClient] for network/API failures.
class ChekiException implements Exception {
  final String message;
  final int? statusCode;

  /// Direct receipt URL (geo-blocked banks) the user can open in a browser.
  final String? fallbackUrl;

  const ChekiException(this.message, {this.statusCode, this.fallbackUrl});

  /// User-friendly version of the message for snackbars / error cards.
  String get friendly {
    final code = statusCode;
    if (code == null) return message;
    if (code == 404) return 'Receipt not found. Double-check the reference.';
    if (code == 400) return message;
    if (code == 429) return 'Too many requests. Wait a moment and try again.';
    if (code >= 500) return 'Bank endpoint unavailable. Try again shortly.';
    return message;
  }

  @override
  String toString() =>
      'ChekiException($message${statusCode != null ? ', status: $statusCode' : ''})';
}

/// The kind of financial institution.
enum BankType { bank, wallet, mobile }

/// A static registry entry describing one supported bank/wallet.
class ChekiBank {
  final String id;
  final String name;
  final String shortName;
  final BankType type;

  /// Whether verification requires (part of) the receiving account number.
  final bool requiresAccount;

  /// Human label for the account field, e.g. "Receiving account number".
  final String accountLabel;

  /// How many trailing account digits are required (CBE: 8, BOA: 5).
  final int? accountDigits;

  /// Whether verification requires the sender phone number.
  final bool requiresPhone;

  /// Whether the bank endpoint is geo-restricted (handled server-side).
  final bool geoBlocked;

  /// Brand color (from the cheki manifest) used for the bank avatar.
  final int colorValue;

  /// Short initials rendered inside the colored avatar.
  final String initials;

  /// Description of the reference format shown as helper text.
  final String referenceFormat;

  /// Example reference shown as input hint.
  final String referenceExample;

  /// Integration notes (geo-blocking, quirks, etc.).
  final String notes;

  const ChekiBank({
    required this.id,
    required this.name,
    required this.shortName,
    required this.type,
    required this.requiresAccount,
    required this.accountLabel,
    required this.accountDigits,
    required this.requiresPhone,
    required this.geoBlocked,
    required this.colorValue,
    required this.initials,
    required this.referenceFormat,
    required this.referenceExample,
    required this.notes,
  });

  bool get isLive => true;

  /// Short badge list for the Banks screen.
  List<String> get badges => [
        if (requiresAccount && accountDigits != null)
          'Needs last $accountDigits digits',
        if (requiresPhone) 'Needs phone number',
        if (geoBlocked) 'Geo-restricted endpoint',
      ];
}

/// A receipt detected from a URL, QR payload, or raw reference text.
///
/// [bank] is null for generic QR payloads we cannot attribute to a bank —
/// the flow then asks the user to pick one before verifying.
class BankDetection {
  final String? bank;
  final String reference;

  /// Account suffix parsed from CBE/BOA receipt URLs.
  final String? accountNumber;

  const BankDetection({
    required this.bank,
    required this.reference,
    this.accountNumber,
  });

  @override
  String toString() =>
      'BankDetection(bank: $bank, reference: $reference, account: $accountNumber)';
}
