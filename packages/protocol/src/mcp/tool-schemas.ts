import { z } from "zod";

/**
 * Lifly MCP Tool Schema v0.1
 *
 * This package defines the shared contract for Cloud MCP and Local MCP.
 * Runtime services may be implemented in Python or TypeScript during M0/M1,
 * but tool names and input/output contracts must stay aligned with this file.
 */

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
  amount: z.number().finite().nonnegative(),
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

export const AssetTypeSchema = z.enum([
  "image",
  "file",
  "pdf",
  "slide",
  "mindmap",
  "link",
  "audio",
  "video",
]);

export const AssetCreateUploadUrlInputSchema = z.object({
  filename: z.string().min(1),
  mime_type: z.string().min(1).optional().nullable(),
  size_bytes: z.number().int().nonnegative().optional().nullable(),
  asset_type: AssetTypeSchema.default("file"),
});

export const AssetRegisterExternalUrlInputSchema = z.object({
  external_url: z.string().url(),
  title: z.string().min(1).optional().nullable(),
  asset_type: AssetTypeSchema.default("link"),
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

export function getLiflyMcpToolInputSchema(name: LiflyMcpToolName): z.ZodTypeAny {
  return LiflyMcpToolInputSchemas[name];
}

export function parseLiflyMcpToolInput<TName extends LiflyMcpToolName>(
  name: TName,
  input: unknown,
): LiflyMcpToolInputMap[TName] {
  return LiflyMcpToolInputSchemas[name].parse(input) as LiflyMcpToolInputMap[TName];
}
