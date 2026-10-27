import { Buffer } from "node:buffer";
import type { Readable, Writable } from "node:stream";

const MAX_FRAME_BYTES = 262_144;
const MAX_OUTPUT_BYTES = 2_097_152;

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type Event = { sourceKey: string; title: string; [key: string]: Json };
export type RecordMutation = { collection: string; key: string; value: Json | null };
export type RunResult = {
  events: Event[];
  state?: Json;
  recordMutations: RecordMutation[];
  summary?: string;
  viewSnapshot?: Json;
};

export class ProtocolError extends Error {}
export class HostError extends ProtocolError {}

type Frame = Record<string, unknown>;

export class Channel {
  private readonly source: AsyncIterator<Buffer>;
  private readonly destination: Writable;
  private pending = Buffer.alloc(0);
  private written = 0;

  constructor(input: Readable = process.stdin, output: Writable = process.stdout) {
    this.source = input[Symbol.asyncIterator]() as AsyncIterator<Buffer>;
    this.destination = output;
  }

  async read(): Promise<Frame> {
    while (true) {
      const newline = this.pending.indexOf(10);
      if (newline >= 0) {
        if (newline > MAX_FRAME_BYTES) throw new ProtocolError("JSON-RPC frame exceeds 256 KiB");
        const line = this.pending.subarray(0, newline);
        this.pending = this.pending.subarray(newline + 1);
        let value: unknown;
        try { value = JSON.parse(line.toString("utf8")); }
        catch { throw new ProtocolError("invalid JSON-RPC JSON"); }
        if (typeof value !== "object" || value === null || Array.isArray(value) ||
            (value as Frame).jsonrpc !== "2.0") {
          throw new ProtocolError("expected JSON-RPC 2.0 object");
        }
        return value as Frame;
      }
      if (this.pending.length > MAX_FRAME_BYTES) throw new ProtocolError("JSON-RPC frame exceeds 256 KiB");
      const next = await this.source.next();
      if (next.done) throw new ProtocolError("missing or unterminated JSON-RPC frame");
      this.pending = Buffer.concat([this.pending, Buffer.from(next.value)]);
    }
  }

  write(frame: Frame): void {
    const data = Buffer.from(JSON.stringify(frame), "utf8");
    if (data.length > MAX_FRAME_BYTES) throw new ProtocolError("JSON-RPC frame exceeds 256 KiB");
    this.written += data.length + 1;
    if (this.written > MAX_OUTPUT_BYTES) throw new ProtocolError("child protocol output exceeds 2 MiB");
    this.destination.write(data);
    this.destination.write("\n");
  }

  async close(): Promise<void> {
    await this.source.return?.();
  }
}

export class Context {
  readonly runID: string;
  readonly automationID: string;
  readonly command: string;
  readonly mode: string;
  readonly now: string;
  readonly config: Record<string, Json>;
  readonly initialState: Json;
  readonly arguments: Record<string, Json>;
  readonly stateRevision: number;
  private readonly channel: Channel;
  private nextID = 1;

  constructor(params: Frame, channel: Channel) {
    if (params.hostProtocol !== "1" && params.hostProtocol !== "2") throw new ProtocolError("unsupported host protocol");
    for (const key of ["runID", "automationID", "command", "mode", "now"]) {
      if (typeof params[key] !== "string") throw new ProtocolError(`missing ${key}`);
    }
    if (typeof params.config !== "object" || params.config === null || Array.isArray(params.config)) {
      throw new ProtocolError("config must be an object");
    }
    this.runID = params.runID as string;
    this.automationID = params.automationID as string;
    this.command = params.command as string;
    this.mode = params.mode as string;
    this.now = params.now as string;
    this.config = params.config as Record<string, Json>;
    this.initialState = (params.state ?? {}) as Json;
    this.arguments = (params.arguments ?? {}) as Record<string, Json>;
    const revision = params.stateRevision ?? 0;
    if (typeof revision !== "number" || !Number.isSafeInteger(revision) || revision < 0) throw new ProtocolError("stateRevision must be a nonnegative integer");
    this.stateRevision = revision;
    this.channel = channel;
  }

  async request(method: string, params: Frame): Promise<Json> {
    const id = this.nextID++;
    this.channel.write({ jsonrpc: "2.0", id, method, params });
    const response = await this.channel.read();
    if (response.id !== id || "method" in response) throw new ProtocolError("host response ID or shape mismatch");
    if ("error" in response) {
      const error = response.error as Frame | undefined;
      throw new HostError(typeof error?.message === "string" ? error.message : "host operation failed");
    }
    if (!("result" in response)) throw new ProtocolError("host response has no result");
    return response.result as Json;
  }

  async integration(operation: string, params: Frame): Promise<Record<string, any>> {
    const result = await this.request("host.integration.call", { operation, params });
    if (typeof result !== "object" || result === null || Array.isArray(result)) {
      throw new ProtocolError("integration result is not an object");
    }
    return result as Record<string, any>;
  }
  getState(): Promise<Json> { return this.request("host.state.get", {}); }
  async queryRecords(collection: string, after = ""): Promise<RecordMutation[]> {
    const result = await this.request("host.records.query", { collection, after });
    if (!Array.isArray(result)) throw new ProtocolError("record query result is not an array");
    return result as RecordMutation[];
  }
  async log(message: string): Promise<void> { await this.request("host.log", { message }); }
}

export async function run(handler: (context: Context) => RunResult | Promise<RunResult>): Promise<void> {
  const channel = new Channel();
  let id: unknown = "run";
  try {
    const request = await channel.read();
    id = request.id ?? "run";
    if (request.id !== "run" || request.method !== "run" ||
        typeof request.params !== "object" || request.params === null || Array.isArray(request.params)) {
      throw new ProtocolError("expected run request with id 'run'");
    }
    const result = await handler(new Context(request.params as Frame, channel));
    if (!Array.isArray(result.events) || !Array.isArray(result.recordMutations)) {
      throw new ProtocolError("invalid run result");
    }
    channel.write({ jsonrpc: "2.0", id, result });
  } catch (error) {
    process.stderr.write(`Ledge plugin failed: ${error instanceof Error ? error.name : "Error"}\n`);
    try { channel.write({ jsonrpc: "2.0", id, error: { code: -32000, message: "Plugin run failed" } }); }
    catch { /* The host will also reject an incomplete child. */ }
    process.exitCode = 1;
  } finally {
    await channel.close();
  }
}
