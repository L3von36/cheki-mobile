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
    final messenger = ScaffoldMessenger.of(context);
    final cloud = context.read<CloudController>();
    final history = context.read<VerifyHistory>();
    final navigator = Navigator.of(context);
    final password = _passwordCtrl.text;

    if (password != _confirmCtrl.text) {
      setState(() => _error = strings.errorAuth(AuthError.passwordMismatch));
      return;
    }
    setState(() => _error = null);

    AuthResult? result;
    try {
      result = await auth.signUp(
        displayName: _nameCtrl.text,
        identifier: _identifierCtrl.text,
        password: password,
      );
    } catch (_) {
      result = null;
    }

    switch (result) {
      case AuthSuccess(:final account):
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: MahtemPalette.green,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.accountCreatedSuccess,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        if (navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
        unawaited(
          cloud.autoEnable(
            password: password,
            account: account,
            history: history,
          ),
        );
      case AuthFailure(:final error):
        if (mounted) setState(() => _error = strings.errorAuth(error));
      case null:
        if (mounted) setState(() => _error = strings.genericAuthError);
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
                            : () => Navigator.of(context).push<void>(
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
