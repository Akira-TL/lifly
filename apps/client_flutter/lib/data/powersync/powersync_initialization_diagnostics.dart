import 'package:flutter/foundation.dart';

class InitializationSingleFlight {
  Future<void>? _pending;

  bool get isRunning => _pending != null;

  Future<void> run(Future<void> Function() action, {VoidCallback? onJoin}) {
    final pending = _pending;
    if (pending != null) {
      onJoin?.call();
      return pending;
    }

    late final Future<void> tracked;
    tracked = Future<void>.sync(action).whenComplete(() {
      if (identical(_pending, tracked)) {
        _pending = null;
      }
    });
    _pending = tracked;
    return tracked;
  }
}

class PowerSyncInitializationFailure implements Exception {
  final String diagnosticId;
  final DateTime occurredAt;
  final String stage;
  final String databasePath;
  final Uri pageUri;
  final int schemaTableCount;
  final Object cause;
  final StackTrace causeStackTrace;
  final List<String> events;

  const PowerSyncInitializationFailure({
    required this.diagnosticId,
    required this.occurredAt,
    required this.stage,
    required this.databasePath,
    required this.pageUri,
    required this.schemaTableCount,
    required this.cause,
    required this.causeStackTrace,
    required this.events,
  });

  String get report {
    final stackLines = causeStackTrace.toString().trim().split('\n');
    final visibleStack = stackLines.take(40).join('\n');
    return <String>[
      'LIFLY_POWERSYNC_DIAGNOSTIC',
      'id=$diagnosticId',
      'occurred_at=${occurredAt.toIso8601String()}',
      'stage=$stage',
      'database_path=$databasePath',
      'page_uri=$pageUri',
      'schema_tables=$schemaTableCount',
      'cause_type=${cause.runtimeType}',
      'cause=$cause',
      'events:',
      ...events.map((event) => '  $event'),
      'stack:',
      visibleStack.isEmpty ? '  <empty>' : visibleStack,
      if (stackLines.length > 40)
        '  ... ${stackLines.length - 40} more stack lines omitted',
    ].join('\n');
  }

  @override
  String toString() {
    return 'Web 本地数据库初始化失败（诊断编号：$diagnosticId）。\n$report';
  }
}
