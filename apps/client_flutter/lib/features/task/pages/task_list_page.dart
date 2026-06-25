import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/domain/entities/task.dart';
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
  late final TaskRepository _repo;
  final List<Task> _items = [];
  bool _isLoading = true;
  bool _isCreating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = TaskRepository(context.read<ApiClient>());
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
      setState(() => _error = '任务加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      await _load();
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
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完成任务失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('任务')),
      body: AsyncContentScaffold(
        isLoading: _isLoading,
        error: _error,
        isEmpty: _items.isEmpty,
        onRefresh: _load,
        emptyIcon: Icons.check_circle_outline,
        emptyTitle: '还没有任务',
        emptySubtitle: '点击右下角新建任务，先打通真实 API 写入。',
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _TaskTile(
            task: _items[index],
            onComplete: () => _completeTask(_items[index]),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isCreating ? null : _createTask,
        icon: _isCreating
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onComplete;

  const _TaskTile({required this.task, required this.onComplete});

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
      child: CheckboxListTile(
        value: task.isDone,
        onChanged: task.isDone ? null : (_) => onComplete(),
        secondary: CircleAvatar(
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
        controlAffinity: ListTileControlAffinity.trailing,
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
