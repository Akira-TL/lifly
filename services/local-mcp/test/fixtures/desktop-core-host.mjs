import { createInterface } from "node:readline";

const memos = [];
let memoSeq = 0;
let runtimeInit = null;

const rl = createInterface({ input: process.stdin, terminal: false });

for await (const line of rl) {
  const trimmed = line.trim();
  if (!trimmed) continue;

  const request = JSON.parse(trimmed);
  const response = await handle(request);
  process.stdout.write(`${JSON.stringify({ id: request.id, ...response })}\n`);
}

async function handle(request) {
  if (request.method === "_runtime_init") {
    const key = Buffer.from(request.input.account_data_key_base64, "base64");
    if (key.length !== 32) {
      return {
        ok: false,
        error: { code: "INVALID_RUNTIME_KEY", message: "runtime key must be 32 bytes" },
      };
    }
    runtimeInit = {
      accountId: request.input.account_id,
      keyVersion: request.input.key_version,
    };
    key.fill(0);
    return { ok: true, result: { status: "initialized" } };
  }

  if (request.method === "health") {
    return {
      ok: true,
      result: {
        status: "ok",
        mode: "desktop_bridge",
        version: "desktop-host.fixture",
        runtime: "desktop",
        detail: runtimeInit
          ? `stdio fixture host account=${runtimeInit.accountId} key_version=${runtimeInit.keyVersion}`
          : "stdio fixture host",
      },
    };
  }

  if (request.method === "memo_create") {
    const now = new Date("2026-08-15T10:00:00.000Z").toISOString();
    const memo = {
      id: `fixture_memo_${++memoSeq}`,
      type: request.input.type,
      title: request.input.title ?? null,
      content_markdown: request.input.content_markdown,
      tags: request.input.tags ?? [],
      status: "active",
      revision: 1,
      created_at: now,
      updated_at: now,
    };
    memos.unshift(memo);
    return { ok: true, result: memo };
  }

  if (request.method === "memo_search") {
    const q = request.input.q.trim().toLowerCase();
    const result = memos
      .filter((memo) => `${memo.title ?? ""}\n${memo.content_markdown}`.toLowerCase().includes(q))
      .slice(0, request.input.limit);
    return { ok: true, result };
  }

  return {
    ok: false,
    error: { code: "UNSUPPORTED_FIXTURE_METHOD", message: `Unsupported fixture method: ${request.method}` },
  };
}
