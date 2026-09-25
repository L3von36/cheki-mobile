import 'package:flutter/material.dart';

import '../../core/receipt_verify/models.dart';

/// Brand colors for the stylepos bank catalog ids.
const Map<String, int> _kBankColors = {
  'telebirr': 0xFF00A0DC,
  'cbe': 0xFF502878,
  'boa': 0xFF0E4D92,
  'mpesa': 0xFF00A651,
  'dashen': 0xFF0066B3,
  'awash': 0xFF1266A2,
  'zemen': 0xFF2F5D8C,
  'cbebirr': 0xFF9C27B0,
  'siinqee': 0xFF7B1FA2,
  'ebirr': 0xFF00897B,
  'cbe-legacy': 0xFF502878,
};

/// Square brand-colored tile with the bank's initials.
class BankAvatar extends StatelessWidget {
  final BankInfo? bank;
  final double size;
  final double radius;

  const BankAvatar({super.key, required this.bank, this.size = 42, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final color = Color(bank == null ? 0xFF9E9E9E : (_kBankColors[bank!.id] ?? 0xFF546E7A));
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

/// Small rounded status chip.
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
