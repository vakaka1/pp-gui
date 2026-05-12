import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import 'app_paths.dart';

class PpClientService {
  Future<PpBinaryInfo> inspect({String? preferredPath}) async {
    final resolvedPath = await resolveBinaryPath(preferredPath: preferredPath);
    if (resolvedPath == null) {
      return const PpBinaryInfo(
        path: null,
        version: null,
        buildDate: null,
        commit: null,
        capabilities: {},
        error: 'pp-client не найден в PATH или стандартных местах установки',
      );
    }

    // Secondary safety check: ensure the file is still a valid EXE 
    // before we attempt to execute it.
    if (!await _isValidBinary(File(resolvedPath))) {
      return PpBinaryInfo(
        path: resolvedPath,
        version: null,
        buildDate: null,
        commit: null,
        capabilities: {},
        error: 'Файл не является корректным исполняемым файлом Windows (возможно, поврежден или это архив)',
      );
    }

    final capabilities = <PpCapability>{};
    String? version;
    String? buildDate;
    String? commit;
    String? error;

    final versionResult = await runCommand(resolvedPath, const ['version']);
    if (versionResult.ok) {
      version = parseVersion(versionResult.stdout);
      buildDate = parseLabeledValue(versionResult.stdout, 'Build Date');
      commit = parseLabeledValue(versionResult.stdout, 'Commit');
    }

    final help = await runCommand(resolvedPath, const ['--help']);
    if (!help.ok) {
      error = help.combinedOutput.trim().isEmpty
          ? 'Не удалось запустить pp-client'
          : help.combinedOutput.trim();
    } else {
      if (help.stdout.contains('validate-config')) {
        capabilities.add(PpCapability.validateConfig);
      }
      if (_hasCommand(help.stdout, 'import')) {
        capabilities.add(PpCapability.importUri);
      }
      if (_hasCommand(help.stdout, 'list')) {
        capabilities.add(PpCapability.listProfiles);
      }
      if (_hasCommand(help.stdout, 'delete')) {
        capabilities.add(PpCapability.deleteProfile);
      }
    }

    final startHelp = await runCommand(resolvedPath, const ['start', '--help']);
    if (startHelp.stdout.contains('--transparent-listen')) {
      capabilities.add(PpCapability.transparentListen);
    }

    return PpBinaryInfo(
      path: resolvedPath,
      version: version,
      buildDate: buildDate,
      commit: commit,
      capabilities: capabilities,
      error: error,
    );
  }

  Future<String?> resolveBinaryPath({String? preferredPath}) async {
    if (preferredPath != null && preferredPath.trim().isNotEmpty) {
      final file = File(preferredPath.trim());
      if (await file.exists() && await _isValidBinary(file)) {
        print('Using preferred path: ${file.path}');
        return file.path;
      }
    }

    final command = Platform.isWindows ? 'where' : 'which';
    final lookup = await _safeProcessRun(command, const ['pp-client']);
    if (lookup.ok) {
      final lines = const LineSplitter()
          .convert(lookup.stdout)
          .where((line) => line.trim().isNotEmpty);
      for (final line in lines) {
        final file = File(line.trim());
        if (await file.exists() && await _isValidBinary(file)) {
          print('Found valid binary via $command: ${file.path}');
          return file.path;
        }
      }
    }

    final common = <String>[
      AppPaths.defaultInstallTarget().path,
      if (Platform.isWindows) ...[
        AppPaths.join(Platform.environment['LOCALAPPDATA'] ?? '', 'pp\\pp-client.exe'),
        AppPaths.join(Platform.environment['LOCALAPPDATA'] ?? '', 'PP\\pp-client.exe'),
      ],
      if (!Platform.isWindows) '/usr/local/bin/pp-client',
      if (!Platform.isWindows) '/usr/bin/pp-client',
    ];
    for (final path in common) {
      final file = File(path);
      if (await file.exists() && await _isValidBinary(file)) {
        print('Found valid binary in common path: ${file.path}');
        return file.path;
      }
    }
    
    print('No valid pp-client binary found');
    return null;
  }

  Future<bool> _isValidBinary(File file) async {
    if (!Platform.isWindows) return true;
    RandomAccessFile? raf;
    try {
      if (await file.length() < 2) return false;
      raf = await file.open(mode: FileMode.read);
      final header = await raf.read(2);
      // Check for 'MZ' header
      return header.length == 2 && header[0] == 0x4D && header[1] == 0x5A;
    } on Object catch (e) {
      print('Error checking binary validity for ${file.path}: $e');
      return false;
    } finally {
      await raf?.close();
    }
  }

  Future<CommandResult> validateConfig(PpBinaryInfo binary, String configPath) {
    return runCommand(binary.path!, ['validate-config', '--config', configPath],
        timeout: const Duration(seconds: 20));
  }

  Future<CommandResult> pingHost(String host) {
    if (Platform.isWindows) {
      return _safeProcessRun('ping', ['-n', '1', '-w', '2000', host],
          timeout: const Duration(seconds: 5));
    }
    return _safeProcessRun('ping', ['-c', '1', '-W', '2', host],
        timeout: const Duration(seconds: 5));
  }

  /// Runs `pp-client test` and parses `PP_CLIENT_TEST_RESULT` JSON.
  Future<TestResult> testProfile(PpBinaryInfo binary, ProfileRef profile) async {
    final args = <String>['test'];
    if (profile.path != null) {
      args.addAll(['--config', profile.path!]);
    } else {
      args.add(profile.name);
    }
    final result = await runCommand(binary.path!, args,
        timeout: const Duration(seconds: 30));
    final match =
        RegExp(r'PP_CLIENT_TEST_RESULT\s+(\{.*\})').firstMatch(result.stdout);
    if (match != null) {
      try {
        final json = jsonDecode(match.group(1)!) as Map<String, dynamic>;
        return TestResult.fromJson(json);
      } on Object {
        // fall through
      }
    }
    return TestResult(
      status: result.ok ? 'ok' : 'error',
      connectOk: false,
      pingOk: false,
      pingMs: null,
      error: result.combinedOutput.trim().isEmpty
          ? 'не удалось выполнить pp-client test'
          : result.combinedOutput.trim(),
    );
  }

  /// Runs `pp-client full-tunnel down` as safety cleanup.
  Future<CommandResult> fullTunnelDown(PpBinaryInfo binary) {
    if (Platform.isLinux) {
      return runCommand('pkexec', [binary.path!, 'full-tunnel', 'down'],
          timeout: const Duration(seconds: 15));
    }
    return runCommand(binary.path!, ['full-tunnel', 'down'],
        timeout: const Duration(seconds: 15));
  }

  /// Runs `pp-client update`.
  Future<CommandResult> ppClientUpdate(PpBinaryInfo binary) {
    return runCommand(binary.path!, ['update'],
        timeout: const Duration(seconds: 120));
  }

  Future<List<ProfileRef>> listProfiles(PpBinaryInfo binary) async {
    if (!binary.canListProfiles || binary.path == null) {
      return const [];
    }
    final result = await runCommand(binary.path!, const ['list', '--json']);
    if (!result.ok) {
      throw ProcessException(binary.path!, const ['list', '--json'],
          result.combinedOutput, result.exitCode);
    }
    final decoded = jsonDecode(result.stdout);
    final items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
            ? decoded['profiles'] as List? ?? const []
            : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(ProfileRef.fromClientJson)
        .map(_resolveClientStoreProfilePath)
        .toList(growable: false);
  }

  ProfileRef _resolveClientStoreProfilePath(ProfileRef profile) {
    final path = profile.path;
    if (path == null || path.trim().isEmpty) {
      return profile;
    }
    final resolvedPath = AppPaths.resolvePpClientConfigPath(path);
    if (resolvedPath == path) {
      return profile;
    }
    return ProfileRef(
      id: resolvedPath,
      name: profile.name,
      source: profile.source,
      path: resolvedPath,
      metadata: {
        ...profile.metadata,
        'path': resolvedPath,
        'original_path': path,
      },
    );
  }

  Future<CommandResult> importUri(PpBinaryInfo binary, String uri) {
    return runCommand(binary.path!, ['import', uri],
        timeout: const Duration(seconds: 20));
  }

  Future<CommandResult> deleteProfile(PpBinaryInfo binary, ProfileRef profile) {
    return runCommand(binary.path!, ['delete', profile.name],
        timeout: const Duration(seconds: 20));
  }

  Future<Process> start(
    PpBinaryInfo binary,
    ProfileRef profile, {
    required bool verbose,
  }) {
    final args = <String>[];
    if (verbose) {
      args.add('--verbose');
    }
    args.add('start');
    
    // Use absolute path if available to ensure it works under pkexec/sudo
    if (profile.path != null) {
      args.add('--config');
      args.add(profile.path!);
    } else {
      args.add(profile.name);
    }
    
    args.add('--full-tunnel');

    if (Platform.isLinux) {
      return Process.start('pkexec', [binary.path!, ...args], runInShell: false);
    } else if (Platform.isMacOS) {
      // For macOS, we can use osascript to prompt for password
      final shellCmd = "'${binary.path}' ${args.map((a) => "'$a'").join(' ')}";
      return Process.start('osascript', [
        '-e',
        'do shell script "$shellCmd" with administrator privileges'
      ], runInShell: false);
    }

    return Process.start(binary.path!, args, runInShell: false);
  }
  Future<void> stop(Process process, {ProfileRef? profile, PpBinaryInfo? binary}) async {
    if (Platform.isLinux) {
      final configPath = profile?.path;
      if (configPath != null && configPath.isNotEmpty) {
        await _safeProcessRun('pkexec', ['pkill', '-INT', '-f', 'pp-client.*--config $configPath']);
      }
      process.kill();
    } else if (Platform.isMacOS) {
      await _safeProcessRun('osascript', [
        '-e',
        'do shell script "pkill -INT -f pp-client.*start.*--full-tunnel" with administrator privileges'
      ]);
    } else {
      process.kill();
    }

    // Safety cleanup: run full-tunnel down after stopping.
    if (binary != null && binary.installed) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await fullTunnelDown(binary);
    }
  }
  Future<CommandResult> runCommand(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return _safeProcessRun(executable, args, timeout: timeout);
  }

  static String? parseVersion(String output) {
    final match = RegExp(r'PP-Client Version:\s*([^\s]+)').firstMatch(output);
    return match?.group(1);
  }

  static String? parseLabeledValue(String output, String label) {
    final match = RegExp('${RegExp.escape(label)}:\\s*(.+)').firstMatch(output);
    return match?.group(1)?.trim();
  }

  Future<CommandResult> _safeProcessRun(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      // Use null encoding to get raw bytes and decode manually to handle 
      // potential encoding mismatches between pp-client (UTF-8) and 
      // Windows system commands (OEM CP like 866).
      final result = await Process.run(
        executable,
        args,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(timeout);

      final stdoutBytes = result.stdout as List<int>? ?? const [];
      final stderrBytes = result.stderr as List<int>? ?? const [];

      String decode(List<int> bytes) {
        if (bytes.isEmpty) return '';
        try {
          // Attempt UTF-8 first (standard for pp-client and modern tools)
          return utf8.decode(bytes);
        } on Object {
          try {
            // Fallback to system encoding (CP866/CP1251 on Russian Windows for ping/where)
            return systemEncoding.decode(bytes);
          } on Object {
            // Last resort: latin1 which never fails for any byte sequence
            return latin1.decode(bytes);
          }
        }
      }

      return CommandResult(
        exitCode: result.exitCode,
        stdout: decode(stdoutBytes),
        stderr: decode(stderrBytes),
      );
    } on TimeoutException {
      return CommandResult(
          exitCode: 124,
          stdout: '',
          stderr:
              'Команда превысила время ожидания: $executable ${args.join(' ')}');
    } on ProcessException catch (error) {
      return CommandResult(
          exitCode: error.errorCode, stdout: '', stderr: error.message);
    } on IOException catch (error) {
      return CommandResult(exitCode: 1, stdout: '', stderr: error.toString());
    }
  }

  bool _hasCommand(String help, String command) {
    return RegExp('^\\s*$command\\s', multiLine: true).hasMatch(help);
  }
}
