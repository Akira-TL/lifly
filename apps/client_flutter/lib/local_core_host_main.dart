import 'dart:convert';
import 'dart:io';

import 'package:client_flutter/data/crypto/account_data_key.dart';
import 'package:client_flutter/data/crypto/account_data_key_ring.dart';
import 'package:client_flutter/data/local_core/desktop_local_core_host.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/write/encrypted_audit_payload_protector.dart';
import 'package:client_flutter/data/powersync/encrypted_sync_store.dart';
import 'package:client_flutter/data/powersync/plaintext_e2ee_migrator.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && message.isNotEmpty) stderr.writeln(message);
  };

  final dbPath = _databasePath();
  await Directory(File(dbPath).parent.path).create(recursive: true);
  final syncService = SyncService();
  await syncService.initialize(dbPath: dbPath);
  DesktopLocalCoreHost? host;

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    Map<String, Object?> response;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException(
          'Desktop Local Core request must be an object',
        );
      }
      final request = decoded.cast<String, dynamic>();
      if (request['method'] == '_runtime_init') {
        host = await _initializeRuntime(syncService, request);
        response = {
          'id': request['id'] is int ? request['id'] as int : 0,
          'ok': true,
          'result': {'status': 'initialized'},
        };
      } else {
        final activeHost = host;
        if (activeHost == null) {
          throw StateError(
            'Desktop Local Core runtime must be initialized before use',
          );
        }
        response = await activeHost.handle(request);
      }
    } catch (error) {
      response = {
        'id': 0,
        'ok': false,
        'error': {'code': 'LOCAL_CORE_HOST_ERROR', 'message': error.toString()},
      };
    }
    stdout.writeln(jsonEncode(response));
    await stdout.flush();
  }
  syncService.dispose();
  exit(0);
}

Future<DesktopLocalCoreHost> _initializeRuntime(
  SyncService syncService,
  Map<String, dynamic> request,
) async {
  final rawInput = request['input'];
  if (rawInput is! Map) {
    throw const FormatException('Desktop Local Core runtime init needs input');
  }
  final input = Map<String, dynamic>.from(rawInput);
  final accountId = _requiredString(input, 'account_id');
  final keyVersion = input['key_version'];
  if (keyVersion is! int || keyVersion < 1) {
    throw const FormatException('key_version must be a positive integer');
  }
  final encodedKey = _requiredString(input, 'account_data_key_base64');
  final keyBytes = base64Decode(encodedKey);
  if (keyBytes.length != AccountDataKey.byteLength) {
    throw const FormatException('Account Data Key must be 32 bytes');
  }
  final dataKey = AccountDataKey.fromBytes(
    keyVersion: keyVersion,
    bytes: keyBytes,
  );
  for (var index = 0; index < keyBytes.length; index += 1) {
    keyBytes[index] = 0;
  }

  final store = PowerSyncEncryptedSyncStore(
    db: syncService.db,
    accountId: accountId,
    keyRing: AccountDataKeyRing(dataKey),
  );
  Future<void> flushProjection() => PlaintextE2eeMigrator(
    db: syncService.db,
    store: store,
    accountId: accountId,
  ).migrateCoreEntities();
  await flushProjection();
  syncService.setLocalMutationFlusher(flushProjection);
  final bridge = PowerSyncLocalCoreBridge(
    syncService: syncService,
    auditPayloadProtector: EncryptedSyncAuditPayloadProtector(store),
    version: '0.9.0',
  );
  return DesktopLocalCoreHost(bridge, userId: accountId);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing $key');
}

String _databasePath() {
  final configured = Platform.environment['LIFLY_LOCAL_CORE_DB_PATH']?.trim();
  if (configured != null && configured.isNotEmpty) return configured;
  final home = Platform.environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    return '$home/.local/share/lifly/lifly-local-core.db';
  }
  return '${Directory.current.path}/lifly-local-core.db';
}
