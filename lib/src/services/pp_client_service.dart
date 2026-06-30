import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import 'app_paths.dart';

abstract class PpClientProcess {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
}

class _NativePpClientProcess implements PpClientProcess {
  _NativePpClientProcess(this._process);

  final Process _process;

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }
}

class _WindowsElevatedPpClientProcess implements PpClientProcess {
  _WindowsElevatedPpClientProcess._({
    required this.pid,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.killCallback,
  });

  final bool Function(ProcessSignal signal) killCallback;

  @override
  final int pid;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  @override
  final Future<int> exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return killCallback(signal);
  }

  static Future<_WindowsElevatedPpClientProcess> start(
    String executable,
    List<String> args,
  ) async {
    final sessionDir = await Directory.systemTemp.createTemp('pp-gui-client-');
    final stdoutFile = File(AppPaths.join(sessionDir.path, 'stdout.log'));
    final stderrFile = File(AppPaths.join(sessionDir.path, 'stderr.log'));
    final pidFile = File(AppPaths.join(sessionDir.path, 'pid.txt'));
    final exitFile = File(AppPaths.join(sessionDir.path, 'exit.txt'));
    final stopFile = File(AppPaths.join(sessionDir.path, 'stop.signal'));
    final scriptFile = File(AppPaths.join(sessionDir.path, 'run-client.ps1'));

    await stdoutFile.writeAsString('');
    await stderrFile.writeAsString('');

    String psQuote(String value) => "'${value.replaceAll("'", "''")}'";
    String cmdEscape(String s) => '"${s.replaceAll('"', '""')}"';
    final escapedArgs = args.map(cmdEscape).join(' ');

    final scriptContent = '''
try {
    \$ErrorActionPreference = 'Stop'
    \$code = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

public class Launcher {
    public static int Run(string exe, string args, string outFile, string errFile, string pidFile, string stopFile) {
        try {
            Process p = new Process();
            p.StartInfo.FileName = "cmd.exe";
            p.StartInfo.Arguments = string.Format("/c \\"\\"{0}\\" {1} > \\"{2}\\" 2> \\"{3}\\"\\"", exe, args, outFile, errFile);
            p.StartInfo.UseShellExecute = false;
            p.StartInfo.CreateNoWindow = true;
            
            if (!p.Start()) return -1;
            
            File.WriteAllText(pidFile, p.Id.ToString());
            
            while (!p.WaitForExit(500)) {
                if (File.Exists(stopFile)) {
                    // Kill the entire tree (cmd.exe and pp-client.exe)
                    using (Process killer = Process.Start(new ProcessStartInfo {
                        FileName = "taskkill",
                        Arguments = "/F /T /PID " + p.Id,
                        CreateNoWindow = true,
                        UseShellExecute = false
                    })) {
                        killer.WaitForExit();
                    }
                    return 0;
                }
            }
            return p.ExitCode;
        } catch (Exception e) {
            File.WriteAllText(errFile, "Launcher Exception: " + e.Message);
            return -2;
        }
    }
}
'@

    Add-Type -TypeDefinition \$code
    \$exitCode = [Launcher]::Run(${psQuote(executable)}, ${psQuote(escapedArgs)}, ${psQuote(stdoutFile.path)}, ${psQuote(stderrFile.path)}, ${psQuote(pidFile.path)}, ${psQuote(stopFile.path)})
    Set-Content -LiteralPath ${psQuote(exitFile.path)} -Value \$exitCode -Encoding ascii
} catch {
    \$msg = "PowerShell Error: \$_"
    Add-Content -LiteralPath ${psQuote(stderrFile.path)} -Value \$msg
    Set-Content -LiteralPath ${psQuote(exitFile.path)} -Value 1 -Encoding ascii
    throw
}
''';

    await scriptFile
        .writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(scriptContent)]);

    await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-Command',
        'Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ${psQuote(scriptFile.path)}) -Verb RunAs -WindowStyle Hidden',
      ],
      runInShell: false,
    );

    final pid = await _waitForPid(pidFile);
    final exitCompleter = Completer<int>();
    final stdoutController = StreamController<List<int>>();
    final stderrController = StreamController<List<int>>();
    final stdoutTail = _FileTail(stdoutFile, stdoutController);
    final stderrTail = _FileTail(stderrFile, stderrController);
    final timers = <Timer>[];

    timers.add(stdoutTail.start());
    timers.add(stderrTail.start());
    timers.add(Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!await exitFile.exists()) return;
      timer.cancel();
      for (final t in timers) {
        if (t.isActive) t.cancel();
      }
      // Wait a bit for file buffers to flush
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await stdoutTail.flush();
      await stderrTail.flush();
      await stdoutController.close();
      await stderrController.close();
      final text = (await exitFile.readAsString()).trim();
      exitCompleter.complete(int.tryParse(text) ?? 0);
      unawaited(Future.delayed(const Duration(seconds: 5), () async {
        try {
          if (await sessionDir.exists()) {
            await sessionDir.delete(recursive: true);
          }
        } on Object {/* ignore */}
      }));
    }));

    return _WindowsElevatedPpClientProcess._(
      pid: pid,
      stdout: stdoutController.stream,
      stderr: stderrController.stream,
      exitCode: exitCompleter.future,
      killCallback: (_) {
        try {
          stopFile.writeAsStringSync('stop');
          return true;
        } on Object {
          unawaited(Process.run('taskkill', ['/F', '/PID', '$pid', '/T']));
          return true;
        }
      },
    );
  }

  static Future<int> _waitForPid(File pidFile) async {
    for (var i = 0; i < 120; i += 1) {
      if (await pidFile.exists()) {
        final text = (await pidFile.readAsString()).trim();
        final pid = int.tryParse(text);
        if (pid != null) return pid;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const ProcessException(
      'powershell.exe',
      ['Start-Process', '-Verb', 'RunAs'],
      'Administrator prompt was cancelled or pp-client did not start.',
    );
  }

  static Future<int> _readNewBytes(
    File file,
    StreamController<List<int>> controller,
    int offset,
  ) async {
    if (controller.isClosed || !await file.exists()) return offset;
    final length = await file.length();
    if (length <= offset) return offset;
    final raf = await file.open();
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(length - offset);
      if (bytes.isNotEmpty && !controller.isClosed) {
        controller.add(bytes);
      }
      return length;
    } finally {
      await raf.close();
    }
  }
}

class _FileTail {
  _FileTail(this.file, this.controller);

  final File file;
  final StreamController<List<int>> controller;
  var _offset = 0;

  Timer start() {
    return Timer.periodic(const Duration(milliseconds: 250), (_) async {
      await flush();
    });
  }

  Future<void> flush() async {
    _offset = await _WindowsElevatedPpClientProcess._readNewBytes(
      file,
      controller,
      _offset,
    );
  }
}

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
        updateChannel: UpdateChannel.stable,
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
        updateChannel: await readUpdateChannel(),
        error:
            'Файл не является корректным исполняемым файлом Windows (возможно, поврежден или это архив)',
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
      if (_hasCommand(help.stdout, 'choice')) {
        capabilities.add(PpCapability.updateChoice);
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
      updateChannel: await readUpdateChannel(),
      error: error,
    );
  }

  Future<String?> resolveBinaryPath({String? preferredPath}) async {
    if (preferredPath != null && preferredPath.trim().isNotEmpty) {
      final file = File(preferredPath.trim());
      if (await file.exists() && await _isValidBinary(file)) {
        debugPrint('Using preferred path: ${file.path}');
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
          debugPrint('Found valid binary via $command: ${file.path}');
          return file.path;
        }
      }
    }

    final common = <String>[
      AppPaths.defaultInstallTarget().path,
      if (Platform.isWindows) ...[
        AppPaths.join(
            Platform.environment['LOCALAPPDATA'] ?? '', 'pp\\pp-client.exe'),
        AppPaths.join(
            Platform.environment['LOCALAPPDATA'] ?? '', 'PP\\pp-client.exe'),
      ],
      if (!Platform.isWindows) '/usr/local/bin/pp-client',
      if (!Platform.isWindows) '/usr/bin/pp-client',
    ];
    for (final path in common) {
      final file = File(path);
      if (await file.exists() && await _isValidBinary(file)) {
        debugPrint('Found valid binary in common path: ${file.path}');
        return file.path;
      }
    }

    debugPrint('No valid pp-client binary found');
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
      debugPrint('Error checking binary validity for ${file.path}: $e');
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
  Future<TestResult> testProfile(
      PpBinaryInfo binary, ProfileRef profile) async {
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
    if (Platform.isWindows) {
      return _runWindowsElevatedCommand(
        binary.path!,
        const ['full-tunnel', 'down'],
        timeout: const Duration(seconds: 20),
      );
    }
    return runCommand(binary.path!, ['full-tunnel', 'down'],
        timeout: const Duration(seconds: 15));
  }

  /// Runs `pp-client update`.
  Future<CommandResult> ppClientUpdate(PpBinaryInfo binary) {
    return runCommand(binary.path!, ['update'],
        timeout: const Duration(seconds: 120));
  }

  Future<UpdateChannel> readUpdateChannel() async {
    final file = AppPaths.updateChannelFile;
    try {
      if (!await file.exists()) return UpdateChannel.stable;
      return UpdateChannelLabels.fromStorageValue(await file.readAsString());
    } on Object {
      return UpdateChannel.stable;
    }
  }

  Future<CommandResult> selectUpdateChannel(
    PpBinaryInfo binary,
    UpdateChannel channel,
  ) {
    return runCommand(binary.path!, ['choice', channel.clientValue],
        timeout: const Duration(seconds: 20));
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

  Future<PpClientProcess> start(
    PpBinaryInfo binary,
    ProfileRef profile, {
    required bool verbose,
  }) async {
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
      final process = await Process.start('pkexec', [binary.path!, ...args],
          runInShell: false);
      return _NativePpClientProcess(process);
    } else if (Platform.isMacOS) {
      // For macOS, we can use osascript to prompt for password
      final shellCmd = "'${binary.path}' ${args.map((a) => "'$a'").join(' ')}";
      final process = await Process.start('osascript',
          ['-e', 'do shell script "$shellCmd" with administrator privileges'],
          runInShell: false);
      return _NativePpClientProcess(process);
    } else if (Platform.isWindows) {
      return _WindowsElevatedPpClientProcess.start(binary.path!, args);
    }

    final process = await Process.start(binary.path!, args, runInShell: false);
    return _NativePpClientProcess(process);
  }

  Future<void> stop(PpClientProcess process,
      {ProfileRef? profile, PpBinaryInfo? binary}) async {
    if (Platform.isLinux) {
      final configPath = profile?.path;
      if (configPath != null && configPath.isNotEmpty) {
        await _safeProcessRun('pkexec',
            ['pkill', '-INT', '-f', 'pp-client.*--config $configPath']);
      }
      process.kill();
    } else if (Platform.isMacOS) {
      await _safeProcessRun('osascript', [
        '-e',
        'do shell script "pkill -INT -f pp-client.*start.*--full-tunnel" with administrator privileges'
      ]);
    } else if (Platform.isWindows) {
      // For Windows, the 'process.pid' might be the PID of the elevated launcher,
      // not the actual client. We must ensure we use the correct PID if available.
      // The taskkill /F /T will handle the entire tree.
      final pid = process.pid;
      _appendDiagnosticLog('Stopping Windows process tree for PID $pid...');
      await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
      process.kill(); // Final safety
    } else {
      process.kill();
    }

    // Safety cleanup: run full-tunnel down after stopping.
    if (binary != null && binary.installed) {
      // Wait a bit more on Windows to ensure process handles are released
      await Future<void>.delayed(
          Duration(milliseconds: Platform.isWindows ? 800 : 500));
      await fullTunnelDown(binary);
    }
  }

  void _appendDiagnosticLog(String message) {
    debugPrint('[PpClientService] \$message');
  }

  Future<CommandResult> runCommand(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return _safeProcessRun(executable, args, timeout: timeout);
  }

  Future<CommandResult> _runWindowsElevatedCommand(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final sessionDir = await Directory.systemTemp.createTemp('pp-gui-command-');
    final stdoutFile = File(AppPaths.join(sessionDir.path, 'stdout.log'));
    final stderrFile = File(AppPaths.join(sessionDir.path, 'stderr.log'));
    final exitFile = File(AppPaths.join(sessionDir.path, 'exit.txt'));
    final scriptFile = File(AppPaths.join(sessionDir.path, 'run-command.ps1'));

    String psQuote(String value) => "'${value.replaceAll("'", "''")}'";
    String cmdEscape(String s) => '"${s.replaceAll('"', '""')}"';
    final escapedArgs = args.map(cmdEscape).join(' ');

    try {
      final scriptContent = '''
\$ErrorActionPreference = 'Stop'
\$code = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.IO;

public class CommandLauncher {
    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public int dwX;
        public int dwY;
        public int dwXSize;
        public int dwYSize;
        public int dwXCountChars;
        public int dwYCountChars;
        public int dwFillAttribute;
        public int dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public int dwProcessId;
        public int dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern bool CreateProcess(
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        [In] ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr hHandle, uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr hObject);

    const uint CREATE_NO_WINDOW = 0x08000000;

    public static int Run(string exe, string args, string outFile, string errFile) {
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        
        string cmdLine = string.Format("/c \\"\\"{0}\\" {1} > \\"{2}\\" 2> \\"{3}\\"\\"", exe, args, outFile, errFile);
        string comspec = Environment.GetEnvironmentVariable("ComSpec");

        PROCESS_INFORMATION pi = new PROCESS_INFORMATION();
        if (!CreateProcess(comspec, comspec + " " + cmdLine, IntPtr.Zero, IntPtr.Zero, false, CREATE_NO_WINDOW, IntPtr.Zero, null, ref si, out pi)) {
            return -1;
        }

        WaitForSingleObject(pi.hProcess, 0xFFFFFFFF);
        uint exitCode = 0;
        GetExitCodeProcess(pi.hProcess, out exitCode);

        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);

        return (int)exitCode;
    }
}
'@

Add-Type -TypeDefinition \$code
\$exitCode = [CommandLauncher]::Run(${psQuote(executable)}, ${psQuote(escapedArgs)}, ${psQuote(stdoutFile.path)}, ${psQuote(stderrFile.path)})
Set-Content -LiteralPath ${psQuote(exitFile.path)} -Value \$exitCode -Encoding ascii
''';

      await scriptFile
          .writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(scriptContent)]);

      await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-Command',
          'Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ${psQuote(scriptFile.path)}) -Verb RunAs -WindowStyle Hidden',
        ],
        runInShell: false,
      );

      final deadline = DateTime.now().add(timeout);
      while (!await exitFile.exists()) {
        if (DateTime.now().isAfter(deadline)) {
          return CommandResult(
            exitCode: 124,
            stdout: await _readTextIfExists(stdoutFile),
            stderr:
                'Команда превысила время ожидания: $executable ${args.join(' ')}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      final exitCode =
          int.tryParse((await exitFile.readAsString()).trim()) ?? 1;
      return CommandResult(
        exitCode: exitCode,
        stdout: await _readTextIfExists(stdoutFile),
        stderr: await _readTextIfExists(stderrFile),
      );
    } finally {
      unawaited(sessionDir.delete(recursive: true).then(
            (_) {},
            onError: (_) {},
          ));
    }
  }

  Future<String> _readTextIfExists(File file) async {
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return '';
    try {
      return utf8.decode(bytes);
    } on Object {
      return systemEncoding.decode(bytes);
    }
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
