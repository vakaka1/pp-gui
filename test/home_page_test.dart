import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:pp_gui/src/ui/home_page.dart';

void main() {
  testWidgets('HomePage loads without unbounded height exceptions', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    
    // Tap on Logs tab
    await tester.tap(find.text('Логи'));
    await tester.pumpAndSettle();
    
    // Tap on Configs tab
    await tester.tap(find.text('Конфиги'));
    await tester.pumpAndSettle();
  });
}
