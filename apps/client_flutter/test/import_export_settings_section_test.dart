import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/import_export/widgets/import_export_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('ImportExportSettingsSection enables data actions in api mode', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSection(LiflyDataMode.api));
    await tester.pumpAndSettle();

    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('Cloud API：可导入、提交、追踪批次并导出数据'), findsOneWidget);
    expect(find.text('账单导入'), findsOneWidget);
    expect(find.text('导入批次'), findsOneWidget);
    expect(find.text('数据导出'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);

    await tester.tap(find.text('数据导出'));
    await tester.pumpAndSettle();

    expect(find.text('数据导出'), findsWidgets);
    expect(find.text('Lifly 数据导出'), findsOneWidget);
  });

  testWidgets(
    'ImportExportSettingsSection disables data actions in local mode',
    (tester) async {
      await tester.pumpWidget(_buildSection(LiflyDataMode.local));
      await tester.pumpAndSettle();

      expect(find.text('Local Core：导入导出需要切换到 Cloud API'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));

      await tester.tap(find.text('数据导出'));
      await tester.pumpAndSettle();

      expect(find.text('Lifly 数据导出'), findsNothing);
    },
  );
}

Widget _buildSection(LiflyDataMode dataMode) {
  return MultiProvider(
    providers: [
      Provider<LiflyDataMode>.value(value: dataMode),
      Provider<ApiClient>.value(
        value: ApiClient(baseUrl: 'http://localhost/api/v1'),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [ImportExportSettingsSection(dataMode: dataMode)],
        ),
      ),
    ),
  );
}
