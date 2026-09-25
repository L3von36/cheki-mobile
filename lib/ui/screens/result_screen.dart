import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/banks_registry.dart';
import '../../core/models.dart';
import '../../state/verify_controller.dart';
import '../../theme/mahtem_theme.dart';
import '../../util/format.dart';
import '../widgets/confetti.dart';

/// Result — one status circle, the amount, the five details that matter,
/// and clear next actions. Fee/metadata rows are intentionally gone.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final result = controller.result;
    final bank = controller.effectiveBank ?? bankById(result?.bank ?? '');

    if (result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verification Result')),
        body: const Center(child: Text('No receipt to display.')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = result.isVerified;
    final bankName =
        bank?.name ?? result.bankName ?? (result.bank ?? 'bank').toUpperCase();

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
                        : (result.error ??
                            result.reason ??
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
                const SizedBox(height: 22),

                if (verified) ...[
                  Center(
                    child: Text(
                      formatAmount(result.amount, result.currency),
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
                ],

                _DetailCard(result: result),

                if (!verified && result.fallbackUrl != null) ...[
                  const SizedBox(height: 14),
                  _OpenReceiptButton(url: result.fallbackUrl!),
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
                            ? () => _shareResult(result, bankName)
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

  void _shareResult(VerifyResult result, String bankName) {
    final buffer = StringBuffer()
      ..writeln('Payment verified via Mahtem')
      ..writeln('Bank: $bankName')
      ..writeln('Reference: ${result.reference ?? '-'}')
      ..writeln('Amount: ${formatAmount(result.amount, result.currency)}')
      ..writeln('Sender: ${result.senderName ?? '-'}')
      ..writeln('Receiver: ${result.receiverName ?? '-'}')
      ..writeln('Date: ${result.date ?? '-'}');
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

class _DetailCard extends StatelessWidget {
  final VerifyResult result;

  const _DetailCard({required this.result});

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
          if (result.senderName != null)
            DetailRow(
              icon: Icons.person_outline_rounded,
              label: 'From',
              value: result.senderName,
            ),
          if (result.receiverName != null)
            DetailRow(
              icon: Icons.person_outline_rounded,
              label: 'To',
              value: result.receiverName,
            ),
          if (result.date != null)
            DetailRow(
              icon: Icons.schedule_rounded,
              label: 'Date',
              value: result.date,
            ),
          if (result.reference != null)
            DetailRow(
              icon: Icons.tag_rounded,
              label: 'Reference',
              value: result.reference,
              mono: true,
            ),
          if (result.reason != null && (result.reason as String).isNotEmpty)
            DetailRow(
              icon: Icons.notes_rounded,
              label: 'Reason',
              value: result.reason,
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

class _OpenReceiptButton extends StatelessWidget {
  final String url;

  const _OpenReceiptButton({required this.url});

  @override
  Widget build(BuildContext context) {
    return _GhostButton(
      label: 'Open original receipt',
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
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
