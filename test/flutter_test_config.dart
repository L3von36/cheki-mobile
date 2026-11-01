import 'dart:async';

import 'package:mahtem/core/cpu_tasks.dart';

/// Runs once per `flutter test` invocation, before any test file.
///
/// Widget tests execute inside a FakeAsync zone: a background isolate's
/// result is delivered by the REAL event loop, so an `await` on
/// `Isolate.run` can never complete there — sign-in walks would freeze
/// and the suite would wedge. Run every CPU-bound derivation inline in
/// tests (test hashes use tiny iteration counts, so this is instant);
/// the real app keeps the isolate offload via the default `true`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  kRunCpuTasksOnBackgroundIsolate = false;
  await testMain();
}
