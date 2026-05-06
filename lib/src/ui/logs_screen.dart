import 'package:flutter/material.dart';
import 'theme.dart';
import 'widgets.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({
    super.key,
    required this.logs,
    required this.onClear,
  });

  final List<String> logs;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: SizedBox(
        height: double.infinity,
        child: PanelCard(
          title: 'Логи',
          expandChild: true,
          trailing: IconButton(
            tooltip: 'Очистить',
            onPressed: onClear,
            icon: const Icon(Icons.clear_all, size: 20),
          ),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E12),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(10),
            child: logs.isEmpty
                ? const Text('Логов пока нет',
                    style: TextStyle(
                        color: PpColors.textDim, fontFamily: 'monospace'))
                : SingleChildScrollView(
                    child: SelectableText(
                      logs.join('\n'),
                      style: const TextStyle(
                        color: PpColors.text,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
