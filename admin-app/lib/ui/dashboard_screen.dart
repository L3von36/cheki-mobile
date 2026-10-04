import 'dart:async';

import 'package:flutter/material.dart';

import '../admin_api.dart';
import '../admin_controller.dart';
import '../format.dart';
import 'theme.dart';

/// The analytics dashboard — pull-to-refresh or let the 30s live loop run.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.controller, super.key});

  final AdminController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await widget.controller.refresh();
  }

  Future<void> _confirmSignOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AdminColors.border),
        ),
        title: const Text('Sign out?', style: TextStyle(fontSize: 17)),
        content: const Text(
          'This device keeps no credentials after sign-out. '
          'Sign back in with the owner email and password.',
          style: TextStyle(fontSize: 13.5, height: 1.45, color: AdminColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out', style: TextStyle(color: AdminColors.rose)),
          ),
        ],
      ),
    );
    if (yes == true) await widget.controller.signOut();
  }

  Future<void> _showChangePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ChangePasswordDialog(controller: widget.controller),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AdminColors.border),
          ),
          content: const Text(
            'Password changed. Other devices were signed out.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final data = controller.overview!;
    final now = DateTime.now().millisecondsSinceEpoch;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AdminColors.background.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 12,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('assets/seal.png', width: 34, height: 34, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mahtem Admin',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.15),
                ),
                Text(
                  'mahtem-api · Cloudflare Workers',
                  style: TextStyle(fontSize: 10.5, color: AdminColors.faint, height: 1.3),
                ),
              ],
            ),
          ],
        ),
        actions: [
          _LiveToggle(controller: controller),
          IconButton(
            onPressed: controller.busy ? null : _refresh,
            tooltip: 'Refresh now',
            icon: controller.busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: AdminColors.emerald),
                  )
                : const Icon(Icons.refresh_rounded, size: 22, color: AdminColors.muted),
          ),
          IconButton(
            onPressed: controller.busy ? null : _showChangePassword,
            tooltip: 'Change password',
            icon: const Icon(Icons.lock_reset_outlined,
                size: 21, color: AdminColors.muted),
          ),
          IconButton(
            onPressed: _confirmSignOut,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded, size: 20, color: AdminColors.muted),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AdminColors.border),
        ),
      ),
      body: RefreshIndicator(
        color: AdminColors.emerald,
        backgroundColor: AdminColors.card,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _HeaderCaption(data: data, now: now),
            _StaleBanner(controller: controller),
            if (data.totals.scans == 0) const _WarmingBanner(),
            const SizedBox(height: 12),
            _KpiGrid(data: data),
            const SizedBox(height: 12),
            _PulseStrip(data: data),
            const SizedBox(height: 12),
            _ActivityCard(data: data),
            const SizedBox(height: 12),
            _BanksCard(data: data),
            const SizedBox(height: 12),
            _RecentCard(data: data, now: now),
            const SizedBox(height: 12),
            _AccountsCard(data: data, now: now),
            const SizedBox(height: 12),
            const _PrivacyCard(),
            const SizedBox(height: 16),
            const Text(
              'Mahtem Admin Console · read-only · v1.0.0',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFF52525B)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header / banners ────────────────────────────────────────────────────────

class _HeaderCaption extends StatelessWidget {
  const _HeaderCaption({required this.data, required this.now});

  final AdminOverview data;
  final int now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Network overview',
          style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        ),
        const SizedBox(height: 3),
        Text(
          'Every account, every synced scan — snapshot taken ${timeAgo(data.generatedAt, now)}',
          style: const TextStyle(fontSize: 12.5, color: AdminColors.muted),
        ),
      ],
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.controller});

  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.error;
    if (error == null || controller.overview == null) return const SizedBox.shrink();
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
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: AdminColors.amber),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarmingBanner extends StatelessWidget {
  const _WarmingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
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

class _LiveToggle extends StatelessWidget {
  const _LiveToggle({required this.controller});

  final AdminController controller;

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
            color: controller.autoRefresh ? AdminColors.emerald : AdminColors.faint,
          ),
        ),
        const SizedBox(width: 6),
        const Text('Live', style: TextStyle(fontSize: 12.5, color: AdminColors.muted)),
        SizedBox(
          height: 30,
          child: Switch(
            value: controller.autoRefresh,
            onChanged: controller.setAutoRefresh,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

// ── KPI grid + pulse strip ──────────────────────────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.data});

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
              child: _StatCard(
                icon: Icons.groups_rounded,
                label: 'REGISTERED ACCOUNTS',
                value: thousands(t.accounts),
                sub: '${thousands(t.vaults)} with cloud vault (${rate(t.vaults, t.accounts)}%)',
              ),
            ),
            SizedBox(
              width: w,
              child: _StatCard(
                icon: Icons.cloud_upload_rounded,
                label: 'CLOUD-SYNCED VAULTS',
                value: thousands(t.vaults),
                sub: 'Encrypted, zero-knowledge storage',
              ),
            ),
            SizedBox(
              width: w,
              child: _StatCard(
                icon: Icons.document_scanner_rounded,
                label: 'TOTAL SCANS (ALL TIME)',
                value: thousands(t.scans),
                sub: '${thousands(t.scans7d)} in the last 7 days',
              ),
            ),
            SizedBox(
              width: w,
              child: _StatCard(
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.progress,
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

class _PulseStrip extends StatelessWidget {
  const _PulseStrip({required this.data});

  final AdminOverview data;

  @override
  Widget build(BuildContext context) {
    final t = data.totals;
    final items = [
      (Icons.today_rounded, 'Scans today', thousands(t.scansToday)),
      (Icons.local_fire_department_rounded, 'Last 7 days', thousands(t.scans7d)),
      (Icons.monitor_heart_rounded, 'Active accounts (7d)', thousands(t.scanningAccounts7d)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(width: 1, height: 34, color: AdminColors.border),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Column(
                    children: [
                      Icon(items[i].$1, size: 15, color: AdminColors.emerald.withValues(alpha: 0.9)),
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

// ── Scan activity (custom bar chart) ────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.data});

  final AdminOverview data;

  @override
  Widget build(BuildContext context) {
    final total = data.days.fold<int>(0, (acc, d) => acc + d.count);
    final peak = data.days.fold<int>(0, (m, d) => m > d.count ? m : d.count);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scan activity',
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      SizedBox(height: 3),
                      Text(
                        'Receipt verifications per day — last 14 days (UTC)',
                        style: TextStyle(fontSize: 11.5, color: AdminColors.faint),
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
            SizedBox(height: 110, width: double.infinity, child: DayBars(days: data.days)),
          ],
        ),
      ),
    );
  }
}

/// Lightweight 14-day bar chart — no chart dependency needed.
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

    // Horizontal gridlines (25/50/75%).
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
        ..color = day.count <= 0 ? _gridColor : _barColor.withValues(alpha: 0.28 + 0.72 * (h / plotH));
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect,
            topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
        paint,
      );
    }

    // Day labels: first, middle, last.
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

// ── Banks ───────────────────────────────────────────────────────────────────

class _BanksCard extends StatelessWidget {
  const _BanksCard({required this.data});

  final AdminOverview data;

  @override
  Widget build(BuildContext context) {
    final banks = data.banks;
    final attributed = banks.fold<int>(0, (acc, b) => acc + b.count);
    const topN = 8;
    final top = banks.take(topN).toList();
    final restCount =
        banks.length > topN ? banks.skip(topN).fold<int>(0, (acc, b) => acc + b.count) : 0;
    final max = top.isEmpty ? 0 : top.first.count;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance_rounded, size: 16, color: AdminColors.emerald),
                SizedBox(width: 8),
                Text('Most-used banks',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
              'Bank share across every verified scan — which bank do people rely on most?',
              style: TextStyle(fontSize: 11.5, color: AdminColors.faint),
            ),
            const SizedBox(height: 14),
            if (banks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    'No bank analytics yet. Banks appear here once devices '
                    'on v1.15.0+ complete their next sync.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                  ),
                ),
              )
            else
              for (var i = 0; i < top.length; i++)
                _BankRow(
                  rank: i + 1,
                  name: top[i].name,
                  count: top[i].count,
                  share: rate(top[i].count, attributed),
                  widthFactor: max > 0 ? (top[i].count / max).clamp(0.06, 1.0) : 0.0,
                  champion: i == 0,
                ),
            if (restCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+ ${banks.length - topN} other banks · ${thousands(restCount)} scans '
                  '(${rate(restCount, attributed)}%)',
                  style: const TextStyle(fontSize: 11.5, color: AdminColors.faint),
                ),
              ),
            if (banks.isNotEmpty && data.totals.scans > attributed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${thousands(attributed)} of ${thousands(data.totals.scans)} scans carry '
                  'bank metadata — older v1.14.x devices sync history without analytics tags.',
                  style: const TextStyle(fontSize: 10.5, height: 1.45, color: Color(0xFF52525B)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({
    required this.rank,
    required this.name,
    required this.count,
    required this.share,
    required this.widthFactor,
    required this.champion,
  });

  final int rank;
  final String name;
  final int count;
  final int share;
  final double widthFactor;
  final bool champion;

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
                            fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF52525B)),
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
              const SizedBox(width: 8),
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
                    champion ? AdminColors.emerald : AdminColors.emerald.withValues(alpha: 0.55),
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

// ── Recent activity ─────────────────────────────────────────────────────────

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.data, required this.now});

  final AdminOverview data;
  final int now;

  @override
  Widget build(BuildContext context) {
    const show = 12;
    final events = data.recent.take(show).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _PulseDot(),
                SizedBox(width: 8),
                Text('Recent scan activity',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
              'Newest verification attempts across every synced device',
              style: TextStyle(fontSize: 11.5, color: AdminColors.faint),
            ),
            const SizedBox(height: 10),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    'No scans recorded yet. The feed lights up as soon as '
                    'v1.15.0+ devices sync their verification history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                  ),
                ),
              )
            else
              for (final ev in events)
                _EventTile(event: ev, now: now),
            if (events.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Showing ${events.length} of ${thousands(data.recent.length)} most recent. '
                  'Receipt contents stay encrypted — the console only sees bank, '
                  'outcome and time.',
                  style: const TextStyle(fontSize: 10.5, height: 1.45, color: Color(0xFF52525B)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AdminColors.emerald),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.now});

  final AdminRecentEvent event;
  final int now;

  @override
  Widget build(BuildContext context) {
    final verified = event.verified == 1;
    return Padding(
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
                  event.bankName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '#${event.userId} · ${verified ? 'verified' : 'not verified'}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AdminColors.faint,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeAgo(event.t, now),
            style: const TextStyle(
                fontSize: 11,
                color: AdminColors.faint,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

// ── Accounts ────────────────────────────────────────────────────────────────

class _AccountsCard extends StatelessWidget {
  const _AccountsCard({required this.data, required this.now});

  final AdminOverview data;
  final int now;

  @override
  Widget build(BuildContext context) {
    final rows = data.accounts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 16, color: AdminColors.emerald),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Accounts',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminColors.background,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AdminColors.border),
                  ),
                  child: Text(
                    '${rows.length}',
                    style: const TextStyle(
                        fontSize: 10.5,
                        color: AdminColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            const Text(
              'Every cloud-synced account — identities stay hashed, only '
              '8-character prefixes are visible',
              style: TextStyle(fontSize: 11.5, color: AdminColors.faint),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No cloud-synced accounts yet.',
                      style: TextStyle(fontSize: 12.5, color: AdminColors.faint)),
                ),
              )
            else
              for (final row in rows.take(30))
                _AccountTile(row: row, now: now),
            if (rows.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Showing first 30 of ${rows.length} accounts.',
                  style: const TextStyle(fontSize: 11, color: AdminColors.faint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.row, required this.now});

  final AdminAccountRow row;
  final int now;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AdminColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AdminColors.border),
      ),
      child: Row(
        children: [
          Text(
            '#${row.id}',
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFD4D4D8),
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const Spacer(),
          _mini('scans', row.scans > 0 ? thousands(row.scans) : '—'),
          const SizedBox(width: 12),
          _mini('last scan', timeAgo(row.lastScanAt, now)),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 9, letterSpacing: 0.5, color: Color(0xFF52525B))),
        const SizedBox(height: 1),
        Text(value,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AdminColors.muted,
                fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}

// ── Privacy ─────────────────────────────────────────────────────────────────

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.muted),
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

/// Change-password dialog. On success the Worker rotates every session and
/// returns a fresh token for this device (handled by [AdminController]).
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.controller});

  final AdminController controller;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_next.text != _confirm.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    final ok = await widget.controller.changePassword(_current.text, _next.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = widget.controller.error);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AdminColors.border),
      ),
      title: const Text('Change password', style: TextStyle(fontSize: 17)),
      content: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final busy = widget.controller.busy;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _current,
                obscureText: _obscure,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'Current password',
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      size: 19, color: AdminColors.faint),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _next,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: 'New password (10+ characters)',
                  prefixIcon: Icon(Icons.lock_reset_outlined,
                      size: 19, color: AdminColors.faint),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) {
                  if (!busy) _submit();
                },
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Repeat new password',
                  prefixIcon: const Icon(Icons.lock_person_rounded,
                      size: 19, color: AdminColors.faint),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19,
                      color: AdminColors.faint,
                    ),
                    tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 12.5, color: AdminColors.rose),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final busy = widget.controller.busy;
            return TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
            );
          },
        ),
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final busy = widget.controller.busy;
            return FilledButton(
              onPressed: busy ? null : _submit,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Color(0xFF052E22)),
                    )
                  : const Text('Change'),
            );
          },
        ),
      ],
    );
  }
}
