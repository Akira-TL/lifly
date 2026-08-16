import { describe, expect, it, vi } from "vitest";

import { LiflyAiJobEnvelopeSchema } from "../../../packages/protocol/src/index.js";
import type { AiRelayClient } from "../src/ai-relay-client.js";
import type { EncryptedAiJobEngine } from "../src/encrypted-job-engine.js";
import { EncryptedAiRelayWorker } from "../src/encrypted-relay-worker.js";

const request = LiflyAiJobEnvelopeSchema.parse({
  protocol_version: 1,
  job_id: "job-terminal-failure",
  account_id: "account-1",
  source_device_id: "web-1",
  target_device_id: "desktop-1",
  message_type: "request",
  correlation_id: null,
  idempotency_key: "idem-terminal-failure",
  expires_at: "2026-08-16T16:30:00.000Z",
  encryption_version: 1,
  nonce: "nonce",
  ciphertext: "ciphertext",
});

describe("EncryptedAiRelayWorker", () => {
  it("acknowledges a terminal failure so the relay does not redeliver it", async () => {
    const failJob = vi.fn(async () => undefined);
    const submitResult = vi.fn();
    const relay: AiRelayClient = {
      nextJob: vi.fn(async () => request),
      submitResult,
      failJob,
      resolveDevicePublicKey: vi.fn(async () => "public-key"),
    };
    const jobs = {
      execute: vi.fn(async () => ({
        status: "failed" as const,
        job_id: request.job_id,
        attempt_count: 1,
        retryable: false,
        deduplicated: false,
        failure_stage: "decrypt" as const,
        error: "unable to decrypt",
      })),
    } as unknown as EncryptedAiJobEngine;

    const result = await new EncryptedAiRelayWorker(relay, jobs).runOnce();

    expect(result.status).toBe("processed");
    expect(failJob).toHaveBeenCalledOnce();
    expect(failJob).toHaveBeenCalledWith(request.job_id);
    expect(submitResult).not.toHaveBeenCalled();
  });

  it("leaves retryable failures leased for a later retry", async () => {
    const failJob = vi.fn(async () => undefined);
    const relay: AiRelayClient = {
      nextJob: vi.fn(async () => request),
      submitResult: vi.fn(),
      failJob,
      resolveDevicePublicKey: vi.fn(async () => "public-key"),
    };
    const jobs = {
      execute: vi.fn(async () => ({
        status: "failed" as const,
        job_id: request.job_id,
        attempt_count: 1,
        retryable: true,
        deduplicated: false,
        failure_stage: "execute" as const,
        error: "provider busy",
      })),
    } as unknown as EncryptedAiJobEngine;

    await new EncryptedAiRelayWorker(relay, jobs).runOnce();

    expect(failJob).not.toHaveBeenCalled();
  });
});
