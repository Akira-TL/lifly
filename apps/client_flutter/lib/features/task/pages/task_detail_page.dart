import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/domain/entities/task.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TaskDetailPage extends StatefulWidget {
  final String taskId;
  final Task? initialTask;

  const TaskDetailPage({super.key, required this.taskId, this.initialTask});

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  late final TaskRepository _repo;
  Task? _task;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = TaskRepository(context.read<ApiClient>());
    _task = widget.initialTask;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = _task == null;
      _error = null;
    });
    try {
      final task = await _repo.get(widget.taskId);
      if (!mounted) return;
      setState(() => _task = task);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '任务详情加载失败：$error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editTask() async {
    final task = _task;
    if (task == null) return;
    final draft = await showDialog<_TaskEditDraft>(context: context, builder: (_) => _TaskEditDialog(task: task));
    if (draft == null) return;

    setState(() => _isSaving = true);
    try {
      final updated = await _repo.update(task.id, {
        'title': draft.title,
        'description': draft.description.isEmpty ? null : draft.description,
        'priority': draft.priority,
        'task_status': draft.taskStatus,
        'due_at': task.dueAt?.toUtc().toIso8601String(),
        'remind_at': task.remindAt?.toUtc().toIso8601String(),
      });
      if (!mounted) return;
      setState(() => _task = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('任务已更新')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新任务失败：$error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _completeTask() async {
    final task = _task;
    if (task == null || task.isDone) return;
    setState(() => _isSaving = true);
    try {
      final updated = await _repo.complete(task.id);
      if (!mounted) return;
      setState(() => _task = updated);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('任务已完成')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('完成任务失败：$error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeTask() async {
    final task = _task;
    if (task == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: const Text('该任务将不再出现在列表中。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.delete(task.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除任务失败：$error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务详情'),
        actions: [
          IconButton(onPressed: _isSaving ? null : _editTask, icon: const Icon(Icons.edit_outlined)),
          IconButton(onPressed: _isSaving ? null : _removeTask, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : task == null
                  ? const EmptyState(icon: Icons.check_circle_outline, title: '未找到任务', subtitle: '该任务不存在或已被移除。')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(task.title, style: Theme.of(context).textTheme.headlineSmall)),
                              Checkbox(value: task.isDone, onChanged: task.isDone || _isSaving ? null : (_) => _completeTask()),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(task.description?.isNotEmpty == true ? task.description! : '暂无描述'),
                          const SizedBox(height: 20),
                          _DetailRow(label: '状态', value: task.taskStatus),
                          _DetailRow(label: '优先级', value: task.priority),
                          _DetailRow(label: '到期时间', value: _formatDate(task.dueAt)),
                          _DetailRow(label: '提醒时间', value: _formatDate(task.remindAt)),
                          _DetailRow(label: '完成时间', value: _formatDate(task.completedAt)),
                          _DetailRow(label: '创建时间', value: _formatDate(task.createdAt)),
                        ],
                      ),
                    ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '无';
    return DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TaskEditDraft {
  final String title;
  final String description;
  final String priority;
  final String taskStatus;

  const _TaskEditDraft({required this.title, required this.description, required this.priority, required this.taskStatus});
}

class _TaskEditDialog extends StatefulWidget {
  final Task task;

  const _TaskEditDialog({required this.task});

  @override
  State<_TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<_TaskEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _priority;
  late String _taskStatus;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController = TextEditingController(text: widget.task.description ?? '');
    _priority = widget.task.priority;
    _taskStatus = widget.task.taskStatus;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑任务'),
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
            DropdownButtonFormField<String>(
              initialValue: _taskStatus,
              decoration: const InputDecoration(labelText: '状态'),
              items: const [
                DropdownMenuItem(value: 'todo', child: Text('待办')),
                DropdownMenuItem(value: 'doing', child: Text('进行中')),
                DropdownMenuItem(value: 'done', child: Text('已完成')),
                DropdownMenuItem(value: 'cancelled', child: Text('已取消')),
              ],
              onChanged: (value) => setState(() => _taskStatus = value ?? 'todo'),
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
            Navigator.pop(context, _TaskEditDraft(title: title, description: _descriptionController.text.trim(), priority: _priority, taskStatus: _taskStatus));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
