import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/crash_reporting.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  // Loaded once here so ThemeController and LocaleController can restore
  // their persisted choices synchronously. If the plugin is unavailable
  // the app still boots — choices just don't persist.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    prefs = null;
  }
  // Sentry wraps the boot only when a DSN was baked in at build time
  // (see lib/core/crash_reporting.dart) — otherwise this is a plain
  // runApp and the app behaves exactly as before.
  await runWithCrashReporting(
    appRunner: () => runApp(MahtemApp(prefs: prefs)),
  );
}
