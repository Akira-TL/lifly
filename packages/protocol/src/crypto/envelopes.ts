import { z } from "zod";

export const LiflyEncryptedEntitySchemaVersion = 1 as const;
export const LiflyPasswordKeyEnvelopeSchemaVersion = 1 as const;

export const LiflyEncryptedEntityLifecycleStatusSchema = z.enum(["active", "tombstone"]);
export type LiflyEncryptedEntityLifecycleStatus = z.infer<
  typeof LiflyEncryptedEntityLifecycleStatusSchema
>;

export const LiflyEncryptedEntityEnvelopeSchema = z.object({
  schema_version: z.literal(LiflyEncryptedEntitySchemaVersion),
  id: z.string().min(1),
  user_id: z.string().min(1),
  entity_type: z.string().min(1),
  revision: z.number().int().positive(),
  lifecycle_status: LiflyEncryptedEntityLifecycleStatusSchema,
  updated_at: z.string().datetime({ offset: true }),
  key_version: z.number().int().positive(),
  encryption_version: z.number().int().positive(),
  nonce: z.string().min(1),
  ciphertext: z.string().min(1),
});
export type LiflyEncryptedEntityEnvelope = z.infer<typeof LiflyEncryptedEntityEnvelopeSchema>;

export const LiflyPasswordKeyEnvelopeSchema = z.object({
  schema_version: z.literal(LiflyPasswordKeyEnvelopeSchemaVersion),
  account_id: z.string().min(1),
  key_version: z.number().int().positive(),
  encryption_version: z.number().int().positive(),
  nonce: z.string().min(1),
  ciphertext: z.string().min(1),
});
export type LiflyPasswordKeyEnvelope = z.infer<typeof LiflyPasswordKeyEnvelopeSchema>;
