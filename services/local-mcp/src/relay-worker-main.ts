import { stdin, stdout } from "node:process";
import { createInterface } from "node:readline/promises";

import { createComputeNodeRelayRuntime } from "./compute-node-runtime.js";

interface BootstrapCredential {
  account_id: string;
  account_data_key_base64: string;
  account_data_key_version?: number;
  device_id: string;
  private_key_base64: string;
  access_token: string;
  api_base_url?: string;
}

async function main(): Promise<void> {
  const bridgePath = process.env.LIFLY_LOCAL_CORE_BRIDGE_PATH;
  if (!bridgePath) {
    throw new Error("LIFLY_LOCAL_CORE_BRIDGE_PATH is required for Compute Node runtime");
  }

  const credentials = await readBootstrapCredential();
  const accountDataKey = decodeBase64(credentials.account_data_key_base64);
  if (accountDataKey.length !== 32) {
    accountDataKey.fill(0);
    throw new Error("Compute Node Account Data Key must be 32 bytes");
  }
  const privateKey = decodeBase64(credentials.private_key_base64);
  if (privateKey.length !== 32) {
    privateKey.fill(0);
    throw new Error("Compute Node X25519 private key must be 32 bytes");
  }
  const runtime = createComputeNodeRelayRuntime({
    accountId: credentials.account_id,
    accountDataKeyBytes: accountDataKey,
    accountDataKeyVersion: credentials.account_data_key_version ?? 1,
    deviceId: credentials.device_id,
    deviceKey: privateKey,
    apiBaseUrl:
      credentials.api_base_url ??
      process.env.LIFLY_API_BASE_URL ??
      "http://127.0.0.1:8210/api/v1",
    tokenProvider: () => credentials.access_token,
    bridgePath,
    providerHelperPath: process.env.LIFLY_AI_PROVIDER_HELPER_PATH ?? null,
  });
  privateKey.fill(0);
  accountDataKey.fill(0);

  stdout.write("Lifly encrypted Compute Node worker started\n");
  try {
    while (true) {
      try {
        const status = await runtime.worker.runOnce();
        if (status.status === "idle") {
          await delay(750);
          continue;
        }
        stdout.write(
          `Lifly Compute Node job ${status.outcome.job_id}: ${status.outcome.status}`
          + ` attempt=${status.outcome.attempt_count}`
          + ` retryable=${String(status.outcome.retryable)}`
          + ` failure_stage=${status.outcome.failure_stage ?? "none"}`
          + ` error_class=${classifyOutcomeError(status.outcome.error)}\n`,
        );
      } catch (error) {
        if (!isRetryableRelayError(error)) throw error;
        stdout.write("Lifly Compute Node relay temporarily unavailable; retrying\n");
        await delay(1500);
      }
    }
  } finally {
    await runtime.localMcp.close?.();
  }
}

async function readBootstrapCredential(): Promise<BootstrapCredential> {
  const lines = createInterface({ input: stdin, terminal: false });
  try {
    for await (const line of lines) {
      if (!line.trim()) continue;
      const decoded = JSON.parse(line) as unknown;
      if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
        throw new Error("Compute Node bootstrap credential must be a JSON object");
      }
      const value = decoded as Record<string, unknown>;
      const accountId = requiredString(value.account_id, "account_id");
      const accountDataKey = requiredString(
        value.account_data_key_base64,
        "account_data_key_base64",
      );
      const accountDataKeyVersion = value.account_data_key_version;
      if (
        accountDataKeyVersion !== undefined
        && (!Number.isInteger(accountDataKeyVersion) || Number(accountDataKeyVersion) < 1)
      ) {
        throw new Error("account_data_key_version must be a positive integer when provided");
      }
      const deviceId = requiredString(value.device_id, "device_id");
      const privateKey = requiredString(
        value.private_key_base64,
        "private_key_base64",
      );
      const accessToken = requiredString(value.access_token, "access_token");
      const apiBaseUrl = value.api_base_url;
      if (apiBaseUrl !== undefined && typeof apiBaseUrl !== "string") {
        throw new Error("api_base_url must be a string when provided");
      }
      return {
        account_id: accountId,
        account_data_key_base64: accountDataKey,
        ...(typeof accountDataKeyVersion === "number"
          ? { account_data_key_version: accountDataKeyVersion }
          : {}),
        device_id: deviceId,
        private_key_base64: privateKey,
        access_token: accessToken,
        ...(typeof apiBaseUrl === "string" && apiBaseUrl.length > 0
          ? { api_base_url: apiBaseUrl }
          : {}),
      };
    }
  } finally {
    lines.close();
  }
  throw new Error("Compute Node bootstrap credential was not provided on stdin");
}

function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${name} must be a non-empty string`);
  }
  return value;
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const result = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    result[index] = binary.charCodeAt(index);
  }
  return result;
}

function classifyOutcomeError(error: string | undefined): string {
  if (!error) return "none";
  const normalized = error.toLowerCase();
  if (
    normalized.includes("decrypt")
    || normalized.includes("aes")
    || normalized.includes("operationerror")
    || normalized.includes("cipher")
  ) {
    return "crypto";
  }
  if (normalized.includes("public key") || normalized.includes("x25519")) {
    return "public_key";
  }
  if (normalized.includes("provider") || normalized.includes("ollama")) {
    return "provider";
  }
  if (normalized.includes("local core") || normalized.includes("desktop bridge")) {
    return "local_core";
  }
  if (normalized.includes("relay") || normalized.includes("http")) {
    return "relay";
  }
  return "unknown";
}

function isRetryableRelayError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  const match = error.message.match(/Compute Node relay request failed: HTTP (\d{3})/);
  if (!match) return false;
  const status = Number(match[1]);
  return status === 429 || status >= 500;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

await main();
