import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/verify_history.dart';
import 'state/app_tab.dart';
import 'state/system_status.dart';
import 'state/theme_controller.dart';
import 'state/verify_controller.dart';
import 'theme/cheki_theme.dart';
import 'ui/screens/splash_screen.dart';

/// Root widget: providers + theme wiring.
class ChekiApp extends StatelessWidget {
  const ChekiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => VerifyController()),
        ChangeNotifierProvider(create: (_) => VerifyHistory()),
        ChangeNotifierProvider(create: (_) => SystemStatus()..refresh()),
        ChangeNotifierProvider(create: (_) => AppTab()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Cheki',
            debugShowCheckedModeBanner: false,
            theme: ChekiTheme.light(),
            darkTheme: ChekiTheme.dark(),
            themeMode: theme.mode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
