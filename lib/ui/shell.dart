import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/verify_history.dart';
import '../theme/mahtem_theme.dart';
import 'flow.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';

/// App shell — two tabs (Verify / History) with a raised center scan button
/// that opens the full-screen scanner. Nothing else competes for attention.
class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final history = context.watch<VerifyHistory>().entries.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? MahtemPalette.dCard : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _Tab(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'Verify',
                  active: _index == 0,
                  onTap: () => setState(() => _index = 0),
                  isDark: isDark,
                ),
                const _ScanButton(),
                _Tab(
                  icon: Icons.history_rounded,
                  activeIcon: Icons.history_rounded,
                  label: history > 0 ? 'History ($history)' : 'History',
                  active: _index == 1,
                  onTap: () => setState(() => _index = 1),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = active
        ? MahtemPalette.green
        : isDark
            ? MahtemPalette.dInkDim
            : MahtemPalette.lInkDim;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? activeIcon : icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Raised center scan button — always one tap away.
class _ScanButton extends StatelessWidget {
  const _ScanButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: GestureDetector(
        onTap: () => unawaitedScan(context),
        child: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: MahtemPalette.buttonGradient),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x332CB168),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.qr_code_scanner_rounded,
              color: Colors.white, size: 24),
        ),
      ),
    );
  }

  void unawaitedScan(BuildContext context) {
    openScanner(context);
  }
}
