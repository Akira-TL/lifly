import { spawn } from "node:child_process";

import type {
  DesktopLocalCoreInvocation,
  DesktopLocalCoreMethod,
  DesktopLocalCoreOperationMap,
  DesktopLocalCoreTransport,
} from "../../../packages/local-core/src/index.js";

export interface DesktopLocalCoreRuntimeBootstrap {
  accountId: string;
  keyVersion: number;
  accountDataKeyBytes: Uint8Array;
}

export interface DesktopLocalCoreProcessTransportOptions {
  bridgePath: string;
  bridgeArgs?: string[];
  requestTimeoutMs?: number;
  runtimeBootstrap?: DesktopLocalCoreRuntimeBootstrap;
}

interface PendingRequest {
  method: DesktopLocalCoreMethod;
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

interface DesktopHostResponse {
  id: number;
  ok: boolean;
  result?: unknown;
  error?: { code?: string; message: string };
}

export class DesktopLocalCoreProcessTransport implements DesktopLocalCoreTransport {
  private readonly bridgePath: string;
  private readonly bridgeArgs: string[];
  private readonly requestTimeoutMs: number;
  private readonly runtimeBootstrap: DesktopLocalCoreRuntimeBootstrap | null;
  private child: ReturnType<typeof spawn> | null = null;
  private stdoutBuffer = "";
  private nextRequestId = 0;
  private readonly pending = new Map<number, PendingRequest>();

  constructor(options: DesktopLocalCoreProcessTransportOptions) {
    this.bridgePath = options.bridgePath;
    this.bridgeArgs = options.bridgeArgs ?? [];
    this.requestTimeoutMs = options.requestTimeoutMs ?? 5_000;
    this.runtimeBootstrap = options.runtimeBootstrap
      ? {
        accountId: options.runtimeBootstrap.accountId,
        keyVersion: options.runtimeBootstrap.keyVersion,
        accountDataKeyBytes: new Uint8Array(options.runtimeBootstrap.accountDataKeyBytes),
      }
      : null;
  }

  async invoke<M extends DesktopLocalCoreMethod>(
    request: DesktopLocalCoreInvocation<M>,
  ): Promise<DesktopLocalCoreOperationMap[M]["result"]> {
    const child = this.ensureChild();
    if (!child.stdin) throw new Error("Desktop Local Core host stdin is unavailable");

    const id = ++this.nextRequestId;
    const payload = JSON.stringify({ id, ...request });

    return new Promise<DesktopLocalCoreOperationMap[M]["result"]>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Desktop Local Core host timed out for ${request.method}`));
      }, this.requestTimeoutMs);

      this.pending.set(id, {
        method: request.method,
        resolve: (value) => resolve(value as DesktopLocalCoreOperationMap[M]["result"]),
        reject,
        timer,
      });

      try {
        child.stdin?.write(`${payload}\n`);
      } catch (error) {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(this.asError(error));
      }
    });
  }

  async close(): Promise<void> {
    this.runtimeBootstrap?.accountDataKeyBytes.fill(0);
    const child = this.child;
    this.child = null;
    if (!child) return;

    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(new Error(`Desktop Local Core host closed before ${pending.method} completed`));
      this.pending.delete(id);
    }

    child.stdin?.end();
    child.kill();
  }

  private ensureChild(): ReturnType<typeof spawn> {
    if (this.child) return this.child;

    const child = spawn(this.bridgePath, this.bridgeArgs, { stdio: ["pipe", "pipe", "inherit"] });
    if (!child.stdin || !child.stdout) {
      child.kill();
      throw new Error("Desktop Local Core host must expose stdin/stdout pipes");
    }

    if (this.runtimeBootstrap) {
      child.stdin.write(`${JSON.stringify({
        id: 0,
        method: "_runtime_init",
        input: {
          account_id: this.runtimeBootstrap.accountId,
          key_version: this.runtimeBootstrap.keyVersion,
          account_data_key_base64: encodeBase64(this.runtimeBootstrap.accountDataKeyBytes),
        },
      })}\n`);
    }

    child.stdout.on("data", (chunk) => this.consumeStdout(chunk.toString()));
    child.on("error", (error) => this.failChild(this.asError(error)));
    child.on("exit", (code, signal) => {
      const suffix = signal ? `signal=${signal}` : `code=${String(code)}`;
      this.failChild(new Error(`Desktop Local Core host exited (${suffix})`));
    });
    this.child = child;
    return child;
  }

  private consumeStdout(chunk: string): void {
    this.stdoutBuffer += chunk;
    while (true) {
      const newline = this.stdoutBuffer.indexOf("\n");
      if (newline < 0) return;
      const line = this.stdoutBuffer.slice(0, newline).trim();
      this.stdoutBuffer = this.stdoutBuffer.slice(newline + 1);
      if (!line) continue;

      try {
        const response = this.parseResponse(JSON.parse(line) as unknown);
        const pending = this.pending.get(response.id);
        if (!pending) continue;
        this.pending.delete(response.id);
        clearTimeout(pending.timer);
        if (response.ok) {
          pending.resolve(response.result);
        } else {
          pending.reject(new Error(response.error?.message ?? "Desktop Local Core host returned an error"));
        }
      } catch (error) {
        this.failChild(new Error(`Invalid Desktop Local Core host response: ${this.asError(error).message}`));
      }
    }
  }

  private parseResponse(value: unknown): DesktopHostResponse {
    if (!value || typeof value !== "object") throw new Error("response must be an object");
    const data = value as Record<string, unknown>;
    if (typeof data.id !== "number" || !Number.isInteger(data.id)) throw new Error("response id must be an integer");
    if (typeof data.ok !== "boolean") throw new Error("response ok must be boolean");

    if (data.ok) {
      return { id: data.id, ok: true, result: data.result };
    }

    const error = data.error;
    if (!error || typeof error !== "object") throw new Error("error response must include error object");
    const errorData = error as Record<string, unknown>;
    if (typeof errorData.message !== "string" || errorData.message.length === 0) {
      throw new Error("error response must include a message");
    }
    return {
      id: data.id,
      ok: false,
      error: {
        code: typeof errorData.code === "string" ? errorData.code : undefined,
        message: errorData.message,
      },
    };
  }

  private failChild(error: Error): void {
    const child = this.child;
    this.child = null;
    this.stdoutBuffer = "";

    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(error);
      this.pending.delete(id);
    }

    if (child) child.kill();
  }

  private asError(error: unknown): Error {
    return error instanceof Error ? error : new Error(String(error));
  }
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
