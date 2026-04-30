import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../models/app_models.dart';
import '../services/github_release_service.dart';
import '../services/pp_client_service.dart';
import '../services/profile_store.dart';
import '../services/settings_store.dart';

enum ConfigEditorMode { form, json }

enum AppSection { home, configs, logs, settings }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ppClient = PpClientService();
  final _releases = GitHubReleaseService();
  final _installer = PpClientInstaller();
  final _settingsStore = SettingsStore();
  final _profiles = ProfileStore();

  final _profileName = TextEditingController();
  final _serverAddress = TextEditingController();
  final _serverDomain = TextEditingController();
  final _noisePublicKey = TextEditingController();
  final _psk = TextEditingController();
  final _grpcPath = TextEditingController();
  final _socks5Listen = TextEditingController();
  final _httpProxyListen = TextEditingController();
  final _transparentListen = TextEditingController();
  final _logLevel = TextEditingController();
  final _tlsFingerprint = TextEditingController();
  final _keepalive = TextEditingController();
  final _rawJson = TextEditingController();
  final _uri = TextEditingController();
  final _binaryPath = TextEditingController();
  final _fullTunnelOwner = TextEditingController();
  final _jsonPath = TextEditingController();

  AppSettings _settings = AppSettings.defaults();
  PpBinaryInfo? _binary;
  ReleaseInfo? _latestRelease;
  List<ProfileRef> _profileList = const [];
  ProfileRef? _selectedProfile;
  Process? _clientProcess;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  TunnelState _tunnelState = TunnelState.stopped;
  ConfigEditorMode _editorMode = ConfigEditorMode.form;
  AppSection _section = AppSection.home;
  bool _loading = true;
  bool _busy = false;
  bool _shaperEnabled = true;
  bool _fullTunnelRequested = false;
  bool _fullTunnelActive = false;
  bool _installing = false;
  bool _verboseLogs = false;
  bool _serverConnected = false;
  bool _stopRequested = false;
  bool _syncingEditors = false;
  double? _installProgress;
  String _status = 'Загрузка';
  final List<String> _logs = [];
  final Map<String, _ProfileCheckResult> _profileChecks = {};

  @override
  void initState() {
    super.initState();
    _installEditorSync();
    _applyDraft(ClientConfigDraft.empty());
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _clientProcess?.kill(ProcessSignal.sigterm);
    for (final controller in [
      _profileName,
      _serverAddress,
      _serverDomain,
      _noisePublicKey,
      _psk,
      _grpcPath,
      _socks5Listen,
      _httpProxyListen,
      _transparentListen,
      _logLevel,
      _tlsFingerprint,
      _keepalive,
      _rawJson,
      _uri,
      _binaryPath,
      _fullTunnelOwner,
      _jsonPath,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final settings = await _settingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _binaryPath.text = settings.binaryPath ?? '';
      _fullTunnelOwner.text = settings.fullTunnelOwner;
      _verboseLogs = settings.verboseLogs;
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
    try {
      release = await _releases.fetchLatestRelease();
    } on Object catch (error) {
      _appendLog('не удалось проверить обновления: $error');
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _binary = binary;
      _latestRelease = release;
      _status = binary.installed ? 'Готово' : 'pp-client не найден';
      _loading = false;
    });
    await _loadProfiles(preserveSelection: true);
  }

  Future<void> _loadProfiles({bool preserveSelection = false}) async {
    final managed = await _profiles.listManagedProfiles();
    var clientProfiles = <ProfileRef>[];
    final binary = _binary;
    if (binary != null && binary.installed && binary.canListProfiles) {
      try {
        clientProfiles = await _ppClient.listProfiles(binary);
      } on Object catch (error) {
        _appendLog('не удалось получить список профилей: $error');
      }
    }

    final all = [...managed, ...clientProfiles];
    ProfileRef? selected;
    if (preserveSelection && _selectedProfile != null) {
      selected = all
          .where((profile) => profile.id == _selectedProfile!.id)
          .firstOrNull;
    }
    selected ??= all.firstOrNull;

    if (!mounted) {
      return;
    }
    setState(() {
      _profileList = all;
      _selectedProfile = selected;
      _profileChecks
          .removeWhere((id, _) => !all.any((profile) => profile.id == id));
    });
    if (selected != null) {
      await _selectProfile(selected);
    }
  }

  Future<void> _selectProfile(ProfileRef profile) async {
    setState(() {
      _selectedProfile = profile;
      _status = 'Профиль: ${profile.name}';
    });
    if (profile.path == null) {
      setState(() {
        _rawJson.text =
            const JsonEncoder.withIndent('  ').convert(profile.metadata);
        try {
          _applyDraft(ClientConfigDraft.fromJson(profile.metadata),
              updateJson: false);
        } on Object {
          // Some pp-client profile entries contain only metadata.
        }
      });
      return;
    }
    try {
      final raw = await _profiles.readRawJson(profile);
      final draft = await _profiles.readDraft(profile);
      if (!mounted) {
        return;
      }
      setState(() {
        _rawJson.text = _prettyJson(raw);
        _applyDraft(draft, updateJson: false);
      });
    } on Object catch (error) {
      _appendLog('не удалось прочитать профиль: $error');
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _busy = true;
      _status = 'Сохранение профиля';
    });
    try {
      ProfileRef saved;
      if (_editorMode == ConfigEditorMode.json) {
        saved = await _profiles.saveJson(_rawJson.text,
            fallbackName: _profileName.text);
      } else {
        final draft = _draftFromFields();
        saved = await _profiles.saveDraft(draft);
        _rawJson.text = draft.toPrettyJson();
      }
      _appendLog('профиль сохранён: ${saved.name}');
      await _loadProfiles();
      await _selectProfile(saved);
    } on Object catch (error) {
      _showSnack('Не удалось сохранить: $error');
      _appendLog('ошибка сохранения: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Готово';
        });
      }
    }
  }

  Future<void> _validateSelected() async {
    final binary = _binary;
    final profile = _selectedProfile;
    setState(() {
      _busy = true;
      _status = 'Проверка конфига и ping';
    });

    var configOk = false;
    var pingOk = false;
    var pingSummary = 'ошибка';
    try {
      if (binary != null &&
          binary.installed &&
          binary.canValidate &&
          profile?.path != null) {
        final result = await _ppClient.validateConfig(binary, profile!.path!);
        configOk = result.ok;
        _appendLog(result.ok
            ? 'конфиг корректен'
            : 'конфиг не прошёл проверку: ${result.combinedOutput}');
      } else {
        _appendLog(
            'проверка конфига недоступна: нужен сохранённый профиль и pp-client с validate-config');
      }

      final host = _pingHostFromAddress(_serverAddress.text);
      if (host == null) {
        _appendLog('ping недоступен: в конфиге не указан адрес сервера');
      } else {
        final result = await _ppClient.pingHost(host);
        pingOk = result.ok;
        final latency = _pingLatency(result.combinedOutput);
        pingSummary =
            latency == null ? (pingOk ? 'OK' : 'ошибка') : '${latency} мс';
        _appendLog(result.ok
            ? 'ping $host: $pingSummary'
            : 'ping $host не прошёл: ${result.combinedOutput}');
      }

      final message =
          'Конфиг: ${configOk ? 'OK' : 'ошибка'}, ping: $pingSummary';
      _showSnack(message);
      if (mounted) {
        setState(() {
          if (profile != null) {
            _profileChecks[profile.id] = _ProfileCheckResult(
                configOk: configOk, pingOk: pingOk, pingLabel: pingSummary);
          }
          _status =
              configOk && pingOk ? 'Ping $pingSummary' : 'Проверьте конфиг';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _validateProfile(ProfileRef profile) async {
    setState(() {
      _busy = true;
      _status = 'Проверка ${profile.name}';
    });
    try {
      final result = await _checkProfile(profile);
      if (!mounted) {
        return;
      }
      setState(() {
        _profileChecks[profile.id] = result;
        _status = result.configOk && result.pingOk
            ? '${profile.name}: ping ${result.pingLabel}'
            : '${profile.name}: проверьте конфиг';
      });
      _appendLog(
          '${profile.name}: конфиг ${result.configOk ? 'OK' : 'ошибка'}, ping ${result.pingLabel}');
      _showSnack('${profile.name}: ping ${result.pingLabel}');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _validateAllProfiles() async {
    if (_profileList.isEmpty) {
      _showSnack('Нет конфигов для проверки');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Проверка всех конфигов';
    });
    var okCount = 0;
    try {
      for (final profile in _profileList) {
        final result = await _checkProfile(profile);
        if (!mounted) {
          return;
        }
        setState(() {
          _profileChecks[profile.id] = result;
        });
        if (result.configOk && result.pingOk) {
          okCount += 1;
        }
        _appendLog(
            '${profile.name}: конфиг ${result.configOk ? 'OK' : 'ошибка'}, ping ${result.pingLabel}');
      }
      _showSnack('Проверено: $okCount/${_profileList.length} OK');
      if (mounted) {
        setState(() {
          _status = 'Проверено: $okCount/${_profileList.length} OK';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<_ProfileCheckResult> _checkProfile(ProfileRef profile) async {
    final binary = _binary;
    var configOk = false;
    var pingOk = false;
    var pingLabel = 'ошибка';

    if (binary != null &&
        binary.installed &&
        binary.canValidate &&
        profile.path != null) {
      final result = await _ppClient.validateConfig(binary, profile.path!);
      configOk = result.ok;
    }

    try {
      final draft = profile.path == null
          ? ClientConfigDraft.fromJson(profile.metadata)
          : await _profiles.readDraft(profile);
      final host = _pingHostFromAddress(draft.serverAddress);
      if (host != null) {
        final ping = await _ppClient.pingHost(host);
        pingOk = ping.ok;
        final latency = _pingLatency(ping.combinedOutput);
        pingLabel =
            latency == null ? (pingOk ? 'OK' : 'ошибка') : '${latency} мс';
      }
    } on Object catch (error) {
      pingLabel = 'ошибка: $error';
    }

    return _ProfileCheckResult(
        configOk: configOk, pingOk: pingOk, pingLabel: pingLabel);
  }

  String? _pingHostFromAddress(String address) {
    final value = address.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      return end > 1 ? value.substring(1, end) : null;
    }
    return value.split(':').first.trim().isEmpty
        ? null
        : value.split(':').first.trim();
  }

  String? _pingLatency(String output) {
    final normalized = output.replaceAll(',', '.');
    final match = RegExp(r'(?:time|время)[=<]?\s*([\d.]+)\s*(?:ms|мс)',
            caseSensitive: false)
        .firstMatch(normalized);
    if (match == null) {
      return null;
    }
    final value = double.tryParse(match.group(1)!);
    if (value == null) {
      return null;
    }
    return value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }

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
      _status = 'Подключение к серверу';
    });

    try {
      final transparentListen =
          _fullTunnelRequested ? _transparentListen.text.trim() : null;
      final process = await _ppClient.start(
        binary,
        profile,
        verbose: _verboseLogs,
        transparentListen: transparentListen,
      );
      _clientProcess = process;
      _appendLog('pp-client запущен, pid=${process.pid}');

      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_handleClientLog);
      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleClientLog(line, stderr: true);
      });
      unawaited(process.exitCode.then((code) {
        if (!mounted) {
          return;
        }
        _appendLog('pp-client завершился с кодом $code');
        setState(() {
          _clientProcess = null;
          if (_stopRequested) {
            _tunnelState = TunnelState.stopped;
            _status = 'Остановлено';
          } else if (_serverConnected && code == 0) {
            _tunnelState = TunnelState.stopped;
            _status = 'Отключено';
          } else {
            _tunnelState = TunnelState.error;
            _status = 'Не удалось подключиться к серверу';
          }
          _serverConnected = false;
          _stopRequested = false;
        });
      }));

      if (_fullTunnelRequested) {
        await _enableFullTunnel();
      }
    } on Object catch (error) {
      _appendLog('ошибка запуска: $error');
      setState(() {
        _tunnelState = TunnelState.error;
        _status = 'Запуск не удался';
      });
    }
  }

  Future<void> _stopClient() async {
    final binary = _binary;
    setState(() {
      _tunnelState = TunnelState.stopping;
      _stopRequested = true;
      _status = 'Остановка туннеля';
    });
    if (_fullTunnelActive && binary != null && binary.installed) {
      final result = await _ppClient.fullTunnelDown(binary);
      _appendLog(result.ok
          ? 'Полный туннель отключён'
          : 'не удалось отключить полный туннель: ${result.combinedOutput}');
      _fullTunnelActive = false;
    }
    _clientProcess?.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted && _clientProcess == null) {
      setState(() {
        _tunnelState = TunnelState.stopped;
        _status = 'Остановлено';
      });
    }
  }

  Future<void> _enableFullTunnel() async {
    final binary = _binary;
    final profile = _selectedProfile;
    if (binary == null ||
        !binary.installed ||
        profile == null ||
        !binary.canFullTunnel) {
      _appendLog('Полный туннель недоступен в этой версии pp-client');
      return;
    }
    final result = await _ppClient.fullTunnelUp(
      binary,
      profile,
      transparentListen: _transparentListen.text,
      owner: _fullTunnelOwner.text,
    );
    if (result.ok) {
      setState(() {
        _fullTunnelActive = true;
      });
      _appendLog('Полный туннель включён');
    } else {
      _appendLog(
          'не удалось включить полный туннель: ${result.combinedOutput}');
      _showSnack('Не удалось включить полный туннель');
      if (mounted) {
        setState(() {
          _tunnelState = TunnelState.error;
          _status = 'Полный туннель не включён';
        });
      }
    }
  }

  Future<void> _importUri() async {
    final raw = _uri.text.trim();
    if (raw.isEmpty) {
      return;
    }
    final binary = _binary;
    try {
      if (binary != null && binary.installed && binary.canImportUri) {
        final result = await _ppClient.importUri(binary, raw);
        if (!result.ok) {
          throw ProcessException(
              binary.path!, ['import'], result.combinedOutput, result.exitCode);
        }
        _appendLog('URI импортирован через pp-client');
      } else {
        final draft = ClientConfigDraft.fromPpfUri(raw);
        final saved = await _profiles.saveDraft(draft);
        _appendLog('URI импортирован как управляемый профиль ${saved.name}');
      }
      _uri.clear();
      await _loadProfiles();
    } on Object catch (error) {
      _showSnack('Импорт не удался: $error');
      _appendLog('ошибка импорта: $error');
    }
  }

  Future<void> _importJsonFile() async {
    final path = _jsonPath.text.trim();
    if (path.isEmpty) {
      return;
    }
    try {
      final raw = await File(path).readAsString();
      final saved = await _profiles.saveJson(raw);
      _appendLog('JSON импортирован: ${saved.name}');
      _jsonPath.clear();
      await _loadProfiles();
      await _selectProfile(saved);
    } on Object catch (error) {
      _showSnack('Импорт JSON не удался: $error');
      _appendLog('ошибка импорта JSON: $error');
    }
  }

  Future<void> _pickAndImportJsonFile() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
              label: 'JSON',
              extensions: ['json'],
              mimeTypes: ['application/json']),
        ],
      );
      if (file == null) {
        return;
      }
      _jsonPath.text = file.path;
      await _importJsonFile();
    } on Object catch (error) {
      _showSnack('Не удалось открыть файл: $error');
      _appendLog('ошибка выбора JSON-файла: $error');
    }
  }

  Future<void> _importJsonFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim();
      if (raw == null || raw.isEmpty) {
        _showSnack('Буфер обмена пуст');
        return;
      }
      if (raw.startsWith('ppf://')) {
        _uri.text = raw;
        await _importUri();
        return;
      }
      final saved = await _profiles.saveJson(raw);
      _appendLog('JSON из буфера импортирован: ${saved.name}');
      await _loadProfiles();
      await _selectProfile(saved);
    } on Object catch (error) {
      _showSnack('Импорт из буфера не удался: $error');
      _appendLog('ошибка импорта из буфера: $error');
    }
  }

  Future<void> _deleteSelected() async {
    final profile = _selectedProfile;
    if (profile == null) {
      return;
    }
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
        _appendLog('профиль pp-client удалён: ${profile.name}');
      }
      await _loadProfiles();
    } on Object catch (error) {
      _showSnack('Удаление не удалось: $error');
      _appendLog('ошибка удаления: $error');
    }
  }

  Future<void> _installLatestClient() async {
    final release = _latestRelease;
    final asset = release?.assetForCurrentPlatform();
    if (release == null || asset == null) {
      _showSnack('В последнем релизе нет pp-client для этой платформы');
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
        if (!mounted || total == null || total == 0) {
          return;
        }
        setState(() {
          _installProgress = received / total;
        });
      });
      final nextSettings = _settings.copyWith(binaryPath: file.path);
      await _settingsStore.save(nextSettings);
      setState(() {
        _settings = nextSettings;
        _binaryPath.text = file.path;
      });
      _appendLog('pp-client установлен в ${file.path}');
      await _refreshEverything();
    } on Object catch (error) {
      _showSnack('Установка не удалась: $error');
      _appendLog('ошибка установки: $error');
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _installProgress = null;
        });
      }
    }
  }

  void _newProfile() {
    final draft = ClientConfigDraft.empty();
    setState(() {
      _selectedProfile = null;
      _editorMode = ConfigEditorMode.form;
      _applyDraft(draft);
      _status = 'Новый профиль';
    });
  }

  void _handleClientLog(String line, {bool stderr = false}) {
    final text = stderr ? 'поток ошибок: $line' : line;
    _appendLog(text);
    final normalized = line.toLowerCase();
    if (!mounted) {
      return;
    }
    if (normalized.contains(
        'browser noise pre-connect scenario completed successfully')) {
      setState(() {
        _serverConnected = true;
        _tunnelState = TunnelState.running;
        _status = 'Подключено к серверу';
      });
    } else if (normalized.contains('socks5 server started') ||
        normalized.contains('http proxy server started')) {
      setState(() {
        _status = 'Локальный прокси запущен, подключение к серверу';
      });
    } else if (normalized.contains('failed') || normalized.contains('error')) {
      setState(() {
        _status = _serverConnected
            ? 'Клиент сообщил об ошибке'
            : 'Подключение к серверу продолжается';
      });
    }
  }

  void _appendLog(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      final timestamp = TimeOfDay.now().format(context);
      _logs.add('[$timestamp] $line');
      if (_logs.length > 800) {
        _logs.removeRange(0, _logs.length - 800);
      }
    });
  }

  void _installEditorSync() {
    for (final controller in _formControllers) {
      controller.addListener(_syncJsonFromForm);
    }
    _rawJson.addListener(_syncFormFromJson);
  }

  List<TextEditingController> get _formControllers => [
        _profileName,
        _serverAddress,
        _serverDomain,
        _noisePublicKey,
        _psk,
        _grpcPath,
        _socks5Listen,
        _httpProxyListen,
        _transparentListen,
        _logLevel,
        _tlsFingerprint,
        _keepalive,
      ];

  void _syncJsonFromForm() {
    if (_syncingEditors) {
      return;
    }
    _syncEditorText(() {
      _rawJson.text = _draftFromFields().toPrettyJson();
    });
  }

  void _syncFormFromJson() {
    if (_syncingEditors) {
      return;
    }
    try {
      final draft = ClientConfigDraft.fromJson(jsonDecode(_rawJson.text));
      _syncEditorText(() {
        _applyDraft(draft, updateJson: false);
      });
    } on Object {
      // Keep invalid JSON editable; it will be parsed again after the next text change.
    }
  }

  void _syncEditorText(VoidCallback update) {
    _syncingEditors = true;
    try {
      update();
    } finally {
      _syncingEditors = false;
    }
  }

  void _applyDraft(ClientConfigDraft draft, {bool updateJson = true}) {
    _syncEditorText(() {
      _profileName.text = draft.profileName;
      _serverAddress.text = draft.serverAddress;
      _serverDomain.text = draft.serverDomain;
      _noisePublicKey.text = draft.noisePublicKey;
      _psk.text = draft.psk;
      _grpcPath.text = draft.grpcPath;
      _socks5Listen.text = draft.socks5Listen;
      _httpProxyListen.text = draft.httpProxyListen;
      _transparentListen.text = draft.transparentListen;
      _logLevel.text = draft.logLevel;
      _tlsFingerprint.text = draft.tlsFingerprint;
      _keepalive.text = draft.keepaliveSeconds.toString();
      _shaperEnabled = draft.shaperEnabled;
      if (updateJson) {
        _rawJson.text = draft.toPrettyJson();
      }
    });
  }

  ClientConfigDraft _draftFromFields() {
    return ClientConfigDraft(
      profileName: _profileName.text,
      serverAddress: _serverAddress.text,
      serverDomain: _serverDomain.text,
      noisePublicKey: _noisePublicKey.text,
      psk: _psk.text,
      grpcPath: _grpcPath.text,
      socks5Listen: _socks5Listen.text,
      httpProxyListen: _httpProxyListen.text,
      transparentListen: _transparentListen.text,
      logLevel: _logLevel.text,
      shaperEnabled: _shaperEnabled,
      keepaliveSeconds: int.tryParse(_keepalive.text) ?? 25,
      tlsFingerprint: _tlsFingerprint.text,
    );
  }

  String _prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } on Object {
      return raw;
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PP'),
        centerTitle: true,
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: _sectionBody(),
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
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.power_settings_new), label: 'Главная'),
          NavigationDestination(
              icon: Icon(Icons.dns_outlined), label: 'Конфиги'),
          NavigationDestination(icon: Icon(Icons.subject), label: 'Логи'),
          NavigationDestination(
              icon: Icon(Icons.info_outline), label: 'О программе'),
        ],
      ),
    );
  }

  Widget _sectionBody() {
    return switch (_section) {
      AppSection.home => _homeScreen(),
      AppSection.configs => _configsScreen(),
      AppSection.logs => _logsScreen(),
      AppSection.settings => _settingsScreen(),
    };
  }

  Widget _screen({required List<Widget> children}) {
    return ListView(
      key: ValueKey(_section),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: children,
    );
  }

  Widget _homeScreen() {
    final processActive = _clientProcess != null;
    final connected = processActive && _serverConnected;
    final canStart = _binary?.installed == true &&
        _selectedProfile != null &&
        !processActive;
    final primaryAction =
        processActive || _fullTunnelActive ? _stopClient : _startClient;
    final primaryEnabled = processActive || _fullTunnelActive || canStart;
    return _screen(
      children: [
        _heroPanel(
          connected: connected,
          processActive: processActive,
          enabled: primaryEnabled,
          onPressed: primaryEnabled ? primaryAction : null,
        ),
        const SizedBox(height: 12),
        _panel(
          title: 'Активный конфиг',
          trailing: TextButton.icon(
            onPressed: () {
              setState(() {
                _section = AppSection.configs;
              });
            },
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Сменить'),
          ),
          child: _selectedProfile == null
              ? const Text(
                  'Выберите или импортируйте конфиг на странице конфигов.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _selectedProfile!.name,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedProfile!.isManaged
                          ? 'Профиль приложения'
                          : 'Профиль pp-client',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xff64706d)),
                    ),
                    if (_selectedProfile!.path != null) ...[
                      const SizedBox(height: 10),
                      SelectableText(_selectedProfile!.path!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _panel(
          title: 'Режим подключения',
          trailing: _statusChip(_statusLabel(), _statusColor()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _infoRow('SOCKS5', _socks5Listen.text),
              _infoRow('HTTP', _httpProxyListen.text),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.swap_horiz),
                      label: Text('Прокси')),
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.route_outlined),
                      label: Text('Туннель')),
                ],
                selected: {_fullTunnelRequested},
                onSelectionChanged: _binary?.canFullTunnel == true
                    ? (selection) {
                        setState(() {
                          _fullTunnelRequested = selection.first;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _validateSelected,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Проверить конфиг и ping'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroPanel({
    required bool connected,
    required bool processActive,
    required bool enabled,
    required VoidCallback? onPressed,
  }) {
    final color =
        connected ? Colors.green : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffd7ddda)),
      ),
      child: Column(
        children: [
          Text(
            _connectionTitle(connected, processActive),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _connectionSubtitle(connected, processActive),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xff64706d)),
          ),
          const SizedBox(height: 18),
          SizedBox.square(
            dimension: 148,
            child: FilledButton(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: color,
                disabledBackgroundColor: const Color(0xffd4dbd8),
              ),
              child: Icon(processActive ? Icons.stop : Icons.power_settings_new,
                  size: 58),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            processActive ? 'Остановить' : 'Подключить',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  String _connectionTitle(bool connected, bool processActive) {
    if (connected) {
      return 'PP подключён';
    }
    if (processActive) {
      return 'Подключение к серверу';
    }
    if (_profileList.isEmpty) {
      return 'Добавьте конфиг';
    }
    if (_selectedProfile == null) {
      return 'Выберите конфиг';
    }
    if (_binary?.installed != true) {
      return 'Установите pp-client';
    }
    return 'PP готов к подключению';
  }

  String _connectionSubtitle(bool connected, bool processActive) {
    if (connected || processActive) {
      return _status;
    }
    if (_profileList.isEmpty) {
      return 'Нет сохранённых конфигов. Импортируйте JSON или вставьте ppf:// URI.';
    }
    if (_selectedProfile == null) {
      return 'Конфиг есть, но активный профиль не выбран.';
    }
    if (_binary?.installed != true) {
      return 'Для подключения нужен установленный pp-client.';
    }
    return _status;
  }

  Widget _configsScreen() {
    return _screen(
      children: [
        _profilePanel(),
      ],
    );
  }

  Widget _logsScreen() {
    return _screen(
      children: [
        SizedBox(height: 560, child: _logPanel()),
      ],
    );
  }

  Widget _settingsScreen() {
    return _screen(
      children: [
        _aboutPanel(),
        const SizedBox(height: 12),
        _updatePanel(),
      ],
    );
  }

  Widget _aboutPanel() {
    return _panel(
      title: 'О программе',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PP',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Эталонное GUI-приложение для протокола PP. Оно нужно, чтобы проверять возможности протокола в одном компактном клиенте: конфиги, импорт URI, локальные прокси, полный туннель и диагностику.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xff64706d), height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _updatePanel() {
    final binary = _binary;
    final latest = _latestRelease;
    final updateAvailable =
        latest != null && latest.isNewerThan(binary?.version);
    final stateText = binary?.installed != true
        ? 'Не установлен'
        : updateAvailable
            ? 'Есть обновление'
            : 'Актуально';
    final stateColor = binary?.installed != true
        ? Colors.red
        : updateAvailable
            ? Colors.orange
            : Colors.green;
    return _panel(
      title: 'Обновление',
      trailing: _statusChip(stateText, stateColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _infoRow('pp-client',
              binary?.installed == true ? 'доступен' : 'не найден'),
          _infoRow('Текущая', binary?.displayVersion ?? 'не установлена'),
          _infoRow('Последняя', latest?.tagName ?? 'неизвестно'),
          if (binary?.path != null) _infoRow('Путь', binary!.path!),
          if (binary?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(binary!.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (_installing) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _installProgress),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _installing ||
                          latest == null ||
                          (!updateAvailable && binary?.installed == true)
                      ? null
                      : _installLatestClient,
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(
                      binary?.installed == true ? 'Обновить' : 'Установить'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Обновить',
                onPressed: _refreshEverything,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profilePanel() {
    return _panel(
      title: 'Конфиги',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Проверить все конфиги',
            onPressed: _busy ? null : _validateAllProfiles,
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: 'Добавить конфиг',
            onPressed: _showAddConfigSheet,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_profileList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Нет конфигов')),
            )
          else
            ..._profileList.map(_profileTile),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectedProfile == null ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить выбранный'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Обновить конфиги',
                onPressed: () => _loadProfiles(preserveSelection: true),
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileTile(ProfileRef profile) {
    final selected = profile.id == _selectedProfile?.id;
    final protocol = _profileProtocol(profile);
    final check = _profileChecks[profile.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
              : const Color(0xfff7f9f8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.35)
                  : const Color(0xffe2e7e4)),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(profile.isManaged
              ? Icons.description_outlined
              : Icons.storage_outlined),
          title:
              Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              check == null ? protocol : '$protocol · ping ${check.pingLabel}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (check != null) ...[
                _statusChip(
                  check.pingLabel,
                  check.configOk && check.pingOk ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: 'Проверить конфиг',
                onPressed: _busy ? null : () => _validateProfile(profile),
                icon: const Icon(Icons.task_alt_outlined),
              ),
              IconButton(
                tooltip: 'Редактировать',
                onPressed: () => _showProfileDetails(profile),
                icon: const Icon(Icons.edit_outlined),
              ),
              if (selected) const Icon(Icons.check_circle),
            ],
          ),
          onTap: () {
            unawaited(_selectProfile(profile));
          },
        ),
      ),
    );
  }

  String _profileProtocol(ProfileRef profile) {
    final raw = (profile.metadata['protocol'] ??
            profile.metadata['type'] ??
            profile.metadata['scheme'] ??
            '')
        .toString()
        .toLowerCase();
    if (raw == 'ppf' || raw == 'pp-fallback' || raw == 'pp_fallback') {
      return 'PP-Fallback';
    }
    return 'PP-Fallback';
  }

  Future<void> _showProfileDetails(ProfileRef profile) async {
    await _selectProfile(profile);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child:
                        _statusChip(_profileProtocol(profile), Colors.blueGrey),
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: _editorPanel()),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  unawaited(_saveProfile());
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Сохранить'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Проверить',
                        onPressed: _busy ? null : _validateSelected,
                        icon: const Icon(Icons.task_alt_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddConfigSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('Импорт файла JSON'),
                  subtitle: const Text('Открыть проводник'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_pickAndImportJsonFile());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.content_paste),
                  title: const Text('Импорт из буфера'),
                  subtitle: const Text('JSON или ppf:// URI'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_importJsonFromClipboard());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('Добавить вручную'),
                  subtitle: const Text('Открыть редактор нового конфига'),
                  onTap: () {
                    Navigator.pop(context);
                    _showManualConfigDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showManualConfigDialog() async {
    _newProfile();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog.fullscreen(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Новый конфиг',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Закрыть',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: _editorPanel()),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  unawaited(_saveProfile());
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Сохранить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _editorPanel() {
    return _panel(
      title: 'Конфигурация',
      expandChild: true,
      trailing: SegmentedButton<ConfigEditorMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
              value: ConfigEditorMode.form,
              icon: Icon(Icons.tune),
              label: Text('Форма')),
          ButtonSegment(
              value: ConfigEditorMode.json,
              icon: Icon(Icons.data_object),
              label: Text('JSON')),
        ],
        selected: {_editorMode},
        onSelectionChanged: (selection) {
          setState(() {
            if (_editorMode == ConfigEditorMode.form &&
                selection.first == ConfigEditorMode.json) {
              _rawJson.text = _draftFromFields().toPrettyJson();
            } else if (_editorMode == ConfigEditorMode.json &&
                selection.first == ConfigEditorMode.form) {
              try {
                final draft =
                    ClientConfigDraft.fromJson(jsonDecode(_rawJson.text));
                _applyDraft(draft, updateJson: false);
              } catch (_) {
                // ignore parsing errors on switch
              }
            }
            _editorMode = selection.first;
          });
        },
      ),
      child:
          _editorMode == ConfigEditorMode.form ? _formEditor() : _jsonEditor(),
    );
  }

  Widget _formEditor() {
    return ListView(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth > 760;
            final fields = [
              _field(_profileName, 'Имя профиля', Icons.badge_outlined),
              _field(_serverAddress, 'Адрес сервера', Icons.dns_outlined),
              _field(_serverDomain, 'TLS-домен', Icons.language),
              _field(_grpcPath, 'Путь gRPC', Icons.alt_route),
              _field(_socks5Listen, 'Адрес SOCKS5', Icons.settings_ethernet),
              _field(_httpProxyListen, 'Адрес HTTP', Icons.http),
              _field(_transparentListen, 'Адрес прозрачного прокси',
                  Icons.route_outlined),
              _field(_logLevel, 'Уровень логов', Icons.subject),
              _field(_keepalive, 'Интервал проверки связи, секунд',
                  Icons.timer_outlined,
                  keyboardType: TextInputType.number),
              _field(_tlsFingerprint, 'TLS-отпечаток', Icons.fingerprint),
            ];
            if (!twoColumns) {
              return Column(
                  children: fields
                      .map((field) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: field))
                      .toList());
            }
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: fields
                  .map((field) => SizedBox(
                      width: (constraints.maxWidth - 10) / 2, child: field))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noisePublicKey,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Публичный ключ Noise',
            prefixIcon: Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _psk,
          maxLines: 1,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PSK',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Шейпер трафика'),
          value: _shaperEnabled,
          onChanged: (value) {
            setState(() {
              _shaperEnabled = value;
            });
            _syncJsonFromForm();
          },
        ),
      ],
    );
  }

  Widget _jsonEditor() {
    return TextField(
      controller: _rawJson,
      expands: true,
      minLines: null,
      maxLines: null,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: const InputDecoration(
        alignLabelWithHint: true,
        labelText: 'client.json',
      ),
    );
  }

  Widget _logPanel() {
    return _panel(
      title: 'Логи',
      expandChild: true,
      trailing: IconButton(
        tooltip: 'Очистить логи',
        onPressed: () {
          setState(_logs.clear);
        },
        icon: const Icon(Icons.clear_all),
      ),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xff101414),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(10),
        child: _logs.isEmpty
            ? const Text('Логов пока нет',
                style: TextStyle(
                    color: Color(0xff9aa4a1), fontFamily: 'monospace'))
            : SingleChildScrollView(
                child: SelectableText(
                  _logs.join('\n'),
                  style: const TextStyle(
                      color: Color(0xffd6e3df),
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.25),
                ),
              ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
      ),
    );
  }

  Widget _panel({
    required String title,
    required Widget child,
    Widget? trailing,
    bool expandChild = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffd7ddda)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          expandChild ? Expanded(child: child) : child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: color.darken(), fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }

  String _statusLabel() {
    return switch (_tunnelState) {
      TunnelState.stopped => 'Остановлено',
      TunnelState.starting => 'Запуск',
      TunnelState.running => 'Работает',
      TunnelState.stopping => 'Остановка',
      TunnelState.error => 'Ошибка',
    };
  }

  Color _statusColor() {
    return switch (_tunnelState) {
      TunnelState.running => Colors.green,
      TunnelState.starting || TunnelState.stopping => Colors.orange,
      TunnelState.error => Colors.red,
      TunnelState.stopped => Colors.blueGrey,
    };
  }
}

class _ProfileCheckResult {
  const _ProfileCheckResult({
    required this.configOk,
    required this.pingOk,
    required this.pingLabel,
  });

  final bool configOk;
  final bool pingOk;
  final String pingLabel;
}

extension on Color {
  Color darken() {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0)).toColor();
  }
}
