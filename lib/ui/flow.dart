import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/receipt_verify/models.dart';
import '../core/verify_history.dart';
import '../state/license_controller.dart';
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

/// Runs the pending verification and, on ANY completed check (verified or
/// failed), slides in the result screen — users always get feedback.
///
/// Licensing gate: every verification path funnels through here. Trials
/// (or an active license) are consumed before the check runs, and an
/// exhausted trial opens the paywall first — activation resumes the check
/// the user was trying to run.
Future<void> runVerificationFlow(BuildContext context) async {
  final controller = context.read<VerifyController>();

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

  // Record the check in local history (verified AND failed).
  try {
    await context.read<VerifyHistory>().record(
          result,
          bankId: controller.effectiveBank?.id ??
              result.receipt?.bankCode ??
              '',
          bankName: result.receipt?.bankName ??
              controller.effectiveBank?.name ??
              'Bank',
          referenceFallback: controller.reference.trim(),
        );
  } catch (_) {
    // History must never block verification.
  }

  if (result.ok) unawaited(HapticFeedback.heavyImpact());
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const ResultScreen(),
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
