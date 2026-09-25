import 'package:flutter/material.dart';

import '../../core/banks_registry.dart';
import '../../core/models.dart';
import '../../theme/cheki_theme.dart';
import '../widgets/bank_avatar.dart';

/// Banks — all 10 supported institutions with their requirements.
///
/// Lives as the second tab of the shell, but can also be pushed as its
/// own route (then [embedded] is false and a back button appears).
class BanksScreen extends StatelessWidget {
  final bool embedded;

  const BanksScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    final list = ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      itemCount: kChekiBanks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final bank = kChekiBanks[index];
        return _BankRow(
          bank: bank,
          dim: dim,
          onTap: () => _showDetails(context, bank),
        );
      },
    );

    // Embedded in the shell tab: the shell owns the app bar.
    if (embedded) return list;

    return Scaffold(
      appBar: AppBar(title: const Text('Supported banks')),
      body: list,
    );
  }

  void _showDetails(BuildContext context, ChekiBank bank) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;
    final ink = isDark ? ChekiPalette.dInk : ChekiPalette.lInk;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BankAvatar(bank: bank, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        bank.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final badge in bank.badges)
                      MetaChip(label: badge),
                    MetaChip(
                      label: bank.type.name.toUpperCase(),
                      color: ChekiPalette.green,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'REFERENCE FORMAT',
                  style: monoStyle(
                    size: 9,
                    weight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: dim,
                  ),
                ),
                const SizedBox(height: 5),
                Text(bank.referenceFormat,
                    style: TextStyle(color: ink, fontSize: 12.5, height: 1.5)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Example: ',
                        style: TextStyle(color: dim, fontSize: 12)),
                    Text(
                      bank.referenceExample,
                      style: monoStyle(
                        size: 12,
                        weight: FontWeight.w700,
                        color: ChekiPalette.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'GOOD TO KNOW',
                  style: monoStyle(
                    size: 9,
                    weight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: dim,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  bank.notes,
                  style: TextStyle(color: dim, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BankRow extends StatelessWidget {
  final ChekiBank bank;
  final Color dim;
  final VoidCallback onTap;

  const _BankRow({
    required this.bank,
    required this.dim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder;
    final color = Color(bank.colorValue);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(14),
            color: isDark ? ChekiPalette.dSurface : ChekiPalette.lSurface,
          ),
          child: Row(
            children: [
              // Brand accent stripe — tiny flourish, big orientation win.
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              BankAvatar(bank: bank, size: 36, radius: 10),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      bank.badges.isEmpty
                          ? 'Reference only — no extra info needed'
                          : bank.badges.join('  ·  '),
                      style: TextStyle(color: dim, fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: dim, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
