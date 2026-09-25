import 'package:cheki_mobile/app.dart';
import 'package:cheki_mobile/core/banks_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ChekiApp boots into the verify form', (tester) async {
    await tester.pumpWidget(const ChekiApp());
    await tester.pump();
    expect(find.text('cheki'), findsOneWidget);
    expect(find.text('Verify receipt'), findsOneWidget);
    // Scan now lives on the raised center button of the bottom bar.
    expect(find.text('SCAN'), findsOneWidget);
    expect(find.text('Banks'), findsOneWidget);
  });

  testWidgets('typing a CBE reference shows the auto-detect chip',
      (tester) async {
    await tester.pumpWidget(const ChekiApp());
    await tester.pump();

    await tester.enterText(
      find.byType(TextField).first,
      'FT26140P01YB',
    );
    // The app has ambient looping animations (pulse dot, stamp, ticker),
    // so pump a fixed duration instead of pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Looks like CBE'), findsOneWidget);
  });

  test('all 10 banks expose a reference example', () {
    for (final bank in kChekiBanks) {
      expect(bank.referenceExample, isNotEmpty, reason: bank.id);
      expect(bank.initials, isNotEmpty, reason: bank.id);
    }
  });
}
