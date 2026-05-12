
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/services/window_manager_service.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Window/tray initialisation must not prevent the app from starting.
  // If any platform plugin fails (missing DLL, permission, etc.) we still
  // show the main UI so the user can at least see an error or use the app.
  try {
    final windowService = WindowManagerService();
    await windowService.initialize();
  } on Object catch (e) {
    debugPrint('Window/tray init failed (non-fatal): $e');
  }

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
