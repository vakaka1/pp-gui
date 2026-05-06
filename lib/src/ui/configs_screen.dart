import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';

import '../models/app_models.dart';
import '../services/pp_client_service.dart';
import '../services/profile_store.dart';
import 'theme.dart';
import 'widgets.dart';

enum ConfigEditorMode { form, json }

/// Data / callbacks injected from the shell into ConfigsScreen.
class ConfigsController {
  const ConfigsController({
    required this.profileList,
    required this.selectedProfile,
    required this.binary,
    required this.busy,
    required this.profileChecks,
    required this.ppClient,
    required this.profiles,
    required this.selectProfile,
    required this.deleteSelected,
    required this.refreshProfiles,
    required this.setBusy,
    required this.appendLog,
    required this.showSnack,
    required this.onProfileSaved,
  });

  final List<ProfileRef> profileList;
  final ProfileRef? selectedProfile;
  final PpBinaryInfo? binary;
  final bool busy;
  final Map<String, ProfileCheckResult> profileChecks;
  final PpClientService ppClient;
  final ProfileStore profiles;
  final void Function(ProfileRef) selectProfile;
  final VoidCallback deleteSelected;
  final VoidCallback refreshProfiles;
  final void Function(bool) setBusy;
  final void Function(String) appendLog;
  final void Function(String) showSnack;
  final VoidCallback onProfileSaved;
}

class ProfileCheckResult {
  const ProfileCheckResult({
    required this.configOk,
    required this.pingOk,
    required this.pingLabel,
  });
  final bool configOk;
  final bool pingOk;
  final String pingLabel;
}

class ConfigsScreen extends StatefulWidget {
  const ConfigsScreen({super.key, required this.controller});
  final ConfigsController controller;

  @override
  State<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends State<ConfigsScreen> {
  ConfigsController get c => widget.controller;

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
  final _jsonPath = TextEditingController();

  ConfigEditorMode _editorMode = ConfigEditorMode.form;
  bool _shaperEnabled = true;
  bool _syncingEditors = false;

  @override
  void initState() {
    super.initState();
    _installEditorSync();
    _applyDraft(ClientConfigDraft.empty());
  }

  @override
  void didUpdateWidget(ConfigsScreen old) {
    super.didUpdateWidget(old);
    if (c.selectedProfile != old.controller.selectedProfile &&
        c.selectedProfile != null) {
      unawaited(_loadSelectedProfile());
    }
  }

  @override
  void dispose() {
    for (final ctrl in [
      _profileName, _serverAddress, _serverDomain, _noisePublicKey,
      _psk, _grpcPath, _socks5Listen, _httpProxyListen, _transparentListen,
      _logLevel, _tlsFingerprint, _keepalive, _rawJson, _uri, _jsonPath,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSelectedProfile() async {
    final profile = c.selectedProfile;
    if (profile == null) return;
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
      final raw = await c.profiles.readRawJson(profile);
      final draft = await c.profiles.readDraft(profile);
      if (!mounted) return;
      setState(() {
        _rawJson.text = _prettyJson(raw);
        _applyDraft(draft, updateJson: false);
      });
    } on Object catch (error) {
      c.appendLog('не удалось прочитать профиль ${profile.name}: $error');
    }
  }

  // --- Editor sync ---
  void _installEditorSync() {
    for (final ctrl in _formControllers) {
      ctrl.addListener(_syncJsonFromForm);
    }
    _rawJson.addListener(_syncFormFromJson);
  }

  List<TextEditingController> get _formControllers => [
        _profileName, _serverAddress, _serverDomain, _noisePublicKey,
        _psk, _grpcPath, _socks5Listen, _httpProxyListen, _transparentListen,
        _logLevel, _tlsFingerprint, _keepalive,
      ];

  void _syncJsonFromForm() {
    if (_syncingEditors) return;
    _syncEditorText(() {
      _rawJson.text = _draftFromFields().toPrettyJson();
    });
  }

  void _syncFormFromJson() {
    if (_syncingEditors) return;
    try {
      final draft = ClientConfigDraft.fromJson(jsonDecode(_rawJson.text));
      _syncEditorText(() {
        _applyDraft(draft, updateJson: false);
      });
    } on Object {
      // ignore
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

  // --- Profile actions ---

  Future<void> _saveProfile() async {
    c.setBusy(true);
    try {
      ProfileRef saved;
      if (_editorMode == ConfigEditorMode.json) {
        saved = await c.profiles.saveJson(_rawJson.text,
            fallbackName: _profileName.text);
      } else {
        final draft = _draftFromFields();
        saved = await c.profiles.saveDraft(draft);
        _rawJson.text = draft.toPrettyJson();
      }
      c.appendLog('профиль сохранён: ${saved.name}');
      c.onProfileSaved();
      c.selectProfile(saved);
    } on Object catch (error) {
      c.showSnack('Не удалось сохранить: $error');
      c.appendLog('ошибка сохранения: $error');
    } finally {
      c.setBusy(false);
    }
  }

  Future<void> _validateProfile(ProfileRef profile) async {
    final binary = c.binary;
    if (binary == null || !binary.installed) {
      c.showSnack('pp-client не установлен');
      return;
    }
    c.setBusy(true);
    try {
      final result = await c.ppClient.testProfile(binary, profile);
      if (!mounted) return;
      final check = ProfileCheckResult(
        configOk: result.connectOk,
        pingOk: result.pingOk,
        pingLabel: result.summary,
      );
      c.profileChecks[profile.id] = check;
      c.appendLog('${profile.name}: ${result.summary}');
      c.showSnack('${profile.name}: ${result.summary}');
    } on Object catch (error) {
      c.appendLog('ошибка проверки ${profile.name}: $error');
    } finally {
      c.setBusy(false);
    }
  }

  Future<void> _validateAll() async {
    if (c.profileList.isEmpty) {
      c.showSnack('Нет конфигов для проверки');
      return;
    }
    c.setBusy(true);
    var okCount = 0;
    try {
      for (final profile in c.profileList) {
        await _validateProfile(profile);
        final check = c.profileChecks[profile.id];
        if (check != null && check.configOk && check.pingOk) okCount++;
      }
      c.showSnack('Проверено: $okCount/${c.profileList.length} OK');
    } finally {
      c.setBusy(false);
    }
  }

  Future<void> _importUri() async {
    final raw = _uri.text.trim();
    if (raw.isEmpty) return;
    final binary = c.binary;
    try {
      if (binary != null && binary.installed && binary.canImportUri) {
        final result = await c.ppClient.importUri(binary, raw);
        if (!result.ok) {
          throw ProcessException(
              binary.path!, ['import'], result.combinedOutput, result.exitCode);
        }
        c.appendLog('URI импортирован через pp-client');
      } else {
        final draft = ClientConfigDraft.fromPpfUri(raw);
        final saved = await c.profiles.saveDraft(draft);
        c.appendLog('URI импортирован: ${saved.name}');
      }
      _uri.clear();
      c.refreshProfiles();
    } on Object catch (error) {
      c.showSnack('Импорт не удался: $error');
      c.appendLog('ошибка импорта: $error');
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
      if (file == null) return;
      _jsonPath.text = file.path;
      await _importJsonFile();
    } on Object catch (error) {
      c.showSnack('Не удалось открыть файл: $error');
    }
  }

  Future<void> _importJsonFile() async {
    final path = _jsonPath.text.trim();
    if (path.isEmpty) return;
    try {
      final raw = await File(path).readAsString();
      final saved = await c.profiles.saveJson(raw);
      c.appendLog('JSON импортирован: ${saved.name}');
      _jsonPath.clear();
      c.refreshProfiles();
    } on Object catch (error) {
      c.showSnack('Импорт JSON не удался: $error');
    }
  }

  Future<void> _importJsonFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim();
      if (raw == null || raw.isEmpty) {
        c.showSnack('Буфер обмена пуст');
        return;
      }
      if (raw.startsWith('ppf://')) {
        _uri.text = raw;
        await _importUri();
        return;
      }
      final saved = await c.profiles.saveJson(raw);
      c.appendLog('JSON из буфера импортирован: ${saved.name}');
      c.refreshProfiles();
    } on Object catch (error) {
      c.showSnack('Импорт из буфера не удался: $error');
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        _profilePanel(),
      ],
    );
  }

  Widget _profilePanel() {
    return PanelCard(
      title: 'Конфиги',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Проверить все',
            onPressed: c.busy ? null : _validateAll,
            icon: const Icon(Icons.fact_check_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Добавить конфиг',
            onPressed: _showAddConfigSheet,
            icon: const Icon(Icons.add, size: 20),
          ),
        ],
      ),
      child: Column(
        children: [
          if (c.profileList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child: Text('Нет конфигов',
                      style: TextStyle(color: PpColors.textDim))),
            )
          else
            ...c.profileList.map(_profileTile),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      c.selectedProfile == null ? null : c.deleteSelected,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Удалить выбранный'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Обновить список',
                onPressed: c.refreshProfiles,
                icon: const Icon(Icons.sync, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileTile(ProfileRef profile) {
    final selected = profile.id == c.selectedProfile?.id;
    final protocol = _profileProtocol(profile);
    final check = c.profileChecks[profile.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? PpColors.accent.withValues(alpha: 0.08)
              : PpColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? PpColors.accent.withValues(alpha: 0.35)
                : PpColors.border,
          ),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(
            profile.isManaged
                ? Icons.description_outlined
                : Icons.storage_outlined,
            color: PpColors.textDim,
          ),
          title: Text(profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PpColors.text)),
          subtitle: Text(
            protocol,
            style: const TextStyle(color: PpColors.textDim, fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (check != null) ...[
                StatusChip(
                  check.pingLabel,
                  check.configOk && check.pingOk
                      ? PpColors.green
                      : PpColors.orange,
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: 'Проверить',
                onPressed: c.busy ? null : () => _validateProfile(profile),
                icon: const Icon(Icons.wifi_tethering, size: 18),
              ),
              IconButton(
                tooltip: 'Редактировать',
                onPressed: () => _showProfileDetails(profile),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: PpColors.accent, size: 18),
            ],
          ),
          onTap: () => c.selectProfile(profile),
        ),
      ),
    );
  }

  String _profileProtocol(ProfileRef profile) {
    final meta = profile.metadata['meta'] is Map<String, dynamic>
        ? profile.metadata['meta'] as Map<String, dynamic>
        : <String, dynamic>{};
    final raw = (meta['protocol'] ??
            profile.metadata['protocol'] ??
            profile.metadata['type'] ??
            '')
        .toString()
        .toLowerCase();
    if (raw == 'ppf' || raw == 'pp-fallback' || raw == 'pp_fallback') {
      return 'PP-Fallback';
    }
    return 'PP-Fallback';
  }

  // --- Dialogs ---

  Future<void> _showProfileDetails(ProfileRef profile) async {
    c.selectProfile(profile);
    await _loadSelectedProfile();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, dialogSetState) => Dialog.fullscreen(
          backgroundColor: PpColors.bg,
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
                          style: const TextStyle(
                            color: PpColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: PpColors.textDim),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusChip(
                        _profileProtocol(profile), PpColors.textDim),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                      child: _editorPanel(dialogSetState: dialogSetState)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: c.busy
                              ? null
                              : () {
                                  Navigator.pop(ctx);
                                  unawaited(_saveProfile());
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Сохранить'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Проверить',
                        onPressed: c.busy
                            ? null
                            : () => _validateProfile(profile),
                        icon: const Icon(Icons.wifi_tethering),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddConfigSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
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
                  Navigator.pop(ctx);
                  unawaited(_pickAndImportJsonFile());
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('Импорт из буфера'),
                subtitle: const Text('JSON или ppf:// URI'),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_importJsonFromClipboard());
                },
              ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Добавить вручную'),
                subtitle: const Text('Открыть редактор нового конфига'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showManualConfigDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showManualConfigDialog() async {
    setState(() {
      _editorMode = ConfigEditorMode.form;
      _applyDraft(ClientConfigDraft.empty());
    });
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, dialogSetState) => Dialog.fullscreen(
          backgroundColor: PpColors.bg,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Новый конфиг',
                          style: TextStyle(
                            color: PpColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: PpColors.textDim),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                      child: _editorPanel(dialogSetState: dialogSetState)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: c.busy
                              ? null
                              : () {
                                  Navigator.pop(ctx);
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
        ),
      ),
    );
  }

  // --- Editor ---

  Widget _editorPanel({StateSetter? dialogSetState}) {
    return PanelCard(
      title: 'Конфигурация',
      expandChild: true,
      trailing: SegmentedButton<ConfigEditorMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
              value: ConfigEditorMode.form,
              icon: Icon(Icons.tune, size: 16),
              label: Text('Форма')),
          ButtonSegment(
              value: ConfigEditorMode.json,
              icon: Icon(Icons.data_object, size: 16),
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
              } catch (_) {}
            }
            _editorMode = selection.first;
          });
          dialogSetState?.call(() {});
        },
      ),
      child:
          _editorMode == ConfigEditorMode.form ? _formEditor() : _jsonEditor(),
    );
  }

  Widget _formEditor() {
    return ListView(
      children: [
        _field(_profileName, 'Имя профиля', Icons.badge_outlined),
        _field(_serverAddress, 'Адрес сервера', Icons.dns_outlined),
        _field(_serverDomain, 'TLS-домен', Icons.language),
        _field(_grpcPath, 'Путь gRPC', Icons.alt_route),
        _field(_socks5Listen, 'Адрес SOCKS5', Icons.settings_ethernet),
        _field(_httpProxyListen, 'Адрес HTTP', Icons.http),
        _field(_transparentListen, 'Адрес прозрачного прокси',
            Icons.route_outlined),
        _field(_logLevel, 'Уровень логов', Icons.subject),
        _field(
            _keepalive, 'Интервал keepalive (сек)', Icons.timer_outlined,
            keyboardType: TextInputType.number),
        _field(_tlsFingerprint, 'TLS-отпечаток', Icons.fingerprint),
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
          title: const Text('Шейпер трафика',
              style: TextStyle(color: PpColors.text)),
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
      style: const TextStyle(
          fontFamily: 'monospace', fontSize: 13, color: PpColors.text),
      decoration: const InputDecoration(
        alignLabelWithHint: true,
        labelText: 'client.json',
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }
}
