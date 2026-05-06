import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/app_models.dart';

/// Callback for download progress: (receivedBytes, totalBytes).
typedef GuiUpdateProgress = void Function(int received, int? total);

/// Detects the directory where the running GUI is installed.
///
/// - Linux  : the bundle directory that contains the `pp_gui` executable.
///            When installed by the .bin makeself installer this is
///            `/opt/pp-gui/`.  When running directly from a build artefact
///            the directory is wherever the binary lives.
/// - Windows: the directory that contains `pp_gui.exe`.
Directory get _installDir {
  final exe = Platform.resolvedExecutable;
  // On Linux the Flutter bundle layout is:
  //   <installDir>/pp_gui          ← executable
  //   <installDir>/lib/            ← shared libs
  //   <installDir>/data/           ← flutter assets
  // On Windows:
  //   <installDir>\pp_gui.exe
  //   <installDir>\*.dll
  return File(exe).parent;
}

class GuiUpdater {
  /// Download the update archive from [asset], extract it over the current
  /// installation directory and restart the application.
  ///
  /// Throws on any failure so the caller can surface the error to the user.
  Future<void> applyUpdate(
    ReleaseAsset asset, {
    GuiUpdateProgress? onProgress,
  }) async {
    if (asset.browserDownloadUrl.trim().isEmpty) {
      throw const FormatException('Нет URL для скачивания обновления GUI');
    }

    final installDir = _installDir;

    // ---- 1. Download archive to a temp file --------------------------------
    final tmpDir = await Directory.systemTemp.createTemp('pp-gui-update-');
    final archiveName = asset.name;
    final tmpArchive = File('${tmpDir.path}/$archiveName');

    try {
      await _downloadTo(asset, tmpArchive, onProgress: onProgress);

      // ---- 2. Extract -------------------------------------------------------
      if (Platform.isLinux) {
        await _extractTarGz(tmpArchive, installDir);
      } else if (Platform.isWindows) {
        await _extractZip(tmpArchive, installDir);
      } else {
        throw UnsupportedError('Автообновление GUI не поддерживается на этой платформе');
      }

      // ---- 3. Restart the application --------------------------------------
      await _restart();
    } finally {
      // Best-effort cleanup of temp files.
      try {
        await tmpDir.delete(recursive: true);
      } on Object {/* ignore */}
    }
  }

  // ---------------------------------------------------------------------------

  Future<void> _downloadTo(
    ReleaseAsset asset,
    File dest, {
    GuiUpdateProgress? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request =
          await client.getUrl(Uri.parse(asset.browserDownloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'pp-gui');
      final response =
          await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decodeStream(response);
        throw HttpException(
            'Скачивание не удалось, HTTP ${response.statusCode}: $body');
      }

      final sink = dest.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(
              received,
              response.contentLength <= 0 ? null : response.contentLength);
        }
      } finally {
        await sink.close();
      }

      if (asset.size > 0 && received != asset.size) {
        throw FileSystemException(
            'Размер скачанного файла не совпадает с ожидаемым', dest.path);
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Extracts [archive] (tar.gz) into [destDir], replacing existing files.
  Future<void> _extractTarGz(File archive, Directory destDir) async {
    final result = await Process.run(
      'tar',
      ['--overwrite', '-xzf', archive.path, '-C', destDir.path],
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'tar',
        ['--overwrite', '-xzf', archive.path, '-C', destDir.path],
        '${result.stdout}\n${result.stderr}'.trim(),
        result.exitCode,
      );
    }

    // Ensure the main executable is still executable.
    final exe = File('${destDir.path}/pp_gui');
    if (await exe.exists()) {
      await Process.run('chmod', ['755', exe.path]);
    }
  }

  /// Extracts [archive] (zip) into [destDir], replacing existing files.
  /// Uses PowerShell's Expand-Archive on Windows (available since Win10).
  Future<void> _extractZip(File archive, Directory destDir) async {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Expand-Archive -Force -Path "${archive.path}" -DestinationPath "${destDir.path}"',
      ],
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell',
        ['Expand-Archive'],
        '${result.stdout}\n${result.stderr}'.trim(),
        result.exitCode,
      );
    }
  }

  /// Relaunches the current executable and exits this process.
  Future<void> _restart() async {
    final exe = Platform.resolvedExecutable;
    await Process.start(exe, [], mode: ProcessStartMode.detached);
    exit(0);
  }
}
