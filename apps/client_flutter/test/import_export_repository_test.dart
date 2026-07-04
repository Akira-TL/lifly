import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:client_flutter/data/repositories/import_export_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeApiClient api;
  late ImportExportRepository repo;

  setUp(() {
    api = _FakeApiClient();
    repo = ImportExportRepository(api);
  });

  test(
    'uploadPreview uploads bill bytes and parses preview contract',
    () async {
      api.multipartResponse = {
        'data': {
          'batch_id': 'batch-1',
          'source_provider': 'wechat',
          'total_rows': 2,
          'valid_rows': 1,
          'duplicate_rows': 0,
          'error_rows': 1,
          'ignored_rows': 0,
          'preview': [
            {
              'row_index': 1,
              'raw_data': {'商户': '咖啡店'},
              'parsed': {
                'direction': 'expense',
                'amount': '18.50',
                'merchant': '咖啡店',
              },
              'status': 'valid',
              'error': null,
            },
          ],
        },
      };

      final result = await repo.uploadPreview(
        bytes: const [1, 2, 3],
        filename: 'wechat.csv',
        provider: ImportProvider.wechat,
      );

      expect(api.calls.single.path, '/import/upload');
      expect(api.calls.single.params, {'provider': 'wechat'});
      expect(api.calls.single.filename, 'wechat.csv');
      expect(result.batchId, 'batch-1');
      expect(result.sourceProvider, 'wechat');
      expect(result.errorRows, 1);
      expect(result.preview.single.parsedData?['merchant'], '咖啡店');
    },
  );

  test('previewDetail parses page data and mixed row keys', () async {
    api.getResponses['/import/batch-1/preview'] = {
      'data': {
        'batch': {
          'id': 'batch-1',
          'status': 'preview',
          'filename': 'alipay.csv',
          'total_rows': 3,
          'valid_rows': 2,
          'duplicate_rows': 1,
        },
        'total': 3,
        'limit': 2,
        'offset': 0,
        'items': [
          {
            'id': 'row-1',
            'row_index': 1,
            'raw_data': {'amount': '8.00'},
            'parsed_data': {'amount': '8.00'},
            'status': 'pending',
            'error_message': null,
          },
          {
            'id': 'row-2',
            'row_index': 2,
            'raw_data': {'amount': '-'},
            'parsed_data': null,
            'status': 'error',
            'error_message': 'Invalid amount',
          },
        ],
      },
    };

    final page = await repo.previewDetail('batch-1', limit: 2);

    expect(api.calls.single.path, '/import/batch-1/preview');
    expect(page.batch.filename, 'alipay.csv');
    expect(page.hasMore, isTrue);
    expect(page.items.last.errorMessage, 'Invalid amount');
  });

  test('commit and rollback parse operation summaries', () async {
    api.postResponses['/import/batch-1/commit'] = {
      'data': {
        'batch_id': 'batch-1',
        'source_provider': 'alipay',
        'imported': 2,
        'duplicates': 1,
        'errors': 0,
        'skipped': 1,
        'status': 'committed',
      },
    };
    api.postResponses['/import/batch-1/rollback'] = {
      'data': {
        'batch_id': 'batch-1',
        'rolled_back': 2,
        'skipped': 0,
        'status': 'rolled_back',
      },
    };

    final commit = await repo.commit('batch-1');
    final rollback = await repo.rollback('batch-1');

    expect(commit.imported, 2);
    expect(commit.duplicates, 1);
    expect(rollback.rolledBack, 2);
    expect(rollback.status, 'rolled_back');
  });

  test('listBatches and getBatch parse batch metadata', () async {
    api.getResponses['/import/batches'] = {
      'data': {
        'total': 1,
        'limit': 20,
        'offset': 0,
        'items': [
          {
            'id': 'batch-1',
            'filename': 'bill.csv',
            'status': 'committed',
            'total_rows': 10,
            'valid_rows': 9,
            'duplicate_rows': 1,
            'created_at': '2026-07-04T10:00:00Z',
            'committed_at': '2026-07-04T10:01:00Z',
            'rolled_back_at': null,
          },
        ],
      },
    };
    api.getResponses['/import/batch-1'] = {
      'data': {
        'id': 'batch-1',
        'filename': 'bill.csv',
        'source_provider': 'wechat',
        'status': 'committed',
        'total_rows': 10,
        'valid_rows': 9,
        'duplicate_rows': 1,
        'file_hash': 'abc',
      },
    };

    final page = await repo.listBatches(status: 'committed');
    final detail = await repo.getBatch('batch-1');

    expect(api.calls.first.params?['status'], 'committed');
    expect(page.items.single.status, 'committed');
    expect(detail.sourceProvider, 'wechat');
    expect(detail.fileHash, 'abc');
  });

  test('exportMetadata and downloadExport parse export contracts', () async {
    api.postResponses['/export'] = {
      'data': {
        'contract_version': 'export.v0.5.6',
        'entity_type': 'ledger_transactions',
        'format': 'csv',
        'media_type': 'text/csv',
        'filename': 'lifly-export-ledger_transactions.csv',
        'size_bytes': 128,
        'checksum_sha256': 'hash-1',
        'counts': {'ledger_transactions': 3},
        'preview': 'id,amount',
      },
    };
    api.binaryResponse = const ApiBinaryResponse(
      bytes: [105, 100, 44, 97, 109, 111, 117, 110, 116],
      headers: {
        'content-disposition':
            'attachment; filename="lifly-export-ledger_transactions.csv"',
        'content-type': 'text/csv',
        'x-lifly-export-contract': 'export.v0.5.6',
        'x-lifly-export-checksum-sha256': 'hash-1',
        'x-lifly-export-size-bytes': '128',
      },
    );

    final metadata = await repo.exportMetadata(
      entityType: ExportEntityType.ledgerTransactions,
    );
    final payload = await repo.downloadExport(
      entityType: ExportEntityType.ledgerTransactions,
    );

    expect(metadata.counts['ledger_transactions'], 3);
    expect(payload.bytes.length, 9);
    expect(payload.metadata.filename, 'lifly-export-ledger_transactions.csv');
    expect(payload.metadata.sizeBytes, 128);
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost/api/v1');

  final List<_ApiCall> calls = [];
  final Map<String, Map<String, dynamic>> getResponses = {};
  final Map<String, Map<String, dynamic>> postResponses = {};
  Map<String, dynamic> multipartResponse = const {'data': {}};
  ApiBinaryResponse binaryResponse = const ApiBinaryResponse(
    bytes: [],
    headers: {},
  );

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    calls.add(_ApiCall(path: path, params: params));
    return getResponses[path] ?? const {'data': {}};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    calls.add(_ApiCall(path: path, data: data));
    return postResponses[path] ?? const {'data': {}};
  }

  @override
  Future<Map<String, dynamic>> postMultipartBytes(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, dynamic>? fields,
    Map<String, dynamic>? params,
  }) async {
    calls.add(
      _ApiCall(
        path: path,
        params: params,
        fieldName: fieldName,
        bytes: bytes,
        filename: filename,
      ),
    );
    return multipartResponse;
  }

  @override
  Future<ApiBinaryResponse> downloadBytes(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    calls.add(_ApiCall(path: path, params: params));
    return binaryResponse;
  }
}

class _ApiCall {
  final String path;
  final Map<String, dynamic>? params;
  final Map<String, dynamic>? data;
  final String? fieldName;
  final List<int>? bytes;
  final String? filename;

  const _ApiCall({
    required this.path,
    this.params,
    this.data,
    this.fieldName,
    this.bytes,
    this.filename,
  });
}
