import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mahtem/app.dart';
import 'package:mahtem/core/auth/password_hasher.dart';
import 'package:mahtem/core/localization/app_strings.dart'
    show EnglishStrings;
import 'package:mahtem/state/auth_controller.dart';
import 'package:mahtem/ui/screens/auth/create_account_screen.dart';
import 'package:mahtem/ui/screens/auth/sign_in_screen.dart';
import 'package:mahtem/ui/shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end auth test against the REAL app and REAL platform storage
/// (flutter_secure_storage web implementation + SharedPreferences) —
/// the exact layer that lost accounts in production.
///
/// Flow mirrors the user's report: create account → app restart →
/// the session should boot straight into the shell and a fresh sign-in
/// must find the account.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const kAccountKey = 'mahtem.auth.accounts_v1';
  const kSessionKey = 'mahtem.auth.session_v1';

  Future<void> wipeAuthStorage() async {
    // Both layers of ResilientAccountStore: secure storage + prefs mirror.
    const secure = FlutterSecureStorage();
    for (final key in [kAccountKey, kSessionKey]) {
      try {
        await secure.delete(key: key);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {}
    }
  }

  /// Pumps forward without pumpAndSettle — the gate splash has an
  /// infinite spinner that never settles.
  Future<void> settle(WidgetTester tester, {int ticks = 25}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  MahtemApp buildApp() =>
      MahtemApp(hasher: PasswordHasher(iterations: 1000)); // fast PBKDF2

  testWidgets('create account → restart → session + sign-in survive',
      (tester) async {
    debugPrint('STAGE 0: wiping auth storage');
    await wipeAuthStorage();
    debugPrint('STAGE 0 done');

    const name = 'Abebe Kebede';
    const phone = '0911223344';
    const password = 'secret1';
    const strings = EnglishStrings();

    // ── Run 1: fresh install → create account via the real UI ────────
    debugPrint('STAGE 1: booting app');
    await tester.pumpWidget(buildApp());
    await settle(tester);
    debugPrint('STAGE 1: app booted, checking gate');
    expect(find.byType(CreateAccountScreen), findsOneWidget,
        reason: 'fresh device must open the create-account screen');

    final fields = find.byType(TextField);
    debugPrint('STAGE 2: filling form (${fields.evaluate().length} fields)');
    expect(fields, findsNWidgets(4)); // name, identifier, password, confirm
    await tester.enterText(fields.at(0), name);
    await tester.enterText(fields.at(1), phone);
    await tester.enterText(fields.at(2), password);
    await tester.enterText(fields.at(3), password);
    await tester.pump();

    debugPrint('STAGE 3: tapping CREATE ACCOUNT');
    await tester.tap(find.text(strings.createAccountButton));
    await settle(tester);
    debugPrint('STAGE 3: tapped, checking shell');
    expect(find.byType(ShellScreen), findsOneWidget,
        reason: 'sign-up must land in the app shell');

    // ── App restart: tear the whole widget tree down and rebuild ─────
    // The process/storage layer is NOT reset — exactly like closing and
    // reopening the app on the same device.
    debugPrint('STAGE 4: simulating restart');
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, ticks: 3);
    await tester.pumpWidget(buildApp());
    await settle(tester);
    debugPrint('STAGE 4: restarted, checking shell');

    expect(find.byType(ShellScreen), findsOneWidget,
        reason: 'the persisted session must boot straight into the shell');

    // ── Sign out (controller) → sign in again through the real UI ────
    debugPrint('STAGE 5: signing out');
    final context = tester.element(find.byType(ShellScreen));
    await context.read<AuthController>().signOut();
    await settle(tester, ticks: 6);
    debugPrint('STAGE 5: signed out, checking sign-in screen');
    expect(find.byType(SignInScreen), findsOneWidget);

    debugPrint('STAGE 6: signing in');
    final signInFields = find.byType(TextField);
    expect(signInFields, findsNWidgets(2));
    await tester.enterText(signInFields.at(0), phone);
    await tester.enterText(signInFields.at(1), password);
    await tester.pump();

    await tester.tap(find.text(strings.signInButton));
    await settle(tester);
    debugPrint('STAGE 6: signed in, final check');

    expect(find.byType(ShellScreen), findsOneWidget,
        reason: 'sign-in must find the account created before the restart');
  });
}
