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
      await _insertMemo(
        handle,
        memo,
        metadata,
        sourceCaptureId: createInput.sourceCaptureId,
      );
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

  Future<List<LocalMemoClassification>> getMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    await syncService.ensureInitialized();
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final status = input['classification_status'] as String?;
    final rows = await syncService.db.getAll(
      'SELECT id, memo_id, tag, source, status, confidence, reason, created_at, updated_at, confirmed_at '
      'FROM memo_classifications '
      'WHERE (? IS NULL OR memo_id = ?) AND (? IS NULL OR status = ?) '
      'ORDER BY updated_at DESC',
      [memoId, memoId, status, status],
    );
    return rows.map(_classificationFromRow).toList(growable: false);
  }

  Future<LocalMemoClassification> confirmMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _upsertClassification(input, context, 'confirmed');
  }

  Future<LocalMemoClassification> rejectMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _upsertClassification(input, context, 'rejected');
  }

  Future<List<LocalTagSummary>> getTagSummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final kind = input['kind'] as String? ?? 'memo';
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT c.tag AS tag, count(*) AS count, '
      'sum(CASE WHEN c.status = ? THEN 1 ELSE 0 END) AS confirmed_count, '
      'sum(CASE WHEN c.status = ? THEN 1 ELSE 0 END) AS suggested_count, '
      'm.color_token AS color_token, m.icon_token AS icon_token, m.sort_order AS sort_order '
      'FROM memo_classifications c '
      'LEFT JOIN tag_metadata m ON m.name = c.tag AND m.kind = ? AND m.status = ? '
      'WHERE c.status != ? '
      'GROUP BY c.tag, m.color_token, m.icon_token, m.sort_order '
      'ORDER BY count DESC, c.tag ASC',
      ['confirmed', 'suggested', kind, 'active', 'rejected'],
    );
    return rows
        .map((row) {
          return LocalTagSummary(
            tag: row['tag'] as String,
            kind: kind,
            count: row['count'] as int? ?? 0,
            confirmedCount: row['confirmed_count'] as int? ?? 0,
            suggestedCount: row['suggested_count'] as int? ?? 0,
            colorToken: row['color_token'] as String?,
            iconToken: row['icon_token'] as String?,
            sortOrder: row['sort_order'] as int?,
          );
        })
        .toList(growable: false);
  }

  Future<LocalMemoRecord> deleteMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final deleteInput = LocalMemoDeleteInput.fromMap(input);
    late final LocalMemoRecord deletedMemo;

    await LocalCoreWriteExecutor(syncService: syncService).run((handle) async {
      final oldMemo = await _findActiveMemo(handle, deleteInput.memoId);
      if (oldMemo == null) {
        throw StateError('Memo not found: ${deleteInput.memoId}');
      }

      final metadata = policy.metadataForUpdate(
        context,
        currentRevision: oldMemo.revision,
        createdAt: oldMemo.createdAt,
      );
      deletedMemo = LocalMemoRecord(
        id: oldMemo.id,
        type: oldMemo.type,
        title: oldMemo.title,
        contentMarkdown: oldMemo.contentMarkdown,
        tags: oldMemo.tags,
        status: deleteInput.status,
        revision: metadata.revision,
        createdAt: oldMemo.createdAt,
        updatedAt: metadata.timestamps.updatedAt,
      );

      await _softDeleteMemo(handle, deletedMemo, metadata);
      await auditLogWriter.write(
        handle,
        LocalCoreAuditLogInput(
          context: context,
          action: 'memo.delete',
          entityType: 'memo',
          entityId: deletedMemo.id,
          beforeSnapshot: LocalMemoMapper.snapshot(oldMemo),
          afterSnapshot: LocalMemoMapper.snapshot(deletedMemo),
        ),
      );
    });

    return deletedMemo;
  }

  Future<LocalMemoClassification> _upsertClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
    String status,
  ) async {
    final classificationId =
        input['classification_id'] as String? ?? input['id'] as String?;
    final memoId = input['memo_id'] as String?;
    final tag = (input['tag'] as String?)?.trim();
    if (classificationId == null &&
        (memoId == null || tag == null || tag.isEmpty)) {
      throw ArgumentError(
        'memo_id and tag are required when classification_id is not provided',
      );
    }
    await syncService.ensureInitialized();
    final now = context.effectiveNow.toUtc();
    final id = classificationId ?? policy.nextEntityId('memo_cls');
    await syncService.db.execute(
      'INSERT OR REPLACE INTO memo_classifications('
      'id, user_id, memo_id, tag, source, status, confidence, reason, confirmed_at, created_at, updated_at'
      ') VALUES (?, ?, coalesce((SELECT memo_id FROM memo_classifications WHERE id = ?), ?), '
      'coalesce((SELECT tag FROM memo_classifications WHERE id = ?), ?), '
      'coalesce((SELECT source FROM memo_classifications WHERE id = ?), ?), ?, '
      'coalesce((SELECT confidence FROM memo_classifications WHERE id = ?), ?), '
      'coalesce((SELECT reason FROM memo_classifications WHERE id = ?), ?), ?, '
      'coalesce((SELECT created_at FROM memo_classifications WHERE id = ?), ?), ?)',
      [
        id,
        context.userId,
        id,
        memoId,
        id,
        tag,
        id,
        input['source'] as String? ?? 'user',
        status,
        id,
        (input['confidence'] as num?)?.toDouble(),
        id,
        input['reason'] as String?,
        status == 'confirmed' ? now.toIso8601String() : null,
        id,
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    final rows = await getMemoClassifications({
      'classification_status': status,
    }, context);
    return rows.firstWhere((item) => item.id == id);
  }

  LocalMemoClassification _classificationFromRow(Map<String, Object?> row) {
    return LocalMemoClassification(
      id: row['id'] as String,
      memoId: row['memo_id'] as String,
      tag: row['tag'] as String,
      source: row['source'] as String? ?? 'ai',
      status: row['status'] as String? ?? 'suggested',
      confidence: (row['confidence'] as num?)?.toDouble(),
      reason: row['reason'] as String?,
      createdAt: _readDateTime(row['created_at']),
      updatedAt: _readDateTime(row['updated_at']),
      confirmedAt: row['confirmed_at'] == null
          ? null
          : _readDateTime(row['confirmed_at']),
    );
  }

  DateTime _readDateTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value).toUtc();
    throw ArgumentError('Expected ISO datetime string, got $value');
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
    LocalCoreWriteMetadata metadata, {
    String? sourceCaptureId,
  }) async {
    await handle.execute(
      'INSERT INTO memos('
      'id, user_id, type, title, content_markdown, tags, source_capture_id, source, status, created_at, updated_at, revision'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        memo.id,
        metadata.userId,
        memo.type,
        memo.title,
        memo.contentMarkdown,
        LocalMemoMapper.encodeTags(memo.tags),
        sourceCaptureId,
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

  Future<void> _softDeleteMemo(
    LocalCoreWriteHandle handle,
    LocalMemoRecord memo,
    LocalCoreWriteMetadata metadata,
  ) async {
    await handle.execute(
      'UPDATE memos SET status = ?, deleted_at = ?, updated_at = ?, revision = ? '
      'WHERE id = ? AND status = ?',
      [
        memo.status,
        metadata.timestamps.updatedAtIso,
        metadata.timestamps.updatedAtIso,
        metadata.revision,
        memo.id,
        'active',
      ],
    );
  }
}
