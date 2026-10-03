import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/auth/account_store.dart';
import 'package:mahtem/core/error_safety_net.dart';
import 'package:mahtem/core/auth/password_hasher.dart';
import 'package:mahtem/state/auth_controller.dart';

/// A fake primary layer that simulates a broken platform secure store:
/// reads/writes throw once [broken] flips, and the data written BEFORE
/// it broke stays intact (so recovery can be proven after healing).
class FlakyStore implements AccountKeyValue {
  final Map<String, String> values = {};
  bool broken = false;

  @override
  Future<String?> read(String key) async {
    if (broken) throw Exception('platform decryption failed (AEADBadTag)');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (broken) throw Exception('platform encryption failed');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (broken) throw Exception('platform delete failed');
    values.remove(key);
  }
}

void main() {
  setUp(DiagnosticsLog.I.clear);

  group('ResilientAccountStore — healthy layers', () {
    test('write lands in both layers, read comes from primary', () async {
      final primary = MemoryAccountStore();
      final mirror = MemoryAccountStore();
      final store = ResilientAccountStore(primary: primary, mirror: mirror);

      await store.write('accounts_v1', '[{"id":"a"}]');
      expect(primary.values['accounts_v1'], isNotNull);
      expect(mirror.values['accounts_v1'], isNotNull);
      expect(await store.read('accounts_v1'), '[{"id":"a"}]');
    });

    test('delete removes from both layers', () async {
      final primary = MemoryAccountStore();
      final mirror = MemoryAccountStore();
      final store = ResilientAccountStore(primary: primary, mirror: mirror);

      await store.write('session_v1', 'x');
      await store.delete('session_v1');
      expect(primary.values.containsKey('session_v1'), isFalse);
      expect(mirror.values.containsKey('session_v1'), isFalse);
      expect(await store.read('session_v1'), isNull);
    });
  });

  group('ResilientAccountStore — secure layer breaks (user bug path)', () {
    test('read falls back to the mirror after the secure layer broke',
        () async {
      final primary = FlakyStore();
      final mirror = MemoryAccountStore();
      final store = ResilientAccountStore(primary: primary, mirror: mirror);

      // Healthy period: account + session written (v1.13.0 behavior).
      await store.write('accounts_v1', '[{"id":"251911223344"}]');
      await store.write('session_v1', '{"accountId":"251911223344"}');

      // The secure layer breaks (Keystore invalidation / plugin bug).
      primary.broken = true;

      // The account must still be found — this is the exact failure the
      // user reported ("no account found … create one first").
      expect(await store.read('accounts_v1'), '[{"id":"251911223344"}]');
      expect(await store.read('session_v1'), '{"accountId":"251911223344"}');
      // Degraded events are visible in the diagnostics trail.
      expect(
        DiagnosticsLog.I.entries.any((e) => e.message.contains('primary-read')),
        isTrue,
      );
    });

    test('write still persists through the mirror when secure throws',
        () async {
      final primary = FlakyStore()..broken = true;
      final mirror = MemoryAccountStore();
      final store = ResilientAccountStore(primary: primary, mirror: mirror);

      // Must NOT throw — the mirror persisted the data.
      await store.write('accounts_v1', '[{"id":"a"}]');
      expect(mirror.values['accounts_v1'], '[{"id":"a"}]');
    });

    test('write throws only when BOTH layers fail', () async {
      final primary = FlakyStore()..broken = true;
      final store = ResilientAccountStore(primary: primary, mirror: null);

      await expectLater(
        store.write('accounts_v1', '[]'),
        throwsA(isA<Exception>()),
      );
    });

    test('auth survives restart with a broken secure store end-to-end',
        () async {
      final primary = FlakyStore();
      final mirror = MemoryAccountStore();

      // First run: sign up through the resilient store.
      final first = AuthController(
        store: ResilientAccountStore(primary: primary, mirror: mirror),
        hasher: PasswordHasher(iterations: 1000),
      );
      final signUp = await first.signUp(
        displayName: 'Abebe',
        identifier: '0911223344',
        password: 'secret1',
      );
      expect(signUp, isA<AuthSuccess>());

      // Second run (app restart): the secure layer has meanwhile broken.
      primary.broken = true;
      final second = AuthController(
        store: ResilientAccountStore(primary: primary, mirror: mirror),
        hasher: PasswordHasher(iterations: 1000),
      );
      await second.ensureLoaded();
      // Gate resolves accounts from the mirror instead of losing them.
      expect(second.hasAccounts, isTrue);
      expect(second.isSignedIn, isTrue);
      expect(second.currentAccount!.displayName, 'Abebe');

      // Even a fresh sign-in works off the mirror.
      await second.signOut();
      final signIn = await second.signIn(
        identifier: '+251 911 223 344',
        password: 'secret1',
      );
      expect(signIn, isA<AuthSuccess>());
    });
  });

  group('sign-in error truthfulness', () {
    AuthController controller() => AuthController(
          store: MemoryAccountStore(),
          hasher: PasswordHasher(iterations: 1000),
        );

    test('malformed identifier is invalid-identifier, NOT account-not-found',
        () async {
      final auth = controller();
      final bad = await auth.signIn(
        identifier: '12345', // not a valid Ethiopian phone shape
        password: 'whatever1',
      );
      expect(bad, isA<AuthFailure>());
      expect((bad as AuthFailure).error, AuthError.invalidIdentifier);
    });

    test('malformed email is invalid-email at sign-in', () async {
      final auth = controller();
      final bad = await auth.signIn(
        identifier: 'abebe@bad',
        password: 'whatever1',
      );
      expect((bad as AuthFailure).error, AuthError.invalidEmail);
    });

    test('valid-but-unknown identifier is still account-not-found', () async {
      final auth = controller();
      final missing = await auth.signIn(
        identifier: '0944556677',
        password: 'whatever1',
      );
      expect((missing as AuthFailure).error, AuthError.accountNotFound);
    });
  });
}
