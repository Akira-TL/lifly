import { randomUUID } from "node:crypto";

import {
  LiflyAiJobEnvelopeSchema,
  LiflyAiJobProtocolVersion,
  type LiflyAiJobEnvelope,
} from "../../../packages/protocol/src/index.js";

export class RetryableEncryptedAiJobError extends Error {
  override readonly name = "RetryableEncryptedAiJobError";
}

export interface EncryptedAiJobCiphertext {
  encryption_version: number;
  nonce: string;
  ciphertext: string;
}

export interface EncryptedAiJobCipher {
  decrypt(envelope: LiflyAiJobEnvelope): Promise<unknown>;
  encrypt(payload: unknown, context: EncryptedAiJobResultContext): Promise<EncryptedAiJobCiphertext>;
}

export interface DecryptedAiJobExecutionContext {
  request: LiflyAiJobEnvelope;
  attempt: number;
}

export interface DecryptedAiJobExecutor {
  execute(payload: unknown, context: DecryptedAiJobExecutionContext): Promise<unknown>;
}

export interface EncryptedAiJobResultContext {
  request: LiflyAiJobEnvelope;
  result_job_id: string;
  source_device_id: string;
  target_device_id: string;
  expires_at: string;
}

export type EncryptedAiJobStatus = "running" | "succeeded" | "failed" | "expired";

export type EncryptedAiJobFailureStage = "decrypt" | "execute" | "encrypt";

export interface EncryptedAiJobExecutionOutcome {
  status: EncryptedAiJobStatus;
  job_id: string;
  attempt_count: number;
  retryable: boolean;
  deduplicated: boolean;
  result_envelope?: LiflyAiJobEnvelope;
  failure_stage?: EncryptedAiJobFailureStage;
  error?: string;
}

export interface EncryptedAiJobEngineOptions {
  deviceId: string;
  cipher: EncryptedAiJobCipher;
  executor: DecryptedAiJobExecutor;
  maxAttempts?: number;
  now?: () => Date;
  createJobId?: () => string;
}

interface StoredAiJobOutcome {
  jobId: string;
  requestFingerprint: string;
  outcome: EncryptedAiJobExecutionOutcome;
}

interface AiJobAttemptState {
  jobId: string;
  requestFingerprint: string;
  count: number;
}

interface InFlightAiJob {
  jobId: string;
  requestFingerprint: string;
  promise: Promise<EncryptedAiJobExecutionOutcome>;
}

export class EncryptedAiJobEngine {
  private readonly deviceId: string;
  private readonly cipher: EncryptedAiJobCipher;
  private readonly executor: DecryptedAiJobExecutor;
  private readonly maxAttempts: number;
  private readonly now: () => Date;
  private readonly createJobId: () => string;
  private readonly attempts = new Map<string, AiJobAttemptState>();
  private readonly completed = new Map<string, StoredAiJobOutcome>();
  private readonly inFlight = new Map<string, InFlightAiJob>();
  private readonly latestByJobId = new Map<string, EncryptedAiJobExecutionOutcome>();

  constructor(options: EncryptedAiJobEngineOptions) {
    this.deviceId = options.deviceId;
    this.cipher = options.cipher;
    this.executor = options.executor;
    this.maxAttempts = options.maxAttempts ?? 3;
    if (!Number.isInteger(this.maxAttempts) || this.maxAttempts < 1) {
      throw new Error("Encrypted AI job maxAttempts must be a positive integer");
    }
    this.now = options.now ?? (() => new Date());
    this.createJobId = options.createJobId ?? (() => randomUUID());
  }

  async execute(rawEnvelope: unknown): Promise<EncryptedAiJobExecutionOutcome> {
    const request = LiflyAiJobEnvelopeSchema.parse(rawEnvelope);
    this.validateRequest(request);

    const idempotencyKey = this.idempotencyKey(request);
    const requestFingerprint = this.requestFingerprint(request);

    const existing = this.completed.get(idempotencyKey);
    if (existing) {
      this.assertSameRequest(request, requestFingerprint, existing.jobId, existing.requestFingerprint);
      return { ...existing.outcome, deduplicated: true };
    }

    const active = this.inFlight.get(idempotencyKey);
    if (active) {
      this.assertSameRequest(request, requestFingerprint, active.jobId, active.requestFingerprint);
      const outcome = await active.promise;
      return { ...outcome, deduplicated: true };
    }

    const previousAttempt = this.attempts.get(idempotencyKey);
    if (previousAttempt) {
      this.assertSameRequest(
        request,
        requestFingerprint,
        previousAttempt.jobId,
        previousAttempt.requestFingerprint,
      );
    }

    if (this.isExpired(request)) {
      const outcome: EncryptedAiJobExecutionOutcome = {
        status: "expired",
        job_id: request.job_id,
        attempt_count: previousAttempt?.count ?? 0,
        retryable: false,
        deduplicated: false,
      };
      this.storeCompleted(idempotencyKey, request, requestFingerprint, outcome);
      return outcome;
    }

    const attempt = (previousAttempt?.count ?? 0) + 1;
    this.attempts.set(idempotencyKey, {
      jobId: request.job_id,
      requestFingerprint,
      count: attempt,
    });
    this.latestByJobId.set(request.job_id, {
      status: "running",
      job_id: request.job_id,
      attempt_count: attempt,
      retryable: false,
      deduplicated: false,
    });

    const promise = this.runAttempt(request, idempotencyKey, requestFingerprint, attempt);
    this.inFlight.set(idempotencyKey, {
      jobId: request.job_id,
      requestFingerprint,
      promise,
    });

    try {
      return await promise;
    } finally {
      const current = this.inFlight.get(idempotencyKey);
      if (current?.promise === promise) this.inFlight.delete(idempotencyKey);
    }
  }

  status(jobId: string): EncryptedAiJobExecutionOutcome | null {
    const outcome = this.latestByJobId.get(jobId);
    return outcome ? { ...outcome } : null;
  }

  private async runAttempt(
    request: LiflyAiJobEnvelope,
    idempotencyKey: string,
    requestFingerprint: string,
    attempt: number,
  ): Promise<EncryptedAiJobExecutionOutcome> {
    let plaintext: unknown;
    try {
      plaintext = await this.cipher.decrypt(request);
    } catch (error) {
      const retryable = this.isExplicitlyRetryable(error)
        && attempt < this.maxAttempts
        && !this.isExpired(request);
      return this.storeFailure(
        idempotencyKey,
        request,
        requestFingerprint,
        attempt,
        "decrypt",
        error,
        retryable,
      );
    }

    let resultPayload: unknown;
    try {
      resultPayload = await this.executor.execute(plaintext, { request, attempt });
    } catch (error) {
      const retryable = this.isExplicitlyRetryable(error)
        && attempt < this.maxAttempts
        && !this.isExpired(request);
      return this.storeFailure(
        idempotencyKey,
        request,
        requestFingerprint,
        attempt,
        "execute",
        error,
        retryable,
      );
    }

    try {
      const resultEnvelope = await this.encryptResult(request, resultPayload);
      const outcome: EncryptedAiJobExecutionOutcome = {
        status: "succeeded",
        job_id: request.job_id,
        attempt_count: attempt,
        retryable: false,
        deduplicated: false,
        result_envelope: resultEnvelope,
      };
      this.storeCompleted(idempotencyKey, request, requestFingerprint, outcome);
      return outcome;
    } catch (error) {
      // Execution has already succeeded. Re-running it to recover an encryption
      // failure could duplicate Local Core side effects, so this phase is terminal.
      return this.storeFailure(
        idempotencyKey,
        request,
        requestFingerprint,
        attempt,
        "encrypt",
        error,
        false,
      );
    }
  }

  private async encryptResult(request: LiflyAiJobEnvelope, resultPayload: unknown): Promise<LiflyAiJobEnvelope> {
    const resultJobId = this.createJobId();
    const resultContext: EncryptedAiJobResultContext = {
      request,
      result_job_id: resultJobId,
      source_device_id: this.deviceId,
      target_device_id: request.source_device_id,
      expires_at: request.expires_at,
    };
    const encrypted = await this.cipher.encrypt(resultPayload, resultContext);
    return LiflyAiJobEnvelopeSchema.parse({
      protocol_version: LiflyAiJobProtocolVersion,
      job_id: resultJobId,
      account_id: request.account_id,
      source_device_id: this.deviceId,
      target_device_id: request.source_device_id,
      message_type: "result",
      correlation_id: request.job_id,
      idempotency_key: request.idempotency_key,
      expires_at: request.expires_at,
      encryption_version: encrypted.encryption_version,
      nonce: encrypted.nonce,
      ciphertext: encrypted.ciphertext,
    });
  }

  private storeFailure(
    idempotencyKey: string,
    request: LiflyAiJobEnvelope,
    requestFingerprint: string,
    attempt: number,
    failureStage: EncryptedAiJobFailureStage,
    error: unknown,
    retryable: boolean,
  ): EncryptedAiJobExecutionOutcome {
    const outcome: EncryptedAiJobExecutionOutcome = {
      status: "failed",
      job_id: request.job_id,
      attempt_count: attempt,
      retryable,
      deduplicated: false,
      failure_stage: failureStage,
      error: this.errorMessage(error),
    };
    if (!retryable) {
      this.storeCompleted(idempotencyKey, request, requestFingerprint, outcome);
    } else {
      this.latestByJobId.set(request.job_id, outcome);
    }
    return outcome;
  }

  private storeCompleted(
    idempotencyKey: string,
    request: LiflyAiJobEnvelope,
    requestFingerprint: string,
    outcome: EncryptedAiJobExecutionOutcome,
  ): void {
    this.completed.set(idempotencyKey, {
      jobId: request.job_id,
      requestFingerprint,
      outcome,
    });
    this.latestByJobId.set(request.job_id, outcome);
  }

  private validateRequest(request: LiflyAiJobEnvelope): void {
    if (request.message_type !== "request") {
      throw new Error(`Encrypted AI job must be a request envelope: ${request.job_id}`);
    }
    if (request.target_device_id !== this.deviceId) {
      throw new Error(
        `Encrypted AI job target mismatch: expected ${this.deviceId}, received ${request.target_device_id}`,
      );
    }
  }

  private assertSameRequest(
    request: LiflyAiJobEnvelope,
    requestFingerprint: string,
    boundJobId: string,
    boundFingerprint: string,
  ): void {
    if (boundJobId !== request.job_id || boundFingerprint !== requestFingerprint) {
      throw new Error(
        `Encrypted AI job idempotency conflict: ${request.idempotency_key} is already bound to another request`,
      );
    }
  }

  private isExpired(request: LiflyAiJobEnvelope): boolean {
    return Date.parse(request.expires_at) <= this.now().getTime();
  }

  private isExplicitlyRetryable(error: unknown): boolean {
    return error instanceof RetryableEncryptedAiJobError;
  }

  private idempotencyKey(request: LiflyAiJobEnvelope): string {
    return JSON.stringify([request.account_id, request.source_device_id, request.idempotency_key]);
  }

  private requestFingerprint(request: LiflyAiJobEnvelope): string {
    return JSON.stringify([
      request.protocol_version,
      request.job_id,
      request.account_id,
      request.source_device_id,
      request.target_device_id,
      request.message_type,
      request.correlation_id ?? null,
      request.idempotency_key,
      request.expires_at,
      request.encryption_version,
      request.nonce,
      request.ciphertext,
    ]);
  }

  private errorMessage(error: unknown): string {
    return error instanceof Error ? error.message : String(error);
  }
}
