declare module "node:readline/promises" {
  export function createInterface(options: { input: unknown; terminal?: boolean }): AsyncIterable<string> & { close(): void };
}

declare module "node:process" {
  export const stdin: unknown;
  export const stdout: { write(chunk: string): boolean };
}

declare const process: {
  argv: string[];
};
