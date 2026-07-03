import { describe, expect, it } from "vitest";

import {
  LiflyMcpToolDescriptions,
  LiflyMcpToolInputSchemas,
  LiflyMcpToolNameSchema,
  parseLiflyMcpToolOutput,
} from "../../../packages/protocol/src/index.js";
import { callLocalMcpTool, createTestLocalMcpRuntime, listLocalMcpTools } from "../src/index.js";

const VALID_INPUTS = {
  capture_parse: { text: "在食堂花了18元，提醒我晚上复盘，记一下状态不错 https://example.com/lifly" },
  capture_commit: { capture_id: "placeholder" },
  capture_undo: { undo_token: "placeholder" },
  memo_create: { type: "memo", content_markdown: "parity memo", tags: ["parity"] },
  memo_search: { q: "parity", limit: 20 },
  expense_create: { amount: 18, merchant: "食堂", direction: "expense", currency: "CNY" },
  expense_search: { q: "食堂", limit: 20 },
  expense_summary: { period: "current_month" },
  task_create: { title: "parity task", priority: "normal" },
  task_list: { task_status: "todo", limit: 20 },
  task_complete: { task_id: "placeholder" },
  asset_create_upload_url: { filename: "demo.txt", asset_type: "file" },
  asset_register_external_url: { external_url: "https://example.com/lifly", asset_type: "link" },
} as const;

describe("Local MCP parity", () => {
  it("exposes the exact protocol tool list and descriptions", () => {
    expect(listLocalMcpTools()).toEqual(
      LiflyMcpToolNameSchema.options.map((name) => ({
        name,
        description: LiflyMcpToolDescriptions[name],
      })),
    );
  });

  it("has valid sample input for every protocol tool", () => {
    expect(Object.keys(VALID_INPUTS)).toEqual(LiflyMcpToolNameSchema.options);
    for (const name of LiflyMcpToolNameSchema.options) {
      expect(LiflyMcpToolInputSchemas[name].parse(VALID_INPUTS[name])).toBeTruthy();
    }
  });

  it("returns protocol-valid output for every executable local tool", async () => {
    const runtime = createTestLocalMcpRuntime();

    const memo = await callLocalMcpTool(runtime, "memo_create", VALID_INPUTS.memo_create);
    expect(parseLiflyMcpToolOutput("memo_create", memo)).toBeTruthy();
    expect(parseLiflyMcpToolOutput("memo_search", await callLocalMcpTool(runtime, "memo_search", VALID_INPUTS.memo_search))).toBeTruthy();

    const expense = await callLocalMcpTool(runtime, "expense_create", VALID_INPUTS.expense_create);
    expect(parseLiflyMcpToolOutput("expense_create", expense)).toBeTruthy();
    expect(parseLiflyMcpToolOutput("expense_search", await callLocalMcpTool(runtime, "expense_search", VALID_INPUTS.expense_search))).toBeTruthy();
    expect(parseLiflyMcpToolOutput("expense_summary", await callLocalMcpTool(runtime, "expense_summary", VALID_INPUTS.expense_summary))).toBeTruthy();

    const taskOutput = parseLiflyMcpToolOutput("task_create", await callLocalMcpTool(runtime, "task_create", VALID_INPUTS.task_create));
    expect(parseLiflyMcpToolOutput("task_list", await callLocalMcpTool(runtime, "task_list", VALID_INPUTS.task_list))).toBeTruthy();
    expect(parseLiflyMcpToolOutput("task_complete", await callLocalMcpTool(runtime, "task_complete", { task_id: taskOutput.task.id }))).toBeTruthy();

    const upload = await callLocalMcpTool(runtime, "asset_create_upload_url", VALID_INPUTS.asset_create_upload_url);
    expect(upload).toMatchObject({ unsupported: true });
    expect(parseLiflyMcpToolOutput("asset_register_external_url", await callLocalMcpTool(runtime, "asset_register_external_url", VALID_INPUTS.asset_register_external_url))).toBeTruthy();

    const parsed = parseLiflyMcpToolOutput("capture_parse", await callLocalMcpTool(runtime, "capture_parse", VALID_INPUTS.capture_parse));
    const committed = parseLiflyMcpToolOutput("capture_commit", await callLocalMcpTool(runtime, "capture_commit", {
      capture_id: parsed.capture_id,
      selected_action_indexes: [0, 1],
    }));
    expect(committed.failed_actions).toEqual([]);
    expect(parseLiflyMcpToolOutput("capture_undo", await callLocalMcpTool(runtime, "capture_undo", { undo_token: committed.undo_token }))).toBeTruthy();
  });
});
