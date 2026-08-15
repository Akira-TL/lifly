import type {
  AssetRegisterExternalUrlInput,
  CaptureCommitInput,
  CaptureParseInput,
  CaptureUndoInput,
  ExpenseCreateInput,
  ExpenseSearchInput,
  ExpenseSummaryInput,
  LocalAsset,
  LocalCaptureCommitResult,
  LocalCaptureSession,
  LocalCaptureUndoResult,
  LocalCoreContext,
  LocalCoreHealth,
  LocalExpenseSummary,
  LocalLedgerTransaction,
  LocalMemo,
  LocalTask,
  MemoCreateInput,
  MemoSearchInput,
  TaskCompleteInput,
  TaskCreateInput,
  TaskListInput,
} from "./types.js";

export interface DesktopLocalCoreOperationMap {
  health: { input: null; result: LocalCoreHealth };
  memo_create: { input: MemoCreateInput; result: LocalMemo };
  memo_search: { input: MemoSearchInput; result: LocalMemo[] };
  expense_create: { input: ExpenseCreateInput; result: LocalLedgerTransaction };
  expense_search: { input: ExpenseSearchInput; result: LocalLedgerTransaction[] };
  expense_summary: { input: ExpenseSummaryInput; result: LocalExpenseSummary };
  task_create: { input: TaskCreateInput; result: LocalTask };
  task_list: { input: TaskListInput; result: LocalTask[] };
  task_complete: { input: TaskCompleteInput; result: LocalTask };
  asset_register_external_url: { input: AssetRegisterExternalUrlInput; result: LocalAsset };
  capture_parse: { input: CaptureParseInput; result: LocalCaptureSession };
  capture_commit: { input: CaptureCommitInput; result: LocalCaptureCommitResult };
  capture_undo: { input: CaptureUndoInput; result: LocalCaptureUndoResult };
}

export type DesktopLocalCoreMethod = keyof DesktopLocalCoreOperationMap;

export interface DesktopLocalCoreInvocation<M extends DesktopLocalCoreMethod = DesktopLocalCoreMethod> {
  method: M;
  input: DesktopLocalCoreOperationMap[M]["input"];
  context?: LocalCoreContext;
}

export interface DesktopLocalCoreTransport {
  invoke<M extends DesktopLocalCoreMethod>(
    request: DesktopLocalCoreInvocation<M>,
  ): Promise<DesktopLocalCoreOperationMap[M]["result"]>;
  close?(): Promise<void> | void;
}
