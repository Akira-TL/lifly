import { stdin, stdout } from "node:process";
import { createInterface } from "node:readline/promises";

import { createComputeNodeRelayRuntime } from "./compute-node-runtime.js";

interface BootstrapCredential {
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
  const privateKey = decodeBase64(credentials.private_key_base64);
  if (privateKey.length !== 32) {
    privateKey.fill(0);
    throw new Error("Compute Node X25519 private key must be 32 bytes");
  }
  const runtime = createComputeNodeRelayRuntime({
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

  stdout.write("Lifly encrypted Compute Node worker started\n");
  try {
    while (true) {
      const status = await runtime.worker.runOnce();
      if (status.status === "idle") {
        await delay(750);
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

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

await main();
