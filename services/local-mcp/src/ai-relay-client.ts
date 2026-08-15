import {
  LiflyAiJobEnvelopeSchema,
  type LiflyAiJobEnvelope,
} from "../../../packages/protocol/src/index.js";

export type AccessTokenProvider = () => Promise<string> | string;

export interface AiRelayClient {
  nextJob(): Promise<LiflyAiJobEnvelope | null>;
  submitResult(envelope: LiflyAiJobEnvelope): Promise<LiflyAiJobEnvelope>;
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
  private readonly publicKeys = new Map<string, string>();

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

  async resolveDevicePublicKey(deviceId: string): Promise<string> {
    const cached = this.publicKeys.get(deviceId);
    if (cached) return cached;
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
      const id = record.device_id;
      const publicKey = record.public_key;
      const trustState = record.trust_state;
      if (
        typeof id === "string"
        && typeof publicKey === "string"
        && publicKey.length > 0
        && trustState === "trusted"
      ) {
        this.publicKeys.set(id, publicKey);
      }
    }
    const resolved = this.publicKeys.get(deviceId);
    if (!resolved) {
      throw new Error(`Trusted device public key unavailable: ${deviceId}`);
    }
    return resolved;
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
