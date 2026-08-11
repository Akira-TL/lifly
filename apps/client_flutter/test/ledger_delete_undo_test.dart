import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/features/ledger/pages/ledger_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ledger delete can be undone from the ledger list', (tester) async {
    final api = ApiClient(baseUrl: 'http://localhost/api/v1');
    final localCore = FakeLocalCoreBridge();
    await localCore.createExpense(
      {
        'direction': 'expense',
        'amount': 28.6,
        'merchant': '可撤销咖啡店',
        'note': '撤销测试',
      },
      LocalCoreContext.flutterUser(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<LocalCoreBridge>.value(value: localCore),
          Provider<LiflyDataMode>.value(value: LiflyDataMode.local),
        ],
        child: const MaterialApp(home: LedgerListPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('可撤销咖啡店'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除账单'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('可撤销咖啡店'), findsNothing);
    expect(find.text('账单已删除'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('账单已恢复'), findsOneWidget);
    expect(find.text('可撤销咖啡店'), findsOneWidget);
  });
}
