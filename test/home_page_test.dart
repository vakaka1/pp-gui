import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:pp_gui/src/ui/app_shell.dart';

void main() {
  testWidgets('AppShell loads without unbounded height exceptions', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pump(const Duration(seconds: 1));
    
    // Tap on Logs tab
    await tester.tap(find.text('Логи'));
    await tester.pump(const Duration(seconds: 1));
    
    // Tap on Configs tab
    await tester.tap(find.text('Конфиги'));
    await tester.pump(const Duration(seconds: 1));
  });
}
