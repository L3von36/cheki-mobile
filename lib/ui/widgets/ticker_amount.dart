import 'package:flutter/material.dart';

import '../../util/format.dart';

/// Count-up animated amount text — the receipt "hero" number.
class TickerAmount extends StatelessWidget {
  final double? amount;
  final String? currency;
  final TextStyle? style;
  final Duration duration;

  const TickerAmount({
    super.key,
    required this.amount,
    this.currency,
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    if (amount == null) {
      return Text('—', style: style ?? DefaultTextStyle.of(context).style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amount),
      duration: duration,
      curve: Curves.easeOutExpo,
      builder: (context, value, _) {
        return Text(
          formatAmountPlain(value),
          style: style ?? DefaultTextStyle.of(context).style,
        );
      },
    );
  }
}
