/// Shared building blocks for the sign-in and create-account screens:
/// brand header, gradient submit button, error box and privacy note —
/// so both screens look unmistakably like the same app.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/locale_controller.dart';
import '../../../theme/mahtem_theme.dart';
import '../../widgets/pressable.dart';

/// Brand header: gradient logo mark, app name, then the screen's
/// title + subtitle.
class AuthHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const AuthHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: MahtemPalette.splashGradient),
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Mahtem',
              style: TextStyle(
                color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          title,
          style: TextStyle(
            color: isDark ? MahtemPalette.dInk : MahtemPalette.lInk,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// The green gradient submit button ("SIGN IN" / "CREATE ACCOUNT").
/// Shows a spinner while [busy] and ignores taps.
class AuthSubmitButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onTap != null && !busy;
    final disabledFill = isDark
        ? MahtemPalette.dCardAlt
        : MahtemPalette.lBorder;
    return Pressable(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: MahtemPalette.buttonGradient)
              : null,
          color: enabled ? null : disabledFill,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x332CB168),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? Colors.white
                      : (isDark
                            ? MahtemPalette.dInkFaint
                            : MahtemPalette.lInkFaint),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
      ),
    );
  }
}

/// Soft red error box shown above the submit button after a failed
/// attempt.
class AuthErrorBox extends StatelessWidget {
  final String message;

  const AuthErrorBox({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MahtemPalette.redSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MahtemPalette.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: MahtemPalette.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: MahtemPalette.red,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom privacy note: a lock icon plus the "device-only" reassurance.
class AuthPrivacyNote extends StatelessWidget {
  const AuthPrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strings = context.watch<LocaleController>().strings;
    return Row(
      children: [
        Icon(
          Icons.verified_user_outlined,
          color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
          size: 15,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            strings.authPrivacyNote,
            style: TextStyle(
              color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
              fontSize: 10.5,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

/// Labeled text field styled for the auth screens.
class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscure;
  final String? errorText;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.errorText,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strings = context.watch<LocaleController>().strings;
    final fill = isDark ? MahtemPalette.dCard : Colors.white;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            widget.label,
            style: TextStyle(
              color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        TextField(
          controller: widget.controller,
          obscureText: widget.obscure && !_revealed,
          onSubmitted: widget.onSubmitted,
          textInputAction: TextInputAction.next,
          textCapitalization: widget.textCapitalization,
          autofillHints: widget.obscure
              ? const [AutofillHints.password, AutofillHints.newPassword]
              : const [
                  AutofillHints.username,
                  AutofillHints.email,
                  AutofillHints.telephoneNumberNational,
                ],
          style: TextStyle(
            color: isDark ? MahtemPalette.dInk : MahtemPalette.lInk,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            hintStyle: TextStyle(
              color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
              fontSize: 12,
            ),
            prefixIcon: Icon(
              widget.icon,
              size: 18,
              color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _revealed
                        ? strings.hidePassword
                        : strings.showPassword,
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 17,
                      color: isDark
                          ? MahtemPalette.dInkDim
                          : MahtemPalette.lInkDim,
                    ),
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: MahtemPalette.green,
                width: 1.6,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: MahtemPalette.red,
                width: 1.3,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: MahtemPalette.red,
                width: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
