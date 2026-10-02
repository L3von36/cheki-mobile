import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahtem/core/error_safety_net.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiagnosticsLog', () {
    test('starts empty, copyText says nothing recorded', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final log = DiagnosticsLog(prefs: prefs);
      await log.restore(prefs);

      expect(log.count, 0);
      expect(log.copyText(), contains('No problems recorded.'));
    });

    test('record() adds entries with message and stack lines', () {
      final log = DiagnosticsLog();
      log.record(StateError('boom'), StackTrace.current);

      expect(log.count, 1);
      final entry = log.entries.single;
      expect(entry.message, contains('boom'));
      expect(entry.stack, isNotEmpty);
      expect(entry.timeIso, isNotEmpty);
    });

    test('caps at 30 entries, dropping the oldest', () {
      final log = DiagnosticsLog();
      for (var i = 0; i < 35; i++) {
        log.record(StateError('error-$i'), null);
      }

      expect(log.count, kDiagnosticsCapacity);
      expect(log.entries.first.message, contains('error-5'));
      expect(log.entries.last.message, contains('error-34'));
    });

    test('truncates pathological messages to 300 chars', () {
      final log = DiagnosticsLog();
      log.record(StateError('x' * 1000), null);

      expect(log.entries.single.message.length, lessThanOrEqualTo(301));
      expect(log.entries.single.message.endsWith('…'), isTrue);
    });

    test('persists to SharedPreferences and restores', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final writer = DiagnosticsLog(prefs: prefs);
      writer.record(StateError('persisted-problem'), StackTrace.current);

      final reader = DiagnosticsLog(prefs: prefs);
      await reader.restore(prefs);

      expect(reader.count, 1);
      expect(reader.entries.single.message, contains('persisted-problem'));
    });

    test('restore() drops corrupt payloads instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        kDiagnosticsLogKey: 'not-json-at-all{',
      });
      final prefs = await SharedPreferences.getInstance();
      final log = DiagnosticsLog(prefs: prefs);
      await log.restore(prefs);

      expect(log.count, 0);
    });

    test('restore() caps an oversized persisted trail', () async {
      final oversized = List.generate(
        50,
        (i) => '{"t":"2026-01-0${i % 9}T10:00:00Z","m":"old-$i","s":""}',
      ).join(',');
      SharedPreferences.setMockInitialValues({
        kDiagnosticsLogKey: '[$oversized]',
      });
      final prefs = await SharedPreferences.getInstance();
      final log = DiagnosticsLog(prefs: prefs);
      await log.restore(prefs);

      expect(log.count, kDiagnosticsCapacity);
      expect(log.entries.first.message, contains('old-'));
    });

    test('copyText lists every recorded entry', () {
      final log = DiagnosticsLog();
      log.record(StateError('first'), null);
      log.record(ArgumentError('second'), null);

      final text = log.copyText();
      expect(text, contains('first'));
      expect(text, contains('second'));
      expect(text, contains('2 recorded problems'));
    });

    test('record() survives a throwing persistence layer', () {
      // Null prefs → _persist() is a no-op; the in-memory trail must
      // still record. (The catch-all inside record() guards the rest.)
      final log = DiagnosticsLog();
      expect(() => log.record('anything', null), returnsNormally);
      expect(log.count, 1);
    });
  });

  group('installErrorSafetyNet', () {
    late DiagnosticsLog log;
    FlutterExceptionHandler? originalFlutterOnError;
    bool Function(Object, StackTrace)? originalDispatcherOnError;

    setUp(() {
      log = DiagnosticsLog();
      originalFlutterOnError = FlutterError.onError;
      originalDispatcherOnError = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = originalFlutterOnError;
      PlatformDispatcher.instance.onError = originalDispatcherOnError;
      localizedScreenErrorResolver = null;
    });

    test('captures framework errors into the log', () {
      final reset = installErrorSafetyNet(log: log);
      try {
        FlutterError.onError!(
          FlutterErrorDetails(
            exception: StateError('widget-explosion'),
            library: 'test',
          ),
        );

        expect(log.count, 1);
        expect(log.entries.single.message, contains('widget-explosion'));
      } finally {
        reset();
      }
    });

    test('captures uncaught async errors and marks them handled', () {
      final reset = installErrorSafetyNet(log: log);
      try {
        final handled = PlatformDispatcher.instance.onError!(
          Exception('uncaught-async'),
          StackTrace.current,
        );

        expect(handled, isTrue);
        expect(log.count, 1);
        expect(log.entries.single.message, contains('uncaught-async'));
      } finally {
        reset();
      }
    });

    test('reset() restores the previous handlers', () {
      void sentinel(FlutterErrorDetails details) {}
      FlutterError.onError = sentinel;
      final reset = installErrorSafetyNet(log: log);
      reset();

      expect(FlutterError.onError, same(sentinel));
      expect(PlatformDispatcher.instance.onError,
          same(originalDispatcherOnError));
    });
  });

  group('buildFriendlyErrorWidget', () {
    testWidgets('uses the localized resolver message when set',
        (tester) async {
      localizedScreenErrorResolver = () => 'ችግር በገጠመ';
      addTearDown(() => localizedScreenErrorResolver = null);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => buildFriendlyErrorWidget(
            FlutterErrorDetails(exception: StateError('x'), library: 'test'),
          ),
        ),
      ));

      expect(find.text('ችግር በገጠመ'), findsOneWidget);
    });

    testWidgets('falls back to the neutral English message without resolver',
        (tester) async {
      localizedScreenErrorResolver = null;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => buildFriendlyErrorWidget(
            FlutterErrorDetails(exception: StateError('x'), library: 'test'),
          ),
        ),
      ));

      expect(find.text(kFallbackScreenError), findsOneWidget);
    });

    testWidgets('a throwing resolver degrades to the fallback, never throws',
        (tester) async {
      localizedScreenErrorResolver = () => throw StateError('resolver-broke');
      addTearDown(() => localizedScreenErrorResolver = null);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => buildFriendlyErrorWidget(
            FlutterErrorDetails(exception: StateError('x'), library: 'test'),
          ),
        ),
      ));

      expect(find.text(kFallbackScreenError), findsOneWidget);
    });
  });
}
