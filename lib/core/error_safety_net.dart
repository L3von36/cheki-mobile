/// Global error safety net (v1.12.1).
///
/// Sentry (v1.8.0) reports crashes ONLY when a build-time DSN exists —
/// and most current builds ship without one. Until then this module is
/// the last line of defence for everything Sentry would have caught:
///
///   * [ErrorSafetyNet.install] — fallback handlers for framework errors
///     (`FlutterError.onError`) and uncaught async/platform errors
///     (`PlatformDispatcher.instance.onError`) that record each event in
///     the on-device [DiagnosticsLog] instead of vanishing silently.
///   * [DiagnosticsLog] — a small, LOCAL-ONLY ring buffer (30 entries)
///     persisted to SharedPreferences so a user who reports "the app did
///     something weird" can copy the trail out of Settings. Nothing is
///     ever uploaded from here; sharing happens only when the user
///     explicitly taps copy.
///   * [buildFriendlyErrorWidget] — the release-mode replacement for
///     Flutter's grey developer error box: a calm, localized
///     "something went wrong here" card that can never itself throw.
///
/// When a Sentry DSN IS present, [ErrorSafetyNet.install] is skipped
/// entirely — Sentry installs its own handlers and double-reporting the
/// same error through two channels would only confuse the trail.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key holding the persisted diagnostics trail
/// (a JSON list of small {t, m, s} objects).
const String kDiagnosticsLogKey = 'diag.error_log';

/// Maximum number of error entries kept (newest last, oldest dropped).
const int kDiagnosticsCapacity = 30;

/// Neutral English fallback used when no localized resolver is reachable.
const String kFallbackScreenError =
    'Something went wrong displaying this part. Go back and try again.';

/// One recorded problem: when it happened, what the error said (truncated
/// — unexpected errors are framework/exception text, but the cap keeps a
/// pathological message from bloating the log) and the first stack lines
/// that point at our code.
class DiagnosticEntry {
  final String timeIso;
  final String message;
  final String stack;

  const DiagnosticEntry({
    required this.timeIso,
    required this.message,
    required this.stack,
  });

  Map<String, String> toJson() => {'t': timeIso, 'm': message, 's': stack};

  static DiagnosticEntry fromJson(Map<dynamic, dynamic> json) =>
      DiagnosticEntry(
        timeIso: json['t'] as String? ?? '',
        message: json['m'] as String? ?? '',
        stack: json['s'] as String? ?? '',
      );
}

/// On-device, capped, privacy-first error trail.
///
/// Every write is fire-and-forget: persistence failures are swallowed —
/// a diagnostics log must never cause the very crash it is recording.
class DiagnosticsLog {
  DiagnosticsLog({SharedPreferences? prefs, this.capacity = kDiagnosticsCapacity})
      : _prefs = prefs;

  static final DiagnosticsLog I = DiagnosticsLog();

  final SharedPreferences? _prefs;
  final int capacity;

  final List<DiagnosticEntry> _entries = [];
  String? _appVersion;

  /// Header label for [copyText] — set from `main()` once PackageInfo is
  /// available; falls back to a stable placeholder.
  void setAppVersion(String version) => _appVersion = version;

  String get _versionLabel =>
      (_appVersion == null || _appVersion!.isEmpty) ? 'unknown' : _appVersion!;

  /// Newest entry last; oldest entries are dropped first.
  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  int get count => _entries.length;

  /// Loads the persisted trail. Safe to call more than once; only the
  /// first call restores.
  Future<void> restore(SharedPreferences? prefs) async {
    final store = prefs ?? _prefs;
    if (store == null) return;
    try {
      final raw = store.getString(kDiagnosticsLogKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(list
            .whereType<Map<dynamic, dynamic>>()
            .map(DiagnosticEntry.fromJson)
            .where((e) => e.message.isNotEmpty));
      while (_entries.length > capacity) {
        _entries.removeAt(0);
      }
    } catch (_) {
      // A corrupt trail must never break boot — start clean.
      _entries.clear();
    }
  }

  /// Records an unexpected error. Never throws, never awaits.
  void record(Object? error, StackTrace? stack) {
    try {
      _entries.add(DiagnosticEntry(
        timeIso: DateTime.now().toIso8601String(),
        message: _truncate(error?.toString() ?? 'Unknown error', 300),
        stack: _truncate(_firstStackLines(stack, 5), 600),
      ));
      while (_entries.length > capacity) {
        _entries.removeAt(0);
      }
      _persist();
    } catch (_) {
      // Recording must never throw — not even out of the catch block.
    }
  }

  /// Drops every recorded entry (tests; future "clear trail" action).
  /// Persists the empty trail when a store is attached.
  void clear() {
    try {
      _entries.clear();
      _persist();
    } catch (_) {
      // Never throw from a diagnostics housekeeping call.
    }
  }

  /// Multi-line human-readable dump for the Settings "copy" button.
  String copyText() {
    if (_entries.isEmpty) {
      return 'Mahtem $_versionLabel\nNo problems recorded.';
    }
    final buffer = StringBuffer('Mahtem $_versionLabel — '
        '${_entries.length} '
        'recorded problem${_entries.length == 1 ? '' : 's'} (newest last)\n');
    for (final e in _entries) {
      buffer
        ..writeln()
        ..writeln('— ${e.timeIso}')
        ..writeln(e.message);
      if (e.stack.isNotEmpty) buffer.writeln(e.stack);
    }
    return buffer.toString();
  }

  void _persist() {
    final store = _prefs;
    if (store == null) return;
    try {
      store.setString(
        kDiagnosticsLogKey,
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Storage full / locked — the in-memory trail still works.
    }
  }

  static String _truncate(String text, int max) =>
      text.length <= max ? text : '${text.substring(0, max)}…';

  /// First [lines] meaningful stack lines — enough to locate the frame
  /// in our code without a wall of dart:xxx internals.
  static String _firstStackLines(StackTrace? stack, int lines) {
    if (stack == null) return '';
    final kept = <String>[];
    for (final line in stack.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      kept.add(trimmed);
      if (kept.length >= lines) break;
    }
    return kept.join('\n');
  }
}

/// Installs the fallback handlers. Returns a [VoidCallback] that restores
/// whatever handlers were in place before — used by tests and by callers
/// that hand control to Sentry afterwards.
VoidCallback installErrorSafetyNet({
  required DiagnosticsLog log,
  bool consoleDumpInDebug = true,
}) {
  final previousFlutterError = FlutterError.onError;
  final previousDispatcherError = PlatformDispatcher.instance.onError;

  FlutterError.onError = (details) {
    log.record(details.exception, details.stack);
    if (consoleDumpInDebug && !kReleaseMode) {
      previousFlutterError?.call(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    log.record(error, stack);
    // Mark handled so the error does not also tear down the zone — the
    // app stays alive with the problem logged instead of dying silently.
    return true;
  };

  return () {
    FlutterError.onError = previousFlutterError;
    PlatformDispatcher.instance.onError = previousDispatcherError;
  };
}

/// Resolves the localized message for the friendly error widget. Set once
/// per build in `app.dart` (which owns the [LocaleController]); the
/// closure holds the controller instance, so it stays fresh across locale
/// switches without needing a BuildContext.
String Function()? localizedScreenErrorResolver;

/// Release-mode replacement for Flutter's default grey/red developer
/// error box: a calm, localized card. Deliberately dependency-free —
/// providers, theme lookups and the resolver are all treated as things
/// that may themselves be broken, so every read is guarded and the whole
/// builder degrades to blank rather than recursing.
Widget buildFriendlyErrorWidget(FlutterErrorDetails details) {
  try {
    String message = '';
    try {
      message = localizedScreenErrorResolver?.call() ?? '';
    } catch (_) {
      message = '';
    }
    if (message.trim().isEmpty) message = kFallbackScreenError;
    return ColoredBox(
      color: const Color(0xFFF6F7FB),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5B6170),
            ),
          ),
        ),
      ),
    );
  } catch (_) {
    return const SizedBox.shrink();
  }
}
