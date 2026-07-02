export type LocalCoreActorType = "user" | "ai" | "system";
export type LocalCoreSourceChannel = "flutter" | "local_mcp" | "cloud_mcp" | "import" | "system";

export interface LocalCoreContext {
  actorType: LocalCoreActorType;
  sourceChannel: LocalCoreSourceChannel;
  toolName?: string;
  requestId?: string;
  now?: Date;
}

export interface LocalCoreHealth {
  status: "ok" | "unavailable";
  mode: "fake" | "desktop_bridge" | "powersync";
  version: string;
  runtime?: "test" | "desktop";
  detail?: string;
}

export interface LocalCoreEntityRef {
  type: "memo" | "ledger_transaction" | "task" | "asset";
  id: string;
}

export type MemoType = "memo" | "journal" | "clip" | "doc";
export type ExpenseDirection = "expense" | "income" | "transfer";
export type TaskPriority = "low" | "normal" | "high" | "urgent";
export type TaskStatus = "todo" | "doing" | "done" | "cancelled";

export interface LocalMemo {
  id: string;
  type: MemoType;
  title: string | null;
  content_markdown: string;
  tags: string[];
  status: "active" | "ai_trashed" | "user_trashed";
  revision: number;
  created_at: string;
  updated_at: string;
}

export interface LocalLedgerTransaction {
  id: string;
  direction: ExpenseDirection;
  amount: number;
  currency: string;
  merchant: string | null;
  note: string | null;
  category_hint: string | null;
  occurred_at: string;
  status: "active" | "ai_trashed" | "user_trashed";
  revision: number;
  created_at: string;
  updated_at: string;
}

export interface LocalTask {
  id: string;
  title: string;
  description: string | null;
  due_at: string | null;
  remind_at: string | null;
  priority: TaskPriority;
  task_status: TaskStatus;
  completed_at: string | null;
  status: "active" | "ai_trashed" | "user_trashed";
  revision: number;
  created_at: string;
  updated_at: string;
}

export interface LocalAsset {
  id: string;
  kind: "external" | "internal_intent";
  asset_type: string;
  title: string | null;
  external_url: string | null;
  sync_status: "synced" | "pending" | "unsupported";
  status: "active" | "ai_trashed" | "user_trashed";
  revision: number;
  created_at: string;
  updated_at: string;
}

export interface LocalCaptureAction {
  type: "memo_create" | "expense_create" | "task_create" | "asset_register_external_url";
  payload: Record<string, unknown>;
  confidence: number;
}

export interface LocalCaptureSession {
  capture_id: string;
  actions: LocalCaptureAction[];
  requires_confirmation: boolean;
}

export interface LocalCaptureFailedAction {
  action_index: number;
  action_type: string | null;
  reason: string;
  detail?: unknown;
}

export interface LocalCaptureCommitResult {
  committed: boolean;
  created_entities: LocalCoreEntityRef[];
  failed_actions: LocalCaptureFailedAction[];
  undo_token: string;
}

export interface LocalCaptureUndoResult {
  undone: number;
  entities: LocalCoreEntityRef[];
  failed_entities: LocalCoreEntityRef[];
}

export interface LocalExpenseSummary {
  period: string;
  total_expense: number;
  total_income: number;
  count: number;
}

export interface MemoCreateInput {
  content_markdown: string;
  title?: string | null;
  type: MemoType;
  tags?: string[] | null;
}

export interface MemoSearchInput {
  q: string;
  limit: number;
}

export interface ExpenseCreateInput {
  amount: number;
  merchant: string;
  direction: ExpenseDirection;
  currency: string;
  category_hint?: string | null;
  note?: string | null;
  occurred_at?: string | null;
}

export interface ExpenseSearchInput {
  q: string;
  limit: number;
}

export interface ExpenseSummaryInput {
  period: "current_month" | "last_month" | "current_week" | "custom";
  start_at?: string | null;
  end_at?: string | null;
}

export interface TaskCreateInput {
  title: string;
  remind_at?: string | null;
  description?: string | null;
  due_at?: string | null;
  priority: TaskPriority;
}

export interface TaskListInput {
  task_status?: TaskStatus | null;
  limit: number;
}

export interface TaskCompleteInput {
  task_id: string;
}

export interface AssetRegisterExternalUrlInput {
  external_url: string;
  title?: string | null;
  asset_type: string;
}

export interface CaptureParseInput {
  text: string;
  timezone: string;
  locale: string;
}

export interface CaptureCommitInput {
  capture_id: string;
  selected_action_indexes?: number[] | null;
}

export interface CaptureUndoInput {
  undo_token: string;
}
