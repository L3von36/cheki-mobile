/// Where CPU-bound pure-Dart work (PBKDF2 at 120k iterations) runs.
///
/// `true` in the app: deriving on the UI isolate freezes animations and
/// input for a second or more on low-end phones — the "sign-in is laggy"
/// complaint. Flutter widget tests run inside a FakeAsync zone where a
/// background isolate can never deliver its result, so the test runner
/// config (test/flutter_test_config.dart) flips this to `false` and the
/// derivations run inline at test speed.
bool kRunCpuTasksOnBackgroundIsolate = true;
