import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/receipt_verify/models.dart';
import '../../state/verify_controller.dart';
import '../../theme/mahtem_theme.dart';
import '../../util/format.dart';
import '../widgets/confetti.dart';

/// Result — one status circle, the amount, the details that matter, and
/// clear next actions. Data comes straight from the stylepos verifier's
/// [VerifyResult]: either a [ReceiptData] or a [VerifyFailure] with tips.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final result = controller.result;

    if (result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verification Result')),
        body: const Center(child: Text('No receipt to display.')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = result.ok;
    final receipt = result.receipt;
    final failure = result.failure;
    final bankName = receipt?.bankName ??
        controller.effectiveBank?.name ??
        'bank';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Result'),
      ),
      body: Stack(
        children: [
          if (verified)
            const Positioned.fill(
              child: IgnorePointer(child: ConfettiBurst()),
            ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              children: [
                const SizedBox(height: 14),
                _StatusCircle(verified: verified),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    verified ? 'Payment Verified!' : 'Verification Failed',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: verified ? MahtemPalette.green : MahtemPalette.red,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    verified
                        ? 'This payment is real and confirmed by the bank.'
                        : (failure?.message ??
                            'This receipt could not be verified.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color:
                          isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
                    ),
                  ),
                ),
                if (!verified && (failure?.tips.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 14),
                  _TipsCard(tips: failure!.tips),
                ],
                const SizedBox(height: 22),

                if (verified && receipt != null) ...[
                  Center(
                    child: Text(
                      formatAmount(receipt.amount, receipt.currency),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color:
                            isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      bankName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? MahtemPalette.dInkDim
                            : MahtemPalette.lInkDim,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _DetailCard(receipt: receipt),
                  if (receipt.note != null &&
                      receipt.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _NoteCard(note: receipt.note!),
                  ],
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _GhostButton(
                        label: 'Done',
                        onTap: () {
                          controller.reset();
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GradientButton(
                        label: verified ? 'Share' : 'Try again',
                        onTap: verified
                            ? () => _shareResult(receipt!, bankName)
                            : () {
                                controller.reset();
                                Navigator.of(context).pop();
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _shareResult(ReceiptData receipt, String bankName) {
    final buffer = StringBuffer()
      ..writeln('Payment verified via Mahtem')
      ..writeln('Bank: $bankName')
      ..writeln('Reference: ${receipt.reference}')
      ..writeln('Amount: ${formatAmount(receipt.amount, receipt.currency)}')
      ..writeln('Sender: ${receipt.senderName ?? '-'}')
      ..writeln('Receiver: ${receipt.receiverName ?? '-'}')
      ..writeln('Date: ${receipt.date ?? '-'}');
    SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }
}

// ---------------------------------------------------------------- widgets

class _StatusCircle extends StatelessWidget {
  final bool verified;

  const _StatusCircle({required this.verified});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          color: verified ? MahtemPalette.greenSoft : MahtemPalette.redSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(
          verified ? Icons.check_rounded : Icons.close_rounded,
          color: verified ? MahtemPalette.green : MahtemPalette.red,
          size: 46,
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  final List<String> tips;

  const _TipsCard({required this.tips});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? MahtemPalette.dCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.arrow_right_rounded,
                      size: 15, color: MahtemPalette.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
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
    );
  }
}

class _NoteCard extends StatelessWidget {
  final String note;

  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? MahtemPalette.dCardAlt : MahtemPalette.blueSoft)
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: MahtemPalette.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final ReceiptData receipt;

  const _DetailCard({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? MahtemPalette.dCard : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          if (receipt.senderName != null)
            DetailRow(
              icon: Icons.person_outline_rounded,
              label: 'From',
              value: receipt.senderName,
            ),
          if (receipt.senderAccount != null)
            DetailRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'From account',
              value: receipt.senderAccount,
              mono: true,
            ),
          if (receipt.receiverName != null)
            DetailRow(
              icon: Icons.person_outline_rounded,
              label: 'To',
              value: receipt.receiverName,
            ),
          if (receipt.receiverAccount != null)
            DetailRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'To account',
              value: receipt.receiverAccount,
              mono: true,
            ),
          if (receipt.date != null)
            DetailRow(
              icon: Icons.schedule_rounded,
              label: 'Date',
              value: receipt.date,
            ),
          if (receipt.reference.isNotEmpty)
            DetailRow(
              icon: Icons.tag_rounded,
              label: 'Reference',
              value: receipt.reference,
              mono: true,
            ),
          if (receipt.reason != null && receipt.reason!.isNotEmpty)
            DetailRow(
              icon: Icons.notes_rounded,
              label: 'Reason',
              value: receipt.reason,
            ),
          if (receipt.transactionStatus != null &&
              receipt.transactionStatus!.isNotEmpty)
            DetailRow(
              icon: Icons.verified_outlined,
              label: 'Status',
              value: receipt.transactionStatus,
            ),
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool mono;

  const DetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = value ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark ? MahtemPalette.dCardAlt : MahtemPalette.blueSoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon,
                size: 14,
                color: isDark ? MahtemPalette.blueLight : MahtemPalette.blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark
                        ? MahtemPalette.dInkFaint
                        : MahtemPalette.lInkFaint,
                  ),
                ),
                const SizedBox(height: 1),
                SelectableText(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GradientButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: MahtemPalette.buttonGradient),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
