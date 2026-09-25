import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/verify_history.dart';
import 'state/app_tab.dart';
import 'state/verify_controller.dart';
import 'theme/cheki_theme.dart';
import 'ui/shell.dart';

/// Root widget: providers + theme wiring. Boots straight into the shell —
/// no splash, no extra screens between the user and their task.
class ChekiApp extends StatelessWidget {
  const ChekiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VerifyController()),
        ChangeNotifierProvider(create: (_) => VerifyHistory()),
        ChangeNotifierProvider(create: (_) => AppTab()),
      ],
      child: MaterialApp(
        title: 'Cheki',
        debugShowCheckedModeBanner: false,
        theme: ChekiTheme.light(),
        darkTheme: ChekiTheme.dark(),
        themeMode: ThemeMode.system,
        home: const ShellScreen(),
      ),
    );
  }
}
