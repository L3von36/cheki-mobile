import 'package:flutter/material.dart';

import '../admin_controller.dart';
import 'theme.dart';

/// Owner sign-in — email + password (v1.1.0). On a fresh deployment the
/// server has no owner yet and this screen becomes one-time setup.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.controller,
    super.key,
  });

  final AdminController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailField = TextEditingController();
  final _passwordField = TextEditingController();
  final _confirmField = TextEditingController();
  bool _obscure = true;
  bool _confirmObscure = true;

  /// False = sign in; true = first-run owner setup. Starts as sign-in and
  /// flips to setup once the server confirms no owner exists.
  bool _setupMode = false;
  bool _modeResolved = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _detectMode();
  }

  @override
  void dispose() {
    _emailField.dispose();
    _passwordField.dispose();
    _confirmField.dispose();
    super.dispose();
  }

  Future<void> _detectMode() async {
    final hasAdmin = await widget.controller.fetchHasAdmin();
    if (!mounted) return;
    setState(() {
      _modeResolved = true;
      _setupMode = hasAdmin == false;
    });
  }

  void _clearError() {
    if (_localError != null) setState(() => _localError = null);
  }

  Future<void> _submit() async {
    if (_setupMode && _passwordField.text != _confirmField.text) {
      setState(() => _localError = 'Passwords do not match.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = _setupMode
        ? await widget.controller.signUpOwner(
            _emailField.text,
            _passwordField.text,
          )
        : await widget.controller.signIn(
            _emailField.text,
            _passwordField.text,
          );
    if (!ok && mounted) {
      setState(() => _localError = widget.controller.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _localError;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C0C0E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AdminColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/seal.png',
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Mahtem Admin',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _setupMode
                          ? 'First run — create the one owner account\nfor the Mahtem verification network.'
                          : 'Owner-only analytics for the Mahtem\nreceipt verification network.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.45, color: AdminColors.muted),
                    ),
                    const SizedBox(height: 26),
                    TextField(
                      controller: _emailField,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: true,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _clearError(),
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email_rounded,
                            size: 20, color: AdminColors.faint),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordField,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        _setupMode
                            ? AutofillHints.newPassword
                            : AutofillHints.password
                      ],
                      textInputAction:
                          _setupMode ? TextInputAction.next : TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_setupMode) _submit();
                      },
                      onChanged: (_) => _clearError(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        hintText: _setupMode
                            ? 'Password (10+ characters)'
                            : 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded,
                            size: 20, color: AdminColors.faint),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: AdminColors.faint,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 16),
                      ),
                    ),
                    if (_setupMode) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmField,
                        obscureText: _confirmObscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        onChanged: (_) => _clearError(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        decoration: InputDecoration(
                          hintText: 'Confirm password',
                          prefixIcon: const Icon(Icons.lock_person_rounded,
                              size: 20, color: AdminColors.faint),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _confirmObscure = !_confirmObscure),
                            icon: Icon(
                              _confirmObscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AdminColors.faint,
                            ),
                            tooltip: _confirmObscure
                                ? 'Show password'
                                : 'Hide password',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 16),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBox(message: error),
                    ],
                    const SizedBox(height: 16),
                    ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) {
                        final busy = widget.controller.busy;
                        return FilledButton(
                          onPressed: busy ? null : _submit,
                          child: busy
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Color(0xFF052E22),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(_setupMode
                                        ? 'Creating account…'
                                        : 'Signing in…'),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _setupMode
                                          ? Icons.person_add_rounded
                                          : Icons.verified_user_outlined,
                                      size: 19,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(_setupMode
                                        ? 'Create owner account'
                                        : 'Sign in'),
                                  ],
                                ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 13, color: AdminColors.faint),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _setupMode
                                ? 'One owner account only — yours. The password is '
                                    'hashed with PBKDF2 on the server and never stored '
                                    'in plain text.'
                                : 'Your password is verified against a salted PBKDF2 '
                                    'hash. This device only keeps a 30-day session '
                                    'token for read-only analytics.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: AdminColors.faint,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: _modeResolved ? 1 : 0.4,
                      child: const Text(
                        'READ-ONLY · ZERO-KNOWLEDGE SAFE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF52525B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdminColors.rose.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.rose.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 15, color: AdminColors.rose),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: AdminColors.rose),
            ),
          ),
        ],
      ),
    );
  }
}
