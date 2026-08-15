import type { DesktopLocalCoreTransport } from "../../../packages/local-core/src/index.js";
import { HttpAiRelayClient, type AccessTokenProvider } from "./ai-relay-client.js";
import { LocalCoreComputeNodePlanner } from "./compute-node-planner.js";
import { DeviceAiJobCipher } from "./device-ai-job-cipher.js";
import { EncryptedAiJobEngine } from "./encrypted-job-engine.js";
import { EncryptedAiRelayWorker } from "./encrypted-relay-worker.js";
import { createDesktopLocalMcpRuntime, type LocalMcpRuntime } from "./tool-handlers.js";

export interface ComputeNodeRelayRuntimeOptions {
  deviceId: string;
  deviceKey: Uint8Array;
  apiBaseUrl: string;
  tokenProvider: AccessTokenProvider;
  bridgePath?: string | null;
  bridgeArgs?: string[];
  transport?: DesktopLocalCoreTransport | null;
  requestTimeoutMs?: number;
  maxJobAttempts?: number;
  fetch?: typeof fetch;
}

export interface ComputeNodeRelayRuntime {
  localMcp: LocalMcpRuntime;
  jobs: EncryptedAiJobEngine;
  worker: EncryptedAiRelayWorker;
}

export function createComputeNodeRelayRuntime(
  options: ComputeNodeRelayRuntimeOptions,
): ComputeNodeRelayRuntime {
  const localMcp = createDesktopLocalMcpRuntime({
    bridgePath: options.bridgePath,
    bridgeArgs: options.bridgeArgs,
    transport: options.transport,
    requestTimeoutMs: options.requestTimeoutMs,
  });
  const relay = new HttpAiRelayClient({
    apiBaseUrl: options.apiBaseUrl,
    accessToken: options.tokenProvider,
    fetch: options.fetch,
  });
  const cipher = new DeviceAiJobCipher({
    deviceId: options.deviceId,
    privateKeyBytes: options.deviceKey,
    resolvePublicKey: (deviceId) => relay.resolveDevicePublicKey(deviceId),
  });
  const jobs = new EncryptedAiJobEngine({
    deviceId: options.deviceId,
    cipher,
    executor: new LocalCoreComputeNodePlanner(localMcp.core),
    maxAttempts: options.maxJobAttempts,
  });
  localMcp.jobs = jobs;
  return {
    localMcp,
    jobs,
    worker: new EncryptedAiRelayWorker(relay, jobs),
  };
}
