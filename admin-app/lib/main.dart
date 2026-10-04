import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_controller.dart';
import 'ui/dashboard_screen.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AdminController();
  unawaited(controller.restore());
  runApp(MahtemAdminApp(controller: controller));
}

class MahtemAdminApp extends StatelessWidget {
  const MahtemAdminApp({required this.controller, super.key});

  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mahtem Admin',
      debugShowCheckedModeBanner: false,
      theme: adminTheme(),
      home: AdminShell(controller: controller),
    );
  }
}

/// Switches between login and dashboard based on [AdminController.unlocked]:
///   null  → boot splash (session restore in flight)
///   false → login screen
///   true  → dashboard
class AdminShell extends StatelessWidget {
  const AdminShell({required this.controller, super.key});

  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final unlocked = controller.unlocked;
        if (unlocked == null) {
          if (controller.restoreFailed) {
            return _BootErrorScreen(controller: controller);
          }
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 40, color: AdminColors.border),
                  SizedBox(height: 14),
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AdminColors.emerald),
                  ),
                ],
              ),
            ),
          );
        }
        if (unlocked) {
          return DashboardScreen(controller: controller);
        }
        return LoginScreen(controller: controller);
      },
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.controller});

  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 38, color: AdminColors.faint),
              const SizedBox(height: 16),
              const Text(
                "Can't reach the Mahtem API",
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your admin key is still stored on this device. '
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.5, color: AdminColors.muted),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: controller.retryRestore,
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: controller.signOut,
                child:
                    const Text('Lock console', style: TextStyle(color: AdminColors.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
