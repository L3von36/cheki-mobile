import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/theme_controller.dart';
import 'state/verify_controller.dart';
import 'theme/cheki_theme.dart';
import 'ui/screens/home_screen.dart';

/// Root widget: providers + theme wiring.
class ChekiApp extends StatelessWidget {
  const ChekiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => VerifyController()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Cheki',
            debugShowCheckedModeBanner: false,
            theme: ChekiTheme.light(),
            darkTheme: ChekiTheme.dark(),
            themeMode: theme.mode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
