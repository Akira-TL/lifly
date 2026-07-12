import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/powersync_persistence_harness.dart';

void main() {
  test('PowerSyncLocalCoreBridge reports health or diagnostic error', () async {
    final service = SyncService();
    addTearDown(service.dispose);

    final health = await PowerSyncLocalCoreBridge(
      syncService: service,
    ).health();

    expect(health.mode, 'powersync');
    expect(health.version, '0.2.5');
    expect(health.checkedAt, isNotNull);
    expect(health.status, anyOf('ok', 'error'));

    if (health.status == 'error') {
      expect(health.detail, isNot(isEmpty));
    } else {
      expect(health.detail, contains('database initialized'));
    }
  });

  test('PowerSync home overview reports real sync and import summaries', () async {
    final harness = await PowerSyncPersistenceHarness.create(
      'lifly_home_summary_',
    );
    addTearDown(harness.dispose);

    final service = await harness.openService();
    if (service == null) return;

    await service.db.execute(
      'INSERT INTO assets(id, user_id, sync_status, status, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        'asset-failed',
        'local-dev',
        'failed',
        'active',
        '2026-07-11T10:00:00Z',
        '2026-07-11T10:00:00Z',
      ],
    );
    await service.db.execute(
      'INSERT INTO import_batches('
      'id, user_id, source_provider, filename, status, total_rows, valid_rows, '
      'duplicate_rows, created_at, committed_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'batch-1',
        'local-dev',
        'alipay',
        'alipay.csv',
        'committed',
        20,
        18,
        2,
        '2026-07-11T10:00:00Z',
        '2026-07-11T10:05:00Z',
      ],
    );

    final overview = await PowerSyncLocalCoreBridge(
      syncService: service,
    ).getHomeOverview(
      {
        'source_mode': 'local',
        'user_timezone': 'Asia/Shanghai',
      },
      LocalCoreContext.flutterUser(
        now: DateTime.utc(2026, 7, 11, 12),
      ),
    );

    expect(overview.syncSummary.status, 'error');
    expect(overview.syncSummary.failedAssetCount, 1);
    expect(overview.importSummary.status, 'committed');
    expect(overview.importSummary.latestBatchId, 'batch-1');
    expect(overview.importSummary.validRows, 18);
    expect(overview.settingsSummary.localCoreAvailable, isTrue);
    expect(overview.settingsSummary.timezone, 'Asia/Shanghai');

    service.dispose();
  });
}
