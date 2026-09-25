import 'package:flutter/material.dart';

import '../../core/banks_registry.dart';
import '../../core/models.dart';
import '../../theme/cheki_theme.dart';
import '../widgets/bank_avatar.dart';

/// Banks — all 10 supported institutions with their requirements.
class BanksScreen extends StatelessWidget {
  const BanksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Scaffold(
      appBar: AppBar(title: const Text('Supported banks')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: kChekiBanks.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final bank = kChekiBanks[index];
          return _BankRow(
            bank: bank,
            dim: dim,
            onTap: () => _showDetails(context, bank),
          );
        },
      ),
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
                    BankAvatar(bank: bank, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        bank.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 18),
                Text(
                  'REFERENCE FORMAT',
                  style: monoStyle(
                    size: 10,
                    weight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: dim,
                  ),
                ),
                const SizedBox(height: 6),
                Text(bank.referenceFormat,
                    style: TextStyle(color: ink, fontSize: 13.5, height: 1.5)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Example: ',
                        style: TextStyle(color: dim, fontSize: 13)),
                    Text(
                      bank.referenceExample,
                      style: monoStyle(
                        size: 13,
                        weight: FontWeight.w700,
                        color: ChekiPalette.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'GOOD TO KNOW',
                  style: monoStyle(
                    size: 10,
                    weight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: dim,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  bank.notes,
                  style: TextStyle(color: dim, fontSize: 13, height: 1.5),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              BankAvatar(bank: bank, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bank.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bank.badges.isEmpty
                          ? 'Reference only — no extra info needed'
                          : bank.badges.join('  ·  '),
                      style: TextStyle(color: dim, fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: dim),
            ],
          ),
        ),
      ),
    );
  }
}
