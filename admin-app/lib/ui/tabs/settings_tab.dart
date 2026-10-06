import 'package:flutter/material.dart';

import '../../admin_controller.dart';
import '../../admin_api.dart';
import '../admin_widgets.dart';
import '../theme.dart';

/// Settings tab — owner profile, security, live updates and the privacy
/// contract. Change-password lives here (plus a quick lock icon in the app
/// bar) instead of cluttering the analytics tabs.
class SettingsTab extends StatelessWidget {
  const SettingsTab({
    required this.controller,
    required this.data,
    required this.onChangePassword,
    required this.onSignOut,
    super.key,
  });

  final AdminController controller;
  final AdminOverview data;
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final email = controller.email ?? 'Owner';
    final initial = email.trim().isEmpty ? 'M' : email.trim()[0].toUpperCase();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        // Owner card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AdminColors.emerald.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AdminColors.emerald.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AdminColors.emerald),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: AdminColors.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        controller.isOwner
                            ? 'Owner · full access · sessions last 30 days'
                            : 'Admin · analytics, accounts & announcements · sessions last 30 days',
                        style: const TextStyle(fontSize: 11.5, color: AdminColors.faint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Security
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.lock_reset_outlined,
                  title: 'Security',
                  subtitle:
                      'Changing the password signs out every other device instantly',
                ),
                const SizedBox(height: 12),
                _actionTile(
                  icon: Icons.key_rounded,
                  title: 'Change password',
                  subtitle: 'Stored as a salted PBKDF2 hash (100k iterations)',
                  onTap: onChangePassword,
                ),
                _actionTile(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  subtitle:
                      'Revokes this session server-side; nothing stays on-device',
                  onTap: onSignOut,
                  destructive: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Live updates
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.sync_rounded,
                  title: 'Live updates',
                  subtitle: 'The console re-polls the Mahtem API every 30 seconds',
                ),
                const SizedBox(height: 6),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-refresh',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      controller.autoRefresh
                          ? 'On — data refreshes itself'
                          : 'Off — pull down or tap refresh to update',
                      style: const TextStyle(fontSize: 11.5, color: AdminColors.faint),
                    ),
                    value: controller.autoRefresh,
                    onChanged: controller.setAutoRefresh,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // About
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.verified_user_rounded,
                  title: 'Privacy contract',
                  subtitle: 'Zero-knowledge, by construction',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Mahtem is zero-knowledge: vaults are end-to-end encrypted, so '
                  'this console can never read receipt contents, references or '
                  'amounts. It sees account counts, revision timestamps, and — for '
                  'devices on v1.15.0+ — bank names and verification outcomes '
                  'reported with each sync. Nothing extra is collected, and '
                  "deleting a device's cloud copy removes its contribution here too.",
                  style: TextStyle(fontSize: 12, height: 1.55, color: AdminColors.faint),
                ),
                const SizedBox(height: 10),
                Text(
                  'Mahtem Admin · app v1.3.0 · API v1.19 · snapshot '
                  '${fmtSnapshot(data.generatedAt)}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF52525B),
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String fmtSnapshot(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toUtc();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, '
        '${two(d.hour)}:${two(d.minute)} UTC';
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? AdminColors.rose : AdminColors.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: destructive ? AdminColors.rose : AdminColors.text)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.35, color: AdminColors.faint)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AdminColors.faint),
          ],
        ),
      ),
    );
  }
}
