import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:client_flutter/data/repositories/paged_result.dart';

class ImportExportRepository {
  final ApiClient api;

  const ImportExportRepository(this.api);

  Future<ImportUploadPreview> uploadPreview({
    required List<int> bytes,
    required String filename,
    ImportProvider provider = ImportProvider.auto,
  }) async {
    final res = await api.postMultipartBytes(
      '/import/upload',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      params: {'provider': provider.value},
    );
    return ImportUploadPreview.fromJson(_data(res));
  }

  Future<ImportPreviewPage> previewDetail(
    String batchId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await api.get(
      '/import/$batchId/preview',
      params: {'limit': limit, 'offset': offset},
    );
    return ImportPreviewPage.fromJson(_data(res));
  }

  Future<ImportCommitResult> commit(String batchId) async {
    final res = await api.post('/import/$batchId/commit');
    return ImportCommitResult.fromJson(_data(res));
  }

  Future<ImportRollbackResult> rollback(String batchId) async {
    final res = await api.post('/import/$batchId/rollback');
    return ImportRollbackResult.fromJson(_data(res));
  }

  Future<PagedResult<ImportBatch>> listBatches({
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (status != null && status.isNotEmpty) params['status'] = status;

    final res = await api.get('/import/batches', params: params);
    return PagedResult.fromData(_data(res), ImportBatch.fromJson);
  }

  Future<ImportBatch> getBatch(String batchId) async {
    final res = await api.get('/import/$batchId');
    return ImportBatch.fromJson(_data(res));
  }

  Future<ExportMetadata> exportMetadata({
    ExportEntityType entityType = ExportEntityType.all,
  }) async {
    final res = await api.post(
      '/export',
      data: {'entity_type': entityType.value},
    );
    return ExportMetadata.fromJson(_data(res));
  }

  Future<ExportStreamPayload> downloadExport({
    ExportEntityType entityType = ExportEntityType.all,
  }) async {
    final response = await api.downloadBytes(
      '/export/stream',
      params: {'entity_type': entityType.value},
    );
    return ExportStreamPayload(
      bytes: response.bytes,
      metadata: ExportStreamMetadata.fromHeaders(
        entityType: entityType.value,
        headers: response.headers,
      ),
    );
  }

  Map<String, dynamic> _data(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }
}
