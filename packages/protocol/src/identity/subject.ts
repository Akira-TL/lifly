import { z } from "zod";

export const LiflyIdentityContractVersion = 1 as const;

export const LiflyAuthenticatedSubjectSchema = z.object({
  account_id: z.string().min(1),
  user_id: z.string().min(1),
  device_id: z.string().min(1).optional().nullable(),
}).superRefine((subject, context) => {
  if (subject.account_id !== subject.user_id) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["user_id"],
      message: "v0.9.0 business user_id must equal authenticated account_id",
    });
  }
});

export type LiflyAuthenticatedSubject = z.infer<typeof LiflyAuthenticatedSubjectSchema>;
