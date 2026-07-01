import 'dart:convert';

import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_ids.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 7, 1, 12, 30);

  test(
    'LocalCoreWritePolicy creates stable metadata for create and update',
    () {
      final policy = LocalCoreWritePolicy(
        idGenerator: LocalCoreIdGenerator(timeSource: () => fixedNow),
      );
      final context = LocalCoreContext.flutterUser(
        userId: 'user_1',
        now: fixedNow,
      );

      final entityId = policy.nextEntityId('memo');
      final createMetadata = policy.metadataForCreate(context);
      final updateMetadata = policy.metadataForUpdate(
        context,
        currentRevision: 3,
        createdAt: DateTime.utc(2026, 6, 30),
      );

      expect(entityId, startsWith('local_memo_'));
      expect(entityId, endsWith('_0001'));
      expect(createMetadata.userId, 'user_1');
      expect(createMetadata.source, 'flutter');
      expect(createMetadata.revision, 1);
      expect(
        createMetadata.timestamps.createdAtIso,
        fixedNow.toIso8601String(),
      );
      expect(
        createMetadata.timestamps.updatedAtIso,
        fixedNow.toIso8601String(),
      );
      expect(updateMetadata.revision, 4);
      expect(updateMetadata.timestamps.createdAt, DateTime.utc(2026, 6, 30));
      expect(updateMetadata.timestamps.updatedAt, fixedNow);
    },
  );

  test(
    'LocalCoreAuditLogWriter maps context and snapshots into insert parameters',
    () async {
      final policy = LocalCoreWritePolicy(
        idGenerator: LocalCoreIdGenerator(timeSource: () => fixedNow),
      );
      final writer = LocalCoreAuditLogWriter(policy: policy);
      final handle = _RecordingWriteHandle();
      final context = LocalCoreContext(
        actorType: LocalCoreActorType.ai,
        sourceChannel: LocalCoreSourceChannel.localMcp,
        userId: 'user_1',
        actorId: 'assistant_1',
        toolName: 'memo_create',
        requestId: 'request_1',
        sourceText: 'local write test',
        now: fixedNow,
      );

      final auditId = await writer.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'memo.create',
          entityType: 'memo',
          entityId: 'memo_1',
          beforeSnapshot: {'title': 'old'},
          afterSnapshot: {'title': 'new'},
        ),
      );

      expect(auditId, startsWith('local_audit_'));
      expect(auditId, endsWith('_0001'));
      expect(handle.calls, hasLength(1));

      final call = handle.calls.single;
      expect(call.sql, contains('INSERT INTO audit_logs'));
      expect(call.parameters, hasLength(14));
      expect(call.parameters[0], auditId);
      expect(call.parameters[1], 'user_1');
      expect(call.parameters[2], 'ai');
      expect(call.parameters[3], 'assistant_1');
      expect(call.parameters[4], 'memo.create');
      expect(call.parameters[5], 'memo');
      expect(call.parameters[6], 'memo_1');
      expect(call.parameters[7], jsonEncode({'title': 'old'}));
      expect(call.parameters[8], jsonEncode({'title': 'new'}));
      expect(call.parameters[9], 'localMcp');
      expect(call.parameters[10], 'local write test');
      expect(call.parameters[11], 'memo_create');
      expect(call.parameters[12], 'request_1');
      expect(call.parameters[13], fixedNow.toIso8601String());
    },
  );
}

class _RecordingWriteHandle implements LocalCoreWriteHandle {
  final List<_RecordedSqlCall> calls = [];

  @override
  Future<void> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    calls.add(_RecordedSqlCall(sql: sql, parameters: parameters));
  }
}

class _RecordedSqlCall {
  final String sql;
  final List<Object?> parameters;

  const _RecordedSqlCall({required this.sql, required this.parameters});
}
