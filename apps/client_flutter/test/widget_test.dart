import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_flutter/main.dart';
import 'package:provider/provider.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

  static final Map<String, dynamic> memo = {
    'id': 'memo-test',
    'type': 'memo',
    'title': '测试备忘',
    'content_markdown': '测试内容',
    'tags': ['test'],
    'mood': null,
    'status': 'active',
    'created_at': '2026-06-25T00:00:00Z',
    'updated_at': '2026-06-25T00:00:00Z',
  };

  static final Map<String, dynamic> transaction = {
    'id': 'tx-test',
    'direction': 'expense',
    'amount': 12.3,
    'currency': 'CNY',
    'merchant': '测试商户',
    'note': '测试账单',
    'category_id': null,
    'occurred_at': '2026-06-25T00:00:00Z',
    'source': 'manual',
    'created_at': '2026-06-25T00:00:00Z',
  };

  static final Map<String, dynamic> task = {
    'id': 'task-test',
    'title': '测试任务',
    'description': '测试描述',
    'due_at': null,
    'remind_at': null,
    'priority': 'normal',
    'task_status': 'todo',
    'completed_at': null,
    'created_at': '2026-06-25T00:00:00Z',
  };

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    if (path == '/dashboard') {
      return {
        'success': true,
        'data': {
          'memo_total': 1,
          'task_todo': 1,
          'task_total': 1,
          'month_income': 0,
          'month_expense': 12.3,
          'daily_trend': [],
          'recent_transactions': [],
        },
      };
    }
    if (path == '/memos') {
      return {
        'success': true,
        'data': {
          'total': 1,
          'limit': 50,
          'offset': 0,
          'items': [memo],
        },
      };
    }
    if (path == '/memos/memo-test') {
      return {'success': true, 'data': memo};
    }
    if (path == '/ledger/transactions') {
      return {
        'success': true,
        'data': {
          'total': 1,
          'limit': 50,
          'offset': 0,
          'items': [transaction],
        },
      };
    }
    if (path == '/ledger/transactions/tx-test') {
      return {'success': true, 'data': transaction};
    }
    if (path == '/ledger/summary') {
      return {
        'success': true,
        'data': {
          'expense_total': 12.3,
          'income_total': 0,
          'transaction_count': 1,
        },
      };
    }
    if (path == '/tasks') {
      return {
        'success': true,
        'data': {
          'total': 1,
          'limit': 50,
          'offset': 0,
          'items': [task],
        },
      };
    }
    if (path == '/tasks/task-test') {
      return {'success': true, 'data': task};
    }
    if (path == '/audit/ai-summary') {
      return {
        'success': true,
        'data': {
          'actor_type': 'ai',
          'items': [
            {
              'source_channel': 'cloud_mcp',
              'tool_name': 'capture_commit',
              'count': 1,
            },
          ],
        },
      };
    }
    return {'success': true, 'data': {}};
  }
}

void main() {
  testWidgets('App displays real API backed shell pages and detail pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LiflyDataMode>.value(value: LiflyDataMode.api),
          Provider<ApiClient>(create: (_) => FakeApiClient()),
          Provider<LocalCoreBridge>(create: (_) => FakeLocalCoreBridge()),
          ProxyProvider3<
            ApiClient,
            LiflyDataMode,
            LocalCoreBridge,
            AiCaptureService
          >(
            update: (_, api, dataMode, localCore, _) => AiCaptureService(
              api: api,
              dataMode: dataMode,
              localCore: localCore,
            ),
          ),
        ],
        child: const LiflyApp(),
      ),
    );

    await tester.pump();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('备忘'), findsWidgets);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('记账'), findsWidgets);
    expect(find.text('任务'), findsWidgets);
    expect(find.text('搜索'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(find.byTooltip('全局搜索'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.text('测试备忘'), findsNothing);

    await tester.tap(find.text('备忘').last);
    await tester.pump();
    expect(find.text('测试备忘'), findsOneWidget);

    await tester.tap(find.text('测试备忘'));
    await tester.pumpAndSettle();
    expect(find.text('备忘详情'), findsOneWidget);
    expect(find.text('测试内容'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('记账'));
    await tester.pump();
    expect(find.text('测试商户'), findsOneWidget);

    await tester.tap(find.text('测试商户'));
    await tester.pumpAndSettle();
    expect(find.text('账单详情'), findsOneWidget);
    expect(find.text('测试账单'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI'));
    await tester.pump();
    expect(find.text('AI 写入'), findsOneWidget);

    await tester.tap(find.text('任务'));
    await tester.pump();
    expect(find.text('测试任务'), findsOneWidget);

    await tester.tap(find.text('测试任务'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('测试描述'), findsOneWidget);
  });
}
