import 'package:flutter/material.dart';

import '../admin_api.dart';
import '../format.dart';
import 'theme.dart';

/// Shared building blocks for every admin tab.

// ── Section headers ────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AdminColors.emerald),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(fontSize: 11.5, color: AdminColors.faint)),
      ],
    );
  }
}

// ── Banners ────────────────────────────────────────────────────────────────

class StaleBanner extends StatelessWidget {
  const StaleBanner({required this.error, super.key});

  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error == null || error!.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AdminColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 15, color: AdminColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$error Showing the last successful snapshot.',
              style: const TextStyle(
                  fontSize: 12.5, height: 1.4, color: AdminColors.amber),
            ),
          ),
        ],
      ),
    );
  }
}

class WarmingBanner extends StatelessWidget {
  const WarmingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AdminColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 16, color: AdminColors.muted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Analytics are warming up. Account and vault counts are live. '
              'Bank rankings and scan feeds fill in once devices on the '
              'v1.15.0+ app complete their next history sync.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: AdminColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0C0C0E),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'What this console can (and cannot) see',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.muted),
            ),
            SizedBox(height: 8),
            Text(
              'Mahtem is zero-knowledge: vaults are end-to-end encrypted, so '
              'this console can never read receipt contents, references or '
              'amounts. It sees account counts, revision timestamps, and — for '
              'devices on v1.15.0+ — bank names and verification outcomes '
              'reported with each sync. Nothing extra is collected, and '
              "deleting a device's cloud copy removes its contribution here too.",
              style: TextStyle(fontSize: 12, height: 1.55, color: AdminColors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

// ── KPI cards ──────────────────────────────────────────────────────────────

class KpiGrid extends StatelessWidget {
  const KpiGrid({required this.data, super.key});

  final AdminOverview data;

  @override
  Widget build(BuildContext context) {
    final t = data.totals;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final w = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: w,
              child: StatCard(
                icon: Icons.groups_rounded,
                label: 'REGISTERED ACCOUNTS',
                value: thousands(t.accounts),
                sub: '${thousands(t.vaults)} with cloud vault (${rate(t.vaults, t.accounts)}%)',
              ),
            ),
            SizedBox(
              width: w,
              child: StatCard(
                icon: Icons.cloud_upload_rounded,
                label: 'CLOUD-SYNCED VAULTS',
                value: thousands(t.vaults),
                sub: 'Encrypted, zero-knowledge storage',
              ),
            ),
            SizedBox(
              width: w,
              child: StatCard(
                icon: Icons.document_scanner_rounded,
                label: 'TOTAL SCANS (ALL TIME)',
                value: thousands(t.scans),
                sub: '${thousands(t.scans7d)} in 7d · ${thousands(t.scans30d)} in 30d',
              ),
            ),
            SizedBox(
              width: w,
              child: StatCard(
                icon: Icons.verified_rounded,
                label: 'VERIFIED RECEIPTS',
                value: thousands(t.verified),
                sub: '${rate(t.verified, t.scans)}% verification success rate',
                progress: rate(t.verified, t.scans) / 100,
              ),
            ),
          ],
        );
      },
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.progress,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.faint,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AdminColors.emerald.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 17, color: AdminColors.emerald),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(
                sub!,
                style: const TextStyle(fontSize: 11.5, color: AdminColors.faint),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: AdminColors.border,
                  valueColor: const AlwaysStoppedAnimation(AdminColors.emerald),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PulseStrip extends StatelessWidget {
  const PulseStrip({required this.data, super.key});

  final AdminOverview data;

  @override
  Widget build(BuildContext context) {
    final t = data.totals;
    final items = [
      (Icons.today_rounded, 'Scans today', thousands(t.scansToday)),
      (Icons.local_fire_department_rounded, 'Last 7 days', thousands(t.scans7d)),
      (Icons.monitor_heart_rounded, 'Active (7d)', thousands(t.scanningAccounts7d)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Container(width: 1, height: 34, color: AdminColors.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Column(
                    children: [
                      Icon(items[i].$1,
                          size: 15, color: AdminColors.emerald.withValues(alpha: 0.9)),
                      const SizedBox(height: 5),
                      Text(
                        items[i].$2,
                        style: const TextStyle(fontSize: 10, color: AdminColors.faint),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$3,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Activity chart (custom painter, no chart dependency) ───────────────────

class ActivityCard extends StatelessWidget {
  const ActivityCard({required this.days, this.title = 'Scan activity', super.key});

  final List<AdminDay> days;
  final String title;

  @override
  Widget build(BuildContext context) {
    final total = days.fold<int>(0, (acc, d) => acc + d.count);
    final peak = days.fold<int>(0, (m, d) => m > d.count ? m : d.count);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        'Receipt verifications per day (UTC)',
                        style: const TextStyle(fontSize: 11.5, color: AdminColors.faint),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      thousands(total),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      peak > 0 ? 'peak $peak/day' : 'no scans yet',
                      style: const TextStyle(fontSize: 10.5, color: AdminColors.faint),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(height: 110, width: double.infinity, child: DayBars(days: days)),
          ],
        ),
      ),
    );
  }
}

/// Lightweight bar chart — no chart dependency needed.
class DayBars extends StatelessWidget {
  const DayBars({required this.days, super.key});

  final List<AdminDay> days;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DayBarsPainter(days: days), size: Size.infinite);
  }
}

class _DayBarsPainter extends CustomPainter {
  _DayBarsPainter({required this.days});

  final List<AdminDay> days;

  static const _barColor = AdminColors.emerald;
  static const _labelColor = Color(0xFF71717A);
  static const _gridColor = Color(0xFF1C1C1F);

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    const labelH = 16.0;
    final plotH = size.height - labelH;
    final n = days.length;
    final slot = size.width / n;
    final barW = (slot * 0.52).clamp(2.0, 22.0);
    final maxCount = days.fold<int>(1, (m, d) => m > d.count ? m : d.count);

    final grid = Paint()
      ..color = _gridColor
      ..strokeWidth = 1;
    for (final f in const [0.25, 0.5, 0.75]) {
      final y = plotH * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    for (var i = 0; i < n; i++) {
      final day = days[i];
      final h = day.count <= 0 ? 2.0 : (day.count / maxCount) * (plotH - 6);
      final cx = slot * i + slot / 2;
      final rect = Rect.fromLTWH(cx - barW / 2, plotH - h, barW, h);
      final paint = Paint()
        ..color = day.count <= 0
            ? _gridColor
            : _barColor.withValues(alpha: 0.28 + 0.72 * (h / plotH));
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect,
            topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
        paint,
      );
    }

    _label(canvas, days.first.day, Offset(0, plotH + 3),
        align: TextAlign.left, maxWidth: slot * 1.6);
    _label(canvas, days[n ~/ 2].day, Offset(size.width / 2, plotH + 3),
        align: TextAlign.center, maxWidth: slot * 1.6);
    _label(canvas, days.last.day, Offset(size.width, plotH + 3),
        align: TextAlign.right, maxWidth: slot * 1.6);
  }

  void _label(Canvas canvas, String iso, Offset anchor,
      {required TextAlign align, required double maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(
        text: fmtDayLabel(iso),
        style: const TextStyle(fontSize: 9, color: _labelColor),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    final dx = switch (align) {
      TextAlign.left => anchor.dx,
      TextAlign.right => anchor.dx - tp.width,
      _ => anchor.dx - tp.width / 2,
    };
    tp.paint(canvas, Offset(dx, anchor.dy));
  }

  @override
  bool shouldRepaint(covariant _DayBarsPainter oldDelegate) =>
      oldDelegate.days != days;
}

// ── Bank rows ──────────────────────────────────────────────────────────────

class BankRow extends StatelessWidget {
  const BankRow({
    required this.rank,
    required this.name,
    required this.count,
    required this.share,
    required this.widthFactor,
    required this.champion,
    this.verified,
    super.key,
  });

  final int rank;
  final String name;
  final int count;
  final int share;
  final double widthFactor;
  final bool champion;
  final int? verified;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                child: champion
                    ? const Icon(Icons.emoji_events_rounded,
                        size: 14, color: AdminColors.amber)
                    : Text(
                        '$rank',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF52525B)),
                      ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (verified != null && count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AdminColors.emerald.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AdminColors.emerald.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '$verified/$count',
                    style: const TextStyle(
                        fontSize: 10,
                        color: AdminColors.emerald,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Text(
                thousands(count),
                style: const TextStyle(
                    fontSize: 12,
                    color: AdminColors.muted,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AdminColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AdminColors.border),
                ),
                child: Text(
                  '$share%',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AdminColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: widthFactor),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  backgroundColor: AdminColors.border,
                  valueColor: AlwaysStoppedAnimation(
                    champion
                        ? AdminColors.emerald
                        : AdminColors.emerald.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Event tiles ────────────────────────────────────────────────────────────

class PulseDot extends StatelessWidget {
  const PulseDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AdminColors.emerald),
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({
    required this.bankName,
    required this.verified,
    required this.timeAgoLabel,
    this.subtitle,
    this.onTap,
    super.key,
  });

  final String bankName;
  final bool verified;
  final String timeAgoLabel;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            verified ? Icons.check_circle_rounded : Icons.help_outline_rounded,
            size: 17,
            color: verified ? AdminColors.emerald : AdminColors.amber,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bankName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AdminColors.faint,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeAgoLabel,
            style: const TextStyle(
                fontSize: 11,
                color: AdminColors.faint,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 16, color: AdminColors.faint),
          ],
        ],
      ),
    );
    if (onTap == null) return tile;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: tile,
    );
  }
}

// ── Live toggle (app-bar action) ───────────────────────────────────────────

class LiveToggle extends StatelessWidget {
  const LiveToggle({required this.on, required this.onChanged, super.key});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? AdminColors.emerald : AdminColors.faint,
          ),
        ),
        const SizedBox(width: 6),
        const Text('Live', style: TextStyle(fontSize: 12.5, color: AdminColors.muted)),
        SizedBox(
          height: 30,
          child: Switch(
            value: on,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
