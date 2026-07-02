import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';
import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AiCapturePage extends StatefulWidget {
  const AiCapturePage({super.key});

  @override
  State<AiCapturePage> createState() => _AiCapturePageState();
}

class _AiCapturePageState extends State<AiCapturePage> {
  final TextEditingController _textController = TextEditingController();
  final Set<int> _selectedIndexes = <int>{};

  AiCaptureParseResult? _parseResult;
  AiCaptureCommitResult? _commitResult;
  AiCaptureUndoResult? _undoResult;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AiCaptureService>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 写入'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                service.modeLabel,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ModeNotice(service: service),
          const SizedBox(height: 12),
          TextField(
            controller: _textController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '自然语言输入',
              hintText: '例如：在食堂花了18元，提醒我晚上复盘，记一下今天状态不错',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading || !service.supportsCloudCapture ? null : _parse,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('解析候选动作'),
          ),
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(message: _error!),
          ],
          if (_parseResult != null) ...[
            const SizedBox(height: 16),
            _CandidateActionsCard(
              result: _parseResult!,
              selectedIndexes: _selectedIndexes,
              onChanged: (index, selected) {
                setState(() {
                  if (selected) {
                    _selectedIndexes.add(index);
                  } else {
                    _selectedIndexes.remove(index);
                  }
                });
              },
              onCommit: _selectedIndexes.isEmpty || _loading ? null : _commit,
            ),
          ],
          if (_commitResult != null) ...[
            const SizedBox(height: 16),
            _CommitResultCard(
              result: _commitResult!,
              onUndo: _commitResult!.undoToken.isEmpty || _loading ? null : _undo,
            ),
          ],
          if (_undoResult != null) ...[
            const SizedBox(height: 16),
            _UndoResultCard(result: _undoResult!),
          ],
        ],
      ),
    );
  }

  Future<void> _parse() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入要解析的内容。');
      return;
    }

    await _run(() async {
      final service = context.read<AiCaptureService>();
      final result = await service.parse(text: text);
      setState(() {
        _parseResult = result;
        _commitResult = null;
        _undoResult = null;
        _selectedIndexes
          ..clear()
          ..addAll(List<int>.generate(result.actions.length, (index) => index));
      });
    });
  }

  Future<void> _commit() async {
    final result = _parseResult;
    if (result == null) return;

    await _run(() async {
      final service = context.read<AiCaptureService>();
      final commit = await service.commit(
        captureId: result.captureId,
        selectedActionIndexes: _selectedIndexes.toList()..sort(),
      );
      setState(() {
        _commitResult = commit;
        _undoResult = null;
      });
    });
  }

  Future<void> _undo() async {
    final result = _commitResult;
    if (result == null || result.undoToken.isEmpty) return;

    await _run(() async {
      final service = context.read<AiCaptureService>();
      final undo = await service.undo(undoToken: result.undoToken);
      setState(() => _undoResult = undo);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _ModeNotice extends StatelessWidget {
  const _ModeNotice({required this.service});

  final AiCaptureService service;

  @override
  Widget build(BuildContext context) {
    final message = service.supportsCloudCapture
        ? '当前使用 Cloud MCP。提交前请确认候选动作，写入后可通过 undo_token 撤销。'
        : '当前是 Local Core 模式。Local MCP 属于桌面端 host，本客户端暂不直接启动 MCP Server。';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(service.supportsCloudCapture ? Icons.cloud_done_outlined : Icons.desktop_windows_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _CandidateActionsCard extends StatelessWidget {
  const _CandidateActionsCard({
    required this.result,
    required this.selectedIndexes,
    required this.onChanged,
    required this.onCommit,
  });

  final AiCaptureParseResult result;
  final Set<int> selectedIndexes;
  final void Function(int index, bool selected) onChanged;
  final VoidCallback? onCommit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('候选动作', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('capture_id: ${result.captureId}'),
            const SizedBox(height: 8),
            for (var i = 0; i < result.actions.length; i++)
              CheckboxListTile(
                value: selectedIndexes.contains(i),
                onChanged: (value) => onChanged(i, value ?? false),
                title: Text('${result.actions[i].label} · ${result.actions[i].summary}'),
                subtitle: Text('confidence: ${result.actions[i].confidence.toStringAsFixed(2)}'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onCommit,
              icon: const Icon(Icons.check_outlined),
              label: const Text('确认写入选中动作'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitResultCard extends StatelessWidget {
  const _CommitResultCard({required this.result, required this.onUndo});

  final AiCaptureCommitResult result;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('提交结果', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('committed: ${result.committed}'),
            Text('created: ${result.createdEntities.length}'),
            Text('failed: ${result.failedActions.length}'),
            Text('undo_token: ${result.undoToken}'),
            if (result.createdEntities.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final entity in result.createdEntities) Text('${entity.type}: ${entity.id}'),
            ],
            if (result.failedActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final failure in result.failedActions)
                Text('#${failure.actionIndex} ${failure.actionType ?? '-'} · ${failure.reason}'),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onUndo,
              icon: const Icon(Icons.undo_outlined),
              label: const Text('撤销本次 AI 写入'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UndoResultCard extends StatelessWidget {
  const _UndoResultCard({required this.result});

  final AiCaptureUndoResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('撤销结果', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('undone: ${result.undone}'),
            Text('failed: ${result.failedEntities.length}'),
            for (final entity in result.entities) Text('${entity.type}: ${entity.id}'),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}
