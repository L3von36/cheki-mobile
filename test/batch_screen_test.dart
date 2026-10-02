import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/licensing/license_store.dart';
import 'package:mahtem/core/localization/app_strings.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/receipt_verify/verifier.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/batch_controller.dart';
import 'package:mahtem/state/license_controller.dart';
import 'package:mahtem/state/locale_controller.dart';
import 'package:mahtem/ui/screens/batch_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.12.0 batch screen: paste → pick bank → run → table of results.
/// Fake verifiers, in-memory licensing; English locale.

VerifyResult _ok(String reference) => VerifyResult.receipt(
      ReceiptData(
        verified: true,
        bankCode: 'telebirr',
        bankName: 'Telebirr',
        reference: reference,
        senderName: 'ABEBE',
        receiverName: 'MAHTEM SHOP',
        amount: 1500,
        currency: 'ETB',
        date: '2026-10-02 10:00:00',
      ),
      10,
    );

Widget _harness({
  required BatchController batch,
  required LicenseController license,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<BatchController>.value(value: batch),
      ChangeNotifierProvider<VerifyHistory>.value(value: VerifyHistory()),
      ChangeNotifierProvider<LicenseController>.value(value: license),
      ChangeNotifierProvider<LocaleController>(
        create: (_) => LocaleController(prefs: null)..ensureLoaded(),
      ),
    ],
    child: const MaterialApp(home: BatchScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('paste, pick a bank, run, and see per-row results',
      (tester) async {
    final batch = BatchController(
      verifyFn: (input) async => input.reference == 'CHQ261Z4AB3D'
          ? VerifyResult.failed(
              const VerifyFailure(VerifyErrorKind.notFound, 'Receipt not found'),
              5,
            )
          : _ok(input.reference),
      extraVerifyFn: (input) async => _ok(input.reference),
    );
    final license = LicenseController(
      store: MemoryLicenseStore(),
      deviceKeySource: () async => 'device-1',
    );

    await tester.pumpWidget(_harness(batch: batch, license: license));
    await tester.pumpAndSettle();

    // Paste two references.
    await tester.enterText(
      find.byType(TextField).first,
      'CHQ261Z4AB2C\nCHQ261Z4AB3D',
    );
    await tester.pumpAndSettle();

    // Start is disabled until a bank covers the plain references —
    // both lines are telebirr-shaped so they auto-detect and the
    // button is already live. Tap it.
    final strings = AppStrings.of(AppLocale.english);
    expect(find.text(strings.batchStart(2)), findsOneWidget);
    await tester.tap(find.text(strings.batchStart(2)));
    await tester.pumpAndSettle();

    // Row results: one verified with its amount, one failed with the
    // engine's reason.
    expect(find.text('ETB 1,500.00'), findsOneWidget);
    expect(find.text('Receipt not found'), findsOneWidget);
    // Status line shows the final counts.
    expect(find.text('✓ 1 verified · ✗ 1 not verified'), findsOneWidget);
    // License was charged once per row.
    expect(license.trialsLeft, 3); // 5 free - 2 batch rows
  });

  testWidgets('duplicates collapse and the start button reflects the '
      'chargeable count', (tester) async {
    final batch = BatchController(
      verifyFn: (input) async => _ok(input.reference),
      extraVerifyFn: (input) async => _ok(input.reference),
    );
    final license = LicenseController(
      store: MemoryLicenseStore(),
      deviceKeySource: () async => 'device-1',
    );

    await tester.pumpWidget(_harness(batch: batch, license: license));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'CHQ261Z4AB2C\nchq261z4ab2c\nCHQ261Z4AB4E',
    );
    await tester.pumpAndSettle();

    // 3 lines, 1 duplicate → 2 chargeable; auto-detected telebirr.
    final strings = AppStrings.of(AppLocale.english);
    expect(find.text(strings.batchStart(2)), findsOneWidget);
    expect(find.textContaining('1 duplicate skipped'), findsOneWidget);
  });

  testWidgets('stop leaves the rest pending with a resume button',
      (tester) async {
    late final BatchController batch;
    batch = BatchController(
      verifyFn: (input) async {
        if (input.reference == 'CHQ261Z4AB3D') {
          batch.stop();
        }
        return _ok(input.reference);
      },
      extraVerifyFn: (input) async => _ok(input.reference),
    );
    final license = LicenseController(
      store: MemoryLicenseStore(),
      deviceKeySource: () async => 'device-1',
    );

    await tester.pumpWidget(_harness(batch: batch, license: license));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'CHQ261Z4AB2C\nCHQ261Z4AB3D\nCHQ261Z4AB4E',
    );
    await tester.pumpAndSettle();

    final strings = AppStrings.of(AppLocale.english);
    await tester.tap(find.text(strings.batchStart(3)));
    await tester.pumpAndSettle();

    // Row 3 never ran — the resume button offers it.
    expect(find.text(strings.batchRemaining(1)), findsOneWidget);
    expect(batch.verifiedCount, 2);
    expect(batch.pendingCount, 1);
  });
}
