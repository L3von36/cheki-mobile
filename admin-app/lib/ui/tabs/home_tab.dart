import 'package:flutter/material.dart';

import '../../admin_api.dart';
import '../../admin_controller.dart';
import '../../format.dart';
import '../account_detail_page.dart';
import '../admin_widgets.dart';
import '../theme.dart';

/// Home tab — KPIs, pulse, 14-day chart, top banks and latest scans.
class HomeTab extends StatelessWidget {
  const HomeTab({
    required this.controller,
    required this.data,
    required this.now,
    super.key,
  });

  final AdminController controller;
  final AdminOverview data;
  final int now;

  @override
  Widget build(BuildContext context) {
    final attributed = data.banks.fold<int>(0, (acc, b) => acc + b.count);
    final maxBank = data.banks.isEmpty ? 0 : data.banks.first.count;
    final latest = data.recent.take(8).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Text(
          'Every account, every synced scan — snapshot taken ${timeAgo(data.generatedAt, now)}',
          style: const TextStyle(fontSize: 12.5, color: AdminColors.muted),
        ),
        StaleBanner(error: controller.error),
        if (data.totals.scans == 0) ...[
          const SizedBox(height: 12),
          const WarmingBanner(),
        ],
        const SizedBox(height: 12),
        KpiGrid(data: data),
        const SizedBox(height: 12),
        PulseStrip(data: data),
        const SizedBox(height: 12),
        ActivityCard(days: data.days.length > 14 ? data.days.sublist(data.days.length - 14) : data.days),
        const SizedBox(height: 12),

        // Top banks mini
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.account_balance_rounded,
                  title: 'Top banks',
                  subtitle: 'Where verifications happen most',
                ),
                const SizedBox(height: 12),
                if (data.banks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No bank analytics yet — they arrive with the next sync '
                      'from v1.15.0+ devices.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                    ),
                  )
                else
                  for (var i = 0; i < data.banks.length && i < 5; i++)
                    BankRow(
                      rank: i + 1,
                      name: data.banks[i].name,
                      count: data.banks[i].count,
                      share: rate(data.banks[i].count, attributed),
                      widthFactor:
                          maxBank > 0 ? (data.banks[i].count / maxBank).clamp(0.06, 1.0) : 0.0,
                      champion: i == 0,
                      verified: data.banks[i].verified,
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Latest scans mini
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: SectionHeader(
                        icon: Icons.circle_notifications_outlined,
                        title: 'Latest scans',
                        subtitle: 'Newest verification attempts, live',
                      ),
                    ),
                    const PulseDot(),
                  ],
                ),
                const SizedBox(height: 8),
                if (latest.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      'No scans recorded yet. The feed lights up as devices '
                      'sync their verification history.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                    ),
                  )
                else
                  for (final ev in latest)
                    EventTile(
                      bankName: ev.bankName,
                      verified: ev.verified == 1,
                      timeAgoLabel: timeAgo(ev.t, now),
                      subtitle:
                          '#${ev.userId} · ${ev.verified == 1 ? 'verified' : 'not verified'}',
                      onTap: () => _openAccount(context, ev.userId),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const PrivacyCard(),
      ],
    );
  }

  void _openAccount(BuildContext context, String uid) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountDetailPage(controller: controller, uid: uid),
      ),
    );
  }
}
