import 'package:flutter/material.dart';

import '../../admin_api.dart';
import '../../admin_controller.dart';
import '../../format.dart';
import '../account_detail_page.dart';
import '../admin_widgets.dart';
import '../theme.dart';

enum _OutcomeFilter { all, verified, unverified }

/// Activity tab — the full event feed with outcome filters, grouped by day.
class ActivityTab extends StatefulWidget {
  const ActivityTab({
    required this.controller,
    required this.data,
    required this.now,
    super.key,
  });

  final AdminController controller;
  final AdminOverview data;
  final int now;

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  _OutcomeFilter _filter = _OutcomeFilter.all;
  String? _bank;

  List<AdminRecentEvent> get _events {
    return widget.data.recent.where((ev) {
      if (_filter == _OutcomeFilter.verified && ev.verified != 1) return false;
      if (_filter == _OutcomeFilter.unverified && ev.verified == 1) return false;
      if (_bank != null && ev.bankId != _bank) return false;
      return true;
    }).toList();
  }

  String _dayLabel(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    bool same(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (same(d, today)) return 'Today';
    if (same(d, yesterday)) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${wd[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final events = _events;
    final verifiedCount = events.where((e) => e.verified == 1).length;
    final filtered = events.length != widget.data.recent.length;

    return RefreshIndicator(
      color: AdminColors.emerald,
      backgroundColor: AdminColors.card,
      onRefresh: () => widget.controller.refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Text(
            filtered
                ? '${events.length} of ${widget.data.recent.length} events match the filter'
                    ' · $verifiedCount verified'
                : '${events.length} events across every synced device'
                    ' · $verifiedCount verified',
            style: const TextStyle(fontSize: 12.5, color: AdminColors.muted),
          ),
          const SizedBox(height: 12),

          // Outcome filter chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in _OutcomeFilter.values)
                ChoiceChip(
                  label: Text(switch (f) {
                    _OutcomeFilter.all => 'All',
                    _OutcomeFilter.verified => 'Verified',
                    _OutcomeFilter.unverified => 'Not verified',
                  }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        _filter == f ? FontWeight.w600 : FontWeight.w400,
                    color: _filter == f
                        ? const Color(0xFF052E22)
                        : AdminColors.muted,
                  ),
                  selectedColor: AdminColors.emerald,
                  showCheckmark: false,
                  side: BorderSide(
                    color: _filter == f ? AdminColors.emerald : AdminColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Bank filter dropdown
          if (widget.data.banks.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _bank,
              hint: const Text('All banks',
                  style: TextStyle(fontSize: 13, color: AdminColors.muted)),
              isDense: true,
              dropdownColor: AdminColors.card,
              style: const TextStyle(fontSize: 13, color: AdminColors.text),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon:
                    Icon(Icons.account_balance_rounded, size: 18, color: AdminColors.faint),
              ),
              items: [
                for (final b in widget.data.banks)
                  DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _bank = v),
            ),
          const SizedBox(height: 10),

          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 44),
              child: Column(
                children: [
                  const Icon(Icons.inbox_rounded, size: 34, color: AdminColors.faint),
                  const SizedBox(height: 10),
                  Text(
                    widget.data.recent.isEmpty
                        ? 'No scans recorded yet. Events appear here the moment '
                            'v1.15.0+ devices sync their verification history.'
                        : 'Nothing matches this filter. Try a different outcome or bank.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.5, color: AdminColors.faint),
                  ),
                ],
              ),
            )
          else ...[
            // Group by day (events arrive newest-first).
            for (var i = 0; i < events.length; i++) ...[
              if (i == 0 || _dayLabel(events[i].t) != _dayLabel(events[i - 1].t))
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        _dayLabel(events[i].t),
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: AdminColors.faint),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(child: Divider(thickness: 1, color: AdminColors.border)),
                    ],
                  ),
                ),
              EventTile(
                bankName: events[i].bankName,
                verified: events[i].verified == 1,
                timeAgoLabel: timeAgo(events[i].t, now),
                subtitle: '#${events[i].userId} · '
                    '${events[i].verified == 1 ? 'verified' : 'not verified'}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AccountDetailPage(
                        controller: widget.controller, uid: events[i].userId),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Receipt contents stay encrypted — only bank, outcome and time '
              'are visible.',
              style: TextStyle(fontSize: 10.5, height: 1.45, color: Color(0xFF52525B)),
            ),
          ],
        ],
      ),
    );
  }
}
