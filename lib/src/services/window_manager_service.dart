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
    await windowManager.ensureInitialized().timeout(const Duration(seconds: 2));
    windowManager.addListener(this);

    // Set window icon (affects some window managers / taskbars)
    if (!Platform.isWindows) {
      try {
        await windowManager
            .setIcon('assets/app_icon.png')
            .timeout(const Duration(seconds: 2));
      } on Object catch (e) {
        debugPrint('setIcon failed (non-fatal): $e');
      }
    }

    // Tray initialisation is optional — the app must work even if it fails.
    try {
      trayManager.addListener(this);
      await _initTray().timeout(const Duration(seconds: 3));
      await windowManager.setPreventClose(true);
      _trayReady = true;
    } on Object catch (e) {
      debugPrint('Tray init failed (non-fatal): $e');
    }

    _initialized = true;
  }

  Future<void> _initTray() async {
    // Use 512px icon for tray for maximum sharpness
    String iconPath =
        Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon_512.png';
    await trayManager.setIcon(iconPath);

    Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: 'Показать окно',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: 'Выход',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
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
