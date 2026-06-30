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
    required this.changingUpdateChannel,
    required this.updatingGui,
    required this.guiUpdateProgress,
    required this.onInstallClient,
    required this.onUpdateClient,
    required this.onSelectUpdateChannel,
    required this.onUpdateGui,
    required this.onRefresh,
  });

  final PpBinaryInfo? binary;
  final ReleaseInfo? latestClientRelease;
  final ReleaseInfo? latestGuiRelease;
  final bool installing;
  final double? installProgress;
  final bool updatingClient;
  final bool changingUpdateChannel;
  final bool updatingGui;
  final double? guiUpdateProgress;
  final VoidCallback? onInstallClient;
  final VoidCallback? onUpdateClient;
  final ValueChanged<UpdateChannel>? onSelectUpdateChannel;
  final VoidCallback? onUpdateGui;
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
            style:
                TextStyle(color: PpColors.textDim, height: 1.4, fontSize: 13),
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
    final hasGuiUpdate =
        latestGuiRelease != null && latestGuiRelease!.isNewerThan(appVersion);
    final canUpdate =
        hasGuiUpdate && latestGuiRelease!.assetForCurrentGuiPlatform() != null;
    final stateText = hasGuiUpdate ? 'Есть обновление' : 'Актуально';
    final stateColor = hasGuiUpdate ? PpColors.orange : PpColors.green;

    return PanelCard(
      title: 'Обновление GUI',
      trailing: StatusChip(stateText, stateColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('Текущая', 'v$appVersion'),
          InfoRow('Последняя', latestGuiRelease?.tagName ?? 'неизвестно'),
          if (hasGuiUpdate) ...[
            const SizedBox(height: 6),
            const Text(
              'Новая версия PP GUI доступна. Нажмите «Обновить» — '
              'приложение скачает обновление и перезапустится автоматически.',
              style:
                  TextStyle(color: PpColors.textDim, fontSize: 12, height: 1.4),
            ),
          ],
          if (updatingGui) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: guiUpdateProgress),
            const SizedBox(height: 4),
            Text(
              guiUpdateProgress != null
                  ? 'Загрузка ${(guiUpdateProgress! * 100).toStringAsFixed(0)}%…'
                  : 'Применение обновления…',
              style: const TextStyle(color: PpColors.textDim, fontSize: 11),
            ),
          ],
          if (canUpdate) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: updatingGui ? null : onUpdateGui,
              icon: const Icon(Icons.system_update, size: 18),
              label: const Text('Обновить GUI'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _updateChannelSelector() {
    final current = binary?.updateChannel ?? UpdateChannel.stable;
    final enabled = binary?.installed == true &&
        !installing &&
        !updatingClient &&
        !changingUpdateChannel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ветка обновлений',
          style: TextStyle(
            color: PpColors.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<UpdateChannel>(
          segments: UpdateChannel.values
              .map(
                (channel) => ButtonSegment<UpdateChannel>(
                  value: channel,
                  label: Text(channel.label),
                ),
              )
              .toList(growable: false),
          selected: {current},
          showSelectedIcon: false,
          onSelectionChanged: enabled
              ? (selection) {
                  final selected = selection.first;
                  if (selected != current) {
                    onSelectUpdateChannel?.call(selected);
                  }
                }
              : null,
        ),
        if (changingUpdateChannel) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 8),
      ],
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
          if (binary?.installed == true) ...[
            const SizedBox(height: 8),
            _updateChannelSelector(),
          ],
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
