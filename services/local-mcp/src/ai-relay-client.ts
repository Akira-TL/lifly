import {
  LiflyAiJobEnvelopeSchema,
  type LiflyAiJobEnvelope,
} from "../../../packages/protocol/src/index.js";

export type AccessTokenProvider = () => Promise<string> | string;

export interface AiRelayClient {
  nextJob(): Promise<LiflyAiJobEnvelope | null>;
  submitResult(envelope: LiflyAiJobEnvelope): Promise<LiflyAiJobEnvelope>;
  failJob(jobId: string): Promise<void>;
  resolveDevicePublicKey(deviceId: string): Promise<string>;
}

export interface HttpAiRelayClientOptions {
  apiBaseUrl: string;
  accessToken: AccessTokenProvider;
  fetch?: typeof fetch;
}

export class HttpAiRelayClient implements AiRelayClient {
  private readonly baseUrl: string;
  private readonly accessToken: AccessTokenProvider;
  private readonly fetchImpl: typeof fetch;
  private readonly publicKeys = new Map<
    string,
    { keyVersion: number; publicKey: string }
  >();

  constructor(options: HttpAiRelayClientOptions) {
    this.baseUrl = options.apiBaseUrl.replace(/\/+$/u, "");
    this.accessToken = options.accessToken;
    this.fetchImpl = options.fetch ?? globalThis.fetch;
  }

  async nextJob(): Promise<LiflyAiJobEnvelope | null> {
    const response = await this.request("/ai/relay/jobs/next", { method: "GET" });
    if (response.status === 204) return null;
    const payload = await response.json();
    if (payload === null) return null;
    return LiflyAiJobEnvelopeSchema.parse(payload);
  }

  async submitResult(envelope: LiflyAiJobEnvelope): Promise<LiflyAiJobEnvelope> {
    const response = await this.request("/ai/relay/results", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(envelope),
    });
    return LiflyAiJobEnvelopeSchema.parse(await response.json());
  }

  async failJob(jobId: string): Promise<void> {
    await this.request(`/ai/relay/jobs/${encodeURIComponent(jobId)}/fail`, {
      method: "POST",
    });
  }

  async resolveDevicePublicKey(deviceId: string): Promise<string> {
    // Device keys are routing/security state, not immutable configuration. Fetch
    // the current Registry record on every derivation so a long-lived Compute
    // Node observes rotations and revocations instead of pinning stale key bytes.
    const response = await this.request("/devices", { method: "GET" });
    const payload = (await response.json()) as unknown;
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      throw new Error("Device Registry response must be an object");
    }
    const devices = (payload as Record<string, unknown>).devices;
    if (!Array.isArray(devices)) {
      throw new Error("Device Registry response has no devices list");
    }
    for (const item of devices) {
      if (!item || typeof item !== "object" || Array.isArray(item)) continue;
      const record = item as Record<string, unknown>;
      if (record.device_id !== deviceId || record.trust_state !== "trusted") continue;
      const publicKey = record.public_key;
      const keyVersion = record.key_version;
      if (
        typeof publicKey !== "string"
        || publicKey.length === 0
        || typeof keyVersion !== "number"
        || !Number.isInteger(keyVersion)
        || keyVersion < 1
      ) {
        throw new Error(`Trusted device key record is invalid: ${deviceId}`);
      }
      const cached = this.publicKeys.get(deviceId);
      if (cached && keyVersion < cached.keyVersion) {
        throw new Error(
          `Device Registry key_version moved backwards for ${deviceId}: ${keyVersion} < ${cached.keyVersion}`,
        );
      }
      if (
        cached
        && keyVersion === cached.keyVersion
        && publicKey !== cached.publicKey
      ) {
        throw new Error(
          `Device public key changed without key_version rotation: ${deviceId}`,
        );
      }
      this.publicKeys.set(deviceId, { keyVersion, publicKey });
      return publicKey;
    }
    throw new Error(`Trusted device public key unavailable: ${deviceId}`);
  }

  private async request(path: string, init: RequestInit): Promise<Response> {
    const token = await this.accessToken();
    if (!token) throw new Error("Compute Node relay access token is unavailable");
    const headers = new Headers(init.headers);
    headers.set("authorization", `Bearer ${token}`);
    const response = await this.fetchImpl(`${this.baseUrl}${path}`, {
      ...init,
      headers,
    });
    if (!response.ok) {
      throw new Error(`Compute Node relay request failed: HTTP ${response.status}`);
    }
    return response;
  }
}
