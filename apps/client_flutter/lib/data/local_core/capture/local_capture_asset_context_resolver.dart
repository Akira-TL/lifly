import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

class LocalCaptureAssetContextResolver {
  const LocalCaptureAssetContextResolver(this.syncService);

  final SyncService syncService;

  Future<List<LocalCaptureAssetContext>> resolve(
    List<String> assetIds, {
    required String userId,
  }) async {
    final ids = _normalizeIds(assetIds);
    if (ids.isEmpty) return const [];

    await syncService.ensureInitialized();
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await syncService.db.getAll(
      'SELECT id, kind, asset_type, filename, mime_type, size_bytes, '
      'external_url, sync_status, status '
      'FROM assets WHERE user_id = ? AND id IN ($placeholders)',
      [userId, ...ids],
    );
    final byId = <String, Map<String, Object?>>{
      for (final row in rows) row['id'] as String: row,
    };
    return ids
        .map((id) => _fromRow(id, byId[id]))
        .toList(growable: false);
  }

  Future<List<LocalCaptureAssetContext>> listAvailable({
    required String userId,
    int limit = 50,
  }) async {
    await syncService.ensureInitialized();
    final rows = await syncService.db.getAll(
      'SELECT id, kind, asset_type, filename, mime_type, size_bytes, '
      'external_url, sync_status, status '
      'FROM assets WHERE user_id = ? AND status = ? '
      'ORDER BY updated_at DESC LIMIT ?',
      [userId, 'active', limit],
    );
    return rows
        .map((row) => _fromRow(row['id'] as String, row))
        .toList(growable: false);
  }

  LocalCaptureAssetContext _fromRow(
    String assetId,
    Map<String, Object?>? row,
  ) {
    if (row == null) {
      return LocalCaptureAssetContext(
        assetId: assetId,
        status: 'missing',
        extractor: 'none',
        error: 'asset_not_found',
      );
    }

    final kind = row['kind'] as String?;
    final assetType = row['asset_type'] as String?;
    final mimeType = row['mime_type'] as String?;
    final status = row['status'] as String? ?? 'active';
    final syncStatus = row['sync_status'] as String? ?? 'pending';
    final base = LocalCaptureAssetContext(
      assetId: assetId,
      kind: kind,
      assetType: assetType,
      name:
          row['filename'] as String? ?? row['external_url'] as String? ?? assetId,
      mimeType: mimeType,
      sizeBytes: row['size_bytes'] as int?,
      sourceUrl: row['external_url'] as String?,
      status: 'metadata_only',
      extractor: 'metadata',
    );

    if (status != 'active') {
      return _copy(
        base,
        status: 'inactive',
        error: 'asset_status_$status',
      );
    }
    if (kind == 'internal' && syncStatus != 'synced') {
      return _copy(
        base,
        status: 'pending_upload',
        error: 'asset_sync_status_$syncStatus',
      );
    }
    if (kind == 'external') {
      return _copy(
        base,
        extractor: 'external_reference',
        requiredCapability: 'external_content_fetch',
      );
    }

    final normalizedMime = (mimeType ?? '').split(';').first.trim().toLowerCase();
    if (normalizedMime == 'application/pdf' || assetType == 'pdf') {
      return _copy(
        base,
        status: 'unsupported',
        extractor: 'pdf_adapter',
        requiredCapability: 'pdf_text_extraction',
      );
    }
    if (normalizedMime.startsWith('image/') || assetType == 'image') {
      return _copy(
        base,
        status: 'unsupported',
        extractor: 'image_adapter',
        requiredCapability: 'ocr_or_vision',
      );
    }
    if (normalizedMime.startsWith('audio/') || assetType == 'audio') {
      return _copy(
        base,
        status: 'unsupported',
        extractor: 'audio_adapter',
        requiredCapability: 'speech_to_text',
      );
    }
    if (_textMimeTypes.contains(normalizedMime)) {
      return _copy(
        base,
        requiredCapability: 'local_binary_reader',
      );
    }
    return _copy(
      base,
      requiredCapability: 'binary_content_extractor',
    );
  }

  LocalCaptureAssetContext _copy(
    LocalCaptureAssetContext source, {
    String? status,
    String? extractor,
    String? error,
    String? requiredCapability,
  }) {
    return LocalCaptureAssetContext(
      assetId: source.assetId,
      kind: source.kind,
      assetType: source.assetType,
      name: source.name,
      mimeType: source.mimeType,
      sizeBytes: source.sizeBytes,
      sourceUrl: source.sourceUrl,
      status: status ?? source.status,
      extractor: extractor ?? source.extractor,
      text: source.text,
      error: error,
      requiredCapability: requiredCapability,
    );
  }

  List<String> _normalizeIds(List<String> assetIds) {
    final seen = <String>{};
    return assetIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && seen.add(id))
        .toList(growable: false);
  }

  static const _textMimeTypes = <String>{
    'text/plain',
    'text/markdown',
    'text/csv',
    'application/json',
    'application/xml',
  };
}
