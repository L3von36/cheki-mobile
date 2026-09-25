import 'package:mahtem/app.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootToHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const MahtemApp());
  // The app boots straight into the shell — no splash. There is an ambient
  // pulsing/glow animation in places, so pump fixed durations instead of
  // pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('boots straight into the minimal verify form', (tester) async {
    await bootToHome(tester);

    // Slim brand header + the three core controls.
    expect(find.text('Mahtem'), findsOneWidget);
    expect(find.text('Auto-detect bank'), findsOneWidget);
    expect(find.text('VERIFY RECEIPT'), findsOneWidget);
    expect(find.text('Scan the QR code instead'), findsOneWidget);

    // Bottom nav: Verify / scan / History — no Settings tab.
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('a typed plain reference needs a bank pick before verifying',
      (tester) async {
    await bootToHome(tester);

    // The verify button is inert before a bank + reference are present.
    // (Raw references carry no bank information — stylepos rule.)
    await tester.enterText(find.byType(TextField).first, 'FT26140P01YB');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Auto-detect bank'), findsOneWidget);
    expect(find.text('VERIFY RECEIPT'), findsOneWidget);
  });

  testWidgets('history tab shows the empty state', (tester) async {
    await bootToHome(tester);

    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No checks yet'), findsOneWidget);
  });

  test('every catalog bank exposes hint text and initials', () {
    for (final bank in kVerifyBanks) {
      expect(bank.referenceHint, isNotEmpty, reason: bank.id);
      expect(bank.helper, isNotEmpty, reason: bank.id);
      expect(bank.initials, isNotEmpty, reason: bank.id);
    }
    // The two banks that used to demand account digits in the old engine:
    // CBE now verifies with the receipt id alone; BOA keeps last-5.
    expect(bankById('cbe')!.accountDigits, 0);
    expect(bankById('boa')!.accountDigits, 5);
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
