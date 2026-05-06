import 'dart:convert';
import 'dart:io';

/// Current GUI application version (synced with pubspec.yaml).
const String appVersion = '1.0.0';

/// Result of `pp-client test` command.
class TestResult {
  const TestResult({
    required this.status,
    required this.connectOk,
    required this.pingOk,
    required this.pingMs,
    this.error,
  });

  final String status;
  final bool connectOk;
  final bool pingOk;
  final int? pingMs;
  final String? error;

  bool get ok => status == 'ok' && connectOk && pingOk;

  String get summary {
    if (ok) {
      return pingMs != null ? 'OK · ${pingMs} мс' : 'OK';
    }
    return 'N/A';
  }

  factory TestResult.fromJson(Map<String, dynamic> json) {
    return TestResult(
      status: (json['status'] ?? '').toString(),
      connectOk: json['connect_ok'] == true,
      pingOk: json['ping_ok'] == true,
      pingMs: json['ping_ms'] is num ? (json['ping_ms'] as num).toInt() : null,
      error: json['error']?.toString(),
    );
  }
}

enum PpCapability {
  validateConfig,
  importUri,
  listProfiles,
  deleteProfile,
  transparentListen,
}

enum TunnelState {
  stopped,
  starting,
  running,
  stopping,
  error,
}

enum ProfileSource {
  managed,
  clientStore,
}

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
  String get combinedOutput =>
      [stdout, stderr].where((part) => part.trim().isNotEmpty).join('\n');
}

class PpBinaryInfo {
  const PpBinaryInfo({
    required this.path,
    required this.version,
    required this.buildDate,
    required this.commit,
    required this.capabilities,
    required this.error,
  });

  final String? path;
  final String? version;
  final String? buildDate;
  final String? commit;
  final Set<PpCapability> capabilities;
  final String? error;

  bool get installed => path != null && error == null;
  bool get canValidate => capabilities.contains(PpCapability.validateConfig);
  bool get canImportUri => capabilities.contains(PpCapability.importUri);
  bool get canListProfiles => capabilities.contains(PpCapability.listProfiles);
  bool get canDeleteProfile =>
      capabilities.contains(PpCapability.deleteProfile);
  bool get canTransparentListen =>
      capabilities.contains(PpCapability.transparentListen);

  String get displayVersion => version ?? 'неизвестно';
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
    required this.digest,
  });

  final String name;
  final String browserDownloadUrl;
  final int size;
  final String? digest;

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] ?? '').toString(),
      browserDownloadUrl: (json['browser_download_url'] ?? '').toString(),
      size: json['size'] is int ? json['size'] as int : 0,
      digest: json['digest']?.toString(),
    );
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.htmlUrl,
    required this.publishedAt,
    required this.body,
    required this.assets,
  });

  final String tagName;
  final String htmlUrl;
  final DateTime? publishedAt;
  final String body;
  final List<ReleaseAsset> assets;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    return ReleaseInfo(
      tagName: (json['tag_name'] ?? '').toString(),
      htmlUrl: (json['html_url'] ?? '').toString(),
      publishedAt: DateTime.tryParse((json['published_at'] ?? '').toString()),
      body: (json['body'] ?? '').toString(),
      assets: (json['assets'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ReleaseAsset.fromJson)
          .toList(growable: false),
    );
  }

  ReleaseAsset? assetForCurrentPlatform() {
    if (Platform.isLinux) {
      return assets
          .where((asset) => asset.name == 'pp-client_linux_amd64')
          .firstOrNull;
    }
    if (Platform.isWindows) {
      final candidates = assets.where((asset) {
        final name = asset.name.toLowerCase();
        return name.contains('pp-client') && name.contains('windows');
      });
      return candidates.firstOrNull;
    }
    return null;
  }

  /// Finds the GUI update archive for the current platform.
  /// Linux → pp-gui-<tag>-linux.tar.gz
  /// Windows → pp-gui-<tag>-windows.zip
  ReleaseAsset? assetForCurrentGuiPlatform() {
    if (Platform.isLinux) {
      return assets.where((a) {
        final n = a.name.toLowerCase();
        return n.contains('pp-gui') && n.contains('linux') && n.endsWith('.tar.gz');
      }).firstOrNull;
    }
    if (Platform.isWindows) {
      return assets.where((a) {
        final n = a.name.toLowerCase();
        return n.contains('pp-gui') && n.contains('windows') && n.endsWith('.zip');
      }).firstOrNull;
    }
    return null;
  }

  bool isNewerThan(String? currentVersion) {
    if (currentVersion == null || currentVersion.trim().isEmpty) {
      return true;
    }
    return compareSemverTags(tagName, currentVersion) > 0;
  }
}

class ProfileRef {
  const ProfileRef({
    required this.id,
    required this.name,
    required this.source,
    required this.path,
    required this.metadata,
  });

  final String id;
  final String name;
  final ProfileSource source;
  final String? path;
  final Map<String, dynamic> metadata;

  bool get isManaged => source == ProfileSource.managed;

  factory ProfileRef.fromManagedFile(File file, Map<String, dynamic> json) {
    final fallbackName = _fileStem(file.path);
    final name =
        (json['profile_name'] ?? json['name'] ?? fallbackName).toString();
    return ProfileRef(
      id: file.path,
      name: name,
      source: ProfileSource.managed,
      path: file.path,
      metadata: json,
    );
  }

  factory ProfileRef.fromClientJson(Map<String, dynamic> json) {
    final rawPath =
        json['path'] ?? json['config_path'] ?? json['file'] ?? json['filename'];
    final path = rawPath?.toString();
    final name = (json['name'] ??
            json['profile'] ??
            json['id'] ??
            (path == null ? 'профиль' : _fileStem(path)))
        .toString();
    return ProfileRef(
      id: path ?? name,
      name: name,
      source: ProfileSource.clientStore,
      path: path,
      metadata: json,
    );
  }
}

class ClientConfigDraft {
  const ClientConfigDraft({
    required this.profileName,
    required this.serverAddress,
    required this.serverDomain,
    required this.noisePublicKey,
    required this.psk,
    required this.grpcPath,
    required this.socks5Listen,
    required this.httpProxyListen,
    required this.transparentListen,
    required this.logLevel,
    required this.shaperEnabled,
    required this.keepaliveSeconds,
    required this.tlsFingerprint,
  });

  final String profileName;
  final String serverAddress;
  final String serverDomain;
  final String noisePublicKey;
  final String psk;
  final String grpcPath;
  final String socks5Listen;
  final String httpProxyListen;
  final String transparentListen;
  final String logLevel;
  final bool shaperEnabled;
  final int keepaliveSeconds;
  final String tlsFingerprint;

  factory ClientConfigDraft.empty() {
    return const ClientConfigDraft(
      profileName: 'Основной',
      serverAddress: '',
      serverDomain: '',
      noisePublicKey: '',
      psk: '',
      grpcPath: '/pp.v1.TunnelService/Connect',
      socks5Listen: '127.0.0.1:1080',
      httpProxyListen: '127.0.0.1:8080',
      transparentListen: '127.0.0.1:18080',
      logLevel: 'info',
      shaperEnabled: true,
      keepaliveSeconds: 25,
      tlsFingerprint: '',
    );
  }

  factory ClientConfigDraft.fromJson(Map<String, dynamic> json) {
    final client = json['client'] is Map<String, dynamic>
        ? json['client'] as Map<String, dynamic>
        : <String, dynamic>{};
    final server = client['server'] is Map<String, dynamic>
        ? client['server'] as Map<String, dynamic>
        : <String, dynamic>{};
    final transport = client['transport'] is Map<String, dynamic>
        ? client['transport'] as Map<String, dynamic>
        : <String, dynamic>{};
    final log = json['log'] is Map<String, dynamic>
        ? json['log'] as Map<String, dynamic>
        : <String, dynamic>{};
    final meta = json['meta'] is Map<String, dynamic>
        ? json['meta'] as Map<String, dynamic>
        : <String, dynamic>{};

    return ClientConfigDraft(
      profileName: (json['profile_name'] ??
              json['name'] ??
              meta['client_name'] ??
              server['domain'] ??
              'Профиль')
          .toString(),
      serverAddress: (server['address'] ?? '').toString(),
      serverDomain: (server['domain'] ?? '').toString(),
      noisePublicKey: (server['noise_public_key'] ?? '').toString(),
      psk: (server['psk'] ?? '').toString(),
      grpcPath:
          (server['grpc_path'] ?? '/pp.v1.TunnelService/Connect').toString(),
      socks5Listen: (client['socks5_listen'] ?? '127.0.0.1:1080').toString(),
      httpProxyListen:
          (client['http_proxy_listen'] ?? '127.0.0.1:8080').toString(),
      transparentListen:
          (client['transparent_listen'] ?? '127.0.0.1:18080').toString(),
      logLevel: (log['level'] ?? 'info').toString(),
      shaperEnabled: transport['shaper_enabled'] is bool
          ? transport['shaper_enabled'] as bool
          : true,
      keepaliveSeconds: transport['keepalive_interval_seconds'] is int
          ? transport['keepalive_interval_seconds'] as int
          : 25,
      tlsFingerprint: (server['tls_fingerprint'] ?? '').toString(),
    );
  }

  factory ClientConfigDraft.fromPpfUri(String rawUri) {
    final uri = Uri.parse(rawUri.trim());
    if (uri.scheme != 'ppf') {
      throw const FormatException('Ожидался URI вида ppf://');
    }
    final host = uri.host;
    if (host.isEmpty) {
      throw const FormatException('В URI не указан хост');
    }
    final port = uri.hasPort ? uri.port : 443;
    final pub =
        uri.queryParameters['pub'] ?? uri.queryParameters['public_key'] ?? '';
    final psk = uri.queryParameters['psk'] ?? uri.queryParameters['key'] ?? '';
    final path = uri.queryParameters['path'] ?? '/pp.v1.TunnelService/Connect';
    final user = uri.userInfo.trim();
    return ClientConfigDraft(
      profileName: user.isEmpty ? host : user,
      serverAddress: '$host:$port',
      serverDomain: host,
      noisePublicKey: pub,
      psk: psk,
      grpcPath: path,
      socks5Listen: '127.0.0.1:1080',
      httpProxyListen: '127.0.0.1:8080',
      transparentListen: '127.0.0.1:18080',
      logLevel: 'info',
      shaperEnabled: true,
      keepaliveSeconds: 25,
      tlsFingerprint: uri.queryParameters['fp'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    final server = <String, dynamic>{
      'address': serverAddress.trim(),
      'domain': serverDomain.trim(),
      'noise_public_key': noisePublicKey.trim(),
      'psk': psk.trim(),
      'grpc_path': grpcPath.trim().isEmpty
          ? '/pp.v1.TunnelService/Connect'
          : grpcPath.trim(),
    };
    if (tlsFingerprint.trim().isNotEmpty) {
      server['tls_fingerprint'] = tlsFingerprint.trim();
    }

    final client = <String, dynamic>{
      'socks5_listen': socks5Listen.trim(),
      'http_proxy_listen': httpProxyListen.trim(),
      'transparent_listen': transparentListen.trim(),
      'server': server,
      'transport': {
        'shaper_enabled': shaperEnabled,
        'keepalive_interval_seconds': keepaliveSeconds,
      },
    };

    return {
      'profile_name':
          profileName.trim().isEmpty ? 'Профиль' : profileName.trim(),
      'meta': {
        'client_name':
            profileName.trim().isEmpty ? 'profile' : profileName.trim(),
        'protocol': 'pp-fallback',
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      },
      'log': {
        'level': logLevel.trim().isEmpty ? 'info' : logLevel.trim(),
        'output': 'stdout',
      },
      'client': client,
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}

class AppSettings {
  const AppSettings({
    required this.binaryPath,
    required this.fullTunnelOwner,
    required this.verboseLogs,
    required this.selectedProfileId,
  });

  final String? binaryPath;
  final String fullTunnelOwner;
  final bool verboseLogs;
  final String? selectedProfileId;

  factory AppSettings.defaults() {
    return const AppSettings(
      binaryPath: null,
      fullTunnelOwner: '',
      verboseLogs: false,
      selectedProfileId: null,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      binaryPath: json['binary_path']?.toString(),
      fullTunnelOwner: (json['full_tunnel_owner'] ?? '').toString(),
      verboseLogs: json['verbose_logs'] == true,
      selectedProfileId: json['selected_profile_id']?.toString(),
    );
  }

  AppSettings copyWith({
    String? binaryPath,
    bool clearBinaryPath = false,
    String? fullTunnelOwner,
    bool? verboseLogs,
    String? selectedProfileId,
    bool clearSelectedProfile = false,
  }) {
    return AppSettings(
      binaryPath: clearBinaryPath ? null : (binaryPath ?? this.binaryPath),
      fullTunnelOwner: fullTunnelOwner ?? this.fullTunnelOwner,
      verboseLogs: verboseLogs ?? this.verboseLogs,
      selectedProfileId: clearSelectedProfile
          ? null
          : (selectedProfileId ?? this.selectedProfileId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'binary_path': binaryPath,
      'full_tunnel_owner': fullTunnelOwner,
      'verbose_logs': verboseLogs,
      'selected_profile_id': selectedProfileId,
    };
  }
}

int compareSemverTags(String left, String right) {
  final a = _tagParts(left);
  final b = _tagParts(right);
  for (var i = 0; i < 3; i += 1) {
    final delta = a[i].compareTo(b[i]);
    if (delta != 0) {
      return delta;
    }
  }
  return 0;
}

List<int> _tagParts(String tag) {
  final normalized = tag.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final pieces = normalized.split('.');
  return List<int>.generate(3, (index) {
    if (index >= pieces.length) {
      return 0;
    }
    return int.tryParse(pieces[index].replaceAll(RegExp(r'[^0-9].*$'), '')) ??
        0;
  });
}

String _fileStem(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  final name = parts.isEmpty ? normalized : parts.last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
