import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_ids.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:client_flutter/data/local_core/local_home_overview_builder.dart';
import 'package:client_flutter/data/local_core/memo/local_memo_classification_engine.dart';
import 'package:client_flutter/data/local_core/task/local_task_reminder_strategy_engine.dart';

part 'fake/fake_capture_store.dart';
part 'fake/fake_ledger_store.dart';
part 'fake/fake_memo_store.dart';
part 'fake/fake_task_store.dart';

const Object _fakeReminderUnchanged = Object();
const Object _fakeCaptureUnchanged = Object();

abstract class _FakeLocalCoreState implements LocalCoreBridge {
  List<LocalMemoRecord> get _memos;
  List<LocalMemoClassification> get _memoClassifications;
  List<LocalTagMetadata> get _tagMetadata;
  List<LocalLedgerTransactionRecord> get _expenses;
  List<LocalLedgerBudget> get _ledgerBudgets;
  List<LocalTaskRecord> get _tasks;
  List<LocalTaskReminderStrategy> get _taskReminderStrategies;
  List<LocalReminderRecord> get _reminders;
  List<LocalAssetRecord> get _assets;
  Map<String, LocalCaptureSession> get _captures;
  Map<String, List<LocalCoreEntityRef>> get _undoEntries;
  Map<String, String> get _undoCaptureIds;

  String _nextStableId(String prefix);
}

class FakeLocalCoreBridge extends _FakeLocalCoreState
    with
        _FakeMemoStore,
        _FakeLedgerStore,
        _FakeTaskStore,
        _FakeCaptureStore {
  final LocalCoreIdGenerator _idGenerator;

  FakeLocalCoreBridge({LocalCoreIdGenerator? idGenerator})
    : _idGenerator = idGenerator ?? LocalCoreIdGenerator();

  @override
  final List<LocalMemoRecord> _memos = [];
  @override
  final List<LocalMemoClassification> _memoClassifications = [];
  @override
  final List<LocalTagMetadata> _tagMetadata = [];
  @override
  final List<LocalLedgerTransactionRecord> _expenses = [];
  @override
  final List<LocalLedgerBudget> _ledgerBudgets = [];
  @override
  final List<LocalTaskRecord> _tasks = [];
  @override
  final List<LocalTaskReminderStrategy> _taskReminderStrategies = [];
  @override
  final List<LocalReminderRecord> _reminders = [];
  @override
  final List<LocalAssetRecord> _assets = [];
  @override
  final Map<String, LocalCaptureSession> _captures = {};
  @override
  final Map<String, List<LocalCoreEntityRef>> _undoEntries = {};
  @override
  final Map<String, String> _undoCaptureIds = {};

  @override
  Future<LocalCoreHealth> health() async {
    return LocalCoreHealth(
      status: 'ok',
      mode: 'fake',
      version: '0.2.1',
      detail: 'in-memory fallback bridge',
      checkedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<LocalHomeOverview> getHomeOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final summary = await summarizeExpenses({
      'period': input['period'] as String? ?? 'current_month',
    }, context);
    return const LocalHomeOverviewBuilder().build(
      memos: _memos,
      tasks: _tasks,
      transactions: _expenses,
      summary: summary,
      now: context.effectiveNow,
      sourceMode: input['source_mode'] as String? ?? 'local',
    );
  }

  @override
  String _nextStableId(String prefix) => _idGenerator.nextStable(prefix);
}
