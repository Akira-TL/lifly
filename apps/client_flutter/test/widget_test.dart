import 'package:client_flutter/data/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_flutter/main.dart';
import 'package:provider/provider.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    if (path == '/dashboard') {
      return {
        'success': true,
        'data': {
          'monthly_income': 0,
          'monthly_expense': 0,
          'weekly_trend': [],
          'recent_transactions': [],
        },
      };
    }
    return {'success': true, 'data': {}};
  }
}

void main() {
  testWidgets('App displays shell', (WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<ApiClient>(
        create: (_) => FakeApiClient(),
        child: const LifilyApp(),
      ),
    );

    await tester.pump();

    expect(find.text('备忘'), findsOneWidget);
    expect(find.text('Lifily'), findsNothing);
  });
}
