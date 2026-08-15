import { spawn } from "node:child_process";

import type {
  DecryptedAiJobExecutionContext,
  DecryptedAiJobExecutor,
} from "./encrypted-job-engine.js";
import { parseComputeNodePlanRequest } from "./compute-node-planner.js";

export interface ProviderBackedPlannerOptions {
  helperPath: string;
  helperArgs?: string[];
  fallback: DecryptedAiJobExecutor;
}

export class ProviderBackedComputeNodePlanner implements DecryptedAiJobExecutor {
  private readonly helperPath: string;
  private readonly helperArgs: string[];
  private readonly fallback: DecryptedAiJobExecutor;

  constructor(options: ProviderBackedPlannerOptions) {
    this.helperPath = options.helperPath;
    this.helperArgs = options.helperArgs ?? [];
    this.fallback = options.fallback;
  }

  async execute(
    payload: unknown,
    context: DecryptedAiJobExecutionContext,
  ): Promise<unknown> {
    const request = parseComputeNodePlanRequest(payload);
    if (request.asset_ids.length > 0) {
      return this.fallback.execute(payload, context);
    }
    try {
      return await this.executeProvider(request.text);
    } catch {
      // This remains entirely on the Desktop device: provider failure falls
      // back to deterministic Local Core parsing, never to Lifly Cloud AI.
      return this.fallback.execute(payload, context);
    }
  }

  private executeProvider(text: string): Promise<unknown> {
    return new Promise((resolve, reject) => {
      const child = spawn(this.helperPath, this.helperArgs, {
        stdio: ["pipe", "pipe", "inherit"],
      });
      if (!child.stdin || !child.stdout) {
        reject(new Error("Local AI provider helper did not expose stdio"));
        return;
      }
      let stdout = "";
      child.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
      });
      child.on("error", reject);
      child.on("exit", (code) => {
        if (code !== 0) {
          reject(new Error("Local AI provider helper exited unsuccessfully"));
          return;
        }
        try {
          const lines = stdout
            .split(/\r?\n/u)
            .map((line) => line.trim())
            .filter(Boolean);
          const response = JSON.parse(lines.at(-1) ?? "") as unknown;
          if (!response || typeof response !== "object" || Array.isArray(response)) {
            throw new Error("Local AI provider helper response must be an object");
          }
          const record = response as Record<string, unknown>;
          if (record.ok !== true) {
            throw new Error("Local AI provider helper was unavailable");
          }
          const result = record.result;
          if (!result || typeof result !== "object" || Array.isArray(result)) {
            throw new Error("Local AI provider result must be an object");
          }
          const providerResult = result as Record<string, unknown>;
          if (providerResult.schema_version !== 1 || !Array.isArray(providerResult.actions)) {
            throw new Error("Local AI provider result has invalid schema");
          }
          resolve({
            schema_version: 1,
            provider: providerResult.provider,
            model: providerResult.model,
            fallback_used: providerResult.fallback_used === true,
            actions: providerResult.actions,
          });
        } catch (error) {
          reject(error);
        }
      });
      child.stdin.write(
        `${JSON.stringify({
          text,
          timezone: "Asia/Shanghai",
          locale: "zh-CN",
        })}\n`,
      );
      child.stdin.end();
    });
  }
}
