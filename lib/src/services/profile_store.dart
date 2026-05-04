import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';
import 'app_paths.dart';

class ProfileStore {
  Future<List<ProfileRef>> listManagedProfiles() async {
    final directory = AppPaths.profilesDirectory;
    if (!await directory.exists()) {
      return const [];
    }

    final profiles = <ProfileRef>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is Map<String, dynamic>) {
          profiles.add(ProfileRef.fromManagedFile(entity, decoded));
        }
      } on FormatException {
        continue;
      } on IOException {
        continue;
      }
    }
    profiles
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return profiles;
  }

  Future<ProfileRef> saveDraft(ClientConfigDraft draft) async {
    final file = AppPaths.managedProfileFile(draft.profileName);
    await file.parent.create(recursive: true);
    final json = draft.toJson();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    return ProfileRef.fromManagedFile(file, json);
  }

  Future<ProfileRef> saveJson(String rawJson, {String? fallbackName}) async {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON профиля должен быть объектом');
    }
    final draft = ClientConfigDraft.fromJson(decoded);
    final fallback = fallbackName?.trim();
    final withName = decoded.containsKey('profile_name')
        ? decoded
        : {
            ...decoded,
            'profile_name': fallback != null && fallback.isNotEmpty
                ? fallback
                : draft.profileName,
          };
    final name = (withName['profile_name'] ?? fallbackName ?? draft.profileName)
        .toString();
    final file = AppPaths.managedProfileFile(name);
    await file.parent.create(recursive: true);
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(withName));
    return ProfileRef.fromManagedFile(file, withName);
  }

  Future<ClientConfigDraft> readDraft(ProfileRef profile) async {
    final path = profile.path;
    if (path == null) {
      throw const FileSystemException('У профиля нет пути к конфигурации');
    }
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON профиля должен быть объектом');
    }
    return ClientConfigDraft.fromJson(decoded);
  }

  Future<String> readRawJson(ProfileRef profile) async {
    final path = profile.path;
    if (path == null) {
      throw const FileSystemException('У профиля нет пути к конфигурации');
    }
    return File(path).readAsString();
  }

  Future<void> deleteManaged(ProfileRef profile) async {
    final path = profile.path;
    if (path == null) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
