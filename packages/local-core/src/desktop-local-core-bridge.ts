import type { LocalCoreBridge } from "./bridge.js";
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

export interface DesktopLocalCoreBridgeOptions {
  version?: string;
  bridgePath?: string | null;
}

export class DesktopLocalCoreBridge implements LocalCoreBridge {
  private readonly version: string;
  private readonly bridgePath: string | null;

  constructor(options: DesktopLocalCoreBridgeOptions = {}) {
    this.version = options.version ?? "0.4.6";
    this.bridgePath = options.bridgePath ?? null;
  }

  async health(): Promise<LocalCoreHealth> {
    return {
      status: "unavailable",
      mode: "desktop_bridge",
      version: this.version,
      runtime: "desktop",
      detail: this.bridgePath
        ? `Desktop Local Core bridge is configured but not connected: ${this.bridgePath}`
        : "Desktop Local Core bridge is not connected. Start the Lifly desktop host before using Local MCP writes.",
    };
  }

  async createMemo(input: MemoCreateInput, context: LocalCoreContext): Promise<LocalMemo> {
    return this.unavailable("createMemo", input, context);
  }

  async searchMemos(input: MemoSearchInput, context: LocalCoreContext): Promise<LocalMemo[]> {
    return this.unavailable("searchMemos", input, context);
  }

  async createExpense(input: ExpenseCreateInput, context: LocalCoreContext): Promise<LocalLedgerTransaction> {
    return this.unavailable("createExpense", input, context);
  }

  async searchExpenses(input: ExpenseSearchInput, context: LocalCoreContext): Promise<LocalLedgerTransaction[]> {
    return this.unavailable("searchExpenses", input, context);
  }

  async summarizeExpenses(input: ExpenseSummaryInput, context: LocalCoreContext): Promise<LocalExpenseSummary> {
    return this.unavailable("summarizeExpenses", input, context);
  }

  async createTask(input: TaskCreateInput, context: LocalCoreContext): Promise<LocalTask> {
    return this.unavailable("createTask", input, context);
  }

  async listTasks(input: TaskListInput, context: LocalCoreContext): Promise<LocalTask[]> {
    return this.unavailable("listTasks", input, context);
  }

  async completeTask(input: TaskCompleteInput, context: LocalCoreContext): Promise<LocalTask> {
    return this.unavailable("completeTask", input, context);
  }

  async registerExternalAsset(input: AssetRegisterExternalUrlInput, context: LocalCoreContext): Promise<LocalAsset> {
    return this.unavailable("registerExternalAsset", input, context);
  }

  async captureParse(input: CaptureParseInput, context: LocalCoreContext): Promise<LocalCaptureSession> {
    return this.unavailable("captureParse", input, context);
  }

  async captureCommit(input: CaptureCommitInput, context: LocalCoreContext): Promise<LocalCaptureCommitResult> {
    return this.unavailable("captureCommit", input, context);
  }

  async captureUndo(input: CaptureUndoInput, context: LocalCoreContext): Promise<LocalCaptureUndoResult> {
    return this.unavailable("captureUndo", input, context);
  }

  private unavailable(method: string, input: unknown, context: LocalCoreContext): never {
    void input;
    throw new Error(
      `Local Core desktop bridge is not connected for ${method}. `
      + `tool=${context.toolName ?? "unknown"}; `
      + "Local MCP must be hosted by Lifly desktop and must not write SQLite directly.",
    );
  }
}
