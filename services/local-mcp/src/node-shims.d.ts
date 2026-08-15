declare module "node:readline/promises" {
  export function createInterface(options: { input: unknown; terminal?: boolean }): AsyncIterable<string> & { close(): void };
}

declare module "node:process" {
  export const stdin: unknown;
  export const stdout: { write(chunk: string): boolean };
}

declare module "node:child_process" {
  interface WritablePipe {
    write(chunk: string): boolean;
    end(): void;
  }

  interface ReadablePipe {
    on(event: "data", listener: (chunk: { toString(): string }) => void): this;
  }

  interface ChildProcessLike {
    stdin: WritablePipe | null;
    stdout: ReadablePipe | null;
    on(event: "error", listener: (error: Error) => void): this;
    on(event: "exit", listener: (code: number | null, signal: string | null) => void): this;
    kill(): boolean;
  }

  export function spawn(
    command: string,
    args?: string[],
    options?: { stdio: ["pipe", "pipe", "inherit"] },
  ): ChildProcessLike;
}

declare const process: {
  argv: string[];
  env: Record<string, string | undefined>;
};
