import 'package:flutter_test/flutter_test.dart';
import 'package:pp_gui/src/models/app_models.dart';
import 'package:pp_gui/src/services/app_paths.dart';
import 'package:pp_gui/src/services/pp_client_service.dart';
import 'dart:io';

void main() {
  test('разбирает вывод версии pp-client', () {
    const output = '''
PP-Client Version: v1.0.43
Build Date: 2026-04-29T07:54:34Z
Commit: 1f3592b45b3b1c17683e0f0c7ea5d9684ae4acd1
''';

    expect(PpClientService.parseVersion(output), 'v1.0.43');
    expect(PpClientService.parseLabeledValue(output, 'Build Date'),
        '2026-04-29T07:54:34Z');
  });

  test('определяет более новые теги релизов', () {
    expect(compareSemverTags('v1.0.44', 'v1.0.43'), greaterThan(0));
    expect(compareSemverTags('v1.0.44', '1.0.44'), 0);
    expect(compareSemverTags('v1.1.0', 'v1.0.99'), greaterThan(0));
  });

  test('создаёт клиентскую конфигурацию из ppf uri', () {
    final draft = ClientConfigDraft.fromPpfUri(
        'ppf://office@example.com:443?pub=PUB&psk=PSK&path=/grpc&fp=chrome');
    final json = draft.toJson();

    expect(draft.profileName, 'office');
    expect(json['client']['server']['address'], 'example.com:443');
    expect(json['client']['server']['noise_public_key'], 'PUB');
    expect(json['client']['server']['psk'], 'PSK');
    expect(json['client']['server']['grpc_path'], '/grpc');
    expect(json['client']['server']['tls_fingerprint'], 'chrome');
  });

  test('читает update-channel из пути pp-client', () {
    final path = AppPaths.updateChannelFile.path.replaceAll('/', '\\');
    if (Platform.isWindows) {
      expect(path.toLowerCase().contains('\\pp\\update-channel'), isTrue);
    } else {
      expect(
          path.toLowerCase().contains('.config\\pp-client\\update-channel') ||
              path.toLowerCase().contains('.config/pp-client/update-channel'),
          isTrue);
    }
  });
}
