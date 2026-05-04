import 'dart:io';

class AppPaths {
  const AppPaths._();

  static Directory get configDirectory {
    final base = _configBaseDirectory();
    return Directory(_join(base.path, 'pp-gui'));
  }

  static Directory get profilesDirectory {
    return Directory(_join(configDirectory.path, 'profiles'));
  }

  static Directory get ppClientConfigDirectory {
    final base = _configBaseDirectory();
    return Directory(_join(base.path, 'pp-client'));
  }

  static File get settingsFile {
    return File(_join(configDirectory.path, 'settings.json'));
  }

  static File managedProfileFile(String profileName) {
    return File(
        _join(profilesDirectory.path, '${_safeProfileName(profileName)}.json'));
  }

  static File ppClientProfileFile(String profileName) {
    return File(_join(
        ppClientConfigDirectory.path, '${_safeProfileName(profileName)}.json'));
  }

  static String _safeProfileName(String profileName) {
    final safeName = profileName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9а-яё._-]+', unicode: true), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safeName.isEmpty ? 'профиль' : safeName;
  }

  static File defaultInstallTarget() {
    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      return File(_join(_join(_join(base, 'PP'), 'bin'), 'pp-client.exe'));
    }
    final home = Platform.environment['HOME'] ?? '.';
    return File(_join(_join(_join(home, '.local'), 'bin'), 'pp-client'));
  }

  static String resolvePpClientConfigPath(String path) {
    final trimmed = path.trim();
    if (_isAbsolutePath(trimmed)) {
      return trimmed;
    }
    return _join(ppClientConfigDirectory.path, trimmed);
  }

  static String join(String left, String right) => _join(left, right);

  static Directory _configBaseDirectory() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'];
      return Directory(appData ?? '.');
    }
    final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
    if (xdgConfig != null && xdgConfig.trim().isNotEmpty) {
      return Directory(xdgConfig);
    }
    final home = Platform.environment['HOME'] ?? '.';
    return Directory(_join(home, '.config'));
  }

  static String _join(String left, String right) {
    if (left.isEmpty) {
      return right;
    }
    final separator = Platform.pathSeparator;
    if (left.endsWith('/') || left.endsWith('\\')) {
      return '$left$right';
    }
    return '$left$separator$right';
  }

  static bool _isAbsolutePath(String path) {
    if (Platform.isWindows) {
      return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
          path.startsWith(r'\\');
    }
    return path.startsWith('/');
  }
}
