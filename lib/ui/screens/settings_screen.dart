import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/system_status.dart';
import '../../state/theme_controller.dart';
import '../../theme/cheki_theme.dart';
import 'banks_screen.dart';

/// Settings — appearance, supported banks, system status and about.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final status = context.watch<SystemStatus>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Text(
            'APPEARANCE',
            style: monoStyle(
              size: 9.5,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
              color: dim,
            ),
          ),
          const SizedBox(height: 8),
          _Card(
            isDark: isDark,
            child: SwitchListTile(
              value: theme.isDark,
              onChanged: (_) => theme.toggle(),
              secondary: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: ChekiPalette.blueSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  theme.isDark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  size: 17,
                  color: ChekiPalette.navy,
                ),
              ),
              title: Text(
                'Dark mode',
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                theme.isDark ? 'Night-friendly palette' : 'Bright and clean',
                style: TextStyle(color: dim, fontSize: 10.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),

          const SizedBox(height: 18),
          Text(
            'VERIFICATION',
            style: monoStyle(
              size: 9.5,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
              color: dim,
            ),
          ),
          const SizedBox(height: 8),
          _Card(
            isDark: isDark,
            child: Column(
              children: [
                ListTile(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const BanksScreen()),
                  ),
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: ChekiPalette.blueSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_rounded,
                        size: 17, color: ChekiPalette.navy),
                  ),
                  title: Text(
                    'Supported banks',
                    style: TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '10 banks & wallets · formats and requirements',
                    style: TextStyle(color: dim, fontSize: 10.5),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: dim),
                ),
                Divider(height: 1, color: isDark
                    ? ChekiPalette.dBorder
                    : ChekiPalette.lBorder, indent: 12, endIndent: 12),
                ListTile(
                  onTap: status.loading
                      ? null
                      : status.refresh,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.monitor_heart_rounded,
                        size: 17, color: _statusColor(status)),
                  ),
                  title: Text(
                    'Service status',
                    style: TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    status.loading
                        ? 'Checking…'
                        : _statusText(status),
                    style: TextStyle(color: dim, fontSize: 10.5),
                  ),
                  trailing: Icon(Icons.refresh_rounded,
                      size: 18, color: dim),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),
          Text(
            'ABOUT',
            style: monoStyle(
              size: 9.5,
              weight: FontWeight.w700,
              letterSpacing: 1.4,
              color: dim,
            ),
          ),
          const SizedBox(height: 8),
          _Card(
            isDark: isDark,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: ChekiPalette.buttonGradient),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.verified_user_rounded,
                        color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cheki · version 1.2.0',
                          style: TextStyle(
                            color: ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Free Ethiopian bank receipt verification. '
                          'No signup, no API key, no fees. Receipts are '
                          'fetched straight from each bank\u2019s official '
                          'endpoint and never stored.',
                          style: TextStyle(
                            color: dim,
                            fontSize: 10.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(SystemStatus status) {
    return switch (status.level) {
      'online' => ChekiPalette.green,
      'degraded' => ChekiPalette.amber,
      _ => ChekiPalette.red,
    };
  }

  String _statusText(SystemStatus status) {
    return switch (status.level) {
      'online' => 'All services running normally.',
      'degraded' => 'Some bank endpoints are slow or down.',
      _ => 'Could not reach the verification service.',
    };
  }
}

class _Card extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _Card({required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? ChekiPalette.dCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
        ),
      ),
      child: child,
    );
  }
}
