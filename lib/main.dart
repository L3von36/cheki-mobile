import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';

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
  runApp(MahtemApp(prefs: prefs));
}
