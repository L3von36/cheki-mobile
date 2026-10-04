import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/app_tab.dart';
import 'package:mahtem/state/cloud_controller.dart';
import 'package:mahtem/state/locale_controller.dart';
import 'package:mahtem/state/theme_controller.dart';
import 'package:mahtem/state/verify_controller.dart';
import 'package:mahtem/ui/screens/history_screen.dart';
import 'package:mahtem/ui/widgets/reference_entry_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.7.0 features: manual reference entry (the no-QR path), history
/// search/filter and the "Verify again" prefill. All widget tests run in
/// English (default locale) and with in-memory history — no platform
/// channels touched.

HistoryEntry _entry({
  required String id,
  required String bankId,
  required String bankName,
  required String reference,
  String? sender,
  required bool verified,
}) =>
    HistoryEntry(
      id: id,
      bankId: bankId,
      bankName: bankName,
      reference: reference,
      senderName: sender,
      amount: 250,
      currency: 'ETB',
      verifiedAt: id.hashCode,
      status: verified ? 'verified' : 'failed',
      message: verified ? null : 'Receipt not found',
    );

Future<VerifyHistory> seededHistory() async {
  SharedPreferences.setMockInitialValues({});
  final history = VerifyHistory();
  // Newest last (add() prepends) — DET8FJGUJ4 should lead the recent chips.
  await history.add(_entry(
    id: 'v1',
    bankId: 'cbe',
    bankName: 'Commercial Bank of Ethiopia',
    reference: 'FT26140P01YB',
    sender: 'Alice',
    verified: true,
  ));
  await history.add(_entry(
    id: 'v2',
    bankId: 'telebirr',
    bankName: 'Telebirr',
    reference: 'DET8FJGUJ4',
    verified: false,
  ));
  // A duplicate reference must NOT repeat in the recent chips.
  await history.add(_entry(
    id: 'v3',
    bankId: 'cbe',
    bankName: 'Commercial Bank of Ethiopia',
    reference: 'FT26140P01YB',
    sender: 'Bob',
    verified: true,
  ));
  return history;
}

Widget _harness({
  required Widget child,
  VerifyHistory? history,
  VerifyController? controller,
  AppTab? tab,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VerifyController>.value(
        value: controller ?? VerifyController(),
      ),
      ChangeNotifierProvider<VerifyHistory>.value(
        value: history ?? VerifyHistory(),
      ),
      ChangeNotifierProvider<AppTab>.value(value: tab ?? AppTab()),
      // HistoryScreen reads the cloud controller for the backup row — a
      // prefs-less instance is the neutral (disabled) state in tests.
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

/// Opens the reference sheet and renders whatever value it pops with.
class _SheetOpener extends StatefulWidget {
  const _SheetOpener();

  @override
  State<_SheetOpener> createState() => _SheetOpenerState();
}

class _SheetOpenerState extends State<_SheetOpener> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () async {
              final value = await showReferenceEntrySheet(context);
              if (value != null) setState(() => _result = value);
            },
            child: const Text('OPEN'),
          ),
          if (_result != null) Text('RESULT:$_result'),
        ],
      ),
    );
  }
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reference entry: empty input keeps VERIFY inert', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_harness(child: const _SheetOpener()));
    await _openSheet(tester);

    expect(find.text('Type the transaction or reference number'),
        findsOneWidget);
    expect(find.text('VERIFY RECEIPT'), findsOneWidget);

    // Disabled button: tapping keeps the sheet open.
    await tester.tap(find.text('VERIFY RECEIPT'));
    await tester.pump();
    expect(find.text('Type the transaction or reference number'),
        findsOneWidget);
    expect(find.textContaining('RESULT:'), findsNothing);
  });

  testWidgets('reference entry: typing and verifying pops the value',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_harness(child: const _SheetOpener()));
    await _openSheet(tester);

    // Pasted blobs can carry trailing whitespace/newlines — trimmed out.
    await tester.enterText(find.byType(TextField), ' FT2614G2P01YB\n');
    await tester.pump();
    await tester.tap(find.text('VERIFY RECEIPT'));
    await tester.pumpAndSettle();

    expect(find.text('RESULT:FT2614G2P01YB'), findsOneWidget);
  });

  testWidgets('reference entry: recent checks fill the field in one tap',
      (tester) async {
    final history = await seededHistory();
    await tester.pumpWidget(
        _harness(child: const _SheetOpener(), history: history));
    await _openSheet(tester);

    expect(find.text('Recent checks'), findsOneWidget);
    // Both distinct references appear (newest = the duplicated FT… entry);
    // the duplicate itself must not repeat as a second chip.
    expect(find.text('DET8FJGUJ4'), findsOneWidget);
    expect(find.text('FT26140P01YB'), findsOneWidget);

    await tester.tap(find.text('FT26140P01YB'));
    await tester.pump();
    await tester.tap(find.text('VERIFY RECEIPT'));
    await tester.pumpAndSettle();

    expect(find.text('RESULT:FT26140P01YB'), findsOneWidget);
  });

  testWidgets('history: search narrows by reference and shows no-matches',
      (tester) async {
    final history = await seededHistory();
    await tester.pumpWidget(_harness(child: const HistoryScreen(), history: history));
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Telebirr · DET8FJGUJ4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'FT26');
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Telebirr · DET8FJGUJ4'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    // Close search — the full list returns.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Telebirr · DET8FJGUJ4'), findsOneWidget);
  });

  testWidgets('history: status filter chips include/exclude checks',
      (tester) async {
    final history = await seededHistory();
    await tester.pumpWidget(_harness(child: const HistoryScreen(), history: history));
    await tester.pump();

    // v1.9.0: the summary strip also has a 'Verified' label — the filter
    // chip is the later one in tree order.
    await tester.tap(find.text('Verified').last);
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Telebirr · DET8FJGUJ4'), findsNothing);

    await tester.tap(find.text('Not verified'));
    await tester.pump();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Telebirr · DET8FJGUJ4'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Telebirr · DET8FJGUJ4'), findsOneWidget);
  });

  testWidgets('history: Verify again prefills the form and switches tab',
      (tester) async {
    final history = await seededHistory();
    final controller = VerifyController();
    final tab = AppTab();
    await tester.pumpWidget(_harness(
      child: const HistoryScreen(),
      history: history,
      controller: controller,
      tab: tab,
    ));
    await tester.pump();

    // Open the details sheet of Alice's verified CBE check.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Verify again'), findsOneWidget);

    await tester.tap(find.text('Verify again'));
    await tester.pumpAndSettle();

    expect(controller.reference, 'FT26140P01YB');
    expect(controller.manualBank?.id, 'cbe');
    expect(tab.index, 0); // back on the Verify tab
    expect(find.text('Details filled in — review and verify.'),
        findsOneWidget);
  });
}
