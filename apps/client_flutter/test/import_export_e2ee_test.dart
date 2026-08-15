import 'dart:convert';

import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/import_export_models.dart';
import 'package:client_flutter/data/repositories/import_export_repository.dart';
import 'package:client_flutter/features/import_export/data/local_plaintext_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'plaintext export is generated only from local decrypted projection with warning',
    () async {
      final source = _FakeLocalExportDataSource();
      final builder = LocalPlaintextExportBuilder(source);

      final result = await builder.build(entityType: ExportEntityType.memos);
      final decoded =
          jsonDecode(utf8.decode(result.bytes)) as Map<String, dynamic>;

      expect(result.metadata.mode, ExportMode.plaintext);
      expect(result.metadata.executionLocation, 'trusted_client');
      expect(result.metadata.containsDecryptedUserData, isTrue);
      expect(result.metadata.availableFromCloud, isFalse);
      expect(result.metadata.privacyWarning, contains('明文'));
      expect(decoded['memos'][0]['content_markdown'], 'private local memo');
      expect(source.queries.single, contains('FROM memos'));
      expect(source.parameters.single, ['account-1', 'active']);
    },
  );

  test('encrypted backup requests cloud ciphertext mode explicitly', () async {
    final api = _FakeExportApiClient();
    final repository = ImportExportRepository(api);

    final metadata = await repository.exportMetadata(
      mode: ExportMode.encryptedBackup,
    );
    final download = await repository.downloadExport(
      mode: ExportMode.encryptedBackup,
    );

    expect(metadata.mode, ExportMode.encryptedBackup);
    expect(metadata.containsDecryptedUserData, isFalse);
    expect(api.metadataPayload?['mode'], 'encrypted_backup');
    expect(api.downloadParams?['mode'], 'encrypted_backup');
    expect(download.metadata.mode, ExportMode.encryptedBackup);
  });

  test('repository refuses cloud plaintext download', () async {
    final repository = ImportExportRepository(_FakeExportApiClient());

    expect(
      () => repository.downloadExport(mode: ExportMode.plaintext),
      throwsArgumentError,
    );
  });
}

class _FakeLocalExportDataSource implements LocalPlaintextExportDataSource {
  final List<String> queries = [];
  final List<List<Object?>> parameters = [];

  @override
  Future<String> currentAccountId() async => 'account-1';

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    queries.add(sql);
    this.parameters.add(List<Object?>.from(parameters));
    return [
      {
        'id': 'memo-1',
        'user_id': 'account-1',
        'title': 'private title',
        'content_markdown': 'private local memo',
        'status': 'active',
        'updated_at': '2026-08-15T10:00:00Z',
      },
    ];
  }
}

class _FakeExportApiClient extends ApiClient {
  _FakeExportApiClient() : super(baseUrl: 'http://example.invalid/api/v1');

  Map<String, dynamic>? metadataPayload;
  Map<String, dynamic>? downloadParams;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    expect(path, '/export');
    metadataPayload = Map<String, dynamic>.from(data ?? const {});
    return {
      'data': {
        'contract_version': 'export.e2ee.v1',
        'mode': 'encrypted_backup',
        'execution_location': 'cloud_ciphertext_only',
        'contains_decrypted_user_data': false,
        'available_from_cloud': true,
        'privacy_warning': 'encrypted',
        'entity_type': 'all',
        'format': 'json',
        'media_type': 'application/json',
        'filename': 'lifly-encrypted-backup.json',
        'size_bytes': 128,
        'checksum_sha256': 'abc',
        'counts': {'encrypted_entities': 1},
        'preview': '',
      },
    };
  }

  @override
  Future<ApiBinaryResponse> downloadBytes(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    expect(path, '/export/stream');
    downloadParams = Map<String, dynamic>.from(params ?? const {});
    return const ApiBinaryResponse(
      bytes: [123, 125],
      headers: {
        'content-disposition':
            'attachment; filename="lifly-encrypted-backup.json"',
        'content-type': 'application/json',
        'x-lifly-export-contract': 'export.e2ee.v1',
        'x-lifly-export-mode': 'encrypted_backup',
        'x-lifly-export-checksum-sha256': 'abc',
        'x-lifly-export-size-bytes': '2',
      },
    );
  }
}
