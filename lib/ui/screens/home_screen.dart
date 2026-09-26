import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/receipt_verify/models.dart';
import '../../state/license_controller.dart';
import '../../state/verify_controller.dart';
import '../../theme/mahtem_theme.dart';
import '../flow.dart';
import '../screens/paywall_screen.dart';
import '../widgets/bank_avatar.dart';
import '../widgets/pressable.dart';

/// Verify tab — deliberately minimal:
///   bank selector → reference → (account / phone when required) → VERIFY.
/// No banners, no tiles, no marketing. Everything else lives one tap away.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _referenceCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    final controller = context.read<VerifyController>();
    _syncFromController(controller);
  }

  void _syncFromController(VerifyController controller) {
    _syncing = true;
    _referenceCtrl.text = controller.reference;
    _accountCtrl.text = controller.accountNumber;
    _phoneCtrl.text = controller.phoneNumber;
    _syncing = false;
  }

  @override
  void dispose() {
    _referenceCtrl.dispose();
    _accountCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VerifyController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: _buildAppBar(isDark),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _BankSelector(controller: controller),
            const SizedBox(height: 12),
            _Field(
              controller: _referenceCtrl,
              label: controller.effectiveBank?.referenceLabel ??
                  'Reference number or receipt link',
              hint: controller.effectiveBank?.referenceHint ??
                  'Paste a receipt link or type the number',
              icon: Icons.tag_rounded,
              onChanged: (v) {
                if (_syncing) return;
                controller.setReference(v);
              },
              trailing: _PasteButton(
                onPaste: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text?.trim();
                  if (text == null || text.isEmpty) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text('Clipboard is empty.'),
                        ),
                      );
                    }
                    return;
                  }
                  controller.setReference(text);
                  _syncFromController(controller);
                  setState(() {});
                },
              ),
            ),
            if (controller.effectiveBank?.helper case final helper?)
              _Hint(helper)
            else
              const _Hint(
                'Pick the bank or wallet that issued the receipt — '
                'receipt links and QR scans pick it automatically.',
              ),
            if (controller.effectiveBank != null &&
                controller.effectiveBank!.accountDigits > 0) ...[
              const SizedBox(height: 10),
              _Field(
                controller: _accountCtrl,
                label: controller.effectiveBank!.accountLabel,
                hint:
                    'Last ${controller.effectiveBank!.accountDigits} digits only',
                icon: Icons.account_balance_wallet_outlined,
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  if (_syncing) return;
                  controller.setAccount(v);
                },
              ),
            ],
            if (controller.effectiveBank?.requiresPhone == true) ...[
              const SizedBox(height: 10),
              _Field(
                controller: _phoneCtrl,
                label: 'Phone number on the wallet',
                hint: '09xxxxxxxx',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                onChanged: (v) {
                  if (_syncing) return;
                  controller.setPhone(v);
                },
              ),
            ],
            if (controller.detectedBank != null && controller.manualBank == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _DetectedChip(bank: controller.detectedBank!),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _verifyButton(controller, isDark)),
                if (controller.isVerifying) ...[
                  const SizedBox(width: 10),
                  const _StopButton(),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _ScanAltButton(onTap: () => openScanner(context)),
          ],
        ),
      ),
    );
  }

  /// The main VERIFY button. While a check is running it keeps the active
  /// gradient and shows a spinner — the [_StopButton] beside it aborts.
  Widget _verifyButton(VerifyController controller, bool isDark) {
    final active = controller.canVerify || controller.isVerifying;
    return Pressable(
      onTap:
          controller.canVerify ? () => runVerificationFlow(context) : null,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(colors: MahtemPalette.buttonGradient)
              : null,
          color: active
              ? null
              : (isDark ? MahtemPalette.dCardAlt : MahtemPalette.lBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: controller.isVerifying
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                'VERIFY RECEIPT',
                style: TextStyle(
                  color: controller.canVerify
                      ? Colors.white
                      : (isDark
                          ? MahtemPalette.dInkFaint
                          : MahtemPalette.lInkFaint),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: MahtemPalette.buttonGradient),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: Colors.white, size: 15),
          ),
          const SizedBox(width: 8),
          Text(
            'Mahtem',
            style: TextStyle(
              color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
      actions: [
        const Padding(
          padding: EdgeInsets.only(right: 12),
          child: Center(child: _LicenseChip()),
        ),
      ],
    );
  }
}

/// App-bar licensing chip: "PRO" when an active license exists, otherwise
/// the free checks remaining. Tapping opens the paywall.
class _LicenseChip extends StatelessWidget {
  const _LicenseChip();

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseController>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (label, bg, fg) = license.isEntitled
        ? (
            'PRO · ${license.daysLeft}d',
            MahtemPalette.green,
            Colors.white,
          )
        : (
            license.trialsLeft > 0
                ? '${license.trialsLeft} free left'
                : 'Upgrade',
            license.trialsLeft > 0
                ? (isDark ? MahtemPalette.dCardAlt : MahtemPalette.amberSoft)
                : MahtemPalette.amber,
            license.trialsLeft > 0
                ? (isDark ? MahtemPalette.dInk : MahtemPalette.lInk)
                : Colors.white,
          );

    return Pressable(
      onTap: () => Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- widgets

/// Square red stop control shown next to VERIFY while a check runs —
/// previously there was no way to cancel a slow verification.
class _StopButton extends StatelessWidget {
  const _StopButton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'Stop verifying',
      child: Pressable(
        onTap: () => context.read<VerifyController>().stopVerify(),
        child: Container(
          width: 54,
          height: 50,
          decoration: BoxDecoration(
            color: isDark ? MahtemPalette.dCard : MahtemPalette.redSoft,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MahtemPalette.red, width: 1.2),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.stop_rounded,
            color: MahtemPalette.red,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _BankSelector extends StatelessWidget {
  final VerifyController controller;

  const _BankSelector({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bank = controller.effectiveBank;

    return Pressable(
      onTap: () => pickBankManually(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? MahtemPalette.dCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
          ),
        ),
        child: Row(
          children: [
            if (bank != null) ...[
              BankAvatar(bank: bank, size: 34, radius: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      bank.referenceHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: MahtemPalette.blueSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: MahtemPalette.blue, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Auto-detect bank',
                  style: TextStyle(
                    color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            Icon(Icons.expand_more_rounded,
                color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
                size: 20),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final Widget? trailing;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.trailing,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? MahtemPalette.dCard : Colors.white;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: keyboardType,
          style: TextStyle(
            color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
              fontSize: 12,
            ),
            prefixIcon: Icon(icon,
                size: 18,
                color:
                    isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 40),
            suffixIcon: trailing,
            isDense: true,
            filled: true,
            fillColor: fill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: MahtemPalette.green, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _PasteButton extends StatelessWidget {
  final VoidCallback onPaste;

  const _PasteButton({required this.onPaste});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Paste',
      onPressed: onPaste,
      icon: const Icon(Icons.content_paste_rounded,
          size: 17, color: MahtemPalette.green),
    );
  }
}

class _DetectedChip extends StatelessWidget {
  final BankInfo bank;

  const _DetectedChip({required this.bank});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MahtemPalette.greenSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: MahtemPalette.greenDeep, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Detected: ${bank.shortName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MahtemPalette.greenDeep,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;

  const _Hint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: MahtemPalette.blue, size: 13),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? MahtemPalette.dInkDim
                    : MahtemPalette.lInkDim,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanAltButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ScanAltButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? MahtemPalette.dCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner_rounded,
                color: MahtemPalette.green, size: 18),
            const SizedBox(width: 8),
            Text(
              'Scan the QR code instead',
              style: TextStyle(
                color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
