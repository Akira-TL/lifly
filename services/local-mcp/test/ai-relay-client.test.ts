import { describe, expect, it } from "vitest";

import { HttpAiRelayClient } from "../src/ai-relay-client.js";

describe("HttpAiRelayClient device key directory", () => {
  it("refreshes trusted public keys by key_version instead of pinning the first value", async () => {
    const responses = [
      deviceList("desktop-1", "public-key-v1", 1),
      deviceList("desktop-1", "public-key-v2", 2),
    ];
    let fetchCount = 0;
    const client = new HttpAiRelayClient({
      apiBaseUrl: "https://lifly.invalid/api/v1",
      accessToken: () => "token",
      fetch: async () => {
        const body = responses[Math.min(fetchCount, responses.length - 1)]!;
        fetchCount += 1;
        return Response.json(body);
      },
    });

    await expect(client.resolveDevicePublicKey("desktop-1")).resolves.toBe(
      "public-key-v1",
    );
    await expect(client.resolveDevicePublicKey("desktop-1")).resolves.toBe(
      "public-key-v2",
    );
    expect(fetchCount).toBe(2);
  });

  it("rejects a public-key change that does not advance key_version", async () => {
    const responses = [
      deviceList("desktop-1", "public-key-v1", 3),
      deviceList("desktop-1", "tampered-key", 3),
    ];
    let fetchCount = 0;
    const client = new HttpAiRelayClient({
      apiBaseUrl: "https://lifly.invalid/api/v1",
      accessToken: () => "token",
      fetch: async () => Response.json(responses[fetchCount++]!),
    });

    await client.resolveDevicePublicKey("desktop-1");
    await expect(client.resolveDevicePublicKey("desktop-1")).rejects.toThrow(
      "without key_version rotation",
    );
  });
});

function deviceList(deviceId: string, publicKey: string, keyVersion: number) {
  return {
    devices: [
      {
        device_id: deviceId,
        account_id: "account-1",
        display_name: "Desktop",
        platform: "linux",
        public_key: publicKey,
        trust_state: "trusted",
        capability_report: {
          protocol_version: 1,
          capabilities: ["local_ai"],
          supported_tools: [],
        },
        is_default_compute_node: true,
        key_version: keyVersion,
        protocol_version: 1,
      },
    ],
  };
}
