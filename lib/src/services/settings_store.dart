import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';
import 'app_paths.dart';

class SettingsStore {
  Future<AppSettings> load() async {
    final file = AppPaths.settingsFile;
    if (!await file.exists()) {
      return AppSettings.defaults();
    }
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        return AppSettings.fromJson(json);
      }
    } on FormatException {
      return AppSettings.defaults();
    } on IOException {
      return AppSettings.defaults();
    }
    return AppSettings.defaults();
  }

  Future<void> save(AppSettings settings) async {
    final file = AppPaths.settingsFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(settings.toJson()));
  }
}
