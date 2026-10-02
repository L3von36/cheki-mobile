import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/mahtem_theme.dart';
import '../../shell.dart';
import '../../../state/auth_controller.dart';
import '../../../state/locale_controller.dart';
import 'create_account_screen.dart';
import 'sign_in_screen.dart';

/// Decides what the app opens on: the shell when a valid session exists,
/// otherwise sign-in (or create-account on a fresh install). Listens to
/// [AuthController] — sign-in / sign-out swap screens without any
/// navigation code.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    if (!auth.isLoaded) {
      return const _GateSplash();
    }
    if (auth.isSignedIn) {
      return const ShellScreen();
    }
    if (!auth.hasAccounts) {
      return const CreateAccountScreen();
    }
    return const SignInScreen();
  }
}

/// Branded mini-splash while accounts load from secure storage — usually
/// a single frame on warm starts.
class _GateSplash extends StatelessWidget {
  const _GateSplash();

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? MahtemPalette.dBg : MahtemPalette.lBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/brand_seal.png',
              width: 64,
              height: 64,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: isDark ? MahtemPalette.dInkDim : MahtemPalette.green,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              strings.loading,
              style: TextStyle(
                color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
