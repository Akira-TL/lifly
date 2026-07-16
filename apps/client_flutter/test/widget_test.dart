import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_resolver.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_flutter/main.dart';
import 'package:provider/provider.dart';

class _WidgetThemeResolver implements ThemeResolver {
  ThemeSnapshot? snapshot;

  @override
  Future<ThemeSnapshot?> resolve() async => snapshot;
}

class _MemoryThemePreferenceStore implements ThemePreferenceStore {
  ThemePreference? value;

  @override
  Future<ThemePreference?> load() async => value;

  @override
  Future<void> save(ThemePreference preference) async {
    value = preference;
  }
}

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

Widget _buildTestApp(ThemeRuntime themeRuntime, {ApiClient? apiClient}) {
  final api = apiClient ?? FakeApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeRuntime>.value(value: themeRuntime),
      Provider<LiflyDataMode>.value(value: LiflyDataMode.api),
      Provider<ApiClient>.value(value: api),
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
  );
}

ThemeSnapshot _switchedTheme() {
  return ThemeSnapshot(
    familyId: 'test.widget-theme',
    displayName: 'Widget Test Theme',
    packageVersion: '1.0.0',
    performanceClass: ThemePerformanceClass.standard,
    colorMode: ThemePackageColorMode.light,
    platformProfile: ThemePlatformProfile.defaults(ThemeTargetPlatform.phone),
    tokens: LiflyCoreTheme.tokens,
    lightTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: Colors.orange,
    ),
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.orange,
    ),
    themeMode: ThemeMode.light,
  );
}

void main() {
  testWidgets('App displays real API backed shell pages and detail pages', (
    WidgetTester tester,
  ) async {
    final themeResolver = _WidgetThemeResolver();
    final themeRuntime = ThemeRuntime.withResolver(themeResolver);

    await tester.pumpWidget(_buildTestApp(themeRuntime));

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
    await tester.pumpAndSettle();
    expect(find.text('AI 对话'), findsOneWidget);
    expect(find.byKey(const Key('ai_capture_composer')), findsOneWidget);

    await tester.tap(find.text('任务'));
    await tester.pump();
    expect(find.text('测试任务'), findsOneWidget);

    await tester.tap(find.text('测试任务'));
    await tester.pumpAndSettle();
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('测试描述'), findsOneWidget);

    final switchedTheme = _switchedTheme();
    themeResolver.snapshot = switchedTheme;

    await themeRuntime.restore();
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme, same(switchedTheme.lightTheme));
    expect(app.darkTheme, same(switchedTheme.darkTheme));
    expect(app.themeMode, ThemeMode.light);
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('测试描述'), findsOneWidget);
  });

  testWidgets(
    'Declarative package applies to business pages without theme branches',
    (WidgetTester tester) async {
      final package = ThemePackage.fromJson(liflyTestThemePackageJson);
      final themeRuntime = ThemeRuntime.withResolver(
        ThemePackageResolver(
          package: package,
          appVersion: '0.8.0',
          platform: ThemeTargetPlatform.web,
        ),
      );
      await tester.pumpWidget(_buildTestApp(themeRuntime));
      await tester.pump();

      var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.theme?.colorScheme.primary,
        LiflyCoreTheme.snapshot.lightTheme.colorScheme.primary,
      );

      await themeRuntime.restore();
      await tester.pump();

      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.colorScheme.primary, const Color(0xFF176B52));
      expect(find.text('首页'), findsWidgets);
      expect(find.text('备忘'), findsWidgets);
      expect(find.text('记账'), findsWidgets);
      expect(find.text('任务'), findsWidgets);

      await tester.tap(find.text('任务').last);
      await tester.pump();
      expect(find.text('测试任务'), findsOneWidget);
    },
  );

  testWidgets(
    'Registry theme selection preserves current route and service instances',
    (WidgetTester tester) async {
      final runtime = ThemeRuntime(
        registry: ThemeRegistry(
          packages: [ThemePackage.fromJson(liflyTestThemePackageJson)],
        ),
        preferenceStore: _MemoryThemePreferenceStore(),
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.phone,
      );
      final api = FakeApiClient();
      await tester.pumpWidget(_buildTestApp(runtime, apiClient: api));
      await tester.pump();

      await tester.tap(find.text('任务').last);
      await tester.pump();
      await tester.tap(find.text('测试任务'));
      await tester.pumpAndSettle();
      final apiBefore = tester.element(find.byType(LiflyApp)).read<ApiClient>();

      await runtime.selectFamily('lifly.test.mint');
      await runtime.selectColorMode(ThemePackageColorMode.dark);
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final apiAfter = tester.element(find.byType(LiflyApp)).read<ApiClient>();
      expect(app.themeMode, ThemeMode.dark);
      expect(find.text('任务详情'), findsOneWidget);
      expect(find.text('测试描述'), findsOneWidget);
      expect(apiAfter, same(apiBefore));
      expect(apiAfter, same(api));
    },
  );

  testWidgets('Web dashboard profile extends the rail without losing modules', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = ThemeRuntime.withResolver(
      ThemePackageResolver(
        package: ThemePackage.fromJson(liflyTestThemePackageJson),
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.web,
      ),
    );
    await tester.pumpWidget(_buildTestApp(runtime));
    await runtime.restore();
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(rail.destinations, hasLength(5));
    expect(find.text('首页'), findsWidgets);
    expect(find.text('备忘'), findsWidgets);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('记账'), findsWidgets);
    expect(find.text('任务'), findsWidgets);
  });

  testWidgets('Desktop compact profile keeps a narrow keyboard-ready rail', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final runtime = ThemeRuntime.withResolver(
      ThemePackageResolver(
        package: ThemePackage.fromJson(liflyTestThemePackageJson),
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.desktop,
      ),
    );
    await tester.pumpWidget(_buildTestApp(runtime));
    await runtime.restore();
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.none);
    expect(rail.minWidth, 64);
    expect(find.byType(FocusTraversalGroup), findsWidgets);
  });

  testWidgets(
    'Phone shell keeps every destination touch target at least 48px',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final runtime = ThemeRuntime(
        registry: ThemeRegistry(),
        preferenceStore: _MemoryThemePreferenceStore(),
        appVersion: '0.8.0',
        platform: ThemeTargetPlatform.phone,
      );
      await tester.pumpWidget(_buildTestApp(runtime));
      await tester.pump();

      for (final label in ['首页', '备忘', 'AI', '记账', '任务']) {
        final target = find.byKey(Key('shell_destination_$label'));
        expect(target, findsOneWidget);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      }
    },
  );

  testWidgets('Wide shell keeps NavigationRail while restoring a theme', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final themeResolver = _WidgetThemeResolver();
    final themeRuntime = ThemeRuntime.withResolver(themeResolver);
    await tester.pumpWidget(_buildTestApp(themeRuntime));
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('首页'), findsWidgets);

    final switchedTheme = _switchedTheme();
    themeResolver.snapshot = switchedTheme;
    await themeRuntime.restore();
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme, same(switchedTheme.lightTheme));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
  });
}
