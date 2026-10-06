import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/localization/app_strings.dart';
import '../../core/receipt_verify/extra_banks.dart';
import '../../core/verify_history.dart';
import '../../state/app_tab.dart';
import '../../state/locale_controller.dart';
import '../../state/verify_controller.dart';
import '../../theme/mahtem_theme.dart';
import '../../util/format.dart';
import '../widgets/bank_avatar.dart';
import '../widgets/pressable.dart';
import '../widgets/reason_sheet.dart';
import '../../state/cloud_controller.dart';

/// Status filter above the history list.
enum _HistoryFilter { all, verified, failed }

/// History — every past check, searchable, filterable and grouped (v1.9.0):
///   * summary strip: checks / verified / total verified amount,
///   * search by reference, name or bank,
///   * status filter (all / verified / not verified),
///   * date groups (Today / Yesterday / This week / Earlier),
///   * tap an entry for details, swipe (or long-press) to remove with undo,
///   * "Verify again" prefill — jumps back to the Verify tab with the
///     entry's bank + reference already filled in,
///   * share the whole history as CSV text.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cloud = context.read<CloudController>();
        final history = context.read<VerifyHistory>();
        cloud.pollNow(history);
        cloud.refreshAnnouncements();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(HistoryEntry entry, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    bool hit(String? value) =>
        value != null && value.toLowerCase().contains(needle);
    return hit(entry.reference) ||
        hit(entry.bankName) ||
        hit(entry.title) ||
        hit(entry.senderName) ||
        hit(entry.receiverName) ||
        hit(entry.reason);
  }

  List<HistoryEntry> _filtered(List<HistoryEntry> entries) {
    return entries.where((entry) {
      final statusOk = switch (_filter) {
        _HistoryFilter.all => true,
        _HistoryFilter.verified => entry.isVerified,
        _HistoryFilter.failed => !entry.isVerified,
      };
      return statusOk && _matches(entry, _searchCtrl.text);
    }).toList();
  }

  /// Deletes an entry and offers one-tap undo — the snackbar re-inserts
  /// it at its original position (VerifyHistory.insert clamps the index).
  void _removeWithUndo(VerifyHistory history, HistoryEntry entry) {
    final index = history.entries.indexOf(entry);
    final s = context.read<LocaleController>().strings;
    final messenger = ScaffoldMessenger.of(context);
    HapticFeedback.mediumImpact();
    history.remove(entry.id);
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(s.removedToast),
        action: SnackBarAction(
          label: s.undo,
          onPressed: () => history.insert(index, entry),
        ),
      ),
    );
  }

  /// Hands the whole history to the Android share sheet as CSV text.
  Future<void> _shareHistory(VerifyHistory history) async {
    final s = context.read<LocaleController>().strings;
    try {
      await SharePlus.instance.share(
        ShareParams(title: s.historyTitle, text: history.toCsv()),
      );
    } catch (_) {
      // Share sheet unavailable — nothing to recover, stay silent.
    }
  }

  /// Buckets a checked-at date for the group headers.
  String _bucketOf(HistoryEntry entry, DateTime today) {
    final dt = DateTime.fromMillisecondsSinceEpoch(entry.verifiedAt);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'today';
    if (day == today.subtract(const Duration(days: 1))) return 'yesterday';
    if (day.isAfter(today.subtract(const Duration(days: 7)))) return 'week';
    return 'earlier';
  }

  /// Flattens the filtered list into rows: a header whenever the date
  /// bucket changes, then a dismissible card per entry.
  List<Widget> _buildRows(
    AppStrings s,
    List<HistoryEntry> visible,
    VerifyHistory history,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final headerFor = <String, String>{
      'today': s.groupToday,
      'yesterday': s.groupYesterday,
      'week': s.groupThisWeek,
      'earlier': s.groupEarlier,
    };
    final rows = <Widget>[];
    String? current;
    for (final entry in visible) {
      final bucket = _bucketOf(entry, today);
      if (bucket != current) {
        current = bucket;
        rows.add(_GroupHeader(label: headerFor[bucket]!));
      }
      rows.add(
        Dismissible(
          key: ValueKey('history-${entry.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 18),
            decoration: BoxDecoration(
              color: MahtemPalette.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MahtemPalette.red.withValues(alpha: 0.35)),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: MahtemPalette.red,
              size: 20,
            ),
          ),
          onDismissed: (_) => _removeWithUndo(history, entry),
          child: _EntryCard(
            entry: entry,
            onTap: () => _showDetails(context, entry),
            onLongPress: () => _removeWithUndo(history, entry),
          ),
        ),
      );
    }
    return rows;
  }

  /// "Verify again" now lives on [_DetailsSheet] so the details sheet can
  /// trigger it directly with its own context.

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<VerifyHistory>();
    final s = context.watch<LocaleController>().strings;
    final entries = history.entries;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _searchOpen ? _buildSearchField(s, isDark) : Text(s.historyTitle),
        actions: [
          if (entries.isNotEmpty && !_searchOpen)
            IconButton(
              tooltip: s.exportTooltip,
              icon: const Icon(Icons.share_outlined, size: 20),
              onPressed: () => _shareHistory(history),
            ),
          if (entries.isNotEmpty)
            IconButton(
              tooltip: _searchOpen
                  ? s.cancel
                  : s.historySearchTooltip,
              icon: Icon(
                _searchOpen
                    ? Icons.close_rounded
                    : Icons.search_rounded,
                size: 21,
              ),
              onPressed: () =>
                  _searchOpen ? _closeSearch() : setState(() => _searchOpen = true),
            ),
          if (entries.isNotEmpty && !_searchOpen)
            IconButton(
              tooltip: s.clearHistoryTooltip,
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(s.clearHistoryTitle),
                    content: Text(s.clearHistoryBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(s.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(s.clearButton),
                      ),
                    ],
                  ),
                );
                if (ok == true) await history.clear();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final cloud = context.read<CloudController>();
          final history = context.read<VerifyHistory>();
          await cloud.pollNow(history);
          await cloud.refreshAnnouncements();
        },
        child: entries.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: _EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: s.noChecksTitle,
                      body: s.noChecksBody,
                      ctaLabel: s.emptyCta,
                      onCta: () => context.read<AppTab>().switchTo(0),
                    ),
                  ),
                ),
              )
            : Column(
                children: [
                  _StatsBar(entries: entries),
                  _FilterBar(
                    filter: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                  Expanded(
                    child: Builder(builder: (context) {
                      final visible = _filtered(entries);
                      if (visible.isEmpty) {
                        return LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight),
                              child: _EmptyState(
                                icon: Icons.search_off_rounded,
                                title: s.noMatchesTitle,
                                body: s.noMatchesBody,
                              ),
                            ),
                          ),
                        );
                      }
                      final rows = _buildRows(s, visible, history);
                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => rows[index],
                      );
                    }),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchField(AppStrings s, bool isDark) {
    return TextField(
      controller: _searchCtrl,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: s.historySearchHint,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
        ),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
              ),
        isDense: true,
        filled: true,
        fillColor: isDark ? MahtemPalette.dCard : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: MahtemPalette.green, width: 1.4),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, HistoryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _DetailsSheet(entryId: entry.id),
    );
  }
}

/// Details sheet for one entry. Watches history so edits made while it
/// is open — a reason note saved from its own "Add reason" button —
/// show up immediately without reopening the sheet.
class _DetailsSheet extends StatelessWidget {
  final String entryId;

  const _DetailsSheet({required this.entryId});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<VerifyHistory>();
    final entry = history.getById(entryId);
    if (entry == null) return const SizedBox.shrink();
    final s = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  entry.isVerified
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: entry.isVerified
                      ? MahtemPalette.green
                      : MahtemPalette.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.isVerified
                        ? s.verifiedPaymentLabel
                        : s.notVerifiedLabel,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? MahtemPalette.dInk
                          : MahtemPalette.navy,
                    ),
                  ),
                ),
                Text(
                  formatAmount(entry.amount, entry.currency),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: entry.isVerified
                        ? MahtemPalette.green
                        : MahtemPalette.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Detail(label: s.bankShortLabel, value: entry.bankName),
            _Detail(label: s.referenceShortLabel, value: entry.reference),
            if (entry.title.isNotEmpty)
              _Detail(label: s.senderLabel, value: entry.title),
            if ((entry.receiverName ?? '').isNotEmpty)
              _Detail(label: s.receiverLabel, value: entry.receiverName!),
            if ((entry.receiptDate ?? '').isNotEmpty)
              _Detail(label: s.dateLabel, value: entry.receiptDate!),
            _Detail(
              label: s.checkedLabel,
              value: formatReceiptDate(
                DateTime.fromMillisecondsSinceEpoch(entry.verifiedAt)
                    .toIso8601String(),
              ),
            ),
            if ((entry.message ?? '').isNotEmpty)
              _Detail(label: s.noteLabel, value: entry.message!),
            if ((entry.reason ?? '').isNotEmpty)
              _Detail(label: s.yourReasonLabel, value: entry.reason!),
            if (entry.reference.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Pressable(
                onTap: () => _verifyAgain(context, entry),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: MahtemPalette.buttonGradient,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        s.verifyAgain,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark
                        ? MahtemPalette.dBorder
                        : MahtemPalette.lBorder,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => showReasonSheet(context, entryId),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (entry.reason ?? '').isEmpty
                          ? Icons.add_comment_outlined
                          : Icons.edit_outlined,
                      size: 16,
                      color: isDark
                          ? MahtemPalette.dInkDim
                          : MahtemPalette.lInkDim,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      (entry.reason ?? '').isEmpty
                          ? s.addReasonAction
                          : s.editReasonAction,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? MahtemPalette.dInkDim
                            : MahtemPalette.lInkDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Verify again": prefill the form with this entry's bank + reference,
  /// switch to the Verify tab and let the user run the check. No network
  /// call fires here — the user stays in control (and no check burns).
  void _verifyAgain(BuildContext context, HistoryEntry entry) {
    final reference = entry.reference.trim();
    if (reference.isEmpty) return;
    // Capture everything the toast needs BEFORE the sheet pops — the
    // sheet's context is defunct afterwards.
    final strings = context.read<LocaleController>().strings;
    final controller = context.read<VerifyController>();
    controller.resetAll();
    final bank = bankByIdAll(entry.bankId);
    if (bank != null) controller.manualBank = bank;
    controller.setReference(reference);
    context.read<AppTab>().switchTo(0);
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(); // close the details sheet
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(strings.prefilledToast),
      ),
    );
  }
}

/// Status filter chips — All / Verified / Not verified.
class _FilterBar extends StatelessWidget {
  final _HistoryFilter filter;
  final ValueChanged<_HistoryFilter> onSelected;

  const _FilterBar({required this.filter, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget chip(_HistoryFilter value, String label, {IconData? icon}) {
      final selected = filter == value;
      return Pressable(
        onTap: () => onSelected(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? MahtemPalette.green
                : (isDark ? MahtemPalette.dCard : Colors.white),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? MahtemPalette.green
                  : (isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: selected ? Colors.white : MahtemPalette.green,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : (isDark
                          ? MahtemPalette.dInkDim
                          : MahtemPalette.lInkDim),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Wrap(
        spacing: 8,
        children: [
          chip(_HistoryFilter.all, s.filterAll, icon: Icons.list_rounded),
          chip(_HistoryFilter.verified, s.filterVerified,
              icon: Icons.check_circle_rounded),
          chip(_HistoryFilter.failed, s.filterFailed,
              icon: Icons.cancel_rounded),
        ],
      ),
    );
  }
}

/// Summary strip: total checks, verified count and the sum of verified
/// amounts. Values scale down (FittedBox) so a large total or long
/// localized label can never overflow a 320dp row.
class _StatsBar extends StatelessWidget {
  final List<HistoryEntry> entries;

  const _StatsBar({required this.entries});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified =
        entries.where((e) => e.isVerified).toList(growable: false);
    final total = verified.fold<double>(
      0,
      (sum, e) => sum + (e.amount ?? 0),
    );

    Widget cell(String value, String label, Color valueColor) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
              ),
            ),
          ],
        ),
      );
    }

    final divider = Container(
      width: 1,
      height: 28,
      color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
    );
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.navy;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: isDark ? MahtemPalette.dCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
        ),
      ),
      child: Row(
        children: [
          cell('${entries.length}', s.statsChecks, ink),
          divider,
          cell('${verified.length}', s.statsVerified, MahtemPalette.green),
          divider,
          cell(formatAmount(total, 'ETB'), s.statsTotal, ink),
        ],
      ),
    );
  }
}

/// Small faint header above a date group (Today / Yesterday / …).
class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
        ),
      ),
    );
  }
}

/// Shared empty state: no checks at all, or no matches for search/filter.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  /// Optional call-to-action shown under the copy — the "no checks yet"
  /// state jumps to the Verify tab.
  final String? ctaLabel;
  final VoidCallback? onCta;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.ctaLabel,
    this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 44,
            color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
            ),
          ),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 16),
            Pressable(
              onTap: onCta,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: MahtemPalette.buttonGradient,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  ctaLabel!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;

  const _Detail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _EntryCard({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bank = bankByIdAll(entry.bankId);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? MahtemPalette.dCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
          ),
        ),
        child: Row(
          children: [
            if (bank != null)
              BankAvatar(bank: bank, size: 32, radius: 16)
            else
              const Icon(Icons.receipt_long_rounded, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                    ),
                  ),
                  Text(
                    '${entry.bankName} · ${entry.reference}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? MahtemPalette.dInkDim
                          : MahtemPalette.lInkDim,
                    ),
                  ),
                  if ((entry.reason ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            size: 11,
                            color: MahtemPalette.green
                                .withValues(alpha: isDark ? 0.8 : 1),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry.reason!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? MahtemPalette.dInkDim
                                    : MahtemPalette.lInkDim,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatAmount(entry.amount, entry.currency),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: entry.isVerified
                        ? MahtemPalette.green
                        : MahtemPalette.red,
                  ),
                ),
                Icon(
                  entry.isVerified
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: entry.isVerified
                      ? MahtemPalette.green
                      : MahtemPalette.red,
                  size: 14,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
