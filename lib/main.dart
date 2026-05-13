import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/services/window_manager_service.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/theme.dart';

void main() {
  debugPrint('--- APP STARTING ---');
  // Ensure Flutter is ready.
  WidgetsFlutterBinding.ensureInitialized();

  // Run the app immediately.
  runApp(const PpGuiApp());

  // All window-related initialization must happen after the app starts 
  // and must not block the main execution flow.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('--- POST FRAME CALLBACK ---');
    _initializeWindowService();
  });
}

Future<void> _initializeWindowService() async {
  try {
    final windowService = WindowManagerService();
    await windowService.initialize().timeout(const Duration(seconds: 10));
  } on Object catch (e) {
    debugPrint('Window/tray init failed (non-fatal): $e');
  }
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
