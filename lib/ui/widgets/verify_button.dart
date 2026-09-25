import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The primary verification button with morphing states:
/// idle → verifying (pulsing dots + status text) → success check / error.
class VerifyButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final bool success;
  final String? loadingHint;

  const VerifyButton({
    super.key,
    required this.onPressed,
    required this.loading,
    this.success = false,
    this.loadingHint,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final scheme = Theme.of(context).colorScheme;

    final bg = !enabled
        ? scheme.primary.withValues(alpha: loading ? 1 : 0.35)
        : scheme.primary;
    final fg = scheme.onPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: 58,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: loading
                  ? _LoadingRow(hint: loadingHint, color: fg)
                  : Row(
                      key: const ValueKey('idle'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_rounded,
                            color: fg, size: 21),
                        const SizedBox(width: 10),
                        Text(
                          'Verify receipt',
                          style: GoogleFonts.inter(
                            color: fg,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
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

class _LoadingRow extends StatefulWidget {
  final String? hint;
  final Color color;
  const _LoadingRow({required this.color, this.hint});

  @override
  State<_LoadingRow> createState() => _LoadingRowState();
}

class _LoadingRowState extends State<_LoadingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Row(
              children: List.generate(3, (i) {
                final t =
                    ((_c.value * 3 - i).abs() % 3) / 3.0;
                final bounce = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.translate(
                    offset: Offset(0, -5 * bounce),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(
                          alpha: 0.45 + 0.55 * bounce,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        const SizedBox(width: 14),
        Text(
          widget.hint ?? 'Verifying…',
          style: GoogleFonts.inter(
            color: widget.color.withValues(alpha: 0.9),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
