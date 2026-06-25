import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class MemoListPage extends StatefulWidget {
  const MemoListPage({super.key});

  @override
  State<MemoListPage> createState() => _MemoListPageState();
}

class _MemoListPageState extends State<MemoListPage> {
  late final MemoRepository _repo;
  final List<Memo> _items = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = MemoRepository(context.read<ApiClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _repo.list(limit: 50);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '备忘录加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建备忘失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备忘录')),
      body: AsyncContentScaffold(
        isLoading: _isLoading,
        error: _error,
        isEmpty: _items.isEmpty,
        onRefresh: _load,
        emptyIcon: Icons.note_outlined,
        emptyTitle: '还没有备忘录',
        emptySubtitle: '点击右下角新建，把想法先记下来。',
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _MemoTile(memo: _items[index]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating ? null : _createMemo,
        icon: _isCreating
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
  }
}

class _MemoTile extends StatelessWidget {
  final Memo memo;

  const _MemoTile({required this.memo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = DateFormat('MM/dd HH:mm').format(memo.createdAt.toLocal());
    final title = memo.displayTitle.trim().isEmpty ? '无标题' : memo.displayTitle.trim();
    final content = memo.contentMarkdown.trim();

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withAlpha(24),
          child: Icon(Icons.note_outlined, color: theme.colorScheme.primary),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.isNotEmpty && content != title)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(content, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 4),
            Text(createdAt, style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: memo.tags == null || memo.tags!.isEmpty
            ? null
            : Chip(
                label: Text(memo.tags!.first, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
      ),
    );
  }
}

class _MemoDraft {
  final String title;
  final String content;
  final List<String> tags;

  const _MemoDraft({required this.title, required this.content, required this.tags});
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
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: '标题')),
            TextField(
              controller: _contentController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '内容'),
            ),
            TextField(controller: _tagsController, decoration: const InputDecoration(labelText: '标签，逗号分隔')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
              _MemoDraft(title: _titleController.text.trim(), content: content, tags: tags),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
