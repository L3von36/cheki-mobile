import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/verify_history.dart';
import '../../../state/auth_controller.dart';
import '../../../state/cloud_controller.dart';
import '../../../state/locale_controller.dart';
import '../../../theme/mahtem_theme.dart';
import 'auth_shared.dart';
import 'sign_in_screen.dart';

/// Create-account screen — first stop on a fresh install (no accounts on
/// the device yet). Success signs the user in and the gate swaps into
/// the shell.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _nameCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    // TextField manages its own editing state — the screen never rebuilds
    // while typing unless we listen. Without this the submit button stays
    // disabled forever even with a complete form (the "button won't tap"
    // bug): _formComplete is only re-evaluated on rebuild.
    for (final c in [_nameCtrl, _identifierCtrl, _passwordCtrl, _confirmCtrl]) {
      c.addListener(_onFormChanged);
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _identifierCtrl, _passwordCtrl, _confirmCtrl]) {
      c.removeListener(_onFormChanged);
    }
    _nameCtrl.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    final strings = context.read<LocaleController>().strings;
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = strings.errorAuth(AuthError.passwordMismatch));
      return;
    }
    setState(() => _error = null);
    // v1.14.1: an UNEXPECTED exception must never fail silently — the user
    // would see the button stop spinning and nothing else (reported as
    // "sign up doesn't create an account"). Every known failure maps to a
    // localized AuthError; anything unknown shows the generic message.
    AuthResult? result;
    try {
      result = await auth.signUp(
        displayName: _nameCtrl.text,
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
        // v1.14.0: cloud backup arms ITSELF — no settings visit, no
        // re-typed password, no button. Fire-and-forget: the shell is
        // usable immediately and a network failure stays silent (the
        // Settings sheet remains the manual fallback).
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

  bool get _formComplete =>
      _nameCtrl.text.trim().isNotEmpty &&
      _identifierCtrl.text.trim().isNotEmpty &&
      _passwordCtrl.text.isNotEmpty &&
      _confirmCtrl.text.isNotEmpty;

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
                    title: strings.createAccountTitle,
                    subtitle: strings.createAccountSubtitle,
                  ),
                  const SizedBox(height: 28),
                  AuthField(
                    controller: _nameCtrl,
                    label: strings.fullName,
                    hint: strings.fullNameHint,
                    icon: Icons.person_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 14),
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
                  ),
                  const SizedBox(height: 14),
                  AuthField(
                    controller: _confirmCtrl,
                    label: strings.confirmPasswordLabel,
                    hint: strings.passwordHint,
                    icon: Icons.lock_reset_outlined,
                    obscure: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    AuthErrorBox(message: _error!),
                  ],
                  const SizedBox(height: 20),
                  AuthSubmitButton(
                    label: strings.createAccountButton,
                    busy: auth.isBusy,
                    onTap: auth.isBusy || !_formComplete ? null : _submit,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Flexible: long localized prompts wrap instead of
                      // painting overflow stripes on narrow phones.
                      Flexible(
                        child: Text(
                          strings.haveAccountPrompt,
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
                                      builder: (_) => const SignInScreen(),
                                    ),
                                  ),
                        child: Text(
                          strings.signInLink,
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
