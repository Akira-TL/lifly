import { describe, expect, it } from "vitest";
import { DesktopLocalCoreBridge, FakeLocalCoreBridge, localMcpContext } from "../src/index.js";

const context = localMcpContext("test_tool");

describe("DesktopLocalCoreBridge", () => {
  it("delegates health and business calls through the configured desktop transport", async () => {
    const calls: Array<{ method: string; input: unknown }> = [];
    const transport = {
      async invoke(request: { method: string; input: unknown }) {
        calls.push({ method: request.method, input: request.input });
        if (request.method === "health") {
          return {
            status: "ok",
            mode: "desktop_bridge",
            version: "desktop-host.test",
            runtime: "desktop",
            detail: "fixture transport",
          };
        }
        if (request.method === "memo_create") {
          return {
            id: "desktop_memo_1",
            type: "memo",
            title: null,
            content_markdown: "delegated",
            tags: [],
            status: "active",
            revision: 1,
            created_at: "2026-08-15T10:00:00.000Z",
            updated_at: "2026-08-15T10:00:00.000Z",
          };
        }
        throw new Error(`Unexpected method: ${request.method}`);
      },
    };
    const core = new DesktopLocalCoreBridge({ transport });

    await expect(core.health()).resolves.toMatchObject({ status: "ok", version: "desktop-host.test" });
    await expect(
      core.createMemo({ type: "memo", content_markdown: "delegated" }, context),
    ).resolves.toMatchObject({ id: "desktop_memo_1", content_markdown: "delegated" });
    expect(calls.map((call) => call.method)).toEqual(["health", "memo_create"]);
  });
});

describe("FakeLocalCoreBridge", () => {
  it("reports fake health", async () => {
    const core = new FakeLocalCoreBridge();
    await expect(core.health()).resolves.toMatchObject({ status: "ok", mode: "fake" });
  });

  it("creates and searches memos", async () => {
    const core = new FakeLocalCoreBridge();
    const memo = await core.createMemo(
      {
        type: "memo",
        title: "Local memo",
        content_markdown: "created through local core",
        tags: ["local"],
      },
      context,
    );

    expect(memo.id).toMatch(/^local_memo_/);
    expect(memo.revision).toBe(1);

    const results = await core.searchMemos({ q: "local core", limit: 20 }, context);
    expect(results.map((item) => item.id)).toContain(memo.id);
  });

  it("creates expenses and summarizes them", async () => {
    const core = new FakeLocalCoreBridge();
    const tx = await core.createExpense(
      {
        direction: "expense",
        amount: 12.5,
        currency: "CNY",
        merchant: "Local Merchant",
        note: "local expense",
        category_hint: "test",
        occurred_at: null,
      },
      context,
    );

    expect(tx.id).toMatch(/^local_tx_/);

    const results = await core.searchExpenses({ q: "merchant", limit: 20 }, context);
    expect(results).toHaveLength(1);

    const summary = await core.summarizeExpenses({ period: "current_month", start_at: null, end_at: null }, context);
    expect(summary.total_expense).toBe(12.5);
    expect(summary.count).toBe(1);
  });

  it("creates, lists, and completes tasks", async () => {
    const core = new FakeLocalCoreBridge();
    const task = await core.createTask(
      {
        title: "Local task",
        description: "local task description",
        priority: "normal",
        due_at: null,
        remind_at: null,
      },
      context,
    );

    expect(task.task_status).toBe("todo");

    const tasks = await core.listTasks({ task_status: "todo", limit: 20 }, context);
    expect(tasks.map((item) => item.id)).toContain(task.id);

    const completed = await core.completeTask({ task_id: task.id }, context);
    expect(completed.task_status).toBe("done");
    expect(completed.completed_at).toBeTruthy();
    expect(completed.revision).toBe(2);
  });

  it("registers external assets", async () => {
    const core = new FakeLocalCoreBridge();
    const asset = await core.registerExternalAsset(
      {
        external_url: "https://example.com/local-core",
        title: "Local Core Link",
        asset_type: "link",
      },
      context,
    );

    expect(asset.kind).toBe("external");
    expect(asset.sync_status).toBe("synced");
  });

  it("parses, commits, and undoes capture sessions", async () => {
    const core = new FakeLocalCoreBridge();
    const parsed = await core.captureParse(
      { text: "记一下 Local Core capture", timezone: "Asia/Shanghai", locale: "zh-CN" },
      context,
    );

    expect(parsed.actions).toHaveLength(1);

    const committed = await core.captureCommit({ capture_id: parsed.capture_id, selected_action_indexes: null }, context);
    expect(committed.committed).toBe(true);
    expect(committed.created_entities).toHaveLength(1);
    expect(committed.undo_token).toBeTruthy();

    const undone = await core.captureUndo({ undo_token: committed.undo_token }, context);
    expect(undone.undone).toBe(1);
    expect(undone.failed_entities).toHaveLength(0);
  });
});
