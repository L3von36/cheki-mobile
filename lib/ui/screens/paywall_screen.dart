import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/licensing/license.dart';
import '../../core/licensing/paywall_config.dart';
import '../../state/license_controller.dart';
import '../../theme/mahtem_theme.dart';
import '../widgets/confetti.dart';
import '../widgets/pressable.dart';

/// The paywall: shows the trial status, the Telebirr payment instructions,
/// THIS device's code (needed to mint a license) and the activation box.
///
/// Pops `true` when a license was activated, so the caller can resume the
/// verification the user was trying to run.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _codeCtrl = TextEditingController();
  bool _activating = false;
  String? _error;
  bool _celebrated = false;

  @override
  void initState() {
    super.initState();
    context.read<LicenseController>().ensureLoaded();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_activating) return;
    final controller = context.read<LicenseController>();
    final raw = _codeCtrl.text;
    if (raw.trim().isEmpty) {
      setState(() => _error = 'Paste the activation code you received.');
      return;
    }
    setState(() {
      _activating = true;
      _error = null;
    });
    final validation = await controller.activate(raw);
    if (!mounted) return;
    setState(() => _activating = false);

    if (validation is LicenseValid) {
      setState(() => _celebrated = true);
      unawaited(HapticFeedback.heavyImpact());
      final until = _fmt(validation.expiryUtc);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MahtemPalette.greenDeep,
        content: Text('Mahtem Pro is active until $until 🎉'),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _error = switch (validation) {
        LicenseBadFormat() =>
          "That doesn't look like a Mahtem activation code.",
        LicenseBadSignature() =>
          'This code is not valid — ask the sender to resend it.',
        LicenseWrongDevice() =>
          'This code was issued for a different device. Send the device '
              'code shown above with your payment.',
        LicenseExpired(:final expiryUtc) =>
          'This code expired on ${_fmt(expiryUtc)}. Buy a new one to renew.',
        _ => 'This code could not be accepted.',
      };
    });
    unawaited(HapticFeedback.vibrate());
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Your clipboard is empty — copy the code first.'),
        ));
      }
      return;
    }
    _codeCtrl.text = text;
    setState(() => _error = null);
  }

  Future<void> _copyDeviceCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Device code $code copied — send it with your payment.'),
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

          _PriceCard(),
          const SizedBox(height: 14),

          _StepsCard(
            deviceCode: license.deviceCode,
            onCopyDeviceCode: () => _copyDeviceCode(license.deviceCode),
          ),
          const SizedBox(height: 14),

          _ActivationCard(
            controller: _codeCtrl,
            error: _error,
            activating: _activating,
            celebrated: _celebrated,
            card: card,
            border: border,
            ink: ink,
            dim: dim,
            onPaste: _pasteCode,
            onActivate: _activate,
          ),
          const SizedBox(height: 10),

          Text(
            'Activation codes are bound to one device and expire with the '
            'plan — buying again for another phone? Send that phone\'s '
            'device code instead.',
            style: TextStyle(
              color: dim,
              fontSize: 11.5,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
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
        ],
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  final String deviceCode;
  final VoidCallback onCopyDeviceCode;

  const _StepsCard({
    required this.deviceCode,
    required this.onCopyDeviceCode,
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
            title: 'Pay $kMonthlyPriceEtb ETB via Telebirr',
            body: Text.rich(
              TextSpan(style: stepDim, children: [
                const TextSpan(text: 'Send to '),
                TextSpan(
                    text: kPayTelebirrNumber,
                    style: stepStyle.copyWith(fontWeight: FontWeight.w900)),
                TextSpan(text: ' ($kPayTelebirrName) and keep the receipt.'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _Step(
            n: 2,
            title: 'Send your device code + receipt',
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'We mint your personal activation code from this device '
                  'code:',
                  style: stepDim,
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? MahtemPalette.dBg
                        : MahtemPalette.lBg,
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
                        child: Icon(Icons.copy_rounded,
                            size: 18, color: dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Pressable(
                  onTap: () async {
                    final url = Uri.parse(kSupportTelegramLink);
                    try {
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                              'Find us on Telegram: $kSupportTelegram'),
                        ));
                      }
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.send_rounded,
                          size: 15, color: MahtemPalette.blue),
                      const SizedBox(width: 5),
                      Text('Open Telegram — $kSupportTelegram',
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
            n: 3,
            title: 'Paste the activation code below',
            body: Text(
              'Paste it exactly as received — extra spaces are fine.',
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

class _ActivationCard extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final bool activating;
  final bool celebrated;
  final Color card;
  final Color border;
  final Color ink;
  final Color dim;
  final VoidCallback onPaste;
  final VoidCallback onActivate;

  const _ActivationCard({
    required this.controller,
    required this.error,
    required this.activating,
    required this.celebrated,
    required this.card,
    required this.border,
    required this.ink,
    required this.dim,
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
            onChanged: (_) {},
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Pressable(
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
                                    strokeWidth: 2.4,
                                    color: Colors.white),
                              )
                            : const Text('Activate',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
