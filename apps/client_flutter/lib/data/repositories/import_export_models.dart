enum ImportProvider {
  auto('auto'),
  generic('generic'),
  alipay('alipay'),
  wechat('wechat');

  const ImportProvider(this.value);

  final String value;
}

enum ExportEntityType {
  ledgerTransactions('ledger_transactions'),
  memos('memos'),
  tasks('tasks'),
  assets('assets'),
  all('all');

  const ExportEntityType(this.value);

  final String value;
}

class ImportUploadPreview {
  final String batchId;
  final String sourceProvider;
  final int totalRows;
  final int validRows;
  final int duplicateRows;
  final int errorRows;
  final int ignoredRows;
  final List<ImportPreviewRow> preview;

  const ImportUploadPreview({
    required this.batchId,
    required this.sourceProvider,
    required this.totalRows,
    required this.validRows,
    required this.duplicateRows,
    required this.errorRows,
    required this.ignoredRows,
    required this.preview,
  });

  factory ImportUploadPreview.fromJson(Map<String, dynamic> json) {
    return ImportUploadPreview(
      batchId: _stringValue(json['batch_id']),
      sourceProvider: _stringValue(json['source_provider']),
      totalRows: _intValue(json['total_rows']),
      validRows: _intValue(json['valid_rows']),
      duplicateRows: _intValue(json['duplicate_rows']),
      errorRows: _intValue(json['error_rows']),
      ignoredRows: _intValue(json['ignored_rows']),
      preview: _listValue(
        json['preview'],
      ).map(ImportPreviewRow.fromJson).toList(growable: false),
    );
  }
}

class ImportPreviewPage {
  final ImportBatch batch;
  final int total;
  final int limit;
  final int offset;
  final List<ImportPreviewRow> items;

  const ImportPreviewPage({
    required this.batch,
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
  });

  int get nextOffset => offset + items.length;

  bool get hasMore => nextOffset < total;

  factory ImportPreviewPage.fromJson(Map<String, dynamic> json) {
    return ImportPreviewPage(
      batch: ImportBatch.fromJson(_mapValue(json['batch'])),
      total: _intValue(json['total']),
      limit: _intValue(json['limit']),
      offset: _intValue(json['offset']),
      items: _listValue(
        json['items'],
      ).map(ImportPreviewRow.fromJson).toList(growable: false),
    );
  }
}

class ImportPreviewRow {
  final String? id;
  final int rowIndex;
  final Map<String, dynamic> rawData;
  final Map<String, dynamic>? parsedData;
  final String status;
  final String? errorMessage;

  const ImportPreviewRow({
    required this.id,
    required this.rowIndex,
    required this.rawData,
    required this.parsedData,
    required this.status,
    required this.errorMessage,
  });

  factory ImportPreviewRow.fromJson(Map<String, dynamic> json) {
    final parsed = json.containsKey('parsed_data')
        ? json['parsed_data']
        : json['parsed'];
    final error = json.containsKey('error_message')
        ? json['error_message']
        : json['error'];
    return ImportPreviewRow(
      id: _nullableStringValue(json['id']),
      rowIndex: _intValue(json['row_index']),
      rawData: _mapValue(json['raw_data']),
      parsedData: parsed == null ? null : _mapValue(parsed),
      status: _stringValue(json['status'], fallback: 'unknown'),
      errorMessage: _nullableStringValue(error),
    );
  }
}

class ImportBatch {
  final String id;
  final String? filename;
  final String? sourceProvider;
  final String status;
  final int totalRows;
  final int validRows;
  final int duplicateRows;
  final String? fileHash;
  final String? createdAt;
  final String? committedAt;
  final String? rolledBackAt;

  const ImportBatch({
    required this.id,
    required this.filename,
    required this.sourceProvider,
    required this.status,
    required this.totalRows,
    required this.validRows,
    required this.duplicateRows,
    required this.fileHash,
    required this.createdAt,
    required this.committedAt,
    required this.rolledBackAt,
  });

  factory ImportBatch.fromJson(Map<String, dynamic> json) {
    return ImportBatch(
      id: _stringValue(json['id'] ?? json['batch_id']),
      filename: _nullableStringValue(json['filename']),
      sourceProvider: _nullableStringValue(json['source_provider']),
      status: _stringValue(json['status'], fallback: 'unknown'),
      totalRows: _intValue(json['total_rows']),
      validRows: _intValue(json['valid_rows']),
      duplicateRows: _intValue(json['duplicate_rows']),
      fileHash: _nullableStringValue(json['file_hash']),
      createdAt: _nullableStringValue(json['created_at']),
      committedAt: _nullableStringValue(json['committed_at']),
      rolledBackAt: _nullableStringValue(json['rolled_back_at']),
    );
  }
}

class ImportCommitResult {
  final String batchId;
  final String sourceProvider;
  final int imported;
  final int duplicates;
  final int errors;
  final int skipped;
  final String status;

  const ImportCommitResult({
    required this.batchId,
    required this.sourceProvider,
    required this.imported,
    required this.duplicates,
    required this.errors,
    required this.skipped,
    required this.status,
  });

  factory ImportCommitResult.fromJson(Map<String, dynamic> json) {
    return ImportCommitResult(
      batchId: _stringValue(json['batch_id']),
      sourceProvider: _stringValue(json['source_provider']),
      imported: _intValue(json['imported']),
      duplicates: _intValue(json['duplicates']),
      errors: _intValue(json['errors']),
      skipped: _intValue(json['skipped']),
      status: _stringValue(json['status'], fallback: 'unknown'),
    );
  }
}

class ImportRollbackResult {
  final String batchId;
  final int rolledBack;
  final int skipped;
  final String status;

  const ImportRollbackResult({
    required this.batchId,
    required this.rolledBack,
    required this.skipped,
    required this.status,
  });

  factory ImportRollbackResult.fromJson(Map<String, dynamic> json) {
    return ImportRollbackResult(
      batchId: _stringValue(json['batch_id']),
      rolledBack: _intValue(json['rolled_back']),
      skipped: _intValue(json['skipped']),
      status: _stringValue(json['status'], fallback: 'unknown'),
    );
  }
}

class ExportMetadata {
  final String contractVersion;
  final String entityType;
  final String format;
  final String mediaType;
  final String filename;
  final int sizeBytes;
  final String checksumSha256;
  final Map<String, int> counts;
  final String preview;

  const ExportMetadata({
    required this.contractVersion,
    required this.entityType,
    required this.format,
    required this.mediaType,
    required this.filename,
    required this.sizeBytes,
    required this.checksumSha256,
    required this.counts,
    required this.preview,
  });

  factory ExportMetadata.fromJson(Map<String, dynamic> json) {
    return ExportMetadata(
      contractVersion: _stringValue(json['contract_version']),
      entityType: _stringValue(json['entity_type']),
      format: _stringValue(json['format']),
      mediaType: _stringValue(json['media_type']),
      filename: _stringValue(json['filename']),
      sizeBytes: _intValue(json['size_bytes']),
      checksumSha256: _stringValue(json['checksum_sha256']),
      counts: _intMapValue(json['counts']),
      preview: _stringValue(json['preview']),
    );
  }
}

class ExportStreamPayload {
  final List<int> bytes;
  final ExportStreamMetadata metadata;

  const ExportStreamPayload({required this.bytes, required this.metadata});
}

class ExportStreamMetadata {
  final String entityType;
  final String? contractVersion;
  final String? checksumSha256;
  final int? sizeBytes;
  final String? filename;
  final String? mediaType;

  const ExportStreamMetadata({
    required this.entityType,
    required this.contractVersion,
    required this.checksumSha256,
    required this.sizeBytes,
    required this.filename,
    required this.mediaType,
  });

  factory ExportStreamMetadata.fromHeaders({
    required String entityType,
    required Map<String, String> headers,
  }) {
    return ExportStreamMetadata(
      entityType: entityType,
      contractVersion: headers['x-lifly-export-contract'],
      checksumSha256: headers['x-lifly-export-checksum-sha256'],
      sizeBytes: _nullableIntValue(headers['x-lifly-export-size-bytes']),
      filename: _filenameFromDisposition(headers['content-disposition']),
      mediaType: headers['content-type'],
    );
  }
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  return value.toString();
}

String? _nullableStringValue(Object? value) {
  if (value == null) return null;
  final result = value.toString();
  return result.isEmpty ? null : result;
}

int _intValue(Object? value) => _nullableIntValue(value) ?? 0;

int? _nullableIntValue(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

Map<String, int> _intMapValue(Object? value) {
  return _mapValue(
    value,
  ).map((key, mapValue) => MapEntry(key, _intValue(mapValue)));
}

List<Map<String, dynamic>> _listValue(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

String? _filenameFromDisposition(String? disposition) {
  if (disposition == null || disposition.isEmpty) return null;
  final prefix = 'filename=';
  final index = disposition.indexOf(prefix);
  if (index < 0) return null;
  final raw = disposition
      .substring(index + prefix.length)
      .split(';')
      .first
      .trim();
  if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
    return raw.substring(1, raw.length - 1);
  }
  return raw.isEmpty ? null : raw;
}
