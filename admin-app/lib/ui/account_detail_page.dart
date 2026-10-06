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
      if (d.suspended) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AdminColors.rose.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AdminColors.rose.withValues(alpha: 0.35)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.block_rounded, size: 15, color: AdminColors.rose),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Suspended — this account cannot sign in or sync its vault '
                  'until re-enabled.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: AdminColors.rose),
                ),
              ),
            ],
          ),
        ),
      ],
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

      _ManagementCard(page: this, detail: d),
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

/// Account controls (v1.19 console): suspend / re-enable with instant
/// session revocation, and the irreversible wipe behind a typed
/// confirmation. Any signed-in admin may use these — the Worker
/// enforces the session and writes every action to the audit trail.
class _ManagementCard extends StatelessWidget {
  const _ManagementCard({required this.page, required this.detail});

  final _AccountDetailPageState page;
  final AdminAccountDetail detail;

  AdminController get controller => page.widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.manageBusy;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  icon: Icons.shield_outlined,
                  title: 'Account controls',
                  subtitle: 'Suspension blocks sign-in + sync instantly and is reversible',
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    detail.suspended ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                    size: 20,
                    color: detail.suspended ? AdminColors.rose : AdminColors.emerald,
                  ),
                  title: const Text('Suspended',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    detail.suspended
                        ? 'Tap to re-enable — the account signs in and syncs again'
                        : 'Tap to suspend — sessions are revoked on the spot',
                    style: const TextStyle(fontSize: 11.5, color: AdminColors.faint),
                  ),
                  value: detail.suspended,
                  onChanged: busy ? null : (_) => _toggleSuspend(context),
                ),
                const Divider(height: 1, color: AdminColors.border),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.dangerous_outlined,
                        size: 18, color: AdminColors.rose),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Danger zone',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 3),
                          const Text(
                            'Deleting wipes the encrypted vault, the account '
                            'record and every session for good. Nothing can '
                            'bring it back.',
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                color: AdminColors.faint),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AdminColors.rose,
                        side: const BorderSide(
                            color: AdminColors.rose, width: 0.8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                      ),
                      onPressed: busy ? null : () => _confirmDelete(context),
                      child: const Text('Delete…',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleSuspend(BuildContext context) async {
    // Capture everything that outlives the await BEFORE it — the card's
    // context is defunct once the async gap opens.
    final messenger = ScaffoldMessenger.of(context);
    final target = !detail.suspended;
    final ok = await controller.setAccountSuspended(detail.id, target);
    if (!page.mounted) return;
    if (ok) {
      await page._load(); // re-read the drill-down (flag + banner update)
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AdminColors.border),
          ),
          content: Text(
            target
                ? 'Account #${detail.id} suspended — sessions revoked.'
                : 'Account #${detail.id} re-enabled.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final id = detail.id;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<AccountDeleteResult?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DeleteAccountDialog(
        controller: controller,
        id: id,
      ),
    );
    if (result == null) return;
    // The account no longer exists — leave the drill-down.
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AdminColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AdminColors.border),
        ),
        content: Text(
          'Account #$id deleted — vault wiped, ${result.sessions} session(s) '
          'and ${result.refreshTokens} refresh token(s) revoked.',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

/// Typed-confirmation delete: the owner must repeat the 8-hex prefix —
/// the exact guard the Worker enforces server-side.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.controller, required this.id});

  final AdminController controller;
  final String id;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_confirm.text.trim().toLowerCase() != widget.id) {
      setState(() => _error = 'Type ${widget.id} to confirm.');
      return;
    }
    final result =
        await widget.controller.deleteAccount(widget.id, _confirm.text.trim());
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      setState(() => _error = widget.controller.manageError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.manageBusy;
        return AlertDialog(
          backgroundColor: AdminColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AdminColors.border),
          ),
          title: const Text('Delete this account?', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This permanently removes the encrypted vault, the account '
                'record and every active session. A tombstone stops cached '
                'devices from re-creating the vault.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.5, color: AdminColors.muted),
              ),
              const SizedBox(height: 14),
              Text(
                'Type ${widget.id} to confirm:',
                style: const TextStyle(fontSize: 12.5, color: AdminColors.text),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirm,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontFeatures: [FontFeature.tabularFigures()]),
                decoration: const InputDecoration(hintText: '8-hex account id'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(fontSize: 12.5, color: AdminColors.rose)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: AdminColors.muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AdminColors.rose,
                foregroundColor: Colors.white,
              ),
              onPressed: busy ? null : _delete,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Text('Delete forever'),
            ),
          ],
        );
      },
    );
  }
}
