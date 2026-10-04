import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/app_tab.dart';
import 'package:mahtem/state/cloud_controller.dart';
import 'package:mahtem/state/locale_controller.dart';
import 'package:mahtem/state/theme_controller.dart';
import 'package:mahtem/state/verify_controller.dart';
import 'package:mahtem/ui/screens/history_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.9.0 history upgrade: summary strip, date groups, swipe-to-delete
/// with undo, and the empty-state call to action. All widget tests run in
/// English (default locale) with in-memory history — no platform channels.

HistoryEntry _entry({
  required String id,
  required String bankId,
  required String bankName,
  required String reference,
  String? sender,
  double? amount,
  int? verifiedAt,
  required bool verified,
  String? message,
}) =>
    HistoryEntry(
      id: id,
      bankId: bankId,
      bankName: bankName,
      reference: reference,
      senderName: sender,
      amount: amount ?? 250,
      currency: 'ETB',
      verifiedAt: verifiedAt ?? DateTime.now().millisecondsSinceEpoch,
      status: verified ? 'verified' : 'failed',
      message: message ?? (verified ? null : 'Receipt not found'),
    );

Widget _harness({
  required Widget child,
  VerifyHistory? history,
  AppTab? tab,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VerifyController>.value(value: VerifyController()),
      ChangeNotifierProvider<VerifyHistory>.value(value: history ?? VerifyHistory()),
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

void main() {
  testWidgets('history shows the summary strip: checks, verified, total',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final history = VerifyHistory();
    await history.add(_entry(
      id: 'a',
      bankId: 'cbe',
      bankName: 'Commercial Bank of Ethiopia',
      reference: 'FT26140P01YB',
      sender: 'Alice',
      verified: true,
    ));
    await history.add(_entry(
      id: 'b',
      bankId: 'telebirr',
      bankName: 'Telebirr',
      reference: 'DET8FJGUJ4',
      verified: false,
    ));
    await history.add(_entry(
      id: 'c',
      bankId: 'cbe',
      bankName: 'Commercial Bank of Ethiopia',
      reference: 'FT26140P01Z9',
      sender: 'Bob',
      verified: true,
    ));
    await tester.pumpWidget(
        _harness(child: const HistoryScreen(), history: history));
    await tester.pump();

    // 3 checks, 2 verified, ETB 500.00 total (verified amounts only).
    expect(find.text('Checks'), findsOneWidget);
    expect(find.text('Verified'), findsWidgets); // stat cell + filter chip
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('ETB 500.00'), findsOneWidget);
  });

  testWidgets('history groups entries under date headers', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final history = VerifyHistory();
    final now = DateTime.now();
    await history.add(_entry(
      id: 'old',
      bankId: 'cbe',
      bankName: 'Commercial Bank of Ethiopia',
      reference: 'FTOLD1',
      sender: 'Old Check',
      verified: true,
      verifiedAt: now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
    ));
    await history.add(_entry(
      id: 'fresh',
      bankId: 'telebirr',
      bankName: 'Telebirr',
      reference: 'DETFRESH1',
      sender: 'Fresh Check',
      verified: true,
      verifiedAt: now.millisecondsSinceEpoch,
    ));
    await tester.pumpWidget(
        _harness(child: const HistoryScreen(), history: history));
    await tester.pump();

    // Newest entry lands under Today, the 30-day-old one under Earlier.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('Fresh Check'), findsOneWidget);
    expect(find.text('Old Check'), findsOneWidget);
  });

  testWidgets('swipe to delete offers undo that restores the entry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final history = VerifyHistory();
    await history.add(_entry(
      id: 'a',
      bankId: 'cbe',
      bankName: 'Commercial Bank of Ethiopia',
      reference: 'FT26140P01YB',
      sender: 'Alice',
      verified: true,
    ));
    await history.add(_entry(
      id: 'b',
      bankId: 'telebirr',
      bankName: 'Telebirr',
      reference: 'DET8FJGUJ4',
      verified: false,
    ));
    await tester.pumpWidget(
        _harness(child: const HistoryScreen(), history: history));
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);

    // Swipe Alice's card end-to-start.
    await tester.drag(find.text('Alice'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsNothing);
    expect(history.entries.length, 1);
    expect(find.text('Removed from history'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(history.entries.length, 2);
  });

  testWidgets('long-press delete also offers undo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final history = VerifyHistory();
    await history.add(_entry(
      id: 'a',
      bankId: 'cbe',
      bankName: 'Commercial Bank of Ethiopia',
      reference: 'FT26140P01YB',
      sender: 'Alice',
      verified: true,
    ));
    await tester.pumpWidget(
        _harness(child: const HistoryScreen(), history: history));
    await tester.pump();

    await tester.longPress(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsNothing);
    expect(find.text('Removed from history'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('empty history CTA jumps to the Verify tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tab = AppTab()..switchTo(1); // start somewhere else than Verify
    await tester.pumpWidget(_harness(
      child: const HistoryScreen(),
      history: VerifyHistory(),
      tab: tab,
    ));
    await tester.pump();

    expect(find.text('No checks yet'), findsOneWidget);
    expect(find.text('Verify your first receipt'), findsOneWidget);

    await tester.tap(find.text('Verify your first receipt'));
    await tester.pump();

    expect(tab.index, 0);
  });

  test('VerifyHistory.insert restores an entry at its original position',
      () async {
    SharedPreferences.setMockInitialValues({});
    final history = VerifyHistory();
    final a = _entry(id: 'a', bankId: 'cbe', bankName: 'CBE',
        reference: 'A1', verified: true);
    final b = _entry(id: 'b', bankId: 'cbe', bankName: 'CBE',
        reference: 'B1', verified: true);
    final c = _entry(id: 'c', bankId: 'cbe', bankName: 'CBE',
        reference: 'C1', verified: true);
    await history.add(a);
    await history.add(b);
    await history.add(c); // list is now [c, b, a]
    expect(history.entries.map((e) => e.id).toList(), ['c', 'b', 'a']);

    final index = history.entries.indexOf(b);
    await history.remove('b');
    expect(history.entries.map((e) => e.id).toList(), ['c', 'a']);

    await history.insert(index, b);
    expect(history.entries.map((e) => e.id).toList(), ['c', 'b', 'a']);
  });

  test('VerifyHistory.toCsv escapes RFC 4180 cells and orders oldest first',
      () async {
    SharedPreferences.setMockInitialValues({});
    final history = VerifyHistory();
    final now = DateTime.now();
    // Real usage: add() prepends, so checks are seeded oldest-first —
    // the newest check ends up at the front of the list.
    await history.add(_entry(
      id: 'old',
      bankId: 'cbe',
      bankName: 'CBE',
      reference: 'FTOLD1',
      sender: 'Old Check',
      verified: true,
      verifiedAt: now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
    ));
    await history.add(_entry(
      id: 'old2',
      bankId: 'telebirr',
      bankName: 'Telebirr',
      reference: 'PLAIN1',
      verified: false,
      verifiedAt: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
    ));
    await history.add(_entry(
      id: 'new',
      bankId: 'cbe',
      bankName: 'CBE',
      reference: 'FT,2614',
      sender: 'Say "hi"',
      verified: true,
      verifiedAt: now.millisecondsSinceEpoch,
      message: 'line1\nline2',
    ));

    final csv = history.toCsv();
    final lines = csv.trim().split('\n');

    expect(lines.first,
        'Checked at,Status,Bank,Reference,Amount,Currency,Sender,Receiver,Receipt date,Note');
    // Chronological export: the 30-day-old CBE row leads, the newest is last.
    expect(lines[1], contains('CBE'));
    expect(lines[2], contains('Telebirr'));
    expect(lines[2], contains('not verified'));
    // RFC 4180 quoting — asserted on the whole CSV because the last cell
    // contains a newline, so the newest row legitimately spans two
    // physical lines.
    expect(csv, contains('"FT,2614"'));
    expect(csv, contains('"Say ""hi"""'));
    expect(csv, contains('"line1\nline2"'));
    expect(lines, hasLength(5)); // header + old + old2 + new row + newline tail
  });
}
