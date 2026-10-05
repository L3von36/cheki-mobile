import 'package:flutter/material.dart';

import '../../admin_api.dart';
import '../../admin_controller.dart';
import '../../format.dart';
import '../admin_widgets.dart';
import '../theme.dart';

/// Banks tab — summary strip + the full ranking with per-bank verification.
class BanksTab extends StatelessWidget {
  const BanksTab({
    required this.controller,
    required this.data,
    super.key,
  });

  final AdminController controller;
  final AdminOverview data;

  @override
  Widget build(BuildContext context) {
    final banks = data.banks;
    final attributed = banks.fold<int>(0, (acc, b) => acc + b.count);
    final max = banks.isEmpty ? 0 : banks.first.count;

    return RefreshIndicator(
      color: AdminColors.emerald,
      backgroundColor: AdminColors.card,
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          // Summary strip
          Row(
            children: [
              Expanded(child: _summary('BANKS SEEN', thousands(banks.length))),
              const SizedBox(width: 8),
              Expanded(
                child: _summary(
                  'ATTRIBUTED',
                  thousands(attributed),
                  sub: data.totals.scans > attributed
                      ? '${rate(attributed, data.totals.scans)}% of all scans'
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summary(
                  'MOST USED',
                  banks.isEmpty ? '—' : banks.first.name,
                  sub: banks.isEmpty ? null : '${rate(banks.first.count, attributed)}% share',
                  small: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    icon: Icons.account_balance_rounded,
                    title: 'Bank popularity ranking',
                    subtitle:
                        'Which banks people verify with — ranked by scan count, '
                        'with per-bank verification success',
                  ),
                  const SizedBox(height: 14),
                  if (banks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Center(
                        child: Text(
                          'No bank analytics yet. Banks appear here once devices '
                          'on v1.15.0+ complete their next sync.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < banks.length; i++)
                      BankRow(
                        rank: i + 1,
                        name: banks[i].name,
                        count: banks[i].count,
                        share: rate(banks[i].count, attributed),
                        widthFactor:
                            max > 0 ? (banks[i].count / max).clamp(0.05, 1.0) : 0.0,
                        champion: i == 0,
                        verified: banks[i].verified,
                      ),
                  if (banks.isNotEmpty && data.totals.scans > attributed)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${thousands(attributed)} of ${thousands(data.totals.scans)} scans carry '
                        'bank metadata — older v1.14.x devices sync history without '
                        'analytics tags.',
                        style: const TextStyle(
                            fontSize: 10.5, height: 1.45, color: Color(0xFF52525B)),
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

  Widget _summary(String label, String value, {String? sub, bool small = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AdminColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 8.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: AdminColors.faint),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: small ? 14 : 19,
              fontWeight: FontWeight.w600,
              color: AdminColors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null)
            Text(
              sub,
              style: const TextStyle(fontSize: 10, color: AdminColors.faint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
