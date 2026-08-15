#!/usr/bin/env node
import { createInterface } from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { LocalMcpServer } from "./server.js";
import type { LocalMcpRequest } from "./types.js";

export { LocalMcpServer } from "./server.js";
export { DesktopLocalCoreProcessTransport } from "./desktop-core-transport.js";
export { HttpAiRelayClient } from "./ai-relay-client.js";
export type { AccessTokenProvider, AiRelayClient, HttpAiRelayClientOptions } from "./ai-relay-client.js";
export { LocalCoreComputeNodePlanner } from "./compute-node-planner.js";
export { DeviceAiJobCipher } from "./device-ai-job-cipher.js";
export type { DeviceAiJobCipherOptions, DevicePublicKeyResolver } from "./device-ai-job-cipher.js";
export { EncryptedAiRelayWorker } from "./encrypted-relay-worker.js";
export type { EncryptedRelayWorkerStatus } from "./encrypted-relay-worker.js";
export { createComputeNodeRelayRuntime } from "./compute-node-runtime.js";
export type { ComputeNodeRelayRuntime, ComputeNodeRelayRuntimeOptions } from "./compute-node-runtime.js";
export { EncryptedAiJobEngine, RetryableEncryptedAiJobError } from "./encrypted-job-engine.js";
export type {
  DecryptedAiJobExecutionContext,
  DecryptedAiJobExecutor,
  EncryptedAiJobCipher,
  EncryptedAiJobCiphertext,
  EncryptedAiJobEngineOptions,
  EncryptedAiJobExecutionOutcome,
  EncryptedAiJobResultContext,
  EncryptedAiJobStatus,
} from "./encrypted-job-engine.js";
export type { DesktopLocalCoreProcessTransportOptions } from "./desktop-core-transport.js";
export {
  callLocalMcpTool,
  createDefaultLocalMcpRuntime,
  createDesktopLocalMcpRuntime,
  createTestLocalMcpRuntime,
  listLocalMcpTools,
  localMcpCapabilityReport,
} from "./tool-handlers.js";
export type { DesktopLocalMcpRuntimeOptions, LocalMcpRuntime } from "./tool-handlers.js";
export type * from "./types.js";

export async function runStdioServer(): Promise<void> {
  const server = new LocalMcpServer();
  const rl = createInterface({ input, terminal: false });

  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    let response;
    try {
      const request = JSON.parse(trimmed) as LocalMcpRequest;
      response = await server.handle(request);
    } catch (error) {
      response = {
        ok: false,
        error: {
          code: "BAD_REQUEST",
          message: error instanceof Error ? error.message : String(error),
        },
      };
    }

    output.write(`${JSON.stringify(response)}\n`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await runStdioServer();
}
