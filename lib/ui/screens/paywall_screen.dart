import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/licensing/license.dart';
import '../../core/licensing/paywall_config.dart';
import '../../core/licensing/receipt_activation.dart';
import '../../state/license_controller.dart';
import '../../theme/mahtem_theme.dart';
import '../widgets/confetti.dart';
import '../widgets/pressable.dart';

/// The paywall: trial status, the Telebirr payment details and the
/// self-activation box — the user pays the plan price, pastes the receipt
/// number from the confirmation SMS, and the app verifies that receipt
/// with its own engine and unlocks itself. No code, no chat app.
///
/// The owner-minted activation code stays as a fallback for edge cases
/// (failed receipt checks, gifts, support).
///
/// Pops `true` when a plan was activated, so the caller can resume the
/// verification the user was trying to run.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _receiptCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _checking = false; // receipt self-activation in flight
  bool _activating = false; // code fallback in flight
  String? _error; // receipt path
  String? _codeError; // code path
  bool _showCodeFallback = false;
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    context.read<LicenseController>().ensureLoaded();
  }

  @override
  void dispose() {
    _receiptCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── self-activation: pay → paste receipt number → app verifies it ────────

  Future<void> _verifyAndActivate() async {
    if (_checking) return;
    final raw = _receiptCtrl.text;
    if (raw.trim().isEmpty) {
      setState(() =>
          _error = 'Paste the receipt number from the Telebirr SMS.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final outcome =
        await context.read<LicenseController>().activateWithReceipt(raw);
    if (!mounted) return;
    setState(() => _checking = false);

    if (outcome is ReceiptActivationSuccess) {
      await _celebrate(outcome.expiryUtc);
      return;
    }
    if (outcome is ReceiptActivationRejected) {
      setState(() => _error = outcome.message);
    } else if (outcome is ReceiptActivationError) {
      final failure = outcome.failure;
      final tip = failure.tips.isEmpty ? '' : ' ${failure.tips.first}';
      setState(() => _error = '${failure.message}$tip');
    }
    unawaited(HapticFeedback.vibrate());
  }

  // ── fallback: owner-minted activation code ────────────────────────────────

  Future<void> _activate() async {
    if (_activating) return;
    final controller = context.read<LicenseController>();
    final raw = _codeCtrl.text;
    if (raw.trim().isEmpty) {
      setState(() => _codeError = 'Paste the activation code you received.');
      return;
    }
    setState(() {
      _activating = true;
      _codeError = null;
    });
    final validation = await controller.activate(raw);
    if (!mounted) return;
    setState(() => _activating = false);

    if (validation is LicenseValid) {
      await _celebrate(validation.expiryUtc);
      return;
    }

    setState(() {
      _codeError = switch (validation) {
        LicenseBadFormat() =>
          "That doesn't look like a Mahtem activation code.",
        LicenseBadSignature() =>
          'This code is not valid — ask the sender to resend it.',
        LicenseWrongDevice() =>
          'This code was issued for a different device. Send the device '
              'code shown below with your payment.',
        LicenseExpired(:final expiryUtc) =>
          'This code expired on ${_fmt(expiryUtc)}. Buy a new one to renew.',
        _ => 'This code could not be accepted.',
      };
    });
    unawaited(HapticFeedback.vibrate());
  }

  Future<void> _celebrate(DateTime expiryUtc) async {
    setState(() {
      _celebrated = true;
      _error = null;
      _codeError = null;
    });
    unawaited(HapticFeedback.heavyImpact());
    final until = _fmt(expiryUtc);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MahtemPalette.greenDeep,
      content: Text('Mahtem Pro is active until $until 🎉'),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pasteInto(TextEditingController ctrl) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Your clipboard is empty — copy the number first.'),
        ));
      }
      return;
    }
    ctrl.text = text;
    setState(() {
      _error = null;
      _codeError = null;
    });
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(message),
    ));
  }

  static String _fmt(DateTime utc) {
    final local = utc.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final card = isDark ? MahtemPalette.dCard : MahtemPalette.lCard;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    return Scaffold(
      backgroundColor: isDark ? MahtemPalette.dBg : MahtemPalette.lBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: ink),
        title: Text('Mahtem Pro',
            style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _StatusCard(license: license),
              const SizedBox(height: 14),

              const _PriceCard(),
              const SizedBox(height: 14),

              _StepsCard(
                onCopyNumber: () => _copy(
                  '+251$kPayTelebirrDigits',
                  'Telebirr number +251$kPayTelebirrDigits copied — paste it '
                      'into the Telebirr app.',
                ),
                onCopyAmount: () => _copy(
                  '$kMonthlyPriceEtb',
                  'Amount $kMonthlyPriceEtb ETB copied.',
                ),
              ),
              const SizedBox(height: 14),

              _ReceiptActivationCard(
                controller: _receiptCtrl,
                error: _error,
                checking: _checking,
                card: card,
                border: border,
                ink: ink,
                dim: dim,
                onPaste: () => _pasteInto(_receiptCtrl),
                onVerify: _verifyAndActivate,
              ),
              const SizedBox(height: 10),

              Text(
                'One receipt activates one plan on this device. To renew, '
                'pay again and paste the fresh receipt number — paid days '
                'always stack.',
                style: TextStyle(color: dim, fontSize: 11.5, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Center(
                child: Pressable(
                  onTap: () =>
                      setState(() => _showCodeFallback = !_showCodeFallback),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showCodeFallback
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 17,
                        color: dim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showCodeFallback
                            ? 'Hide activation code'
                            : 'Have an activation code instead?',
                        style: TextStyle(
                          color: dim,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showCodeFallback) ...[
                const SizedBox(height: 10),
                _CodeFallbackCard(
                  controller: _codeCtrl,
                  deviceCode: license.deviceCode,
                  error: _codeError,
                  activating: _activating,
                  card: card,
                  border: border,
                  ink: ink,
                  dim: dim,
                  onCopyDeviceCode: () =>
                      _copy(license.deviceCode, 'Device code copied.'),
                  onPaste: () => _pasteInto(_codeCtrl),
                  onActivate: _activate,
                ),
              ],
            ],
          ),
          if (_celebrated) const Positioned.fill(child: ConfettiBurst()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cards
// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final LicenseController license;

  const _StatusCard({required this.license});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;

    final (icon, iconColor, bg, title, subtitle) = license.isEntitled
        ? (
            Icons.verified_rounded,
            MahtemPalette.green,
            isDark ? MahtemPalette.dCard : MahtemPalette.greenSoft,
            'Mahtem Pro is active',
            'Unlimited checks until ${_ProCard.fmtDate(license.expiresAt!)}.',
          )
        : license.trialsLeft > 0
            ? (
                Icons.stars_rounded,
                MahtemPalette.amber,
                isDark ? MahtemPalette.dCard : MahtemPalette.amberSoft,
                '${license.trialsLeft} free check${license.trialsLeft == 1 ? '' : 's'} left',
                'After that, activate Mahtem Pro below — your history and '
                    'settings stay untouched.',
              )
            : (
                Icons.lock_clock_rounded,
                MahtemPalette.red,
                isDark ? MahtemPalette.dCard : MahtemPalette.redSoft,
                'Free checks used up',
                'Activate below to keep verifying receipts — it takes a '
                    'minute.',
              );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 30),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: dim, fontSize: 12.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final card = isDark ? MahtemPalette.dCard : MahtemPalette.lCard;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$kMonthlyPriceEtb',
                  style: TextStyle(
                      color: ink,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w900)),
              Padding(
                padding: const EdgeInsets.only(left: 5, bottom: 3),
                child: Text('ETB / month',
                    style: TextStyle(
                        color: dim,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Unlimited receipt checks on every bank and wallet — CBE, '
            'Telebirr, BOA, M-Pesa and more.',
            style: TextStyle(color: dim, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Or pay $kYearlyPriceEtb ETB once for a whole year.',
            style: TextStyle(
                color: ink, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  final VoidCallback onCopyNumber;
  final VoidCallback onCopyAmount;

  const _StepsCard({
    required this.onCopyNumber,
    required this.onCopyAmount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final card = isDark ? MahtemPalette.dCard : MahtemPalette.lCard;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    final stepStyle = TextStyle(
        color: ink, fontSize: 13, fontWeight: FontWeight.w700, height: 1.4);
    final stepDim = TextStyle(color: dim, fontSize: 12.5, height: 1.5);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to activate', style: stepStyle.copyWith(fontSize: 15)),
          const SizedBox(height: 14),
          _Step(
            n: 1,
            title: 'Pay $kMonthlyPriceEtb ETB (or $kYearlyPriceEtb ETB / '
                'year) via Telebirr',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send the exact amount to this Telebirr account:',
                  style: stepDim,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        isDark ? MahtemPalette.dBg : MahtemPalette.lBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kPayTelebirrNumber,
                              style: TextStyle(
                                color: ink,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              kPayTelebirrName,
                              style: TextStyle(
                                  color: dim,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      Pressable(
                        onTap: onCopyNumber,
                        child: Icon(Icons.copy_rounded,
                            size: 18, color: dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Pressable(
                  onTap: onCopyAmount,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy_rounded,
                          size: 13, color: MahtemPalette.blue),
                      const SizedBox(width: 5),
                      Text('Copy amount — $kMonthlyPriceEtb ETB',
                          style: const TextStyle(
                              color: MahtemPalette.blue,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Step(
            n: 2,
            title: 'Paste the receipt number below',
            body: Text(
              'Telebirr sends a confirmation SMS with a receipt number '
              '(e.g. CHQ261Z4AB2C) — paste it here and the app checks it '
              'with Telebirr itself. If it is a real $kMonthlyPriceEtb ETB '
              'payment to the account above, Mahtem Pro unlocks '
              'instantly.',
              style: stepDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final Widget body;

  const _Step({required this.n, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 1),
          decoration: const BoxDecoration(
            color: MahtemPalette.green,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              body,
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptActivationCard extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final bool checking;
  final Color card;
  final Color border;
  final Color ink;
  final Color dim;
  final VoidCallback onPaste;
  final VoidCallback onVerify;

  const _ReceiptActivationCard({
    required this.controller,
    required this.error,
    required this.checking,
    required this.card,
    required this.border,
    required this.ink,
    required this.dim,
    required this.onPaste,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: error != null ? MahtemPalette.red : border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Telebirr receipt number',
              style: TextStyle(
                  color: ink, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: !checking,
            style: TextStyle(
                color: ink, fontSize: 14, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'e.g. CHQ261Z4AB2C',
              hintStyle: TextStyle(color: dim, fontWeight: FontWeight.w500),
              filled: true,
              fillColor: dim.withValues(alpha: 0.06),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!,
                style: const TextStyle(
                    color: MahtemPalette.red,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: checking ? null : onPaste,
                  icon: const Icon(Icons.content_paste_rounded, size: 17),
                  label: const Text('Paste'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Pressable(
                  onTap: checking ? null : onVerify,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: MahtemPalette.green,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: checking
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white),
                              ),
                              const SizedBox(width: 9),
                              Text('Checking with Telebirr…',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          )
                        : const Text('Verify & Activate',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeFallbackCard extends StatelessWidget {
  final TextEditingController controller;
  final String deviceCode;
  final String? error;
  final bool activating;
  final Color card;
  final Color border;
  final Color ink;
  final Color dim;
  final VoidCallback onCopyDeviceCode;
  final VoidCallback onPaste;
  final VoidCallback onActivate;

  const _CodeFallbackCard({
    required this.controller,
    required this.deviceCode,
    required this.error,
    required this.activating,
    required this.card,
    required this.border,
    required this.ink,
    required this.dim,
    required this.onCopyDeviceCode,
    required this.onPaste,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: error != null ? MahtemPalette.red : border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activation code',
              style: TextStyle(
                  color: ink, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Codes are bound to one device. If a receipt check ever fails, '
            'send this device code with your payment and a code is minted '
            'for this phone.',
            style: TextStyle(color: dim, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDarkBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    deviceCode.isEmpty ? '…' : deviceCode,
                    style: TextStyle(
                      color: ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Pressable(
                  onTap: onCopyDeviceCode,
                  child: Icon(Icons.copy_rounded, size: 18, color: dim),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: !activating,
            style: TextStyle(
                color: ink, fontSize: 14, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'MAH-XXXXXX-XXXXXX-…',
              hintStyle: TextStyle(color: dim, fontWeight: FontWeight.w500),
              filled: true,
              fillColor: dim.withValues(alpha: 0.06),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!,
                style: const TextStyle(
                    color: MahtemPalette.red,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: activating ? null : onPaste,
                  icon: const Icon(Icons.content_paste_rounded, size: 17),
                  label: const Text('Paste'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Pressable(
                  onTap: activating ? null : onActivate,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: MahtemPalette.green,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: activating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text('Activate',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color isDarkBg(BuildContext context) => _isDark(context)
      ? MahtemPalette.dBg
      : MahtemPalette.lBg;
}

class _ProCard {
  static String fmtDate(DateTime utc) {
    final local = utc.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
