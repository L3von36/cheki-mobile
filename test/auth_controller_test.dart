import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/auth/account_store.dart';
import 'package:mahtem/core/auth/password_hasher.dart';
import 'package:mahtem/core/auth/remote_account.dart';
import 'package:mahtem/state/auth_controller.dart';

AuthController _controller([MemoryAccountStore? store]) => AuthController(
  store: store ?? MemoryAccountStore(),
  hasher: PasswordHasher(iterations: 1000),
);

/// Scriptable stand-in for the cloud account directory (v1.14.4).
class FakeDirectory implements RemoteAccountDirectory {
  FakeDirectory(this.outcome);
  RemoteAuthOutcome outcome;
  int calls = 0;
  String? lastAccountId;
  String? lastPassword;

  @override
  Future<RemoteAuthOutcome> authenticate({
    required String accountId,
    required String password,
  }) async {
    calls++;
    lastAccountId = accountId;
    lastPassword = password;
    return outcome;
  }
}

void main() {
  test('sign up creates the account and signs in', () async {
    final auth = _controller();
    final result = await auth.signUp(
      displayName: 'Abebe Kebede',
      identifier: '0911223344',
      password: 'secret1',
    );
    expect(result, isA<AuthSuccess>());
    expect(auth.isSignedIn, isTrue);
    expect(auth.currentAccount!.displayName, 'Abebe Kebede');
    // Identifier normalized to the international form.
    expect(auth.currentAccount!.id, '251911223344');
  });

  test('sign up refuses duplicate identifiers in any format', () async {
    final auth = _controller();
    await auth.signUp(
      displayName: 'Abebe',
      identifier: '0911223344',
      password: 'secret1',
    );
    final dup = await auth.signUp(
      displayName: 'Bekele',
      identifier: '+251 911 223 344',
      password: 'secret2',
    );
    expect(dup, isA<AuthFailure>());
    expect((dup as AuthFailure).error, AuthError.alreadyExists);
    expect(auth.accounts.length, 1);
  });

  test('sign up validates every input', () async {
    final auth = _controller();

    final shortName = await auth.signUp(
      displayName: 'A',
      identifier: '0911223344',
      password: 'secret1',
    );
    expect((shortName as AuthFailure).error, AuthError.invalidName);

    final badPhone = await auth.signUp(
      displayName: 'Abebe',
      identifier: '12345',
      password: 'secret1',
    );
    expect((badPhone as AuthFailure).error, AuthError.invalidIdentifier);

    final badEmail = await auth.signUp(
      displayName: 'Abebe',
      identifier: 'abebe@bad',
      password: 'secret1',
    );
    expect((badEmail as AuthFailure).error, AuthError.invalidEmail);

    final shortPassword = await auth.signUp(
      displayName: 'Abebe',
      identifier: '0911223344',
      password: '123',
    );
    expect((shortPassword as AuthFailure).error, AuthError.invalidPassword);

    expect(auth.hasAccounts, isFalse);
    expect(auth.isSignedIn, isFalse);
  });

  test(
    'sign in accepts equivalent phone formats, refuses wrong passwords',
    () async {
      final auth = _controller();
      await auth.signUp(
        displayName: 'Abebe',
        identifier: '0911223344',
        password: 'secret1',
      );
      await auth.signOut();
      expect(auth.isSignedIn, isFalse);

      final wrong = await auth.signIn(
        identifier: '0911223344',
        password: 'nope123',
      );
      expect(wrong, isA<AuthFailure>());
      expect((wrong as AuthFailure).error, AuthError.wrongPassword);

      final ok = await auth.signIn(
        identifier: '+251911223344',
        password: 'secret1',
      );
      expect(ok, isA<AuthSuccess>());
      expect(auth.isSignedIn, isTrue);
    },
  );

  test('sign in works by email, case-insensitively', () async {
    final auth = _controller();
    await auth.signUp(
      displayName: 'Abebe',
      identifier: 'Abebe@Mail.com',
      password: 'secret1',
    );
    await auth.signOut();

    final ok = await auth.signIn(
      identifier: 'abebe@mail.com',
      password: 'secret1',
    );
    expect(ok, isA<AuthSuccess>());
  });

  test('unknown identifier signs in as account-not-found', () async {
    final auth = _controller();
    final result = await auth.signIn(
      identifier: '0944556677',
      password: 'whatever',
    );
    expect(result, isA<AuthFailure>());
    expect((result as AuthFailure).error, AuthError.accountNotFound);
  });

  test('session survives a fresh controller (app restart)', () async {
    final store = MemoryAccountStore();
    final first = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
    );
    await first.signUp(
      displayName: 'Abebe',
      identifier: '0911223344',
      password: 'secret1',
    );

    final second = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
    );
    expect(second.isLoaded, isFalse);
    await second.ensureLoaded();
    expect(second.isLoaded, isTrue);
    expect(second.isSignedIn, isTrue);
    expect(second.currentAccount!.displayName, 'Abebe');
  });

  test('sign out clears the session but keeps the account', () async {
    final store = MemoryAccountStore();
    final auth = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
    );
    await auth.signUp(
      displayName: 'Abebe',
      identifier: '0911223344',
      password: 'secret1',
    );
    await auth.signOut();
    expect(auth.isSignedIn, isFalse);

    final fresh = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
    );
    await fresh.ensureLoaded();
    expect(fresh.isSignedIn, isFalse);
    expect(fresh.hasAccounts, isTrue);
  });

  test('resetAccounts wipes accounts and session', () async {
    final store = MemoryAccountStore();
    final auth = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
    );
    await auth.signUp(
      displayName: 'Abebe',
      identifier: '0911223344',
      password: 'secret1',
    );
    await auth.resetAccounts();
    expect(auth.hasAccounts, isFalse);
    expect(auth.isSignedIn, isFalse);

    final fresh = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
    );
    await fresh.ensureLoaded();
    expect(fresh.hasAccounts, isFalse);
  });

  test('isBusy flips on during mutations and resets after', () async {
    final auth = _controller();
    var sawBusy = false;
    auth.addListener(() {
      if (auth.isBusy) sawBusy = true;
    });
    await auth.signUp(
      displayName: 'Abebe',
      identifier: '0911223344',
      password: 'secret1',
    );
    expect(sawBusy, isTrue);
    expect(auth.isBusy, isFalse);
  });

  // ── v1.14.4 — cloud-backed sign-in (cleared data / second device) ──

  test(
    'cleared data: cloud-proven credentials rebuild the account and '
    'sign in, then keep working offline',
    () async {
      final store = MemoryAccountStore();
      final dir = FakeDirectory(
        const RemoteAuthConfirmed(
          RemoteAccountProfile(
            identifier: '0911223344',
            displayName: 'Abebe Bekele',
            createdAtMs: 1700000000000,
          ),
        ),
      );
      final auth = AuthController(
        store: store,
        hasher: PasswordHasher(iterations: 1000),
        remoteDirectory: dir,
      );
      // Nothing local — the exact "cleared app data" state.
      expect(auth.hasAccounts, isFalse);
      final result = await auth.signIn(
        identifier: '+251911223344',
        password: 'secret1',
      );
      expect(result, isA<AuthSuccess>());
      expect(dir.calls, 1);
      // The controller hands the directory the NORMALIZED identifier —
      // the same string backup arming hashed at sign-up.
      expect(dir.lastAccountId, '251911223344');
      expect(dir.lastPassword, 'secret1');
      // Profile fields restored from the encrypted vault.
      expect(auth.currentAccount!.displayName, 'Abebe Bekele');
      expect(auth.currentAccount!.id, '251911223344');
      expect(auth.currentAccount!.identifier, '0911223344');
      expect(
        auth.currentAccount!.createdAtUtc.millisecondsSinceEpoch,
        1700000000000,
      );

      // The rebuilt account is PERSISTED — a fresh controller (app
      // restart) finds it and signs in WITHOUT the directory again.
      final second = AuthController(
        store: store,
        hasher: PasswordHasher(iterations: 1000),
        remoteDirectory: dir,
      );
      await second.ensureLoaded();
      expect(second.hasAccounts, isTrue);
      final again = await second.signIn(
        identifier: '0911223344',
        password: 'secret1',
      );
      expect(again, isA<AuthSuccess>());
      expect(dir.calls, 1); // untouched — the local fast path served it
    },
  );

  test('local account hit never consults the cloud directory', () async {
    final dir = FakeDirectory(const RemoteAuthUnknownAccount());
    final auth = AuthController(
      store: MemoryAccountStore(),
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: dir,
    );
    await auth.signUp(
      displayName: 'Abebe',
      identifier: '0911223344',
      password: 'secret1',
    );
    await auth.signOut();
    final result = await auth.signIn(
      identifier: '0911223344',
      password: 'secret1',
    );
    expect(result, isA<AuthSuccess>());
    expect(dir.calls, 0);
  });

  test('cloud unknown account maps to accountNotFound', () async {
    final auth = AuthController(
      store: MemoryAccountStore(),
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: FakeDirectory(const RemoteAuthUnknownAccount()),
    );
    final result = await auth.signIn(
      identifier: '0944556677',
      password: 'whatever',
    );
    expect((result as AuthFailure).error, AuthError.accountNotFound);
  });

  test('cloud bad password maps to wrongPassword', () async {
    final auth = AuthController(
      store: MemoryAccountStore(),
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: FakeDirectory(const RemoteAuthBadPassword()),
    );
    final result = await auth.signIn(
      identifier: '0944556677',
      password: 'secret1',
    );
    expect((result as AuthFailure).error, AuthError.wrongPassword);
  });

  test('unreachable cloud maps to network, never to "no account"', () async {
    final auth = AuthController(
      store: MemoryAccountStore(),
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: FakeDirectory(const RemoteAuthUnreachable()),
    );
    final result = await auth.signIn(
      identifier: '0944556677',
      password: 'secret1',
    );
    expect((result as AuthFailure).error, AuthError.network);
  });

  test('no vault profile falls back to the display identifier', () async {
    final auth = AuthController(
      store: MemoryAccountStore(),
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: FakeDirectory(const RemoteAuthConfirmed(null)),
    );
    final result = await auth.signIn(
      identifier: '0911223344',
      password: 'secret1',
    );
    expect(result, isA<AuthSuccess>());
    // v1.14.3-era vaults carry no name — the display form of the
    // normalized identifier stands in until a real sync re-writes it.
    expect(auth.currentAccount!.displayName, '+251911223344');
  });

  test('directory throwing is surfaced as network, not "no account"',
      () async {
    final auth = AuthController(
      store: MemoryAccountStore(),
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: _ThrowingDirectory(),
    );
    final result = await auth.signIn(
      identifier: '0944556677',
      password: 'secret1',
    );
    expect((result as AuthFailure).error, AuthError.network);
  });

  test('device at the account cap makes room instead of losing the newest',
      () async {
    final store = MemoryAccountStore();
    final auth = _controller(store);
    for (var i = 0; i < 8; i++) {
      await auth.signUp(
        displayName: 'User $i',
        identifier: '09112233$i$i',
        password: 'secret1',
      );
    }
    expect(auth.accounts.length, 8);
    final dir = FakeDirectory(
      const RemoteAuthConfirmed(
        RemoteAccountProfile(identifier: '0944556677', displayName: 'Newest'),
      ),
    );
    final full = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: dir,
    );
    await full.ensureLoaded();
    final result = await full.signIn(
      identifier: '0944556677',
      password: 'secret1',
    );
    expect(result, isA<AuthSuccess>());
    expect(full.accounts.length, 8);
    // The adopted account survived persistence, the oldest gave way.
    final reborn = AuthController(
      store: store,
      hasher: PasswordHasher(iterations: 1000),
      remoteDirectory: dir,
    );
    await reborn.ensureLoaded();
    expect(reborn.accounts.length, 8);
    expect(
      reborn.accounts.any((a) => a.id == '251944556677'),
      isTrue,
    );
    expect(
      reborn.accounts.any((a) => a.id == '251911223300'),
      isFalse,
    );
  });
}

/// A directory that blows up mid-flight — the inconclusive path.
class _ThrowingDirectory implements RemoteAccountDirectory {
  @override
  Future<RemoteAuthOutcome> authenticate({
    required String accountId,
    required String password,
  }) async {
    throw StateError('boom');
  }
}
