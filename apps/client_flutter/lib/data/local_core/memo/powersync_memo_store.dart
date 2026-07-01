import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/memo/local_memo_mapper.dart';
import 'package:client_flutter/data/local_core/write/local_core_audit_log_writer.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_handle.dart';
import 'package:client_flutter/data/local_core/write/local_core_write_policy.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class PowerSyncMemoStore {
  final SyncService syncService;
  final LocalCoreWritePolicy policy;
  final LocalCoreAuditLogWriter auditLogWriter;

  factory PowerSyncMemoStore({
    required SyncService syncService,
    LocalCoreWritePolicy? policy,
    LocalCoreAuditLogWriter? auditLogWriter,
  }) {
    final resolvedPolicy = policy ?? LocalCoreWritePolicy();
    return PowerSyncMemoStore._(
      syncService: syncService,
      policy: resolvedPolicy,
      auditLogWriter:
          auditLogWriter ?? LocalCoreAuditLogWriter(policy: resolvedPolicy),
    );
  }

  const PowerSyncMemoStore._({
    required this.syncService,
    required this.policy,
    required this.auditLogWriter,
  });

  Future<LocalMemoRecord> createMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final createInput = LocalMemoCreateInput.fromMap(input);
    final metadata = policy.metadataForCreate(context);
    final memo = LocalMemoRecord(
      id: policy.nextEntityId('memo'),
      type: createInput.type,
      title: createInput.title,
      contentMarkdown: createInput.contentMarkdown,
      tags: createInput.tags,
      status: 'active',
      revision: metadata.revision,
      createdAt: metadata.timestamps.createdAt,
      updatedAt: metadata.timestamps.updatedAt,
    );

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      await _insertMemo(handle, memo, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'memo.create',
          entityType: 'memo',
          entityId: memo.id,
          afterSnapshot: LocalMemoMapper.snapshot(memo),
        ),
      );
    });

    return memo;
  }

  Future<List<LocalMemoRecord>> searchMemos(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final searchInput = LocalMemoSearchInput.fromMap(input);
    final query = searchInput.query.toLowerCase();
    final rows = await _searchRows(query: query, limit: searchInput.limit);
    return rows.map(LocalMemoMapper.fromRow).toList(growable: false);
  }

  Future<LocalMemoRecord> updateMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final updateInput = LocalMemoUpdateInput.fromMap(input);
    late final LocalMemoRecord updatedMemo;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldMemo = await _findActiveMemo(handle, updateInput.memoId);
      if (oldMemo == null) {
        throw StateError('Memo not found: ${updateInput.memoId}');
      }

      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldMemo.revision,
        createdAt: oldMemo.createdAt,
      );
      updatedMemo = LocalMemoRecord(
        id: oldMemo.id,
        type: updateInput.type ?? oldMemo.type,
        title: updateInput.title ?? oldMemo.title,
        contentMarkdown: updateInput.contentMarkdown ?? oldMemo.contentMarkdown,
        tags: updateInput.tags ?? oldMemo.tags,
        status: oldMemo.status,
        revision: metadata.revision,
        createdAt: oldMemo.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );

      await _updateMemo(handle, updatedMemo, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'memo.update',
          entityType: 'memo',
          entityId: updatedMemo.id,
          beforeSnapshot: LocalMemoMapper.snapshot(oldMemo),
          afterSnapshot: LocalMemoMapper.snapshot(updatedMemo),
        ),
      );
    });

    return updatedMemo;
  }

  Future<List<Map<String, Object?>>> _searchRows({
    required String query,
    required int limit,
  }) async {
    await syncService.ensureInitialized();
    final likeQuery = '%$query%';
    final rows = await syncService.db.getAll(
      'SELECT id, type, title, content_markdown, tags, status, revision, created_at, updated_at '
      'FROM memos '
      'WHERE status = ? AND (? = ? OR lower(coalesce(title, ?) || ? || coalesce(content_markdown, ?)) LIKE ?) '
      'ORDER BY updated_at DESC '
      'LIMIT ?',
      ['active', query, '', '', '\n', '', likeQuery, limit],
    );
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<LocalMemoRecord?> _findActiveMemo(
    LocalCoreWriteHandle handle,
    String memoId,
  ) async {
    final row = await handle.getOptional(
      'SELECT id, type, title, content_markdown, tags, status, revision, created_at, updated_at '
      'FROM memos WHERE id = ? AND status = ?',
      [memoId, 'active'],
    );
    return row == null ? null : LocalMemoMapper.fromRow(row);
  }

  Future<void> _insertMemo(
    LocalCoreWriteHandle handle,
    LocalMemoRecord memo,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'INSERT INTO memos('
      'id, user_id, type, title, content_markdown, tags, source, status, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        memo.id,
        metadata.userId,
        memo.type,
        memo.title,
        memo.contentMarkdown,
        LocalMemoMapper.encodeTags(memo.tags),
        metadata.source,
        memo.status,
        metadata.timestamps.createdAtIso,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
      ],
    );
  }

  Future<void> _updateMemo(
    LocalCoreWriteHandle handle,
    LocalMemoRecord memo,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'UPDATE memos SET type = ?, title = ?, content_markdown = ?, tags = ?, updated_at = ?, revision = ? '
      'WHERE id = ? AND status = ?',
      [
        memo.type,
        memo.title,
        memo.contentMarkdown,
        LocalMemoMapper.encodeTags(memo.tags),
        metadata.timestamps.updatedAtIso,
        metadata.revision,
        memo.id,
        'active',
      ],
    );
  }
}
