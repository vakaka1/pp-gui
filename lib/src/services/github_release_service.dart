import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';
import 'app_paths.dart';

typedef DownloadProgress = void Function(int receivedBytes, int? totalBytes);

class GitHubReleaseService {
  static const latestReleaseUrl = 'https://api.github.com/repos/vakaka1/pp/releases/latest';

  Future<ReleaseInfo> fetchLatestRelease() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(latestReleaseUrl));
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

      if (await target.exists()) {
        await target.delete();
      }
      await tempFile.rename(target.path);

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
