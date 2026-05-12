import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerService with WindowListener, TrayListener {
  static final WindowManagerService _instance = WindowManagerService._internal();
  factory WindowManagerService() => _instance;
  WindowManagerService._internal();

  bool _initialized = false;
  bool _trayReady = false;

  Future<void> initialize() async {
    debugPrint('WindowManagerService: starting initialization...');
    try {
      await windowManager.ensureInitialized().timeout(const Duration(seconds: 4));
      windowManager.addListener(this);
      debugPrint('WindowManagerService: windowManager initialized');
    } on Object catch (e) {
      debugPrint('WindowManagerService: windowManager.ensureInitialized failed: $e');
    }

    // Tray initialisation is optional — the app must work even if it fails.
    try {
      trayManager.addListener(this);
      // ... (rest of icon logic)
      // Construct absolute path for Windows icon
      String iconPath;
      if (Platform.isWindows) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        iconPath = '$exeDir\\data\\flutter_assets\\assets\\app_icon.ico';
        if (!await File(iconPath).exists()) {
          iconPath = 'assets/app_icon.ico';
        }
      } else {
        iconPath = 'assets/app_icon_512.png';
      }

      await trayManager.setIcon(iconPath).timeout(const Duration(seconds: 3));
      
      final menu = Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Показать окно'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Выход'),
        ],
      );
      await trayManager.setContextMenu(menu).timeout(const Duration(seconds: 2));
      
      await windowManager.setPreventClose(true);
      _trayReady = true;
    } on Object catch (e) {
      debugPrint('Tray/Window extra init failed (non-fatal): $e');
    }

    _initialized = true;
  }

  @override
  void onWindowClose() async {
    if (!_initialized) return;
    if (!_trayReady) {
      await windowManager.destroy();
      exit(0);
    }
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      await windowManager.setPreventClose(false);
      await windowManager.close();
      exit(0);
    }
  }
}
