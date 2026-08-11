import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/home_overview_repository.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:client_flutter/features/home/widgets/home_dashboard_view.dart';
import 'package:client_flutter/features/home/widgets/home_focus_view.dart';
import 'package:client_flutter/features/search/pages/search_page.dart';
import 'package:client_flutter/features/settings/settings_page.dart';
import 'package:client_flutter/features/task/pages/task_list_page.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

typedef HomeOverviewLoader =
    Future<HomeOverview> Function(BuildContext context);
typedef HomeTaskCompleter = Future<void> Function(String taskId);

class HomePage extends StatefulWidget {
  final HomeOverviewLoader? loadOverview;
  final HomeTaskCompleter? completeTask;

  const HomePage({super.key, this.loadOverview, this.completeTask});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  HomeOverview? _overview;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final overview = await _resolveOverview();
      if (!mounted) return;
      setState(() => _overview = overview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '首页概览加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<HomeOverview> _resolveOverview() {
    final customLoader = widget.loadOverview;
    if (customLoader != null) return customLoader(context);

    return HomeOverviewRepository(
      context.read<ApiClient>(),
      localCore: context.read<LocalCoreBridge>(),
      dataMode: context.read<LiflyDataMode>(),
    ).load();
  }

  Future<void> _completeAttentionTask(HomeAttentionItem item) async {
    if (item.entityType != 'task' || item.entityId.isEmpty) return;
    final customCompleter = widget.completeTask;
    try {
      if (customCompleter != null) {
        await customCompleter(item.entityId);
      } else {
        await TaskRepository(
          context.read<ApiClient>(),
          localCore: context.read<LocalCoreBridge>(),
          dataMode: context.read<LiflyDataMode>(),
        ).complete(item.entityId);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('完成任务失败：$error')));
      return;
    }

    if (!mounted) return;
    setState(() {
      final overview = _overview;
      if (overview != null) {
        _overview = _withoutAttentionItem(overview, item.entityId);
      }
    });
    if (customCompleter != null) return;

    try {
      final refreshed = await _resolveOverview();
      if (mounted) setState(() => _overview = refreshed);
    } catch (_) {
      // The task is already complete; keep the optimistic queue instead of
      // reporting the successful action as a failure.
    }
  }

  HomeOverview _withoutAttentionItem(HomeOverview overview, String taskId) {
    return HomeOverview(
      schemaVersion: overview.schemaVersion,
      generatedAt: overview.generatedAt,
      userTimezone: overview.userTimezone,
      sourceMode: overview.sourceMode,
      todayMetrics: overview.todayMetrics,
      financeOverview: overview.financeOverview,
      attentionItems: overview.attentionItems
          .where((item) => item.entityId != taskId)
          .toList(growable: false),
      dailyTrend: overview.dailyTrend,
      recentActivity: overview.recentActivity,
      syncSummary: overview.syncSummary,
      importSummary: overview.importSummary,
      settingsSummary: overview.settingsSummary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        Theme.of(context).extension<ThemePlatformProfile>() ??
        ThemePlatformProfile.defaults(ThemeTargetPlatform.phone);
    final web = profile.platform == ThemeTargetPlatform.web;
    return Scaffold(
      appBar: web ? _buildWebAppBar() : _buildDefaultAppBar(),
      body: _buildBody(web: web),
    );
  }

  PreferredSizeWidget _buildWebAppBar() {
    final theme = Theme.of(context);
    return AppBar(
      key: const Key('home_focus_topbar'),
      toolbarHeight: 68,
      titleSpacing: 28,
      centerTitle: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '今天',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.55,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _webDateLabel(DateTime.now()),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '搜索',
          style: IconButton.styleFrom(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            backgroundColor: theme.colorScheme.surface,
          ),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
          icon: const Icon(Icons.search, size: 18),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('home_schedule_action'),
          tooltip: '日程',
          style: IconButton.styleFrom(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            backgroundColor: theme.colorScheme.surface,
          ),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TaskListPage())),
          icon: const Icon(Icons.calendar_today_outlined, size: 17),
        ),
        const SizedBox(width: 16),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildDefaultAppBar() {
    return AppBar(
      title: const Text('首页'),
      actions: [
        IconButton(
          tooltip: '全局搜索',
          icon: const Icon(Icons.search_outlined),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        ),
        IconButton(
          tooltip: '设置',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBody({required bool web}) {
    if (_isLoading) {
      return const LoadingState(message: '正在整理今天需要关注的内容');
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _loadOverview);
    }

    final overview = _overview;
    if (overview == null) {
      return ErrorState(message: '首页概览为空', onRetry: _loadOverview);
    }

    if (web) {
      return HomeFocusView(
        overview: overview,
        onRefresh: _loadOverview,
        onCompleteTask: _completeAttentionTask,
      );
    }
    return HomeDashboardView(
      overview: overview,
      onRefresh: _loadOverview,
      onCompleteTask: _completeAttentionTask,
    );
  }
}

String _webDateLabel(DateTime date) {
  const weekdays = ['', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  return '${date.year} 年 ${date.month} 月 ${date.day} 日 · ${weekdays[date.weekday]}';
}
