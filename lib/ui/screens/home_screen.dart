import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/banks_registry.dart';
import '../../core/models.dart';
import '../../state/theme_controller.dart';
import '../../state/verify_controller.dart';
import '../../theme/cheki_theme.dart';
import '../widgets/bank_avatar.dart';
import '../widgets/bank_picker_sheet.dart';
import '../widgets/dashed_divider.dart';
import '../widgets/verify_button.dart';
import 'banks_screen.dart';
import 'result_screen.dart';
import 'scan_screen.dart';

/// Home — the receipt verification form.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _referenceFocus = FocusNode();

  @override
  void dispose() {
    _referenceFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Scaffold(
      appBar: const _ChekiAppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _Hero(isDark: isDark, dim: dim),
            const SizedBox(height: 28),
            _ReferenceField(
              focusNode: _referenceFocus,
              onChanged: controller.setReference,
            ),
            const SizedBox(height: 10),
            const _DetectChip(),
            const SizedBox(height: 18),
            _BankSelector(controller: controller),
            _ConditionalFields(controller: controller),
            if (controller.effectiveBank?.geoBlocked ?? false) ...[
              const SizedBox(height: 12),
              _GeoNote(bank: controller.effectiveBank!),
            ],
            const SizedBox(height: 24),
            VerifyButton(
              loading: controller.isVerifying,
              onPressed:
                  controller.canVerify ? () => _runVerification(context) : null,
              loadingHint: _loadingHint(controller),
            ),
            const SizedBox(height: 14),
            _ScanOutlineButton(onTap: () => _openScanner(context)),
            if (controller.status == VerifyStatus.error &&
                controller.errorMessage != null) ...[
              const SizedBox(height: 20),
              _ErrorCard(message: controller.errorMessage!),
            ],
            const SizedBox(height: 36),
            _Footer(dim: dim, isDark: isDark),
          ],
        ),
      ),
    );
  }

  String _loadingHint(VerifyController controller) {
    final bank = controller.effectiveBank;
    if (bank == null) return 'Contacting cheki…';
    return switch (bank.id) {
      'cbe' => 'Reading the CBE receipt…',
      'telebirr' => 'Contacting Ethio Telecom…',
      'mpesa' => 'Contacting Safaricom…',
      'cbebirr' => 'Contacting CBE Birr…',
      _ => 'Fetching official receipt…',
    };
  }

  Future<void> _runVerification(BuildContext context) async {
    final controller = context.read<VerifyController>();
    unawaited(HapticFeedback.mediumImpact());
    final result = await controller.verify();
    if (!context.mounted) return;
    if (result != null && result.success) {
      unawaited(HapticFeedback.heavyImpact());
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ResultScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 320),
        ),
      );
    }
  }

  Future<void> _openScanner(BuildContext context) async {
    final detection = await Navigator.of(context).push<BankDetection>(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (detection != null && context.mounted) {
      context.read<VerifyController>().applyDetection(detection);
      FocusManager.instance.primaryFocus?.unfocus();
      await _runVerification(context);
    }
  }
}

// ─────────────────────────────────────────────────────────────── app bar

class _ChekiAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChekiAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return AppBar(
      title: Row(
        children: [
          Text(
            'cheki',
            style: monoStyle(size: 22, weight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(width: 2),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: ChekiPalette.green,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Scan QR receipt',
          icon: const Icon(Icons.qr_code_scanner_rounded),
          onPressed: () {
            final root = context;
            unawaited(
              Navigator.of(root)
                  .push<BankDetection>(
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  )
                  .then((d) {
                if (d != null && root.mounted) {
                  root.read<VerifyController>().applyDetection(d);
                }
              }),
            );
          },
        ),
        IconButton(
          tooltip: 'Toggle theme',
          icon: Icon(
            themeController.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
          ),
          onPressed: themeController.toggle,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────── hero

class _Hero extends StatelessWidget {
  final bool isDark;
  final Color dim;
  const _Hero({required this.isDark, required this.dim});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Is that payment\nreceipt real?',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(height: 1.12),
        ),
        const SizedBox(height: 10),
        Text(
          'Paste any Ethiopian bank receipt reference — cheki fetches the '
          'official record from the bank and tells you if it is genuine.',
          style: TextStyle(color: dim, fontSize: 14.5, height: 1.5),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────── reference field

class _ReferenceField extends StatelessWidget {
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _ReferenceField({required this.focusNode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: 'RECEIPT REFERENCE OR LINK'),
        const SizedBox(height: 8),
        TextField(
          focusNode: focusNode,
          onChanged: onChanged,
          controller: TextEditingController.fromValue(
            TextEditingValue(
              text: controller.reference,
              selection: TextSelection.collapsed(
                offset: controller.reference.length,
              ),
            ),
          ),
          style: monoStyle(size: 16, weight: FontWeight.w600),
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: 2,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'FT26140P01YB',
            suffixIcon: controller.reference.isEmpty
                ? IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(Icons.content_paste_rounded, size: 20),
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.trim().isNotEmpty) {
                        onChanged(data.text!.trim());
                        unawaited(HapticFeedback.selectionClick());
                      }
                    },
                  )
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => onChanged(''),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: monoStyle(
        size: 11,
        weight: FontWeight.w700,
        letterSpacing: 1.2,
        color: isDark ? ChekiPalette.dInkFaint : ChekiPalette.lInkFaint,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── detect chip

class _DetectChip extends StatelessWidget {
  const _DetectChip();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final detected = controller.detectedBank;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: detected == null
          ? const SizedBox(height: 0)
          : Padding(
              key: ValueKey(detected.id),
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: ChekiPalette.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Looks like ${detected.shortName}',
                    style: TextStyle(
                      color: ChekiPalette.green,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (controller.usingCbeNew) ...[
                    const SizedBox(width: 8),
                    MetaChip(
                      label: 'New CBE QR receipt',
                      color: isDark
                          ? ChekiPalette.dInkDim
                          : ChekiPalette.lInkDim,
                      icon: Icons.qr_code_rounded,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

// ────────────────────────────────────────────────────────── bank selector

class _BankSelector extends StatelessWidget {
  final VerifyController controller;
  const _BankSelector({required this.controller});

  @override
  Widget build(BuildContext context) {
    final bank = controller.effectiveBank;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.lInk;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openBankSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(14),
            color: Colors.transparent,
          ),
          child: Row(
            children: [
              BankAvatar(bank: bank, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank?.name ?? 'Select bank (or leave to auto-detect)',
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (bank != null)
                      Text(
                        bank.id == kCbeNewId
                            ? 'Verified with the new CBE receipt API'
                            : bank.referenceFormat,
                        style: TextStyle(color: dim, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.expand_more_rounded, color: dim),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBankSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<ChekiBank>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BankPickerSheet(),
    );
    if (selected != null) {
      controller.selectBank(selected);
    }
  }
}

// ─────────────────────────────────────────────── conditional extra fields

class _ConditionalFields extends StatelessWidget {
  final VerifyController controller;
  const _ConditionalFields({required this.controller});

  @override
  Widget build(BuildContext context) {
    final bank = controller.effectiveBank;
    if (bank == null || bank.id == kCbeNewId) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bank.requiresAccount) ...[
            const SizedBox(height: 16),
            _AccountField(bank: bank),
          ],
          if (bank.requiresPhone) ...[
            const SizedBox(height: 16),
            _PhoneField(bank: bank),
          ],
        ],
      ),
    );
  }
}

class _AccountField extends StatelessWidget {
  final ChekiBank bank;
  const _AccountField({required this.bank});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final digits = bank.accountDigits ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(
          text: '${bank.accountLabel.toUpperCase()} · LAST $digits DIGITS',
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: controller.setAccount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: digits,
          controller: TextEditingController.fromValue(
            TextEditingValue(
              text: controller.accountNumber,
              selection: TextSelection.collapsed(
                offset: controller.accountNumber.length,
              ),
            ),
          ),
          style: monoStyle(size: 16, weight: FontWeight.w600, letterSpacing: 1.5),
          decoration: InputDecoration(
            counterText: '',
            hintText: '•' * digits,
            helperText: 'Only the last $digits digits — never the full account.',
            helperMaxLines: 2,
          ),
        ),
      ],
    );
  }
}

class _PhoneField extends StatelessWidget {
  final ChekiBank bank;
  const _PhoneField({required this.bank});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: 'WALLET PHONE NUMBER'),
        const SizedBox(height: 8),
        TextField(
          onChanged: controller.setPhone,
          keyboardType: TextInputType.phone,
          controller: TextEditingController.fromValue(
            TextEditingValue(
              text: controller.phoneNumber,
              selection: TextSelection.collapsed(
                offset: controller.phoneNumber.length,
              ),
            ),
          ),
          style: monoStyle(size: 16, weight: FontWeight.w600),
          decoration: const InputDecoration(
            hintText: '09•• ••• ••••',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${bank.name} needs the phone number tied to the transaction.',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).brightness == Brightness.dark
                ? ChekiPalette.dInkFaint
                : ChekiPalette.lInkFaint,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────── geo note

class _GeoNote extends StatelessWidget {
  final ChekiBank bank;
  const _GeoNote({required this.bank});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ChekiPalette.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChekiPalette.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public_rounded, size: 17, color: ChekiPalette.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${bank.shortName} restricts direct access by region — cheki '
              'verifies through its own servers, so this works anywhere.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── scan button

class _ScanOutlineButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScanOutlineButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.lInk;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.qr_code_scanner_rounded, color: ink, size: 21),
        label: Text(
          'Scan receipt QR code',
          style: GoogleFonts.inter(
            color: ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── error card

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChekiPalette.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChekiPalette.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: ChekiPalette.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isDark ? ChekiPalette.dInk : ChekiPalette.lInk,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── footer

class _Footer extends StatelessWidget {
  final Color dim;
  final bool isDark;
  const _Footer({required this.dim, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DashedDivider(),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: dim),
            const SizedBox(width: 6),
            Text(
              'Free forever · No signup · Official bank data',
              style: monoStyle(size: 11, color: dim, letterSpacing: 0.3),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => unawaited(
            Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const BanksScreen()),
            ),
          ),
          child: Text(
            'See all 10 supported banks',
            style: TextStyle(
              color: ChekiPalette.green,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: ChekiPalette.green.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}
