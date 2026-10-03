import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/verify_history.dart';
import '../../../state/auth_controller.dart';
import '../../../state/cloud_controller.dart';
import '../../../state/locale_controller.dart';
import '../../../theme/mahtem_theme.dart';
import 'auth_shared.dart';
import 'create_account_screen.dart';

/// Sign-in screen — the gate's default stop once at least one account
/// exists on the device. Success swaps the gate into the shell.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Same rebuild-on-keystroke wiring as the create-account screen —
    // otherwise the sign-in button never enables while typing.
    _identifierCtrl.addListener(_onFormChanged);
    _passwordCtrl.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _identifierCtrl.removeListener(_onFormChanged);
    _passwordCtrl.removeListener(_onFormChanged);
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    final strings = context.read<LocaleController>().strings;
    setState(() => _error = null);
    // v1.14.1: an UNEXPECTED exception must never fail silently — the user
    // would see the button stop spinning and nothing else (reported as
    // "sign in doesn't create an account"). Known failures map to
    // localized AuthErrors; anything unknown shows the generic message.
    AuthResult? result;
    try {
      result = await auth.signIn(
        identifier: _identifierCtrl.text,
        password: _passwordCtrl.text,
      );
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    if (result == null) {
      setState(() => _error = strings.genericAuthError);
      return;
    }
    switch (result) {
      case AuthSuccess(:final account):
        // The gate rebuilds into the shell; clear any pushed auth route.
        Navigator.of(context).popUntil((route) => route.isFirst);
        // v1.14.0: cloud backup arms ITSELF — signing in on a new device
        // pulls the cloud copy down with zero user action. Fire-and-
        // forget: a network failure stays silent; the Settings sheet
        // remains the manual fallback.
        unawaited(
          context.read<CloudController>().autoEnable(
                password: _passwordCtrl.text,
                account: account,
                history: context.read<VerifyHistory>(),
              ),
        );
      case AuthFailure(:final error):
        setState(() => _error = strings.errorAuth(error));
    }
  }

  Future<void> _forgotPassword() async {
    final auth = context.read<AuthController>();
    final strings = context.read<LocaleController>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.resetAccountsTitle),
        content: Text(strings.resetAccountsBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: MahtemPalette.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.resetAccountsConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await auth.resetAccounts();
      // The gate now shows the create-account screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkDim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;

    return Scaffold(
      backgroundColor: isDark ? MahtemPalette.dBg : MahtemPalette.lBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthHeader(
                    title: strings.welcomeBack,
                    subtitle: strings.signInSubtitle,
                  ),
                  const SizedBox(height: 28),
                  AuthField(
                    controller: _identifierCtrl,
                    label: strings.identifierLabel,
                    hint: strings.identifierHint,
                    icon: Icons.alternate_email_rounded,
                  ),
                  const SizedBox(height: 14),
                  AuthField(
                    controller: _passwordCtrl,
                    label: strings.passwordLabel,
                    hint: strings.passwordHint,
                    icon: Icons.lock_outline_rounded,
                    obscure: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10, left: 4),
                      child: GestureDetector(
                        onTap: auth.isBusy ? null : _forgotPassword,
                        child: Text(
                          strings.forgotPassword,
                          style: const TextStyle(
                            color: MahtemPalette.blue,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AuthErrorBox(message: _error!),
                  ],
                  const SizedBox(height: 20),
                  AuthSubmitButton(
                    label: strings.signInButton,
                    busy: auth.isBusy,
                    onTap:
                        auth.isBusy ||
                            _identifierCtrl.text.trim().isEmpty ||
                            _passwordCtrl.text.isEmpty
                        ? null
                        : _submit,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Flexible: long localized prompts wrap instead of
                      // painting overflow stripes on narrow phones.
                      Flexible(
                        child: Text(
                          strings.noAccountPrompt,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: inkDim, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: auth.isBusy
                            ? null
                            : () => Navigator.of(context)
                                  .pushReplacement<void, void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const CreateAccountScreen(),
                                    ),
                                  ),
                        child: Text(
                          strings.createAccountLink,
                          style: const TextStyle(
                            color: MahtemPalette.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const AuthPrivacyNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
