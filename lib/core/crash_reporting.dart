/// Crash reporting (v1.8.0) — opt-in Sentry wiring.
///
/// The DSN arrives at BUILD time through `--dart-define=SENTRY_DSN=…`
/// (the release workflow reads the `SENTRY_DSN` repo secret and passes
/// it to `flutter build`). With no DSN configured the app boots exactly
/// as before: Sentry is never initialized, nothing touches the network,
/// zero overhead. Crashlytics was rejected because it hard-requires a
/// Firebase project (`google-services.json` + console access); Sentry
/// stays buildable with no external account at all.
library;

import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// DSN baked in at build time — empty in every build without the secret.
const String kSentryDsn = String.fromEnvironment('SENTRY_DSN');

/// A DSN is usable only when it looks like
/// `https://<public-key>@<host>/<project-id>` — this keeps placeholder
/// strings and typos from silently initializing a broken SDK.
bool sentryDsnLooksValid(String dsn) {
  final d = dsn.trim();
  return d.startsWith('https://') &&
      RegExp(r'^https://[^@\s]+@[^@\s]+/\S+$').hasMatch(d);
}

/// The `release` string Sentry groups events under, in the same shape the
/// native Android SDK uses (`packageName@version+build`) so Dart and
/// native events line up in one release. Falls back to a stable name when
/// PackageInfo is unavailable (never fails the boot because of this).
Future<(String release, String? dist)> loadAppIdentity() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return (
      '${info.packageName}@${info.version}+${info.buildNumber}',
      info.buildNumber,
    );
  } catch (_) {
    return ('mahtem@unknown', null);
  }
}

/// Applies the shared, privacy-first option profile. Pure — unit-tested.
///
/// Error events only: no personally identifiable data, no screenshots, no
/// view hierarchies, no performance-tracing network chatter. Session
/// tracking stays on (default) so Sentry's release health shows adopters.
/// (Screenshot / view-hierarchy attachment are Flutter-level options and
/// default to false — pinned here so a future SDK default flip can't
/// silently change what Mahtem sends.)
void configureSentryOptions(
  SentryFlutterOptions options, {
  required String dsn,
  required String release,
  String? dist,
  String environment = 'production',
}) {
  options.dsn = dsn;
  options.release = release;
  options.dist = dist;
  options.environment = environment;
  options.sendDefaultPii = false;
  options.attachScreenshot = false;
  options.attachViewHierarchy = false;
  options.tracesSampleRate = null;
}

/// Boots [appRunner] under Sentry when a DSN was baked in at build time;
/// otherwise this is a straight `appRunner()` call.
///
/// Every failure inside the wrapper degrades to a plain boot — crash
/// reporting must never keep the app from starting.
Future<void> runWithCrashReporting({
  required FutureOr<void> Function() appRunner,
  String dsn = kSentryDsn,
}) async {
  if (!sentryDsnLooksValid(dsn)) {
    await appRunner();
    return;
  }
  try {
    await SentryFlutter.init(
      (options) async {
        final (release, dist) = await loadAppIdentity();
        configureSentryOptions(options, dsn: dsn, release: release, dist: dist);
      },
      appRunner: appRunner,
    );
  } catch (_) {
    await appRunner();
  }
}
