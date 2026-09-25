import 'package:flutter/material.dart';

import '../../core/receipt_verify/models.dart';
import '../../theme/mahtem_theme.dart';
import 'bank_avatar.dart';

/// Bottom-sheet bank picker with an "Auto-detect" option first.
class BankPickerSheet extends StatelessWidget {
  final String? selectedId;

  const BankPickerSheet({super.key, this.selectedId});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.navy;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Text(
                'Which bank issued the receipt?',
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Text(
                'Receipt links and QR scans pick the bank automatically — '
                'pick manually when typing a reference number.',
                style: TextStyle(color: dim, fontSize: 11.5, height: 1.45),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: kVerifyBanks.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _Tile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: MahtemPalette.greenSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: MahtemPalette.green,
                          size: 17,
                        ),
                      ),
                      title: 'Auto-detect from link or scan',
                      subtitle: 'Recommended',
                      selected: selectedId == null,
                      onTap: () => Navigator.of(context).pop(null),
                    );
                  }
                  final bank = kVerifyBanks[index - 1];
                  return _Tile(
                    leading: BankAvatar(bank: bank, size: 36, radius: 18),
                    title: bank.name,
                    subtitle: bank.referenceHint,
                    selected: selectedId == bank.id,
                    onTap: () => Navigator.of(context).pop(bank),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _Tile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MahtemPalette.dInk : MahtemPalette.navy;
    final dim = isDark ? MahtemPalette.dInkDim : MahtemPalette.lInkDim;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 1),
      leading: leading,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? MahtemPalette.greenDeep : ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: monoStyle(size: 10, color: selected ? MahtemPalette.green : dim),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded,
              color: MahtemPalette.green, size: 18)
          : null,
      onTap: onTap,
    );
  }
}
