import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerService with WindowListener, TrayListener {
  static final WindowManagerService _instance = WindowManagerService._internal();
  factory WindowManagerService() => _instance;
  WindowManagerService._internal();

  Future<void> initialize() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);

    await windowManager.setPreventClose(true);

    // Set window icon (affects some window managers / taskbars)
    if (!Platform.isWindows) {
      await windowManager.setIcon('assets/app_icon.png');
    }

    await _initTray();
  }

  Future<void> _initTray() async {
    // Use 512px icon for tray for maximum sharpness
    String iconPath = Platform.isWindows ? 'assets/app_icon.ico' : 'assets/app_icon_512.png';
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
