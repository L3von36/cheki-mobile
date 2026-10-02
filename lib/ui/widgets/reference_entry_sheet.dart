import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/verify_history.dart';
import '../../state/locale_controller.dart';
import '../../theme/mahtem_theme.dart';
import 'pressable.dart';

/// Opens the manual reference-entry sheet; pops with the typed (or
/// pasted) value, or null when dismissed. The value flows back into the
/// caller's pipeline exactly like a scanned QR payload — receipt links
/// auto-detect their bank, bare references pair with a bank pick.
Future<String?> showReferenceEntrySheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ReferenceEntrySheet(),
  );
}

/// "Type the transaction or reference number" — the no-QR path.
///
/// One text field, a paste shortcut and the most recent distinct
/// references from history as one-tap chips. VERIFY pops with the value;
/// the caller owns everything after that (detection, bank pick,
/// licensing, verification).
class ReferenceEntrySheet extends StatefulWidget {
  const ReferenceEntrySheet({super.key});

  @override
  State<ReferenceEntrySheet> createState() => _ReferenceEntrySheetState();
}

class _ReferenceEntrySheetState extends State<ReferenceEntrySheet> {
  final _ctrl = TextEditingController();

  /// Most recent distinct, non-empty references from history — newest
  /// first, capped so the sheet never turns into a list. Receivers often
  /// re-check the same receipt, so one tap beats retyping.
  List<String> _recentReferences() {
    final seen = <String>{};
    final recent = <String>[];
    for (final entry in context.read<VerifyHistory>().entries) {
      final reference = entry.reference.trim();
      if (reference.isEmpty || reference.length < 6) continue;
      if (!seen.add(reference)) continue;
      recent.add(reference);
      if (recent.length >= 4) break;
    }
    return recent;
  }

  void _submit() {
    final value = _ctrl.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(context.read<LocaleController>().strings.clipboardEmpty),
        ),
      );
      return;
    }
    _ctrl.text = text;
    _ctrl.selection = TextSelection.collapsed(offset: text.length);
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? MahtemPalette.dCard : Colors.white;
    final border = isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.navy;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;
    final faint = isDark ? MahtemPalette.dInkFaint : MahtemPalette.lInkFaint;
    final canVerify = _ctrl.text.trim().isNotEmpty;
    final recent = _recentReferences();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.typeSheetTitle,
                style: TextStyle(
                  color: ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                inputFormatters: [
                  // References and receipt links never carry line breaks —
                  // a pasted multi-line blob would silently break detection.
                  FilteringTextInputFormatter.singleLineFormatter,
                ],
                style: TextStyle(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: strings.typeSheetHint,
                  hintMaxLines: 2,
                  prefixIcon: Icon(
                    Icons.tag_rounded,
                    size: 18,
                    color: dim,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  suffixIcon: IconButton(
                    tooltip: strings.pasteTooltip,
                    onPressed: _paste,
                    icon: const Icon(
                      Icons.content_paste_rounded,
                      size: 17,
                      color: MahtemPalette.green,
                    ),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: fill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: MahtemPalette.green,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  strings.typeSheetRecent,
                  style: TextStyle(
                    color: faint,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final reference in recent)
                      Pressable(
                        onTap: () {
                          _ctrl.text = reference;
                          _ctrl.selection = TextSelection.collapsed(
                            offset: reference.length,
                          );
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: (isDark
                                    ? MahtemPalette.dCardAlt
                                    : MahtemPalette.blueSoft)
                                .withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            reference,
                            style: TextStyle(
                              color: ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Pressable(
                onTap: canVerify ? _submit : null,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: canVerify
                        ? const LinearGradient(
                            colors: MahtemPalette.buttonGradient)
                        : null,
                    color: canVerify
                        ? null
                        : (isDark
                            ? MahtemPalette.dCardAlt
                            : MahtemPalette.lBorder),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    strings.verifyReceiptButton,
                    style: TextStyle(
                      color: canVerify
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
