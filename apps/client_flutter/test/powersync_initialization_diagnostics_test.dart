import 'dart:async';

import 'package:client_flutter/data/powersync/powersync_initialization_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initialization single-flight shares one active operation', () async {
    final gate = InitializationSingleFlight();
    final completer = Completer<void>();
    var runs = 0;
    var joins = 0;

    Future<void> initialize() {
      return gate.run(() async {
        runs += 1;
        await completer.future;
      }, onJoin: () => joins += 1);
    }

    final first = initialize();
    final second = initialize();
    final third = initialize();

    expect(gate.isRunning, isTrue);
    expect(runs, 1);
    expect(joins, 2);

    completer.complete();
    await Future.wait([first, second, third]);

    expect(gate.isRunning, isFalse);
  });

  test('initialization single-flight allows retry after failure', () async {
    final gate = InitializationSingleFlight();
    var runs = 0;

    await expectLater(
      gate.run(() async {
        runs += 1;
        throw StateError('first attempt failed');
      }),
      throwsStateError,
    );

    await gate.run(() async => runs += 1);

    expect(runs, 2);
    expect(gate.isRunning, isFalse);
  });

  test('PowerSync failure report includes actionable context', () {
    final failure = PowerSyncInitializationFailure(
      diagnosticId: 'PS-TEST',
      occurredAt: DateTime.utc(2026, 7, 30, 10),
      stage: 'database_initialize_start',
      databasePath: 'lifly-local-core.db',
      pageUri: Uri.parse('http://127.0.0.1:8211/'),
      schemaTableCount: 18,
      cause: StateError('Unexpected null value'),
      causeStackTrace: StackTrace.fromString('frame one\nframe two'),
      events: const ['schema_validate_ok', 'database_construct_ok'],
    );

    expect(failure.report, contains('id=PS-TEST'));
    expect(failure.report, contains('stage=database_initialize_start'));
    expect(failure.report, contains('cause_type=StateError'));
    expect(failure.report, contains('frame one'));
  });
}
