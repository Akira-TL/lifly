import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/features/memo/pages/memo_detail_page.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备忘录')),
      body: Column(
        children: [
          _MemoFilterBar(
            selectedType: _selectedType,
            searchController: _searchController,
            onTypeChanged: _setType,
            onSearch: _loadFirstPage,
          ),
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'memo-create-fab',
        onPressed: _isCreating ? null : _createMemo,
        icon: _isCreating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
  }
}

class _MemoFilterBar extends StatelessWidget {
  final String? selectedType;
  final TextEditingController searchController;
  final ValueChanged<String?> onTypeChanged;
  final VoidCallback onSearch;

  const _MemoFilterBar({
    required this.selectedType,
    required this.searchController,
    required this.onTypeChanged,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            ListFilterBar(
              selectedValue: selectedType,
              padding: EdgeInsets.zero,
              onChanged: onTypeChanged,
              options: const [
                ListFilterOption(label: '全部', value: null),
                ListFilterOption(label: '备忘', value: 'memo'),
                ListFilterOption(label: '日记', value: 'journal'),
                ListFilterOption(label: '剪藏', value: 'clip'),
                ListFilterOption(label: '文档', value: 'doc'),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: onSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
                labelText: '搜索备忘',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ],
        ),
      ),
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
      createdAt,
    ].join(' · ');

    return DenseListRow(
      onTap: onTap,
      minHeight: 68,
      accentColor: _memoTypeColor(memo.type, theme.colorScheme),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: content.isNotEmpty && content != title
          ? Text(content, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      metadata: Text(metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
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
            ),
            TextField(
              controller: _contentController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '内容'),
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
            final content = _contentController.text.trim();
            if (content.isEmpty) return;
            final tags = _tagsController.text
                .split(RegExp(r'[,，]'))
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toList();
            Navigator.pop(
              context,
              _MemoDraft(
                title: _titleController.text.trim(),
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
