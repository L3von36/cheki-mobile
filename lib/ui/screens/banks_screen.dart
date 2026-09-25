import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/banks_registry.dart';
import '../../core/models.dart';
import '../../state/system_status.dart';
import '../../theme/cheki_theme.dart';
import '../widgets/bank_avatar.dart';

/// Supported banks — all 10 institutions with formats, requirements and
/// live endpoint status dots (fed by the health endpoint).
class BanksScreen extends StatelessWidget {
  const BanksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dim = isDark ? ChekiPalette.dInkDim : ChekiPalette.lInkDim;

    return Scaffold(
      appBar: AppBar(title: const Text('Supported Banks')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
        itemCount: kChekiBanks.length,
        separatorBuilder: (context, index) => const SizedBox(height: 9),
        itemBuilder: (context, index) {
          final bank = kChekiBanks[index];
          return _BankRow(
            bank: bank,
            dim: dim,
            isDark: isDark,
            onTap: () => _showDetails(context, bank),
          );
        },
      ),
    );
  }

  void _showDetails(BuildContext context, ChekiBank bank) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetDim = Theme.of(sheetContext).brightness == Brightness.dark
            ? ChekiPalette.dInkDim
            : ChekiPalette.lInkDim;
        final sheetInk = Theme.of(sheetContext).brightness == Brightness.dark
            ? ChekiPalette.dInk
            : ChekiPalette.navy;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BankAvatar(bank: bank, size: 42, radius: 13),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        bank.name,
                        style: TextStyle(
                          color: sheetInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _kv('Reference format', bank.referenceFormat, sheetDim, sheetInk),
                _kv('Example', bank.referenceExample, sheetDim, sheetInk),
                if (bank.requiresAccount)
                  _kv(
                    'Account needed',
                    'Last ${bank.accountDigits} digits of the receiving account',
                    sheetDim,
                    sheetInk,
                  ),
                if (bank.requiresPhone)
                  _kv('Phone needed', 'Number tied to the wallet',
                      sheetDim, sheetInk),
                _kv('Tips', bank.notes, sheetDim, sheetInk),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String key, String value, Color dim, Color ink) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            key.toUpperCase(),
            style: monoStyle(
              size: 9,
              weight: FontWeight.w700,
              letterSpacing: 1.2,
              color: dim,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: ink,
              fontSize: 12,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  final ChekiBank bank;
  final Color dim;
  final bool isDark;
  final VoidCallback onTap;

  const _BankRow({
    required this.bank,
    required this.dim,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = context.watch<SystemStatus>().statusFor(bank.id);
    final (Color dotColor, String dotLabel) = _statusMeta(status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? ChekiPalette.dCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? ChekiPalette.dBorder : ChekiPalette.lBorder,
          ),
        ),
        child: Row(
          children: [
            BankAvatar(bank: bank, size: 42, radius: 13),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          bank.shortName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark
                                ? ChekiPalette.dInk
                                : ChekiPalette.navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    bank.referenceFormat,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(size: 9.5, color: dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              dotLabel,
              style: TextStyle(
                color: dotColor,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: dim),
          ],
        ),
      ),
    );
  }

  (Color, String) _statusMeta(String? status) => switch (status) {
        'reachable' || 'live' => (ChekiPalette.green, 'ONLINE'),
        'geo-blocked' => (ChekiPalette.amber, 'SLOW'),
        'unreachable' => (ChekiPalette.red, 'DOWN'),
        'in-development' => (
            isDark ? ChekiPalette.dInkFaint : ChekiPalette.lInkFaint,
            'SOON'
          ),
        _ => (
            isDark ? ChekiPalette.dInkFaint : ChekiPalette.lInkFaint,
            '—'
          ),
      };
}
