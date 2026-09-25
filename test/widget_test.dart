import 'package:cheki_mobile/app.dart';
import 'package:cheki_mobile/core/banks_registry.dart';
import 'package:cheki_mobile/core/verify_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootToHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const ChekiApp());
  await tester.pump(); // splash first frame
  // Splash auto-advances after ~1.9s. Pump past it (fixed durations —
  // the app has ambient repeating animations, so no pumpAndSettle).
  await tester.pump(const Duration(milliseconds: 2100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('boots through splash into the home screen', (tester) async {
    await bootToHome(tester);

    // Splash is gone; home is visible.
    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(find.text('Enter Payment Details'), findsOneWidget);
    expect(find.textContaining('Verify Payments'), findsOneWidget);
    // Bottom nav tabs.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('Enter Payment Details opens the verify form', (tester) async {
    await bootToHome(tester);

    await tester.tap(find.text('Enter Payment Details'));
    await tester.pump(const Duration(milliseconds: 500));

    // Before typing, the button asks for a reference.
    expect(find.text('Enter a reference to verify'), findsOneWidget);

    // Typing a CBE reference auto-detects the bank in the selector
    // and arms the verify button.
    await tester.enterText(find.byType(TextField).first, 'FT26140P01YB');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Commercial Bank of Ethiopia'), findsOneWidget);
    expect(find.text('Verify Now'), findsOneWidget);
  });

  test('all 10 banks expose a reference example', () {
    for (final bank in kChekiBanks) {
      expect(bank.referenceExample, isNotEmpty, reason: bank.id);
      expect(bank.initials, isNotEmpty, reason: bank.id);
    }
  });

  group('VerifyHistory', () {
    test('records, reads back and clears entries', () async {
      SharedPreferences.setMockInitialValues({});
      final history = VerifyHistory();

      await history.add(
        HistoryEntry(
          id: 'v1',
          bankId: 'cbe',
          bankName: 'Commercial Bank of Ethiopia',
          reference: 'FT26140P01YB',
          senderName: 'Alice',
          amount: 250,
          currency: 'ETB',
          verifiedAt: 1730000000000,
          status: 'verified',
        ),
      );
      await history.add(
        HistoryEntry(
          id: 'v2',
          bankId: 'telebirr',
          bankName: 'Telebirr',
          reference: 'DET8FJGUJ4',
          verifiedAt: 1730000600000,
          status: 'failed',
          message: 'Receipt not found',
        ),
      );

      expect(history.length, 2);
      expect(history.entries.first.id, 'v2'); // newest first
      expect(history.entries.first.isVerified, isFalse);
      expect(history.entries.last.title, 'Alice');

      // Reload from prefs into a fresh store — persistence works.
      final reloaded = VerifyHistory();
      await reloaded.add(
        HistoryEntry(
          id: 'v3',
          bankId: 'boa',
          bankName: 'Bank of Abyssinia',
          reference: 'AB12345678',
          verifiedAt: 1730001200000,
          status: 'verified',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reloaded.length, 3);

      await reloaded.remove('v3');
      expect(reloaded.length, 2);
      await reloaded.clear();
      expect(reloaded.length, 0);
    });

    test('entry title falls back sensibly', () {
      const entry = HistoryEntry(
        id: 'v9',
        bankId: 'awash',
        bankName: 'Awash Bank',
        reference: '2KDL95Z0NR4U61O6',
        verifiedAt: 0,
        status: 'failed',
        message: 'down',
      );
      expect(entry.title, 'Awash Bank');
      expect(entry.isVerified, isFalse);
    });
  });
}
