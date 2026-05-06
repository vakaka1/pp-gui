import 'package:flutter/material.dart';
import '../models/app_models.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.tunnelState,
    required this.isProcessActive,
    required this.isConnected,
    required this.binary,
    required this.selectedProfile,
    required this.profileListEmpty,
    required this.status,
    required this.testResult,
    required this.isTesting,
    required this.onStart,
    required this.onStop,
    required this.onTest,
    required this.onSwitchToConfigs,
  });

  final TunnelState tunnelState;
  final bool isProcessActive;
  final bool isConnected;
  final PpBinaryInfo? binary;
  final ProfileRef? selectedProfile;
  final bool profileListEmpty;
  final String status;
  final TestResult? testResult;
  final bool isTesting;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onTest;
  final VoidCallback onSwitchToConfigs;

  bool get _canStart =>
      binary?.installed == true && selectedProfile != null && !isProcessActive;

  @override
  Widget build(BuildContext context) {
    final primaryAction = isProcessActive ? onStop : onStart;
    final primaryEnabled = isProcessActive || _canStart;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      children: [
        _heroPanel(context, primaryEnabled, primaryAction),
        const SizedBox(height: 12),
        _profileCard(context),
      ],
    );
  }

  Widget _heroPanel(
      BuildContext context, bool enabled, VoidCallback primaryAction) {
    final statusColor = _statusColor();
    final buttonColor = isConnected ? PpColors.green : PpColors.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: PpColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PpColors.border),
      ),
      child: Column(
        children: [
          StatusChip(_connectionTitle(), statusColor),
          const SizedBox(height: 20),
          // Main power button
          SizedBox.square(
            dimension: 140,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: enabled ? primaryAction : null,
                borderRadius: BorderRadius.circular(70),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled
                        ? buttonColor.withValues(alpha: 0.15)
                        : PpColors.border.withValues(alpha: 0.3),
                    border: Border.all(
                      color: enabled
                          ? buttonColor.withValues(alpha: 0.5)
                          : PpColors.border,
                      width: 2.5,
                    ),
                  ),
                  child: Icon(
                    isProcessActive ? Icons.stop_rounded : Icons.power_settings_new_rounded,
                    size: 54,
                    color: enabled ? buttonColor : PpColors.textDim,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isProcessActive ? 'Остановить' : 'Подключить',
            style: const TextStyle(
              color: PpColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: const TextStyle(color: PpColors.textDim, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _profileCard(BuildContext context) {
    return PanelCard(
      title: 'Активный конфиг',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedProfile != null)
            IconButton(
              tooltip: 'Проверить',
              onPressed: isTesting ? null : onTest,
              icon: isTesting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering, size: 20),
            ),
          TextButton.icon(
            onPressed: onSwitchToConfigs,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Сменить'),
          ),
        ],
      ),
      child: selectedProfile == null
          ? const Text('Выберите конфиг на вкладке «Конфиги».',
              style: TextStyle(color: PpColors.textDim))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  selectedProfile!.name,
                  style: const TextStyle(
                      color: PpColors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedProfile!.isManaged
                      ? 'Профиль приложения'
                      : 'Профиль pp-client',
                  style:
                      const TextStyle(color: PpColors.textDim, fontSize: 13),
                ),
                if (selectedProfile!.path != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    selectedProfile!.path!,
                    style:
                        const TextStyle(color: PpColors.textDim, fontSize: 11),
                  ),
                ],
                if (testResult != null) ...[
                  const SizedBox(height: 10),
                  _testResultRow(),
                ],
              ],
            ),
    );
  }

  Widget _testResultRow() {
    final r = testResult!;
    final color = r.ok ? PpColors.green : PpColors.red;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(r.ok ? Icons.check_circle_outline : Icons.error_outline,
              color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r.summary,
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _connectionTitle() {
    if (isConnected) return 'Подключено';
    if (isProcessActive) return status;
    if (profileListEmpty) return 'Добавьте конфиг';
    if (selectedProfile == null) return 'Выберите конфиг';
    if (binary?.installed != true) return 'Установите pp-client';
    return 'Готово';
  }

  Color _statusColor() {
    return switch (tunnelState) {
      TunnelState.running => PpColors.green,
      TunnelState.starting || TunnelState.stopping => PpColors.orange,
      TunnelState.error => PpColors.red,
      TunnelState.stopped => PpColors.textDim,
    };
  }
}
