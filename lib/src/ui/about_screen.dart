import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'theme.dart';
import 'widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({
    super.key,
    required this.binary,
    required this.latestClientRelease,
    required this.latestGuiRelease,
    required this.installing,
    required this.installProgress,
    required this.updatingClient,
    required this.onInstallClient,
    required this.onUpdateClient,
    required this.onRefresh,
  });

  final PpBinaryInfo? binary;
  final ReleaseInfo? latestClientRelease;
  final ReleaseInfo? latestGuiRelease;
  final bool installing;
  final double? installProgress;
  final bool updatingClient;
  final VoidCallback? onInstallClient;
  final VoidCallback? onUpdateClient;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        _aboutPanel(),
        const SizedBox(height: 12),
        _guiUpdatePanel(),
        const SizedBox(height: 12),
        _clientUpdatePanel(),
      ],
    );
  }

  Widget _aboutPanel() {
    return PanelCard(
      title: 'О программе',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'PP GUI — эталонное графическое приложение для работы и проверки протокола PP. '
            'Предназначено для тестирования, демонстрации и повседневного использования PP-клиента.',
            style: TextStyle(color: PpColors.textDim, height: 1.4, fontSize: 13),
          ),
          const SizedBox(height: 10),
          InfoRow('Версия GUI', 'v$appVersion'),
          if (binary?.installed == true)
            InfoRow('pp-client', binary!.displayVersion),
        ],
      ),
    );
  }

  Widget _guiUpdatePanel() {
    final hasGuiUpdate = latestGuiRelease != null &&
        latestGuiRelease!.isNewerThan(appVersion);
    final stateText = hasGuiUpdate ? 'Есть обновление' : 'Актуально';
    final stateColor = hasGuiUpdate ? PpColors.orange : PpColors.green;

    return PanelCard(
      title: 'Обновление GUI',
      trailing: StatusChip(stateText, stateColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('Текущая', 'v$appVersion'),
          InfoRow(
              'Последняя', latestGuiRelease?.tagName ?? 'неизвестно'),
          if (hasGuiUpdate) ...[
            const SizedBox(height: 8),
            const Text(
              'Скачайте обновление со страницы релизов на GitHub.',
              style: TextStyle(color: PpColors.textDim, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _clientUpdatePanel() {
    final latest = latestClientRelease;
    final updateAvailable =
        latest != null && latest.isNewerThan(binary?.version);
    final notInstalled = binary?.installed != true;
    final stateText = notInstalled
        ? 'Не установлен'
        : updateAvailable
            ? 'Есть обновление'
            : 'Актуально';
    final stateColor = notInstalled
        ? PpColors.red
        : updateAvailable
            ? PpColors.orange
            : PpColors.green;

    return PanelCard(
      title: 'Обновление pp-client',
      trailing: StatusChip(stateText, stateColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('pp-client',
              binary?.installed == true ? 'доступен' : 'не найден'),
          InfoRow('Текущая', binary?.displayVersion ?? 'не установлена'),
          InfoRow('Последняя', latest?.tagName ?? 'неизвестно'),
          if (binary?.path != null) InfoRow('Путь', binary!.path!),
          if (binary?.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(binary!.error!,
                  style: const TextStyle(color: PpColors.red, fontSize: 12)),
            ),
          if (installing) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: installProgress),
          ],
          if (updatingClient) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              // pp-client update button (uses pp-client update command)
              if (binary?.installed == true && updateAvailable) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        updatingClient || installing ? null : onUpdateClient,
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    label: const Text('Обновить'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Install/reinstall from GitHub Releases
              if (notInstalled)
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        installing || latest == null ? null : onInstallClient,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Установить'),
                  ),
                ),
              IconButton.filledTonal(
                tooltip: 'Проверить обновления',
                onPressed: onRefresh,
                icon: const Icon(Icons.sync, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
