import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/app.dart';
import 'package:mahtem/ui/widgets/settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart';

/// Regression suite for the two v1.6.0 bugs:
///
///  1. "UI looks bad after switching language" — RenderFlex overflows
///     (striped paint) and font fallbacks once the Ethiopic labels land.
///     The walk below boots every reachable screen in Amharic on a
///     common 360dp phone and a small 320dp phone. Any layout exception
///     the framework throws fails the test — no interception, so the
///     failure output contains the full overflow details.
///
///  2. "Create-account button not clickable" — TextField doesn't rebuild
///     its parent while typing, so the submit button's enabled state was
///     frozen at "disabled" forever. The walk below TAPS the button after
///     typing and expects the flow to advance to the shell.
///
/// Flow under test: fresh device → create account (submit) → home →
/// settings sheet → sign out → sign in (submit) → home → history tab.
Future<void> _walk(WidgetTester tester, String localeCode) async {
  SharedPreferences.setMockInitialValues({'mahtem.locale': localeCode});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(MahtemApp(auth: makeAuth(), prefs: prefs));
  // First pump flushes the async account load; the second one paints the
  // screen the gate swaps in afterwards.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  // ── create-account screen ──────────────────────────────────────────
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'Abebe Kebede');
  await tester.enterText(fields.at(1), '0911223344');
  await tester.enterText(fields.at(2), 'secret1');
  await tester.enterText(fields.at(3), 'secret1');
  await tester.pump(const Duration(milliseconds: 100));

  // The regression: after typing a complete form the button must be
  // tappable — signing up swaps the gate into the shell. (Small screens
  // need a scroll first; the button sits below the fold.)
  final createLabel = switch (localeCode) {
    'am' => 'መለያ ይክፈቱ',
    'om' => 'Herrega uumaa',
    'ti' => 'ሕሳብ ክፉቱ',
    _ => 'CREATE ACCOUNT',
  };
  await tester.ensureVisible(find.text(createLabel));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(createLabel));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(SettingsSheet), findsNothing); // sanity: sheet closed

  // ── home screen: app bar + license chip + bottom nav ───────────────
  expect(find.text('Mahtem'), findsOneWidget);

  // ── settings sheet: theme + language switchers ─────────────────────
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(SettingsSheet), findsOneWidget);
  if (localeCode == 'am') {
    expect(find.text('ስርዓት'), findsOneWidget);
    expect(find.text('ብርሃናማ'), findsOneWidget);
    expect(find.text('ጨለማ'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('አማርኛ'), findsOneWidget);
  } else if (localeCode == 'om') {
    expect(find.text('Sirna'), findsOneWidget);
    expect(find.text('Ifa'), findsOneWidget);
    expect(find.text('Dukkaa'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Afaan Oromoo'), findsOneWidget);
  } else if (localeCode == 'ti') {
    expect(find.text('ስርዓት'), findsOneWidget);
    expect(find.text('ብርሃን'), findsOneWidget);
    expect(find.text('ጽልማት'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('ትግርኛ'), findsOneWidget);
  } else {
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('አማርኛ'), findsOneWidget);
    expect(find.text('Afaan Oromoo'), findsOneWidget);
    expect(find.text('ትግርኛ'), findsOneWidget);
  }

  // Switch theme light → dark → light while the sheet is open: the
  // switcher must not overflow in either direction.
  final lightLabel = find.text(switch (localeCode) {
    'am' => 'ብርሃናማ',
    'om' => 'Ifa',
    'ti' => 'ብርሃን',
    _ => 'Light',
  });
  final darkLabel = find.text(switch (localeCode) {
    'am' => 'ጨለማ',
    'om' => 'Dukkaa',
    'ti' => 'ጽልማት',
    _ => 'Dark',
  });
  await tester.tap(lightLabel);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(darkLabel);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(lightLabel);
  await tester.pump(const Duration(milliseconds: 200));

  // Sign out (localized dialog) → gate lands on sign-in.
  final signOutLabel = find.text(switch (localeCode) {
    'am' => 'ይውጡ',
    'om' => "Ba'aa",
    'ti' => 'ውጻኡ',
    _ => 'Sign out',
  });
  await tester.ensureVisible(signOutLabel);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(signOutLabel);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byType(FilledButton));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));

  // ── sign-in screen ─────────────────────────────────────────────────
  final signInFields = find.byType(TextField);
  await tester.enterText(signInFields.at(0), '0911223344');
  await tester.enterText(signInFields.at(1), 'secret1');
  await tester.pump(const Duration(milliseconds: 100));
  final signInLabel = switch (localeCode) {
    'am' => 'ግቡ',
    'om' => "Galmaa'aa",
    'ti' => 'ኣቱዎ',
    _ => 'SIGN IN',
  };
  await tester.ensureVisible(find.text(signInLabel));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(signInLabel));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Mahtem'), findsOneWidget);

  // ── history tab ────────────────────────────────────────────────────
  // ('History' matches both the nav tab and the screen title — presence
  // is enough; the point is walking the screen without overflow.)
  final historyLabel = find.text(switch (localeCode) {
    'am' => 'ታሪክ',
    'om' => 'Seenaa',
    'ti' => 'ታሪኽ',
    _ => 'History',
  });
  await tester.tap(historyLabel.first);
  await tester.pump(const Duration(milliseconds: 400));
  expect(historyLabel, findsWidgets);
}

void main() {
  testWidgets(
    'Amharic walk, 360x740 — no layout problems, auth flows work',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _walk(tester, 'am');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Amharic walk, 320x600 — no layout problems on small phones',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _walk(tester, 'am');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'English walk, 320x600 — no layout regressions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _walk(tester, 'en');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Afaan Oromoo walk, 320x600 — 4-language switcher must not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _walk(tester, 'om');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Tigrinya walk, 320x600 — Ethiopic labels + 4-language switcher',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _walk(tester, 'ti');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
