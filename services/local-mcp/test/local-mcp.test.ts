import { describe, expect, it } from "vitest";
import { LocalMcpServer } from "../src/index.js";

describe("LocalMcpServer", () => {
  it("reports health", async () => {
    const server = new LocalMcpServer();
    const response = await server.handle({ method: "health" });
    expect(response.ok).toBe(true);
    if (response.ok) {
      expect(response.result).toMatchObject({ status: "ok", mode: "fake" });
    }
  });

  it("lists protocol tools", async () => {
    const server = new LocalMcpServer();
    const response = await server.handle({ method: "tools/list" });
    expect(response.ok).toBe(true);
    if (response.ok) {
      const result = response.result as { tools: Array<{ name: string }> };
      expect(result.tools.map((tool) => tool.name)).toContain("memo_create");
      expect(result.tools.map((tool) => tool.name)).toContain("capture_commit");
    }
  });

  it("calls memo_create and memo_search", async () => {
    const server = new LocalMcpServer();
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

    const searched = await server.handle({
      method: "tools/call",
      params: {
        name: "memo_search",
        input: { q: "local mcp", limit: 20 },
      },
    });
    expect(searched.ok).toBe(true);
    if (searched.ok) {
      const result = searched.result as { memos: Array<{ title: string }> };
      expect(result.memos.some((memo) => memo.title === "Local MCP memo")).toBe(true);
    }
  });

  it("returns validation errors for invalid input", async () => {
    const server = new LocalMcpServer();
    const response = await server.handle({
      method: "tools/call",
      params: { name: "memo_create", input: { type: "invalid", content_markdown: "bad" } },
    });

    expect(response.ok).toBe(false);
  });
});
