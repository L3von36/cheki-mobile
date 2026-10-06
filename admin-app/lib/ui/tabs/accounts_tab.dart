import 'package:flutter/material.dart';

import '../../admin_api.dart';
import '../../admin_controller.dart';
import '../../format.dart';
import '../account_detail_page.dart';
import '../admin_widgets.dart' show copyCsvToClipboard;
import '../theme.dart';

enum _AccountSort { scans, lastScan, synced, created }

/// Accounts tab — searchable, sortable list of every cloud-synced account.
/// Tapping an account opens its full drill-down page.
class AccountsTab extends StatefulWidget {
  const AccountsTab({
    required this.controller,
    required this.data,
    required this.now,
    super.key,
  });

  final AdminController controller;
  final AdminOverview data;
  final int now;

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  String _query = '';
  _AccountSort _sort = _AccountSort.scans;

  static const _sortLabels = {
    _AccountSort.scans: 'Most scans',
    _AccountSort.lastScan: 'Recent scan',
    _AccountSort.synced: 'Last synced',
    _AccountSort.created: 'Newest',
  };

  List<AdminAccountRow> get _rows {
    final q = _query.trim().toLowerCase();
    final rows = widget.data.accounts.where((a) {
      if (q.isEmpty) return true;
      return a.id.toLowerCase().contains(q) ||
          (a.topBank ?? '').toLowerCase().contains(q);
    }).toList();
    int? ts(AdminAccountRow a, int? Function(AdminAccountRow) pick) => pick(a);
    rows.sort((a, b) {
      switch (_sort) {
        case _AccountSort.scans:
          return b.scans.compareTo(a.scans);
        case _AccountSort.lastScan:
          return (ts(b, (x) => x.lastScanAt) ?? 0).compareTo(ts(a, (x) => x.lastScanAt) ?? 0);
        case _AccountSort.synced:
          return (ts(b, (x) => x.updatedAt) ?? 0).compareTo(ts(a, (x) => x.updatedAt) ?? 0);
        case _AccountSort.created:
          return (ts(b, (x) => x.createdAt) ?? 0).compareTo(ts(a, (x) => x.createdAt) ?? 0);
      }
    });
    return rows;
  }

  /// RFC 4180-friendly CSV of the current (filtered + sorted) rows.
  String _accountsCsv(List<AdminAccountRow> rows) {
    String cell(String c) =>
        c.contains(',') || c.contains('"') || c.contains('\n')
            ? '"${c.replaceAll('"', '""')}"'
            : c;
    final buf = StringBuffer(
        'id,created,last synced,last scan,scans,top bank,suspended\n');
    for (final a in rows) {
      String iso(int? ts) => ts == null
          ? ''
          : DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String();
      buf.writeln([
        a.id,
        iso(a.createdAt),
        iso(a.updatedAt),
        iso(a.lastScanAt),
        '${a.scans}',
        a.topBank ?? '',
        a.suspended ? 'yes' : '',
      ].map(cell).join(','));
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final rows = _rows;
    final active7d = widget.data.accounts
        .where((a) => a.lastScanAt != null && now - a.lastScanAt! < 7 * 86400000)
        .length;

    return RefreshIndicator(
      color: AdminColors.emerald,
      backgroundColor: AdminColors.card,
      onRefresh: () => widget.controller.refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(
            '${widget.data.accounts.length} cloud-synced accounts · $active7d scanned in the last 7 days · '
            'identities stay hashed',
            style: const TextStyle(fontSize: 12.5, color: AdminColors.muted),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => copyCsvToClipboard(
                  context, _accountsCsv(rows), '${rows.length} accounts'),
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('Copy CSV', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                foregroundColor: AdminColors.muted,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search account or bank…',
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: AdminColors.faint),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                for (final entry in _sortLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _sort == entry.key,
                      onSelected: (_) => setState(() => _sort = entry.key),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: _sort == entry.key
                            ? const Color(0xFF052E22)
                            : AdminColors.muted,
                        fontWeight:
                            _sort == entry.key ? FontWeight.w600 : FontWeight.w400,
                      ),
                      selectedColor: AdminColors.emerald,
                      showCheckmark: false,
                      side: BorderSide(
                        color: _sort == entry.key
                            ? AdminColors.emerald
                            : AdminColors.border,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _query.isEmpty
                      ? 'No cloud-synced accounts yet.'
                      : 'No accounts match “$_query”.',
                  style: const TextStyle(fontSize: 13, color: AdminColors.faint),
                ),
              ),
            )
          else
            for (final row in rows)
              _AccountCard(row: row, now: now, controller: widget.controller),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.row,
    required this.now,
    required this.controller,
  });

  final AdminAccountRow row;
  final int now;
  final AdminController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AdminColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    AccountDetailPage(controller: controller, uid: row.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '#${row.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AdminColors.text,
                                  fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                          ),
                          if (row.suspended) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AdminColors.rose.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AdminColors.rose.withValues(alpha: 0.4)),
                              ),
                              child: const Text(
                                'SUSPENDED',
                                style: TextStyle(
                                    fontSize: 8.5,
                                    letterSpacing: 0.6,
                                    fontWeight: FontWeight.w600,
                                    color: AdminColors.rose),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (row.topBank != null) ...[
                            Flexible(
                              child: Text(
                                row.topBank!,
                                style: const TextStyle(
                                    fontSize: 11.5, color: AdminColors.emerald),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            'created ${fmtDate(row.createdAt)}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AdminColors.faint,
                                fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _stat('scans', row.scans > 0 ? thousands(row.scans) : '—'),
                const SizedBox(width: 14),
                _stat('last scan', timeAgo(row.lastScanAt, now)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AdminColors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 9, letterSpacing: 0.5, color: Color(0xFF52525B))),
        const SizedBox(height: 1),
        Text(value,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AdminColors.muted,
                fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}
