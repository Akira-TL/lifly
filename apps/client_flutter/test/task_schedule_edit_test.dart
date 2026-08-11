import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/features/task/pages/task_detail_page.dart';
import 'package:client_flutter/features/task/pages/task_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late ApiClient api;
  late FakeLocalCoreBridge localCore;
  late TaskRepository repo;

  setUp(() {
    api = ApiClient(baseUrl: 'http://localhost/api/v1');
    localCore = FakeLocalCoreBridge();
    repo = TaskRepository(
      api,
      localCore: localCore,
      dataMode: LiflyDataMode.local,
    );
  });

  testWidgets('task create can set due and reminder times', (tester) async {
    await tester.pumpWidget(
      _buildApp(api: api, localCore: localCore, child: const TaskListPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新建任务'));
    await tester.pumpAndSettle();
    await tester.enterText(_textField('标题'), '带时间的新任务');

    await _pickDefaultDateTime(tester, const Key('task_due_picker'));
    await _pickDefaultDateTime(tester, const Key('task_reminder_picker'));

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final tasks = await repo.list(limit: 10);
    final created = tasks.singleWhere((task) => task.title == '带时间的新任务');
    expect(created.dueAt, isNotNull);
    expect(created.remindAt, isNotNull);
    final pending = await repo.reminders(status: 'pending');
    expect(pending, hasLength(1));
    expect(pending.single['target_id'], created.id);
    expect(
      DateTime.parse(pending.single['remind_at'] as String).toUtc(),
      created.remindAt!.toUtc(),
    );
  });

  testWidgets('task edit can clear due and reminder times', (tester) async {
    final remindAt = DateTime.utc(2026, 8, 12, 16);
    final task = await repo.create({
      'title': '清理任务时间',
      'due_at': DateTime.utc(2026, 8, 12, 18).toIso8601String(),
      'remind_at': remindAt.toIso8601String(),
    });
    await repo.confirmReminderStrategy(task.id, {
      'warning_level': 'normal',
      'warning_reason': '用户手动设置提醒时间',
      'ai_suggested_remind_at': remindAt.toIso8601String(),
      'source': 'user',
    });
    expect(await repo.reminders(status: 'pending'), hasLength(1));

    await tester.pumpWidget(
      _buildApp(
        api: api,
        localCore: localCore,
        child: TaskDetailPage(taskId: task.id, initialTask: task),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task_due_clear')));
    await tester.tap(find.byKey(const Key('task_reminder_clear')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final updated = await repo.get(task.id);
    expect(updated.dueAt, isNull);
    expect(updated.remindAt, isNull);
    expect(await repo.reminders(status: 'pending'), isEmpty);
    expect(await repo.reminders(status: 'cancelled'), hasLength(1));
    expect(find.text('无'), findsWidgets);
  });
}

Future<void> _pickDefaultDateTime(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  await tester.tap(find.byType(TextButton).last);
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), findsOneWidget);
  await tester.tap(find.byType(TextButton).last);
  await tester.pumpAndSettle();
}

Finder _textField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Widget _buildApp({
  required ApiClient api,
  required LocalCoreBridge localCore,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<LocalCoreBridge>.value(value: localCore),
      Provider<LiflyDataMode>.value(value: LiflyDataMode.local),
    ],
    child: MaterialApp(home: child),
  );
}
