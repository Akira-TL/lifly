import type { AiRelayClient } from "./ai-relay-client.js";
import type {
  EncryptedAiJobEngine,
  EncryptedAiJobExecutionOutcome,
} from "./encrypted-job-engine.js";

export type EncryptedRelayWorkerStatus =
  | { status: "idle" }
  | { status: "processed"; outcome: EncryptedAiJobExecutionOutcome };

export class EncryptedAiRelayWorker {
  constructor(
    private readonly relay: AiRelayClient,
    private readonly jobs: EncryptedAiJobEngine,
  ) {}

  async runOnce(): Promise<EncryptedRelayWorkerStatus> {
    const request = await this.relay.nextJob();
    if (request === null) return { status: "idle" };
    const outcome = await this.jobs.execute(request);
    if (outcome.status === "succeeded" && outcome.result_envelope) {
      await this.relay.submitResult(outcome.result_envelope);
    }
    return { status: "processed", outcome };
  }
}
