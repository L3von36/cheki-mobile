import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/verify_history.dart';
import '../state/verify_controller.dart';
import 'screens/result_screen.dart';
import 'screens/scan_screen.dart';
import 'widgets/bank_picker_sheet.dart';

/// Shared UX flows so the shell, home screen and app bar all behave
/// identically: scan → apply → verify → ALWAYS show the result screen.

/// Pushes the full-screen scanner; if the user captures a receipt QR,
/// applies it to the controller and immediately runs verification.
Future<void> openScanner(BuildContext context) async {
  final detection = await Navigator.of(context).push<BankDetection>(
    MaterialPageRoute(builder: (_) => const ScanScreen()),
  );
  if (detection == null || !context.mounted) return;
  context.read<VerifyController>().applyDetection(detection);
  FocusManager.instance.primaryFocus?.unfocus();
  await runVerificationFlow(context);
}

/// Runs the pending verification and, on ANY completed check (verified or
/// failed), slides in the result screen — users always get feedback.
Future<void> runVerificationFlow(BuildContext context) async {
  final controller = context.read<VerifyController>();
  unawaited(HapticFeedback.mediumImpact());
  final result = await controller.verify();
  if (result == null) {
    // Couldn't even start (no bank / empty inputs) — open the picker so the
    // user can choose the bank instead of a silently disabled button.
    if (context.mounted &&
        controller.reference.trim().isNotEmpty &&
        controller.effectiveBank == null) {
      await pickBankManually(context);
    }
    return;
  }
  if (!context.mounted) return;

  // Record the check in local history (verified AND failed).
  final bank = controller.effectiveBank;
  try {
    await context.read<VerifyHistory>().record(
          result,
          bankId: bank?.id ?? result.bank ?? '',
          bankName: bank?.name ?? result.bankName ?? (result.bank ?? 'Bank'),
          referenceFallback: controller.reference.trim(),
        );
  } catch (_) {
    // History must never block verification.
  }

  if (result.isVerified) unawaited(HapticFeedback.heavyImpact());
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
Future<MahtemBank?> pickBankManually(BuildContext context) {
  final controller = context.read<VerifyController>();
  return showModalBottomSheet<MahtemBank>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BankPickerSheet(selectedId: controller.effectiveBank?.id),
  ).then((bank) {
    if (bank != null) controller.selectBank(bank);
    return bank;
  });
}
