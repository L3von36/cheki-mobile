import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/banks_registry.dart';
import '../../core/cheki_client.dart';
import '../../state/verify_controller.dart';
import '../../theme/cheki_theme.dart';
import '../../util/format.dart';
import '../widgets/bank_avatar.dart';
import '../widgets/confetti.dart';
import '../widgets/dashed_divider.dart';
import '../widgets/receipt_paper.dart';
import '../widgets/ticker_amount.dart';

/// Result — the verified receipt rendered on punched thermal paper.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final result = controller.result;
    final bank = controller.effectiveBank ?? bankById(result?.bank ?? '');

    if (result == null) {
      // Deep-link safety: nothing to show.
      return Scaffold(
        appBar: AppBar(title: const Text('Receipt')),
        body: const Center(child: Text('No receipt to display.')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    final verified = result.isVerified;
    final bankName = bank?.name ??
        result.bankName ??
        (result.bank ?? 'bank').toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification result'),
        actions: [
          IconButton(
            tooltip: 'Verify another',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () {
              context.read<VerifyController>().resetAll();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Celebration! Fires once when the receipt is genuine.
            if (verified)
              const Positioned.fill(
                child: IgnorePointer(child: ConfettiBurst()),
              ),
            Positioned.fill(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
            ReceiptPaper(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header row: bank identity + stamp.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OFFICIAL RECEIPT DATA',
                              style: monoStyle(
                                size: 9,
                                weight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: dim,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                BankAvatar(bank: bank, size: 30, radius: 9),
                                const SizedBox(width: 9),
                                Flexible(
                                  child: Text(
                                    bankName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      StampBadge(
                        kind: verified
                            ? StampKind.verified
                            : (result.reason != null
                                ? StampKind.pending
                                : StampKind.failed),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Amount hero.
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'AMOUNT',
                          style: monoStyle(
                            size: 9,
                            weight: FontWeight.w700,
                            letterSpacing: 1.5,
                            color: dim,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TickerAmount(
                          amount: result.amount,
                          currency: result.currency,
                          style: monoStyle(
                            size: 30,
                            weight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: isDark
                                ? ChekiPalette.dInk
                                : ChekiPalette.lInk,
                          ),
                        ),
                        if (result.totalPaid != null &&
                            result.totalPaid != result.amount)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              'total paid ${formatAmount(result.totalPaid, result.currency)}',
                              style: monoStyle(size: 10, color: dim),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                  DashedDivider(),
                  const SizedBox(height: 16),

                  if (!verified && result.reason != null) ...[
                    _ReasonBanner(reason: result.reason!),
                    const SizedBox(height: 14),
                  ],

                  // Detail rows.
                  _Row(
                    label: 'FROM',
                    value: result.senderName,
                    mono: false,
                    dim: dim,
                  ),
                  _Row(
                    label: 'FROM ACCOUNT',
                    value: maskAccount(result.senderAccount),
                    dim: dim,
                  ),
                  _Row(
                    label: 'TO',
                    value: result.receiverName,
                    mono: false,
                    dim: dim,
                  ),
                  _Row(
                    label: 'TO ACCOUNT',
                    value: maskAccount(result.receiverAccount),
                    dim: dim,
                  ),
                  _Row(
                    label: 'DATE',
                    value: formatReceiptDate(result.date),
                    dim: dim,
                  ),
                  CopyableRow(
                    label: 'REFERENCE',
                    value: result.reference ?? controller.reference,
                    dim: dim,
                  ),
                  _Row(
                    label: 'STATUS',
                    value: result.transactionStatus,
                    dim: dim,
                  ),
                  _Row(
                    label: 'INVOICE NO.',
                    value: result.invoiceNumber,
                    dim: dim,
                  ),
                  _Row(
                    label: 'BRANCH',
                    value: result.branch,
                    mono: false,
                    dim: dim,
                  ),
                  _Row(
                    label: 'SERVICE FEE',
                    value: result.serviceFee != null
                        ? formatAmount(result.serviceFee, result.currency)
                        : null,
                    dim: dim,
                  ),
                  _Row(
                    label: 'STAMP DUTY',
                    value: result.stampDuty != null
                        ? formatAmount(result.stampDuty, result.currency)
                        : null,
                    dim: dim,
                  ),
                  if (result.amountInWords != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '"${result.amountInWords}"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 11,
                          color: dim,
                          height: 1.5,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                  DashedDivider(),
                  const SizedBox(height: 12),

                  // Source + latency.
                  Row(
                    children: [
                      Icon(Icons.link_rounded, size: 12, color: dim),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Fetched from the bank\u2019s official endpoint',
                          style: monoStyle(size: 9, color: dim),
                        ),
                      ),
                      if (controller.lastDurationMs != null)
                        Text(
                          '${(controller.lastDurationMs! / 1000).toStringAsFixed(1)}s',
                          style: monoStyle(
                            size: 9,
                            color: ChekiPalette.green,
                            weight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Actions.
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () => _copyResult(context, controller),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.share_rounded,
                    label: 'Share',
                    onTap: () => _shareResult(context, controller),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  context.read<VerifyController>().resetAll();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                style: FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.primary,
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Verify another receipt',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),
            Center(
              child: Text(
                'Data comes straight from ${bank?.shortName ?? 'the bank'} \u2014 '
                'cheki never stores receipts.',
                textAlign: TextAlign.center,
                style: monoStyle(size: 9, color: dim),
              ),
            ),
          ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String maskAccount(String? account) {
    if (account == null || account.isEmpty) return '';
    if (account.contains('*')) return account; // already masked by bank
    if (account.length <= 4) return account;
    final keep = account.length >= 8 ? 4 : 2;
    return '${account.substring(0, account.length - keep).replaceAll(RegExp(r'.'), '*')}${account.substring(account.length - keep)}';
  }

  void _copyResult(BuildContext context, VerifyController controller) {
    final result = controller.result;
    if (result == null) return;
    final text = receiptSummary(
      bankName: controller.effectiveBank?.name ?? result.bank ?? 'Bank',
      reference: result.reference ?? controller.reference,
      amount: result.amount,
      currency: result.currency,
      sender: result.senderName,
      receiver: result.receiverName,
      date: formatReceiptDate(result.date),
      verified: result.isVerified,
      url: ChekiClient().receiptUrl(
        result.bank ?? '',
        result.reference ?? controller.reference,
      ),
    );
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Receipt copied to clipboard')),
    );
  }

  void _shareResult(BuildContext context, VerifyController controller) {
    final result = controller.result;
    if (result == null) return;
    final text = receiptSummary(
      bankName: controller.effectiveBank?.name ?? result.bank ?? 'Bank',
      reference: result.reference ?? controller.reference,
      amount: result.amount,
      currency: result.currency,
      sender: result.senderName,
      receiver: result.receiverName,
      date: formatReceiptDate(result.date),
      verified: result.isVerified,
      url: ChekiClient().receiptUrl(
        result.bank ?? '',
        result.reference ?? controller.reference,
      ),
    );
    SharePlus.instance.share(ShareParams(text: text, title: 'Cheki receipt'));
  }
}

// ─────────────────────────────────────────────────────────── pieces

class _ReasonBanner extends StatelessWidget {
  final String reason;
  const _ReasonBanner({required this.reason});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ChekiPalette.red.withValues(alpha: 0.08),
        border: Border.all(color: ChekiPalette.red.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 17, color: ChekiPalette.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: isDark ? ChekiPalette.dInk : ChekiPalette.lInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  final Color dim;
  final bool mono;

  const _Row({
    required this.label,
    required this.value,
    required this.dim,
    this.mono = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;
    if (!hasValue) return const SizedBox.shrink();
    final ink = Theme.of(context).brightness == Brightness.dark
        ? ChekiPalette.dInk
        : ChekiPalette.lInk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: monoStyle(
                size: 8.5,
                weight: FontWeight.w700,
                letterSpacing: 1.1,
                color: dim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value!,
              textAlign: TextAlign.right,
              style: mono
                  ? monoStyle(size: 12, weight: FontWeight.w600, color: ink)
                  : TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reference row with a copy affordance.
class CopyableRow extends StatelessWidget {
  final String label;
  final String value;
  final Color dim;

  const CopyableRow({
    super.key,
    required this.label,
    required this.value,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: monoStyle(
                size: 8.5,
                weight: FontWeight.w700,
                letterSpacing: 1.1,
                color: dim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: monoStyle(
                size: 12,
                weight: FontWeight.w700,
                color: ChekiPalette.green,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied')),
              );
            },
            child: Icon(Icons.copy_rounded, size: 14, color: dim),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.lInk;
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: ink),
        label: Text(
          label,
          style: GoogleFonts.inter(
            color: ink,
            fontWeight: FontWeight.w600,
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
