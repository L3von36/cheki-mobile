import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem_admin/admin_api.dart';
import 'package:mahtem_admin/admin_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory twin of the Worker admin API for controller tests.
class FakeAdminApi implements AdminApiClient {
  FakeAdminApi({this.acceptedTokens});

  /// Tokens the overview endpoint accepts. Null = accept anything.
  Set<String>? acceptedTokens;

  /// Owner account this fake knows about (empty = no owner yet).
  String ownerEmail = '';
  String ownerPassword = '';
  int setupCalls = 0;

  /// Session role per minted token (worker resolves it per email).
  final Map<String, AdminRole> tokenRoles = {};

  Object? throwOnOverview;
  Object? throwOnSignIn;

  int overviewCalls = 0;
  int logoutCalls = 0;
  AdminException? lastLogoutException;

  // ── management twin state (mirrors the Worker's KV) ───────────────────
  AdminSettings settingsDoc =
      const AdminSettings(signupsEnabled: true, maintenanceMode: false);
  final Map<String, AdminUser> adminUsers = {};
  final List<Announcement> announcementList = [];
  final List<AuditEntry> auditTrail = [];
  final Map<String, bool> suspendedAccounts = {};
  final Map<String, AccountDeleteResult> deletedAccounts = {};
  String? deleteAccountConfirmSent;

  static const _existingToken = 'tok-existing-session-token-0001';
  final List<String> mintedTokens = [];

  void provisionOwner(String email, String password) {
    ownerEmail = email;
    ownerPassword = password;
    acceptedTokens ??= {};
    acceptedTokens!.add(_existingToken);
    tokenRoles[_existingToken] = AdminRole.owner;
  }

  /// Adds an additional admin (worker: POST /v1/admin/users).
  void provisionAdmin(String email, String id) {
    adminUsers[id] = AdminUser(
        id: id, email: email, createdAt: 1700000000000, createdBy: ownerEmail);
  }

  AdminException _throw(Object? what) => what is AdminException
      ? what
      : AdminException(
          AdminErrorType.server,
          500,
          what?.toString() ?? 'boom',
        );

  void _requireSession(String token) {
    final accepted = acceptedTokens;
    if (accepted != null && !accepted.contains(token)) {
      throw const AdminException(
        AdminErrorType.sessionExpired,
        401,
        'Session expired — sign in again.',
      );
    }
  }

  /// Mirrors the Worker: owner-only actions throw 403 for admins.
  void _requireOwner(String token) {
    if (tokenRoles[token] != AdminRole.owner) {
      throw const AdminException(
        AdminErrorType.forbidden,
        403,
        'Only the owner account can do this.',
      );
    }
  }

  void _audit(String action, {String? target, String? detail}) {
    auditTrail.insert(
      0,
      AuditEntry(
        t: DateTime.now().millisecondsSinceEpoch,
        actor: ownerEmail,
        action: action,
        target: target,
        detail: detail,
      ),
    );
  }

  @override
  Future<AdminOverview> overview(String token) async {
    overviewCalls++;
    if (throwOnOverview != null) throw _throw(throwOnOverview);
    final accepted = acceptedTokens;
    if (accepted != null && !accepted.contains(token)) {
      throw const AdminException(
        AdminErrorType.sessionExpired,
        401,
        'Session expired — sign in again.',
      );
    }
    return _overview();
  }

  int detailCalls = 0;

  @override
  Future<AdminAccountDetail> accountDetail(String token, String uid) async {
    detailCalls++;
    return AdminAccountDetail(
      id: uid,
      createdAt: 1700000000000,
      revision: 3,
      updatedAt: 1700000100000,
      scans: 2,
      verified: 1,
      lastScanAt: 1700000090000,
      suspended: suspendedAccounts[uid] ?? false,
      banks: const [AdminBank(id: 'cbe', name: 'CBE', count: 2, verified: 1)],
      days: const [AdminDay(day: '2026-10-05', count: 2)],
      events: const [],
    );
  }

  @override
  Future<bool> hasAdmin() async => ownerEmail.isNotEmpty;

  @override
  Future<AdminSession> signIn(String email, String password) async {
    if (throwOnSignIn != null) throw _throw(throwOnSignIn);
    if (ownerEmail.isEmpty) {
      throw const AdminException(
        AdminErrorType.noAdmin,
        404,
        'No owner account exists yet. Create one first.',
      );
    }
    if (email != ownerEmail || password != ownerPassword) {
      throw const AdminException(
        AdminErrorType.badCredentials,
        401,
        'Wrong email or password.',
      );
    }
    final session = _mint(email);
    _audit('login', detail: email == ownerEmail ? 'owner' : 'admin');
    return session;
  }

  @override
  Future<AdminSession> signUpOwner(String email, String password) async {
    setupCalls++;
    if (ownerEmail.isNotEmpty) {
      throw const AdminException(
        AdminErrorType.alreadyExists,
        409,
        'An owner account already exists. Please sign in.',
      );
    }
    if (password.length < 10) {
      throw const AdminException(
        AdminErrorType.badInput,
        400,
        'Password must be at least 10 characters.',
      );
    }
    provisionOwner(email, password);
    return _mint(email);
  }

  @override
  Future<AdminMe> me(String token) async {
    final accepted = acceptedTokens;
    if (accepted != null && !accepted.contains(token)) {
      throw const AdminException(
        AdminErrorType.sessionExpired,
        401,
        'Session expired — sign in again.',
      );
    }
    return AdminMe(
      email: ownerEmail,
      expiresAt: 9999999999999,
      role: tokenRoles[token] ?? AdminRole.owner,
    );
  }

  @override
  Future<void> logout(String token) async {
    logoutCalls++;
    acceptedTokens?.remove(token);
    if (lastLogoutException != null) throw lastLogoutException!;
  }

  @override
  Future<AdminSession> changePassword(
    String token,
    String currentPassword,
    String newPassword,
  ) async {
    final accepted = acceptedTokens;
    if (accepted == null || !accepted.contains(token)) {
      throw const AdminException(
        AdminErrorType.sessionExpired,
        401,
        'Session expired — sign in again.',
      );
    }
    if (currentPassword != ownerPassword) {
      throw const AdminException(
        AdminErrorType.badCredentials,
        401,
        'Current password is incorrect.',
      );
    }
    if (newPassword.length < 10) {
      throw const AdminException(
        AdminErrorType.badInput,
        400,
        'New password must be at least 10 characters.',
      );
    }
    ownerPassword = newPassword;
    // Rotation: every old session dies, a fresh one comes back.
    acceptedTokens!.clear();
    return _mint(ownerEmail);
  }

  AdminSession _mint(String email) {
    final token = 'tok-${mintedTokens.length}-${DateTime.now().microsecondsSinceEpoch}';
    mintedTokens.add(token);
    acceptedTokens ??= {};
    acceptedTokens!.add(token);
    tokenRoles[token] =
        email == ownerEmail ? AdminRole.owner : AdminRole.admin;
    return AdminSession(token: token, email: email, expiresAt: 9999999999999);
  }

  // ── management twin (mirrors the Worker's v1.19 endpoints) ─────────────

  @override
  Future<AdminSettings> settings(String token) async {
    _requireSession(token);
    return settingsDoc;
  }

  @override
  Future<AdminSettings> updateSettings(
    String token, {
    bool? signupsEnabled,
    bool? maintenanceMode,
  }) async {
    _requireSession(token);
    _requireOwner(token);
    settingsDoc = AdminSettings(
      signupsEnabled: signupsEnabled ?? settingsDoc.signupsEnabled,
      maintenanceMode: maintenanceMode ?? settingsDoc.maintenanceMode,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      updatedBy: ownerEmail,
    );
    _audit('settings_updated');
    return settingsDoc;
  }

  @override
  Future<AdminUsersDoc> users(String token) async {
    _requireSession(token);
    return AdminUsersDoc(
      ownerEmail: ownerEmail.isEmpty ? null : ownerEmail,
      ownerCreatedAt: ownerEmail.isEmpty ? null : 1700000000000,
      admins: adminUsers.values.toList(),
    );
  }

  @override
  Future<AdminUser> addUser(String token, String email, String password) async {
    _requireSession(token);
    _requireOwner(token);
    if (adminUsers.values.any((u) => u.email == email) || email == ownerEmail) {
      throw const AdminException(
          AdminErrorType.alreadyExists, 409, 'An admin with this email already exists.');
    }
    if (password.length < 10) {
      throw const AdminException(
          AdminErrorType.badInput, 400, 'Password must be at least 10 characters.');
    }
    final user = AdminUser(
      id: 'id-${adminUsers.length + 1}',
      email: email,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      createdBy: ownerEmail,
    );
    adminUsers[user.id] = user;
    _audit('admin_created', target: email);
    return user;
  }

  @override
  Future<void> resetUserPassword(
      String token, String id, String newPassword) async {
    _requireSession(token);
    _requireOwner(token);
    if (adminUsers[id] == null) {
      throw const AdminException(AdminErrorType.notFound, 404, 'No such admin account.');
    }
    if (newPassword.length < 10) {
      throw const AdminException(
          AdminErrorType.badInput, 400, 'New password must be at least 10 characters.');
    }
    _audit('admin_password_reset', target: adminUsers[id]!.email);
  }

  @override
  Future<void> removeUser(String token, String id) async {
    _requireSession(token);
    _requireOwner(token);
    if (adminUsers.remove(id) == null) {
      throw const AdminException(AdminErrorType.notFound, 404, 'No such admin account.');
    }
    _audit('admin_removed', target: id);
  }

  @override
  Future<List<Announcement>> announcements(String token) async {
    _requireSession(token);
    return List.of(announcementList);
  }

  @override
  Future<Announcement> createAnnouncement(
      String token, String message, String level) async {
    _requireSession(token);
    if (message.trim().length < 3 || message.length > 500) {
      throw const AdminException(
          AdminErrorType.badInput, 400, 'Message must be 3-500 characters.');
    }
    if (announcementList.length >= 5) {
      throw const AdminException(
          AdminErrorType.alreadyExists, 409, 'At most 5 announcements can be stored.');
    }
    final a = Announcement(
      id: 'ann-${announcementList.length + 1}',
      message: message.trim(),
      level: level == 'warn' || level == 'critical' ? level : 'info',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      createdBy: ownerEmail,
    );
    announcementList.insert(0, a);
    _audit('announcement_created', target: a.id, detail: message);
    return a;
  }

  @override
  Future<void> deleteAnnouncement(String token, String id) async {
    _requireSession(token);
    announcementList.removeWhere((a) => a.id == id);
    _audit('announcement_deleted', target: id);
  }

  @override
  Future<List<AuditEntry>> audit(String token) async {
    _requireSession(token);
    return List.of(auditTrail);
  }

  @override
  Future<void> setAccountSuspended(
      String token, String uid, bool suspended) async {
    _requireSession(token);
    suspendedAccounts[uid] = suspended;
    _audit(suspended ? 'account_suspended' : 'account_unsuspended', target: uid);
  }

  @override
  Future<AccountDeleteResult> deleteAccount(
      String token, String uid, String confirmId) async {
    _requireSession(token);
    deleteAccountConfirmSent = confirmId;
    if (confirmId.toLowerCase() != uid.toLowerCase()) {
      throw AdminException(
        AdminErrorType.badInput, 400, 'Type "$uid" in the confirm field.',
      );
    }
    final result = AccountDeleteResult(
      id: uid,
      userRemoved: true,
      sessions: 2,
      refreshTokens: 1,
    );
    deletedAccounts[uid] = result;
    _audit('account_deleted', target: uid);
    return result;
  }
}

AdminOverview _overview({int scans = 0}) => AdminOverview(
      generatedAt: 1791144413801,
      totals: AdminTotals(
        accounts: 19,
        vaults: 10,
        scans: scans,
        verified: 0,
        scansToday: 0,
        scans7d: 0,
        scanningAccounts7d: 0,
      ),
      banks: const [],
      days: const [AdminDay(day: '2026-10-04', count: 0)],
      accounts: const [],
      recent: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdminController — sign in', () {
    test('signIn with good credentials persists the session and unlocks',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.restore();
      expect(controller.unlocked, false);

      final ok = await controller.signIn('Owner@Mahtem.APP', 'long-pass-1234');
      expect(ok, isTrue, reason: controller.error);
      expect(controller.unlocked, isTrue);
      expect(controller.overview, isNotNull);
      expect(controller.email, 'owner@mahtem.app');
      expect(controller.error, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.token'), isNotNull);
      expect(prefs.getString('mahtem.admin.email'), 'owner@mahtem.app');
    });

    test('signIn with a wrong password stays locked and does not persist',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.restore();
      final ok = await controller.signIn('owner@mahtem.app', 'wrong-password');
      expect(ok, isFalse);
      expect(controller.unlocked, false);
      expect(controller.error, contains('Wrong email or password'));
      expect(controller.overview, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.token'), isNull);
    });

    test('signIn validates the email shape locally (no network call)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.restore();

      expect(await controller.signIn('not-an-email', 'long-pass-1234'), isFalse);
      expect(controller.error, contains('valid email'));
      expect(await controller.signIn('', ''), isFalse);
      expect(api.overviewCalls, 0, reason: 'locally rejected input never hits the API');
    });

    test('signUpOwner creates the account on first run and unlocks', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.restore();
      final ok = await controller.signUpOwner('me@mahtem.app', 'first-password-1');
      expect(ok, isTrue, reason: controller.error);
      expect(controller.unlocked, isTrue);
      expect(controller.email, 'me@mahtem.app');
      expect(api.setupCalls, 1);
    });

    test('signUpOwner refuses short passwords locally', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      expect(await controller.signUpOwner('me@mahtem.app', 'short'), isFalse);
      expect(controller.error, contains('at least 10'));
      expect(api.setupCalls, 0);
    });
  });

  group('AdminController — session restore', () {
    test('restore() re-unlocks from a persisted session across reboots',
        () async {
      SharedPreferences.setMockInitialValues({
        'mahtem.admin.token': 'tok-existing-session-token-0001',
        'mahtem.admin.email': 'owner@mahtem.app',
      });
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      final restoring = controller.restore();
      expect(controller.unlocked, isNull);
      await restoring;

      expect(controller.unlocked, isTrue);
      expect(controller.overview, isNotNull);
      expect(controller.email, 'owner@mahtem.app');
      expect(api.overviewCalls, 1);
    });

    test('restore() clears a session the API no longer accepts', () async {
      SharedPreferences.setMockInitialValues({
        'mahtem.admin.token': 'tok-revoked-elsewhere',
        'mahtem.admin.email': 'owner@mahtem.app',
      });
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.restore();

      expect(controller.unlocked, false);
      expect(controller.overview, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.token'), isNull);
      expect(prefs.getString('mahtem.admin.email'), isNull);
    });

    test('restore() keeps the session on a network blip and offers retry',
        () async {
      SharedPreferences.setMockInitialValues({
        'mahtem.admin.token': 'tok-existing-session-token-0001',
      });
      final api = FakeAdminApi()
        ..provisionOwner('owner@mahtem.app', 'long-pass-1234')
        ..throwOnOverview = const AdminException(
          AdminErrorType.network,
          0,
          "Can't reach the Mahtem API.",
        );
      final controller = AdminController(api: api);

      await controller.restore();

      // A network failure must NOT log the owner out — only a dead session does.
      expect(controller.unlocked, isNull, reason: 'boot restore inconclusive');
      expect(controller.restoreFailed, isTrue);
      expect(controller.error, contains("Can't reach"));

      // Network recovered → retry succeeds → dashboard.
      api.throwOnOverview = null;
      await controller.retryRestore();
      expect(controller.unlocked, isTrue);
      expect(controller.restoreFailed, isFalse);
      expect(controller.overview, isNotNull);
    });

    test('restore() retires a legacy v1.0.0 admin key', () async {
      SharedPreferences.setMockInitialValues({
        'mahtem.admin.key': 'k' * 32,
      });
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.restore();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.key'), isNull,
          reason: 'the static admin key is retired');
      expect(controller.unlocked, false,
          reason: 'a key alone is no longer a session');
    });
  });

  group('AdminController — lifecycle', () {
    test('refresh() keeps the last snapshot on failure and reports the error',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.signIn('owner@mahtem.app', 'long-pass-1234');
      final before = controller.overview;

      api.throwOnOverview = const AdminException(
        AdminErrorType.server,
        502,
        'Mahtem API error (HTTP 502).',
      );
      final ok = await controller.refresh(silent: true);

      expect(ok, isFalse);
      expect(controller.error, contains('502'));
      expect(controller.overview, same(before), reason: 'snapshot is kept');
      expect(controller.unlocked, isTrue, reason: 'server errors never log out');
    });

    test('changePassword() rotates the session and keeps the owner signed in',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.signIn('owner@mahtem.app', 'long-pass-1234');
      final prefs = await SharedPreferences.getInstance();
      final oldToken = prefs.getString('mahtem.admin.token');

      final ok = await controller.changePassword('long-pass-1234', 'new-pass-9876');
      expect(ok, isTrue, reason: controller.error);

      final newToken = prefs.getString('mahtem.admin.token');
      expect(newToken, isNot(oldToken), reason: 'server rotated the session');
      expect(controller.unlocked, isTrue);

      // Old token is dead everywhere; new one still works.
      api.acceptedTokens!.remove(oldToken);
      final refreshed = await controller.refresh(silent: true);
      expect(refreshed, isTrue);
    });

    test('changePassword() reports a wrong current password', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.signIn('owner@mahtem.app', 'long-pass-1234');
      final ok = await controller.changePassword('not-my-password', 'new-pass-9876');
      expect(ok, isFalse);
      expect(controller.error, contains('incorrect'));
      expect(controller.unlocked, isTrue, reason: 'failed change never signs out');
    });

    test('signOut() revokes the session and forgets everything', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.signIn('owner@mahtem.app', 'long-pass-1234');
      await controller.signOut();

      expect(controller.unlocked, false);
      expect(controller.overview, isNull);
      expect(controller.email, isNull);
      expect(controller.error, isNull);
      expect(api.logoutCalls, 1, reason: 'server-side revocation attempted');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.token'), isNull);
      expect(prefs.getString('mahtem.admin.email'), isNull);
    });

    test('setAutoRefresh persists the preference', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);

      await controller.signIn('owner@mahtem.app', 'long-pass-1234');
      await controller.setAutoRefresh(false);
      expect(controller.autoRefresh, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('mahtem.admin.autorefresh'), isFalse);
    });

    test('accountDetail() caches per account within the TTL window', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      final first = await controller.accountDetail('89da157c');
      final second = await controller.accountDetail('89da157c');
      expect(api.detailCalls, 1, reason: 'second call hits the 60s cache');
      expect(first.id, '89da157c');
      expect(second.id, first.id);

      await controller.accountDetail('9dbba391');
      expect(api.detailCalls, 2, reason: 'a different account is a fresh fetch');

      await controller.signOut();
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');
      await controller.accountDetail('89da157c');
      expect(api.detailCalls, 3,
          reason: 'sign-out/sign-in clears the drill-down cache');
    });
  });

  group('AdminController — management (v1.19 console)', () {
    test('loadManageData populates settings, users, announcements and audit',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      expect(await controller.loadManageData(), isTrue);
      expect(controller.manageError, isNull);
      expect(controller.settings!.signupsEnabled, isTrue);
      expect(controller.settings!.maintenanceMode, isFalse);
      expect(controller.users!.ownerEmail, 'owner@mahtem.app');
      expect(controller.announcements, isEmpty);
      expect(controller.auditEntries, isNotEmpty,
          reason: 'signing in audited a login');

      // The lazy loader is a no-op once loaded.
      await controller.loadManageDataIfStale();
    });

    test('updateSettings flips switches, persists server-side and audits',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      expect(
        await controller.updateSettings(maintenanceMode: true),
        isTrue,
        reason: controller.manageError,
      );
      expect(controller.settings!.maintenanceMode, isTrue);
      expect(controller.settings!.signupsEnabled, isTrue,
          reason: 'untouched switches keep their value');
      expect(controller.settings!.updatedBy, 'owner@mahtem.app');
      expect(
        controller.auditEntries!.any((e) => e.action == 'settings_updated'),
        isTrue,
        reason: 'the action lands in the audit trail',
      );

      expect(await controller.updateSettings(signupsEnabled: false), isTrue);
      expect(controller.settings!.signupsEnabled, isFalse);
      expect(controller.settings!.maintenanceMode, isTrue);
    });

    test('admin-user lifecycle: add, reset, remove — and the audit follows',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      expect(
        await controller.addAdminUser('helper@mahtem.app', 'helper-pass-123'),
        isTrue,
        reason: controller.manageError,
      );
      expect(
        controller.users!.admins.map((u) => u.email).toList(),
        contains('helper@mahtem.app'),
      );

      final id = controller.users!.admins
          .firstWhere((u) => u.email == 'helper@mahtem.app')
          .id;
      expect(
        await controller.resetAdminPassword(id, 'fresh-pass-4567'),
        isTrue,
        reason: controller.manageError,
      );
      expect(await controller.removeAdminUser(id), isTrue);
      expect(controller.users!.admins, isEmpty,
          reason: 'the list reloaded without the removed admin');
      expect(controller.auditEntries!.any((e) => e.action == 'admin_removed'),
          isTrue);
    });

    test('announcements: create, list, delete', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      expect(
        await controller.createAnnouncement(
            'Telebirr receipts may be slow tonight', 'warn'),
        isTrue,
        reason: controller.manageError,
      );
      expect(controller.announcements, hasLength(1));
      expect(controller.announcements!.first.isWarn, isTrue);
      expect(controller.announcements!.first.createdBy, 'owner@mahtem.app');

      expect(
        await controller.deleteAnnouncement(controller.announcements!.first.id),
        isTrue,
      );
      expect(controller.announcements, isEmpty);
    });

    test('suspend toggles the flag, refreshes the overview and clears the cache',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      final overviewCallsBefore = api.overviewCalls;
      await controller.accountDetail('89da157c'); // warm the detail cache

      expect(
        await controller.setAccountSuspended('89da157c', true),
        isTrue,
        reason: controller.manageError,
      );
      expect(api.suspendedAccounts['89da157c'], isTrue);
      expect(api.overviewCalls, greaterThan(overviewCallsBefore),
          reason: 'the overview re-polls after a moderation action');
      expect(
        await controller.accountDetail('89da157c'),
        isA<AdminAccountDetail>(),
      );
      expect(api.detailCalls, 2,
          reason: 'the suspend cleared the 60s detail cache');

      expect(await controller.setAccountSuspended('89da157c', false), isTrue);
      expect(api.suspendedAccounts['89da157c'], isFalse);
    });

    test('deleteAccount forwards the typed confirm id and reports the wipe',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      final result =
          await controller.deleteAccount('89da157c', '89DA157C');
      expect(result, isNotNull);
      expect(result!.userRemoved, isTrue);
      expect(result.sessions, 2);
      expect(api.deleteAccountConfirmSent, '89DA157C',
          reason: 'the typed confirm travels to the Worker verbatim');
      expect(api.deletedAccounts.containsKey('89da157c'), isTrue);
      expect(controller.auditEntries!.any((e) => e.action == 'account_deleted'),
          isTrue);
    });

    test('a failed management action surfaces manageError and never throws',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');

      final ok = await controller.deleteAccount('89da157c', 'wrong-id');
      expect(ok, isNull);
      expect(controller.manageError, contains('confirm'));
      expect(controller.manageBusy, isFalse);
    });

    test('an admin session learns its role and owner-only actions fail with 403',
        () async {
      SharedPreferences.setMockInitialValues({
        'mahtem.admin.token': 'tok-existing-session-token-0001',
        'mahtem.admin.email': 'helper@mahtem.app',
      });
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      api.provisionAdmin('helper@mahtem.app', 'id-9');
      api.tokenRoles['tok-existing-session-token-0001'] = AdminRole.admin;

      final controller = AdminController(api: api);
      await controller.restore();

      expect(controller.unlocked, isTrue);
      expect(controller.role, AdminRole.admin, reason: 'restore() resolved the role via me()');
      expect(controller.isOwner, isFalse);

      final ok = await controller.updateSettings(maintenanceMode: true);
      expect(ok, isFalse);
      expect(controller.manageError, contains('owner'));
    });

    test('signOut clears the management caches too', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi()..provisionOwner('owner@mahtem.app', 'long-pass-1234');
      final controller = AdminController(api: api);
      await controller.signIn('owner@mahtem.app', 'long-pass-1234');
      await controller.loadManageData();
      expect(controller.settings, isNotNull);

      await controller.signOut();
      expect(controller.settings, isNull);
      expect(controller.users, isNull);
      expect(controller.announcements, isNull);
      expect(controller.auditEntries, isNull);
      expect(controller.role, isNull);
    });
  });
}
