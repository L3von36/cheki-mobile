import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem_admin/admin_api.dart';
import 'package:mahtem_admin/admin_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory twin of the Worker admin API for controller tests.
class FakeAdminApi implements AdminApiClient {
  FakeAdminApi({Set<String>? acceptedKeys})
      : acceptedKeys = acceptedKeys ?? {'k' * 32};

  final Set<String> acceptedKeys;
  int calls = 0;
  Object? throwOnCall;

  @override
  Future<AdminOverview> overview(String key) async {
    calls++;
    if (throwOnCall != null) throw throwOnCall!;
    if (!acceptedKeys.contains(key)) {
      throw const AdminException(
        AdminErrorType.badKey,
        401,
        'Invalid admin key. Check the ADMIN_KEY and try again.',
      );
    }
    return _overview();
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

  group('AdminController', () {
    test('unlock with a good key persists it and exposes the overview', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.restore();
      expect(controller.unlocked, false);

      final ok = await controller.unlock('k' * 32);
      expect(ok, isTrue, reason: controller.error);
      expect(controller.unlocked, isTrue);
      expect(controller.overview, isNotNull);
      expect(controller.error, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.key'), 'k' * 32);
    });

    test('unlock with a bad key stays locked and does not persist', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.restore();
      final ok = await controller.unlock('bad-key-value-1234567890');
      expect(ok, isFalse);
      expect(controller.unlocked, false);
      expect(controller.error, contains('Invalid admin key'));
      expect(controller.overview, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.key'), isNull);
    });

    test('unlock validates the key shape locally', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.restore();

      expect(await controller.unlock(''), isFalse);
      expect(controller.error, contains('Enter the admin key'));
      expect(await controller.unlock('short'), isFalse);
      expect(controller.error, contains('too short'));
      expect(api.calls, 0, reason: 'no network call for locally rejected keys');
    });

    test('restore() re-unlocks from a persisted key across reboots', () async {
      SharedPreferences.setMockInitialValues({'mahtem.admin.key': 'k' * 32});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      // unlocked == null during the silent restore…
      final restoring = controller.restore();
      expect(controller.unlocked, isNull);
      await restoring;

      expect(controller.unlocked, isTrue);
      expect(controller.overview, isNotNull);
      expect(api.calls, 1);
    });

    test('restore() clears a key the API no longer accepts', () async {
      SharedPreferences.setMockInitialValues({'mahtem.admin.key': 'stale-key-value-123456'});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.restore();

      expect(controller.unlocked, false);
      expect(controller.overview, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.key'), isNull);
    });

    test('restore() keeps the session on a network blip and offers retry',
        () async {
      SharedPreferences.setMockInitialValues({'mahtem.admin.key': 'k' * 32});
      final api = FakeAdminApi()
        ..throwOnCall = const AdminException(
          AdminErrorType.network,
          0,
          "Can't reach the Mahtem API.",
        );
      final controller = AdminController(api: api);

      await controller.restore();

      // A network failure must NOT log the owner out — only a bad key does.
      expect(controller.unlocked, isNull, reason: 'boot restore inconclusive');
      expect(controller.restoreFailed, isTrue);
      expect(controller.error, contains("Can't reach"));

      // Network recovered → retry succeeds → dashboard.
      api.throwOnCall = null;
      await controller.retryRestore();
      expect(controller.unlocked, isTrue);
      expect(controller.restoreFailed, isFalse);
      expect(controller.overview, isNotNull);
    });

    test('refresh() keeps the last snapshot on failure and reports the error',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.unlock('k' * 32);
      final before = controller.overview;

      api.throwOnCall = const AdminException(
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

    test('signOut() forgets everything', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.unlock('k' * 32);
      await controller.signOut();

      expect(controller.unlocked, false);
      expect(controller.overview, isNull);
      expect(controller.error, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mahtem.admin.key'), isNull);
    });

    test('setAutoRefresh persists the preference', () async {
      SharedPreferences.setMockInitialValues({});
      final api = FakeAdminApi();
      final controller = AdminController(api: api);

      await controller.unlock('k' * 32);
      await controller.setAutoRefresh(false);
      expect(controller.autoRefresh, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('mahtem.admin.autorefresh'), isFalse);
    });
  });
}
