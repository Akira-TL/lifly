import {
  LiflyAiJobProtocolVersion,
  type LiflyAiJobEnvelope,
} from "../../../packages/protocol/src/index.js";
import type {
  EncryptedAiJobCipher,
  EncryptedAiJobCiphertext,
  EncryptedAiJobResultContext,
} from "./encrypted-job-engine.js";

const EncryptionVersion = 1;
const KeyDomain = "lifly/device-ai-job/key/v1";
const AadDomain = "lifly/device-ai-job/aad/v1";
const X25519Pkcs8Prefix = hex("302e020100300506032b656e04220420");

export type DevicePublicKeyResolver = (deviceId: string) => Promise<string>;

/**
 * Cryptographic seam consumed by the AI Job cipher.
 *
 * Implementations keep Device private-key representation internal. Native
 * bootstrap may use [RawX25519DeviceKeyAgreement], while a future hardware or
 * non-extractable WebCrypto adapter can implement the same interface without
 * ever returning private key bytes to the cipher.
 */
export interface DeviceKeyAgreement {
  readonly deviceId: string;
  deriveSharedSecret(remoteDeviceId: string): Promise<ArrayBuffer>;
}

export interface RawX25519DeviceKeyAgreementOptions {
  deviceId: string;
  privateKeyBytes: Uint8Array;
  resolvePublicKey: DevicePublicKeyResolver;
}

export class RawX25519DeviceKeyAgreement implements DeviceKeyAgreement {
  readonly deviceId: string;
  private readonly privateKeyBytes: Uint8Array;
  private readonly resolvePublicKey: DevicePublicKeyResolver;

  constructor(options: RawX25519DeviceKeyAgreementOptions) {
    if (options.privateKeyBytes.length !== 32) {
      throw new Error("Device X25519 private key must be 32 bytes");
    }
    this.deviceId = options.deviceId;
    this.privateKeyBytes = Uint8Array.from(options.privateKeyBytes);
    this.resolvePublicKey = options.resolvePublicKey;
  }

  async deriveSharedSecret(remoteDeviceId: string): Promise<ArrayBuffer> {
    const privateKey = await globalThis.crypto.subtle.importKey(
      "pkcs8",
      asArrayBuffer(concat(X25519Pkcs8Prefix, this.privateKeyBytes)),
      { name: "X25519" },
      false,
      ["deriveBits"],
    );
    const remoteRaw = decodeBase64(await this.resolvePublicKey(remoteDeviceId));
    if (remoteRaw.length !== 32) {
      throw new Error("Device X25519 public key must be 32 bytes");
    }
    const publicKey = await globalThis.crypto.subtle.importKey(
      "raw",
      asArrayBuffer(remoteRaw),
      { name: "X25519" },
      false,
      [],
    );
    return globalThis.crypto.subtle.deriveBits(
      { name: "X25519", public: publicKey },
      privateKey,
      256,
    );
  }
}

export interface DeviceAiJobCipherOptions {
  keyAgreement: DeviceKeyAgreement;
  nonce?: () => Uint8Array;
}

export class DeviceAiJobCipher implements EncryptedAiJobCipher {
  private readonly keyAgreement: DeviceKeyAgreement;
  private readonly nonce: () => Uint8Array;

  constructor(options: DeviceAiJobCipherOptions) {
    this.keyAgreement = options.keyAgreement;
    this.nonce =
      options.nonce ??
      (() => {
        const value = new Uint8Array(12);
        globalThis.crypto.getRandomValues(value);
        return value;
      });
  }

  async decrypt(envelope: LiflyAiJobEnvelope): Promise<unknown> {
    if (envelope.encryption_version !== EncryptionVersion) {
      throw new Error(
        `Unsupported device AI job encryption version: ${envelope.encryption_version}`,
      );
    }
    if (envelope.target_device_id !== this.keyAgreement.deviceId) {
      throw new Error(
        `Device ${this.keyAgreement.deviceId} cannot decrypt AI job for ${envelope.target_device_id}`,
      );
    }
    const contextValue = requestContext(envelope);
    const key = await this.deriveKey(envelope.source_device_id, contextValue);
    const nonce = decodeBase64Url(envelope.nonce);
    if (nonce.length !== 12) throw new Error("Device AI job nonce must be 12 bytes");
    const sealed = decodeBase64Url(envelope.ciphertext);
    if (sealed.length <= 16) throw new Error("Device AI job ciphertext is truncated");
    const clear = await globalThis.crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: asArrayBuffer(nonce),
        additionalData: asArrayBuffer(aad(contextValue)),
        tagLength: 128,
      },
      key,
      asArrayBuffer(sealed),
    );
    return JSON.parse(new TextDecoder().decode(clear)) as unknown;
  }

  async encrypt(
    payload: unknown,
    result: EncryptedAiJobResultContext,
  ): Promise<EncryptedAiJobCiphertext> {
    if (result.source_device_id !== this.keyAgreement.deviceId) {
      throw new Error(
        `Device ${this.keyAgreement.deviceId} cannot encrypt AI result as ${result.source_device_id}`,
      );
    }
    const contextValue = resultContext(result);
    const key = await this.deriveKey(result.target_device_id, contextValue);
    const nonce = Uint8Array.from(this.nonce());
    if (nonce.length !== 12) throw new Error("Device AI job nonce must be 12 bytes");
    const clear = new TextEncoder().encode(JSON.stringify(payload));
    const sealed = await globalThis.crypto.subtle.encrypt(
      {
        name: "AES-GCM",
        iv: asArrayBuffer(nonce),
        additionalData: asArrayBuffer(aad(contextValue)),
        tagLength: 128,
      },
      key,
      asArrayBuffer(clear),
    );
    return {
      encryption_version: EncryptionVersion,
      nonce: encodeBase64Url(nonce),
      ciphertext: encodeBase64Url(new Uint8Array(sealed)),
    };
  }

  private async deriveKey(
    deviceId: string,
    contextValue: readonly unknown[],
  ): Promise<CryptoKey> {
    const shared = await this.keyAgreement.deriveSharedSecret(deviceId);
    const sharedKey = await globalThis.crypto.subtle.importKey(
      "raw",
      shared,
      "HKDF",
      false,
      ["deriveKey"],
    );
    return globalThis.crypto.subtle.deriveKey(
      {
        name: "HKDF",
        hash: "SHA-256",
        salt: asArrayBuffer(
          new TextEncoder().encode(`${KeyDomain}/${String(contextValue[1])}`),
        ),
        info: asArrayBuffer(new TextEncoder().encode(JSON.stringify(contextValue))),
      },
      sharedKey,
      { name: "AES-GCM", length: 256 },
      false,
      ["encrypt", "decrypt"],
    );
  }
}

function requestContext(envelope: LiflyAiJobEnvelope): readonly unknown[] {
  return context(
    envelope.account_id,
    envelope.source_device_id,
    envelope.target_device_id,
    envelope.message_type,
    envelope.correlation_id ?? null,
    envelope.job_id,
    envelope.idempotency_key,
    envelope.expires_at,
  );
}

function resultContext(result: EncryptedAiJobResultContext): readonly unknown[] {
  return context(
    result.request.account_id,
    result.source_device_id,
    result.target_device_id,
    "result",
    result.request.job_id,
    result.result_job_id,
    result.request.idempotency_key,
    result.expires_at,
  );
}

function context(
  accountId: string,
  sourceDeviceId: string,
  targetDeviceId: string,
  messageType: string,
  correlationId: string | null,
  jobId: string,
  idempotencyKey: string,
  expiresAt: string,
): readonly unknown[] {
  return [
    KeyDomain,
    accountId,
    sourceDeviceId,
    targetDeviceId,
    messageType,
    correlationId,
    jobId,
    idempotencyKey,
    new Date(expiresAt).toISOString(),
    LiflyAiJobProtocolVersion,
    EncryptionVersion,
  ];
}

function aad(contextValue: readonly unknown[]): Uint8Array {
  return new TextEncoder().encode(
    JSON.stringify([AadDomain, ...contextValue.slice(1)]),
  );
}

function asArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.length);
  copy.set(bytes);
  return copy.buffer;
}

function concat(left: Uint8Array, right: Uint8Array): Uint8Array {
  const result = new Uint8Array(left.length + right.length);
  result.set(left, 0);
  result.set(right, left.length);
  return result;
}

function hex(value: string): Uint8Array {
  if (value.length % 2 !== 0) throw new Error("Invalid hex string");
  const output = new Uint8Array(value.length / 2);
  for (let index = 0; index < output.length; index += 1) {
    output[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return output;
}

function encodeBase64Url(bytes: Uint8Array): string {
  return encodeBase64(bytes).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/u, "");
}

function decodeBase64Url(value: string): Uint8Array {
  return decodeBase64(value.replaceAll("-", "+").replaceAll("_", "/"));
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function decodeBase64(value: string): Uint8Array {
  const padding = (4 - (value.length % 4)) % 4;
  const binary = atob(`${value}${"=".repeat(padding)}`);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}
