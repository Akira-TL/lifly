import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/home_overview_repository.dart';
import 'package:client_flutter/domain/entities/home_overview.dart';
import 'package:client_flutter/features/home/widgets/home_dashboard_view.dart';
import 'package:client_flutter/features/search/pages/search_page.dart';
import 'package:client_flutter/features/settings/settings_page.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

typedef HomeOverviewLoader = Future<HomeOverview> Function(BuildContext context);

class HomePage extends StatefulWidget {
  final HomeOverviewLoader? loadOverview;

  const HomePage({super.key, this.loadOverview});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
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
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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

    return HomeDashboardView(overview: overview, onRefresh: _loadOverview);
  }
}
