import { z } from "zod";

export const LiflyDeviceProtocolVersion = 1 as const;

export const LiflyDeviceCapabilitySchema = z.enum([
  "local_ai",
  "local_mcp",
  "background_executor",
]);
export type LiflyDeviceCapability = z.infer<typeof LiflyDeviceCapabilitySchema>;

export const LiflyDeviceTrustStateSchema = z.enum(["pending", "trusted", "revoked"]);
export type LiflyDeviceTrustState = z.infer<typeof LiflyDeviceTrustStateSchema>;

export const LiflyDeviceCapabilityReportSchema = z.object({
  protocol_version: z.literal(LiflyDeviceProtocolVersion),
  capabilities: z.array(LiflyDeviceCapabilitySchema),
  supported_tools: z.array(z.string().min(1)).default([]),
});
export type LiflyDeviceCapabilityReport = z.infer<typeof LiflyDeviceCapabilityReportSchema>;

export const LiflyDeviceDescriptorSchema = z.object({
  device_id: z.string().min(1),
  account_id: z.string().min(1),
  display_name: z.string().min(1),
  platform: z.string().min(1),
  public_key: z.string().min(1),
  trust_state: LiflyDeviceTrustStateSchema,
  capability_report: LiflyDeviceCapabilityReportSchema,
  is_default_compute_node: z.boolean(),
});
export type LiflyDeviceDescriptor = z.infer<typeof LiflyDeviceDescriptorSchema>;
