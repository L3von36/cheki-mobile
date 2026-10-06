import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/verify_history.dart';
import '../../state/locale_controller.dart';
import '../../theme/mahtem_theme.dart';

/// Opens the "why was this receipt checked?" sheet for a history entry:
/// one text field prefilled with any existing reason, SAVE (or an empty
/// save to clear) writes through [VerifyHistory.setReason] — the note
/// then shows on the entry card, in the details sheet and in the CSV
/// export, and rides the encrypted vault on the next auto-sync.
Future<void> showReasonSheet(BuildContext context, String entryId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReasonSheet(entryId: entryId),
  );
}

class ReasonSheet extends StatefulWidget {
  final String entryId;

  const ReasonSheet({super.key, required this.entryId});

  @override
  State<ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<ReasonSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final entry = context.read<VerifyHistory>().getById(widget.entryId);
    _ctrl = TextEditingController(text: entry?.reason ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final history = context.read<VerifyHistory>();
    await history.setReason(widget.entryId, _ctrl.text);
    if (!mounted) return;
    final s = context.read<LocaleController>().strings;
    unawaited(HapticFeedback.selectionClick());
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(s.reasonSavedToast),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleController>().strings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.reasonSheetTitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            onSubmitted: (_) => _save(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? MahtemPalette.dInk : MahtemPalette.navy,
            ),
            decoration: InputDecoration(
              hintText: s.reasonSheetHint,
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: isDark ? MahtemPalette.dCard : Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? MahtemPalette.dBorder : MahtemPalette.lBorder,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: MahtemPalette.green, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: MahtemPalette.buttonGradient,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _save,
                child: Text(
                  s.reasonSaveButton,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
