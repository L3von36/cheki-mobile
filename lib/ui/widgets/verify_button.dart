import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The primary verification button with morphing states:
/// idle → verifying (pulsing dots + status text). When enabled it breathes
/// with a soft green glow so the main action always draws the eye.
class VerifyButton extends StatefulWidget {
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
  State<VerifyButton> createState() => _VerifyButtonState();
}

class _VerifyButtonState extends State<VerifyButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _syncGlow();
  }

  @override
  void didUpdateWidget(VerifyButton old) {
    super.didUpdateWidget(old);
    _syncGlow();
  }

  void _syncGlow() {
    final active = widget.onPressed != null || widget.loading;
    if (active && !_glow.isAnimating) {
      _glow.repeat(reverse: true);
    } else if (!active && _glow.isAnimating) {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final scheme = Theme.of(context).colorScheme;

    final bg = !enabled
        ? scheme.primary.withValues(alpha: widget.loading ? 1 : 0.35)
        : scheme.primary;
    final fg = scheme.onPrimary;

    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_glow.value);
        final glowActive = widget.onPressed != null || widget.loading;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            boxShadow: glowActive
                ? [
                    BoxShadow(
                      color: scheme.primary
                          .withValues(alpha: 0.22 + 0.20 * t),
                      blurRadius: 16 + 10 * t,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        height: 50,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: enabled ? widget.onPressed : null,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: widget.loading
                    ? _LoadingRow(hint: widget.loadingHint, color: fg)
                    : Row(
                        key: const ValueKey('idle'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user_rounded,
                              color: fg, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Verify receipt',
                            style: GoogleFonts.inter(
                              color: fg,
                              fontSize: 14,
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
                    offset: Offset(0, -4 * bounce),
                    child: Container(
                      width: 6,
                      height: 6,
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
        const SizedBox(width: 12),
        Text(
          widget.hint ?? 'Verifying…',
          style: GoogleFonts.inter(
            color: widget.color.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
