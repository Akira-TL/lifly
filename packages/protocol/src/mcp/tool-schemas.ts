import { z } from "zod";

/**
 * Lifly MCP Tool Schema
 *
 * packages/protocol is the source of truth for Cloud MCP, Local MCP,
 * Flutter AI Capture, and contract tests. Runtime services may be
 * implemented in Python, TypeScript, or Dart, but tool names and
 * input/output contracts must stay aligned with this file.
 */

export const LiflyMcpToolContractVersion = "0.4.1" as const;

export const LiflyMcpToolNameSchema = z.enum([
  "capture_parse",
  "capture_commit",
  "capture_undo",
  "memo_create",
  "memo_search",
  "expense_create",
  "expense_search",
  "expense_summary",
  "task_create",
  "task_list",
  "task_complete",
  "asset_create_upload_url",
  "asset_register_external_url",
]);

export type LiflyMcpToolName = z.infer<typeof LiflyMcpToolNameSchema>;

const IsoDateTimeStringSchema = z.string().min(1).describe("ISO-8601 datetime string");
const NullableStringSchema = z.string().nullable().optional();
const EntityStatusSchema = z.enum(["active", "ai_trashed", "user_trashed"]);
const RevisionSchema = z.number().int().positive().optional();
const DateFieldsSchema = {
  created_at: IsoDateTimeStringSchema.nullable().optional(),
  updated_at: IsoDateTimeStringSchema.nullable().optional(),
} as const;

export const CaptureParseInputSchema = z.object({
  text: z.string().min(1),
  timezone: z.string().default("Asia/Shanghai"),
  locale: z.string().default("zh-CN"),
});

export const CaptureCommitInputSchema = z.object({
  capture_id: z.string().min(1),
  selected_action_indexes: z.array(z.number().int().nonnegative()).optional().nullable(),
});

export const CaptureUndoInputSchema = z.object({
  undo_token: z.string().min(1),
});

export const MemoTypeSchema = z.enum(["memo", "journal", "clip", "doc"]);

export const MemoCreateInputSchema = z.object({
  content_markdown: z.string().default(""),
  title: z.string().min(1).optional().nullable(),
  type: MemoTypeSchema.default("memo"),
  tags: z.array(z.string().min(1)).optional().nullable(),
});

export const MemoSearchInputSchema = z.object({
  q: z.string().default(""),
  limit: z.number().int().positive().max(100).default(20),
});

export const ExpenseDirectionSchema = z.enum(["expense", "income", "transfer"]);

export const ExpenseCreateInputSchema = z.object({
  amount: z.number().finite().positive(),
  merchant: z.string().min(1),
  direction: ExpenseDirectionSchema.default("expense"),
  currency: z.string().min(3).max(8).default("CNY"),
  category_hint: z.string().min(1).optional().nullable(),
  note: z.string().optional().nullable(),
  occurred_at: IsoDateTimeStringSchema.optional().nullable(),
});

export const ExpenseSearchInputSchema = z.object({
  q: z.string().default(""),
  limit: z.number().int().positive().max(100).default(20),
});

export const ExpenseSummaryInputSchema = z.object({
  period: z.enum(["current_month", "last_month", "current_week", "custom"]).default("current_month"),
  start_at: IsoDateTimeStringSchema.optional().nullable(),
  end_at: IsoDateTimeStringSchema.optional().nullable(),
});

export const TaskCreateInputSchema = z.object({
  title: z.string().min(1),
  remind_at: IsoDateTimeStringSchema.optional().nullable(),
  description: z.string().optional().nullable(),
  due_at: IsoDateTimeStringSchema.optional().nullable(),
  priority: z.enum(["low", "normal", "high", "urgent"]).default("normal"),
});

export const TaskListInputSchema = z.object({
  task_status: z.enum(["todo", "doing", "done", "cancelled"]).optional().nullable(),
  limit: z.number().int().positive().max(100).default(20),
});

export const TaskCompleteInputSchema = z.object({
  task_id: z.string().min(1),
});

export const InternalAssetTypeSchema = z.enum([
  "image",
  "pdf",
  "ppt",
  "mindmap",
  "file",
  "audio",
  "video",
]);

export const ExternalAssetTypeSchema = z.enum([
  "image",
  "pdf",
  "ppt",
  "mindmap",
  "file",
  "audio",
  "video",
  "link",
  "embed",
]);

export const AssetTypeSchema = z.union([InternalAssetTypeSchema, z.enum(["link", "embed"])]);

export const AssetCreateUploadUrlInputSchema = z.object({
  filename: z.string().min(1),
  mime_type: z.string().min(1).optional().nullable(),
  size_bytes: z.number().int().nonnegative().optional().nullable(),
  asset_type: InternalAssetTypeSchema.default("file"),
});

export const AssetRegisterExternalUrlInputSchema = z.object({
  external_url: z.string().url(),
  title: z.string().min(1).optional().nullable(),
  asset_type: ExternalAssetTypeSchema.default("link"),
});

export const LiflyMcpToolInputSchemas = {
  capture_parse: CaptureParseInputSchema,
  capture_commit: CaptureCommitInputSchema,
  capture_undo: CaptureUndoInputSchema,
  memo_create: MemoCreateInputSchema,
  memo_search: MemoSearchInputSchema,
  expense_create: ExpenseCreateInputSchema,
  expense_search: ExpenseSearchInputSchema,
  expense_summary: ExpenseSummaryInputSchema,
  task_create: TaskCreateInputSchema,
  task_list: TaskListInputSchema,
  task_complete: TaskCompleteInputSchema,
  asset_create_upload_url: AssetCreateUploadUrlInputSchema,
  asset_register_external_url: AssetRegisterExternalUrlInputSchema,
} as const satisfies Record<LiflyMcpToolName, z.ZodTypeAny>;

export type LiflyMcpToolInputMap = {
  [K in keyof typeof LiflyMcpToolInputSchemas]: z.infer<(typeof LiflyMcpToolInputSchemas)[K]>;
};

export const LiflyMcpEntityRefSchema = z.object({
  type: z.enum(["memo", "ledger_transaction", "task", "asset"]),
  id: z.string().min(1),
});

export const LiflyMcpMemoSchema = z.object({
  id: z.string().min(1),
  user_id: z.string().min(1).optional(),
  type: MemoTypeSchema,
  title: NullableStringSchema,
  content_markdown: z.string(),
  tags: z.array(z.string()).nullable().optional(),
  status: EntityStatusSchema,
  revision: RevisionSchema,
  ...DateFieldsSchema,
}).passthrough();

export const LiflyMcpLedgerTransactionSchema = z.object({
  id: z.string().min(1),
  user_id: z.string().min(1).optional(),
  direction: ExpenseDirectionSchema,
  amount: z.number().finite(),
  currency: z.string().min(1),
  merchant: NullableStringSchema,
  note: NullableStringSchema,
  category_hint: NullableStringSchema,
  category_id: NullableStringSchema,
  account_id: NullableStringSchema,
  occurred_at: IsoDateTimeStringSchema,
  status: EntityStatusSchema,
  revision: RevisionSchema,
  ...DateFieldsSchema,
}).passthrough();

export const LiflyMcpExpenseSummarySchema = z.object({
  period: z.string().min(1),
  total_expense: z.number().finite(),
  total_income: z.number().finite().optional(),
  count: z.number().int().nonnegative(),
}).passthrough();

export const LiflyMcpTaskSchema = z.object({
  id: z.string().min(1),
  user_id: z.string().min(1).optional(),
  title: z.string().min(1),
  description: NullableStringSchema,
  due_at: IsoDateTimeStringSchema.nullable().optional(),
  remind_at: IsoDateTimeStringSchema.nullable().optional(),
  priority: z.enum(["low", "normal", "high", "urgent"]),
  task_status: z.enum(["todo", "doing", "done", "cancelled"]),
  completed_at: IsoDateTimeStringSchema.nullable().optional(),
  status: EntityStatusSchema,
  revision: RevisionSchema,
  ...DateFieldsSchema,
}).passthrough();

export const LiflyMcpAssetSchema = z.object({
  id: z.string().min(1),
  kind: z.enum(["external", "internal", "internal_intent"]),
  asset_type: z.string().min(1),
  title: NullableStringSchema,
  external_url: z.string().url().nullable().optional(),
  storage_key: z.string().min(1).nullable().optional(),
  sync_status: z.enum(["synced", "pending", "unsupported"]),
  revision: RevisionSchema,
  ...DateFieldsSchema,
}).passthrough();

export const LiflyMcpCaptureActionSchema = z.object({
  type: z.enum(["memo_create", "expense_create", "task_create", "asset_register_external_url"]),
  payload: z.record(z.unknown()),
  confidence: z.number().min(0).max(1),
});

export const LiflyMcpToolOutputSchemas = {
  capture_parse: z.object({
    capture_id: z.string().min(1),
    actions: z.array(LiflyMcpCaptureActionSchema),
    requires_confirmation: z.boolean(),
  }).passthrough(),
  capture_commit: z.object({
    committed: z.boolean(),
    created_entities: z.array(LiflyMcpEntityRefSchema),
    failed_actions: z.array(z.object({
      action_index: z.number().int().nonnegative(),
      action_type: z.string().nullable(),
      reason: z.string().min(1),
      detail: z.unknown().optional(),
    }).passthrough()).default([]),
    undo_token: z.string().min(1),
  }).passthrough(),
  capture_undo: z.object({
    undone: z.number().int().nonnegative(),
    entities: z.array(LiflyMcpEntityRefSchema).optional(),
    failed_entities: z.array(LiflyMcpEntityRefSchema.passthrough()),
  }).passthrough(),
  memo_create: z.object({
    memo_id: z.string().min(1),
    memo: LiflyMcpMemoSchema,
    undo_token: z.string().min(1).nullable().optional(),
    status: EntityStatusSchema.optional(),
  }).passthrough(),
  memo_search: z.object({
    memos: z.array(LiflyMcpMemoSchema),
  }).passthrough(),
  expense_create: z.object({
    transaction: LiflyMcpLedgerTransactionSchema,
    undo_token: z.string().min(1).nullable().optional(),
  }).passthrough(),
  expense_search: z.object({
    transactions: z.array(LiflyMcpLedgerTransactionSchema),
  }).passthrough(),
  expense_summary: LiflyMcpExpenseSummarySchema,
  task_create: z.object({
    task: LiflyMcpTaskSchema,
    undo_token: z.string().min(1).nullable().optional(),
  }).passthrough(),
  task_list: z.object({
    tasks: z.array(LiflyMcpTaskSchema),
  }).passthrough(),
  task_complete: z.object({
    task: LiflyMcpTaskSchema,
  }).passthrough(),
  asset_create_upload_url: z.union([
    z.object({
      asset_id: z.string().min(1),
      storage_key: z.string().min(1),
      upload_url: z.string().min(1),
      asset: LiflyMcpAssetSchema,
      undo_token: z.string().min(1).nullable().optional(),
    }).passthrough(),
    z.object({
      unsupported: z.literal(true),
      reason: z.string().min(1),
    }).passthrough(),
  ]),
  asset_register_external_url: z.object({
    asset: LiflyMcpAssetSchema,
    undo_token: z.string().min(1).nullable().optional(),
  }).passthrough(),
} as const satisfies Record<LiflyMcpToolName, z.ZodTypeAny>;

export type LiflyMcpToolOutputMap = {
  [K in keyof typeof LiflyMcpToolOutputSchemas]: z.infer<(typeof LiflyMcpToolOutputSchemas)[K]>;
};

export const LiflyMcpToolDescriptions: Record<LiflyMcpToolName, string> = {
  capture_parse: "Parse natural language into candidate memo, expense, and task actions without committing them.",
  capture_commit: "Commit selected actions from a capture session and return an undo token.",
  capture_undo: "Undo a capture commit by moving created entities into AI trash.",
  memo_create: "Create a markdown memo, journal entry, clip, or document.",
  memo_search: "Search active memos by title and markdown content.",
  expense_create: "Create an expense, income, or transfer transaction.",
  expense_search: "Search active ledger transactions by merchant or note.",
  expense_summary: "Summarize ledger transactions for a supported period.",
  task_create: "Create a task or reminder.",
  task_list: "List active tasks, optionally filtered by task status.",
  task_complete: "Mark a task as completed.",
  asset_create_upload_url: "Create internal asset metadata and return a pre-signed upload URL.",
  asset_register_external_url: "Register an external URL as an asset reference.",
};

export const LiflyMcpToolSchemas = Object.entries(LiflyMcpToolInputSchemas).map(
  ([name, inputSchema]) => ({
    name: name as LiflyMcpToolName,
    description: LiflyMcpToolDescriptions[name as LiflyMcpToolName],
    inputSchema,
  }),
);

export const LiflyMcpToolContracts = LiflyMcpToolNameSchema.options.map((name) => ({
  name,
  version: LiflyMcpToolContractVersion,
  description: LiflyMcpToolDescriptions[name],
  inputSchema: LiflyMcpToolInputSchemas[name],
  outputSchema: LiflyMcpToolOutputSchemas[name],
}));

export function getLiflyMcpToolInputSchema(name: LiflyMcpToolName): z.ZodTypeAny {
  return LiflyMcpToolInputSchemas[name];
}

export function getLiflyMcpToolOutputSchema(name: LiflyMcpToolName): z.ZodTypeAny {
  return LiflyMcpToolOutputSchemas[name];
}

export function parseLiflyMcpToolInput<TName extends LiflyMcpToolName>(
  name: TName,
  input: unknown,
): LiflyMcpToolInputMap[TName] {
  return LiflyMcpToolInputSchemas[name].parse(input) as LiflyMcpToolInputMap[TName];
}

export function parseLiflyMcpToolOutput<TName extends LiflyMcpToolName>(
  name: TName,
  output: unknown,
): LiflyMcpToolOutputMap[TName] {
  return LiflyMcpToolOutputSchemas[name].parse(output) as LiflyMcpToolOutputMap[TName];
}
