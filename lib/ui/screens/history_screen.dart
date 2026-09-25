import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/banks_registry.dart';
import '../../core/verify_history.dart';
import '../../theme/cheki_theme.dart';
import '../../util/format.dart';
import '../widgets/bank_avatar.dart';

/// History — "Payment History" per the design: search bar, filter chips,
/// and a list of saved verifications with status pills.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

enum _Filter { all, verified, failed }

class _HistoryScreenState extends State<HistoryScreen> {
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final history = context.watch<VerifyHistory>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    final all = history.entries;
    final q = _query.trim().toLowerCase();
    final entries = all.where((e) {
      final matchesFilter = switch (_filter) {
        _Filter.all => true,
        _Filter.verified => e.isVerified,
        _Filter.failed => !e.isVerified,
      };
      if (!matchesFilter) return false;
      if (q.isEmpty) return true;
      final haystack = [
        e.title,
        e.bankName,
        e.reference,
        e.receiverName ?? '',
        if (e.amount != null) formatAmount(e.amount, e.currency),
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment History'),
        actions: [
          if (all.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_rounded, size: 20),
              onPressed: () => _confirmClear(context, history),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: ink, fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Search by name, ID or amount…',
                prefixIcon: Icon(Icons.search_rounded, size: 19, color: dim),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                _chip('All', _Filter.all),
                const SizedBox(width: 8),
                _chip('Successful', _Filter.verified),
                const SizedBox(width: 8),
                _chip('Failed', _Filter.failed),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: entries.isEmpty
                ? _EmptyState(hasAny: all.isNotEmpty, isDark: isDark)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, i) =>
                        _HistoryCard(entry: entries[i], isDark: isDark),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, _Filter value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? ChekiPalette.green : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? ChekiPalette.green : ChekiPalette.lBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : ChekiPalette.lInkDim,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, VerifyHistory history) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'All saved verifications will be removed from this device. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              history.clear();
              Navigator.of(dialogContext).pop();
            },
            style: TextButton.styleFrom(foregroundColor: ChekiPalette.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── list card

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final bool isDark;

  const _HistoryCard({required this.entry, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final card = isDark ? ChekiPalette.dCard : Colors.white;

    final bank = bankById(entry.bankId);
    final time = formatHistoryTime(entry.verifiedAt);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TransactionDetailsScreen(entryId: entry.id),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            bank != null
                ? BankAvatar(bank: bank, size: 42, radius: 21)
                : Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: entry.isVerified
                          ? ChekiPalette.greenSoft
                          : ChekiPalette.redSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      entry.isVerified
                          ? Icons.check_rounded
                          : Icons.close_rounded,
                      color: entry.isVerified
                          ? ChekiPalette.green
                          : ChekiPalette.red,
                      size: 20,
                    ),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.amount != null
                        ? '${formatAmount(entry.amount, entry.currency)}  ·  $time'
                        : '${bank?.shortName ?? entry.bankName}  ·  $time',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(verified: entry.isVerified),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18, color: dim),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool verified;
  const _StatusPill({required this.verified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: verified ? ChekiPalette.greenSoft : ChekiPalette.redSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        verified ? 'Verified' : 'Failed',
        style: TextStyle(
          color: verified ? ChekiPalette.greenDeep : ChekiPalette.red,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── empty state

class _EmptyState extends StatelessWidget {
  final bool hasAny;
  final bool isDark;

  const _EmptyState({required this.hasAny, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: ChekiPalette.blueSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasAny ? Icons.search_off_rounded : Icons.receipt_long_rounded,
              size: 36,
              color: ChekiPalette.navy,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            hasAny ? 'No matching results' : 'No verifications yet',
            style: TextStyle(
              color: dim,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasAny
                ? 'Try a different search or filter.'
                : 'Verified receipts will appear here —\ncheck one from the Home tab.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: dim.withValues(alpha: 0.8),
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────── transaction details screen

/// "Transaction Details" per the design — status banner + detail rows.
class TransactionDetailsScreen extends StatelessWidget {
  final String entryId;
  const TransactionDetailsScreen({super.key, required this.entryId});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<VerifyHistory>();
    final entry = history.getById(entryId);

    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction Details')),
        body: const Center(child: Text('This record no longer exists.')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = entry.isVerified;
    final bank = bankById(entry.bankId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            onPressed: () {
              history.remove(entry.id);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:
                    verified ? ChekiPalette.greenSoft : ChekiPalette.redSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: verified ? ChekiPalette.green : ChekiPalette.red,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      verified ? Icons.check_rounded : Icons.close_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verified
                              ? 'Payment Verified'
                              : 'Verification Failed',
                          style: TextStyle(
                            color: verified
                                ? ChekiPalette.greenDeep
                                : ChekiPalette.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          verified
                              ? 'This transaction is valid and confirmed.'
                              : (entry.message ??
                                  'This receipt could not be verified.'),
                          style: TextStyle(
                            color: verified
                                ? ChekiPalette.greenDeep.withValues(alpha: 0.85)
                                : ChekiPalette.red.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DetailRowsCard(
              entry: entry,
              bankName: bank?.name ?? entry.bankName,
            ),
            const SizedBox(height: 16),
            if (entry.fallbackUrl != null) ...[
              _LinkButton(url: entry.fallbackUrl!, isDark: isDark),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color:
                        isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
                  ),
                  backgroundColor: isDark ? ChekiPalette.dCard : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Back to Home',
                  style: TextStyle(
                    color: isDark ? ChekiPalette.dInk : ChekiPalette.navy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRowsCard extends StatelessWidget {
  final HistoryEntry entry;
  final String bankName;

  const _DetailRowsCard({required this.entry, required this.bankName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final card = isDark ? ChekiPalette.dCard : Colors.white;

    final rows = <(IconData, String, String?, bool)>[
      (Icons.storefront_rounded, 'Merchant / Sender', entry.senderName?.trim(), false),
      (Icons.person_rounded, 'Received By', entry.receiverName?.trim(), false),
      (
        Icons.payments_rounded,
        'Amount',
        entry.amount != null ? formatAmount(entry.amount, entry.currency) : null,
        true,
      ),
      (Icons.calendar_month_rounded, 'Date & Time', formatReceiptDate(entry.receiptDate), false),
      (Icons.numbers_rounded, 'Transaction ID', entry.reference, true),
      (Icons.account_balance_rounded, 'Payment Method', bankName, false),
      (Icons.schedule_rounded, 'Checked On', formatHistoryTime(entry.verifiedAt), false),
      (Icons.tag_rounded, 'Result', entry.isVerified ? 'Verified' : 'Failed', false),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          for (final (icon, label, value, mono) in rows)
            if (value != null && value.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: value == rows.last.$3 && rows.last.$3 == value
                          ? Colors.transparent
                          : border,
                      width: 0.7,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: ChekiPalette.blueSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 16, color: ChekiPalette.navy),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: dim,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            value,
                            style: mono
                                ? monoStyle(
                                    size: 11.5,
                                    weight: FontWeight.w700,
                                    color: ink,
                                    letterSpacing: 0.3,
                                  )
                                : TextStyle(
                                    color: ink,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                          ),
                        ],
                      ),
                    ),
                    if (label == 'Transaction ID')
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.copy_rounded, size: 15, color: dim),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: value));
                          HapticFeedback.selectionClick();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Transaction ID copied')),
                          );
                        },
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String url;
  final bool isDark;

  const _LinkButton({required this.url, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        icon: Icon(
          Icons.open_in_browser_rounded,
          size: 17,
          color: isDark ? ChekiPalette.dInk : ChekiPalette.navy,
        ),
        label: Text(
          'Open Receipt in Browser',
          style: TextStyle(
            color: isDark ? ChekiPalette.dInk : ChekiPalette.navy,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }
}

/// Compact timestamp for history rows: "Sep 25, 12:41".
String formatHistoryTime(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateFormat('d MMM, h:mm a').format(dt);
}
