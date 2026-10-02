import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/batch_parse.dart';
import '../../core/localization/app_strings.dart';
import '../../core/receipt_verify/models.dart';
import '../../core/verify_history.dart';
import '../../state/batch_controller.dart';
import '../../state/license_controller.dart';
import '../../state/locale_controller.dart';
import '../../theme/mahtem_theme.dart';
import '../../util/format.dart';
import '../widgets/bank_avatar.dart';
import '../widgets/bank_picker_sheet.dart';
import '../widgets/pressable.dart';
import 'paywall_screen.dart';

/// Batch check (v1.12.0) — paste many references, one per line, and
/// check them all sequentially on-device. Built for the end-of-day till
/// reconciliation the competition apps call "batch verification".
///
/// Licensing: one attempt per checked row, charged right before each
/// check; skipped rows (duplicates, CBE printed numbers, unknown links)
/// are never charged. A batch larger than the remaining attempts is
/// refused up front with the paywall offered.
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final _textCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  BankInfo? _bank;

  @override
  void dispose() {
    _textCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  void _reparse() {
    context.read<BatchController>().load(
          parseBatchLines(
            _textCtrl.text,
            bank: _bank,
            account: _accountCtrl.text,
          ),
        );
  }

  Future<void> _pickBank() async {
    final bank = await showModalBottomSheet<BankInfo>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BankPickerSheet(selectedId: _bank?.id),
    );
    if (bank == null || !mounted) return;
    setState(() {
      _bank = bank;
      _accountCtrl.clear();
    });
    // Re-bind the bank onto every row (plain references follow the
    // batch bank; link/QR rows keep their own).
    _reparse();
  }

  Future<void> _start() async {
    final controller = context.read<BatchController>();
    final license = context.read<LicenseController>();
    final strings = context.read<LocaleController>().strings;
    await license.ensureLoaded();
    if (!mounted) return;

    // Pre-flight licensing: the batch must fit the remaining attempts.
    // An active plan is unlimited; on trial the whole batch must fit.
    if (!license.isEntitled && license.trialsLeft < controller.chargeableCount) {
      final activated = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(strings.upgrade),
          content: Text(strings.batchNeedMore(
            license.trialsLeft,
            controller.chargeableCount,
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.upgrade),
            ),
          ],
        ),
      );
      if (activated != true || !mounted) return;
      final opened = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
      if (opened != true || !mounted) return;
      // Re-check after the paywall — activation may have changed things.
      final refreshed = context.read<LicenseController>();
      await refreshed.ensureLoaded();
      if (!refreshed.isEntitled &&
          refreshed.trialsLeft < controller.chargeableCount) {
        return;
      }
    }

    await context.read<BatchController>().run(
          history: context.read<VerifyHistory>(),
          consumeAttempt: () async {
            final l = context.read<LicenseController>();
            // Nothing left to charge — stop before burning anything.
            if (!l.isEntitled && l.trialsLeft <= 0) return false;
            // consumeAttempt no-ops while entitled, so this is the
            // actual charge; the pre-flight gate already made sure the
            // batch fits.
            await l.consumeAttempt();
            return true;
          },
          duplicateNote: (when) => strings.duplicateReceiptNote(when),
          staleNote: (days) => strings.staleReceiptNote(days),
        );
  }

  Future<void> _shareResults() async {
    final controller = context.read<BatchController>();
    final strings = context.read<LocaleController>().strings;
    final buf = StringBuffer()
      ..writeln('Mahtem — ${strings.batchTitle}')
      ..writeln();
    for (final row in controller.rows) {
      if (row.isSkippedNow) continue;
      // Only finished rows carry a verdict worth sharing.
      if (row.status != BatchRowStatus.verified &&
          row.status != BatchRowStatus.failed) {
        continue;
      }
      final res = row.result;
      final ok = row.status == BatchRowStatus.verified;
      final line = StringBuffer('${row.reference} — ');
      if (ok) {
        line.write(strings.verifiedPaymentLabel);
        final amount = res?.receipt?.amount;
        if (amount != null) {
          line.write(
              ' · ${formatAmount(amount, res?.receipt?.currency)}');
        }
      } else {
        line.write(strings.notVerifiedLabel);
      }
      buf.writeln(line);
    }
    await SharePlus.instance.share(ShareParams(text: buf.toString()));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BatchController>();
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: Text(
          strings.batchTitle,
          style: TextStyle(
            color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (controller.chargeableCount > 0 &&
              (controller.verifiedCount + controller.failedCount) > 0)
            IconButton(
              tooltip: strings.batchShareTooltip,
              onPressed: _shareResults,
              icon: const Icon(Icons.ios_share_rounded, size: 20),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: controller.hasRows
                  ? _ResultsList(controller: controller)
                  : _InputStage(
                      textCtrl: _textCtrl,
                      accountCtrl: _accountCtrl,
                      bank: _bank,
                      onTextChanged: _reparse,
                      onPickBank: _pickBank,
                    ),
            ),
            _BottomBar(bank: _bank, onStart: _start),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input stage
// ─────────────────────────────────────────────────────────────────────────────

class _InputStage extends StatelessWidget {
  final TextEditingController textCtrl;
  final TextEditingController accountCtrl;
  final BankInfo? bank;
  final VoidCallback onTextChanged;
  final VoidCallback onPickBank;

  const _InputStage({
    required this.textCtrl,
    required this.accountCtrl,
    required this.bank,
    required this.onTextChanged,
    required this.onPickBank,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.navy;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final card = isDark ? MahtemPalette.dCard : MahtemPalette.lCard;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      children: [
        Text(
          strings.batchIntro,
          style: TextStyle(color: dim, fontSize: 12.5, height: 1.5),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: TextField(
            controller: textCtrl,
            onChanged: (_) => onTextChanged(),
            maxLines: 8,
            minLines: 5,
            style: TextStyle(color: ink, fontSize: 13.5, height: 1.5),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: strings.batchInputHint,
              hintStyle: TextStyle(color: dim, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _BankChip(
                bank: bank,
                onTap: onPickBank,
              ),
            ),
          ],
        ),
        if (bank != null && bank!.accountDigits > 0) ...[
          const SizedBox(height: 10),
          TextField(
            controller: accountCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: ink, fontSize: 13.5),
            onChanged: (_) => onTextChanged(),
            decoration: InputDecoration(
              labelText: bank!.accountLabel,
              helperText: strings.lastDigitsOnly(bank!.accountDigits),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
        if (bank?.requiresPhone == true) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 15, color: MahtemPalette.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  strings.batchNeedsPhone(bank!.name),
                  style: const TextStyle(
                      color: MahtemPalette.amber, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BankChip extends StatelessWidget {
  final BankInfo? bank;
  final VoidCallback onTap;

  const _BankChip({required this.bank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.navy;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    return Pressable(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isDark ? MahtemPalette.dCard : MahtemPalette.lCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            if (bank != null) ...[
              BankAvatar(bank: bank!),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                bank?.name ?? strings.batchBankLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bank != null ? ink : dim,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: dim, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results list
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsList extends StatelessWidget {
  final BatchController controller;

  const _ResultsList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      itemCount: controller.total,
      itemBuilder: (context, index) {
        final row = controller.rows[index];
        return _RowTile(row: row, isDark: isDark);
      },
    );
  }
}

class _RowTile extends StatelessWidget {
  final BatchRow row;
  final bool isDark;

  const _RowTile({required this.row, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().strings;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.navy;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final card = isDark ? MahtemPalette.dCard : MahtemPalette.lCard;

    final (icon, color) = switch (row.status) {
      BatchRowStatus.pending || BatchRowStatus.skipped => (
          row.status == BatchRowStatus.pending
              ? Icons.schedule_rounded
              : Icons.remove_circle_outline_rounded,
          dim,
        ),
      BatchRowStatus.running => (
          Icons.sync_rounded,
          MahtemPalette.blue,
        ),
      BatchRowStatus.verified => (
          Icons.check_circle_rounded,
          MahtemPalette.green,
        ),
      BatchRowStatus.failed => (
          Icons.error_rounded,
          MahtemPalette.red,
        ),
    };

    final res = row.result;
    final subtitle = StringBuffer();
    if (row.status == BatchRowStatus.verified && res?.receipt != null) {
      final amount = res!.receipt!.amount;
      if (amount != null) {
        subtitle.write(formatAmount(amount, res.receipt!.currency));
      }
    } else if (row.status == BatchRowStatus.failed) {
      final kind = res?.failure?.kind;
      if (kind != null) {
        subtitle.write(strings.failureMessage(
          kind,
          res!.failure!.message,
        ));
      }
    } else if (row.status == BatchRowStatus.skipped) {
      subtitle.write(_skipText(strings));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.reference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle.toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle.toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: row.status == BatchRowStatus.verified
                          ? dim
                          : (row.status == BatchRowStatus.failed
                              ? MahtemPalette.red
                              : dim),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
                if (row.advisory != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    row.advisory!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MahtemPalette.amber,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _skipText(AppStrings strings) => switch (row.skipReason) {
        BatchSkipReason.duplicate => strings.batchSkipDuplicate,
        BatchSkipReason.cbePrinted => strings.batchSkipCbe,
        BatchSkipReason.unknownLink => strings.batchSkipUnknown,
        BatchSkipReason.overLimit => strings.batchSkipOverLimit,
        null => strings.batchSkipDuplicate,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom bar — pre-flight summary + start / stop / progress
// ─────────────────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final BankInfo? bank;
  final Future<void> Function() onStart;

  const _BottomBar({required this.bank, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BatchController>();
    final license = context.watch<LicenseController>();
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;

    final needsBank = _countNeedingBank(controller) > 0;
    final phoneBlocked = bank?.requiresPhone == true;
    final canStart = controller.hasRows &&
        !controller.isRunning &&
        controller.chargeableCount > 0 &&
        !needsBank &&
        !phoneBlocked;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? MahtemPalette.dCard : Colors.white,
        border: Border(top: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.isRunning) ...[
              LinearProgressIndicator(
                value: controller.total == 0
                    ? null
                    : (controller.verifiedCount + controller.failedCount) /
                        controller.chargeableCount.clamp(1, 1 << 31),
                minHeight: 4,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusLine(controller, strings, license),
                    style: TextStyle(color: dim, fontSize: 11),
                  ),
                ),
                if (controller.isRunning)
                  Pressable(
                    onTap: controller.stop,
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? MahtemPalette.dCardAlt
                            : MahtemPalette.redSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        strings.stopVerifying,
                        style: const TextStyle(
                          color: MahtemPalette.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                else
                  _StartButton(
                    enabled: canStart,
                    count: controller.chargeableCount,
                    onTap: () => onStart(),
                  ),
              ],
            ),
            if (controller.isStoppedWithPending) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onStart,
                  child: Text(strings.batchRemaining(
                    controller.pendingCount,
                  )),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _countNeedingBank(BatchController controller) => controller.rows
      .where((r) =>
          !r.isSkippedNow &&
          r.status == BatchRowStatus.pending &&
          r.bankId == null &&
          r.scannedQr == null)
      .length;

  String _statusLine(
    BatchController controller,
    AppStrings strings,
    LicenseController license,
  ) {
    if (!controller.hasRows) return strings.batchEmpty;
    if (controller.isRunning) {
      return strings.batchProgress(
        controller.verifiedCount + controller.failedCount,
        controller.chargeableCount,
      );
    }
    if (controller.verifiedCount + controller.failedCount > 0) {
      return strings.batchDoneCounts(
        controller.verifiedCount,
        controller.failedCount,
      );
    }
    final parts = <String>[];
    final needingBank = _countNeedingBank(controller);
    if (needingBank > 0) {
      parts.add(strings.batchNeedsBank(needingBank));
    }
    if (controller.skippedCount > 0) {
      parts.add(strings.batchDuplicates(controller.skippedCount));
    }
    if (license.isLoaded && !license.isEntitled) {
      parts.add(strings.freeChecksLeft(license.trialsLeft));
    }
    return parts.isEmpty ? '' : parts.join(' · ');
  }
}

class _StartButton extends StatelessWidget {
  final bool enabled;
  final int count;
  final VoidCallback onTap;

  const _StartButton({
    required this.enabled,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ethiopic =
        context.watch<LocaleController>().usesEthiopicScript;

    return Pressable(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: MahtemPalette.buttonGradient)
              : null,
          color: enabled
              ? null
              : (isDark ? MahtemPalette.dCardAlt : MahtemPalette.lBorder),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: Text(
          strings.batchStart(count),
          style: TextStyle(
            color: enabled
                ? Colors.white
                : (isDark
                    ? MahtemPalette.dInkFaint
                    : MahtemPalette.lInkFaint),
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: ethiopic ? 0.2 : 0.5,
          ),
        ),
      ),
    );
  }
}
