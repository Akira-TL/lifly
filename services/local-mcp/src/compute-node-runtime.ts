import type { DesktopLocalCoreTransport } from "../../../packages/local-core/src/index.js";
import { HttpAiRelayClient, type AccessTokenProvider } from "./ai-relay-client.js";
import { LocalCoreComputeNodePlanner } from "./compute-node-planner.js";
import { ProviderBackedComputeNodePlanner } from "./provider-backed-planner.js";
import {
  DeviceAiJobCipher,
  RawX25519DeviceKeyAgreement,
} from "./device-ai-job-cipher.js";
import { EncryptedAiJobEngine } from "./encrypted-job-engine.js";
import { EncryptedAiRelayWorker } from "./encrypted-relay-worker.js";
import { createDesktopLocalMcpRuntime, type LocalMcpRuntime } from "./tool-handlers.js";

export interface ComputeNodeRelayRuntimeOptions {
  accountId: string;
  accountDataKeyBytes: Uint8Array;
  accountDataKeyVersion?: number;
  deviceId: string;
  deviceKey: Uint8Array;
  apiBaseUrl: string;
  tokenProvider: AccessTokenProvider;
  bridgePath?: string | null;
  bridgeArgs?: string[];
  transport?: DesktopLocalCoreTransport | null;
  requestTimeoutMs?: number;
  maxJobAttempts?: number;
  providerHelperPath?: string | null;
  providerHelperArgs?: string[];
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
    runtimeBootstrap: {
      accountId: options.accountId,
      keyVersion: options.accountDataKeyVersion ?? 1,
      accountDataKeyBytes: options.accountDataKeyBytes,
    },
  });
  const relay = new HttpAiRelayClient({
    apiBaseUrl: options.apiBaseUrl,
    accessToken: options.tokenProvider,
    fetch: options.fetch,
  });
  const keyAgreement = new RawX25519DeviceKeyAgreement({
    deviceId: options.deviceId,
    privateKeyBytes: options.deviceKey,
    resolvePublicKey: (deviceId) => relay.resolveDevicePublicKey(deviceId),
  });
  const cipher = new DeviceAiJobCipher({ keyAgreement });
  const deterministicPlanner = new LocalCoreComputeNodePlanner(localMcp.core);
  const executor = options.providerHelperPath
    ? new ProviderBackedComputeNodePlanner({
      helperPath: options.providerHelperPath,
      helperArgs: options.providerHelperArgs,
      fallback: deterministicPlanner,
    })
    : deterministicPlanner;
  const jobs = new EncryptedAiJobEngine({
    deviceId: options.deviceId,
    cipher,
    executor,
    maxAttempts: options.maxJobAttempts,
  });
  localMcp.jobs = jobs;
  return {
    localMcp,
    jobs,
    worker: new EncryptedAiRelayWorker(relay, jobs),
  };
}
