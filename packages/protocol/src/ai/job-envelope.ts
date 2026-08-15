import { z } from "zod";

export const LiflyAiJobProtocolVersion = 1 as const;

export const LiflyAiJobMessageTypeSchema = z.enum(["request", "result"]);
export type LiflyAiJobMessageType = z.infer<typeof LiflyAiJobMessageTypeSchema>;

export const LiflyAiJobEnvelopeSchema = z.object({
  protocol_version: z.literal(LiflyAiJobProtocolVersion),
  job_id: z.string().min(1),
  account_id: z.string().min(1),
  source_device_id: z.string().min(1),
  target_device_id: z.string().min(1),
  message_type: LiflyAiJobMessageTypeSchema,
  correlation_id: z.string().min(1).optional().nullable(),
  idempotency_key: z.string().min(1),
  expires_at: z.string().datetime({ offset: true }),
  encryption_version: z.number().int().positive(),
  nonce: z.string().min(1),
  ciphertext: z.string().min(1),
});
export type LiflyAiJobEnvelope = z.infer<typeof LiflyAiJobEnvelopeSchema>;
