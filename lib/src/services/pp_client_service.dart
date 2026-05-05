import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      if (await file.exists()) {
        return file.path;
      }
    }

    final command = Platform.isWindows ? 'where' : 'which';
    final lookup = await _safeProcessRun(command, const ['pp-client']);
    if (lookup.ok) {
      final first = const LineSplitter()
          .convert(lookup.stdout)
          .where((line) => line.trim().isNotEmpty)
          .firstOrNull;
      if (first != null) {
        return first.trim();
      }
    }

    final common = <String>[
      AppPaths.defaultInstallTarget().path,
      if (!Platform.isWindows) '/usr/local/bin/pp-client',
      if (!Platform.isWindows) '/usr/bin/pp-client',
    ];
    for (final path in common) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
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
Future<void> stop(Process process, {ProfileRef? profile}) async {
  if (Platform.isLinux) {
    // Use SIGINT (-2) for graceful shutdown, it's safer for Go apps.
    // Use the config path to target ONLY the specific process.
    final configPath = profile?.path;
    if (configPath != null && configPath.isNotEmpty) {
      // We use pkexec to ensure we have permission to kill if it was started as root.
      // Using -INT instead of -TERM helps to avoid 'close of closed channel' panic.
      await _safeProcessRun('pkexec', ['pkill', '-INT', '-f', 'pp-client.*--config $configPath']);
    }

    // Also kill the pkexec wrapper itself
    process.kill();
  } else if (Platform.isMacOS) {
    await _safeProcessRun('osascript', [
      '-e',
      'do shell script "pkill -INT -f pp-client.*start.*--full-tunnel" with administrator privileges'
    ]);
  } else {
    process.kill();
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
      final result = await Process.run(
        executable,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      return CommandResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
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
