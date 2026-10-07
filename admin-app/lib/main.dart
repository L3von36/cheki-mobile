import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_controller.dart';
import 'ui/dashboard_screen.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

const _themeModeKey = 'theme_mode';

/// Global theme mode notifier — initialised in main() after loading prefs.
late final ThemeModeNotifier themeModeNotifier;

/// Loads the saved theme mode (defaults to dark).
Future<ThemeMode> _loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final index = prefs.getInt(_themeModeKey) ?? 1; // 0=light, 1=dark, 2=system
  return ThemeMode.values[index];
}

/// Saves the theme mode.
Future<void> _saveThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_themeModeKey, mode.index);
}

class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  ThemeModeNotifier(super.value);

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    await _saveThemeMode(mode);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Any build-time failure lands in the details of a calm error card
  // instead of a grey screen — release builds too.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (details) => Material(
        color: const Color(0xFF09090B),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.report_problem_outlined,
                      color: Color(0xFFF43F5E), size: 34),
                  const SizedBox(height: 10),
                  const Text('Something went wrong',
                      style: TextStyle(
                          color: Color(0xFFF4F4F5),
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                    details.exceptionAsString(),
                    style: const TextStyle(
                        color: Color(0xFFA1A1AA), fontSize: 11.5, height: 1.4),
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  final controller = AdminController();
  unawaited(controller.restore());
  final themeMode = await _loadThemeMode();
  themeModeNotifier = ThemeModeNotifier(themeMode);
  runApp(MahtemAdminApp(controller: controller));
}

class MahtemAdminApp extends StatelessWidget {
  const MahtemAdminApp({required this.controller, super.key});

  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Mahtem Admin',
          debugShowCheckedModeBanner: false,
          theme: adminLightTheme(),
          darkTheme: adminTheme(),
          themeMode: mode,
          home: AdminShell(controller: controller),
        );
      },
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
                'Your session is still stored on this device. '
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
