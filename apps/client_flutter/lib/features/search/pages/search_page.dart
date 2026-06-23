import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/data/api/api_client.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>>? _results;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _entityTypeLabel(String type) {
    switch (type) {
      case 'memo':
        return '备忘';
      case 'ledger':
        return '记账';
      case 'task':
        return '任务';
      default:
        return type;
    }
  }

  IconData _entityTypeIconData(String type) {
    switch (type) {
      case 'memo':
        return Icons.note_outlined;
      case 'ledger':
        return Icons.account_balance_wallet_outlined;
      case 'task':
        return Icons.check_circle_outline;
      default:
        return Icons.search;
    }
  }

  Color _entityTypeColor(String type) {
    switch (type) {
      case 'memo':
        return Colors.blue;
      case 'ledger':
        return Colors.green;
      case 'task':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final response = await api.get('/search', params: {'q': trimmed});

      if (!mounted) return;

      if (response['success'] == true) {
        final data = response['data'];
        setState(() {
          _results = data is List ? data.cast<Map<String, dynamic>>() : [];
        });
      } else {
        setState(() {
          _error = response['message'] as String? ?? '搜索失败';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '搜索出错: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onClear() {
    _searchController.clear();
    setState(() {
      _results = null;
      _error = null;
    });
  }

  void _onResultTap(Map<String, dynamic> item) {
    final type = _entityTypeLabel(item['entity_type'] as String? ?? '');
    final title = item['title'] as String? ?? '';
    final snippet = item['snippet'] as String? ?? '';

    final buffer = StringBuffer();
    buffer.writeln('类型: $type');
    if (title.isNotEmpty) buffer.writeln('标题: $title');
    if (snippet.isNotEmpty) buffer.writeln('摘要: $snippet');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(buffer.toString().trim()),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索备忘录、记账、任务...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _onClear,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      );
    }

    if (_results == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('输入关键词开始搜索', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_results!.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('未找到相关内容', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _results!.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _results![index];
        final type = item['entity_type'] as String? ?? '';
        final title = item['title'] as String? ?? '';
        final snippet = item['snippet'] as String? ?? '';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _entityTypeColor(type).withAlpha(30),
            child: Icon(
              _entityTypeIconData(type),
              color: _entityTypeColor(type),
            ),
          ),
          title: Text(
            title.isNotEmpty ? title : (snippet.isNotEmpty ? snippet : '无标题'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: snippet.isNotEmpty && snippet != title
              ? Text(
                  snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: Chip(
            label: Text(
              _entityTypeLabel(type),
              style: const TextStyle(fontSize: 12),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
          onTap: () => _onResultTap(item),
        );
      },
    );
  }
}
