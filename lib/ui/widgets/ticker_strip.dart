import 'package:flutter/material.dart';

import '../../core/banks_registry.dart';
import '../../theme/cheki_theme.dart';

/// Receipt-style ticker tape: the supported bank names scroll by forever,
/// like the marquee on an old exchange board. Pure decoration with a
/// one-off "cheki ✓" ping when tapped.
class BankTickerStrip extends StatefulWidget {
  const BankTickerStrip({super.key});

  @override
  State<BankTickerStrip> createState() => _BankTickerStripState();
}

class _BankTickerStripState extends State<BankTickerStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faint = isDark ? ChekiPalette.dInkFaint : ChekiPalette.lInkFaint;

    final names = [
      for (final b in kChekiBanks) '${b.shortName} ✓',
    ];

    return ClipRect(
      child: SizedBox(
        height: 18,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                // Build one long string so the loop seam is invisible.
                final text = '${names.join('   ·   ')}   ·   ';
                return Stack(
                  children: [
                    for (var i = 0; i < 2; i++)
                      Positioned(
                        left: -(_controller.value * w) + i * w,
                        top: 2,
                        child: Text(
                          text,
                          maxLines: 1,
                          softWrap: false,
                          style: monoStyle(
                            size: 10,
                            color: faint,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}