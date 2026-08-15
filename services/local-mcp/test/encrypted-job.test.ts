import { describe, expect, it, vi } from "vitest";

import { LiflyAiJobEnvelopeSchema } from "../../../packages/protocol/src/index.js";
import { EncryptedAiJobEngine, RetryableEncryptedAiJobError } from "../src/index.js";

const now = new Date("2026-08-15T10:00:00.000Z");

function requestEnvelope(overrides: Record<string, unknown> = {}) {
  return LiflyAiJobEnvelopeSchema.parse({
    protocol_version: 1,
    job_id: "job-request-1",
    account_id: "account-1",
    source_device_id: "phone-1",
    target_device_id: "desktop-1",
    message_type: "request",
    correlation_id: null,
    idempotency_key: "idem-1",
    expires_at: "2026-08-15T10:10:00.000Z",
    encryption_version: 1,
    nonce: "request-nonce",
    ciphertext: "request-ciphertext",
    ...overrides,
  });
}

describe("EncryptedAiJobEngine", () => {
  it("rejects expired jobs before decryption or execution", async () => {
    const decrypt = vi.fn(async () => ({ secret: true }));
    const execute = vi.fn(async () => ({ result: true }));
    const encrypt = vi.fn(async () => ({
      encryption_version: 1,
      nonce: "result-nonce",
      ciphertext: "result-ciphertext",
    }));
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: { decrypt, encrypt },
      executor: { execute },
      now: () => now,
      createJobId: () => "job-result-expired",
    });

    const outcome = await engine.execute(
      requestEnvelope({ job_id: "expired-job", expires_at: "2026-08-15T09:59:59.000Z" }),
    );

    expect(outcome).toMatchObject({
      status: "expired",
      job_id: "expired-job",
      attempt_count: 0,
      retryable: false,
      deduplicated: false,
    });
    expect(decrypt).not.toHaveBeenCalled();
    expect(execute).not.toHaveBeenCalled();
    expect(encrypt).not.toHaveBeenCalled();
  });

  it("retries a failed execution without duplicating a successful result", async () => {
    const decrypt = vi.fn(async () => ({ private: "payload" }));
    const execute = vi
      .fn()
      .mockRejectedValueOnce(new RetryableEncryptedAiJobError("provider busy"))
      .mockResolvedValueOnce({ result: "recovered" });
    const encrypt = vi.fn(async () => ({
      encryption_version: 1,
      nonce: "result-nonce",
      ciphertext: "result-ciphertext",
    }));
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: { decrypt, encrypt },
      executor: { execute },
      maxAttempts: 3,
      now: () => now,
      createJobId: () => "job-result-retry",
    });
    const request = requestEnvelope({ job_id: "retry-job", idempotency_key: "retry-idem" });

    const failed = await engine.execute(request);
    const recovered = await engine.execute(request);
    const repeated = await engine.execute(request);

    expect(failed).toMatchObject({
      status: "failed",
      job_id: "retry-job",
      attempt_count: 1,
      retryable: true,
      error: "provider busy",
    });
    expect(recovered).toMatchObject({
      status: "succeeded",
      attempt_count: 2,
      retryable: false,
      deduplicated: false,
    });
    expect(repeated).toMatchObject({
      status: "succeeded",
      attempt_count: 2,
      deduplicated: true,
    });
    expect(decrypt).toHaveBeenCalledTimes(2);
    expect(execute).toHaveBeenCalledTimes(2);
    expect(encrypt).toHaveBeenCalledOnce();
  });

  it("coalesces concurrent duplicate delivery into one execution", async () => {
    let releaseExecution!: () => void;
    const executionGate = new Promise<void>((resolve) => {
      releaseExecution = resolve;
    });
    const decrypt = vi.fn(async () => ({ private: "payload" }));
    const execute = vi.fn(async () => {
      await executionGate;
      return { result: "once" };
    });
    const encrypt = vi.fn(async () => ({
      encryption_version: 1,
      nonce: "result-nonce",
      ciphertext: "result-ciphertext",
    }));
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: { decrypt, encrypt },
      executor: { execute },
      now: () => now,
      createJobId: () => "job-result-concurrent",
    });
    const request = requestEnvelope({ job_id: "concurrent-job", idempotency_key: "concurrent-idem" });

    const first = engine.execute(request);
    const repeated = engine.execute(request);
    await vi.waitFor(() => expect(execute).toHaveBeenCalledOnce());
    expect(engine.status("concurrent-job")).toMatchObject({
      status: "running",
      job_id: "concurrent-job",
      attempt_count: 1,
    });
    releaseExecution();
    const [firstOutcome, repeatedOutcome] = await Promise.all([first, repeated]);

    expect(firstOutcome).toMatchObject({ status: "succeeded", deduplicated: false, attempt_count: 1 });
    expect(repeatedOutcome).toMatchObject({ status: "succeeded", deduplicated: true, attempt_count: 1 });
    expect(decrypt).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledOnce();
    expect(encrypt).toHaveBeenCalledOnce();
  });

  it("rejects changed ciphertext when a retry reuses the same idempotency identity", async () => {
    const decrypt = vi.fn(async () => ({ private: "payload" }));
    const execute = vi.fn(async () => {
      throw new RetryableEncryptedAiJobError("temporary failure");
    });
    const encrypt = vi.fn(async () => ({
      encryption_version: 1,
      nonce: "result-nonce",
      ciphertext: "result-ciphertext",
    }));
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: { decrypt, encrypt },
      executor: { execute },
      maxAttempts: 3,
      now: () => now,
    });
    const request = requestEnvelope({ job_id: "bound-job", idempotency_key: "bound-idem" });

    const failed = await engine.execute(request);
    expect(failed).toMatchObject({ status: "failed", retryable: true, attempt_count: 1 });
    await expect(
      engine.execute({ ...request, ciphertext: "different-ciphertext" }),
    ).rejects.toThrow("idempotency conflict");
    expect(decrypt).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledOnce();
    expect(encrypt).not.toHaveBeenCalled();
  });

  it("does not rerun execution when result encryption fails after execution", async () => {
    const decrypt = vi.fn(async () => ({ private: "payload" }));
    const execute = vi.fn(async () => ({ side_effectful_result: true }));
    const encrypt = vi.fn(async () => {
      throw new Error("result encryption failed");
    });
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: { decrypt, encrypt },
      executor: { execute },
      maxAttempts: 3,
      now: () => now,
    });
    const request = requestEnvelope({ job_id: "encrypt-fail-job", idempotency_key: "encrypt-fail-idem" });

    const failed = await engine.execute(request);
    const repeated = await engine.execute(request);

    expect(failed).toMatchObject({
      status: "failed",
      attempt_count: 1,
      retryable: false,
      error: "result encryption failed",
    });
    expect(repeated).toMatchObject({
      status: "failed",
      attempt_count: 1,
      retryable: false,
      deduplicated: true,
    });
    expect(decrypt).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledOnce();
    expect(encrypt).toHaveBeenCalledOnce();
  });

  it("deduplicates a completed request by account, source device, and idempotency key", async () => {
    const decrypt = vi.fn(async () => ({ private: "payload" }));
    const execute = vi.fn(async () => ({ result: "once" }));
    const encrypt = vi.fn(async () => ({
      encryption_version: 1,
      nonce: "result-nonce",
      ciphertext: "result-ciphertext",
    }));
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: { decrypt, encrypt },
      executor: { execute },
      now: () => now,
      createJobId: () => "job-result-deduplicated",
    });
    const request = requestEnvelope();

    const first = await engine.execute(request);
    const repeated = await engine.execute(request);

    expect(first.status).toBe("succeeded");
    expect(repeated).toMatchObject({
      status: "succeeded",
      job_id: request.job_id,
      attempt_count: 1,
      retryable: false,
      deduplicated: true,
      result_envelope: first.result_envelope,
    });
    expect(decrypt).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledOnce();
    expect(encrypt).toHaveBeenCalledOnce();
  });

  it("decrypts, executes, and returns an encrypted result envelope", async () => {
    const decrypt = vi.fn(async () => ({ kind: "opaque-provider-request", prompt: "private" }));
    const execute = vi.fn(async () => ({ actions: [{ type: "memo_create" }] }));
    const encrypt = vi.fn(async () => ({
      encryption_version: 1,
      nonce: "result-nonce",
      ciphertext: "result-ciphertext",
    }));
    const engine = new EncryptedAiJobEngine({
      deviceId: "desktop-1",
      cipher: { decrypt, encrypt },
      executor: { execute },
      now: () => now,
      createJobId: () => "job-result-1",
    });

    const outcome = await engine.execute(requestEnvelope());

    expect(outcome).toMatchObject({
      status: "succeeded",
      job_id: "job-request-1",
      attempt_count: 1,
      retryable: false,
      deduplicated: false,
    });
    expect(outcome.result_envelope).toMatchObject({
      job_id: "job-result-1",
      account_id: "account-1",
      source_device_id: "desktop-1",
      target_device_id: "phone-1",
      message_type: "result",
      correlation_id: "job-request-1",
      idempotency_key: "idem-1",
      nonce: "result-nonce",
      ciphertext: "result-ciphertext",
    });
    expect(decrypt).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledWith(
      { kind: "opaque-provider-request", prompt: "private" },
      expect.objectContaining({ attempt: 1 }),
    );
    expect(encrypt).toHaveBeenCalledWith(
      { actions: [{ type: "memo_create" }] },
      expect.objectContaining({ target_device_id: "phone-1" }),
    );
  });
});
