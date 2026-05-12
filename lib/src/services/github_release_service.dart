import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';
import 'app_paths.dart';

typedef DownloadProgress = void Function(int receivedBytes, int? totalBytes);

class GitHubReleaseService {
  static const latestReleaseUrl = 'https://api.github.com/repos/vakaka1/pp/releases/latest';
  static const guiLatestReleaseUrl = 'https://api.github.com/repos/vakaka1/pp-gui/releases/latest';

  Future<ReleaseInfo> fetchLatestRelease() async {
    return _fetchRelease(latestReleaseUrl);
  }

  Future<ReleaseInfo?> fetchLatestGuiRelease() async {
    try {
      return await _fetchRelease(guiLatestReleaseUrl);
    } on Object {
      // GUI repo may not have releases yet.
      return null;
    }
  }

  Future<ReleaseInfo> _fetchRelease(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'pp-gui');
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('GitHub вернул HTTP ${response.statusCode}: $body');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Ответ GitHub о релизе не является объектом');
      }
      return ReleaseInfo.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }
}

class PpClientInstaller {
  Future<File> installAsset(
    ReleaseAsset asset, {
    DownloadProgress? onProgress,
  }) async {
    if (asset.browserDownloadUrl.trim().isEmpty) {
      throw const FormatException('У файла релиза нет URL для скачивания');
    }

    final target = AppPaths.defaultInstallTarget();
    await target.parent.create(recursive: true);
    final tempFile = File('${target.path}.download');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(asset.browserDownloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'pp-gui');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decodeStream(response);
        throw HttpException('Скачивание не удалось, HTTP ${response.statusCode}: $body');
      }

      final sink = tempFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, response.contentLength <= 0 ? null : response.contentLength);
        }
      } finally {
        await sink.close();
      }

      if (asset.size > 0 && received != asset.size) {
        throw FileSystemException('Размер скачанного файла не совпадает с ожидаемым', tempFile.path);
      }

      if (asset.name.toLowerCase().endsWith('.zip')) {
        // Handle ZIP archive (common for Windows releases)
        final extractDir = await Directory.systemTemp.createTemp('pp-client-extract-');
        try {
          if (Platform.isWindows) {
            final result = await Process.run('powershell', [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              'Expand-Archive -Force -Path "${tempFile.path}" -DestinationPath "${extractDir.path}"'
            ]);
            if (result.exitCode != 0) {
              throw ProcessException('powershell', ['Expand-Archive'], result.stderr.toString(), result.exitCode);
            }
          } else {
            // Fallback for other platforms if they use ZIP
            final result = await Process.run('unzip', ['-o', tempFile.path, '-d', extractDir.path]);
            if (result.exitCode != 0) {
              throw ProcessException('unzip', [tempFile.path], result.stderr.toString(), result.exitCode);
            }
          }

          // Find the actual binary in the extracted files
          final files = await extractDir.list(recursive: true).toList();
          final binary = files.whereType<File>().where((f) {
            final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
            return name == 'pp-client.exe' || name == 'pp-client';
          }).firstOrNull;

          if (binary == null) {
            throw FileSystemException('Исполняемый файл не найден в архиве', asset.name);
          }

          if (await target.exists()) {
            await target.delete();
          }
          await binary.rename(target.path);
        } finally {
          try {
            await extractDir.delete(recursive: true);
          } on Object {/* ignore */}
        }
      } else {
        // Direct binary download (common for Linux)
        if (await target.exists()) {
          await target.delete();
        }
        await tempFile.rename(target.path);
      }

      if (!Platform.isWindows) {
        await Process.run('chmod', ['755', target.path]);
      }
      return target;
    } finally {
      client.close(force: true);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}
