import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/powersync/powersync_crud_mapper.dart';

class SyncPushResult {
  final int applied;
  final int skipped;
  final List<Map<String, Object?>> results;

  const SyncPushResult({
    required this.applied,
    required this.skipped,
    required this.results,
  });

  factory SyncPushResult.fromJson(Map<String, dynamic> json) {
    final rows = json['results'] as List? ?? const [];
    return SyncPushResult(
      applied: json['applied'] as int? ?? 0,
      skipped: json['skipped'] as int? ?? 0,
      results: rows
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false),
    );
  }
}

class SyncPushUploadDiagnostics {
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final int uploadedChanges;
  final int ignoredChanges;
  final int applied;
  final int skipped;

  const SyncPushUploadDiagnostics({
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.lastError,
    required this.uploadedChanges,
    required this.ignoredChanges,
    required this.applied,
    required this.skipped,
  });

  const SyncPushUploadDiagnostics.idle()
    : lastAttemptAt = null,
      lastSuccessAt = null,
      lastError = null,
      uploadedChanges = 0,
      ignoredChanges = 0,
      applied = 0,
      skipped = 0;

  factory SyncPushUploadDiagnostics.success({
    required DateTime at,
    required int uploadedChanges,
    required int ignoredChanges,
    required SyncPushResult result,
  }) {
    return SyncPushUploadDiagnostics(
      lastAttemptAt: at,
      lastSuccessAt: at,
      lastError: null,
      uploadedChanges: uploadedChanges,
      ignoredChanges: ignoredChanges,
      applied: result.applied,
      skipped: result.skipped,
    );
  }

  factory SyncPushUploadDiagnostics.ignored({
    required DateTime at,
    required int ignoredChanges,
  }) {
    return SyncPushUploadDiagnostics(
      lastAttemptAt: at,
      lastSuccessAt: at,
      lastError: null,
      uploadedChanges: 0,
      ignoredChanges: ignoredChanges,
      applied: 0,
      skipped: 0,
    );
  }

  factory SyncPushUploadDiagnostics.failure({
    required DateTime at,
    required int uploadedChanges,
    required int ignoredChanges,
    required Object error,
  }) {
    return SyncPushUploadDiagnostics(
      lastAttemptAt: at,
      lastSuccessAt: null,
      lastError: error.toString(),
      uploadedChanges: uploadedChanges,
      ignoredChanges: ignoredChanges,
      applied: 0,
      skipped: 0,
    );
  }

  bool get hasError => lastError != null;

  String get statusLabel {
    if (lastAttemptAt == null) return '未上传';
    if (hasError) return '失败';
    if (uploadedChanges == 0) return '无业务变更';
    return '成功';
  }
}

class SyncPushService {
  final ApiClient api;

  const SyncPushService(this.api);

  Future<SyncPushResult> push(EncryptedSyncPushRequestPayload request) async {
    if (!request.hasChanges) {
      throw ArgumentError('sync push request must contain at least one change');
    }

    final response = await api.post('/sync/encrypted', data: request.toJson());
    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw StateError('Sync push response missing data');
    }
    return SyncPushResult.fromJson(data);
  }
}
