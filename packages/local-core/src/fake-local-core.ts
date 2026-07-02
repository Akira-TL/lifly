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
  LocalCaptureFailedAction,
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
  private readonly committedCaptures = new Set<string>();
  private readonly undoEntries = new Map<string, LocalCoreEntityRef[]>();
  private readonly usedUndoTokens = new Set<string>();

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
      status: "active",
      revision: 1,
      created_at: now,
      updated_at: now,
    };
    this.assets.unshift(asset);
    return asset;
  }

  async captureParse(input: CaptureParseInput): Promise<LocalCaptureSession> {
    const captureId = this.nextId("capture", ++this.captureSeq);
    const actions = this.parseActions(input);
    const session: LocalCaptureSession = {
      capture_id: captureId,
      actions,
      requires_confirmation: actions.length === 1 && actions[0]?.confidence === 0.4,
    };
    this.captures.set(captureId, session);
    return session;
  }

  async captureCommit(input: CaptureCommitInput, context: LocalCoreContext): Promise<LocalCaptureCommitResult> {
    if (this.committedCaptures.has(input.capture_id)) {
      throw new Error(`Capture already committed: ${input.capture_id}`);
    }

    const session = this.captures.get(input.capture_id);
    if (!session) throw new Error(`Capture not found: ${input.capture_id}`);

    const indexes = input.selected_action_indexes ?? session.actions.map((_, index) => index);
    const created: LocalCoreEntityRef[] = [];
    const failed: LocalCaptureFailedAction[] = [];
    const seen = new Set<number>();

    for (const index of indexes) {
      if (seen.has(index)) {
        failed.push({ action_index: index, action_type: null, reason: "duplicate_action_index" });
        continue;
      }
      seen.add(index);

      const action = session.actions[index];
      if (!action) {
        failed.push({ action_index: index, action_type: null, reason: "action_index_out_of_range" });
        continue;
      }

      try {
        const ref = await this.commitAction(action, context);
        created.push(ref);
      } catch (error) {
        failed.push({
          action_index: index,
          action_type: action.type,
          reason: "validation_error",
          detail: error instanceof Error ? error.message : String(error),
        });
      }
    }

    const undoToken = this.nextId("undo", ++this.undoSeq);
    this.undoEntries.set(undoToken, created);
    this.committedCaptures.add(input.capture_id);
    this.captures.delete(input.capture_id);
    return {
      committed: created.length > 0,
      created_entities: created,
      failed_actions: failed,
      undo_token: undoToken,
    };
  }

  async captureUndo(input: CaptureUndoInput, context: LocalCoreContext): Promise<LocalCaptureUndoResult> {
    if (this.usedUndoTokens.has(input.undo_token)) {
      return { undone: 0, entities: [], failed_entities: [] };
    }

    const entries = this.undoEntries.get(input.undo_token);
    if (!entries) throw new Error(`Undo token not found: ${input.undo_token}`);
    const now = this.now(context);
    const undoneEntities: LocalCoreEntityRef[] = [];
    const failed: LocalCoreEntityRef[] = [];

    for (const entry of entries) {
      const entity = this.findEntity(entry);
      if (entity) {
        entity.status = "ai_trashed";
        entity.updated_at = now;
        entity.revision += 1;
        undoneEntities.push(entry);
      } else {
        failed.push(entry);
      }
    }

    this.usedUndoTokens.add(input.undo_token);
    this.undoEntries.delete(input.undo_token);
    return { undone: undoneEntities.length, entities: undoneEntities, failed_entities: failed };
  }

  private parseActions(input: CaptureParseInput): LocalCaptureAction[] {
    const text = input.text.trim();
    const actions: LocalCaptureAction[] = [];
    const amountMatch = text.match(/(?:花了?|消费|支出)\s*(\d+(?:\.\d{1,2})?)|(\d+(?:\.\d{1,2})?)\s*[元块]/);

    if (amountMatch) {
      const amount = Number(amountMatch[1] ?? amountMatch[2]);
      actions.push({
        type: "expense_create",
        payload: {
          amount,
          merchant: this.inferMerchant(text),
          direction: "expense",
          currency: "CNY",
          note: text,
          category_hint: this.inferCategory(text),
        },
        confidence: 0.85,
      });
    }

    const taskMatch = text.match(/(?:提醒我?|记得|别忘了|要做)\s*(.{2,40})/);
    if (taskMatch) {
      actions.push({
        type: "task_create",
        payload: {
          title: taskMatch[1]?.trim() ?? text,
          priority: "normal",
        },
        confidence: 0.8,
      });
    }

    const urlMatch = text.match(/https?:\/\/\S+/);
    if (urlMatch) {
      actions.push({
        type: "asset_register_external_url",
        payload: {
          external_url: urlMatch[0],
          asset_type: "link",
          title: null,
        },
        confidence: 0.75,
      });
    }

    if (text.includes("记一下") || text.includes("备忘") || text.includes("日记")) {
      actions.push({
        type: "memo_create",
        payload: {
          type: "memo",
          title: null,
          content_markdown: text.replace(/^(记一下|备忘|日记)\s*/, ""),
          tags: ["capture"],
        },
        confidence: 0.78,
      });
    }

    if (actions.length === 0) {
      actions.push({
        type: "memo_create",
        payload: {
          type: "memo",
          title: null,
          content_markdown: text,
          tags: ["capture"],
        },
        confidence: 0.4,
      });
    }

    return actions;
  }

  private async commitAction(action: LocalCaptureAction, context: LocalCoreContext): Promise<LocalCoreEntityRef> {
    if (action.type === "memo_create") {
      const memo = await this.createMemo(action.payload as unknown as MemoCreateInput, context);
      return { type: "memo", id: memo.id };
    }
    if (action.type === "expense_create") {
      const tx = await this.createExpense(action.payload as unknown as ExpenseCreateInput, context);
      return { type: "ledger_transaction", id: tx.id };
    }
    if (action.type === "task_create") {
      const task = await this.createTask(action.payload as unknown as TaskCreateInput, context);
      return { type: "task", id: task.id };
    }
    if (action.type === "asset_register_external_url") {
      const asset = await this.registerExternalAsset(action.payload as unknown as AssetRegisterExternalUrlInput, context);
      return { type: "asset", id: asset.id };
    }
    throw new Error(`Unsupported capture action: ${String(action.type)}`);
  }

  private findEntity(ref: LocalCoreEntityRef): LocalMemo | LocalLedgerTransaction | LocalTask | LocalAsset | null {
    if (ref.type === "memo") return this.memos.find((item) => item.id === ref.id) ?? null;
    if (ref.type === "ledger_transaction") return this.expenses.find((item) => item.id === ref.id) ?? null;
    if (ref.type === "task") return this.tasks.find((item) => item.id === ref.id) ?? null;
    if (ref.type === "asset") return this.assets.find((item) => item.id === ref.id) ?? null;
    return null;
  }

  private inferMerchant(text: string): string {
    const match = text.match(/(?:在|去|到)\s*(.{1,20}?)\s*(?:花了?|消费|吃饭|用餐|买了|购物)/);
    return match?.[1]?.trim() || "未知商户";
  }

  private inferCategory(text: string): string {
    if (/食堂|餐厅|饭|外卖/.test(text)) return "餐饮";
    if (/超市|买了|购物/.test(text)) return "购物";
    if (/公交|地铁|打车|滴滴/.test(text)) return "交通";
    return "未分类";
  }

  private nextId(prefix: string, seq: number): string {
    return `local_${prefix}_${seq.toString().padStart(4, "0")}`;
  }

  private now(context: LocalCoreContext): string {
    return (context.now ?? new Date()).toISOString();
  }
}
