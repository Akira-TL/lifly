import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/repositories/task_repository.dart';
import 'package:client_flutter/domain/entities/task.dart';
import 'package:client_flutter/features/task/widgets/task_date_time_field.dart';
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
    _repo = TaskRepository(
      context.read<ApiClient>(),
      localCore: context.read<LocalCoreBridge>(),
      dataMode: context.read<LiflyDataMode>(),
    );
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
    final draft = await showDialog<_TaskEditDraft>(
      context: context,
      builder: (_) => _TaskEditDialog(task: task),
    );
    if (draft == null) return;

    setState(() => _isSaving = true);
    try {
      final reminderChanged =
          task.remindAt?.toUtc().millisecondsSinceEpoch !=
          draft.remindAt?.toUtc().millisecondsSinceEpoch;
      final updated = await _repo.update(task.id, {
        'title': draft.title,
        'description': draft.description.isEmpty ? null : draft.description,
        'priority': draft.priority,
        'task_status': draft.taskStatus,
        'due_at': draft.dueAt?.toUtc().toIso8601String(),
        'remind_at': draft.remindAt?.toUtc().toIso8601String(),
      });
      Object? reminderError;
      if (reminderChanged) {
        try {
          await _repo.setManualReminder(task.id, draft.remindAt);
        } catch (error) {
          reminderError = error;
        }
      }
      if (!mounted) return;
      setState(() => _task = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reminderError == null
                ? '任务已更新'
                : '任务已更新，但提醒同步失败：$reminderError',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新任务失败：$error')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('任务已完成')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('完成任务失败：$error')));
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
      await _repo.delete(task.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除任务失败：$error')));
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
          IconButton(
            tooltip: '编辑任务',
            onPressed: _isSaving ? null : _editTask,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除任务',
            onPressed: _isSaving ? null : _removeTask,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: '正在加载任务')
          : _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : task == null
          ? const EmptyState(
              icon: Icons.check_circle_outline,
              title: '未找到任务',
              subtitle: '该任务不存在或已被移除。',
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      Checkbox(
                        value: task.isDone,
                        onChanged: task.isDone || _isSaving
                            ? null
                            : (_) => _completeTask(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.description?.isNotEmpty == true
                        ? task.description!
                        : '暂无描述',
                  ),
                  const SizedBox(height: 20),
                  _DetailRow(
                    label: '状态',
                    value: _taskStatusLabel(task.taskStatus),
                  ),
                  _DetailRow(
                    label: '优先级',
                    value: _taskPriorityLabel(task.priority),
                  ),
                  _DetailRow(label: '到期时间', value: _formatDate(task.dueAt)),
                  _DetailRow(label: '提醒时间', value: _formatDate(task.remindAt)),
                  _DetailRow(
                    label: '完成时间',
                    value: _formatDate(task.completedAt),
                  ),
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

String _taskStatusLabel(String status) {
  return switch (status) {
    'todo' => '待办',
    'doing' => '进行中',
    'done' => '已完成',
    'cancelled' => '已取消',
    _ => '其他状态',
  };
}

String _taskPriorityLabel(String priority) {
  return switch (priority) {
    'low' => '低优先级',
    'normal' => '普通',
    'high' => '高优先级',
    'urgent' => '紧急',
    _ => '普通',
  };
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
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
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
  final DateTime? dueAt;
  final DateTime? remindAt;

  const _TaskEditDraft({
    required this.title,
    required this.description,
    required this.priority,
    required this.taskStatus,
    required this.dueAt,
    required this.remindAt,
  });
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
  DateTime? _dueAt;
  DateTime? _remindAt;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController = TextEditingController(
      text: widget.task.description ?? '',
    );
    _priority = widget.task.priority;
    _taskStatus = widget.task.taskStatus;
    _dueAt = widget.task.dueAt?.toLocal();
    _remindAt = widget.task.remindAt?.toLocal();
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
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '标题',
                errorText: _titleError,
              ),
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: '描述'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              decoration: const InputDecoration(labelText: '优先级'),
              items: const [
                DropdownMenuItem(value: 'low', child: Text('低')),
                DropdownMenuItem(value: 'normal', child: Text('普通')),
                DropdownMenuItem(value: 'high', child: Text('高')),
                DropdownMenuItem(value: 'urgent', child: Text('紧急')),
              ],
              onChanged: (value) =>
                  setState(() => _priority = value ?? 'normal'),
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
              onChanged: (value) =>
                  setState(() => _taskStatus = value ?? 'todo'),
            ),
            TaskDateTimeField(
              label: '到期时间',
              value: _dueAt,
              pickerKey: const Key('task_due_picker'),
              clearKey: const Key('task_due_clear'),
              onChanged: (value) => setState(() => _dueAt = value),
            ),
            TaskDateTimeField(
              label: '提醒时间',
              value: _remindAt,
              pickerKey: const Key('task_reminder_picker'),
              clearKey: const Key('task_reminder_clear'),
              onChanged: (value) => setState(() => _remindAt = value),
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
            if (title.isEmpty) {
              setState(() => _titleError = '请输入任务标题');
              return;
            }
            Navigator.pop(
              context,
              _TaskEditDraft(
                title: title,
                description: _descriptionController.text.trim(),
                priority: _priority,
                taskStatus: _taskStatus,
                dueAt: _dueAt,
                remindAt: _remindAt,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
