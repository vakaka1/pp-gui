import 'package:flutter_test/flutter_test.dart';

import 'package:pp_gui/main.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PpGuiApp());
    // Verify that the app renders with the title in the AppBar.
    expect(find.text('PP GUI'), findsOneWidget);
  });
}
