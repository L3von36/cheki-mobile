import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/licensing/license_store.dart';
import 'package:mahtem/core/receipt_verify/extra_banks.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/license_controller.dart';
import 'package:mahtem/state/locale_controller.dart';
import 'package:mahtem/state/theme_controller.dart';
import 'package:mahtem/state/verify_controller.dart';
import 'package:mahtem/ui/flow.dart';
import 'package:mahtem/ui/screens/result_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.10.1 CBE printed-number gate: the FT number printed on a CBE slip can
/// never verify — the bank's receipt API only accepts its shared,
/// cryptographically-valid receipt codes (live-verified Oct 2026: printed FT
/// references always answer HTTP 500 "Security Alert"). So
/// [runVerificationFlow] explains BEFORE running instead of burning a
/// licensed check on a guaranteed failure. Widget tests run in English
/// (default locale) with in-memory storage — no platform channels touched.

VerifyResult _failedResult() => VerifyResult.failed(
      const VerifyFailure(VerifyErrorKind.notFound, 'nope'),
      5,
    );

Widget _harness({
  required VerifyController controller,
  required WidgetBuilder onReady,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VerifyController>.value(value: controller),
      ChangeNotifierProvider<VerifyHistory>.value(value: VerifyHistory()),
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
    child: MaterialApp(home: Builder(builder: onReady)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'CBE + printed FT reference: guidance dialog, no check, no attempt '
      'burned', (tester) async {
    var verifyCalls = 0;
    final controller = VerifyController(
      verifyFn: (input) async {
        verifyCalls++;
        return _failedResult();
      },
      extraVerifyFn: (input) async {
        verifyCalls++;
        return _failedResult();
      },
    );
    controller.selectBank(bankByIdAll('cbe'));
    controller.setReference('FT2614977L8S'); // the shape printed on a slip

    late final BuildContext context;
    await tester.pumpWidget(_harness(
      controller: controller,
      onReady: (ctx) {
        context = ctx;
        return const SizedBox.expand();
      },
    ));

    final flow = runVerificationFlow(context);
    await tester.pumpAndSettle();

    // The explanation shows instead of running a doomed check.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('CBE needs the receipt code'), findsOneWidget);
    expect(verifyCalls, isZero);
    // The flow returns BEFORE the licensing gate — no provider was even
    // touched, so no trial attempt could have been consumed.
    expect(controller.result, isNull);
    expect(controller.status, VerifyStatus.idle);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await flow;
  });

  testWidgets(
      'CBE + a real receipt code (link / QR token) runs the verification '
      'without the dialog', (tester) async {
    var extraCalls = 0;
    final controller = VerifyController(
      verifyFn: (input) async => _failedResult(),
      extraVerifyFn: (input) async {
        extraCalls++;
        return _failedResult();
      },
    );
    controller.selectBank(bankByIdAll('cbe'));
    controller.setReference('fHCxyV4mg5pRIwEkJO'); // code from a shared link

    late final BuildContext context;
    await tester.pumpWidget(_harness(
      controller: controller,
      onReady: (ctx) {
        context = ctx;
        return const SizedBox.expand();
      },
    ));

    final flow = runVerificationFlow(context);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(AlertDialog), findsNothing);
    expect(extraCalls, 1); // the check ran (CBE routes to the extra verifier)

    // The flow pushed the result screen — pop it so the awaited flow
    // unwinds cleanly before the test ends.
    await tester.pumpAndSettle();
    expect(find.byType(ResultScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ResultScreen))).pop();
    await tester.pumpAndSettle();
    await flow;
  });

  testWidgets(
      'FT references stay verifiable at banks that accept them (Amhara), '
      'so the gate only guards CBE', (tester) async {
    var extraCalls = 0;
    final controller = VerifyController(
      verifyFn: (input) async => _failedResult(),
      extraVerifyFn: (input) async {
        extraCalls++;
        return _failedResult();
      },
    );
    controller.selectBank(bankByIdAll('amhara'));
    controller.setReference('FT262507XG9T'); // Amhara's own FT shape

    late final BuildContext context;
    await tester.pumpWidget(_harness(
      controller: controller,
      onReady: (ctx) {
        context = ctx;
        return const SizedBox.expand();
      },
    ));

    final flow = runVerificationFlow(context);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(AlertDialog), findsNothing);
    expect(extraCalls, 1);

    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ResultScreen))).pop();
    await tester.pumpAndSettle();
    await flow;
  });
}
