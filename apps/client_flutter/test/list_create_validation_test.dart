import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/features/ledger/pages/ledger_list_page.dart';
import 'package:client_flutter/features/memo/pages/memo_list_page.dart';
import 'package:client_flutter/features/task/pages/task_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'memo create explains invalid input and accepts title-only memo',
    (tester) async {
      await tester.pumpWidget(_buildApp(const MemoListPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('新建备忘'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pump();
      expect(find.text('请输入标题或内容'), findsOneWidget);

      await tester.enterText(_textField('标题'), '只有标题的新备忘');
      await tester.pump();
      expect(find.text('请输入标题或内容'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('只有标题的新备忘'), findsOneWidget);
    },
  );

  testWidgets('task create explains missing title and recovers', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(const TaskListPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入任务标题'), findsOneWidget);

    await tester.enterText(_textField('标题'), '新建任务校验');
    await tester.pump();
    expect(find.text('请输入任务标题'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('新建任务校验'), findsOneWidget);
  });

  testWidgets('ledger create explains invalid amount and recovers', (
    tester,
  ) async {
    await tester.pumpWidget(_buildApp(const LedgerListPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('记一笔'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('请输入大于 0 的金额'), findsOneWidget);

    await tester.enterText(_textField('金额'), '12.50');
    await tester.pump();
    expect(find.text('请输入大于 0 的金额'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('-¥12.50'), findsOneWidget);
  });
}

Widget _buildApp(Widget child) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(
        value: ApiClient(baseUrl: 'http://localhost/api/v1'),
      ),
      Provider<LocalCoreBridge>.value(value: FakeLocalCoreBridge()),
      Provider<LiflyDataMode>.value(value: LiflyDataMode.local),
    ],
    child: MaterialApp(home: child),
  );
}

Finder _textField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}
