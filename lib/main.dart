import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/crash_reporting.dart';
import 'core/error_safety_net.dart';

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
  // ── error safety net (v1.12.1) ──────────────────────────────────────
  // The local diagnostics trail always runs (Settings → Report a problem
  // reads it back). DiagnosticsLog.I is THE shared instance: the safety
  // net, the error widget and the auth account store all record into it.
  // The fallback handlers install ONLY when Sentry is NOT configured:
  // with a DSN baked in, SentryFlutter.init installs its own handlers
  // and double-reporting through two channels would only muddy the trail.
  final diagnostics = DiagnosticsLog.I;
  await diagnostics.restore(prefs);
  try {
    final info = await PackageInfo.fromPlatform();
    diagnostics.setAppVersion('${info.version}+${info.buildNumber}');
  } catch (_) {
    // Header just reads "unknown" — never block boot for a label.
  }
  if (!sentryDsnLooksValid(kSentryDsn)) {
    installErrorSafetyNet(log: diagnostics);
  }
  // Release builds get the friendly error card instead of Flutter's grey
  // developer box; debug keeps the verbose box for development.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) {
      diagnostics.record(details.exception, details.stack);
      return buildFriendlyErrorWidget(details);
    };
  }

  // Sentry wraps the boot only when a DSN was baked in at build time
  // (see lib/core/crash_reporting.dart) — otherwise this is a plain
  // runApp and the app behaves exactly as before.
  await runWithCrashReporting(
    appRunner: () => runApp(MahtemApp(prefs: prefs)),
  );
}
