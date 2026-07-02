import { describe, expect, it } from "vitest";

import {
  LiflyMcpToolDescriptions,
  LiflyMcpToolNameSchema,
  parseLiflyMcpToolOutput,
} from "../../../packages/protocol/src/index.js";
import { createTestLocalMcpRuntime, LocalMcpServer } from "../src/index.js";

function createFakeServer(): LocalMcpServer {
  return new LocalMcpServer(createTestLocalMcpRuntime());
}

describe("LocalMcpServer", () => {
  it("reports desktop bridge health by default", async () => {
    const server = new LocalMcpServer();
    const response = await server.handle({ method: "health" });
    expect(response.ok).toBe(true);
    if (response.ok) {
      expect(response.result).toMatchObject({
        status: "unavailable",
        mode: "desktop_bridge",
        runtime: "desktop",
      });
    }
  });

  it("fails fast for desktop bridge tool calls when desktop host is not connected", async () => {
    const server = new LocalMcpServer();
    const response = await server.handle({
      method: "tools/call",
      params: {
        name: "memo_create",
        input: {
          type: "memo",
          content_markdown: "should not be written without desktop host",
        },
      },
    });

    expect(response.ok).toBe(false);
    if (!response.ok) {
      expect(response.error.message).toContain("desktop bridge is not connected");
      expect(response.error.message).toContain("must not write SQLite directly");
    }
  });

  it("reports fake health only when fake test runtime is explicit", async () => {
    const server = createFakeServer();
    const response = await server.handle({ method: "health" });
    expect(response.ok).toBe(true);
    if (response.ok) {
      expect(response.result).toMatchObject({ status: "ok", mode: "fake", runtime: "test" });
    }
  });

  it("lists protocol tools with aligned descriptions", async () => {
    const server = createFakeServer();
    const response = await server.handle({ method: "tools/list" });
    expect(response.ok).toBe(true);
    if (response.ok) {
      const result = response.result as { tools: Array<{ name: string; description: string }> };
      expect(result.tools.map((tool) => tool.name)).toEqual(LiflyMcpToolNameSchema.options);
      expect(result.tools).toEqual(
        LiflyMcpToolNameSchema.options.map((name) => ({
          name,
          description: LiflyMcpToolDescriptions[name],
        })),
      );
    }
  });

  it("calls memo_create and memo_search with protocol output contracts", async () => {
    const server = createFakeServer();
    const created = await server.handle({
      method: "tools/call",
      params: {
        name: "memo_create",
        input: {
          type: "memo",
          title: "Local MCP memo",
          content_markdown: "created by local mcp",
          tags: ["local"],
        },
      },
    });
    expect(created.ok).toBe(true);
    if (created.ok) {
      parseLiflyMcpToolOutput("memo_create", created.result);
    }

    const searched = await server.handle({
      method: "tools/call",
      params: {
        name: "memo_search",
        input: { q: "local mcp", limit: 20 },
      },
    });
    expect(searched.ok).toBe(true);
    if (searched.ok) {
      const result = parseLiflyMcpToolOutput("memo_search", searched.result);
      expect(result.memos.some((memo) => memo.title === "Local MCP memo")).toBe(true);
    }
  });

  it("calls expense tools with protocol output contracts", async () => {
    const server = createFakeServer();
    const created = await server.handle({
      method: "tools/call",
      params: {
        name: "expense_create",
        input: {
          amount: 18,
          merchant: "食堂",
          direction: "expense",
          currency: "CNY",
          note: "午饭",
        },
      },
    });
    expect(created.ok).toBe(true);
    if (created.ok) {
      parseLiflyMcpToolOutput("expense_create", created.result);
    }

    const searched = await server.handle({
      method: "tools/call",
      params: { name: "expense_search", input: { q: "食堂", limit: 20 } },
    });
    expect(searched.ok).toBe(true);
    if (searched.ok) {
      parseLiflyMcpToolOutput("expense_search", searched.result);
    }

    const summary = await server.handle({
      method: "tools/call",
      params: { name: "expense_summary", input: { period: "current_month" } },
    });
    expect(summary.ok).toBe(true);
    if (summary.ok) {
      parseLiflyMcpToolOutput("expense_summary", summary.result);
    }
  });

  it("calls task tools with protocol output contracts", async () => {
    const server = createFakeServer();
    const created = await server.handle({
      method: "tools/call",
      params: { name: "task_create", input: { title: "买猫粮", priority: "normal" } },
    });
    expect(created.ok).toBe(true);
    let taskId = "";
    if (created.ok) {
      const result = parseLiflyMcpToolOutput("task_create", created.result);
      taskId = result.task.id;
    }

    const listed = await server.handle({
      method: "tools/call",
      params: { name: "task_list", input: { task_status: "todo", limit: 20 } },
    });
    expect(listed.ok).toBe(true);
    if (listed.ok) {
      parseLiflyMcpToolOutput("task_list", listed.result);
    }

    const completed = await server.handle({
      method: "tools/call",
      params: { name: "task_complete", input: { task_id: taskId } },
    });
    expect(completed.ok).toBe(true);
    if (completed.ok) {
      parseLiflyMcpToolOutput("task_complete", completed.result);
    }
  });

  it("calls asset tools with protocol output contracts", async () => {
    const server = createFakeServer();
    const upload = await server.handle({
      method: "tools/call",
      params: { name: "asset_create_upload_url", input: { filename: "demo.txt", asset_type: "file" } },
    });
    expect(upload.ok).toBe(true);
    if (upload.ok) {
      parseLiflyMcpToolOutput("asset_create_upload_url", upload.result);
    }

    const external = await server.handle({
      method: "tools/call",
      params: {
        name: "asset_register_external_url",
        input: { external_url: "https://example.com/lifly", asset_type: "link" },
      },
    });
    expect(external.ok).toBe(true);
    if (external.ok) {
      parseLiflyMcpToolOutput("asset_register_external_url", external.result);
    }
  });

  it("calls capture tools with protocol output contracts", async () => {
    const server = createFakeServer();
    const parsed = await server.handle({
      method: "tools/call",
      params: { name: "capture_parse", input: { text: "记一下今天状态不错" } },
    });
    expect(parsed.ok).toBe(true);
    let captureId = "";
    if (parsed.ok) {
      const result = parseLiflyMcpToolOutput("capture_parse", parsed.result);
      expect(result.actions.map((action) => action.type)).toEqual(["memo_create"]);
      captureId = result.capture_id;
    }

    const committed = await server.handle({
      method: "tools/call",
      params: { name: "capture_commit", input: { capture_id: captureId } },
    });
    expect(committed.ok).toBe(true);
    let undoToken = "";
    if (committed.ok) {
      const result = parseLiflyMcpToolOutput("capture_commit", committed.result);
      expect(result.committed).toBe(true);
      expect(result.created_entities).toHaveLength(1);
      expect(result.failed_actions).toEqual([]);
      undoToken = result.undo_token;
    }

    const undone = await server.handle({
      method: "tools/call",
      params: { name: "capture_undo", input: { undo_token: undoToken } },
    });
    expect(undone.ok).toBe(true);
    if (undone.ok) {
      const result = parseLiflyMcpToolOutput("capture_undo", undone.result);
      expect(result.undone).toBe(1);
      expect(result.entities).toHaveLength(1);
    }
  });

  it("supports local capture partial commit, failed_actions, and idempotent undo", async () => {
    const server = createFakeServer();
    const parsed = await server.handle({
      method: "tools/call",
      params: {
        name: "capture_parse",
        input: { text: "在食堂花了18元，提醒我晚上复盘，记一下状态不错 https://example.com/lifly" },
      },
    });
    expect(parsed.ok).toBe(true);
    let captureId = "";
    if (parsed.ok) {
      const result = parseLiflyMcpToolOutput("capture_parse", parsed.result);
      expect(result.actions.map((action) => action.type)).toEqual([
        "expense_create",
        "task_create",
        "asset_register_external_url",
        "memo_create",
      ]);
      captureId = result.capture_id;
    }

    const committed = await server.handle({
      method: "tools/call",
      params: { name: "capture_commit", input: { capture_id: captureId, selected_action_indexes: [1, 3, 3, 9] } },
    });
    expect(committed.ok).toBe(true);
    let undoToken = "";
    if (committed.ok) {
      const result = parseLiflyMcpToolOutput("capture_commit", committed.result);
      expect(result.created_entities.map((entity) => entity.type)).toEqual(["task", "memo"]);
      expect(result.failed_actions.map((failure) => failure.reason)).toEqual([
        "duplicate_action_index",
        "action_index_out_of_range",
      ]);
      undoToken = result.undo_token;
    }

    const undone = await server.handle({
      method: "tools/call",
      params: { name: "capture_undo", input: { undo_token: undoToken } },
    });
    expect(undone.ok).toBe(true);
    if (undone.ok) {
      const result = parseLiflyMcpToolOutput("capture_undo", undone.result);
      expect(result.undone).toBe(2);
      expect(result.entities?.map((entity) => entity.type)).toEqual(["task", "memo"]);
    }

    const repeated = await server.handle({
      method: "tools/call",
      params: { name: "capture_undo", input: { undo_token: undoToken } },
    });
    expect(repeated.ok).toBe(true);
    if (repeated.ok) {
      const result = parseLiflyMcpToolOutput("capture_undo", repeated.result);
      expect(result.undone).toBe(0);
      expect(result.entities).toEqual([]);
      expect(result.failed_entities).toEqual([]);
    }
  });

  it("returns validation errors for invalid input", async () => {
    const server = createFakeServer();
    const response = await server.handle({
      method: "tools/call",
      params: { name: "memo_create", input: { type: "invalid", content_markdown: "bad" } },
    });

    expect(response.ok).toBe(false);
  });
});
