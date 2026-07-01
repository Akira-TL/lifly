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

export interface LocalCoreBridge {
  health(): Promise<LocalCoreHealth>;

  createMemo(input: MemoCreateInput, context: LocalCoreContext): Promise<LocalMemo>;
  searchMemos(input: MemoSearchInput, context: LocalCoreContext): Promise<LocalMemo[]>;

  createExpense(input: ExpenseCreateInput, context: LocalCoreContext): Promise<LocalLedgerTransaction>;
  searchExpenses(input: ExpenseSearchInput, context: LocalCoreContext): Promise<LocalLedgerTransaction[]>;
  summarizeExpenses(input: ExpenseSummaryInput, context: LocalCoreContext): Promise<LocalExpenseSummary>;

  createTask(input: TaskCreateInput, context: LocalCoreContext): Promise<LocalTask>;
  listTasks(input: TaskListInput, context: LocalCoreContext): Promise<LocalTask[]>;
  completeTask(input: TaskCompleteInput, context: LocalCoreContext): Promise<LocalTask>;

  registerExternalAsset(input: AssetRegisterExternalUrlInput, context: LocalCoreContext): Promise<LocalAsset>;

  captureParse(input: CaptureParseInput, context: LocalCoreContext): Promise<LocalCaptureSession>;
  captureCommit(input: CaptureCommitInput, context: LocalCoreContext): Promise<LocalCaptureCommitResult>;
  captureUndo(input: CaptureUndoInput, context: LocalCoreContext): Promise<LocalCaptureUndoResult>;
}

export function localMcpContext(toolName: string): LocalCoreContext {
  return {
    actorType: "ai",
    sourceChannel: "local_mcp",
    toolName,
  };
}
