import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'SyncService local mutation flusher is explicit and replaceable',
    () async {
      final service = SyncService();
      var calls = 0;
      service.setLocalMutationFlusher(() async {
        calls += 1;
      });

      await service.flushLocalMutations();
      expect(calls, 1);

      service.setLocalMutationFlusher(null);
      await service.flushLocalMutations();
      expect(calls, 1);
    },
  );
}
