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

    final fullTunnelHelp =
        await runCommand(resolvedPath, const ['full-tunnel', '--help']);
    if (fullTunnelHelp.ok && fullTunnelHelp.stdout.contains('full-tunnel')) {
      capabilities.add(PpCapability.fullTunnel);
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
        .toList(growable: false);
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
    String? transparentListen,
  }) {
    final args = <String>[];
    if (verbose) {
      args.add('--verbose');
    }
    args.add('start');
    if (profile.path != null) {
      args.addAll(['--config', profile.path!]);
    } else {
      args.add(profile.name);
    }
    if (transparentListen != null &&
        transparentListen.trim().isNotEmpty &&
        binary.canTransparentListen) {
      args.addAll(['--transparent-listen', transparentListen.trim()]);
    }
    return Process.start(binary.path!, args, runInShell: false);
  }

  Future<CommandResult> fullTunnelUp(
    PpBinaryInfo binary,
    ProfileRef profile, {
    required String transparentListen,
    required String owner,
  }) {
    if (!Platform.isLinux) {
      return Future.value(const CommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Полный туннель поддерживается только в Linux'));
    }
    return _runPrivileged([
      binary.path!,
      'full-tunnel',
      'up',
      if (profile.path != null) ...['--config', profile.path!] else
        profile.name,
      if (transparentListen.trim().isNotEmpty) ...[
        '--transparent-listen',
        transparentListen.trim()
      ],
      if (owner.trim().isNotEmpty) ...['--owner', owner.trim()],
    ]);
  }

  Future<CommandResult> fullTunnelDown(PpBinaryInfo binary) {
    if (!Platform.isLinux) {
      return Future.value(const CommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'Полный туннель поддерживается только в Linux'));
    }
    return _runPrivileged([binary.path!, 'full-tunnel', 'down']);
  }

  Future<CommandResult> runCommand(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return _safeProcessRun(executable, args, timeout: timeout);
  }

  Future<CommandResult> _runPrivileged(List<String> args) async {
    final pkexec = await _resolveCommand('pkexec');
    if (pkexec == null) {
      return const CommandResult(
        exitCode: 127,
        stdout: '',
        stderr:
            'pkexec не найден. Установите пакет policykit-1/polkit и перезапустите приложение, чтобы GUI мог запросить права администратора для полного туннеля.',
      );
    }
    return _safeProcessRun(pkexec, args, timeout: const Duration(minutes: 2));
  }

  Future<String?> _resolveCommand(String command) async {
    final lookup = await _safeProcessRun(
        Platform.isWindows ? 'where' : 'which', [command]);
    if (!lookup.ok) {
      return null;
    }
    return const LineSplitter()
        .convert(lookup.stdout)
        .where((line) => line.trim().isNotEmpty)
        .firstOrNull
        ?.trim();
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
