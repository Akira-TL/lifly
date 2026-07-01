import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class MemoDetailPage extends StatefulWidget {
  final String memoId;
  final Memo? initialMemo;

  const MemoDetailPage({super.key, required this.memoId, this.initialMemo});

  @override
  State<MemoDetailPage> createState() => _MemoDetailPageState();
}

class _MemoDetailPageState extends State<MemoDetailPage> {
  late final MemoRepository _repo;
  Memo? _memo;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = MemoRepository(
      context.read<ApiClient>(),
      localCore: context.read<LocalCoreBridge>(),
      dataMode: context.read<LiflyDataMode>(),
    );
    _memo = widget.initialMemo;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _memo == null;
      _error = null;
    });
    try {
      final memo = await _repo.get(widget.memoId);
      if (!mounted) return;
      setState(() => _memo = memo);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '备忘详情加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editMemo() async {
    final memo = _memo;
    if (memo == null) return;
    final draft = await showDialog<_MemoEditDraft>(
      context: context,
      builder: (_) => _MemoEditDialog(memo: memo),
    );
    if (draft == null) return;

    setState(() => _isSaving = true);
    try {
      final updated = await _repo.update(memo.id, {
        'title': draft.title.isEmpty ? null : draft.title,
        'content_markdown': draft.content,
        'tags': draft.tags,
        'mood': draft.mood.isEmpty ? null : draft.mood,
        'type': memo.type,
      });
      if (!mounted) return;
      setState(() => _memo = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('备忘已更新')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新备忘失败：$error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteMemo() async {
    final memo = _memo;
    if (memo == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除备忘？'),
        content: const Text('删除后会进入后端回收/删除状态，列表将不再显示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.delete(memo.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除备忘失败：$error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memo = _memo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('备忘详情'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _editMemo,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: _isSaving ? null : _deleteMemo,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : memo == null
          ? const EmptyState(
              icon: Icons.note_outlined,
              title: '未找到备忘',
              subtitle: '该备忘不存在或已被删除。',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    memo.displayTitle.trim().isEmpty
                        ? '无标题'
                        : memo.displayTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatMeta(memo),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (memo.tags != null && memo.tags!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: memo.tags!
                          .map((tag) => Chip(label: Text(tag)))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    memo.contentMarkdown.isEmpty
                        ? '暂无内容'
                        : memo.contentMarkdown,
                  ),
                ],
              ),
            ),
    );
  }

  String _formatMeta(Memo memo) {
    final updated = DateFormat(
      'yyyy-MM-dd HH:mm',
    ).format(memo.updatedAt.toLocal());
    final mood = memo.mood == null || memo.mood!.isEmpty
        ? ''
        : ' · ${memo.mood}';
    return '${memo.type} · ${memo.status} · 更新于 $updated$mood';
  }
}

class _MemoEditDraft {
  final String title;
  final String content;
  final List<String> tags;
  final String mood;

  const _MemoEditDraft({
    required this.title,
    required this.content,
    required this.tags,
    required this.mood,
  });
}

class _MemoEditDialog extends StatefulWidget {
  final Memo memo;

  const _MemoEditDialog({required this.memo});

  @override
  State<_MemoEditDialog> createState() => _MemoEditDialogState();
}

class _MemoEditDialogState extends State<_MemoEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  late final TextEditingController _moodController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.memo.title ?? '');
    _contentController = TextEditingController(
      text: widget.memo.contentMarkdown,
    );
    _tagsController = TextEditingController(
      text: widget.memo.tags?.join(', ') ?? '',
    );
    _moodController = TextEditingController(text: widget.memo.mood ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    _moodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑备忘'),
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
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(labelText: '内容'),
            ),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(labelText: '标签，逗号分隔'),
            ),
            TextField(
              controller: _moodController,
              decoration: const InputDecoration(labelText: '心情'),
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
              _MemoEditDraft(
                title: _titleController.text.trim(),
                content: content,
                tags: tags,
                mood: _moodController.text.trim(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
