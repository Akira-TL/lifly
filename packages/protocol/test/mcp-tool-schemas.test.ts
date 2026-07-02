import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import {
  LiflyMcpToolContractVersion,
  LiflyMcpToolContracts,
  LiflyMcpToolDescriptions,
  LiflyMcpToolInputSchemas,
  LiflyMcpToolNameSchema,
  LiflyMcpToolOutputSchemas,
  LiflyMcpToolSchemas,
  parseLiflyMcpToolInput,
  parseLiflyMcpToolOutput,
} from "../src/index.js";

const FROZEN_TOOL_NAMES = [
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
] as const;

const NOW = "2026-07-02T10:00:00.000Z";

const MEMO = {
  id: "memo_1",
  type: "memo",
  title: "灵感",
  content_markdown: "# 想法",
  tags: ["lifly"],
  status: "active",
  revision: 1,
  created_at: NOW,
  updated_at: NOW,
};

const TRANSACTION = {
  id: "tx_1",
  direction: "expense",
  amount: 28,
  currency: "CNY",
  merchant: "食堂",
  note: null,
  category_hint: "餐饮",
  occurred_at: NOW,
  status: "active",
  revision: 1,
  created_at: NOW,
  updated_at: NOW,
};

const TASK = {
  id: "task_1",
  title: "买猫粮",
  description: null,
  due_at: null,
  remind_at: NOW,
  priority: "normal",
  task_status: "todo",
  completed_at: null,
  status: "active",
  revision: 1,
  created_at: NOW,
  updated_at: NOW,
};

const ASSET = {
  id: "asset_1",
  kind: "external",
  asset_type: "link",
  title: "Lifly",
  external_url: "https://example.com/lifly",
  sync_status: "synced",
  revision: 1,
  created_at: NOW,
  updated_at: NOW,
};

const OUTPUT_SAMPLES: Record<(typeof FROZEN_TOOL_NAMES)[number], unknown> = {
  capture_parse: {
    capture_id: "capture_1",
    actions: [{ type: "memo_create", payload: { content_markdown: "记一下" }, confidence: 0.8 }],
    requires_confirmation: false,
  },
  capture_commit: {
    committed: true,
    created_entities: [{ type: "memo", id: "memo_1" }],
    failed_actions: [],
    undo_token: "undo_1",
  },
  capture_undo: {
    undone: 1,
    entities: [{ type: "memo", id: "memo_1" }],
    failed_entities: [],
  },
  memo_create: {
    memo_id: "memo_1",
    memo: MEMO,
    undo_token: "undo_1",
  },
  memo_search: {
    memos: [MEMO],
  },
  expense_create: {
    transaction: TRANSACTION,
    undo_token: "undo_1",
  },
  expense_search: {
    transactions: [TRANSACTION],
  },
  expense_summary: {
    period: "current_month",
    total_expense: 28,
    total_income: 0,
    count: 1,
  },
  task_create: {
    task: TASK,
    undo_token: "undo_1",
  },
  task_list: {
    tasks: [TASK],
  },
  task_complete: {
    task: { ...TASK, task_status: "done", completed_at: NOW },
  },
  asset_create_upload_url: {
    asset_id: "asset_2",
    storage_key: "attachments/local-dev/asset_2/demo.txt",
    upload_url: "http://localhost:9000/upload/demo.txt",
    asset: { ...ASSET, id: "asset_2", kind: "internal", asset_type: "file", external_url: null, sync_status: "pending" },
    undo_token: "undo_1",
  },
  asset_register_external_url: {
    asset: ASSET,
    undo_token: "undo_1",
  },
};

describe("Lifly MCP Tool Schema", () => {
  it("matches the frozen tool list exactly", () => {
    expect(LiflyMcpToolNameSchema.options).toEqual(FROZEN_TOOL_NAMES);
    expect(Object.keys(LiflyMcpToolInputSchemas)).toEqual(FROZEN_TOOL_NAMES);
    expect(Object.keys(LiflyMcpToolOutputSchemas)).toEqual(FROZEN_TOOL_NAMES);
    expect(Object.keys(LiflyMcpToolDescriptions)).toEqual(FROZEN_TOOL_NAMES);
    expect(LiflyMcpToolSchemas.map((tool) => tool.name)).toEqual(FROZEN_TOOL_NAMES);
    expect(LiflyMcpToolContracts.map((tool) => tool.name)).toEqual(FROZEN_TOOL_NAMES);
  });

  it("attaches input and output schemas to every contract", () => {
    for (const contract of LiflyMcpToolContracts) {
      expect(contract.version).toBe(LiflyMcpToolContractVersion);
      expect(contract.description).toBe(LiflyMcpToolDescriptions[contract.name]);
      expect(contract.inputSchema).toBe(LiflyMcpToolInputSchemas[contract.name]);
      expect(contract.outputSchema).toBe(LiflyMcpToolOutputSchemas[contract.name]);
    }
  });

  it("keeps the Python Cloud MCP tool list aligned with packages/protocol", () => {
    const cloudServer = readFileSync(
      new URL("../../../services/api/app/modules/mcp/cloud_server.py", import.meta.url),
      "utf8",
    );
    const cloudToolNames = [...cloudServer.matchAll(/@cloud_mcp\.tool\(\s*name="([^"]+)"/g)].map((match) => match[1]);

    expect(cloudToolNames).toEqual(FROZEN_TOOL_NAMES);
  });

  it("parses capture_parse input with defaults", () => {
    const parsed = parseLiflyMcpToolInput("capture_parse", {
      text: "今天午饭花了 28 元，明天提醒我买猫粮",
    });

    expect(parsed).toEqual({
      text: "今天午饭花了 28 元，明天提醒我买猫粮",
      timezone: "Asia/Shanghai",
      locale: "zh-CN",
    });
  });

  it("parses memo_create input", () => {
    const parsed = parseLiflyMcpToolInput("memo_create", {
      title: "灵感",
      content_markdown: "# 想法\n做一个 AI-first 生活记录系统。",
      type: "doc",
      tags: ["lifly", "idea"],
    });

    expect(parsed.type).toBe("doc");
    expect(parsed.tags).toEqual(["lifly", "idea"]);
  });

  it("rejects invalid memo type", () => {
    expect(() =>
      parseLiflyMcpToolInput("memo_create", {
        content_markdown: "invalid",
        type: "calendar",
      }),
    ).toThrow();
  });

  it("parses expense_create input", () => {
    const parsed = parseLiflyMcpToolInput("expense_create", {
      amount: 28,
      merchant: "食堂",
    });

    expect(parsed.amount).toBe(28);
    expect(parsed.direction).toBe("expense");
    expect(parsed.currency).toBe("CNY");
  });

  it("rejects zero or negative expense amounts", () => {
    expect(() =>
      parseLiflyMcpToolInput("expense_create", {
        amount: 0,
        merchant: "食堂",
      }),
    ).toThrow();

    expect(() =>
      parseLiflyMcpToolInput("expense_create", {
        amount: -1,
        merchant: "食堂",
      }),
    ).toThrow();
  });

  it("aligns internal upload asset types with the Python runtime", () => {
    const parsed = parseLiflyMcpToolInput("asset_create_upload_url", {
      filename: "deck.pptx",
      asset_type: "ppt",
    });

    expect(parsed.asset_type).toBe("ppt");

    expect(() =>
      parseLiflyMcpToolInput("asset_create_upload_url", {
        filename: "slide.pptx",
        asset_type: "slide",
      }),
    ).toThrow();

    expect(() =>
      parseLiflyMcpToolInput("asset_create_upload_url", {
        filename: "external-link.txt",
        asset_type: "link",
      }),
    ).toThrow();
  });

  it("aligns external asset types with the Python runtime", () => {
    const link = parseLiflyMcpToolInput("asset_register_external_url", {
      external_url: "https://example.com/link",
      asset_type: "link",
    });
    const embed = parseLiflyMcpToolInput("asset_register_external_url", {
      external_url: "https://example.com/embed",
      asset_type: "embed",
    });

    expect(link.asset_type).toBe("link");
    expect(embed.asset_type).toBe("embed");
  });

  it("rejects invalid external asset URL", () => {
    expect(() =>
      parseLiflyMcpToolInput("asset_register_external_url", {
        external_url: "not-a-url",
      }),
    ).toThrow();
  });

  it("parses every declared tool output sample", () => {
    for (const toolName of FROZEN_TOOL_NAMES) {
      expect(parseLiflyMcpToolOutput(toolName, OUTPUT_SAMPLES[toolName])).toBeTruthy();
    }
  });

  it("parses capture_commit partial failure output", () => {
    const parsed = parseLiflyMcpToolOutput("capture_commit", {
      committed: true,
      created_entities: [{ type: "memo", id: "memo_1" }],
      failed_actions: [{ action_index: 2, action_type: "task_create", reason: "validation_error" }],
      undo_token: "undo_1",
    });

    expect(parsed.failed_actions).toHaveLength(1);
  });

  it("rejects invalid output shape", () => {
    expect(() => parseLiflyMcpToolOutput("memo_create", { memo_id: "memo_1" })).toThrow();
    expect(() => parseLiflyMcpToolOutput("capture_commit", { committed: true })).toThrow();
  });
});
