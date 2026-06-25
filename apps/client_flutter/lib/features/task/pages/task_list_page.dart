import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/domain/entities/task.dart';
import 'package:client_flutter/features/task/pages/task_detail_page.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  static const _pageSize = 20;

  late final TaskRepository _repo;
  final _scrollController = ScrollController();
  final List<Task> _items = [];
  String? _taskStatus;
  int _total = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isCreating = false;
  String? _error;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _repo = TaskRepository(context.read<ApiClient>());
    _scrollController.addListener(_handleScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || !_hasMore || _isLoading || _isLoadingMore) return;
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
      final page = await _repo.listPage(limit: _pageSize, offset: 0, taskStatus: _taskStatus);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '任务加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);

    try {
      final page = await _repo.listPage(limit: _pageSize, offset: _items.length, taskStatus: _taskStatus);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载更多任务失败：$error')));
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _createTask() async {
    final draft = await showDialog<_TaskDraft>(context: context, builder: (_) => const _TaskEditorDialog());
    if (draft == null) return;

    setState(() => _isCreating = true);
    try {
      await _repo.create({
        'title': draft.title,
        'description': draft.description.isEmpty ? null : draft.description,
        'priority': draft.priority,
        'source': 'flutter',
      });
      await _loadFirstPage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建任务失败：$error')));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _completeTask(Task task) async {
    if (task.isDone) return;
    try {
      await _repo.complete(task.id);
      await _loadFirstPage();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完成任务失败：$error')));
    }
  }

  void _setTaskStatus(String? taskStatus) {
    if (_taskStatus == taskStatus) return;
    setState(() => _taskStatus = taskStatus);
    _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务')),
      body: Column(
        children: [
          _TaskFilterBar(selectedTaskStatus: _taskStatus, onTaskStatusChanged: _setTaskStatus),
          Expanded(
            child: AsyncContentScaffold(
              isLoading: _isLoading,
              error: _error,
              isEmpty: _items.isEmpty,
              onRefresh: _loadFirstPage,
              emptyIcon: Icons.check_circle_outline,
              emptyTitle: '还没有任务',
              emptySubtitle: '点击右下角新建任务，先打通真实 API 写入。',
              child: ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: _items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return _PaginationFooter(
                      total: _total,
                      current: _items.length,
                      hasMore: _hasMore,
                      isLoadingMore: _isLoadingMore,
                      onLoadMore: _loadMore,
                    );
                  }
                  return _TaskTile(
                    task: _items[index],
                    onComplete: () => _completeTask(_items[index]),
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskDetailPage(taskId: _items[index].id, initialTask: _items[index]),
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
        heroTag: 'task-create-fab',
        onPressed: _isCreating ? null : _createTask,
        icon: _isCreating
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
  }
}

class _TaskFilterBar extends StatelessWidget {
  final String? selectedTaskStatus;
  final ValueChanged<String?> onTaskStatusChanged;

  const _TaskFilterBar({required this.selectedTaskStatus, required this.onTaskStatusChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            _FilterChipOption(label: '全部', selected: selectedTaskStatus == null, onTap: () => onTaskStatusChanged(null)),
            _FilterChipOption(label: '待办', selected: selectedTaskStatus == 'todo', onTap: () => onTaskStatusChanged('todo')),
            _FilterChipOption(label: '进行中', selected: selectedTaskStatus == 'doing', onTap: () => onTaskStatusChanged('doing')),
            _FilterChipOption(label: '已完成', selected: selectedTaskStatus == 'done', onTap: () => onTaskStatusChanged('done')),
          ],
        ),
      ),
    );
  }
}

class _FilterChipOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  final int total;
  final int current;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  const _PaginationFooter({required this.total, required this.current, required this.hasMore, required this.isLoadingMore, required this.onLoadMore});

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: hasMore
            ? OutlinedButton(onPressed: onLoadMore, child: Text('加载更多（$current/$total）'))
            : Text('已显示 $current/$total', style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onComplete;
  final VoidCallback onTap;

  const _TaskTile({required this.task, required this.onComplete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueLabel = task.dueAt == null ? null : DateFormat('MM/dd HH:mm').format(task.dueAt!.toLocal());
    final statusLabel = task.isDone ? '已完成' : task.isOverdue ? '已逾期' : '进行中';
    final statusColor = task.isDone
        ? Colors.green
        : task.isOverdue
            ? theme.colorScheme.error
            : theme.colorScheme.primary;

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: statusColor.withAlpha(24),
          child: Icon(task.isDone ? Icons.done : Icons.check_circle_outline, color: statusColor),
        ),
        title: Text(
          task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: task.isDone ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description != null && task.description!.isNotEmpty)
              Text(task.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text([statusLabel, task.priority, ?dueLabel].join(' · '), style: theme.textTheme.bodySmall),
          ],
        ),
        trailing: Checkbox(
          value: task.isDone,
          onChanged: task.isDone ? null : (_) => onComplete(),
        ),
      ),
    );
  }
}

class _TaskDraft {
  final String title;
  final String description;
  final String priority;

  const _TaskDraft({required this.title, required this.description, required this.priority});
}

class _TaskEditorDialog extends StatefulWidget {
  const _TaskEditorDialog();

  @override
  State<_TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<_TaskEditorDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _priority = 'normal';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: '标题')),
            TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: '描述')),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: '优先级'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('低')),
                DropdownMenuItem(value: 'normal', child: Text('普通')),
                DropdownMenuItem(value: 'high', child: Text('高')),
                DropdownMenuItem(value: 'urgent', child: Text('紧急')),
              ],
              onChanged: (value) => setState(() => _priority = value ?? 'normal'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(
              context,
              _TaskDraft(title: title, description: _descriptionController.text.trim(), priority: _priority),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
