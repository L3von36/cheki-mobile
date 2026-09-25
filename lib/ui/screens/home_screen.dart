import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_tab.dart';
import '../../state/system_status.dart';
import '../../state/verify_controller.dart';
import '../../theme/cheki_theme.dart';
import '../flow.dart';
import '../widgets/pressable.dart';

/// Home — the "Payment Verifier" landing from the design:
/// blue gradient hero, green Scan button, details form, quick tiles and a
/// live "System Online" banner fed by the real health endpoint.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showForm = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openForm() {
    setState(() => _showForm = true);
    HapticFeedback.selectionClick();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: ChekiPalette.green,
          onRefresh: () => context.read<SystemStatus>().refresh(),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
            children: [
              _TopBar(isDark: isDark),
              const SizedBox(height: 14),
              const _HeroCard(),
              const SizedBox(height: 14),
              _GradientButton(
                onPressed: () => openScanner(context),
                icon: Icons.qr_code_scanner_rounded,
                label: 'Scan QR Code',
              ),
              const SizedBox(height: 10),
              _WhiteButton(
                onPressed: _openForm,
                icon: Icons.keyboard_rounded,
                label: 'Enter Payment Details',
                isDark: isDark,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _showForm
                    ? _VerifyForm(controller: controller, isDark: isDark)
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 16),
              _QuickTiles(
                onHistory: () => context.read<AppTab>().switchTo(1),
                onSettings: () => context.read<AppTab>().switchTo(2),
                onHelp: _showHelpSheet,
              ),
              const SizedBox(height: 16),
              const _SystemBanner(),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelpSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _HelpSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────── top bar

class _TopBar extends StatelessWidget {
  final bool isDark;
  const _TopBar({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: ChekiPalette.buttonGradient),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.verified_user_rounded,
              color: Colors.white, size: 19),
        ),
        const SizedBox(width: 9),
        Text(
          'Cheki',
          style: TextStyle(
            color: ink,
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        Pressable(
          onTap: () => _showAboutSheet(context),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: ChekiPalette.blueSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: ChekiPalette.navy, size: 19),
          ),
        ),
      ],
    );
  }

  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _HelpSheet(about: true),
    );
  }
}

// ─────────────────────────────────────────────────────────────── hero

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ChekiPalette.heroGradient,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: ChekiPalette.blue.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verify Payments\nin Seconds',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Scan QR codes or enter details to confirm payments and '
                  'prevent fraud.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const _HeroArt(),
        ],
      ),
    );
  }
}

/// Two playful receipt cards with a QR + green check, echoing the design.
class _HeroArt extends StatelessWidget {
  const _HeroArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Back card (tilted).
          Positioned(
            right: 2,
            top: 2,
            child: Transform.rotate(
              angle: 0.14,
              child: Container(
                width: 62,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          // Front card with QR.
          Positioned(
            left: 0,
            top: 8,
            child: Transform.rotate(
              angle: -0.08,
              child: Container(
                width: 62,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(9),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_2_rounded,
                        size: 38, color: ChekiPalette.navy),
                    const SizedBox(height: 5),
                    Container(
                      height: 4,
                      width: 34,
                      decoration: BoxDecoration(
                        color: ChekiPalette.blueSoft,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 4,
                      width: 24,
                      decoration: BoxDecoration(
                        color: ChekiPalette.blueSoft,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Green check badge.
          Positioned(
            right: -2,
            bottom: 0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: ChekiPalette.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.4),
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── buttons

class _GradientButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _GradientButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: ChekiPalette.buttonGradient),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: ChekiPalette.green.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
}

class _WhiteButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isDark;

  const _WhiteButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final card = isDark ? ChekiPalette.dCard : Colors.white;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    return Pressable(
      onTap: onPressed,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(icon, color: ink, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: ink.withValues(alpha: 0.5),
                size: 22),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── verify form

class _VerifyForm extends StatelessWidget {
  final VerifyController controller;
  final bool isDark;

  const _VerifyForm({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final card = isDark ? ChekiPalette.dCard : Colors.white;
    final bank = controller.effectiveBank;
    final hasReference = controller.reference.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Reference field.
            TextField(
              onChanged: controller.setReference,
              textCapitalization: TextCapitalization.characters,
              style: monoStyle(
                size: 13,
                weight: FontWeight.w600,
                color: ink,
                letterSpacing: 0.4,
              ),
              decoration: InputDecoration(
                hintText: bank?.referenceExample ?? 'FT26140P01YB or link',
                prefixIcon: Icon(Icons.receipt_long_rounded,
                    size: 19, color: dim),
                suffixIcon: hasReference
                    ? IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.close_rounded, size: 17, color: dim),
                        onPressed: () => controller.setReference(''),
                      )
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Paste',
                        icon: Icon(Icons.content_paste_rounded,
                            size: 17, color: dim),
                        onPressed: () async {
                          final data =
                              await Clipboard.getData('text/plain');
                          final text = data?.text?.trim() ?? '';
                          if (text.isNotEmpty) controller.setReference(text);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),

            // Detection status / bank selector.
            _BankSelector(controller: controller, isDark: isDark),

            // Extra fields (account / phone) when the bank requires them.
            if (bank != null && bank.requiresAccount) ...[
              const SizedBox(height: 8),
              TextField(
                onChanged: controller.setAccount,
                keyboardType: TextInputType.number,
                style: monoStyle(size: 13, weight: FontWeight.w600, color: ink),
                decoration: InputDecoration(
                  hintText:
                      'Last ${bank.accountDigits} digits of receiving account',
                  prefixIcon:
                      Icon(Icons.account_balance_rounded, size: 19, color: dim),
                ),
              ),
            ],
            if (bank != null && bank.requiresPhone) ...[
              const SizedBox(height: 8),
              TextField(
                onChanged: controller.setPhone,
                keyboardType: TextInputType.phone,
                style: monoStyle(size: 13, weight: FontWeight.w600, color: ink),
                decoration: InputDecoration(
                  hintText: 'Phone number tied to the wallet',
                  prefixIcon:
                      Icon(Icons.phone_android_rounded, size: 19, color: dim),
                ),
              ),
            ],
            if (bank != null) ...[
              const SizedBox(height: 8),
              Text(
                bank.referenceFormat,
                style: TextStyle(color: dim, fontSize: 10.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 12),

            // Verify button.
            _VerifyButton(controller: controller, isDark: isDark),
          ],
        ),
      ),
    );
  }
}

class _BankSelector extends StatelessWidget {
  final VerifyController controller;
  final bool isDark;

  const _BankSelector({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final field = isDark ? ChekiPalette.dCardAlt : ChekiPalette.blueSoft;
    final bank = controller.effectiveBank;

    return Pressable(
      onTap: () => pickBankManually(context),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Icon(Icons.account_balance_rounded, size: 19, color: dim),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                bank != null
                    ? bank.name
                    : (hasText(controller.reference)
                        ? 'No bank detected — tap to pick'
                        : 'Auto-detect from reference'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bank != null ? ink : dim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (bank != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ChekiPalette.greenSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  controller.usingCbeNew ? 'CBE QR' : bank.shortName,
                  style: const TextStyle(
                    color: ChekiPalette.greenDeep,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: dim),
          ],
        ),
      ),
    );
  }

  static bool hasText(String s) => s.trim().isNotEmpty;
}

class _VerifyButton extends StatelessWidget {
  final VerifyController controller;
  final bool isDark;

  const _VerifyButton({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ready = controller.canVerify;
    final busy = controller.isVerifying;
    final hasRef = controller.reference.trim().isNotEmpty;

    final child = Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: ready || busy
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: ChekiPalette.buttonGradient,
              )
            : null,
        color: ready || busy ? null : (isDark
            ? ChekiPalette.dCardAlt
            : ChekiPalette.blueSoft),
        borderRadius: BorderRadius.circular(14),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Text(
              hasRef ? 'Verify Now' : 'Enter a reference to verify',
              style: TextStyle(
                color: ready || busy
                    ? Colors.white
                    : (isDark
                        ? ChekiPalette.dInkDim
                        : ChekiPalette.lInkDim),
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
    );

    return Pressable(
      scale: ready ? 0.97 : 1.0,
      onTap: ready && !busy
          ? () {
              // No bank detected → open the picker instead of a dead tap.
              if (controller.effectiveBank == null) {
                pickBankManually(context).then((picked) {
                  if (picked != null && context.mounted) {
                    runVerificationFlow(context);
                  }
                });
                return;
              }
              runVerificationFlow(context);
            }
          : null,
      child: child,
    );
  }
}

// ──────────────────────────────────────────────────────── quick tiles

class _QuickTiles extends StatelessWidget {
  final VoidCallback onHistory;
  final VoidCallback onSettings;
  final VoidCallback onHelp;

  const _QuickTiles({
    required this.onHistory,
    required this.onSettings,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? ChekiPalette.dCard : Colors.white;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final label = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    final tiles = [
      ('Recent', Icons.access_time_rounded, onHistory),
      ('History', Icons.receipt_long_rounded, onHistory),
      ('Settings', Icons.settings_rounded, onSettings),
      ('Help', Icons.help_rounded, onHelp),
    ];

    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          Expanded(
            child: Pressable(
              onTap: tiles[i].$3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: ChekiPalette.blueSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(tiles[i].$2, size: 18, color: ChekiPalette.navy),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      tiles[i].$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: label,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (i != tiles.length - 1) const SizedBox(width: 9),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────── system banner

class _SystemBanner extends StatelessWidget {
  const _SystemBanner();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<SystemStatus>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? ChekiPalette.dCard : Colors.white;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;

    final String title;
    final String subtitle;
    final Color color;
    final Color soft;
    final IconData icon;
    switch (status.level) {
      case 'online':
        title = 'System Online';
        subtitle = 'All services are running normally.';
        color = ChekiPalette.green;
        soft = ChekiPalette.greenSoft;
        icon = Icons.verified_user_rounded;
      case 'degraded':
        title = 'Partial Service';
        subtitle = 'Some bank endpoints are slow or down.';
        color = ChekiPalette.amber;
        soft = ChekiPalette.amberSoft;
        icon = Icons.warning_amber_rounded;
      default:
        title = 'Connection Issue';
        subtitle = 'Could not reach the verification service.';
        color = ChekiPalette.red;
        soft = ChekiPalette.redSoft;
        icon = Icons.cloud_off_rounded;
    }

    return Pressable(
      onTap: status.loading ? null : status.refresh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
              child: status.loading
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status.lastChecked == null
                        ? subtitle
                        : '$subtitle  Checked ${TimeOfDay.fromDateTime(status.lastChecked!).format(context)}',
                    style: TextStyle(
                      color: isDark
                          ? ChekiPalette.dInkDim
                          : ChekiPalette.lInkDim,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.refresh_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── help sheet

class _HelpSheet extends StatelessWidget {
  final bool about;
  const _HelpSheet({this.about = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: ChekiPalette.buttonGradient),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.verified_user_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Text(
                  about ? 'About Cheki' : 'How Cheki works',
                  style: TextStyle(
                      color: ink, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _step('1', 'Scan the QR code on the bank receipt, or paste the '
                'reference number / receipt link into the form.'),
            _step('2', 'Cheki detects the bank automatically — or pick it '
                'from the list of 10 supported banks.'),
            _step('3', 'We fetch the receipt straight from the bank\'s '
                'official endpoint and show the verified details.'),
            _step('4', 'Every check is saved to History so you can review '
                'and share receipts later. Nothing is stored online.'),
            const SizedBox(height: 12),
            Text(
              'Cheki is free, needs no signup, and never stores your '
              'receipts. Built for Ethiopia · chekiapp.vercel.app',
              style: TextStyle(color: dim, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String number, String text) {
    return Builder(builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final ink = isDark ? ChekiPalette.dInk : ChekiPalette.navy;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: ChekiPalette.blueSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                number,
                style: const TextStyle(
                  color: ChekiPalette.navy,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    color: ink, fontSize: 12, height: 1.5, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    });
  }
}
