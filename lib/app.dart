import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth/account_store.dart';
import 'core/auth/password_hasher.dart';
import 'core/error_safety_net.dart';
import 'core/localization/am_material_localizations.dart';
import 'core/localization/app_strings.dart';
import 'core/verify_history.dart';
import 'state/app_tab.dart';
import 'state/auth_controller.dart';
import 'state/batch_controller.dart';
import 'state/cloud_controller.dart';
import 'state/license_controller.dart';
import 'state/locale_controller.dart';
import 'state/theme_controller.dart';
import 'state/verify_controller.dart';
import 'theme/mahtem_theme.dart';
import 'ui/screens/auth/auth_gate.dart';

/// Root widget: providers + theme + language + auth wiring.
///
/// The [AuthGate] boots straight into the shell when a session exists —
/// otherwise sign-in / create-account, depending on whether the device
/// already has an account. Theme mode and language are persisted via the
/// [SharedPreferences] instance loaded in `main()`. [auth] and [authStore]
/// exist for tests so the gate can run without platform secure storage.
class MahtemApp extends StatelessWidget {
  const MahtemApp({
    super.key,
    this.prefs,
    this.auth,
    this.authStore,
    this.hasher,
  });

  final SharedPreferences? prefs;

  /// Pre-built auth controller (tests seed a signed-in session with it).
  final AuthController? auth;

  /// In-memory account store for tests when no pre-built controller is
  /// needed.
  final AccountKeyValue? authStore;

  /// Fast hasher for tests.
  final PasswordHasher? hasher;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VerifyController()),
        // Batch checker owns its state — rows from the last paste, run
        // results. Fresh instance per app boot (nothing persists).
        ChangeNotifierProvider(create: (_) => BatchController()),
        ChangeNotifierProvider(create: (_) => VerifyHistory()),
        // Cloud backup (v1.13.0) — opt-in zero-knowledge history backup.
        // Restores its persisted session from the boot prefs; a no-op
        // until the user enables it in Settings.
        ChangeNotifierProvider(
          create: (_) => CloudController(prefs: prefs)..ensureLoaded(),
        ),
        ChangeNotifierProvider(create: (_) => AppTab()),
        // Licensing loads in the background — the paywall/gate awaits it.
        ChangeNotifierProvider(
          create: (_) => LicenseController()..ensureLoaded(),
        ),
        // Appearance + language restore synchronously from prefs.
        ChangeNotifierProvider(
          create: (_) => ThemeController(prefs: prefs)..ensureLoaded(),
        ),
        ChangeNotifierProvider(
          create: (_) => LocaleController(prefs: prefs)..ensureLoaded(),
        ),
        // Accounts load from secure storage in the background — the gate
        // shows a branded splash until then. (ensureLoaded is idempotent
        // and safe on a pre-seeded test controller.)
        ChangeNotifierProvider<AuthController>(
          create: (_) =>
              (auth ?? AuthController(store: authStore, hasher: hasher))
                ..ensureLoaded(),
        ),
      ],
      child: Consumer2<ThemeController, LocaleController>(
        builder: (context, theme, locale, _) {
          // Friendly error widget text stays localized: the resolver holds
          // the current LocaleController instance (no context needed), and
          // app.dart rebuilds it on every locale switch.
          localizedScreenErrorResolver =
              () => locale.strings.somethingWentWrongScreen;
          return MaterialApp(
            title: 'Mahtem',
            debugShowCheckedModeBanner: false,
            // Flutter has no built-in `am` MaterialLocalizations — this
            // delegate ships the Amharic system strings (copy/paste menus,
            // tooltips) so Amharic mode boots clean, without the "locale am
            // is not supported" warning.
            localizationsDelegates: const [
              MahtemLocalizationsDelegate(),
              MahtemCupertinoLocalizationsDelegate(),
            ],
            locale: locale.materialLocale,
            supportedLocales: kSupportedLocales,
            theme: MahtemTheme.light(ethiopicFont: locale.usesEthiopicScript),
            darkTheme: MahtemTheme.dark(ethiopicFont: locale.usesEthiopicScript),
            themeMode: theme.mode,
            home: const AuthGate(),
            // Records which screen the user was on when a crash happens —
            // a no-op unless Sentry was initialized at boot (DSN present).
            navigatorObservers: [SentryNavigatorObserver()],
          );
        },
      ),
    );
  }
}
