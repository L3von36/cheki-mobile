import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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

/// Status filter above the history list.
enum _HistoryFilter { all, verified, failed }

/// History — every past check, searchable and filterable (v1.7.0):
///   * search by reference, name or bank,
///   * status filter (all / verified / not verified),
///   * tap an entry for details, long-press to remove,
///   * "Verify again" prefill — jumps back to the Verify tab with the
///     entry's bank + reference already filled in.
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
        hit(entry.receiverName);
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

  void _closeSearch() {
    setState(() {
      _searchOpen = false;
      _searchCtrl.clear();
    });
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
      body: entries.isEmpty
          ? _EmptyState(
              icon: Icons.receipt_long_outlined,
              title: s.noChecksTitle,
              body: s.noChecksBody,
            )
          : Column(
              children: [
                _FilterBar(
                  filter: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                Expanded(
                  child: Builder(builder: (context) {
                    final visible = _filtered(entries);
                    if (visible.isEmpty) {
                      return _EmptyState(
                        icon: Icons.search_off_rounded,
                        title: s.noMatchesTitle,
                        body: s.noMatchesBody,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = visible[index];
                        return _EntryCard(
                          entry: entry,
                          onTap: () => _showDetails(context, entry),
                          onLongPress: () => history.remove(entry.id),
                        );
                      },
                    );
                  }),
                ),
              ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = context.read<LocaleController>().strings;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
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
              ],
            ),
          ),
        );
      },
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

/// Shared empty state: no checks at all, or no matches for search/filter.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
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
