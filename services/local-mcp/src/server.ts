import { LiflyMcpToolNameSchema, type LiflyMcpToolName } from "../../../packages/protocol/src/index.js";
import {
  callLocalMcpTool,
  createDefaultLocalMcpRuntime,
  listLocalMcpTools,
  localMcpCapabilityReport,
  type LocalMcpRuntime,
} from "./tool-handlers.js";
import type {
  LocalMcpCallParams,
  LocalMcpJobExecuteParams,
  LocalMcpJobStatusParams,
  LocalMcpRequest,
  LocalMcpResponse,
} from "./types.js";

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
          const capabilityReport = localMcpCapabilityReport(this.runtime);
          return {
            id: request.id,
            ok: true,
            result: {
              ...health,
              capabilities: capabilityReport.capabilities,
              supported_tools: capabilityReport.supported_tools,
              encrypted_jobs: this.runtime.jobs ? "ready" : "unconfigured",
            },
          };
        }
        case "node/capabilities": {
          return { id: request.id, ok: true, result: localMcpCapabilityReport(this.runtime) };
        }
        case "jobs/execute": {
          const jobs = this.requireJobEngine();
          const params = normalizeJobExecuteParams(request.params);
          const result = await jobs.execute(params.envelope);
          return { id: request.id, ok: true, result };
        }
        case "jobs/status": {
          const jobs = this.requireJobEngine();
          const params = normalizeJobStatusParams(request.params);
          const result = jobs.status(params.job_id);
          if (!result) throw new Error(`Encrypted AI job not found: ${params.job_id}`);
          return { id: request.id, ok: true, result };
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

  private requireJobEngine() {
    if (!this.runtime.jobs) {
      throw new Error("Encrypted AI job executor is not configured for this Personal Compute Node");
    }
    return this.runtime.jobs;
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

export function normalizeJobExecuteParams(params: unknown): LocalMcpJobExecuteParams {
  if (!params || typeof params !== "object") {
    throw new Error("jobs/execute params must be an object");
  }
  const data = params as Record<string, unknown>;
  if (!("envelope" in data)) throw new Error("jobs/execute params must include envelope");
  return { envelope: data.envelope };
}

export function normalizeJobStatusParams(params: unknown): LocalMcpJobStatusParams {
  if (!params || typeof params !== "object") {
    throw new Error("jobs/status params must be an object");
  }
  const data = params as Record<string, unknown>;
  if (typeof data.job_id !== "string" || data.job_id.length === 0) {
    throw new Error("jobs/status params must include a non-empty job_id");
  }
  return { job_id: data.job_id };
}
