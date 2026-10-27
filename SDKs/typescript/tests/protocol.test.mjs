import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { once } from "node:events";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const program = fileURLToPath(new URL("./echo_program.ts", import.meta.url));

test("TypeScript SDK v2 retains action arguments", async () => {
  const { Context, Channel } = await import("../src/index.ts");
  const ctx = new Context({ hostProtocol: "2", runID: "r", automationID: "a", command: "run", mode: "preview", now: "2026-10-26T00:00:00Z", config: {}, arguments: { message: "hello" }, stateRevision: 7 }, new Channel());
  assert.deepEqual(ctx.arguments, { message: "hello" });
  assert.equal(ctx.stateRevision, 7);
});

test("TypeScript SDK exchanges protocol v1 host requests", async () => {
  const child = spawn(process.execPath, ["--experimental-strip-types", program], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  try {
    const frames = createInterface({ input: child.stdout })[Symbol.asyncIterator]();
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: "run", method: "run", params: {
      runID: "r1", automationID: "a1", command: "scan", config: {}, state: {},
      mode: "dryRun", now: "2026-10-26T00:00:00Z", hostProtocol: "1",
    } }) + "\n");
    const request = JSON.parse((await frames.next()).value);
    assert.equal(request.method, "host.integration.call");
    assert.deepEqual(request.params, { operation: "github.issues.listUpdated",
      params: { repository: "owner/repo", page: 1 } });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: request.id,
      result: { data: [{ title: "Useful issue" }], hasNext: false, checkedAt: "2026-10-26T00:00:00Z" } }) + "\n");
    const final = JSON.parse((await frames.next()).value);
    assert.equal(final.id, "run");
    assert.equal(final.result.events[0].title, "Useful issue");
    assert.equal(final.result.summary, "dryRun");
    const exitCode = child.exitCode ?? (await once(child, "exit"))[0];
    assert.equal(exitCode, 0);
  } finally {
    if (child.exitCode === null) child.kill();
  }
});
