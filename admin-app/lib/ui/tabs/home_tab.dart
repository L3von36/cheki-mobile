import 'package:flutter/material.dart';

import '../../admin_api.dart';
import '../../admin_controller.dart';
import '../../format.dart';
import '../account_detail_page.dart';
import '../admin_widgets.dart';
import '../theme.dart';

/// Home tab — KPIs, pulse, the activity chart with a 7/14/30-day range,
/// top banks and latest scans.
class HomeTab extends StatefulWidget {
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
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  int _range = 14;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final now = widget.now;
    final attributed = data.banks.fold<int>(0, (acc, b) => acc + b.count);
    final maxBank = data.banks.isEmpty ? 0 : data.banks.first.count;
    final latest = data.recent.take(8).toList();
    final days = data.days.length > _range
        ? data.days.sublist(data.days.length - _range)
        : data.days;
    final rangeTotal =
        days.fold<int>(0, (acc, d) => acc + d.count);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Text(
          'Every account, every synced scan — snapshot taken ${timeAgo(data.generatedAt, now)}',
          style: const TextStyle(fontSize: 12.5, color: AdminColors.muted),
        ),
        StaleBanner(error: widget.controller.error),
        if (data.totals.scans == 0) ...[
          const SizedBox(height: 12),
          const WarmingBanner(),
        ],
        const SizedBox(height: 12),
        KpiGrid(data: data),
        const SizedBox(height: 12),
        PulseStrip(data: data),
        const SizedBox(height: 12),
        ActivityCard(
          days: days,
          title: 'Scan activity',
          subtitle: '${thousands(rangeTotal)} checks in the last $_range days (UTC)',
          trailing: _rangeSelector(),
        ),
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

  /// 7 / 14 / 30-day quick ranges for the activity chart.
  Widget _rangeSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (days, label) in const [(7, '7d'), (14, '14d'), (30, '30d')]) ...[
          if (days != 7) const SizedBox(width: 6),
          _rangeChip(days, label),
        ],
      ],
    );
  }

  Widget _rangeChip(int days, String label) {
    final selected = _range == days;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _range = days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AdminColors.emerald
              : AdminColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AdminColors.emerald : AdminColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? const Color(0xFF052E22) : AdminColors.muted,
          ),
        ),
      ),
    );
  }

  void _openAccount(BuildContext context, String uid) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountDetailPage(controller: widget.controller, uid: uid),
      ),
    );
  }
}
