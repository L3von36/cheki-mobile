import 'package:flutter/material.dart';

import '../../core/models.dart';

/// Square brand-colored tile with the bank's initials.
class BankAvatar extends StatelessWidget {
  final ChekiBank? bank;
  final double size;
  final double radius;

  const BankAvatar({super.key, required this.bank, this.size = 42, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final color = Color(bank?.colorValue ?? 0xFF9E9E9E);
    final initials = bank?.initials ?? '??';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.32,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Small rounded status chip (e.g. "Needs last 8 digits").
class MetaChip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;

  const MetaChip({super.key, required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = color ?? (isDark ? const Color(0xFF9BA0A8) : const Color(0xFF5D6167));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: base),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: base,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
