import 'package:flutter/material.dart';

import '../admin_controller.dart';
import 'theme.dart';

/// Owner login — the ADMIN_KEY unlocks the console and stays on-device.
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
  final _keyField = TextEditingController();
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await widget.controller.unlock(_keyField.text);
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
                  const Text(
                    'Owner-only analytics for the Mahtem\nreceipt verification network.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: AdminColors.muted),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _keyField,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) {
                      if (_localError != null) setState(() => _localError = null);
                    },
                    style: const TextStyle(
                      fontSize: 14,
                      letterSpacing: 0.6,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      hintText: 'Paste your ADMIN_KEY',
                      prefixIcon: const Icon(Icons.key_rounded,
                          size: 20, color: AdminColors.faint),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                          color: AdminColors.faint,
                        ),
                        tooltip: _obscure ? 'Show key' : 'Hide key',
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    ),
                  ),
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
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Color(0xFF052E22),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Verifying key…'),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.verified_user_outlined, size: 19),
                                  SizedBox(width: 8),
                                  Text('Unlock dashboard'),
                                ],
                              ),
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 13, color: AdminColors.faint),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'The key stays in this device only and is sent '
                          'exclusively to the Mahtem API to authorize '
                          'read-only analytics.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: AdminColors.faint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'READ-ONLY · ZERO-KNOWLEDGE SAFE',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2.4,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF52525B),
                    ),
                  ),
                ],
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
