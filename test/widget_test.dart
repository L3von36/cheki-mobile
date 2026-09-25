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
    expect(find.text('Scan receipt QR code'), findsOneWidget);
  });

  testWidgets('typing a CBE reference shows the auto-detect chip',
      (tester) async {
    await tester.pumpWidget(const ChekiApp());
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextField, 'FT26140P01YB').first,
      'FT26140P01YB',
    );
    await tester.pumpAndSettle();

    expect(find.text('Looks like CBE'), findsOneWidget);
  });

  test('all 10 banks expose a reference example', () {
    for (final bank in kChekiBanks) {
      expect(bank.referenceExample, isNotEmpty, reason: bank.id);
      expect(bank.initials, isNotEmpty, reason: bank.id);
    }
  });
}
