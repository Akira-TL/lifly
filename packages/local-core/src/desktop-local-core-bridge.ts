import type { LocalCoreBridge } from "./bridge.js";
import type {
  DesktopLocalCoreMethod,
  DesktopLocalCoreOperationMap,
  DesktopLocalCoreTransport,
} from "./desktop-transport.js";
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
  transport?: DesktopLocalCoreTransport | null;
}

export class DesktopLocalCoreBridge implements LocalCoreBridge {
  private readonly version: string;
  private readonly bridgePath: string | null;
  private readonly transport: DesktopLocalCoreTransport | null;

  constructor(options: DesktopLocalCoreBridgeOptions = {}) {
    this.version = options.version ?? "0.9.0";
    this.bridgePath = options.bridgePath ?? null;
    this.transport = options.transport ?? null;
  }

  async health(): Promise<LocalCoreHealth> {
    if (!this.transport) return this.unavailableHealth();

    try {
      return await this.transport.invoke({ method: "health", input: null });
    } catch (error) {
      return {
        ...this.unavailableHealth(),
        detail: `Desktop Local Core bridge transport failed${this.bridgePath ? ` (${this.bridgePath})` : ""}: ${this.errorMessage(error)}`,
      };
    }
  }

  async createMemo(input: MemoCreateInput, context: LocalCoreContext): Promise<LocalMemo> {
    return this.invoke("memo_create", input, context);
  }

  async searchMemos(input: MemoSearchInput, context: LocalCoreContext): Promise<LocalMemo[]> {
    return this.invoke("memo_search", input, context);
  }

  async createExpense(input: ExpenseCreateInput, context: LocalCoreContext): Promise<LocalLedgerTransaction> {
    return this.invoke("expense_create", input, context);
  }

  async searchExpenses(input: ExpenseSearchInput, context: LocalCoreContext): Promise<LocalLedgerTransaction[]> {
    return this.invoke("expense_search", input, context);
  }

  async summarizeExpenses(input: ExpenseSummaryInput, context: LocalCoreContext): Promise<LocalExpenseSummary> {
    return this.invoke("expense_summary", input, context);
  }

  async createTask(input: TaskCreateInput, context: LocalCoreContext): Promise<LocalTask> {
    return this.invoke("task_create", input, context);
  }

  async listTasks(input: TaskListInput, context: LocalCoreContext): Promise<LocalTask[]> {
    return this.invoke("task_list", input, context);
  }

  async completeTask(input: TaskCompleteInput, context: LocalCoreContext): Promise<LocalTask> {
    return this.invoke("task_complete", input, context);
  }

  async registerExternalAsset(input: AssetRegisterExternalUrlInput, context: LocalCoreContext): Promise<LocalAsset> {
    return this.invoke("asset_register_external_url", input, context);
  }

  async captureParse(input: CaptureParseInput, context: LocalCoreContext): Promise<LocalCaptureSession> {
    return this.invoke("capture_parse", input, context);
  }

  async captureCommit(input: CaptureCommitInput, context: LocalCoreContext): Promise<LocalCaptureCommitResult> {
    return this.invoke("capture_commit", input, context);
  }

  async captureUndo(input: CaptureUndoInput, context: LocalCoreContext): Promise<LocalCaptureUndoResult> {
    return this.invoke("capture_undo", input, context);
  }

  async close(): Promise<void> {
    await this.transport?.close?.();
  }

  private async invoke<M extends Exclude<DesktopLocalCoreMethod, "health">>(
    method: M,
    input: DesktopLocalCoreOperationMap[M]["input"],
    context: LocalCoreContext,
  ): Promise<DesktopLocalCoreOperationMap[M]["result"]> {
    if (!this.transport) {
      throw new Error(
        `Local Core desktop bridge is not connected for ${method}. `
        + `tool=${context.toolName ?? "unknown"}; `
        + "Local MCP must be hosted by Lifly desktop and must not write SQLite directly.",
      );
    }
    return this.transport.invoke({ method, input, context });
  }

  private unavailableHealth(): LocalCoreHealth {
    return {
      status: "unavailable",
      mode: "desktop_bridge",
      version: this.version,
      runtime: "desktop",
      detail: this.bridgePath
        ? `Desktop Local Core bridge is configured but not connected: ${this.bridgePath}`
        : "Desktop Local Core bridge transport is not configured. Start the Lifly desktop host before using Local MCP writes.",
    };
  }

  private errorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
  }
}
