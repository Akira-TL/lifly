import 'package:client_flutter/data/api/api_client.dart';

class ApiHealthStatus {
  final String status;
  final String version;
  final int? port;

  const ApiHealthStatus({
    required this.status,
    required this.version,
    required this.port,
  });

  factory ApiHealthStatus.fromJson(Map<String, dynamic> json) {
    return ApiHealthStatus(
      status: json['status'] as String? ?? 'unknown',
      version: json['version'] as String? ?? 'unknown',
      port: json['port'] as int?,
    );
  }
}

class McpSmokeStepResult {
  final String name;
  final bool passed;
  final String? detail;

  const McpSmokeStepResult({
    required this.name,
    required this.passed,
    this.detail,
  });
}

class McpSmokeReport {
  final List<McpSmokeStepResult> steps;

  const McpSmokeReport(this.steps);

  bool get passed => steps.every((step) => step.passed);
  int get passedCount => steps.where((step) => step.passed).length;
  int get totalCount => steps.length;
}

class ApiDiagnosticsService {
  final ApiClient api;

  ApiDiagnosticsService(this.api);

  Future<ApiHealthStatus> fetchHealth() async {
    final response = await api.get('/health');
    return ApiHealthStatus.fromJson(response);
  }

  Future<McpSmokeReport> runMcpSmoke() async {
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final steps = <McpSmokeStepResult>[];
    String? memoId;
    String? taskId;

    Future<void> step(String name, Future<void> Function() action) async {
      try {
        await action();
        steps.add(McpSmokeStepResult(name: name, passed: true));
      } catch (error) {
        steps.add(
          McpSmokeStepResult(
            name: name,
            passed: false,
            detail: error.toString(),
          ),
        );
      }
    }

    await step('health', () async {
      final health = await fetchHealth();
      if (health.status != 'ok') {
        throw StateError('Health status is ${health.status}');
      }
    });

    await step('mcp.memo.create', () async {
      final response = await api.post('/mcp/memo/create', data: {
        'type': 'memo',
        'title': 'Flutter MCP smoke memo $runId',
        'content_markdown': 'created by Flutter diagnostics smoke test',
        'tags': ['flutter', 'smoke'],
      });
      memoId = response['memo_id'] as String?;
      if (memoId == null || memoId!.isEmpty) {
        throw StateError('memo_id missing');
      }
    });

    await step('mcp.memo.search', () async {
      final response = await api.post('/mcp/memo/search', data: {
        'q': 'Flutter MCP smoke memo $runId',
        'limit': 5,
      });
      final memos = response['memos'] as List? ?? const [];
      final found = memos.any((memo) {
        final item = memo as Map<String, dynamic>;
        return item['id'] == memoId;
      });
      if (!found) throw StateError('created memo not found');
    });

    await step('mcp.expense.create', () async {
      final response = await api.post('/mcp/expense/create', data: {
        'amount': 1.23,
        'currency': 'CNY',
        'direction': 'expense',
        'merchant': 'Flutter MCP Smoke Merchant $runId',
        'note': 'created by Flutter diagnostics smoke test',
      });
      final transaction = response['transaction'] as Map<String, dynamic>?;
      if (transaction == null || transaction['id'] == null) {
        throw StateError('transaction.id missing');
      }
    });

    await step('mcp.task.create', () async {
      final response = await api.post('/mcp/task/create', data: {
        'title': 'Flutter MCP smoke task $runId',
        'description': 'created by Flutter diagnostics smoke test',
        'priority': 'normal',
      });
      final task = response['task'] as Map<String, dynamic>?;
      taskId = task?['id'] as String?;
      if (taskId == null || taskId!.isEmpty) {
        throw StateError('task.id missing');
      }
    });

    await step('mcp.task.complete', () async {
      await api.post('/mcp/task/complete', data: {'task_id': taskId});
    });

    await step('mcp.asset.registerExternalUrl', () async {
      final response = await api.post('/mcp/asset/register-external-url', data: {
        'external_url': 'https://example.com/flutter-mcp-smoke-$runId',
        'title': 'Flutter MCP smoke link $runId',
        'asset_type': 'link',
      });
      final asset = response['asset'] as Map<String, dynamic>?;
      if (asset == null || asset['kind'] != 'external') {
        throw StateError('external asset missing');
      }
    });

    return McpSmokeReport(steps);
  }
}
