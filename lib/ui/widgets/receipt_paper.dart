import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A "thermal paper" container: rounded card with punched semicircular
/// notches on the left and right edges (classic receipt perforation).
class ReceiptPaper extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? paperColor;
  final double notchRadius;

  const ReceiptPaper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24),
    this.paperColor,
    this.notchRadius = 9,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paper = paperColor ??
        (isDark ? const Color(0xFF131519) : const Color(0xFFF8F6F0));
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Stack(
      children: [
        // Shadow card behind the punched paper.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isDark ? 0.45 : 0.08,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
        ),
        ClipPath(
          clipper: _ReceiptNotchClipper(notchRadius: notchRadius),
          child: Container(color: paper, padding: padding, child: child),
        ),
        // Punch-hole rims so the notches read as cut-outs against the bg.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _NotchRimPainter(
                notchRadius: notchRadius,
                rimColor: bg,
                paperColor: paper,
                borderColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptNotchClipper extends CustomClipper<Path> {
  final double notchRadius;
  _ReceiptNotchClipper({required this.notchRadius});

  @override
  Path getClip(Size size) {
    final r = notchRadius;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(18),
        ),
      );

    // Punch semicircles along both vertical edges.
    final punchYs = <double>[
      size.height * 0.16,
      size.height * 0.32,
      size.height * 0.48,
      size.height * 0.64,
      size.height * 0.80,
    ];
    for (final y in punchYs) {
      path.addOval(Rect.fromCircle(center: Offset(0, y), radius: r));
      path.addOval(Rect.fromCircle(center: Offset(size.width, y), radius: r));
    }
    return Path.combine(PathOperation.difference, path, Path());
  }

  @override
  bool shouldReclip(_ReceiptNotchClipper oldDelegate) =>
      oldDelegate.notchRadius != notchRadius;
}

class _NotchRimPainter extends CustomPainter {
  final double notchRadius;
  final Color rimColor;
  final Color paperColor;
  final Color borderColor;
  final double borderRadius;

  _NotchRimPainter({
    required this.notchRadius,
    required this.rimColor,
    required this.paperColor,
    required this.borderColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = notchRadius;
    // Fill the notch circles with the page background → real cut-out look.
    final fill = Paint()..color = rimColor;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = borderColor;

    final ys = <double>[
      size.height * 0.16,
      size.height * 0.32,
      size.height * 0.48,
      size.height * 0.64,
      size.height * 0.80,
    ];

    // Border of the paper.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(borderRadius),
      ),
      rim,
    );

    for (final y in ys) {
      canvas.drawCircle(Offset(0, y), r - 0.5, fill);
      canvas.drawCircle(Offset(size.width, y), r - 0.5, fill);
      canvas.drawCircle(Offset(0, y), r - 0.5, rim);
      canvas.drawCircle(Offset(size.width, y), r - 0.5, rim);
    }

    // Subtle top edge highlight.
    final highlight = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.04);
    canvas.drawLine(
      Offset(borderRadius, 0.5),
      Offset(size.width - borderRadius, 0.5),
      highlight,
    );
  }

  @override
  bool shouldRepaint(_NotchRimPainter old) =>
      old.notchRadius != notchRadius || old.rimColor != rimColor;
}

/// Rotated rubber-stamp badge ("VERIFIED" / "FAILED" / "NOT FOUND").
class StampBadge extends StatelessWidget {
  final StampKind kind;
  final String? label;

  const StampBadge({super.key, required this.kind, this.label});

  @override
  Widget build(BuildContext context) {
    final spec = switch (kind) {
      StampKind.verified => (
          const Color(0xFF2DDB6A),
          label ?? 'VERIFIED'
        ),
      StampKind.failed => (const Color(0xFFF0556A), label ?? 'FAILED'),
      StampKind.pending => (const Color(0xFFF5B049), label ?? 'NOT FOUND'),
    };
    final color = spec.$1;
    final text = spec.$2;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.6, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Transform.rotate(
        angle: -8 * math.pi / 180,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(7),
            color: color.withValues(alpha: 0.08),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

enum StampKind { verified, failed, pending }
