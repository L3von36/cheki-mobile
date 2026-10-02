import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/auth/account.dart';
import '../../core/localization/app_strings.dart';
import '../../state/auth_controller.dart';
import '../../state/license_controller.dart';
import '../../state/locale_controller.dart';
import '../../state/theme_controller.dart';
import '../../theme/mahtem_theme.dart';
import 'pressable.dart';

/// Opens the settings bottom sheet from any screen.
Future<void> openSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SettingsSheet(),
  );
}

/// Settings: device account (sign out), appearance (system / light /
/// dark) and language (English / አማርኛ / Afaan Oromoo / ትግርኛ) — plus
/// version and the device code users quote when buying an activation code.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final theme = context.watch<ThemeController>();
    final locale = context.watch<LocaleController>();
    final license = context.watch<LicenseController>();
    final strings = locale.strings;
    final account = auth.currentAccount;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountHeader(account: account, strings: strings),
            const Divider(height: 28),
            _SectionLabel(strings.appearanceSection),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              // Compact segments so the three Amharic labels + icons fit
              // even on 320dp phones — the default padding overflows and
              // paints yellow/black stripes (the "ugly UI" bug).
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 9),
                ),
              ),
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_rounded, size: 17),
                  label: _SegmentLabel(strings.themeSystem),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined, size: 17),
                  label: _SegmentLabel(strings.themeLight),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined, size: 17),
                  label: _SegmentLabel(strings.themeDark),
                ),
              ],
              selected: {theme.mode},
              onSelectionChanged: (selection) =>
                  context.read<ThemeController>().setMode(selection.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 18),
            _SectionLabel(strings.languageSection),
            const SizedBox(height: 8),
            // Four language segments no longer fit a 320dp sheet at full
            // size — scale the whole switcher down only when it's tight
            // (never overflows, unchanged look on regular phones).
            FittedBox(
              fit: BoxFit.scaleDown,
              child: SegmentedButton<AppLocale>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 9),
                  ),
                ),
                segments: [
                  for (final l in AppLocale.values)
                    ButtonSegment(value: l, label: _SegmentLabel(l.label)),
                ],
                selected: {locale.locale},
                onSelectionChanged: (selection) =>
                    context.read<LocaleController>().setLocale(selection.first),
                showSelectedIcon: false,
              ),
            ),
            const SizedBox(height: 18),
            _SignOutTile(
              enabled: account != null,
              strings: strings,
              onSignOut: () => _confirmSignOut(context),
            ),
            const SizedBox(height: 14),
            _MetaRow(
              label: strings.versionLabel,
              valueFuture: PackageInfo.fromPlatform()
                  .then((info) => info.version)
                  .catchError((_) => ''),
            ),
            if (license.deviceCode.isNotEmpty)
              _MetaRow(
                label: strings.deviceCodeLabel,
                valueFuture: Future.value(license.deviceCode),
                copyable: true,
              ),
            const SizedBox(height: 8),
            _FinePrint(text: strings.crashReportsNote),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthController>();
    final strings = context.read<LocaleController>().strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.signOutConfirmTitle),
        content: Text(strings.signOutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.signOut),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      await auth.signOut();
      // The auth gate swaps to the sign-in screen on its own.
    }
  }
}

/// Single-line, never-wrapping segment label — the last-resort ellipsis
/// keeps a long localized label from painting overflow stripes inside a
/// segment; the compact segment style makes ellipsis unreachable in
/// practice on real screens.
class _SegmentLabel extends StatelessWidget {
  final String text;

  const _SegmentLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _AccountHeader extends StatelessWidget {
  final AccountRecord? account;
  final AppStrings strings;

  const _AccountHeader({required this.account, required this.strings});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.lInk;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final acct = account; // local copy — promotes to non-null below

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: MahtemPalette.buttonGradient),
            shape: BoxShape.circle,
          ),
          child: Text(
            acct?.initials ?? 'M',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                acct?.displayName ?? 'Mahtem',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (acct != null)
                Text(
                  displayIdentifierFor(acct.identifier),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 10.5, color: dim),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ethiopic = context.watch<LocaleController>().usesEthiopicScript;
    // Ethiopic script has no case and wide glyphs — heavy tracking and
    // uppercase transforms only make it look stretched and broken.
    final label = ethiopic ? text : text.toUpperCase();
    return Text(
      label,
      style: TextStyle(
        color: isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: ethiopic ? 0.3 : 1.1,
      ),
    );
  }
}

class _SignOutTile extends StatelessWidget {
  final bool enabled;
  final AppStrings strings;
  final VoidCallback onSignOut;

  const _SignOutTile({
    required this.enabled,
    required this.strings,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Pressable(
      onTap: enabled ? onSignOut : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? MahtemPalette.dCard : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: MahtemPalette.red.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.logout_rounded,
              color: MahtemPalette.red,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                strings.signOut,
                style: const TextStyle(
                  color: MahtemPalette.red,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fine-print disclosure under the meta rows: what (little) crash
/// reporting sends. Muted like the meta labels, but wraps to 2–3 lines.
class _FinePrint extends StatelessWidget {
  final String text;

  const _FinePrint({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faint = isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text,
        style: TextStyle(color: faint, fontSize: 10.5, height: 1.4),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final Future<String> valueFuture;
  final bool copyable;

  const _MetaRow({
    required this.label,
    required this.valueFuture,
    this.copyable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final faint = isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint;

    return FutureBuilder<String>(
      future: valueFuture,
      builder: (context, snapshot) {
        final value = (snapshot.data ?? '').trim();
        if (value.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: faint, fontSize: 10.5),
                ),
              ),
              GestureDetector(
                onTap: copyable
                    ? () {
                        Clipboard.setData(ClipboardData(text: value));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              context
                                  .read<LocaleController>()
                                  .strings
                                  .copiedToClipboard,
                            ),
                          ),
                        );
                      }
                    : null,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value, style: monoStyle(size: 11, color: dim)),
                    if (copyable) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.copy_rounded, size: 12, color: faint),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
