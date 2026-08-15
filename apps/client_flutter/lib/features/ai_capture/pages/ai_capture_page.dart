import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_execution_runtime.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';
import 'package:client_flutter/features/ai_capture/data/external_ai_action_committer.dart';
import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:client_flutter/features/ai_capture/models/cloud_ai_models.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_capture_asset_picker.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_capture_session_panel.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_capture_turn_card.dart';
import 'package:client_flutter/features/ai_capture/widgets/ai_execution_target_bar.dart';
import 'package:client_flutter/features/ai_capture/widgets/cloud_ai_consent_dialog.dart';
import 'package:client_flutter/features/ai_capture/widgets/external_ai_plan_panel.dart';
import 'package:client_flutter/shared/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AiCapturePage extends StatefulWidget {
  const AiCapturePage({super.key, this.executionRuntime});

  final AiCaptureExecutionRuntime? executionRuntime;

  @override
  State<AiCapturePage> createState() => _AiCapturePageState();
}

class _AiCapturePageState extends State<AiCapturePage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedAssetIds = <String>{};

  List<AiCaptureSession> _sessions = const [];
  List<AiCaptureAssetContext> _assets = const [];
  AiCaptureSession? _session;
  late AiCaptureExecutionRuntime _executionRuntime;
  AiExecutionTarget _executionTarget = AiExecutionTarget.existing;
  List<DeviceDescriptor> _computeNodes = const [];
  String? _selectedComputeNodeId;
  String _computeStatusText = '尚未读取 Device Registry。';
  ExternalAiPlanResult? _externalPlan;
  final Map<int, ExternalAiActionCommitResult> _externalCommits = {};
  final Set<int> _externalBusyIndexes = {};
  AiProviderKind _cloudProvider = AiProviderKind.ollama;
  String _cloudModel = '';
  String? _error;
  bool _loading = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final api = context.read<ApiClient?>();
    _executionRuntime =
        widget.executionRuntime ??
        (api == null
            ? const UnavailableAiCaptureExecutionRuntime()
            : DefaultAiCaptureExecutionRuntime(api));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AiCaptureService>();
    final compactHeader = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 对话'),
        actions: [
          IconButton(
            tooltip: '新会话',
            onPressed: _loading ? null : _newSession,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: '历史会话',
            onPressed: _loading ? null : _showSessionHistory,
            icon: const Icon(Icons.history_outlined),
          ),
          if (_session != null && !_session!.isDismissed)
            IconButton(
              tooltip: '关闭当前会话',
              onPressed: _loading ? null : _dismissCurrentSession,
              icon: const Icon(Icons.close_outlined),
            ),
          if (!compactHeader)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  service.modeLabel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSessionPanel = constraints.maxWidth >= 1000;
          return Row(
            children: [
              if (showSessionPanel)
                SizedBox(
                  width: 280,
                  child: AiCaptureSessionPanel(
                    sessions: _sessions,
                    selectedCaptureId: _session?.captureId,
                    onSelected: _openSession,
                    onNew: _newSession,
                  ),
                ),
              if (showSessionPanel) const VerticalDivider(width: 1),
              Expanded(child: _buildChat(service)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChat(AiCaptureService service) {
    final selectedComputeNode = _selectedComputeNode();
    final composerEnabled = switch (_executionTarget) {
      AiExecutionTarget.existing => service.supportsCapture && !_loading,
      AiExecutionTarget.computeNode ||
      AiExecutionTarget.cloudAi => service.supportsCloudCapture && !_loading,
    };
    return Column(
      children: [
        _ModeNotice(service: service),
        AiExecutionTargetBar(
          target: _executionTarget,
          computeNodes: _computeNodes,
          selectedComputeNodeId: selectedComputeNode?.deviceId,
          computeStatusText: _computeStatusText,
          onTargetChanged: (target) =>
              setState(() => _executionTarget = target),
          onComputeNodeChanged: (deviceId) {
            setState(() {
              _selectedComputeNodeId = deviceId;
              _computeStatusText = _computeNodeStatus(_selectedComputeNode());
            });
          },
        ),
        if (_error != null) _ErrorBanner(message: _error!),
        if (_externalPlan != null)
          ExternalAiPlanPanel(
            plan: _externalPlan!,
            commits: _externalCommits,
            busyIndexes: _externalBusyIndexes,
            onCommit: _commitExternalAction,
            onUndo: _undoExternalAction,
            onClose: () => setState(() {
              _externalPlan = null;
              _externalCommits.clear();
              _externalBusyIndexes.clear();
            }),
          ),
        Expanded(
          child: _session == null
              ? _EmptyConversation(onStart: _focusComposer)
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  itemCount: _session!.turns.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final turn = _session!.turns[index];
                    return AiCaptureTurnCard(
                      key: ValueKey('${turn.id}-${turn.turnStatus}'),
                      turn: turn,
                      busy: _loading,
                      onCommit: _commitTurn,
                      onRevise: _reviseTurn,
                      onUndo: _undoTurn,
                    );
                  },
                ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        _Composer(
          controller: _textController,
          enabled: composerEnabled,
          selectedAssets: _assets
              .where((asset) => _selectedAssetIds.contains(asset.assetId))
              .toList(growable: false),
          onAttach: _selectAssets,
          onRemoveAsset: (assetId) {
            setState(() => _selectedAssetIds.remove(assetId));
          },
          onSend: _sendMessage,
        ),
      ],
    );
  }

  Future<void> _loadInitial() async {
    await _run(() async {
      final service = context.read<AiCaptureService>();
      final results = await Future.wait<Object>([
        service.listSessions(),
        service.listAssets(),
      ]);
      final page = results[0] as AiCaptureSessionPage;
      final assets = results[1] as List<AiCaptureAssetContext>;
      AiCaptureSession? session;
      if (page.items.isNotEmpty) {
        session = await service.getSession(page.items.first.captureId);
      }
      if (!mounted) return;
      setState(() {
        _sessions = page.items;
        _assets = assets;
        _session = session;
      });
      _scrollToBottom();
    });
    await _loadExecutionTargets();
  }

  Future<void> _refreshSessions({String? selectCaptureId}) async {
    final service = context.read<AiCaptureService>();
    final page = await service.listSessions();
    AiCaptureSession? session = _session;
    final targetId = selectCaptureId ?? session?.captureId;
    if (targetId != null) {
      try {
        session = await service.getSession(targetId);
      } catch (_) {
        session = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _sessions = page.items;
      _session = session;
    });
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入要记录或设置的内容。');
      return;
    }
    final assetIds = _selectedAssetIds.toList(growable: false);
    switch (_executionTarget) {
      case AiExecutionTarget.existing:
        await _sendExistingMessage(text, assetIds);
      case AiExecutionTarget.computeNode:
        await _sendComputeNodeMessage(text, assetIds);
      case AiExecutionTarget.cloudAi:
        await _sendCloudAiMessage(text);
    }
  }

  Future<void> _sendExistingMessage(String text, List<String> assetIds) async {
    await _run(() async {
      final service = context.read<AiCaptureService>();
      String captureId;
      if (_session == null || _session!.isDismissed) {
        final parsed = await service.parse(text: text, assetIds: assetIds);
        captureId = parsed.captureId;
      } else {
        final updated = await service.appendTurn(
          captureId: _session!.captureId,
          text: text,
          assetIds: assetIds,
        );
        captureId = updated.captureId;
      }
      _textController.clear();
      _selectedAssetIds.clear();
      await _refreshSessions(selectCaptureId: captureId);
    });
  }

  Future<void> _sendComputeNodeMessage(
    String text,
    List<String> assetIds,
  ) async {
    final target = _selectedComputeNode();
    if (target == null) {
      setState(() => _error = '请先选择一个 Trusted Compute Node。');
      return;
    }
    await _run(() async {
      try {
        final plan = await _executionRuntime.planOnComputeNode(
          target: target,
          text: text,
          assetIds: assetIds,
        );
        if (!mounted) return;
        setState(() {
          _externalPlan = plan;
          _externalCommits.clear();
          _textController.clear();
          _selectedAssetIds.clear();
          _computeStatusText = '${target.displayName} 已返回加密 Job 结果。';
        });
      } on ComputeNodeUnavailable catch (error) {
        if (mounted) {
          setState(() {
            _computeStatusText = '${error.message} 不会自动转 Cloud AI。';
          });
        }
        rethrow;
      }
    });
  }

  Future<void> _sendCloudAiMessage(String text) async {
    final decision = await showCloudAiConsentDialog(
      context,
      inputText: text,
      selectedAssetCount: _selectedAssetIds.length,
      initialProvider: _cloudProvider,
      initialModel: _cloudModel,
    );
    if (decision == null || !mounted) return;
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final request = CloudAiInferenceRequest(
      requestId: 'cloud-$stamp',
      disclosure: CloudAiDisclosureScope(
        consentId: 'consent-$stamp',
        granted: true,
        provider: decision.provider,
        model: decision.model,
        allowedDataTypes: {'capture_input'},
        reason: '用户本次明确授权 Cloud AI 处理当前输入',
        includesAttachments: false,
        includesHistory: false,
      ),
      input: AiContextItem(dataType: 'capture_input', content: text),
    );
    setState(() {
      _cloudProvider = decision.provider;
      _cloudModel = decision.model;
    });
    await _run(() async {
      final plan = await _executionRuntime.planOnCloud(request);
      if (!mounted) return;
      setState(() {
        _externalPlan = plan;
        _externalCommits.clear();
        _textController.clear();
      });
    });
  }

  Future<void> _commitTurn(AiCaptureTurn turn, List<int> indexes) async {
    await _run(() async {
      await context.read<AiCaptureService>().commit(
        captureId: turn.captureId,
        turnId: turn.id,
        selectedActionIndexes: indexes,
      );
      await _refreshSessions(selectCaptureId: turn.captureId);
    });
  }

  Future<void> _reviseTurn(
    AiCaptureTurn turn,
    int actionIndex,
    Map<String, dynamic> payload,
  ) async {
    await _run(() async {
      await context.read<AiCaptureService>().reviseAction(
        captureId: turn.captureId,
        turnId: turn.id,
        actionIndex: actionIndex,
        payload: payload,
        note: '用户在聊天界面修改候选内容',
      );
      await _refreshSessions(selectCaptureId: turn.captureId);
    });
  }

  Future<void> _undoTurn(AiCaptureTurn turn) async {
    final undoToken = turn.undoToken;
    if (undoToken == null || undoToken.isEmpty) return;
    await _run(() async {
      await context.read<AiCaptureService>().undo(undoToken: undoToken);
      await _refreshSessions(selectCaptureId: turn.captureId);
    });
  }

  Future<void> _dismissCurrentSession() async {
    final session = _session;
    if (session == null) return;
    await _run(() async {
      await context.read<AiCaptureService>().dismissSession(
        session.captureId,
        reason: '用户从 AI 聊天界面关闭会话',
      );
      _newSession();
      await _refreshSessions();
    });
  }

  Future<void> _openSession(String captureId) async {
    await _run(() async {
      final session = await context.read<AiCaptureService>().getSession(
        captureId,
      );
      if (!mounted) return;
      setState(() => _session = session);
      _scrollToBottom();
    });
  }

  void _newSession() {
    setState(() {
      _session = null;
      _selectedAssetIds.clear();
      _externalPlan = null;
      _externalCommits.clear();
      _externalBusyIndexes.clear();
      _error = null;
    });
  }

  Future<void> _selectAssets() async {
    if (_assets.isEmpty) {
      await _run(() async {
        final assets = await context.read<AiCaptureService>().listAssets();
        if (mounted) setState(() => _assets = assets);
      });
    }
    if (!mounted) return;
    final selected = await showAiCaptureAssetPicker(
      context,
      assets: _assets,
      selectedIds: _selectedAssetIds,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedAssetIds
          ..clear()
          ..addAll(selected);
      });
    }
  }

  Future<void> _showSessionHistory() async {
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: AiCaptureSessionPanel(
          sessions: _sessions,
          selectedCaptureId: _session?.captureId,
          onSelected: (captureId) => Navigator.of(context).pop(captureId),
          onNew: () => Navigator.of(context).pop(''),
        ),
      ),
    );
    if (selectedId == null) return;
    if (selectedId.isEmpty) {
      _newSession();
    } else {
      await _openSession(selectedId);
    }
  }

  Future<void> _loadExecutionTargets() async {
    try {
      final snapshot = await _executionRuntime.loadTargets();
      if (!mounted) return;
      setState(() {
        _computeNodes = snapshot.computeNodes;
        _selectedComputeNodeId =
            snapshot.defaultComputeNode?.deviceId ??
            (snapshot.computeNodes.isEmpty
                ? null
                : snapshot.computeNodes.first.deviceId);
        _computeStatusText = _computeNodeStatus(_selectedComputeNode());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _computeNodes = const [];
        _selectedComputeNodeId = null;
        _computeStatusText = 'Device Registry 不可用：$error；不会自动转 Cloud AI。';
      });
    }
  }

  DeviceDescriptor? _selectedComputeNode() {
    final id = _selectedComputeNodeId;
    if (id == null) return null;
    for (final device in _computeNodes) {
      if (device.deviceId == id) return device;
    }
    return null;
  }

  String _computeNodeStatus(DeviceDescriptor? device) {
    if (device == null) return '没有可用的 Compute Node。';
    final lastSeen = device.lastSeenAt;
    if (lastSeen == null) {
      return '${device.displayName} 尚未上报 last_seen；当前合同无法判定在线状态。不会自动转 Cloud AI。';
    }
    return '${device.displayName} 最近心跳 ${lastSeen.toLocal()}；当前 Device Registry 合同未提供 online 布尔状态。不会自动转 Cloud AI。';
  }

  Future<void> _commitExternalAction(int index) async {
    final plan = _externalPlan;
    if (plan == null || index < 0 || index >= plan.actions.length) return;
    setState(() => _externalBusyIndexes.add(index));
    try {
      final result = await _executionRuntime.commit(plan.actions[index]);
      if (mounted) setState(() => _externalCommits[index] = result);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () => _error = userFacingFailure(
            action: '提交 AI 候选动作',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _externalBusyIndexes.remove(index));
    }
  }

  Future<void> _undoExternalAction(int index) async {
    final committed = _externalCommits[index];
    if (committed == null) return;
    setState(() => _externalBusyIndexes.add(index));
    try {
      final result = await _executionRuntime.undo(committed.undoToken);
      if (mounted && result.undone > 0) {
        setState(() => _externalCommits.remove(index));
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () => _error = userFacingFailure(
            action: '撤销 AI 候选动作',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _externalBusyIndexes.remove(index));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () => _error = userFacingFailure(
            action: 'AI 操作',
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _focusComposer() => FocusScope.of(context).nextFocus();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.selectedAssets,
    required this.onAttach,
    required this.onRemoveAsset,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final List<AiCaptureAssetContext> selectedAssets;
  final VoidCallback onAttach;
  final ValueChanged<String> onRemoveAsset;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            compact ? 6 : 8,
            12,
            compact ? 8 : 10,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedAssets.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selectedAssets
                        .map(
                          (asset) => InputChip(
                            label: Text(asset.displayName),
                            onDeleted: enabled
                                ? () => onRemoveAsset(asset.assetId)
                                : null,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              if (selectedAssets.isNotEmpty) const SizedBox(height: 8),
              TextField(
                key: const Key('ai_capture_composer'),
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: compact ? 4 : 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  isDense: compact,
                  hintText: '告诉 AI 要记录、修改或设置什么…',
                  prefixIcon: IconButton(
                    tooltip: '添加附件',
                    onPressed: enabled ? onAttach : null,
                    icon: const Icon(Icons.attach_file, size: 20),
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(4),
                    child: IconButton.filled(
                      tooltip: '发送',
                      onPressed: enabled ? onSend : null,
                      icon: const Icon(Icons.send_outlined, size: 18),
                    ),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeNotice extends StatelessWidget {
  const _ModeNotice({required this.service});

  final AiCaptureService service;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 700) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final message = service.supportsCapture
        ? '${service.modeLabel} · ${service.supportsCloudCapture ? '在线可用' : '离线可用'}'
        : service.modeLabel;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            Icon(
              service.supportsCloudCapture
                  ? Icons.cloud_done_outlined
                  : Icons.offline_bolt_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Text(
              message,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 48),
            const SizedBox(height: 12),
            Text('开始一段连续会话', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'AI 设置任务、备忘或账单后，会在对话中保留结果，并提供修改和撤销入口。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onStart, child: const Text('开始输入')),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
