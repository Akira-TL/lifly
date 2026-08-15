import 'dart:convert';
import 'dart:io';

import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/auth/auth_session.dart';
import 'package:client_flutter/data/auth/secure_secret_store.dart';
import 'package:client_flutter/data/auth/secure_session_store.dart';
import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/account_e2ee_runtime.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/password_key_envelope_service.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:client_flutter/features/ai_capture/data/external_ai_action_committer.dart';
import 'package:flutter/widgets.dart';

class _MemorySecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) stderr.writeln(message);
  };

  final input = await stdin.transform(utf8.decoder).join();
  final decoded = jsonDecode(input);
  if (decoded is! Map) {
    throw const FormatException('Golden bootstrap must be an object');
  }
  final bootstrap = Map<String, dynamic>.from(decoded);
  final apiBase = _requiredString(bootstrap, 'api_base_url');
  final session = AuthSession.fromJson(_requiredMap(bootstrap, 'session'));
  final keyVersion = bootstrap['account_data_key_version'];
  if (keyVersion is! int || keyVersion < 1) {
    throw const FormatException('account_data_key_version must be positive');
  }
  final accountDataKeyBytes = base64Url.decode(
    _padBase64(_requiredString(bootstrap, 'account_data_key')),
  );
  final accountDataKey = AccountDataKey.fromBytes(
    keyVersion: keyVersion,
    bytes: accountDataKeyBytes,
  );
  accountDataKeyBytes.fillRange(0, accountDataKeyBytes.length, 0);
  final action = AiCandidateAction.fromJson(_requiredMap(bootstrap, 'action'));
  final marker = _requiredString(bootstrap, 'marker');
  final dbPath = _requiredString(bootstrap, 'db_path');

  final secrets = _MemorySecretStore();
  final sessions = SecureAuthSessionStore(secrets);
  await sessions.write(session);
  final api = ApiClient(
    baseUrl: apiBase,
    accessTokenProvider: sessions.readAccessToken,
  );
  final syncService = SyncService(api: api);
  await syncService.initialize(dbPath: dbPath);
  final e2ee = AccountE2eeRuntime(
    syncService: syncService,
    sessions: sessions,
    secrets: secrets,
    passwordEnvelopes: PasswordKeyEnvelopeService(api),
  );

  try {
    await e2ee.initializeWithLocalDataKey(
      accountId: session.account.accountId,
      dataKey: accountDataKey,
    );
    final bridge = PowerSyncLocalCoreBridge(
      syncService: syncService,
      auditPayloadProtector: e2ee,
      version: '0.9.0',
    );
    final committer = LocalCoreExternalAiActionCommitter(
      bridge: bridge,
      sessions: sessions,
    );
    final committed = await committer.commit(action);

    final entityEnvelope = await syncService.db.getOptional(
      'SELECT revision, lifecycle_status, ciphertext FROM encrypted_entities '
      'WHERE id = ? AND entity_type = ?',
      [committed.entityId, committed.entityType],
    );
    if (entityEnvelope == null) {
      throw StateError(
        'Committed entity did not enter encrypted sync data plane',
      );
    }
    final entityCiphertext = entityEnvelope['ciphertext']?.toString() ?? '';
    if (entityCiphertext.isEmpty || entityCiphertext.contains(marker)) {
      throw StateError('Committed entity ciphertext leaked Golden marker');
    }

    final audit = await syncService.db.getOptional(
      'SELECT before_snapshot, after_snapshot, source_text FROM audit_logs '
      'WHERE entity_id = ? ORDER BY created_at DESC LIMIT 1',
      [committed.entityId],
    );
    if (audit == null ||
        audit['before_snapshot'] != null ||
        audit['after_snapshot'] != null ||
        audit['source_text'] != null) {
      throw StateError('Sensitive audit payload was persisted in plaintext');
    }
    final encryptedAudit = await syncService.db.getOptional(
      "SELECT ciphertext FROM encrypted_entities WHERE entity_type = 'audit' "
      'ORDER BY updated_at DESC LIMIT 1',
    );
    final auditCiphertext = encryptedAudit?['ciphertext']?.toString() ?? '';
    if (auditCiphertext.isEmpty || auditCiphertext.contains(marker)) {
      throw StateError(
        'Encrypted audit envelope is missing or leaked Golden marker',
      );
    }

    final undone = await committer.undo(committed.undoToken);
    if (undone.undone < 1) {
      throw StateError('Golden candidate undo did not affect an entity');
    }
    final postUndoEnvelope = await syncService.db.getOptional(
      'SELECT revision, ciphertext FROM encrypted_entities WHERE id = ?',
      [committed.entityId],
    );
    final revision = postUndoEnvelope?['revision'];
    if (revision is! num || revision.toInt() < 2) {
      throw StateError(
        'Undo did not publish a newer encrypted entity revision',
      );
    }

    stdout.writeln(
      jsonEncode({
        'status': 'pass',
        'entity_type': committed.entityType,
        'entity_id': committed.entityId,
        'encrypted_revision': revision.toInt(),
        'undo_count': undone.undone,
      }),
    );
    await stdout.flush();
  } finally {
    syncService.dispose();
  }
  exit(0);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing $key');
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('Missing object $key');
}

String _padBase64(String value) {
  final padding = (4 - value.length % 4) % 4;
  return '$value${List<String>.filled(padding, '=').join()}';
}
