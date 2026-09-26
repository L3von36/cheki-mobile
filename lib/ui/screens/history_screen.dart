import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/receipt_verify/extra_banks.dart';
import '../../core/verify_history.dart';
import '../../theme/mahtem_theme.dart';
import '../../util/format.dart';
import '../widgets/bank_avatar.dart';

/// History — one flat list of past checks. Tap an entry to see its details;
/// long-press to remove. No search bars, no filter chips.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<VerifyHistory>();
    final entries = history.entries;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear history?'),
                    content: const Text(
                        'All saved checks will be removed from this device.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Clear'),
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
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 44,
                    color:
                        isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No checks yet',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Verified receipts will appear here.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? MahtemPalette.dInkDim
                          : MahtemPalette.lInkDim,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _EntryCard(
                  entry: entry,
                  onTap: () => _showDetails(context, entry),
                  onLongPress: () => history.remove(entry.id),
                );
              },
            ),
    );
  }

  void _showDetails(BuildContext context, HistoryEntry entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
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
                        entry.isVerified ? 'Verified payment' : 'Not verified',
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
                _Detail(label: 'Bank', value: entry.bankName),
                _Detail(label: 'Reference', value: entry.reference),
                if (entry.title.isNotEmpty)
                  _Detail(label: 'From', value: entry.title),
                if ((entry.receiverName ?? '').isNotEmpty)
                  _Detail(label: 'To', value: entry.receiverName!),
                if ((entry.receiptDate ?? '').isNotEmpty)
                  _Detail(label: 'Date', value: entry.receiptDate!),
                _Detail(
                  label: 'Checked',
                  value: formatReceiptDate(
                    DateTime.fromMillisecondsSinceEpoch(entry.verifiedAt)
                        .toIso8601String(),
                  ),
                ),
                if ((entry.message ?? '').isNotEmpty)
                  _Detail(label: 'Note', value: entry.message!),
              ],
            ),
          ),
        );
      },
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
