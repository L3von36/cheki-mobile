import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/fraud_advisories.dart';
import '../core/receipt_verify/models.dart';
import '../core/verify_history.dart';
import '../state/license_controller.dart';
import '../state/locale_controller.dart';
import '../state/verify_controller.dart';
import 'screens/paywall_screen.dart';
import 'screens/result_screen.dart';
import 'screens/scan_screen.dart';
import 'widgets/bank_picker_sheet.dart';

/// Shared UX flows so the shell, home screen and app bar all behave
/// identically: scan → apply → verify → ALWAYS show the result screen.

/// Pushes the full-screen scanner; if the user captures a QR payload,
/// applies it to the controller and immediately runs verification.
Future<void> openScanner(BuildContext context) async {
  final payload = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const ScanScreen()),
  );
  if (payload == null || !context.mounted) return;
  context.read<VerifyController>().applyScan(payload);
  FocusManager.instance.primaryFocus?.unfocus();
  await runVerificationFlow(context);
}

/// The FT reference printed on a CBE slip. CBE's receipt API cryptographically
/// validates its shared short codes and rejects this shape with a 500
/// "Security Alert: Invalid or tampered legacy token!" — verified live, so a
/// check against it can only fail (and still burn a licensed attempt).
final RegExp _cbePrintedReference = RegExp(r'^FT[0-9A-Za-z]{5,}$');

/// Runs the pending verification and, on ANY completed check (verified or
/// failed), slides in the result screen — users always get feedback.
///
/// Licensing gate: every verification path funnels through here. Trials
/// (or an active license) are consumed before the check runs, and an
/// exhausted trial opens the paywall first — activation resumes the check
/// the user was trying to run.
Future<void> runVerificationFlow(BuildContext context) async {
  final controller = context.read<VerifyController>();

  // ── CBE printed-number gate ───────────────────────────────────────────
  // The number the camera scanner (or the slip's print) provides for CBE is
  // the FT reference, and CBE's API cannot look it up — only the shared
  // receipt code (link / QR) verifies. Explain BEFORE running so no
  // attempt is spent on a guaranteed failure.
  if (controller.effectiveBank?.id == 'cbe' &&
      controller.scannedQr == null &&
      _cbePrintedReference.hasMatch(controller.reference.trim())) {
    final strings = context.read<LocaleController>().strings;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.cbeNeedsCodeTitle),
        content: Text(strings.cbeNeedsCodeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.ok),
          ),
        ],
      ),
    );
    return;
  }

  // ── licensing gate ────────────────────────────────────────────────────
  final license = context.read<LicenseController>();
  await license.ensureLoaded();
  if (!context.mounted) return;
  if (!license.canVerifyNow) {
    final activated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    if (activated != true || !context.mounted) return;
    final resumed = context.read<LicenseController>();
    if (!resumed.canVerifyNow) return;
    // Count the attempt BEFORE the check — attempts are charged, not
    // successes. Skipped when the form cannot run (no bank / no reference)
    // so dead taps never burn a free check.
    if (controller.canVerify) await resumed.consumeAttempt();
  } else if (controller.canVerify) {
    await license.consumeAttempt();
  }

  unawaited(HapticFeedback.mediumImpact());
  final result = await controller.verify();
  if (result == null) {
    // Couldn't even start (no bank / empty inputs) — open the picker so the
    // user can choose the bank instead of a silently disabled button.
    if (context.mounted &&
        (controller.reference.trim().isNotEmpty || controller.scannedQr != null) &&
        controller.effectiveBank == null) {
      await pickBankManually(context);
    }
    return;
  }
  if (!context.mounted) return;

  // ── local anti-fraud advisories ─────────────────────────────────────
  // Duplicate reference + stale receipt. Both are computed BEFORE the
  // check is recorded so the lookup can never see the row it triggers,
  // and both are strictly on-device (history never leaves the phone).
  String? advisory;
  if (result.ok) {
    try {
      final strings = context.read<LocaleController>().strings;
      final history = context.read<VerifyHistory>();
      final now = DateTime.now();
      final receipt = result.receipt!;
      advisory = duplicateAdvisory(
        entries: history.entries,
        bankId: controller.effectiveBank?.id ?? receipt.bankCode,
        reference: receipt.reference.isNotEmpty
            ? receipt.reference
            : controller.reference.trim(),
        now: now,
        note: strings.duplicateReceiptNote,
      );
      advisory ??= freshnessAdvisory(
        receiptDate: receipt.date,
        now: now,
        note: strings.staleReceiptNote,
      );
    } catch (_) {
      advisory = null; // advisories must never block verification
    }
  }

  // Record the check in local history (verified AND failed). The entry's
  // id travels to the result screen so a verified receipt can be given
  // a reason note right away.
  String? recordedId;
  try {
    final recorded = await context.read<VerifyHistory>().record(
          result,
          bankId: controller.effectiveBank?.id ??
              result.receipt?.bankCode ??
              '',
          bankName: result.receipt?.bankName ??
              controller.effectiveBank?.name ??
              'Bank',
          referenceFallback: controller.reference.trim(),
        );
    recordedId = recorded.id;
  } catch (_) {
    // History must never block verification.
  }
  if (advisory != null && context.mounted) {
    context.read<VerifyController>().applyAdvisoryNote(advisory);
  }

  if (result.ok) unawaited(HapticFeedback.heavyImpact());
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          ResultScreen(historyEntryId: recordedId),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    ),
  );
}

/// Opens the manual bank picker; popping with a bank selects it on the
/// controller. Returns the selected bank (or null if dismissed).
Future<BankInfo?> pickBankManually(BuildContext context) {
  final controller = context.read<VerifyController>();
  return showModalBottomSheet<BankInfo>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BankPickerSheet(selectedId: controller.effectiveBank?.id),
  ).then((bank) {
    if (bank != null) controller.selectBank(bank);
    return bank;
  });
}
