import {
  DesktopLocalCoreBridge,
  FakeLocalCoreBridge,
  localMcpContext,
  type LocalCoreBridge,
} from "../../../packages/local-core/src/index.js";
import type {
  AssetRegisterExternalUrlInput,
  CaptureCommitInput,
  CaptureParseInput,
  CaptureUndoInput,
  ExpenseCreateInput,
  ExpenseSearchInput,
  ExpenseSummaryInput,
  MemoCreateInput,
  MemoSearchInput,
  TaskCompleteInput,
  TaskCreateInput,
  TaskListInput,
} from "../../../packages/local-core/src/index.js";
import {
  LiflyMcpToolDescriptions,
  LiflyMcpToolInputSchemas,
  LiflyMcpToolNameSchema,
  type LiflyMcpToolName,
} from "../../../packages/protocol/src/index.js";
import type { LocalMcpToolDefinition } from "./types.js";

export type LocalMcpBridgeMode = "desktop" | "fake";

export interface LocalMcpRuntime {
  core: LocalCoreBridge;
  bridgeMode: LocalMcpBridgeMode;
}

export function createDesktopLocalMcpRuntime(): LocalMcpRuntime {
  return { core: new DesktopLocalCoreBridge(), bridgeMode: "desktop" };
}

export function createTestLocalMcpRuntime(): LocalMcpRuntime {
  return { core: new FakeLocalCoreBridge(), bridgeMode: "fake" };
}

export function createDefaultLocalMcpRuntime(): LocalMcpRuntime {
  return createDesktopLocalMcpRuntime();
}

export function listLocalMcpTools(): LocalMcpToolDefinition[] {
  return LiflyMcpToolNameSchema.options.map((name) => ({
    name,
    description: LiflyMcpToolDescriptions[name],
  }));
}

export async function callLocalMcpTool(
  runtime: LocalMcpRuntime,
  name: LiflyMcpToolName,
  rawInput: unknown,
): Promise<unknown> {
  const context = localMcpContext(name);

  switch (name) {
    case "memo_create": {
      const input = LiflyMcpToolInputSchemas.memo_create.parse(rawInput ?? {}) as MemoCreateInput;
      const memo = await runtime.core.createMemo(input, context);
      return { memo_id: memo.id, memo };
    }
    case "memo_search": {
      const input = LiflyMcpToolInputSchemas.memo_search.parse(rawInput ?? {}) as MemoSearchInput;
      const memos = await runtime.core.searchMemos(input, context);
      return { memos };
    }
    case "expense_create": {
      const input = LiflyMcpToolInputSchemas.expense_create.parse(rawInput ?? {}) as ExpenseCreateInput;
      const transaction = await runtime.core.createExpense(input, context);
      return { transaction };
    }
    case "expense_search": {
      const input = LiflyMcpToolInputSchemas.expense_search.parse(rawInput ?? {}) as ExpenseSearchInput;
      const transactions = await runtime.core.searchExpenses(input, context);
      return { transactions };
    }
    case "expense_summary": {
      const input = LiflyMcpToolInputSchemas.expense_summary.parse(rawInput ?? {}) as ExpenseSummaryInput;
      return runtime.core.summarizeExpenses(input, context);
    }
    case "task_create": {
      const input = LiflyMcpToolInputSchemas.task_create.parse(rawInput ?? {}) as TaskCreateInput;
      const task = await runtime.core.createTask(input, context);
      return { task };
    }
    case "task_list": {
      const input = LiflyMcpToolInputSchemas.task_list.parse(rawInput ?? {}) as TaskListInput;
      const tasks = await runtime.core.listTasks(input, context);
      return { tasks };
    }
    case "task_complete": {
      const input = LiflyMcpToolInputSchemas.task_complete.parse(rawInput ?? {}) as TaskCompleteInput;
      const task = await runtime.core.completeTask(input, context);
      return { task };
    }
    case "asset_register_external_url": {
      const input = LiflyMcpToolInputSchemas.asset_register_external_url.parse(rawInput ?? {}) as AssetRegisterExternalUrlInput;
      const asset = await runtime.core.registerExternalAsset(input, context);
      return { asset };
    }
    case "capture_parse": {
      const input = LiflyMcpToolInputSchemas.capture_parse.parse(rawInput ?? {}) as CaptureParseInput;
      return runtime.core.captureParse(input, context);
    }
    case "capture_commit": {
      const input = LiflyMcpToolInputSchemas.capture_commit.parse(rawInput ?? {}) as CaptureCommitInput;
      return runtime.core.captureCommit(input, context);
    }
    case "capture_undo": {
      const input = LiflyMcpToolInputSchemas.capture_undo.parse(rawInput ?? {}) as CaptureUndoInput;
      return runtime.core.captureUndo(input, context);
    }
    case "asset_create_upload_url": {
      LiflyMcpToolInputSchemas.asset_create_upload_url.parse(rawInput ?? {});
      return {
        unsupported: true,
        reason: "Local MCP desktop mode does not create cloud upload URLs.",
      };
    }
  }
}
