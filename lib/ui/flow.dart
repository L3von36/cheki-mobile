import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../state/verify_controller.dart';
import 'screens/result_screen.dart';
import 'screens/scan_screen.dart';

/// Shared UX flows so the shell, home screen and app bar all behave
/// identically: scan → apply → verify → show result ticket.

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

/// Runs the pending verification and, on success, slides in the result
/// receipt. Fires haptics along the way.
Future<void> runVerificationFlow(BuildContext context) async {
  final controller = context.read<VerifyController>();
  unawaited(HapticFeedback.mediumImpact());
  final result = await controller.verify();
  if (!context.mounted) return;
  if (result != null && result.success) {
    unawaited(HapticFeedback.heavyImpact());
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
}
