/// Flutter Web end-to-end proof of the FULL auth lifecycle (v1.14.1).
///
/// The v1.14.0 E2E proved sign-up + self-arming sync. This one drives the
/// complete user journey the way a real user does, on the REAL app (real
/// prefs, real secure storage, live Cloudflare Worker):
///
///   1. fresh boot → create-account screen → sign up via the real UI;
///   2. cloud backup arms itself at sign-up (live Worker round-trip);
///   3. an INDEPENDENT session proves the cloud account was actually
///      created (session + vault reachable server-side);
///   4. sign out through Settings;
///   5. SOFT RESTART (fresh controllers over the same storage) — the gate
///      must show SIGN-IN, i.e. the account PERSISTED (the exact bug the
///      user reported: "sign up doesn't create an account" — if storage
///      failed, this boot would show CREATE-ACCOUNT instead);
///   6. wrong password → visible localized error, no sign-in;
///   7. correct sign-in via the real UI → shell, session restored, cloud
///      still armed, history entry from before the restart still present.
///
/// Run (from the repo root):
///   CHROME_EXECUTABLE=/home/z/dev/bin/google-chrome DISPLAY=:99 \
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/auth_lifecycle_web_test.dart -d chrome
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mahtem/app.dart';
import 'package:mahtem/core/cloud/cloud_api.dart';
import 'package:mahtem/core/cloud/cloud_keys.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/main.dart' as app;
import 'package:mahtem/state/auth_controller.dart';
import 'package:mahtem/state/cloud_controller.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'sign up → self-arm → sign out → restart → sign in all work',
    (tester) async {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final identifier = 'auth-lc-$stamp@mahtem.test';
      final password = 'e2e-pass-$stamp';
      final entryId = 'e2e-entry-$stamp';

      Future<T> step<T>(String label, Future<T> Function() body) async {
        try {
          return await body();
        } catch (e, s) {
          fail('E2E STEP FAILED — $label :: $e\n$s');
        }
      }

      Future<void> settle([Duration d = const Duration(seconds: 3)]) async {
        await Future<void>.delayed(d);
        await tester.pumpAndSettle();
      }

      /// Waits until the cloud controller is enabled and idle (arming
      /// finished) — two consecutive stable checks.
      Future<void> waitCloudSettled(CloudController cloud) async {
        var stable = 0;
        for (var i = 0; i < 80 && stable < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await tester.pump();
          stable = (cloud.enabled && !cloud.isWorking) ? stable + 1 : 0;
        }
        expect(cloud.enabled, isTrue, reason: 'cloud must be armed');
        expect(cloud.isWorking, isFalse, reason: 'cloud must be idle');
      }

      AuthController authOf(WidgetTester t) =>
          Provider.of<AuthController>(
            t.element(find.byType(MaterialApp).first),
            listen: false,
          );

      try {
        // ── 1. boot the real app → create-account screen ───────────────
        await step('boot the real app', () async {
          await app.main();
          await settle(const Duration(seconds: 4));
          expect(find.byType(TextField), findsAtLeast(4),
              reason: 'fresh device must show the create-account screen '
                  '(4 fields)');
        });

        // ── 2. sign up through the real UI ─────────────────────────────
        await step('sign up via the real UI', () async {
          final fields = find.byType(TextField);
          for (var i = 0; i < 4; i++) {
            await tester.ensureVisible(fields.at(i));
          }
          await tester.enterText(fields.at(0), 'Auth E2E Tester');
          await tester.enterText(fields.at(1), identifier);
          await tester.enterText(fields.at(2), password);
          await tester.enterText(fields.at(3), password);
          await tester.pump();
          await tester.tap(find.text('CREATE ACCOUNT'));
          await settle(const Duration(seconds: 6));
          expect(find.byIcon(Icons.settings_outlined), findsOneWidget,
              reason: 'sign-up must land on the home shell');
          expect(authOf(tester).isSignedIn, isTrue);
        });

        final ctx = tester.element(find.byType(MaterialApp).first);
        final cloud = Provider.of<CloudController>(ctx, listen: false);

        // ── 3. cloud armed itself at sign-up ───────────────────────────
        await step('cloud self-arms at sign-up (live Worker)', () async {
          await waitCloudSettled(cloud);
          expect(cloud.lastSyncAt, isNotNull,
              reason: 'arming must stamp the first merge-upload');
        });

        // ── 4. independent proof the cloud ACCOUNT exists ──────────────
        await step('independent session proves the cloud account exists',
            () async {
          final idHash = await cloudIdentifierHash(identifier);
          final authKey = await deriveCloudAuthKey(password);
          final api = CloudApi();
          final session = await api.createSession(
            identifierHash: idHash,
            authKey: authKey,
          );
          expect(session.sessionToken, isNotEmpty,
              reason: 'the cloud account must exist and accept the '
                  'credentials — this is what "account created" means '
                  'server-side');
          final remote = await api.getVault(session.sessionToken);
          expect(remote, isNotNull,
              reason: 'arming must have merge-uploaded a vault');
          await api.deleteSession(session.sessionToken);
        });

        // ── 5. insert a history entry (survival marker for restart) ────
        await step('insert history entry via real store', () async {
          final history = Provider.of<VerifyHistory>(ctx, listen: false);
          await history.add(HistoryEntry(
            id: entryId,
            bankId: 'cbe',
            bankName: 'CBE',
            reference: 'FT25$stamp',
            senderName: 'E2E Sender',
            receiverName: 'E2E Receiver',
            amount: 100,
            currency: 'ETB',
            verifiedAt: stamp,
            status: 'verified',
          ));
          await tester.pump();
          expect(history.entries.map((e) => e.id), contains(entryId));
        });

        // ── 6. sign out through Settings ───────────────────────────────
        await step('sign out through settings UI', () async {
          await tester.tap(find.byIcon(Icons.settings_outlined));
          await settle(const Duration(seconds: 2));
          await tester.ensureVisible(find.text('Sign out'));
          await tester.tap(find.text('Sign out'));
          await settle(const Duration(seconds: 1));
          // Confirm dialog → FilledButton 'Sign out'.
          await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
          await settle(const Duration(seconds: 3));
          expect(authOf(tester).isSignedIn, isFalse,
              reason: 'sign-out must clear the session');
          expect(authOf(tester).hasAccounts, isTrue,
              reason: 'the account record must remain on the device');
          expect(find.text('SIGN IN'), findsOneWidget,
              reason: 'gate must swap to the sign-in screen');
        });

        // ── 7. SOFT RESTART — persistence proof ────────────────────────
        // Fresh controllers over the same storage: if accounts were NOT
        // persisted this boot would show the create-account screen again
        // (the reported bug), not sign-in.
        await step('soft restart → gate shows SIGN-IN (account persisted)',
            () async {
          final prefs = await SharedPreferences.getInstance();
          await tester.pumpWidget(MahtemApp(prefs: prefs));
          await settle(const Duration(seconds: 5));
          expect(find.byType(TextField), findsNWidgets(2),
              reason: 'restart must land on the sign-in screen (2 fields) '
                  '— NOT create-account');
          expect(find.text('SIGN IN'), findsOneWidget);
          expect(authOf(tester).hasAccounts, isTrue,
              reason: 'account must load back from secure storage');
          expect(authOf(tester).isSignedIn, isFalse,
              reason: 'session stays cleared after restart');
        });

        // ── 8. wrong password → visible error, no sign-in ──────────────
        await step('wrong password shows a visible error', () async {
          final fields = find.byType(TextField);
          await tester.enterText(fields.at(0), identifier);
          await tester.enterText(fields.at(1), 'wrong-$password');
          await tester.pump();
          await tester.tap(find.text('SIGN IN'));
          await settle(const Duration(seconds: 4));
          expect(find.textContaining('Wrong password'), findsOneWidget,
              reason: 'the error must be VISIBLE to the user');
          expect(authOf(tester).isSignedIn, isFalse);
        });

        // ── 9. correct sign-in → shell, cloud armed, history intact ────
        await step('sign in via the real UI', () async {
          final fields = find.byType(TextField);
          await tester.enterText(fields.at(0), identifier);
          await tester.enterText(fields.at(1), password);
          await tester.pump();
          await tester.tap(find.text('SIGN IN'));
          await settle(const Duration(seconds: 6));
          expect(find.byIcon(Icons.settings_outlined), findsOneWidget,
              reason: 'sign-in must land on the home shell');
          final auth = authOf(tester);
          expect(auth.isSignedIn, isTrue);
          expect(auth.currentAccount!.identifier, identifier);
        });

        await step('cloud still armed after sign-in', () async {
          await waitCloudSettled(cloud);
          expect(cloud.hasSession, isTrue);
        });

        await step('history entry survived the restart', () async {
          final ctx2 = tester.element(find.byType(MaterialApp).first);
          final history = Provider.of<VerifyHistory>(ctx2, listen: false);
          expect(history.entries.map((e) => e.id), contains(entryId),
              reason: 'local history must persist across app restarts');
        });

        // ── 10. privacy cleanup: delete the cloud copy ─────────────────
        await step('disable deletes the cloud copy', () async {
          await cloud.disable();
          await settle(const Duration(seconds: 6));
          expect(cloud.enabled, isFalse);
          final idHash = await cloudIdentifierHash(identifier);
          final authKey = await deriveCloudAuthKey(password);
          final api = CloudApi();
          final s2 = await api.createSession(
            identifierHash: idHash,
            authKey: authKey,
          );
          final gone = await api.getVault(s2.sessionToken);
          expect(gone, isNull, reason: 'disable must delete the cloud copy');
          await api.deleteSession(s2.sessionToken);
        });
      } catch (e) {
        fail('E2E UNCAUGHT :: $e');
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
