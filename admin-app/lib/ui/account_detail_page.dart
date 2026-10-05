import 'package:flutter/material.dart';

import '../admin_api.dart';
import '../admin_controller.dart';
import '../format.dart';
import 'admin_widgets.dart';
import 'theme.dart';

/// Full drill-down for one account: KPIs, 30-day series, banks used and the
/// event timeline. Metadata only — the vault blob never leaves the server.
class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({required this.controller, required this.uid, super.key});

  final AdminController controller;
  final String uid;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  AdminAccountDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.controller.accountDetail(widget.uid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on AdminException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        backgroundColor: AdminColors.background.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          '#${widget.uid}',
          style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Reload',
            icon: _loading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AdminColors.emerald),
                  )
                : const Icon(Icons.refresh_rounded, size: 22, color: AdminColors.muted),
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AdminColors.border),
        ),
      ),
      body: _loading && _detail == null
          ? const Center(
              child: CircularProgressIndicator(color: AdminColors.emerald))
          : _error != null && _detail == null
              ? _ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  color: AdminColors.emerald,
                  backgroundColor: AdminColors.card,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: _buildBody(now),
                  ),
                ),
    );
  }

  List<Widget> _buildBody(int now) {
    final d = _detail!;
    final success = rate(d.verified, d.scans);
    return [
      if (_error != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AdminColors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.amber.withValues(alpha: 0.3)),
          ),
          child: Text(
            '$_error — showing the last successful load.',
            style: const TextStyle(fontSize: 12.5, color: AdminColors.amber),
          ),
        ),

      // KPI row
      Row(
        children: [
          Expanded(
            child: _kpi('SCANS', thousands(d.scans)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _kpi(
              'VERIFIED',
              '$success%',
              valueColor: success >= 50
                  ? AdminColors.emerald
                  : success > 0
                      ? AdminColors.amber
                      : AdminColors.muted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _kpi('LAST SCAN', timeAgo(d.lastScanAt, now)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        d.createdAt != null
            ? 'Created ${fmtDate(d.createdAt)} · encrypted vault · metadata only'
            : 'Encrypted vault — metadata only',
        style: const TextStyle(fontSize: 11.5, color: AdminColors.faint),
      ),
      const SizedBox(height: 14),

      // 30-day series
      ActivityCard(days: d.days),
      const SizedBox(height: 12),

      // Banks used
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                icon: Icons.account_balance_rounded,
                title: 'Banks used',
                subtitle: 'Where this account verifies — with per-bank success',
              ),
              const SizedBox(height: 12),
              if (d.banks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'No bank analytics yet — this account has not synced scan '
                    'history from a v1.15.0+ device.',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                  ),
                )
              else
                for (var i = 0; i < d.banks.length; i++)
                  BankRow(
                    rank: i + 1,
                    name: d.banks[i].name,
                    count: d.banks[i].count,
                    share: rate(d.banks[i].count, d.scans),
                    widthFactor:
                        d.banks[0].count > 0 ? (d.banks[i].count / d.banks[0].count).clamp(0.06, 1.0) : 0.0,
                    champion: i == 0,
                    verified: d.banks[i].verified,
                  ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // Events
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                icon: Icons.history_rounded,
                title: 'Recent events',
                subtitle:
                    '${d.events.length} most recent of ${thousands(d.scans)} scans',
              ),
              const SizedBox(height: 8),
              if (d.events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Nothing recorded yet.',
                    style: TextStyle(fontSize: 12.5, color: AdminColors.faint),
                  ),
                )
              else
                for (final ev in d.events.take(60))
                  EventTile(
                    bankName: ev.bankName,
                    verified: ev.verified == 1,
                    timeAgoLabel: timeAgo(ev.t, now),
                    subtitle: fmtDate(ev.t),
                  ),
              if (d.events.length > 60)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Showing the 60 most recent events.',
                    style: TextStyle(fontSize: 11, color: AdminColors.faint),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      const PrivacyCard(),
    ];
  }

  Widget _kpi(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AdminColors.background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w600, color: AdminColors.faint),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AdminColors.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 34, color: AdminColors.faint),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5, color: AdminColors.muted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
