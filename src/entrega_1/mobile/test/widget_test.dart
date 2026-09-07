import 'package:flutter_test/flutter_test.dart';

import 'package:smart_tennis_arena_mobile/main.dart';

void main() {
  testWidgets('Mostra a mensagem de hello world', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartTennisArenaApp());

    expect(find.text('Hello, Smart Tennis Arena!'), findsOneWidget);
  });
}
