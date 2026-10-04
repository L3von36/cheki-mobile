import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/app.dart';
import 'package:mahtem/core/auth/account_store.dart';
import 'package:mahtem/core/auth/password_hasher.dart';
import 'package:mahtem/core/auth/remote_account.dart';
import 'package:mahtem/core/receipt_verify/extra_banks.dart';
import 'package:mahtem/core/receipt_verify/models.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/state/auth_controller.dart';
import 'package:mahtem/ui/screens/auth/sign_in_screen.dart';
import 'package:mahtem/ui/shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An auth controller wired to in-memory storage with a fast hasher, so
/// widget tests never touch platform secure storage.
AuthController makeAuth() => AuthController(
  store: MemoryAccountStore(),
  hasher: PasswordHasher(iterations: 1000),
);

class _ConfirmedDirectory implements RemoteAccountDirectory {
  @override
  Future<RemoteAuthOutcome> authenticate({
    required String accountId,
    required String password,
  }) async => const RemoteAuthConfirmed(
    RemoteAccountProfile(
      identifier: '0911223344',
      displayName: 'Test User',
    ),
  );
}

/// Seeds a signed-in session so the gate opens straight into the shell.
Future<AuthController> seededAuth() async {
  final auth = makeAuth();
  await auth.signUp(
    displayName: 'Test User',
    identifier: '0911223344',
    password: 'secret1',
  );
  return auth;
}

Future<void> bootToHome(WidgetTester tester, {AuthController? auth}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(MahtemApp(auth: auth));
  // The auth gate loads accounts (in-memory → one frame), then boots into
  // the shell — no splash. There is an ambient pulsing/glow animation in
  // places, so pump fixed durations instead of pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a fresh device lands on the create-account screen', (
    tester,
  ) async {
    await bootToHome(tester, auth: makeAuth());

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('CREATE ACCOUNT'), findsOneWidget);
    expect(find.text('Already have an account?'), findsOneWidget);
  });

  testWidgets('persisted verification history loads on app startup', (
    tester,
  ) async {
    const entry = HistoryEntry(
      id: 'saved-on-device',
      bankId: 'cbe',
      bankName: 'CBE',
      reference: 'FT-SAVED-1',
      verifiedAt: 1000,
      status: 'verified',
    );
    SharedPreferences.setMockInitialValues({
      'mahtem.history.v1': jsonEncode([entry.toJson()]),
    });
    await tester.pumpWidget(MahtemApp(auth: await seededAuth()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('FT-SAVED-1'), findsOneWidget);
  });

  testWidgets('sign in from create-account returns to the app shell', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthController(
      store: MemoryAccountStore(),
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: _ConfirmedDirectory(),
    );
    await bootToHome(tester, auth: auth);

    final signInLink = find.text('Sign in');
    await tester.ensureVisible(signInLink);
    await tester.pump();
    await tester.tap(signInLink);
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
    final signInFields = find.descendant(
      of: find.byType(SignInScreen),
      matching: find.byType(TextField),
    );
    await tester.enterText(signInFields.at(0), '0911223344');
    await tester.enterText(signInFields.at(1), 'secret1');
    final signInButton = find.text('SIGN IN');
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(auth.isSignedIn, isTrue);
    expect(find.byType(ShellScreen), findsOneWidget);
  });

  testWidgets('boots straight into the minimal verify form when signed in', (
    tester,
  ) async {
    await bootToHome(tester, auth: await seededAuth());

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

  testWidgets('a typed plain reference needs a bank pick before verifying', (
    tester,
  ) async {
    await bootToHome(tester, auth: await seededAuth());

    // The verify button is inert before a bank + reference are present.
    // (Raw references carry no bank information — stylepos rule.)
    await tester.enterText(find.byType(TextField).first, 'FT26140P01YB');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Auto-detect bank'), findsOneWidget);
    expect(find.text('VERIFY RECEIPT'), findsOneWidget);
  });

  testWidgets('history tab shows the empty state', (tester) async {
    await bootToHome(tester, auth: await seededAuth());

    await tester.tap(find.text('History'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No checks yet'), findsOneWidget);
  });

  test('every catalog bank exposes hint text and initials', () {
    for (final bank in kAllVerifyBanks) {
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
