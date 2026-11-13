import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/verify_history.dart';
import '../../../state/auth_controller.dart';
import '../../../state/cloud_controller.dart';
import '../../../state/license_controller.dart';
import '../../../state/locale_controller.dart';
import '../../../theme/mahtem_theme.dart';
import 'auth_shared.dart';
import 'create_account_screen.dart';
import 'github_sign_in_sheet.dart';

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

  /// Post-sign-in work indicator: sign-in → vault arming + sync. While
  /// set, the button stays busy and the progress line tells the user
  /// the app is working — on a slow connection (or the second-device
  /// cloud lookup) the wait otherwise reads as a freeze.
  String? _progress;

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
    setState(() {
      _error = null;
      _progress = strings.signingIn;
    });
    // v1.14.1: an UNEXPECTED exception must never fail silently — the user
    // would see the button stop spinning and nothing else (reported as
    // "sign in doesn't create an account"). Known failures map to
    // localized AuthErrors; anything unknown shows the generic message.
    final cloud = context.read<CloudController>();
    final license = context.read<LicenseController>();
    final history = context.read<VerifyHistory>();
    final navigator = Navigator.of(context);
    final password = _passwordCtrl.text;

    AuthResult? result;
    try {
      result = await auth.signIn(
        identifier: _identifierCtrl.text,
        password: password,
      );
    } catch (_) {
      result = null;
    }

    switch (result) {
      case AuthSuccess(:final account):
        // Vault arming and the trial refresh ride on the network — keep
        // the progress line up until they finish (same on-device freeze
        // report as the create-account screen).
        if (mounted) setState(() => _progress = strings.preparingAccount);
        await cloud.autoEnable(
          password: password,
          account: account,
          history: history,
        );
        await license.refreshTrialBudget();
        if (navigator.canPop()) {
          navigator.popUntil((route) => route.isFirst);
        }
      case AuthFailure(:final error):
        if (error == AuthError.githubRequired && mounted) {
          // GitHub-provisioned accounts can't re-prove a password —
          // send the user straight into the device flow.
          setState(() => _progress = null);
          await _githubSignIn();
          return;
        }
        if (mounted) {
          setState(() {
            _progress = null;
            _error = strings.errorAuth(error);
          });
        }
      case null:
        if (mounted) {
          setState(() {
            _progress = null;
            _error = strings.genericAuthError;
          });
        }
    }
  }

  /// GitHub device-flow sign-in. On success the same post-sign-in work
  /// runs, minus vault arming — GitHub accounts have no password to
  /// derive the vault key from (backup can be enabled from settings).
  Future<void> _githubSignIn() async {
    final license = context.read<LicenseController>();
    final navigator = Navigator.of(context);
    final result = await showGitHubSignIn(context);
    if (result is AuthSuccess) {
      await license.refreshTrialBudget();
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    } else if (result is AuthFailure && mounted) {
      setState(() =>
          _error = context.read<LocaleController>().strings.errorAuth(result.error));
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
    final busy = auth.isBusy || _progress != null;

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
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [
                      AutofillHints.telephoneNumberNational,
                    ],
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
                        onTap: busy ? null : _forgotPassword,
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
                    busy: busy,
                    onTap: busy ||
                            _identifierCtrl.text.trim().isEmpty ||
                            _passwordCtrl.text.isEmpty
                        ? null
                        : _submit,
                  ),
                  if (_progress != null) ...[
                    const SizedBox(height: 12),
                    AuthProgressLine(message: _progress!),
                  ],
                  const SizedBox(height: 12),
                  AuthGithubButton(
                    onTap: auth.isBusy ? null : _githubSignIn,
                  ),
                  const SizedBox(height: 14),
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
                        onTap: busy
                            ? null
                            : () => Navigator.of(context).push<void>(
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
