import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/github_release_service.dart';
import '../services/gui_updater.dart';
import '../services/pp_client_service.dart';
import '../services/profile_store.dart';
import '../services/settings_store.dart';
import 'about_screen.dart';
import 'configs_screen.dart';
import 'home_screen.dart';
import 'logs_screen.dart';

enum AppSection { home, configs, logs, about }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _ppClient = PpClientService();
  final _releases = GitHubReleaseService();
  final _installer = PpClientInstaller();
  final _guiUpdater = GuiUpdater();
  final _settingsStore = SettingsStore();
  final _profiles = ProfileStore();

  AppSettings _settings = AppSettings.defaults();
  PpBinaryInfo? _binary;
  ReleaseInfo? _latestRelease;
  ReleaseInfo? _latestGuiRelease;
  List<ProfileRef> _profileList = const [];
  ProfileRef? _selectedProfile;
  PpClientProcess? _clientProcess;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  TunnelState _tunnelState = TunnelState.stopped;
  AppSection _section = AppSection.home;
  bool _loading = true;
  bool _busy = false;
  bool _installing = false;
  bool _updatingClient = false;
  bool _updatingGui = false;
  bool _serverConnected = false;
  bool _stopRequested = false;
  bool _adminElevationStarted = false;
  bool _isTesting = false;
  double? _installProgress;
  double? _guiUpdateProgress;
  String _status = 'Загрузка';
  TestResult? _testResult;
  final List<String> _logs = [];
  final Map<String, ProfileCheckResult> _profileChecks = {};

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _clientProcess?.kill(ProcessSignal.sigterm);
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Bootstrap
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
    });
    await _refreshEverything();
  }

  Future<void> _refreshEverything() async {
    setState(() {
      _loading = true;
      _status = 'Проверка pp-client';
    });

    final binary = await _ppClient.inspect(preferredPath: _settings.binaryPath);
    ReleaseInfo? release;
    ReleaseInfo? guiRelease;
    try {
      release = await _releases.fetchLatestRelease();
    } on Object catch (e) {
      _appendLog('не удалось проверить обновления pp-client: $e');
    }
    try {
      guiRelease = await _releases.fetchLatestGuiRelease();
    } on Object catch (e) {
      _appendLog('не удалось проверить обновления GUI: $e');
    }

    if (!mounted) return;
    setState(() {
      _binary = binary;
      _latestRelease = release;
      _latestGuiRelease = guiRelease;
      _status = binary.installed ? 'Готово' : 'pp-client не найден';
      _loading = false;
    });
    await _loadProfiles(preserveSelection: true);
  }

  // ---------------------------------------------------------------------------
  // Profiles
  // ---------------------------------------------------------------------------

  Future<void> _loadProfiles({bool preserveSelection = false}) async {
    final managed = await _profiles.listManagedProfiles();
    var clientProfiles = <ProfileRef>[];
    final binary = _binary;
    if (binary != null && binary.installed && binary.canListProfiles) {
      try {
        clientProfiles = await _ppClient.listProfiles(binary);
      } on Object catch (e) {
        _appendLog('не удалось получить список профилей: $e');
      }
    }

    final all = [...managed, ...clientProfiles];
    final seenPaths = <String>{};
    final deduplicated = <ProfileRef>[];
    for (final p in all) {
      final key = p.path ?? p.id;
      if (seenPaths.add(key)) deduplicated.add(p);
    }

    ProfileRef? selected;
    if (preserveSelection && _selectedProfile != null) {
      selected =
          deduplicated.where((p) => p.id == _selectedProfile!.id).firstOrNull;
    }
    // Restore from settings if no explicit selection.
    if (selected == null && _settings.selectedProfileId != null) {
      selected = deduplicated
          .where((p) => p.id == _settings.selectedProfileId)
          .firstOrNull;
    }
    selected ??= deduplicated.firstOrNull;

    if (!mounted) return;
    setState(() {
      _profileList = deduplicated;
      _selectedProfile = selected;
      _profileChecks
          .removeWhere((id, _) => !deduplicated.any((p) => p.id == id));
    });
  }

  void _selectProfile(ProfileRef profile) {
    setState(() {
      _selectedProfile = profile;
      _testResult = null;
      _status = 'Профиль: ${profile.name}';
    });
    // Persist selection.
    final next = _settings.copyWith(selectedProfileId: profile.id);
    _settings = next;
    unawaited(_settingsStore.save(next));
  }

  Future<void> _deleteSelected() async {
    final profile = _selectedProfile;
    if (profile == null) return;
    try {
      if (profile.isManaged) {
        await _profiles.deleteManaged(profile);
        _appendLog('профиль удалён: ${profile.name}');
      } else {
        final binary = _binary;
        if (binary == null || !binary.canDeleteProfile) {
          _showSnack('Удаление через pp-client недоступно');
          return;
        }
        final result = await _ppClient.deleteProfile(binary, profile);
        if (!result.ok) {
          throw ProcessException(binary.path!, ['delete', profile.name],
              result.combinedOutput, result.exitCode);
        }
        _appendLog('профиль удалён: ${profile.name}');
      }
      await _loadProfiles();
    } on Object catch (e) {
      _showSnack('Удаление не удалось: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Client lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _startClient() async {
    final binary = _binary;
    final profile = _selectedProfile;
    if (binary == null || !binary.installed || profile == null) {
      _showSnack('pp-client или профиль отсутствует');
      return;
    }
    if (_clientProcess != null) {
      _showSnack('Клиент уже запущен');
      return;
    }

    setState(() {
      _tunnelState = TunnelState.starting;
      _serverConnected = false;
      _stopRequested = false;
      _adminElevationStarted = false;
      _status = 'Запуск';
    });

    try {
      final process = await _ppClient.start(
        binary,
        profile,
        verbose: _settings.verboseLogs,
      );
      _clientProcess = process;
      _appendLog('pp-client start запущен, pid=${process.pid}');

      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleClientLog);
      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _handleClientLog(line, stderr: true));

      unawaited(process.exitCode.then((code) async {
        if (!mounted) return;
        _appendLog('pp-client завершился с кодом $code');
        final wasConnected = _serverConnected;
        final stopRequested = _stopRequested;
        final adminElevationStarted = _adminElevationStarted;
        
        setState(() {
          _clientProcess = null;
          _serverConnected = false;
          _stopRequested = false;
          _adminElevationStarted = false;

          if (stopRequested) {
            _tunnelState = TunnelState.stopped;
            _status = 'Остановлено';
          } else if (Platform.isWindows && adminElevationStarted && code == 0 && !wasConnected) {
            // This was likely the intermediate elevation process finishing,
            // but the actual client should still be running and tracked via the process wrapper.
            // If we are here and not connected, it might mean the elevation process returned 0
            // but we are still waiting for logs or connection.
            _appendLog('процесс повышения прав завершен, ожидание подключения...');
          } else if (wasConnected && code == 0) {
            _tunnelState = TunnelState.stopped;
            _status = 'Отключено';
          } else if (code != 0) {
            _tunnelState = TunnelState.error;
            _status = wasConnected ? 'Соединение потеряно (код $code)' : 'Ошибка запуска (код $code)';
          } else {
            _tunnelState = TunnelState.stopped;
            _status = 'Завершено';
          }
        });

        // Safety cleanup on unexpected crash.
        if (!stopRequested && _binary != null && _binary!.installed) {
          _appendLog('аварийная очистка full-tunnel');
          await _ppClient.fullTunnelDown(_binary!);
        }
      }));

    } on Object catch (e) {
      _appendLog('ошибка запуска: $e');
      setState(() {
        _tunnelState = TunnelState.error;
        _status = 'Запуск не удался';
      });
    }
  }

  Future<void> _stopClient() async {
    if (_tunnelState == TunnelState.stopping) return;

    _appendLog('запрос на остановку туннеля...');
    setState(() {
      _tunnelState = TunnelState.stopping;
      _stopRequested = true;
      _status = 'Остановка туннеля';
    });

    final process = _clientProcess;
    if (process != null) {
      try {
        _appendLog('завершение процесса pid=${process.pid}...');
        await _ppClient
            .stop(process, profile: _selectedProfile, binary: _binary)
            .timeout(const Duration(seconds: 10));
        _appendLog('процесс и сеть очищены');
      } on Object catch (e) {
        _appendLog('ошибка при остановке: $e');
      }
    } else {
      _appendLog('процесс не найден, попытка аварийной очистки сети...');
      if (_binary != null && _binary!.installed) {
        await _ppClient.fullTunnelDown(_binary!);
        _appendLog('сеть очищена (аварийно)');
      }
    }



    // Force UI update if process didn't exit by itself
    if (mounted) {
      setState(() {
        _clientProcess = null;
        _serverConnected = false;
        _tunnelState = TunnelState.stopped;
        _status = 'Остановлено';
      });
    }
  }


  // ---------------------------------------------------------------------------
  // Test
  // ---------------------------------------------------------------------------

  Future<void> _testSelectedProfile() async {
    final binary = _binary;
    final profile = _selectedProfile;
    if (binary == null || !binary.installed || profile == null) {
      _showSnack('Нужен pp-client и выбранный профиль');
      return;
    }
    setState(() {
      _isTesting = true;
    });
    try {
      final result = await _ppClient.testProfile(binary, profile);
      if (!mounted) return;
      setState(() {
        _testResult = result;
      });
      _appendLog('test ${profile.name}: ${result.summary}');
      _showSnack('${profile.name}: ${result.summary}');
    } on Object catch (e) {
      _appendLog('ошибка теста: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Install / Update
  // ---------------------------------------------------------------------------

  Future<void> _installLatestClient() async {
    final release = _latestRelease;
    final asset = release?.assetForCurrentPlatform();
    if (release == null || asset == null) {
      _showSnack('Нет pp-client для этой платформы');
      return;
    }
    setState(() {
      _installing = true;
      _installProgress = null;
      _status = 'Установка ${release.tagName}';
    });
    try {
      final file =
          await _installer.installAsset(asset, onProgress: (received, total) {
        if (!mounted || total == null || total == 0) return;
        setState(() {
          _installProgress = received / total;
        });
      });
      final nextSettings = _settings.copyWith(binaryPath: file.path);
      await _settingsStore.save(nextSettings);
      setState(() {
        _settings = nextSettings;
      });
      _appendLog('pp-client установлен в ${file.path}');
      await _refreshEverything();
    } on Object catch (e) {
      _showSnack('Установка не удалась: $e');
      _appendLog('ошибка установки: $e');
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _installProgress = null;
        });
      }
    }
  }

  Future<void> _updateClient() async {
    final binary = _binary;
    if (binary == null || !binary.installed) {
      _showSnack('pp-client не установлен');
      return;
    }
    setState(() {
      _updatingClient = true;
      _installProgress = null;
      _status = 'Обновление pp-client';
    });
    try {
      final release = _latestRelease;
      final asset = release?.assetForCurrentPlatform();
      if (release != null && asset != null) {
        final file =
            await _installer.installAsset(asset, onProgress: (received, total) {
          if (!mounted || total == null || total == 0) return;
          setState(() {
            _installProgress = received / total;
          });
        });
        final nextSettings = _settings.copyWith(binaryPath: file.path);
        await _settingsStore.save(nextSettings);
        if (!mounted) return;
        setState(() {
          _settings = nextSettings;
        });
        _appendLog('pp-client обновлён в ${file.path}');
        await _refreshEverything();
      } else {
        _appendLog('ошибка: не найден подходящий файл для обновления в релизе GitHub');
        _showSnack('Файл обновления не найден в репозитории');
      }
    } on Object catch (e) {
      _appendLog('ошибка обновления: $e');
      _showSnack('Ошибка: $e');
    } finally {
      if (mounted) {
        setState(() {
          _updatingClient = false;
          _installProgress = null;
          _status = 'Готово';
        });
      }
    }
  }

  Future<void> _updateGui() async {
    final release = _latestGuiRelease;
    final asset = release?.assetForCurrentGuiPlatform();
    if (release == null || asset == null) {
      _showSnack('Нет пакета обновления GUI для этой платформы');
      return;
    }
    setState(() {
      _updatingGui = true;
      _guiUpdateProgress = null;
      _status = 'Обновление GUI ${release.tagName}';
    });
    try {
      await _guiUpdater.applyUpdate(
        asset,
        onProgress: (received, total) {
          if (!mounted || total == null || total == 0) return;
          setState(() {
            _guiUpdateProgress = received / total;
          });
        },
      );
      // applyUpdate calls exit(0) on success — this line is unreachable.
    } on Object catch (e) {
      _appendLog('ошибка обновления GUI: $e');
      _showSnack('Ошибка обновления GUI: $e');
    } finally {
      if (mounted) {
        setState(() {
          _updatingGui = false;
          _guiUpdateProgress = null;
          _status = 'Готово';
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Log handling
  // ---------------------------------------------------------------------------

  void _handleClientLog(String line, {bool stderr = false}) {
    final text = stderr ? 'stderr: $line' : line;
    _appendLog(text);
    final normalized = line.toLowerCase();
    if (!mounted) return;
    if (Platform.isWindows &&
        normalized.contains('requesting administrator privileges')) {
      setState(() {
        _adminElevationStarted = true;
        _status = 'Подтвердите запрос прав администратора';
      });
      return;
    }
    if (normalized.contains(
        'browser noise pre-connect scenario completed successfully')) {
      setState(() {
        _serverConnected = true;
        _tunnelState = TunnelState.running;
        _status = 'Полный туннель подключён';
      });
    } else if (normalized.contains('transparent proxy server started')) {
      setState(() {
        _status = 'Полный туннель запущен';
      });
    } else if (normalized.contains('socks5 server started') ||
        normalized.contains('http proxy server started')) {
      setState(() {
        _status = 'Локальный прокси запущен, подключение к серверу';
      });
    } else if (normalized.contains('failed') || normalized.contains('error')) {
      if (normalized.contains('bind: only one usage of each socket address') ||
          normalized.contains('address already in use')) {
        setState(() {
          _status = 'Ошибка: Порт уже занят другим приложением';
        });
        return;
      }
      setState(() {
        _status = _serverConnected
            ? 'Клиент сообщил об ошибке'
            : 'Подключение к серверу продолжается';
      });
    }


  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      final ts = TimeOfDay.now().format(context);
      _logs.add('[$ts] $line');
      if (_logs.length > 800) _logs.removeRange(0, _logs.length - 800);
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  bool get _hasUpdateBadge {
    final clientUpdate =
        _latestRelease != null && _latestRelease!.isNewerThan(_binary?.version);
    final guiUpdate =
        _latestGuiRelease != null && _latestGuiRelease!.isNewerThan(appVersion);
    return clientUpdate || guiUpdate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PP GUI',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _refreshEverything,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: IndexedStack(
                    index: _section.index,
                    children: [
                      HomeScreen(
                        tunnelState: _tunnelState,
                        isProcessActive: _clientProcess != null,
                        isConnected: _clientProcess != null && _serverConnected,
                        binary: _binary,
                        selectedProfile: _selectedProfile,
                        profileListEmpty: _profileList.isEmpty,
                        status: _status,
                        testResult: _testResult,
                        isTesting: _isTesting,
                        onStart: _startClient,
                        onStop: _stopClient,
                        onTest: _testSelectedProfile,
                        onSwitchToConfigs: () =>
                            setState(() => _section = AppSection.configs),
                      ),
                      ConfigsScreen(
                        controller: ConfigsController(
                          profileList: _profileList,
                          selectedProfile: _selectedProfile,
                          binary: _binary,
                          busy: _busy,
                          profileChecks: _profileChecks,
                          ppClient: _ppClient,
                          profiles: _profiles,
                          selectProfile: _selectProfile,
                          deleteSelected: _deleteSelected,
                          refreshProfiles: () async {
                            await _loadProfiles(preserveSelection: true);
                            _showSnack('Список обновлён');
                          },
                          setBusy: (v) => setState(() => _busy = v),
                          appendLog: _appendLog,
                          showSnack: _showSnack,
                          onProfileSaved: () => _loadProfiles(),
                        ),
                      ),
                      LogsScreen(
                        logs: _logs,
                        onClear: () => setState(_logs.clear),
                      ),
                      AboutScreen(
                        binary: _binary,
                        latestClientRelease: _latestRelease,
                        latestGuiRelease: _latestGuiRelease,
                        installing: _installing,
                        installProgress: _installProgress,
                        updatingClient: _updatingClient,
                        updatingGui: _updatingGui,
                        guiUpdateProgress: _guiUpdateProgress,
                        onInstallClient: _installLatestClient,
                        onUpdateClient: _updateClient,
                        onUpdateGui: _updateGui,
                        onRefresh: _refreshEverything,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section.index,
        onDestinationSelected: (index) {
          setState(() {
            _section = AppSection.values[index];
          });
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.power_settings_new), label: 'Главная'),
          const NavigationDestination(
              icon: Icon(Icons.dns_outlined), label: 'Конфиги'),
          const NavigationDestination(icon: Icon(Icons.subject), label: 'Логи'),
          NavigationDestination(
            icon: _hasUpdateBadge
                ? const Badge(smallSize: 8, child: Icon(Icons.info_outline))
                : const Icon(Icons.info_outline),
            label: 'О программе',
          ),
        ],
      ),
    );
  }
}
