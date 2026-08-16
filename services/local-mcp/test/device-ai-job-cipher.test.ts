import { readFileSync } from "node:fs";
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
import {
  DeviceAiJobCipher,
  RawX25519DeviceKeyAgreement,
} from "../src/device-ai-job-cipher.js";
import { EncryptedAiJobEngine } from "../src/encrypted-job-engine.js";

const phonePrivate = Buffer.alloc(32, 1);
const desktopPrivate = Buffer.alloc(32, 2);
const phonePublic = publicKeyFromPrivate(phonePrivate);
const desktopPublic = publicKeyFromPrivate(desktopPrivate);
const expiresAt = "2026-08-15T13:00:00.000Z";
const sharedVector = JSON.parse(
  readFileSync(
    new URL("../../../packages/protocol/test-vectors/device-ai-job-v1.json", import.meta.url),
    "utf8",
  ),
) as {
  phone: { public_key_base64: string };
  desktop: { public_key_base64: string };
  request: {
    nonce_base64url: string;
    ciphertext_base64url: string;
    payload: Record<string, unknown>;
  };
  result: {
    nonce_base64url: string;
    ciphertext_base64url: string;
    payload: Record<string, unknown>;
  };
};

function resolver(keys: Record<string, string>) {
  return async (deviceId: string): Promise<string> => {
    const key = keys[deviceId];
    if (!key) throw new Error(`Unknown device: ${deviceId}`);
    return key;
  };
}

describe("DeviceAiJobCipher", () => {
  it("matches the shared Dart/TypeScript request and result vectors", async () => {
    const desktopCipher = cipherFor(
      "desktop-1",
      desktopPrivate,
      { "phone-1": sharedVector.phone.public_key_base64 },
      () => Buffer.from(sharedVector.result.nonce_base64url, "base64url"),
    );
    const request = LiflyAiJobEnvelopeSchema.parse({
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
      nonce: sharedVector.request.nonce_base64url,
      ciphertext: sharedVector.request.ciphertext_base64url,
    });

    await expect(desktopCipher.decrypt(request)).resolves.toEqual(
      sharedVector.request.payload,
    );
    const encryptedResult = await desktopCipher.encrypt(sharedVector.result.payload, {
      request,
      result_job_id: "result-1",
      source_device_id: "desktop-1",
      target_device_id: "phone-1",
      expires_at: expiresAt,
    });
    expect(encryptedResult.nonce).toBe(sharedVector.result.nonce_base64url);
    expect(encryptedResult.ciphertext).toBe(sharedVector.result.ciphertext_base64url);
  });

  it("executes encrypted request through Local Core and returns encrypted strict candidates", async () => {
    const requestCiphertext = encryptRequestForDesktop();
    const desktopCipher = cipherFor(
      "desktop-1",
      desktopPrivate,
      { "phone-1": phonePublic },
      () => new Uint8Array(12).fill(3),
    );
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
    const phoneCipher = cipherFor(
      "phone-1",
      phonePrivate,
      { "desktop-1": desktopPublic },
    );
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

  it("decrypts requests whose wire expiry has microseconds using canonical UTC milliseconds", async () => {
    const request = encryptRequestForDesktop("2026-08-15T13:00:00.123456Z");
    const desktopCipher = cipherFor(
      "desktop-1",
      desktopPrivate,
      { "phone-1": phonePublic },
    );
    const clear = await desktopCipher.decrypt(request) as {
      schema_version: number;
      text: string;
    };
    expect(clear.schema_version).toBe(1);
    expect(clear.text).toBe("记一下跨设备");
  });

  it("fails closed when authenticated routing metadata is changed", async () => {
    const request = encryptRequestForDesktop();
    const desktopCipher = cipherFor(
      "desktop-2",
      desktopPrivate,
      { "phone-1": phonePublic },
    );
    await expect(
      desktopCipher.decrypt({ ...request, target_device_id: "desktop-2" }),
    ).rejects.toThrow();
  });
});

function encryptRequestForDesktop(wireExpiresAt = expiresAt) {
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
    new Date(wireExpiresAt).toISOString(),
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
    timezone: "Asia/Shanghai",
    locale: "zh-CN",
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
    expires_at: wireExpiresAt,
    encryption_version: 1,
    nonce: nonce.toString("base64url"),
    ciphertext: Buffer.concat([cipherText, tag]).toString("base64url"),
  });
}

function cipherFor(
  deviceId: string,
  privateKeyBytes: Uint8Array,
  keys: Record<string, string>,
  nonce?: () => Uint8Array,
): DeviceAiJobCipher {
  return new DeviceAiJobCipher({
    keyAgreement: new RawX25519DeviceKeyAgreement({
      deviceId,
      privateKeyBytes,
      resolvePublicKey: resolver(keys),
    }),
    nonce,
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
