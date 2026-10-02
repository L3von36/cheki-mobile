/// Cloud Backup sheet (v1.13.0) — opt-in, zero-knowledge backup of the
/// verification history to the user's own Cloudflare-hosted Mahtem API.
///
/// OFF state: privacy explainer + password field (the SAME password as
/// the device account — verified locally first, never sent anywhere).
/// ON state: last-sync status, Back up now / Restore / Turn off.
library;


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/localization/app_strings.dart';
import '../../core/verify_history.dart';
import '../../state/auth_controller.dart';
import '../../state/cloud_controller.dart';
import '../../theme/mahtem_theme.dart';
import 'pressable.dart';

Future<void> openCloudBackupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const CloudBackupSheet(),
  );
}

class CloudBackupSheet extends StatefulWidget {
  const CloudBackupSheet({super.key});

  @override
  State<CloudBackupSheet> createState() => _CloudBackupSheetState();
}

class _CloudBackupSheetState extends State<CloudBackupSheet> {
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudController>();
    final history = context.watch<VerifyHistory>();
    final strings = context.read<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 18 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.cloudBackupSection,
              style: TextStyle(
                color: isDark ? MahtemPalette.dInk : MahtemPalette.lInk,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              strings.cloudBackupBetaNote,
              style: TextStyle(
                color: isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            if (cloud.enabled) ...[
              _buildEnabled(cloud, history, strings, isDark),
            ] else ...[
              _buildEnable(cloud, strings, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEnable(
      CloudController cloud, AppStrings strings, bool isDark) {
    final failureText = _failureText(cloud.failure, strings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _password,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: strings.cloudBackupPasswordFieldHint,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (failureText != null) ...[
          const SizedBox(height: 8),
          Text(
            failureText,
            style: const TextStyle(
                color: MahtemPalette.red, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: cloud.isWorking ? null : () => _enable(context, cloud),
          style: FilledButton.styleFrom(
            backgroundColor: MahtemPalette.blue,
          ),
          child: cloud.isWorking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(strings.cloudBackupEnable),
        ),
      ],
    );
  }

  Widget _buildEnabled(CloudController cloud, VerifyHistory history,
      AppStrings strings, bool isDark) {
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final lastSync = cloud.lastSyncAt == null
        ? strings.cloudBackupLastNever
        : '${strings.cloudBackupLastAt} ${_formatTime(cloud.lastSyncAt!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? MahtemPalette.dCard : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: MahtemPalette.green.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_done_rounded,
                  color: MahtemPalette.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.cloudBackupEntryCount(history.length),
                      style: TextStyle(
                        color: isDark ? MahtemPalette.dInk : MahtemPalette.lInk,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastSync,
                      style: TextStyle(color: dim, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (cloud.failure != CloudFailure.none) ...[
          const SizedBox(height: 8),
          Text(
            _failureText(cloud.failure, strings) ?? '',
            style: const TextStyle(
                color: MahtemPalette.red, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: cloud.isWorking ? null : () => _backupNow(context, cloud),
          style: FilledButton.styleFrom(backgroundColor: MahtemPalette.blue),
          child: cloud.isWorking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(strings.cloudBackupNow),
        ),
        const SizedBox(height: 8),
        Pressable(
          onTap: cloud.isWorking ? null : () => _restore(context, cloud),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? MahtemPalette.dCard : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: (isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim)
                    .withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.restore_rounded, size: 18, color: dim),
                const SizedBox(width: 10),
                Text(
                  strings.cloudBackupRestore,
                  style: TextStyle(
                    color: isDark ? MahtemPalette.dInk : MahtemPalette.lInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Pressable(
          onTap: cloud.isWorking ? null : () => _disable(context, cloud),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? MahtemPalette.dCard : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border:
                  Border.all(color: MahtemPalette.red.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: MahtemPalette.red, size: 18),
                const SizedBox(width: 10),
                Text(
                  strings.cloudBackupTurnOff,
                  style: const TextStyle(
                    color: MahtemPalette.red,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── actions ─────────────────────────────────────────────────────────
  Future<void> _enable(BuildContext sheetContext, CloudController cloud) async {
    final auth = sheetContext.read<AuthController>();
    final history = sheetContext.read<VerifyHistory>();
    final account = auth.currentAccount;
    if (account == null) return;
    final ok = await cloud.enable(
      password: _password.text,
      account: account,
      history: history,
    );
    if (ok && sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }
  }

  Future<void> _backupNow(
      BuildContext sheetContext, CloudController cloud) async {
    final history = sheetContext.read<VerifyHistory>();
    final strings = sheetContext.read<LocaleController>().strings;
    final ok = await cloud.backupNow(history);
    if (!sheetContext.mounted) return;
    ScaffoldMessenger.of(sheetContext).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
            ok ? strings.cloudBackupDone : strings.cloudBackupNetworkError),
      ),
    );
  }

  Future<void> _restore(
      BuildContext sheetContext, CloudController cloud) async {
    final history = sheetContext.read<VerifyHistory>();
    final strings = sheetContext.read<LocaleController>().strings;
    final added = await cloud.restore(history);
    if (!sheetContext.mounted) return;
    String message;
    if (added < 0) {
      message = strings.cloudBackupNetworkError;
    } else if (added == 0) {
      message = strings.cloudBackupNothingToRestore;
    } else {
      message = strings.cloudBackupRestored(added);
    }
    ScaffoldMessenger.of(sheetContext).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  Future<void> _disable(
      BuildContext sheetContext, CloudController cloud) async {
    final strings = sheetContext.read<LocaleController>().strings;
    await cloud.disable();
    if (!sheetContext.mounted) return;
    ScaffoldMessenger.of(sheetContext).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(strings.cloudBackupTurnedOff),
      ),
    );
  }

  String? _failureText(CloudFailure failure, AppStrings strings) {
    switch (failure) {
      case CloudFailure.none:
        return null;
      case CloudFailure.wrongPassword:
        return strings.cloudBackupWrongPassword;
      case CloudFailure.network:
        return strings.cloudBackupNetworkError;
      case CloudFailure.server:
        return strings.cloudBackupServerError;
      case CloudFailure.sessionExpired:
        return strings.cloudBackupSessionExpired;
      case CloudFailure.decrypt:
        return strings.cloudBackupDecryptError;
    }
  }

  String _formatTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year} ${two(t.hour)}:${two(t.minute)}';
  }
}
