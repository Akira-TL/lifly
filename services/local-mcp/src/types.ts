import type { LiflyMcpToolName } from "../../../packages/protocol/src/index.js";

export interface LocalMcpToolDefinition {
  name: LiflyMcpToolName;
  description: string;
}

export interface LocalMcpRequest {
  id?: string | number | null;
  method: "health" | "node/capabilities" | "jobs/execute" | "jobs/status" | "tools/list" | "tools/call";
  params?: unknown;
}

export interface LocalMcpCallParams {
  name: LiflyMcpToolName;
  input?: unknown;
}

export interface LocalMcpJobExecuteParams {
  envelope: unknown;
}

export interface LocalMcpJobStatusParams {
  job_id: string;
}

export type LocalMcpResponse =
  | { id?: string | number | null; ok: true; result: unknown }
  | { id?: string | number | null; ok: false; error: { message: string; code: string } };
