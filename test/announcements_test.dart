import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mahtem/core/cloud/cloud_api.dart';
import 'package:mahtem/core/licensing/license_store.dart';
import 'package:mahtem/state/cloud_controller.dart';
import 'package:mahtem/state/license_controller.dart';
import 'package:mahtem/state/locale_controller.dart';
import 'package:mahtem/state/theme_controller.dart';
import 'package:mahtem/state/verify_controller.dart';
import 'package:mahtem/ui/screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner broadcasts from the admin console surface on the Verify tab:
/// the Worker serves active announcements at /v1/announcements, the
/// CloudController owns the latest fetch, and HomeScreen renders a
/// dismissible, level-colored banner — everything else stays frozen.

const _payload = '''
{"announcements": [
  {"id": "a1", "message": "Pro sale this Tuesday", "level": "info", "createdAt": 1791200000000},
  {"id": "a2", "message": "Telebirr checks are slow", "level": "warn", "createdAt": 1791200100000},
  {"id": "a3", "message": "Data is back", "level": "info", "createdAt": 1791100000000},
  "garbage"
]}
''';

MockClient _mockOk() => MockClient((request) async {
      expect(request.url.path, '/v1/announcements');
      expect(request.headers['X-Mahtem-Client'], 'mahtem-android');
      return http.Response(_payload, 200);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fetchAnnouncements parses the public feed, skipping corrupt rows',
      () async {
    final api = CloudApi(client: _mockOk(), baseUrl: 'https://x.test');
    final list = await api.fetchAnnouncements();
    expect(list.length, 3);
    expect(list.any((a) => a.isWarn), isTrue);
    expect(list.map((a) => a.id), containsAll(['a1', 'a2', 'a3']));
  });

  test('refreshAnnouncements sorts newest-first; server list is authoritative',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = CloudController(
      api: CloudApi(client: _mockOk(), baseUrl: 'https://x.test'),
      prefs: prefs,
    );

    await controller.refreshAnnouncements();
    expect(
      controller.announcements.map((a) => a.id).toList(),
      ['a2', 'a1', 'a3'],
    );
  });

  test('a failed fetch never clears the last good list', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var n = 0;
    final controller = CloudController(
      api: CloudApi(
        client: MockClient((_) async {
          n++;
          if (n == 1) return http.Response(_payload, 200);
          throw Exception('offline');
        }),
        baseUrl: 'https://x.test',
      ),
      prefs: prefs,
    );

    await controller.refreshAnnouncements();
    expect(controller.announcements, isNotEmpty);
    await controller.refreshAnnouncements();
    expect(controller.announcements, isNotEmpty,
        reason: 'authoritative list unavailable — last good one stays');
  });

  test('refreshAnnouncements is a no-op in the disabled (prefs-less) state',
      () async {
    final controller = CloudController(); // prefs: null — tests' neutral
    await controller.refreshAnnouncements();
    expect(controller.announcements, isEmpty);
  });

  testWidgets('HomeScreen shows the newest banner and dismiss hides it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cloud = CloudController(
      api: CloudApi(client: _mockOk(), baseUrl: 'https://x.test'),
      prefs: prefs,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<VerifyController>.value(value: VerifyController()),
          ChangeNotifierProvider<CloudController>.value(value: cloud),
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
        child: const MaterialApp(home: HomeScreen()),
      ),
    );

    // initState fired the fetch — give the MockClient one round.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(cloud.announcements, isNotEmpty);
    // Newest first → the warn banner leads.
    expect(find.text('Telebirr checks are slow'), findsOneWidget);
    expect(find.text('Pro sale this Tuesday'), findsNothing,
        reason: 'only the highest-priority banner slot is taken');

    // Dismiss: the slot moves to the next announcement behind it.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Telebirr checks are slow'), findsNothing);
    expect(find.text('Pro sale this Tuesday'), findsOneWidget);
  });
}
