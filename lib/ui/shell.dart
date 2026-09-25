import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/theme_controller.dart';
import '../../theme/cheki_theme.dart';
import 'flow.dart';
import 'screens/banks_screen.dart';
import 'screens/home_screen.dart';

/// App shell — owns the bottom navigation between the verify form and the
/// bank directory, with a raised scan button between them.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _ChekiAppBar(
        onTab: () => setState(() => _tab = 0),
        showBanksTitle: _tab == 1,
      ),
      body: IndexedStack(
        index: _tab,
        children: const [HomeScreen(), BanksScreen(embedded: true)],
      ),
      bottomNavigationBar: _ChekiNavBar(
        index: _tab,
        onVerify: () => setState(() => _tab = 0),
        onScan: () => unawaited(openScanner(context)),
        onBanks: () => setState(() => _tab = 1),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── app bar

class _ChekiAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onTab;
  final bool showBanksTitle;
  const _ChekiAppBar({required this.onTab, this.showBanksTitle = false});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return AppBar(
      titleSpacing: 20,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        child: showBanksTitle
            ? Text(
                'Supported banks',
                key: const ValueKey('banks'),
                style: Theme.of(context).appBarTheme.titleTextStyle,
              )
            : GestureDetector(
                key: const ValueKey('logo'),
                onTap: onTab,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'cheki',
                      style: monoStyle(
                        size: 18,
                        weight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const _PulsingDot(),
                  ],
                ),
              ),
      ),
      actions: [
        IconButton(
          tooltip: 'Toggle theme',
          iconSize: 20,
          icon: Icon(
            themeController.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
          ),
          onPressed: themeController.toggle,
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// The little green heart-beat dot next to the logo.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: 6 + 2 * t,
          height: 6 + 2 * t,
          decoration: BoxDecoration(
            color: ChekiPalette.green.withValues(alpha: 0.55 + 0.45 * t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: ChekiPalette.green.withValues(alpha: 0.4 * t),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────── bottom bar

/// Floating capsule nav: [Verify] · (scan) · [Banks], with the scan
/// button raised like a big green "press me" arcade button.
class _ChekiNavBar extends StatelessWidget {
  final int index;
  final VoidCallback onVerify;
  final VoidCallback onScan;
  final VoidCallback onBanks;

  const _ChekiNavBar({
    required this.index,
    required this.onVerify,
    required this.onScan,
    required this.onBanks,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final surface = isDark ? ChekiPalette.dSurface : ChekiPalette.lSurface;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    Widget item({
      required int tab,
      required IconData icon,
      required IconData activeIcon,
      required String label,
      required VoidCallback onTap,
    }) {
      final active = index == tab;
      final color = active ? ChekiPalette.greenInk : dim;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active
                  ? ChekiPalette.green.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(active ? activeIcon : icon, size: 21, color: color),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.07),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              item(
                tab: 0,
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long_rounded,
                label: 'Verify',
                onTap: onVerify,
              ),
              // Center scan button.
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onScan();
                },
                child: Container(
                  width: 74,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [ChekiPalette.green, ChekiPalette.greenDark],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: ChekiPalette.green.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded,
                          color: Color(0xFF07130B), size: 24),
                      SizedBox(height: 1),
                      Text(
                        'SCAN',
                        style: TextStyle(
                          color: Color(0xFF07130B),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              item(
                tab: 1,
                icon: Icons.account_balance_outlined,
                activeIcon: Icons.account_balance_rounded,
                label: 'Banks',
                onTap: onBanks,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
