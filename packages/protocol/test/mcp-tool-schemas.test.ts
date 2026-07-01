import { describe, expect, it } from "vitest";

import {
  LiflyMcpToolInputSchemas,
  LiflyMcpToolNameSchema,
  LiflyMcpToolSchemas,
  parseLiflyMcpToolInput,
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

describe("Lifly MCP Tool Schema v0.1", () => {
  it("matches the frozen v0.1 tool list exactly", () => {
    expect(LiflyMcpToolNameSchema.options).toEqual(FROZEN_TOOL_NAMES);
    expect(Object.keys(LiflyMcpToolInputSchemas)).toEqual(FROZEN_TOOL_NAMES);
    expect(LiflyMcpToolSchemas.map((tool) => tool.name)).toEqual(FROZEN_TOOL_NAMES);
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
});
