import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/banks_registry.dart';
import '../../core/cheki_client.dart';
import '../../state/verify_controller.dart';
import '../../theme/cheki_theme.dart';
import '../../util/format.dart';
import '../widgets/confetti.dart';

/// Result — "Verification Result" per the design: a big status circle,
/// headline, and a white card of icon-circle detail rows.
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
        appBar: AppBar(title: const Text('Verification Result')),
        body: const Center(child: Text('No receipt to display.')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = result.isVerified;
    final bankName = bank?.name ??
        result.bankName ??
        (result.bank ?? 'bank').toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Result')),
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

                // Big status circle.
                _StatusCircle(verified: verified),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    verified ? 'Payment Verified!' : 'Verification Failed',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: verified
                          ? ChekiPalette.green
                          : ChekiPalette.red,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    verified
                        ? 'The payment details are valid and confirmed.'
                        : (result.error ??
                            result.reason ??
                            'This receipt could not be verified.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: isDark
                          ? ChekiPalette.dInkDim
                          : ChekiPalette.lInkDim,
                    ),
                  ),
                ),

                // Geo-blocked fallback: open the receipt directly.
                if (!verified && result.fallbackUrl != null) ...[
                  const SizedBox(height: 14),
                  _FallbackButton(url: result.fallbackUrl!),
                ],

                const SizedBox(height: 22),

                // Detail card.
                _DetailCard(
                  bankName: bankName,
                  result: result,
                  controller: controller,
                ),

                const SizedBox(height: 14),

                // Info banner (design's blue "secure gateway" note).
                _InfoBanner(verified: verified),

                const SizedBox(height: 20),

                if (verified) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _GhostButton(
                          icon: Icons.copy_rounded,
                          label: 'Copy',
                          isDark: isDark,
                          onTap: () => _copyResult(context, controller),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GhostButton(
                          icon: Icons.share_rounded,
                          label: 'Share',
                          isDark: isDark,
                          onTap: () => _shareResult(context, controller),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],

                // Primary action.
                _GradientButton(
                  label: verified ? 'Done' : 'Try Again',
                  onPressed: () {
                    if (verified) {
                      controller.resetAll();
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                const SizedBox(height: 10),
                _WhiteButton(
                  label: verified ? 'Verify Another' : 'Close',
                  isDark: isDark,
                  onPressed: () {
                    controller.resetAll();
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Data comes straight from ${bank?.shortName ?? 'the bank'} '
                    '— cheki never stores receipts.',
                    textAlign: TextAlign.center,
                    style: monoStyle(
                      size: 9,
                      color: isDark
                          ? ChekiPalette.dInkFaint
                          : ChekiPalette.lInkFaint,
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

// ─────────────────────────────────────────────────────── status circle

class _StatusCircle extends StatelessWidget {
  final bool verified;
  const _StatusCircle({required this.verified});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.4, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.elasticOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: verified
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: ChekiPalette.buttonGradient,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFF87171), Color(0xFFEF4444)],
                  ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (verified ? ChekiPalette.green : ChekiPalette.red)
                    .withValues(alpha: 0.35),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            verified ? Icons.check_rounded : Icons.close_rounded,
            color: Colors.white,
            size: 52,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── detail card

class _DetailCard extends StatelessWidget {
  final String bankName;
  final VerifyResult result;
  final VerifyController controller;

  const _DetailCard({
    required this.bankName,
    required this.result,
    required this.controller,
  });

  String _maskAccount(String? account) {
    if (account == null || account.isEmpty) return '';
    if (account.contains('*')) return account; // already masked by bank
    if (account.length <= 4) return account;
    final keep = account.length >= 8 ? 4 : 2;
    return '${account.substring(0, account.length - keep).replaceAll(RegExp(r'.'), '*')}${account.substring(account.length - keep)}';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <DetailRow>[
      DetailRow(
        icon: Icons.storefront_rounded,
        label: 'From',
        value: result.senderName?.trim(),
      ),
      DetailRow(
        icon: Icons.person_rounded,
        label: 'To',
        value: result.receiverName?.trim(),
      ),
      DetailRow(
        icon: Icons.payments_rounded,
        label: 'Amount',
        value: result.amount != null
            ? formatAmount(result.amount, result.currency)
            : null,
        bold: true,
      ),
      DetailRow(
        icon: Icons.calendar_month_rounded,
        label: 'Date & Time',
        value: formatReceiptDate(result.date),
      ),
      DetailRow(
        icon: Icons.numbers_rounded,
        label: 'Transaction ID',
        value: result.reference ?? controller.reference,
        mono: true,
        copyable: true,
      ),
      DetailRow(
        icon: Icons.account_balance_rounded,
        label: 'Payment Method',
        value: bankName,
      ),
      DetailRow(
        icon: Icons.location_on_outlined,
        label: 'Branch',
        value: result.branch?.trim(),
      ),
      DetailRow(
        icon: Icons.receipt_rounded,
        label: 'Sender Account',
        value: _maskAccount(result.senderAccount),
        mono: true,
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? ChekiPalette.dCard
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? ChekiPalette.dBorder
              : ChekiPalette.lBorder,
        ),
      ),
      child: Column(
        children: [
          for (final row in rows)
            if (row.hasValue) row,
        ],
      ),
    );
  }
}

/// One icon-in-circle detail row (the design's signature row style).
class DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool mono;
  final bool bold;
  final bool copyable;

  const DetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
    this.bold = false,
    this.copyable = false,
  });

  bool get hasValue => value != null && value!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
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
                  value!,
                  style: mono
                      ? monoStyle(
                          size: 11.5,
                          weight: FontWeight.w700,
                          color: ink,
                          letterSpacing: 0.3,
                        )
                      : TextStyle(
                          color: ink,
                          fontSize: bold ? 13.5 : 12.5,
                          fontWeight: bold
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy_rounded, size: 15, color: dim),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value!));
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────── banners & buttons

class _InfoBanner extends StatelessWidget {
  final bool verified;
  const _InfoBanner({required this.verified});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = verified
        ? (isDark ? ChekiPalette.blueSoftDark : ChekiPalette.blueSoft)
        : (isDark ? ChekiPalette.dCardAlt : ChekiPalette.redSoft);
    final color = verified ? ChekiPalette.blue : ChekiPalette.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            verified
                ? Icons.info_rounded
                : Icons.error_outline_rounded,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              verified
                  ? 'Fetched directly from the bank\u2019s official endpoint '
                      'and checked against the bank\u2019s own records.'
                  : 'Double-check the reference and account digits, or the '
                      'bank\u2019s endpoint may be temporarily down.',
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackButton extends StatelessWidget {
  final String url;
  const _FallbackButton({required this.url});

  @override
  Widget build(BuildContext context) {
    return _WhiteButton(
      label: 'Open Receipt in Browser',
      isDark: Theme.of(context).brightness == Brightness.dark,
      icon: Icons.open_in_browser_rounded,
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _GhostButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: ink),
        label: Text(
          label,
          style: TextStyle(
            color: ink,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _GradientButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: ChekiPalette.buttonGradient),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: ChekiPalette.green.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onPressed;
  final IconData? icon;

  const _WhiteButton({
    required this.label,
    required this.isDark,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final card = isDark ? ChekiPalette.dCard : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon != null
            ? Icon(icon, size: 18, color: ink)
            : const SizedBox.shrink(),
        label: Text(
          label,
          style: TextStyle(
            color: ink,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: card,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
