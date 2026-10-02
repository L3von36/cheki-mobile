import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/crash_reporting.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  // Crash reporting must be invisible until a DSN is baked in at build
  // time — these tests pin the opt-in gate and the privacy-first profile.

  group('sentryDsnLooksValid', () {
    test('accepts a real-looking https DSN', () {
      expect(
        sentryDsnLooksValid(
          'https://abc123def456@o123456.ingest.sentry.io/7654321',
        ),
        isTrue,
      );
      expect(
        sentryDsnLooksValid(
          '  https://abc123def456@o123456.ingest.sentry.io/7654321  ',
        ),
        isTrue,
        reason: 'surrounding whitespace is tolerated',
      );
    });

    test('rejects empty, placeholder and malformed values', () {
      const bad = <String>[
        '',
        '   ',
        'placeholder',
        'your-dsn-here',
        'http://key@host/1', // not https — plain-text keys never count
        'https://key@host', // no project id
        'https://key@host/', // empty project id
      ];
      for (final dsn in bad) {
        expect(sentryDsnLooksValid(dsn), isFalse, reason: '"$dsn" must fail');
      }
    });
  });

  group('configureSentryOptions', () {
    test('locks in the privacy-first profile', () {
      final options = SentryOptions();
      configureSentryOptions(
        options,
        dsn: 'https://k@o1.ingest.sentry.io/42',
        release: 'app.mahtem.mobile@1.8.0+28',
        dist: '28',
      );
      expect(options.dsn, 'https://k@o1.ingest.sentry.io/42');
      expect(options.release, 'app.mahtem.mobile@1.8.0+28');
      expect(options.dist, '28');
      expect(options.environment, 'production');
      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.attachViewHierarchy, isFalse);
      expect(options.tracesSampleRate, isNull);
    });
  });

  group('runWithCrashReporting', () {
    test('with no usable DSN it boots the app unchanged', () async {
      var ran = false;
      await runWithCrashReporting(
        dsn: '',
        appRunner: () async => ran = true,
      );
      expect(ran, isTrue);

      var ranPlaceholder = false;
      await runWithCrashReporting(
        dsn: 'placeholder-dsn',
        appRunner: () async => ranPlaceholder = true,
      );
      expect(ranPlaceholder, isTrue);
    });
  });
}
