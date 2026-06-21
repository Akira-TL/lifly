import 'package:flutter_test/flutter_test.dart';
import 'package:client_flutter/main.dart';

void main() {
  testWidgets('App displays shell', (WidgetTester tester) async {
    await tester.pumpWidget(const LifilyApp());
    expect(find.text('备忘'), findsOneWidget);
    expect(find.text('Lifily'), findsNothing);
  });
}
