import {
  createCipheriv,
  createPrivateKey,
  createPublicKey,
  diffieHellman,
  hkdfSync,
} from "node:crypto";

import { describe, expect, it } from "vitest";

import { FakeLocalCoreBridge } from "../../../packages/local-core/src/index.js";
import { LiflyAiJobEnvelopeSchema } from "../../../packages/protocol/src/index.js";
import { LocalCoreComputeNodePlanner } from "../src/compute-node-planner.js";
import { DeviceAiJobCipher } from "../src/device-ai-job-cipher.js";
import { EncryptedAiJobEngine } from "../src/encrypted-job-engine.js";

const phonePrivate = Buffer.alloc(32, 1);
const desktopPrivate = Buffer.alloc(32, 2);
const phonePublic = publicKeyFromPrivate(phonePrivate);
const desktopPublic = publicKeyFromPrivate(desktopPrivate);
const expiresAt = "2026-08-15T13:00:00.000Z";

function resolver(keys: Record<string, string>) {
  return async (deviceId: string): Promise<string> => {
    const key = keys[deviceId];
    if (!key) throw new Error(`Unknown device: ${deviceId}`);
    return key;
  };
}

describe("DeviceAiJobCipher", () => {
  it("executes encrypted request through Local Core and returns encrypted strict candidates", async () => {
    const requestCiphertext = encryptRequestForDesktop();
    const desktopCipher = new DeviceAiJobCipher({
      deviceId: "desktop-1",
      privateKeyBytes: desktopPrivate,
      resolvePublicKey: resolver({ "phone-1": phonePublic }),
      nonce: () => new Uint8Array(12).fill(3),
    });
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: desktopCipher,
      executor: new LocalCoreComputeNodePlanner(
        new FakeLocalCoreBridge(),
        () => new Date("2026-08-15T12:00:00.000Z"),
      ),
      createJobId: () => "result-1",
      now: () => new Date("2026-08-15T12:00:00.000Z"),
    });

    const outcome = await engine.execute(requestCiphertext);

    expect(outcome.status).toBe("succeeded");
    expect(outcome.result_envelope?.correlation_id).toBe("request-1");
    expect(outcome.result_envelope?.target_device_id).toBe("phone-1");
    const phoneCipher = new DeviceAiJobCipher({
      deviceId: "phone-1",
      privateKeyBytes: phonePrivate,
      resolvePublicKey: resolver({ "desktop-1": desktopPublic }),
    });
    const clear = (await phoneCipher.decrypt(outcome.result_envelope!)) as {
      schema_version: number;
      actions: Array<{ type: string; payload: Record<string, unknown> }>;
    };
    expect(clear.schema_version).toBe(1);
    expect(clear.actions).toHaveLength(1);
    expect(clear.actions[0]?.type).toBe("memo_create");
    expect(clear.actions[0]?.payload).toEqual({
      type: "memo",
      content_markdown: "跨设备",
    });
  });

  it("fails closed when authenticated routing metadata is changed", async () => {
    const request = encryptRequestForDesktop();
    const desktopCipher = new DeviceAiJobCipher({
      deviceId: "desktop-2",
      privateKeyBytes: desktopPrivate,
      resolvePublicKey: resolver({ "phone-1": phonePublic }),
    });
    await expect(
      desktopCipher.decrypt({ ...request, target_device_id: "desktop-2" }),
    ).rejects.toThrow();
  });
});

function encryptRequestForDesktop() {
  const privateKey = x25519PrivateKey(phonePrivate);
  const publicKey = x25519PublicKey(desktopPublic);
  const context = [
    "lifly/device-ai-job/key/v1",
    "account-1",
    "phone-1",
    "desktop-1",
    "request",
    null,
    "request-1",
    "idem-1",
    expiresAt,
    1,
    1,
  ];
  const shared = diffieHellman({ privateKey, publicKey });
  const key = Buffer.from(
    hkdfSync(
      "sha256",
      shared,
      Buffer.from("lifly/device-ai-job/key/v1/account-1"),
      Buffer.from(JSON.stringify(context)),
      32,
    ),
  );
  const nonce = Buffer.alloc(12, 5);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(
    Buffer.from(
      JSON.stringify(["lifly/device-ai-job/aad/v1", ...context.slice(1)]),
    ),
  );
  const plaintext = JSON.stringify({
    schema_version: 1,
    operation: "plan",
    text: "记一下跨设备",
    asset_ids: [],
  });
  const cipherText = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  return LiflyAiJobEnvelopeSchema.parse({
    protocol_version: 1,
    job_id: "request-1",
    account_id: "account-1",
    source_device_id: "phone-1",
    target_device_id: "desktop-1",
    message_type: "request",
    correlation_id: null,
    idempotency_key: "idem-1",
    expires_at: expiresAt,
    encryption_version: 1,
    nonce: nonce.toString("base64url"),
    ciphertext: Buffer.concat([cipherText, tag]).toString("base64url"),
  });
}

function publicKeyFromPrivate(privateBytes: Uint8Array): string {
  const der = createPublicKey(x25519PrivateKey(privateBytes)).export({
    format: "der",
    type: "spki",
  });
  return Buffer.from(der).subarray(-32).toString("base64");
}

function x25519PrivateKey(privateBytes: Uint8Array) {
  return createPrivateKey({
    key: Buffer.concat([
      Buffer.from("302e020100300506032b656e04220420", "hex"),
      Buffer.from(privateBytes),
    ]),
    format: "der",
    type: "pkcs8",
  });
}

function x25519PublicKey(publicKey: string) {
  return createPublicKey({
    key: Buffer.concat([
      Buffer.from("302a300506032b656e032100", "hex"),
      Buffer.from(publicKey, "base64"),
    ]),
    format: "der",
    type: "spki",
  });
}
