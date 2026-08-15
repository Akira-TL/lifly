import {
  localMcpContext,
  type LocalCaptureAction,
  type LocalCoreBridge,
} from "../../../packages/local-core/src/index.js";
import type {
  DecryptedAiJobExecutionContext,
  DecryptedAiJobExecutor,
} from "./encrypted-job-engine.js";

export interface ComputeNodePlanRequest {
  schema_version: 1;
  operation: "plan";
  text: string;
  asset_ids: string[];
}

export class LocalCoreComputeNodePlanner implements DecryptedAiJobExecutor {
  constructor(
    private readonly core: LocalCoreBridge,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async execute(payload: unknown, _context: DecryptedAiJobExecutionContext): Promise<unknown> {
    const request = parseComputeNodePlanRequest(payload);
    if (request.asset_ids.length > 0) {
      throw new Error(
        "Desktop Local MCP capture parser does not yet accept attachment content; encrypted AI Job was not executed",
      );
    }
    const session = await this.core.captureParse(
      {
        text: request.text,
        timezone: "Asia/Shanghai",
        locale: "zh-CN",
      },
      localMcpContext("capture_parse"),
    );
    return {
      schema_version: 1,
      actions: session.actions.map((action) => strictCandidateAction(action, this.now)),
    };
  }
}

export function parseComputeNodePlanRequest(payload: unknown): ComputeNodePlanRequest {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("Encrypted AI Job plaintext must be an object");
  }
  const value = payload as Record<string, unknown>;
  if (value.schema_version !== 1 || value.operation !== "plan") {
    throw new Error("Unsupported encrypted AI Job plan schema");
  }
  if (typeof value.text !== "string" || value.text.trim().length === 0) {
    throw new Error("Encrypted AI Job plan text must be non-empty");
  }
  const assetIds = value.asset_ids ?? [];
  if (!Array.isArray(assetIds) || assetIds.some((item) => typeof item !== "string" || item.length === 0)) {
    throw new Error("Encrypted AI Job asset_ids must be a string list");
  }
  return {
    schema_version: 1,
    operation: "plan",
    text: value.text.trim(),
    asset_ids: assetIds as string[],
  };
}

function strictCandidateAction(
  action: LocalCaptureAction,
  now: () => Date,
): Record<string, unknown> {
  const confidence = requireConfidence(action.confidence);
  const payload = action.payload;
  switch (action.type) {
    case "memo_create":
      return {
        type: action.type,
        payload: {
          type: payload.type === "journal" ? "journal" : "memo",
          content_markdown: requireString(payload.content_markdown, "memo content_markdown"),
          ...(typeof payload.mood === "string" && payload.mood.length > 0
            ? { mood: payload.mood }
            : {}),
        },
        confidence,
      };
    case "task_create": {
      const priority = ["low", "normal", "high", "urgent"].includes(String(payload.priority))
        ? String(payload.priority)
        : "normal";
      return {
        type: action.type,
        payload: {
          title: requireString(payload.title, "task title"),
          ...(typeof payload.remind_at === "string" && payload.remind_at.length > 0
            ? { remind_at: payload.remind_at }
            : {}),
          priority,
        },
        confidence,
      };
    }
    case "expense_create": {
      if (typeof payload.amount !== "number" || !Number.isFinite(payload.amount) || payload.amount <= 0) {
        throw new Error("Local Core expense candidate amount must be positive");
      }
      const direction = payload.direction === "income" ? "income" : "expense";
      const currency =
        typeof payload.currency === "string" && payload.currency.length === 3
          ? payload.currency
          : "CNY";
      return {
        type: action.type,
        payload: {
          amount: payload.amount,
          currency,
          direction,
          merchant:
            typeof payload.merchant === "string" && payload.merchant.length > 0
              ? payload.merchant
              : "未知商户",
          ...(typeof payload.category_hint === "string" && payload.category_hint.length > 0
            ? { category_hint: payload.category_hint }
            : {}),
          occurred_at:
            typeof payload.occurred_at === "string" && payload.occurred_at.length > 0
              ? payload.occurred_at
              : now().toISOString(),
        },
        confidence,
      };
    }
    case "asset_register_external_url":
      return {
        type: action.type,
        payload: {
          external_url: requireString(payload.external_url, "external_url"),
          ...(typeof payload.title === "string" && payload.title.length > 0
            ? { title: payload.title }
            : {}),
        },
        confidence,
      };
  }
}

function requireString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`Local Core candidate ${name} must be non-empty`);
  }
  return value;
}

function requireConfidence(value: number): number {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new Error("Local Core candidate confidence must be in [0, 1]");
  }
  return value;
}
