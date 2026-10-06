import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/cloud/cloud_vault.dart';
import 'package:mahtem/core/licensing/license_store.dart';
import 'package:mahtem/core/receipt_verify/extra_banks.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/app_tab.dart';
import 'package:mahtem/state/cloud_controller.dart';
import 'package:mahtem/state/license_controller.dart';
import 'package:mahtem/state/locale_controller.dart';
import 'package:mahtem/state/theme_controller.dart';
import 'package:mahtem/state/verify_controller.dart';
import 'package:mahtem/ui/flow.dart';
import 'package:mahtem/ui/screens/history_screen.dart';
import 'package:mahtem/ui/screens/result_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.16.0 reason notes: after a verified check the user can record WHY
/// the receipt was checked ("rent", "order #12"). The note lives on the
/// HistoryEntry, shows on the list tile + details sheet + result screen,
/// exports with the CSV and rides the encrypted vault untouched.

HistoryEntry _entry({
  required String id,
  String? reason,
}) =>
    HistoryEntry(
      id: id,
      bankId: 'telebirr',
      bankName: 'Telebirr',
      reference: 'CHQ261Z4AB2C$id',
      senderName: 'Sender $id',
      amount: 100,
      currency: 'ETB',
      verifiedAt: DateTime.now().millisecondsSinceEpoch,
      status: 'verified',
      reason: reason,
    );

Widget _historyHarness({required Widget child, required VerifyHistory history}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VerifyController>.value(value: VerifyController()),
      ChangeNotifierProvider<VerifyHistory>.value(value: history),
      ChangeNotifierProvider<AppTab>.value(value: AppTab()),
      ChangeNotifierProvider<CloudController>.value(value: CloudController()),
      ChangeNotifierProvider<ThemeController>(
        create: (_) => ThemeController(prefs: null)..ensureLoaded(),
      ),
      ChangeNotifierProvider<LocaleController>(
        create: (_) => LocaleController(prefs: null)..ensureLoaded(),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VerifyHistory.setReason', () {
    test('sets, trims, clears and persists across reloads', () async {
      final history = VerifyHistory();
      final added = await history.add(_entry(id: 'a'));

      // Set (whitespace trimmed).
      await history.setReason(added.id, '  Rent for October  ');
      expect(history.getById(added.id)!.reason, 'Rent for October');

      // Same value twice is a no-op (no notify, no rewrite).
      await history.setReason(added.id, 'Rent for October');
      expect(history.getById(added.id)!.reason, 'Rent for October');

      // Blank input clears the note.
      await history.setReason(added.id, '   ');
      expect(history.getById(added.id)!.reason, isNull);

      // Unknown id is silently ignored.
      await history.setReason('missing', 'nope');
      expect(history.length, 1);

      // Persisted: a fresh store loads the saved reason.
      await history.setReason(added.id, 'Order #12');
      final reloaded = VerifyHistory();
      await reloaded.ensureLoaded();
      expect(reloaded.getById(added.id)!.reason, 'Order #12');
      // All other fields survived the rewrite.
      expect(reloaded.getById(added.id)!.reference, added.reference);
      expect(reloaded.getById(added.id)!.senderName, added.senderName);
      expect(reloaded.getById(added.id)!.status, 'verified');
    });

    test('rows saved by older versions decode without a reason', () {
      final legacy = HistoryEntry.fromJson({
        'id': 'old',
        'bankId': 'cbe',
        'bankName': 'CBE',
        'reference': 'FTOLD',
        'verifiedAt': 1,
        'status': 'verified',
        // no 'reason' key at all — the pre-v1.16.0 on-disk shape.
      });
      expect(legacy.reason, isNull);
      expect(legacy.toJson().containsKey('reason'), isFalse);
    });

    test('the reason rides the encrypted vault payload verbatim', () async {
      final history = VerifyHistory();
      final added =
          await history.add(_entry(id: 'v', reason: 'Market purchase'));
      final payload = encodeVaultPayload(history.entries);
      final doc = decodeVaultDocument(payload);
      expect(doc.entries.single.reason, 'Market purchase');
      expect(doc.entries.single.id, added.id);
    });

    test('toCsv exports the reason as the last column', () async {
      final history = VerifyHistory();
      await history.add(_entry(id: 'r', reason: 'Say "done", ok?'));
      final csv = history.toCsv();
      final lines = csv.trim().split('\n');
      expect(lines.first, endsWith(',Note,Reason'));
      expect(lines.last, endsWith('"Say ""done"", ok?"'));
    });
  });

  group('reason UI', () {
    testWidgets('history tile + details sheet show the reason and edit it',
        (tester) async {
      final history = VerifyHistory();
      await history.add(_entry(id: 'a'));

      await tester.pumpWidget(_historyHarness(
        child: const HistoryScreen(),
        history: history,
      ));
      await tester.pump();

      // No reason yet: tile has no note line, details offers "Add reason".
      await tester.tap(find.text('Sender a'));
      await tester.pumpAndSettle();
      expect(find.text('Add reason'), findsOneWidget);

      // Open the reason sheet and save a note.
      await tester.tap(find.text('Add reason'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Rent payment');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Toast confirms, details sheet now shows the note + "Edit reason".
      expect(find.text('Reason saved to history'), findsOneWidget);
      expect(find.text('Rent payment'), findsWidgets);
      expect(find.text('Your reason'), findsOneWidget);
      expect(find.text('Edit reason'), findsOneWidget);

      // Close the sheet: the list tile now carries the note line too.
      await tester.tapAt(const Offset(20, 20)); // dismiss the details sheet
      await tester.pumpAndSettle();
      expect(find.text('Rent payment'), findsOneWidget);
      expect(history.getById(history.entries.first.id)!.reason,
          'Rent payment');

      // Search finds the note.
      await tester.tap(find.byTooltip('Search history'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'rent');
      await tester.pumpAndSettle();
      expect(find.text('Sender a'), findsOneWidget);
    });

    testWidgets(
        'result screen offers Add reason right after a verified check '
        'and the note lands on the fresh history row', (tester) async {
      final history = VerifyHistory();
      final controller = VerifyController(
        verifyFn: (input) async => VerifyResult.receipt(
          const ReceiptData(
            verified: true,
            bankCode: 'telebirr',
            bankName: 'Telebirr',
            reference: 'CHQ261Z4AB2C',
            amount: 150,
          ),
          5,
        ),
      );
      controller.selectBank(bankByIdAll('telebirr'));
      controller.setReference('CHQ261Z4AB2C');

      late final BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VerifyController>.value(value: controller),
            ChangeNotifierProvider<VerifyHistory>.value(value: history),
            ChangeNotifierProvider<LicenseController>(
              create: (_) => LicenseController(
                store: MemoryLicenseStore(),
                deviceKeySource: () async => 'device-1',
              ),
            ),
            ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController(prefs: null)..ensureLoaded(),
            ),
            ChangeNotifierProvider<LocaleController>(
              create: (_) => LocaleController(prefs: null)..ensureLoaded(),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      final flow = runVerificationFlow(context);
      await tester.pumpAndSettle();
      expect(find.byType(ResultScreen), findsOneWidget);

      // Verified → the history row exists and the result screen offers
      // the reason note for exactly that row.
      expect(history.entries, hasLength(1));
      final entryId = history.entries.first.id;
      expect(find.text('Add reason'), findsOneWidget);

      await tester.tap(find.text('Add reason'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Order #12 payment');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(history.getById(entryId)!.reason, 'Order #12 payment');
      // The button became the note card with an edit affordance.
      expect(find.text('Order #12 payment'), findsOneWidget);
      expect(find.text('Your reason'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await flow;
    });

    testWidgets('a failed check records history but offers no reason button',
        (tester) async {
      final history = VerifyHistory();
      final controller = VerifyController(
        verifyFn: (input) async => VerifyResult.failed(
          const VerifyFailure(VerifyErrorKind.notFound, 'nope'),
          5,
        ),
      );
      controller.selectBank(bankByIdAll('telebirr'));
      controller.setReference('CHQ261Z4AB2C');

      late final BuildContext context;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VerifyController>.value(value: controller),
            ChangeNotifierProvider<VerifyHistory>.value(value: history),
            ChangeNotifierProvider<LicenseController>(
              create: (_) => LicenseController(
                store: MemoryLicenseStore(),
                deviceKeySource: () async => 'device-1',
              ),
            ),
            ChangeNotifierProvider<ThemeController>(
              create: (_) => ThemeController(prefs: null)..ensureLoaded(),
            ),
            ChangeNotifierProvider<LocaleController>(
              create: (_) => LocaleController(prefs: null)..ensureLoaded(),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                context = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      final flow = runVerificationFlow(context);
      await tester.pumpAndSettle();
      expect(find.byType(ResultScreen), findsOneWidget);
      expect(history.entries, hasLength(1));
      expect(history.entries.first.isVerified, isFalse);
      expect(find.text('Add reason'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await flow;
    });
  });
}
