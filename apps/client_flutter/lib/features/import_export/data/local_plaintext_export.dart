import 'dart:convert';

import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:crypto/crypto.dart';

const String localPlaintextExportWarning =
    '明文导出包含可直接阅读的个人数据，只能在已解密的受信设备本地生成；请自行保护导出文件。';

abstract interface class LocalPlaintextExportDataSource {
  Future<String> currentAccountId();

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]);
}

class SyncServicePlaintextExportDataSource
    implements LocalPlaintextExportDataSource {
  final SyncService syncService;

  const SyncServicePlaintextExportDataSource(this.syncService);

  @override
  Future<String> currentAccountId() async {
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT DISTINCT user_id FROM encrypted_entities '
      "WHERE lifecycle_status = 'active' ORDER BY user_id LIMIT 2",
    );
    if (rows.length != 1) {
      throw StateError(
        'Plaintext export requires exactly one active encrypted account in the local database',
      );
    }
    final userId = rows.single['user_id']?.toString() ?? '';
    if (userId.isEmpty) {
      throw StateError('Plaintext export account identity is unavailable');
    }
    return userId;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    await syncService.ensureInitialized();
    return syncService.db.getAll(sql, parameters);
  }
}

class LocalPlaintextExportResult {
  final List<int> bytes;
  final ExportMetadata metadata;

  const LocalPlaintextExportResult({
    required this.bytes,
    required this.metadata,
  });

  ExportStreamPayload toStreamPayload() {
    return ExportStreamPayload(
      bytes: bytes,
      metadata: ExportStreamMetadata(
        entityType: metadata.entityType,
        mode: ExportMode.plaintext,
        contractVersion: metadata.contractVersion,
        checksumSha256: metadata.checksumSha256,
        sizeBytes: metadata.sizeBytes,
        filename: metadata.filename,
        mediaType: metadata.mediaType,
      ),
    );
  }
}

class LocalPlaintextExportBuilder {
  final LocalPlaintextExportDataSource source;

  const LocalPlaintextExportBuilder(this.source);

  Future<LocalPlaintextExportResult> build({
    ExportEntityType entityType = ExportEntityType.all,
  }) async {
    final userId = await source.currentAccountId();
    final sections = <String, Object?>{};
    final counts = <String, int>{};

    for (final spec in _specsFor(entityType)) {
      final rows = await source.query(
        'SELECT * FROM ${spec.table} WHERE user_id = ? AND status = ? '
        'ORDER BY updated_at DESC',
        [userId, 'active'],
      );
      final normalized = rows
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
      sections[spec.jsonKey] = normalized;
      counts[spec.jsonKey] = normalized.length;
    }

    final payload = <String, Object?>{
      'contract_version': 'export.e2ee.v1',
      'mode': 'plaintext',
      'generated_on': 'trusted_client',
      'privacy_warning': localPlaintextExportWarning,
      'account_id': userId,
      'entity_type': entityType.value,
      'counts': counts,
      ...sections,
    };
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    final checksum = sha256.convert(bytes).toString();
    final filename = 'lifly-plaintext-${entityType.value}.json';
    final previewText = utf8.decode(bytes);
    final preview = previewText.substring(
      0,
      previewText.length > 500 ? 500 : previewText.length,
    );
    return LocalPlaintextExportResult(
      bytes: bytes,
      metadata: ExportMetadata(
        contractVersion: 'export.e2ee.v1',
        mode: ExportMode.plaintext,
        executionLocation: 'trusted_client',
        containsDecryptedUserData: true,
        availableFromCloud: false,
        privacyWarning: localPlaintextExportWarning,
        entityType: entityType.value,
        format: 'json',
        mediaType: 'application/json',
        filename: filename,
        sizeBytes: bytes.length,
        checksumSha256: checksum,
        counts: counts,
        preview: preview,
      ),
    );
  }
}

class _LocalExportSpec {
  final String table;
  final String jsonKey;

  const _LocalExportSpec(this.table, this.jsonKey);
}

const _memos = _LocalExportSpec('memos', 'memos');
const _ledger = _LocalExportSpec('ledger_transactions', 'ledger_transactions');
const _tasks = _LocalExportSpec('tasks', 'tasks');
const _assets = _LocalExportSpec('assets', 'assets');

List<_LocalExportSpec> _specsFor(ExportEntityType type) {
  return switch (type) {
    ExportEntityType.memos => const [_memos],
    ExportEntityType.ledgerTransactions => const [_ledger],
    ExportEntityType.tasks => const [_tasks],
    ExportEntityType.assets => const [_assets],
    ExportEntityType.all => const [_memos, _ledger, _tasks, _assets],
  };
}
