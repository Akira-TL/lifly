import { LiflyMcpToolNameSchema, type LiflyMcpToolName } from "../../../packages/protocol/src/index.js";
import {
  callLocalMcpTool,
  createDefaultLocalMcpRuntime,
  listLocalMcpTools,
  localMcpCapabilityReport,
  type LocalMcpRuntime,
} from "./tool-handlers.js";
import type { LocalMcpCallParams, LocalMcpRequest, LocalMcpResponse } from "./types.js";

export class LocalMcpServer {
  constructor(private readonly runtime: LocalMcpRuntime = createDefaultLocalMcpRuntime()) {}

  async close(): Promise<void> {
    await this.runtime.close?.();
  }

  async handle(request: LocalMcpRequest): Promise<LocalMcpResponse> {
    try {
      switch (request.method) {
        case "health": {
          const health = await this.runtime.core.health();
          return { id: request.id, ok: true, result: health };
        }
        case "node/capabilities": {
          return { id: request.id, ok: true, result: localMcpCapabilityReport() };
        }
        case "tools/list": {
          return { id: request.id, ok: true, result: { tools: listLocalMcpTools() } };
        }
        case "tools/call": {
          const params = normalizeCallParams(request.params);
          const result = await callLocalMcpTool(this.runtime, params.name, params.input);
          return { id: request.id, ok: true, result };
        }
      }
    } catch (error) {
      return {
        id: request.id,
        ok: false,
        error: {
          code: "LOCAL_MCP_ERROR",
          message: error instanceof Error ? error.message : String(error),
        },
      };
    }
  }
}

export function normalizeCallParams(params: unknown): LocalMcpCallParams {
  if (!params || typeof params !== "object") {
    throw new Error("tools/call params must be an object");
  }

  const data = params as Record<string, unknown>;
  const name = LiflyMcpToolNameSchema.parse(data.name);
  const input = data.input ?? data["arguments"] ?? {};
  return { name: name as LiflyMcpToolName, input };
}
