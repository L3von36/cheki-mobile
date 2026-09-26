/// Self-activation — the app verifies its own purchase.
///
/// The user pays the plan price via Telebirr to the owner's account
/// (`paywall_config.dart`), then pastes the Telebirr receipt number into
/// the paywall. The app runs THAT receipt through its own verification
/// engine (the same `ReceiptVerifier` used for customer receipts) and
/// unlocks itself when the receipt is genuine and matches the plan:
///
///   * the receipt exists at Telebirr (verified live),
///   * the transaction completed successfully,
///   * the settled amount equals a plan price exactly (150 / 1200 ETB),
///   * the money went to the owner (credited account digits or name),
///   * the receipt is fresh (paid within the last few days).
///
/// Everything here is pure logic so it can be unit-tested without network.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import '../receipt_verify/models.dart';
import 'paywall_config.dart';

/// Outcome of checking one receipt against the activation rules.
sealed class ReceiptActivation {
  const ReceiptActivation();
}

/// The receipt is a genuine plan payment — the controller grants
/// [planDays] on top of the current entitlement.
class ReceiptActivationAccepted extends ReceiptActivation {
  final double amountEtb;
  final int planDays;
  const ReceiptActivationAccepted({required this.amountEtb, required this.planDays});
}

/// Telebirr verified the receipt, but it is NOT a valid plan payment.
class ReceiptActivationRejected extends ReceiptActivation {
  final String message;
  const ReceiptActivationRejected(this.message);
}

/// The check could not complete (network / Telebirr unreachable) — the
/// user may simply retry. Carries the engine's own failure with its
/// user-ready copy and tips.
class ReceiptActivationError extends ReceiptActivation {
  final VerifyFailure failure;
  const ReceiptActivationError(this.failure);
}

/// Final controller verdict: the receipt activated (or confirmed) a plan
/// until [expiryUtc].
class ReceiptActivationSuccess extends ReceiptActivation {
  final DateTime expiryUtc;
  final double amountEtb;
  final int planDays;

  /// True when the same receipt was submitted while its plan is still
  /// running — nothing changed, the user just sees the current expiry.
  final bool alreadyActive;
  const ReceiptActivationSuccess({
    required this.expiryUtc,
    required this.amountEtb,
    required this.planDays,
    required this.alreadyActive,
  });
}

/// The plan prices that unlock the app, with their durations in days.
const Map<int, int> kPlanPricesEtb = {
  kMonthlyPriceEtb: kMonthlyPlanDays,
  kYearlyPriceEtb: kYearlyPlanDays,
};

/// Exact (± half a cent) match against the plan price table.
int? planDaysForAmount(double? amount) {
  if (amount == null) return null;
  for (final entry in kPlanPricesEtb.entries) {
    if ((amount - entry.key).abs() < 0.005) return entry.value;
  }
  return null;
}

/// Telebirr stamps receipts in Ethiopia local time (UTC+3, no DST) as
/// `dd-MM-yyyy HH:mm:ss`. Returns that instant in UTC, or null when the
/// text does not carry a parseable stamp.
DateTime? parseTelebirrReceiptDate(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'(\d{2})-(\d{2})-(\d{4})\s+(\d{2}):(\d{2}):(\d{2})')
      .firstMatch(raw.trim());
  if (m == null) return null;
  final wall = DateTime.utc(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
  return wall.subtract(const Duration(hours: 3));
}

/// A credited account "ends with" the owner's digits (receipts may show
/// `989680816`, `+251989680816` or `251989680816` — all end the same).
bool accountEndsWithOwnerDigits(String? account) {
  if (account == null) return false;
  final digits = account.replaceAll(RegExp(r'\D'), '');
  return digits.endsWith(kPayTelebirrDigits);
}

/// Lenient name comparison — receipts may shout the name, add extra
/// words, or shuffle spacing.
bool receiverNameMatchesOwner(String? receiverName) {
  if (receiverName == null) return false;
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  final receiver = norm(receiverName);
  final owner = norm(kPayTelebirrName);
  if (receiver.isEmpty || owner.isEmpty) return false;
  return receiver.contains(owner);
}

bool _statusLooksFailed(String? status) {
  if (status == null) return false;
  final s = status.toLowerCase();
  return s.contains('fail') ||
      s.contains('cancel') ||
      s.contains('revers') ||
      s.contains('pend');
}

String _fmtAmount(double amount) =>
    amount == amount.roundToDouble() ? '${amount.round()}' : '$amount';

/// Checks a VERIFIED Telebirr receipt against the activation rules.
/// Network failures never reach here — the controller maps them first.
ReceiptActivation evaluateActivationReceipt(
  ReceiptData receipt, {
  required DateTime now,
}) {
  if (receipt.bankCode != 'telebirr') {
    return const ReceiptActivationRejected(
        'Only Telebirr payment receipts can activate Mahtem Pro.');
  }
  if (_statusLooksFailed(receipt.transactionStatus)) {
    return const ReceiptActivationRejected(
        'That Telebirr transaction did not complete — no activation.');
  }

  final days = planDaysForAmount(receipt.amount);
  if (days == null) {
    return ReceiptActivationRejected(
      'This receipt is for ${_fmtAmount(receipt.amount ?? 0)} ETB — activation '
      'needs exactly $kMonthlyPriceEtb ETB (1 month) or $kYearlyPriceEtb ETB '
      '(1 year) sent to $kPayTelebirrNumber.',
    );
  }

  final receiverOk = accountEndsWithOwnerDigits(receipt.receiverAccount) ||
      receiverNameMatchesOwner(receipt.receiverName);
  if (!receiverOk) {
    return ReceiptActivationRejected(
      'This payment was not sent to $kPayTelebirrName ($kPayTelebirrNumber). '
      'Pay the plan price to that account and paste the new receipt.',
    );
  }

  // Freshness is only enforced when the receipt carries a parseable stamp —
  // never reject a paying user over a missing date alone.
  final paidAt = parseTelebirrReceiptDate(receipt.date);
  if (paidAt != null) {
    final age = now.difference(paidAt);
    if (age > const Duration(days: kActivationReceiptMaxAgeDays)) {
      return ReceiptActivationRejected(
        'This receipt is more than $kActivationReceiptMaxAgeDays days old. '
        'Pay again and use the fresh receipt from the new SMS.',
      );
    }
  }

  return ReceiptActivationAccepted(amountEtb: receipt.amount!, planDays: days);
}

/// Stable identifier for an activation receipt: SHA-256 over the invoice
/// number, hex-encoded. Stored device-side so one receipt cannot grant a
/// second month after its plan expires.
String receiptHashFor(String referenceKey) {
  final digest = SHA256Digest().process(
    Uint8List.fromList(utf8.encode('mahtem-receipt-v1:$referenceKey')),
  );
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Normalizes a receipt number for [receiptHashFor] — upper-case, no
/// spaces, no URL decoration.
String normalizeReceiptReference(String raw) =>
    raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
