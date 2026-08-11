import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/asset_repository.dart';
import 'package:client_flutter/data/repositories/memo_repository.dart';
import 'package:client_flutter/domain/entities/memo.dart';
import 'package:client_flutter/shared/widgets/asset_card.dart';
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
  late final AssetRepository _assetRepo;
  Memo? _memo;
  List<MemoAssetRef> _assets = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAddingAsset = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _repo = MemoRepository(
      api,
      localCore: context.read<LocalCoreBridge>(),
      dataMode: context.read<LiflyDataMode>(),
    );
    _assetRepo = AssetRepository(api);
    _memo = widget.initialMemo;
    _assets = widget.initialMemo?.assets ?? const [];
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
      setState(() {
        _memo = memo;
        _assets = memo.assets;
      });
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
        content: const Text('删除后将不再显示在备忘列表中。'),
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

  Future<void> _addExternalAsset() async {
    final memo = _memo;
    if (memo == null) return;
    final draft = await showDialog<_ExternalAssetDraft>(
      context: context,
      builder: (_) => const _ExternalAssetDialog(),
    );
    if (draft == null) return;

    setState(() => _isAddingAsset = true);
    try {
      final asset = await _assetRepo.registerExternalUrl(
        externalUrl: draft.url,
        title: draft.title.isEmpty ? null : draft.title,
      );
      final refs = await _repo.bindAsset(memo.id, asset.id);
      if (!mounted) return;
      setState(() => _assets = refs);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('外链已添加到备忘')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加附件失败：$error')));
    } finally {
      if (mounted) setState(() => _isAddingAsset = false);
    }
  }

  Future<void> _unbindAsset(MemoAssetRef ref) async {
    final memo = _memo;
    if (memo == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除附件引用？'),
        content: Text('只会从该备忘中移除引用，不会删除附件：${ref.asset.displayName}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.unbindAsset(memo.id, ref.assetId);
      final refs = await _repo.listAssets(memo.id);
      if (!mounted) return;
      setState(() => _assets = refs);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('移除附件失败：$error')));
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
            tooltip: '编辑备忘',
            onPressed: _isSaving ? null : _editMemo,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除备忘',
            onPressed: _isSaving ? null : _deleteMemo,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: '正在加载备忘')
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
                  const SizedBox(height: 24),
                  _MemoAssetsSection(
                    refs: _assets,
                    isAdding: _isAddingAsset,
                    onAddExternalLink: _addExternalAsset,
                    onRemove: _isSaving ? null : _unbindAsset,
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
    return '${_memoTypeLabel(memo.type)} · ${_memoStatusLabel(memo.status)} · 更新于 $updated$mood';
  }
}

String _memoTypeLabel(String type) {
  return switch (type) {
    'memo' => '备忘',
    'journal' => '日记',
    'clip' => '剪藏',
    'doc' => '文档',
    _ => '其他',
  };
}

String _memoStatusLabel(String status) {
  return switch (status) {
    'active' => '正常',
    'archived' => '已归档',
    'deleted' => '已删除',
    _ => '其他状态',
  };
}

class _MemoAssetsSection extends StatelessWidget {
  final List<MemoAssetRef> refs;
  final bool isAdding;
  final VoidCallback onAddExternalLink;
  final ValueChanged<MemoAssetRef>? onRemove;

  const _MemoAssetsSection({
    required this.refs,
    required this.isAdding,
    required this.onAddExternalLink,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('附件引用', style: theme.textTheme.titleMedium)),
            TextButton.icon(
              onPressed: isAdding ? null : onAddExternalLink,
              icon: isAdding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_link),
              label: const Text('添加外链'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (refs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '还没有附件。可以添加外部链接，文件附件可从附件库统一管理。',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          ...refs.map(
            (ref) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AssetCard(
                asset: ref.asset,
                trailing: IconButton(
                  tooltip: '移除引用',
                  onPressed: onRemove == null ? null : () => onRemove!(ref),
                  icon: const Icon(Icons.link_off),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ExternalAssetDraft {
  final String title;
  final String url;

  const _ExternalAssetDraft({required this.title, required this.url});
}

class _ExternalAssetDialog extends StatefulWidget {
  const _ExternalAssetDialog();

  @override
  State<_ExternalAssetDialog> createState() => _ExternalAssetDialogState();
}

class _ExternalAssetDialogState extends State<_ExternalAssetDialog> {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加外链附件'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final url = _urlController.text.trim();
            if (url.isEmpty) return;
            Navigator.pop(
              context,
              _ExternalAssetDraft(
                title: _titleController.text.trim(),
                url: url,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
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
  String? _contentError;

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
              onChanged: (_) {
                if (_contentError != null) setState(() => _contentError = null);
              },
            ),
            TextField(
              controller: _contentController,
              minLines: 4,
              maxLines: 8,
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
              _MemoEditDraft(
                title: title,
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
