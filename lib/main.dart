import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/services/window_manager_service.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final windowService = WindowManagerService();
  await windowService.initialize();

  runApp(const PpGuiApp());
}

class PpGuiApp extends StatelessWidget {
  const PpGuiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PP GUI',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [
        Locale('ru'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: ppDarkTheme(),
      home: const AppShell(),
    );
  }
}
