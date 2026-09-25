import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/banks_registry.dart';
import '../../core/models.dart';
import '../../state/verify_controller.dart';
import '../../theme/cheki_theme.dart';
import '../flow.dart';
import '../widgets/bank_avatar.dart';
import '../widgets/bank_picker_sheet.dart';
import '../widgets/pressable.dart';
import '../widgets/ticker_strip.dart';
import '../widgets/verify_button.dart';

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

    var step = 0;
    Widget staged(Widget child) => _Stagger(index: step++, child: child);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        staged(const _Hero()),
        const SizedBox(height: 18),
        staged(_ReferenceField(
          focusNode: _referenceFocus,
          onChanged: controller.setReference,
        )),
        const SizedBox(height: 6),
        staged(const _DetectChip()),
        const SizedBox(height: 12),
        staged(_BankSelector(controller: controller)),
        staged(_QuickBanks(controller: controller)),
        staged(_ConditionalFields(controller: controller)),
        if (controller.effectiveBank?.geoBlocked ?? false) ...[
          const SizedBox(height: 10),
          staged(_GeoNote(bank: controller.effectiveBank!)),
        ],
        const SizedBox(height: 18),
        staged(VerifyButton(
          loading: controller.isVerifying,
          onPressed:
              controller.canVerify ? () => _runVerification(context) : null,
          loadingHint: _loadingHint(controller),
        )),
        if (controller.status == VerifyStatus.error &&
            controller.errorMessage != null) ...[
          const SizedBox(height: 14),
          staged(_ErrorCard(message: controller.errorMessage!)),
        ],
        const SizedBox(height: 26),
        staged(const _Footer()),
      ],
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

  Future<void> _runVerification(BuildContext context) =>
      runVerificationFlow(context);
}

// ─────────────────────────────────────────────────────── staggered entrance

/// Slides + fades its child in, staggered by [index] via an Interval curve
/// (no delayed timers — test-safe), producing the cascading "settle into
/// place" feel on first paint.
class _Stagger extends StatefulWidget {
  final int index;
  final Widget child;
  const _Stagger({required this.index, required this.child});

  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final begin = (0.09 * widget.index).clamp(0.0, 0.9);
    final curved = CurvedAnimation(
      parent: _c,
      curve: Interval(begin, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.05), end: Offset.zero)
            .animate(curved),
        child: widget.child,
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── hero

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Is that receipt real?',
                style: Theme.of(context)
                    .textTheme
                    .headlineLarge
                    ?.copyWith(height: 1.1),
              ),
              const SizedBox(height: 6),
              Text(
                'Paste a reference or scan the QR — cheki checks it against '
                'the bank\u2019s official record in seconds.',
                style: TextStyle(color: dim, fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const _WavingStamp(),
      ],
    );
  }
}

/// A tiny rubber stamp that rocks back and forth — pure personality.
class _WavingStamp extends StatefulWidget {
  const _WavingStamp();

  @override
  State<_WavingStamp> createState() => _WavingStampState();
}

class _WavingStampState extends State<_WavingStamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final angle = -0.14 + 0.14 * Curves.easeInOut.transform(_c.value);
        return Transform.rotate(
          angle: angle,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: ChekiPalette.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: ChekiPalette.green.withValues(alpha: 0.5),
              ),
            ),
            child: const Icon(
              Icons.approval_rounded,
              color: ChekiPalette.greenInk,
              size: 26,
            ),
          ),
        );
      },
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
        const SizedBox(height: 6),
        // When empty and unfocused the whole field is one big paste target;
        // once focused (or non-empty) it behaves like a normal text field.
        ListenableBuilder(
          listenable: focusNode,
          builder: (context, _) {
            final pasteTarget =
                controller.reference.isEmpty && !focusNode.hasFocus;
            return GestureDetector(
              onTap: pasteTarget
                  ? () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null &&
                          data!.text!.trim().isNotEmpty) {
                        onChanged(data.text!.trim());
                        unawaited(HapticFeedback.selectionClick());
                      } else {
                        focusNode.requestFocus();
                      }
                    }
                  : null,
              child: AbsorbPointer(
                absorbing: pasteTarget,
                child: TextField(
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
                  style: monoStyle(size: 14, weight: FontWeight.w600),
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'FT26140P01YB — or tap to paste',
                    suffixIcon: controller.reference.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.content_paste_rounded,
                                    size: 15, color: ChekiPalette.greenInk),
                                const SizedBox(width: 5),
                                Text(
                                  'PASTE',
                                  style: monoStyle(
                                    size: 9,
                                    weight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    color: ChekiPalette.greenInk,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : IconButton(
                            tooltip: 'Clear',
                            iconSize: 18,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => onChanged(''),
                          ),
                  ),
                ),
              ),
            );
          },
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
        size: 9.5,
        weight: FontWeight.w700,
        letterSpacing: 1.1,
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: detected == null
          ? const SizedBox(height: 0)
          : Padding(
              key: ValueKey(detected.id),
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: ChekiPalette.green,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Looks like ${detected.shortName}',
                    style: const TextStyle(
                      color: ChekiPalette.greenInk,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (controller.usingCbeNew) ...[
                    const SizedBox(width: 7),
                    Text(
                      'new CBE QR flow',
                      style: monoStyle(size: 10, color: ChekiPalette.greenInk),
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
    final isManual = controller.manualBank != null;

    return Pressable(
      onTap: () => _openBankSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: isManual
                ? ChekiPalette.green.withValues(alpha: 0.55)
                : border,
          ),
          borderRadius: BorderRadius.circular(13),
          color: isDark ? ChekiPalette.dField : ChekiPalette.lSurface,
        ),
        child: Row(
          children: [
            BankAvatar(bank: bank, size: 34, radius: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bank?.name ?? 'Auto-detect the bank',
                    style: TextStyle(
                      color: ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    bank == null
                        ? 'Recommended — we read it from the reference'
                        : (bank.id == kCbeNewId
                            ? 'New CBE receipt API'
                            : bank.referenceFormat),
                    style: TextStyle(color: dim, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more_rounded, color: dim, size: 20),
          ],
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

// ─────────────────────────────────────────────── quick bank chips

class _QuickBanks extends StatelessWidget {
  final VerifyController controller;
  const _QuickBanks({required this.controller});

  static const _ids = ['cbe', 'telebirr', 'boa', 'mpesa', 'dashen'];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faint = isDark ? ChekiPalette.dInkFaint : ChekiPalette.lInkFaint;
    final banks = [
      for (final id in _ids)
        kChekiBanks.firstWhere((b) => b.id == id, orElse: () => kChekiBanks.first),
    ];
    final current = controller.effectiveBank;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'POPULAR',
            style: monoStyle(
              size: 8.5,
              weight: FontWeight.w700,
              letterSpacing: 1.2,
              color: faint,
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: banks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final bank = banks[i];
                final active = current?.id == bank.id;
                return Pressable(
                  onTap: () =>
                      controller.selectBank(active ? null : bank),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: active
                          ? ChekiPalette.green.withValues(alpha: 0.12)
                          : (isDark
                              ? ChekiPalette.dField
                              : ChekiPalette.lSurface),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? ChekiPalette.green
                            : (isDark
                                ? ChekiPalette.dBorder
                                : ChekiPalette.lBorder),
                        width: active ? 1.4 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BankAvatar(bank: bank, size: 22, radius: 6),
                        const SizedBox(height: 3),
                        Text(
                          bank.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.1,
                            fontWeight:
                                active ? FontWeight.w800 : FontWeight.w600,
                            color: active
                                ? ChekiPalette.greenInk
                                : (isDark
                                    ? ChekiPalette.dInkDim
                                    : ChekiPalette.lInkDim),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bank.requiresAccount) ...[
            const SizedBox(height: 12),
            _AccountField(bank: bank),
          ],
          if (bank.requiresPhone) ...[
            const SizedBox(height: 12),
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
        const SizedBox(height: 6),
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
          style: monoStyle(size: 14.5, weight: FontWeight.w600, letterSpacing: 1.5),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(text: 'WALLET PHONE NUMBER'),
        const SizedBox(height: 6),
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
          style: monoStyle(size: 14.5, weight: FontWeight.w600),
          decoration: const InputDecoration(
            hintText: '09•• ••• ••••',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${bank.name} needs the phone number tied to the transaction.',
          style: TextStyle(
            fontSize: 10.5,
            color: isDark ? ChekiPalette.dInkFaint : ChekiPalette.lInkFaint,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ChekiPalette.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: ChekiPalette.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public_rounded, size: 15, color: ChekiPalette.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${bank.shortName} restricts access by region — cheki verifies '
              'through its own servers, so this works anywhere.',
              style: TextStyle(
                fontSize: 11,
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

// ─────────────────────────────────────────────────────────── error card

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ChekiPalette.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ChekiPalette.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: ChekiPalette.red, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isDark ? ChekiPalette.dInk : ChekiPalette.lInk,
                fontSize: 12,
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
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Column(
      children: [
        const BankTickerStrip(),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 11, color: dim),
            const SizedBox(width: 5),
            Text(
              'Free forever · No signup · Official bank data',
              style: monoStyle(size: 9.5, color: dim, letterSpacing: 0.3),
            ),
          ],
        ),
      ],
    );
  }
}
