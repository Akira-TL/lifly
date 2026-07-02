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
  LocalCaptureAction,
  LocalCaptureCommitResult,
  LocalCaptureSession,
  LocalCaptureUndoResult,
  LocalCoreContext,
  LocalCoreEntityRef,
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

export class FakeLocalCoreBridge implements LocalCoreBridge {
  private memoSeq = 0;
  private expenseSeq = 0;
  private taskSeq = 0;
  private assetSeq = 0;
  private captureSeq = 0;
  private undoSeq = 0;

  private readonly memos: LocalMemo[] = [];
  private readonly expenses: LocalLedgerTransaction[] = [];
  private readonly tasks: LocalTask[] = [];
  private readonly assets: LocalAsset[] = [];
  private readonly captures = new Map<string, LocalCaptureSession>();
  private readonly undoEntries = new Map<string, LocalCoreEntityRef[]>();

  async health(): Promise<LocalCoreHealth> {
    return { status: "ok", mode: "fake", version: "0.1.0", runtime: "test" };
  }

  async createMemo(input: MemoCreateInput, context: LocalCoreContext): Promise<LocalMemo> {
    const now = this.now(context);
    const memo: LocalMemo = {
      id: this.nextId("memo", ++this.memoSeq),
      type: input.type,
      title: input.title ?? null,
      content_markdown: input.content_markdown,
      tags: input.tags ?? [],
      status: "active",
      revision: 1,
      created_at: now,
      updated_at: now,
    };
    this.memos.unshift(memo);
    return memo;
  }

  async searchMemos(input: MemoSearchInput): Promise<LocalMemo[]> {
    const q = input.q.trim().toLowerCase();
    return this.memos
      .filter((memo) => memo.status === "active")
      .filter((memo) => !q || `${memo.title ?? ""}\n${memo.content_markdown}`.toLowerCase().includes(q))
      .slice(0, input.limit);
  }

  async createExpense(input: ExpenseCreateInput, context: LocalCoreContext): Promise<LocalLedgerTransaction> {
    const now = this.now(context);
    const tx: LocalLedgerTransaction = {
      id: this.nextId("tx", ++this.expenseSeq),
      direction: input.direction,
      amount: input.amount,
      currency: input.currency,
      merchant: input.merchant,
      note: input.note ?? null,
      category_hint: input.category_hint ?? null,
      occurred_at: input.occurred_at ?? now,
      status: "active",
      revision: 1,
      created_at: now,
      updated_at: now,
    };
    this.expenses.unshift(tx);
    return tx;
  }

  async searchExpenses(input: ExpenseSearchInput): Promise<LocalLedgerTransaction[]> {
    const q = input.q.trim().toLowerCase();
    return this.expenses
      .filter((tx) => tx.status === "active")
      .filter((tx) => !q || `${tx.merchant ?? ""}\n${tx.note ?? ""}`.toLowerCase().includes(q))
      .slice(0, input.limit);
  }

  async summarizeExpenses(input: ExpenseSummaryInput): Promise<LocalExpenseSummary> {
    const active = this.expenses.filter((tx) => tx.status === "active");
    return {
      period: input.period,
      total_expense: active.filter((tx) => tx.direction === "expense").reduce((sum, tx) => sum + tx.amount, 0),
      total_income: active.filter((tx) => tx.direction === "income").reduce((sum, tx) => sum + tx.amount, 0),
      count: active.length,
    };
  }

  async createTask(input: TaskCreateInput, context: LocalCoreContext): Promise<LocalTask> {
    const now = this.now(context);
    const task: LocalTask = {
      id: this.nextId("task", ++this.taskSeq),
      title: input.title,
      description: input.description ?? null,
      due_at: input.due_at ?? null,
      remind_at: input.remind_at ?? null,
      priority: input.priority,
      task_status: "todo",
      completed_at: null,
      status: "active",
      revision: 1,
      created_at: now,
      updated_at: now,
    };
    this.tasks.unshift(task);
    return task;
  }

  async listTasks(input: TaskListInput): Promise<LocalTask[]> {
    return this.tasks
      .filter((task) => task.status === "active")
      .filter((task) => !input.task_status || task.task_status === input.task_status)
      .slice(0, input.limit);
  }

  async completeTask(input: TaskCompleteInput, context: LocalCoreContext): Promise<LocalTask> {
    const task = this.tasks.find((item) => item.id === input.task_id && item.status === "active");
    if (!task) throw new Error(`Task not found: ${input.task_id}`);
    task.task_status = "done";
    task.completed_at = this.now(context);
    task.updated_at = task.completed_at;
    task.revision += 1;
    return task;
  }

  async registerExternalAsset(input: AssetRegisterExternalUrlInput, context: LocalCoreContext): Promise<LocalAsset> {
    const now = this.now(context);
    const asset: LocalAsset = {
      id: this.nextId("asset", ++this.assetSeq),
      kind: "external",
      asset_type: input.asset_type,
      title: input.title ?? null,
      external_url: input.external_url,
      sync_status: "synced",
      revision: 1,
      created_at: now,
      updated_at: now,
    };
    this.assets.unshift(asset);
    return asset;
  }

  async captureParse(input: CaptureParseInput): Promise<LocalCaptureSession> {
    const captureId = this.nextId("capture", ++this.captureSeq);
    const action: LocalCaptureAction = {
      type: "memo_create",
      payload: {
        type: "memo",
        title: null,
        content_markdown: input.text,
        tags: ["capture"],
      },
      confidence: 0.8,
    };
    const session: LocalCaptureSession = {
      capture_id: captureId,
      actions: [action],
      requires_confirmation: false,
    };
    this.captures.set(captureId, session);
    return session;
  }

  async captureCommit(input: CaptureCommitInput, context: LocalCoreContext): Promise<LocalCaptureCommitResult> {
    const session = this.captures.get(input.capture_id);
    if (!session) throw new Error(`Capture not found: ${input.capture_id}`);

    const indexes = input.selected_action_indexes ?? session.actions.map((_, index) => index);
    const created: LocalCoreEntityRef[] = [];

    for (const index of indexes) {
      const action = session.actions[index];
      if (!action) continue;
      if (action.type === "memo_create") {
        const memo = await this.createMemo(action.payload as unknown as MemoCreateInput, context);
        created.push({ type: "memo", id: memo.id });
      }
    }

    const undoToken = this.nextId("undo", ++this.undoSeq);
    this.undoEntries.set(undoToken, created);
    this.captures.delete(input.capture_id);
    return { committed: true, created_entities: created, undo_token: undoToken };
  }

  async captureUndo(input: CaptureUndoInput, context: LocalCoreContext): Promise<LocalCaptureUndoResult> {
    const entries = this.undoEntries.get(input.undo_token);
    if (!entries) throw new Error(`Undo token not found: ${input.undo_token}`);
    const now = this.now(context);
    let undone = 0;
    const failed: LocalCoreEntityRef[] = [];

    for (const entry of entries) {
      if (entry.type === "memo") {
        const memo = this.memos.find((item) => item.id === entry.id);
        if (memo) {
          memo.status = "ai_trashed";
          memo.updated_at = now;
          memo.revision += 1;
          undone += 1;
        } else {
          failed.push(entry);
        }
      } else {
        failed.push(entry);
      }
    }

    this.undoEntries.delete(input.undo_token);
    return { undone, failed_entities: failed };
  }

  private nextId(prefix: string, seq: number): string {
    return `local_${prefix}_${seq.toString().padStart(4, "0")}`;
  }

  private now(context: LocalCoreContext): string {
    return (context.now ?? new Date()).toISOString();
  }
}
