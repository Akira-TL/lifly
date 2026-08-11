import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/features/memo/pages/memo_detail_page.dart';
import 'package:client_flutter/shared/widgets/adaptive_action_fab.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:client_flutter/shared/widgets/dense_list_row.dart';
import 'package:client_flutter/shared/widgets/list_filter_bar.dart';
import 'package:client_flutter/shared/widgets/pagination_footer.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class MemoListPage extends StatefulWidget {
  const MemoListPage({super.key});

  @override
  State<MemoListPage> createState() => _MemoListPageState();
}

class _MemoListPageState extends State<MemoListPage> {
  static const _pageSize = 20;

  late final MemoRepository _repo;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<Memo> _items = [];
  String? _selectedType;
  int _total = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isCreating = false;
  bool _isSearching = false;
  String? _error;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _repo = MemoRepository(
      context.read<ApiClient>(),
      localCore: context.read<LocalCoreBridge>(),
      dataMode: context.read<LiflyDataMode>(),
    );
    _scrollController.addListener(_handleScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        !_hasMore ||
        _isLoading ||
        _isLoadingMore) {
      return;
    }
    final threshold = _scrollController.position.maxScrollExtent - 240;
    if (_scrollController.position.pixels >= threshold) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final page = await _repo.listPage(
        limit: _pageSize,
        offset: 0,
        type: _selectedType,
        q: _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '备忘录加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final page = await _repo.listPage(
        limit: _pageSize,
        offset: _items.length,
        type: _selectedType,
        q: _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载更多备忘失败：$error')));
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _createMemo() async {
    final result = await showDialog<_MemoDraft>(
      context: context,
      builder: (_) => const _MemoEditorDialog(),
    );
    if (result == null) return;

    setState(() => _isCreating = true);
    try {
      await _repo.create({
        'type': 'memo',
        'title': result.title.isEmpty ? null : result.title,
        'content_markdown': result.content,
        'tags': result.tags,
        'source': 'flutter',
      });
      await _loadFirstPage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建备忘失败：$error')));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _setType(String? type) {
    if (_selectedType == type) return;
    setState(() => _selectedType = type);
    _loadFirstPage();
  }

  void _openSearch() {
    setState(() => _isSearching = true);
  }

  void _closeSearch() {
    final hadQuery = _searchController.text.trim().isNotEmpty;
    _searchController.clear();
    setState(() => _isSearching = false);
    if (hadQuery) _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSearching) _closeSearch();
      },
      child: Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                key: const Key('memo_inline_search'),
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '搜索备忘',
                  border: InputBorder.none,
                  isDense: true,
                ),
                onSubmitted: (_) => _loadFirstPage(),
              )
            : const Text('备忘录'),
        actions: [
          if (_isSearching) ...[
            IconButton(
              tooltip: '执行搜索',
              onPressed: _loadFirstPage,
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: '退出搜索',
              onPressed: _closeSearch,
              icon: const Icon(Icons.close),
            ),
          ] else
            IconButton(
              tooltip: '搜索备忘',
              onPressed: _openSearch,
              icon: const Icon(Icons.search),
            ),
        ],
      ),
      body: Column(
        children: [
          _MemoFilterBar(selectedType: _selectedType, onTypeChanged: _setType),
          Expanded(
            child: AsyncContentScaffold(
              isLoading: _isLoading,
              error: _error,
              isEmpty: _items.isEmpty,
              onRefresh: _loadFirstPage,
              emptyIcon: Icons.note_outlined,
              emptyTitle: '还没有备忘录',
              emptySubtitle: '点击右下角新建，把想法先记下来。',
              child: ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
                itemCount: _items.length + 1,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return PaginationFooter(
                      total: _total,
                      current: _items.length,
                      hasMore: _hasMore,
                      isLoadingMore: _isLoadingMore,
                      onLoadMore: _loadMore,
                    );
                  }
                  return _MemoTile(
                    memo: _items[index],
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MemoDetailPage(
                            memoId: _items[index].id,
                            initialMemo: _items[index],
                          ),
                        ),
                      );
                      if (context.mounted) await _loadFirstPage();
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
        floatingActionButton: AdaptiveActionFab(
          heroTag: 'memo-create-fab',
          tooltip: '新建备忘',
          label: '新建',
          icon: Icons.add,
          isLoading: _isCreating,
          onPressed: _isCreating ? null : _createMemo,
        ),
      ),
    );
  }
}

class _MemoFilterBar extends StatelessWidget {
  final String? selectedType;
  final ValueChanged<String?> onTypeChanged;

  const _MemoFilterBar({
    required this.selectedType,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListFilterBar(
      selectedValue: selectedType,
      onChanged: onTypeChanged,
      options: const [
        ListFilterOption(label: '全部', value: null),
        ListFilterOption(label: '备忘', value: 'memo'),
        ListFilterOption(label: '日记', value: 'journal'),
        ListFilterOption(label: '剪藏', value: 'clip'),
        ListFilterOption(label: '文档', value: 'doc'),
      ],
    );
  }
}

class _MemoTile extends StatelessWidget {
  final Memo memo;
  final VoidCallback onTap;

  const _MemoTile({required this.memo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = DateFormat(
      'MM/dd HH:mm',
    ).format(memo.createdAt.toLocal());
    final title = memo.displayTitle.trim().isEmpty
        ? '无标题'
        : memo.displayTitle.trim();
    final content = memo.contentMarkdown.trim();

    final tags = memo.tags ?? const <String>[];
    final metadata = [
      _memoTypeLabel(memo.type),
      if (tags.isNotEmpty) tags.first,
      if (tags.length > 1) '+${tags.length - 1}',
    ].join(' · ');

    return DenseListRow(
      onTap: onTap,
      minHeight: 68,
      accentColor: _memoTypeColor(memo.type, theme.colorScheme),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: content.isNotEmpty && content != title
          ? Text(content, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      metadata: Row(
        children: [
          Expanded(
            child: Text(metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          Text(createdAt, key: Key('memo_timestamp_${memo.id}')),
        ],
      ),
    );
  }
}

String _memoTypeLabel(String type) {
  return switch (type) {
    'journal' => '日记',
    'clip' => '剪藏',
    'doc' => '文档',
    _ => '备忘',
  };
}

Color _memoTypeColor(String type, ColorScheme colorScheme) {
  return switch (type) {
    'journal' => colorScheme.tertiary,
    'clip' => colorScheme.secondary,
    'doc' => colorScheme.outline,
    _ => colorScheme.primary,
  };
}

class _MemoDraft {
  final String title;
  final String content;
  final List<String> tags;

  const _MemoDraft({
    required this.title,
    required this.content,
    required this.tags,
  });
}

class _MemoEditorDialog extends StatefulWidget {
  const _MemoEditorDialog();

  @override
  State<_MemoEditorDialog> createState() => _MemoEditorDialogState();
}

class _MemoEditorDialogState extends State<_MemoEditorDialog> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagsController = TextEditingController();
  String? _contentError;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建备忘'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '标题'),
              onChanged: (_) {
                if (_contentError != null) setState(() => _contentError = null);
              },
            ),
            TextField(
              controller: _contentController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: '内容',
                errorText: _contentError,
              ),
              onChanged: (_) {
                if (_contentError != null) setState(() => _contentError = null);
              },
            ),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(labelText: '标签，逗号分隔'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            final content = _contentController.text.trim();
            if (title.isEmpty && content.isEmpty) {
              setState(() => _contentError = '请输入标题或内容');
              return;
            }
            final tags = _tagsController.text
                .split(RegExp(r'[,，]'))
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList();
            Navigator.pop(
              context,
              _MemoDraft(
                title: title,
                content: content,
                tags: tags,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
