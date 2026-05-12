import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/services/window_manager_service.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const PpGuiApp());

  // Window/tray initialisation must never block the first Flutter frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeWindowService());
  });
}

Future<void> _initializeWindowService() async {
  try {
    final windowService = WindowManagerService();
    await windowService.initialize().timeout(const Duration(seconds: 5));
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
