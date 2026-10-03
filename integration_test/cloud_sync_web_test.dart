/// Flutter Web end-to-end proof for the v1.13.1 always-on cloud sync.
///
/// Boots the REAL MahtemApp (real prefs, real secure storage, real network
/// stack) inside a real Chrome browser and talks to the LIVE Cloudflare
/// Worker at mahtem-api.mahtem.workers.dev. Camera/OCR have no web
/// implementation, so the single history change is inserted through the
/// real [VerifyHistory] store — the exact object a verification would
/// notify, hitting the exact auto-sync listener wiring.
///
/// What this proves, in order:
///   1. the app runs and signs up on Flutter Web;
///   2. enabling Cloud Backup reaches the live Worker (lookup/create/
///      session/first merge upload) and reports success in the UI state;
///   3. WITHOUT touching the manual "Back-up now" button, a local history
///      change is pushed to Cloudflare automatically after the debounce
///      window — the phone talked to the Worker on its own;
///   4. an independent session (fresh login, same credentials, separate
///      API client — as if from another device) downloads and decrypts
///      the vault and finds the auto-pushed entry;
///   5. turning the feature off deletes the cloud copy again.
///
/// Run (from the repo root, Chrome for Testing recommended):
///   CHROME_EXECUTABLE=.../chrome flutter drive --profile
///       --driver=test_driver/integration_test.dart
///       --target=integration_test/cloud_sync_web_test.dart -d chrome
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:mahtem/core/cloud/cloud_api.dart';
import 'package:mahtem/core/cloud/cloud_keys.dart';
import 'package:mahtem/core/cloud/cloud_vault.dart';
import 'package:mahtem/core/verify_history.dart';
import 'package:mahtem/main.dart' as app;
import 'package:mahtem/state/cloud_controller.dart';
import 'package:mahtem/ui/widgets/cloud_backup_sheet.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'auto-sync talks to Cloudflare without the manual backup button',
    (tester) async {
      const debounced = Duration(seconds: 26); // > 20s default debounce
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final identifier = 'web-e2e-$stamp@mahtem.test';
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

      try {
        // ── boot the real app ──────────────────────────────────────────
        await app.main();
        await settle(const Duration(seconds: 4));

        // ── 1. sign up through the real UI ─────────────────────────────
        await step('fill sign-up form', () async {
          final fields = find.byType(TextField);
          expect(fields, findsAtLeast(4),
              reason: 'create-account screen should show 4 fields');
          for (var i = 0; i < 4; i++) {
            await tester.ensureVisible(fields.at(i));
          }
          await tester.enterText(fields.at(0), 'Web E2E Tester');
          await tester.enterText(fields.at(1), identifier);
          await tester.enterText(fields.at(2), password);
          await tester.enterText(fields.at(3), password);
          await tester.pump();
        });

        await step('tap CREATE ACCOUNT', () async {
          await tester.tap(find.text('CREATE ACCOUNT'));
          await settle(const Duration(seconds: 6));
          expect(find.byIcon(Icons.settings_outlined), findsOneWidget,
              reason: 'sign-up should land on the home shell');
        });

        final appCtx = tester.element(find.byType(MaterialApp).first);
        final cloud = Provider.of<CloudController>(appCtx, listen: false);
        expect(cloud.enabled, isFalse);
        expect(cloud.autoSyncEnabled, isTrue,
            reason: 'auto-sync defaults to ON once backup is enabled');

        // ── 2. enable Cloud Backup (real network round-trips) ──────────
        await step('open settings + cloud sheet', () async {
          await tester.tap(find.byIcon(Icons.settings_outlined));
          await settle();
          await tester.tap(find.text('Cloud backup — off'));
          await settle();
          final sheetField = find
              .descendant(
                of: find.byType(CloudBackupSheet),
                matching: find.byType(TextField),
              )
              .first;
          await tester.enterText(sheetField, password);
          await tester.pump();
        });

        await step('tap Turn on backup (live Worker)', () async {
          await tester.tap(find.text('Turn on backup'));
          await settle(const Duration(seconds: 12));
        });

        expect(cloud.enabled, isTrue,
            reason: 'enable must succeed against the live Worker '
                '(failure was: ${cloud.failure})');
        final syncAfterEnable = cloud.lastSyncAt;
        expect(syncAfterEnable, isNotNull,
            reason: 'first merge-upload should stamp lastSyncAt');

        // ── 3. local change → automatic push (no manual button!) ───────
        await step('insert history entry via real store', () async {
          final history = Provider.of<VerifyHistory>(appCtx, listen: false);
          await history.add(HistoryEntry(
            id: entryId,
            bankId: 'cbe',
            bankName: 'CBE',
            reference: 'FT25$stamp',
            senderName: 'E2E Sender',
            receiverName: 'E2E Receiver',
            amount: 250,
            currency: 'ETB',
            verifiedAt: stamp,
            status: 'verified',
          ));
          await tester.pump();
          expect(cloud.hasUnsyncedChanges, isTrue,
              reason: 'dirty flag set immediately after the change');
        });

        // The debounce is 20s in the real app — wait it out in real time.
        // This is the "phone talks to Cloudflare by itself" moment.
        await Future<void>.delayed(debounced);
        await settle(const Duration(seconds: 5));

        expect(cloud.hasUnsyncedChanges, isFalse,
            reason: 'auto-sync must clear the dirty flag after pushing');
        expect(cloud.lastSyncAt, greaterThan(syncAfterEnable!),
            reason: 'auto-sync must refresh the last-sync stamp');

        // ── 4. independent device check: download + decrypt the vault ──
        final remote = await step(
          'independent session downloads vault from live Worker',
          () async {
            final idHash = await cloudIdentifierHash(identifier);
            final authKey = await deriveCloudAuthKey(password);
            final api = CloudApi();
            final session = await api.createSession(
              identifierHash: idHash,
              authKey: authKey,
            );
            final r = await api.getVault(session.sessionToken);
            expect(r, isNotNull, reason: 'vault must exist on the Worker');
            return r!;
          },
        );
        final vaultKey = await deriveVaultKey(password, identifier);
        final entries =
            decodeVaultPayload(await decryptVaultBlob(vaultKey, remote.blob));
        expect(entries.map((e) => e.id), contains(entryId),
            reason: 'the auto-pushed vault must contain the new entry');

        // ── 5. turn off → cloud copy deleted (privacy default) ─────────
        await step('disable deletes the cloud copy', () async {
          await cloud.disable();
          await settle(const Duration(seconds: 6));
          expect(cloud.enabled, isFalse);
          final api = CloudApi();
          final idHash = await cloudIdentifierHash(identifier);
          final authKey = await deriveCloudAuthKey(password);
          final s2 = await api.createSession(
            identifierHash: idHash,
            authKey: authKey,
          );
          final gone = await api.getVault(s2.sessionToken);
          expect(gone, isNull, reason: 'disable must delete the cloud copy');
        });
      } catch (e) {
        fail('E2E UNCAUGHT :: $e');
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
