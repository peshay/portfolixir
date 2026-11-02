import assert from "node:assert/strict";
import { execFile, spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { once } from "node:events";
import { readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { createServer as createNetServer, type AddressInfo } from "node:net";
import { join } from "node:path";
import { before, describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { LATEST_PROTOCOL_VERSION } from "@modelcontextprotocol/server";

import { MCP_PROFILES, type McpProfile } from "../src/profiles.js";
import { publishedToolList } from "../src/server.js";

// The companion's real transports (#1021): the built dist/index.js, started as
// an operator starts it, spoken to over stdin/stdout and over streamable HTTP.
// Every other test in this folder runs the server in-process; these are the
// only ones that cross a process boundary and the SDK's transport code on
// both ends of the wire. The client side is written out by hand (newline-
// delimited JSON-RPC, a fetch with the protocol's headers) so that the SDK
// under test is not also the SDK that judges it. Nothing leaves 127.0.0.1.

const packageRoot = fileURLToPath(new URL("..", import.meta.url));
const entry = join(packageRoot, "dist", "index.js");
const tsc = join(packageRoot, "node_modules", "typescript", "bin", "tsc");

// Synthetic credentials of a sound length that match no placeholder prefix
// (requireMcpToken). The two differ so the fake API can tell which one the
// companion forwarded.
const apiToken = "spawned-companion-api-bearer-4f1c9a7e2b6d8035";
const mcpToken = "spawned-companion-mcp-bearer-9d3e7b1a5c2f6084";

// The read the tools/call makes, and the synthetic answer the fake API gives.
const toolName = "portfolixir.contract.get";
const toolArguments = { since: "2026-01-01" };
const apiPath = "/api/v1/contract?since=2026-01-01";
const apiAnswer = {
  data: {
    version: "transport-test-7",
    last_changed_at: "2026-01-02",
    changed: true,
    endpoints_total: 3,
    tools_total: 3,
    entries: [{ date: "2026-01-02", summary: "synthetic entry for the transport test" }]
  }
};

// One deadline per wait, so a silent companion fails the test and its
// cleanup still runs instead of the run hanging on a live child.
const answerDeadlineMs = 10_000;

function within<T>(promise: Promise<T>, ms: number, what: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const deadline = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new Error(`${what}: nothing within ${ms} ms`)), ms);
  });

  return Promise.race([promise, deadline]).finally(() => clearTimeout(timer));
}

interface ApiHit {
  method: string;
  url: string;
  authorization: string | undefined;
}

interface FakeApi {
  baseUrl: string;
  hits: ApiHit[];
  close(): Promise<void>;
}

// A loopback stand-in for the Portfolixir API: it answers the one read the
// tool makes, answers anything else 404, and records every request it gets.
async function startFakeApi(): Promise<FakeApi> {
  const hits: ApiHit[] = [];
  const server = createServer((req, res) => {
    hits.push({
      method: req.method ?? "",
      url: req.url ?? "",
      authorization: req.headers.authorization
    });
    const found = req.method === "GET" && req.url === apiPath;

    res.writeHead(found ? 200 : 404, { "content-type": "application/json" });
    res.end(JSON.stringify(found ? apiAnswer : { errors: { detail: "Not Found" } }));
  });

  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const { port } = server.address() as AddressInfo;

  return {
    baseUrl: `http://127.0.0.1:${port}`,
    hits,
    close: async () => {
      server.closeAllConnections();
      server.close();
      await once(server, "close");
    }
  };
}

// A port nothing listens on a moment ago. The companion's listener takes a
// fixed port (port 0 would give it Host names under ":0"), so the test picks
// one the way an operator would, and closes the probe before handing it over.
async function freePort(): Promise<number> {
  const probe = createServer();
  probe.listen(0, "127.0.0.1");
  await once(probe, "listening");
  const { port } = probe.address() as AddressInfo;
  probe.close();
  await once(probe, "close");
  return port;
}

interface SpawnedCompanion {
  child: ChildProcessWithoutNullStreams;
  stderr(): string;
  /** Rejects when the process ends, naming its exit and its stderr. */
  died: Promise<never>;
  stop(): Promise<void>;
}

// `node dist/index.js` with exactly the environment given: nothing of the
// developer's own PORTFOLIXIR_* or proxy variables reaches it.
function spawnCompanion(env: Record<string, string>): SpawnedCompanion {
  const child = spawn(process.execPath, [entry], { cwd: packageRoot, env, stdio: "pipe" });
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk: string) => {
    stderr += chunk;
  });

  const closed = new Promise<string>((resolve) => {
    child.once("close", (code, signal) => {
      resolve(`the companion exited (code ${code}, signal ${signal}); stderr: ${stderr || "(empty)"}`);
    });
  });
  const died = closed.then((description): never => {
    throw new Error(description);
  });
  died.catch(() => undefined);

  return {
    child,
    stderr: () => stderr,
    died,
    stop: async () => {
      if (child.exitCode === null && child.signalCode === null) {
        child.kill("SIGTERM");

        try {
          await within(closed, 5_000, "the companion's shutdown");
        } catch {
          child.kill("SIGKILL");
        }
      }

      await closed;
    }
  };
}

interface JsonRpcMessage {
  jsonrpc?: unknown;
  id?: unknown;
  method?: unknown;
  result?: any;
  error?: unknown;
}

interface StdioWire {
  /** Every line the companion wrote to stdout that parsed as JSON. */
  received: JsonRpcMessage[];
  /** Every line it wrote to stdout that did not. */
  stray: string[];
  notify(method: string, params?: unknown): void;
  request(id: number, method: string, params?: unknown): Promise<JsonRpcMessage>;
}

// The stdio transport as a host speaks it: one JSON-RPC message per line on
// the child's stdin, one per line back on its stdout.
function stdioWire(companion: SpawnedCompanion): StdioWire {
  const received: JsonRpcMessage[] = [];
  const stray: string[] = [];
  const waiting = new Map<number, (message: JsonRpcMessage) => void>();
  let partial = "";

  companion.child.stdout.setEncoding("utf8");
  companion.child.stdout.on("data", (chunk: string) => {
    partial += chunk;
    let newline = partial.indexOf("\n");

    while (newline >= 0) {
      const line = partial.slice(0, newline);
      partial = partial.slice(newline + 1);
      newline = partial.indexOf("\n");

      let message: JsonRpcMessage;

      try {
        message = JSON.parse(line) as JsonRpcMessage;
      } catch {
        stray.push(line);
        continue;
      }

      received.push(message);

      if (typeof message.id === "number") {
        waiting.get(message.id)?.(message);
      }
    }
  });

  const write = (message: object): void => {
    companion.child.stdin.write(`${JSON.stringify(message)}\n`);
  };

  return {
    received,
    stray,
    notify: (method, params) => write({ jsonrpc: "2.0", method, params }),
    request: (id, method, params) => {
      const answered = new Promise<JsonRpcMessage>((resolve) => waiting.set(id, resolve));
      write({ jsonrpc: "2.0", id, method, params });
      return within(Promise.race([answered, companion.died]), answerDeadlineMs, `${method} over stdio`);
    }
  };
}

interface HttpAnswer {
  status: number;
  contentType: string;
  body: string;
  /** The JSON-RPC messages the body carries, as JSON or as SSE events. */
  messages: JsonRpcMessage[];
}

function sseMessages(body: string): JsonRpcMessage[] {
  return body
    .split(/\r?\n\r?\n/)
    .map((event) =>
      event
        .split(/\r?\n/)
        .filter((line) => line.startsWith("data:"))
        .map((line) => line.slice("data:".length).trimStart())
        .join("\n")
    )
    .filter((data) => data !== "")
    .map((data) => JSON.parse(data) as JsonRpcMessage);
}

// One POST to /mcp with the headers the streamable HTTP transport requires.
async function postMcp(
  base: string,
  message: object,
  headers: Record<string, string>
): Promise<HttpAnswer> {
  const response = await fetch(`${base}/mcp`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      ...headers
    },
    body: JSON.stringify(message),
    signal: AbortSignal.timeout(answerDeadlineMs)
  });
  const body = await response.text();
  const contentType = response.headers.get("content-type") ?? "";
  let messages: JsonRpcMessage[] = [];

  if (contentType.startsWith("text/event-stream")) {
    messages = sseMessages(body);
  } else if (contentType.startsWith("application/json") && body !== "") {
    messages = [JSON.parse(body) as JsonRpcMessage];
  }

  return { status: response.status, contentType, body, messages };
}

const initializeParams = {
  protocolVersion: LATEST_PROTOCOL_VERSION,
  capabilities: {},
  clientInfo: { name: "portfolixir-transport-test", version: "0.0.0" }
};

interface Conversation {
  initialize: JsonRpcMessage;
  list: JsonRpcMessage;
  call: JsonRpcMessage;
}

// What both transports must answer alike: the handshake, the tool list the
// source publishes, and the fake API's payload passed through unchanged after
// one request carrying the API token (never the MCP client's token).
function assertConversation(conversation: Conversation, api: FakeApi, transport: string): void {
  const { initialize, list, call } = conversation;

  assert.equal(initialize.jsonrpc, "2.0", transport);
  assert.equal(initialize.error, undefined, transport);
  assert.equal(initialize.result.protocolVersion, LATEST_PROTOCOL_VERSION, transport);
  assert.equal(initialize.result.serverInfo.name, "portfolixir", transport);
  assert.ok(initialize.result.capabilities.tools, transport);

  assert.equal(list.error, undefined, transport);
  const names = (list.result.tools as Array<{ name: string }>).map((tool) => tool.name);
  assert.ok(names.includes(toolName), transport);
  assert.deepEqual(
    names,
    publishedToolList().map((tool) => tool.name),
    `${transport}: the built companion lists what the source publishes`
  );

  assert.equal(call.error, undefined, transport);
  assert.notEqual(call.result.isError, true, `${transport}: ${JSON.stringify(call.result)}`);
  assert.deepEqual(call.result.structuredContent, apiAnswer, transport);
  assert.equal(call.result.content[0].type, "text", transport);
  assert.deepEqual(JSON.parse(call.result.content[0].text), apiAnswer, transport);

  assert.deepEqual(
    api.hits,
    [{ method: "GET", url: apiPath, authorization: `Bearer ${apiToken}` }],
    `${transport}: the fake API saw one read, with the API token`
  );
}

// THE STDIO SURFACE, AS A HOST RECEIVES IT (#1115). What the companion says
// over stdio, per profile, captured from the wire into a golden file with the
// SDK v1 build (1.32.2) before the move to v2, and held equal since: the
// handshake, the tool list, the prompt list and the prompts, a read's answer
// and the refusals an agent meets (an invalid argument, an unknown tool, a
// tool its profile leaves out, an unknown prompt, a request without its
// params, a method the companion does not offer). The request asks for the
// protocol version today's hosts send, so a host that changes nothing sees
// nothing change. The move to v2 changed two of the refusals (an unknown
// prompt, a tools/call without params), and contract entry 23 says how.
//
// The golden file is the agent's view: it changes only together with a
// contract entry saying what an agent sees change. To rewrite it, run the
// suite with PORTFOLIXIR_WRITE_STDIO_SURFACE=1 and read the diff.
const surfaceFile = join(packageRoot, "test", "fixtures", "stdio-surface.json");
const surfaceProtocolVersion = "2025-11-25";

type Exchange = { result?: unknown; error?: unknown };
type ProfileSurface = Record<string, Exchange | string[]>;

// One JSON-RPC answer as the golden file holds it: its result or its error,
// the envelope (jsonrpc, id) left out.
function exchange(message: JsonRpcMessage): Exchange {
  return "error" in message ? { error: message.error } : { result: message.result };
}

// The whole conversation one spawned companion holds under `profile`. The full
// profile answers everything; the narrower two answer the handshake, the names
// they list (each tool's definition is the full profile's, asserted
// separately), their own first-setup prompt and their refusal of a tool they
// leave out.
async function stdioSurface(
  profile: McpProfile,
  api: FakeApi
): Promise<{ surface: ProfileSurface; tools: Array<{ name: string }> }> {
  const companion = spawnCompanion({
    PORTFOLIXIR_API_BASE_URL: api.baseUrl,
    PORTFOLIXIR_API_TOKEN: apiToken,
    PORTFOLIXIR_MCP_TRANSPORT: "stdio",
    PORTFOLIXIR_MCP_PROFILE: profile
  });

  try {
    const wire = stdioWire(companion);
    let id = 0;
    const ask = async (method: string, params?: unknown): Promise<JsonRpcMessage> =>
      wire.request(++id, method, params);
    const surface: ProfileSurface = {};

    surface.initialize = exchange(
      await ask("initialize", { ...initializeParams, protocolVersion: surfaceProtocolVersion })
    );
    wire.notify("notifications/initialized");

    const list = await ask("tools/list", {});
    const tools = list.result.tools as Array<{ name: string }>;
    surface["tools/list names"] = tools.map((tool) => tool.name);
    surface["prompts/get first_setup"] = exchange(await ask("prompts/get", { name: "first_setup" }));

    if (profile !== "full") {
      surface["tools/call a write the profile leaves out"] = exchange(
        await ask("tools/call", {
          name: "portfolixir.securities.delete",
          arguments: { id: "00000000-0000-4000-8000-000000000000" }
        })
      );

      return { surface, tools };
    }

    surface["tools/list"] = exchange(list);
    surface["prompts/list"] = exchange(await ask("prompts/list", {}));
    surface["prompts/get import_converter"] = exchange(
      await ask("prompts/get", { name: "import_converter", arguments: { export_file: "export.csv" } })
    );
    surface["tools/call a read"] = exchange(
      await ask("tools/call", { name: toolName, arguments: toolArguments })
    );
    surface["tools/call an invalid argument"] = exchange(
      await ask("tools/call", { name: toolName, arguments: { since: 20260101 } })
    );
    surface["tools/call an unknown tool"] = exchange(
      await ask("tools/call", { name: "portfolixir.no_such_tool", arguments: {} })
    );
    surface["tools/call without params"] = exchange(await ask("tools/call"));
    surface["prompts/get an unknown prompt"] = exchange(await ask("prompts/get", { name: "no_such_prompt" }));
    surface["resources/list, not offered"] = exchange(await ask("resources/list", {}));
    surface.ping = exchange(await ask("ping"));

    assert.deepEqual(wire.stray, [], `${profile}: stdout carries JSON-RPC only`);
    return { surface, tools };
  } finally {
    await companion.stop();
  }
}

describe("the built companion over its real transports", () => {
  // `npm test` alone is enough: the suite compiles dist/ the way `npm run
  // build` does (CI runs the tests before its build step), so the process
  // these tests start is the current source, never a stale build.
  before(
    async () => {
      await promisify(execFile)(process.execPath, [tsc, "-p", "tsconfig.json"], {
        cwd: packageRoot,
        timeout: 120_000
      });
    },
    { timeout: 150_000 }
  );

  // User story (#1021):
  // As an operator whose MCP host starts the companion as a subprocess,
  // I want the built companion to complete the protocol over stdin and stdout,
  // so that an update of the MCP SDK that breaks the stdio transport fails a
  // test instead of my host.
  //
  // Acceptance criteria:
  // - `node dist/index.js` with PORTFOLIXIR_MCP_TRANSPORT=stdio answers
  //   initialize, then (after notifications/initialized) tools/list and
  //   tools/call of a read tool, each on stdout as newline-delimited JSON-RPC.
  // - tools/list carries the tools the source publishes; tools/call returns
  //   the fake API's payload, and the fake API saw the API bearer token.
  // - Nothing but JSON-RPC reaches stdout, and nothing answers the notification.
  it("answers initialize, tools/list and tools/call over stdio", { timeout: 60_000 }, async () => {
    const api = await startFakeApi();
    const companion = spawnCompanion({
      PORTFOLIXIR_API_BASE_URL: api.baseUrl,
      PORTFOLIXIR_API_TOKEN: apiToken,
      PORTFOLIXIR_MCP_TRANSPORT: "stdio"
    });

    try {
      const wire = stdioWire(companion);
      const initialize = await wire.request(1, "initialize", initializeParams);
      wire.notify("notifications/initialized");
      const list = await wire.request(2, "tools/list", {});
      const call = await wire.request(3, "tools/call", { name: toolName, arguments: toolArguments });

      assertConversation({ initialize, list, call }, api, "stdio");
      assert.deepEqual(wire.stray, [], "stdout carries JSON-RPC only");
      assert.deepEqual(
        wire.received.map((message) => [message.jsonrpc, message.id]),
        [
          ["2.0", 1],
          ["2.0", 2],
          ["2.0", 3]
        ],
        "one answer per request, none to the notification"
      );
    } finally {
      await companion.stop();
      await api.close();
    }
  });

  // User story (#1115):
  // As the agent the operator runs, connected over stdio,
  // I want the companion to answer exactly as it did before its MCP SDK moved
  // from v1 to v2,
  // so that a dependency move changes no tool name, schema, description,
  // prompt, answer or refusal I rely on without a contract entry saying so.
  //
  // Acceptance criteria:
  // - Under each profile, the built companion's stdio answers equal the
  //   golden file captured from the v1 build, key order included: the
  //   handshake, the tool names, the first-setup prompt, and the refusal of
  //   a tool the profile leaves out; under full also the whole tool list, the
  //   prompts, a read's answer and each refusal.
  // - Each tool the read and book profiles list is the full profile's tool,
  //   byte for byte.
  it("answers over stdio exactly what the golden surface holds, under every profile", { timeout: 120_000 }, async () => {
    const api = await startFakeApi();
    const actual: Record<string, ProfileSurface> = {};
    const listed: Record<string, Array<{ name: string }>> = {};

    try {
      for (const profile of MCP_PROFILES) {
        ({ surface: actual[profile], tools: listed[profile] } = await stdioSurface(profile, api));
      }
    } finally {
      await api.close();
    }

    const captured = { protocolVersion: surfaceProtocolVersion, profiles: actual };

    if (process.env.PORTFOLIXIR_WRITE_STDIO_SURFACE === "1") {
      writeFileSync(surfaceFile, `${JSON.stringify(captured, null, 2)}\n`);
    }

    const golden = JSON.parse(readFileSync(surfaceFile, "utf8")) as typeof captured;

    assert.equal(golden.protocolVersion, surfaceProtocolVersion);
    assert.deepEqual(Object.keys(golden.profiles), Object.keys(actual));

    for (const profile of MCP_PROFILES) {
      assert.deepEqual(Object.keys(actual[profile]), Object.keys(golden.profiles[profile]), profile);

      for (const [what, answer] of Object.entries(actual[profile])) {
        // Serialised, so a key that moved or a field that appeared fails too.
        assert.equal(
          JSON.stringify(answer, null, 2),
          JSON.stringify(golden.profiles[profile][what], null, 2),
          `${profile}: ${what} differs from the golden surface`
        );
      }
    }

    const fullTools = new Map(listed.full.map((tool) => [tool.name, JSON.stringify(tool)]));

    for (const profile of ["read", "book"] as const) {
      for (const tool of listed[profile]) {
        assert.equal(JSON.stringify(tool), fullTools.get(tool.name), `${profile}: ${tool.name}`);
      }
    }
  });

  // User story (#1021):
  // As an operator whose MCP host reaches the companion over HTTP,
  // I want the built companion to complete the protocol over its streamable
  // HTTP listener and to refuse a request without its bearer token,
  // so that an update of the MCP SDK or of the listener that breaks either
  // fails a test instead of my host.
  //
  // Acceptance criteria:
  // - `node dist/index.js` with PORTFOLIXIR_MCP_TRANSPORT=http on 127.0.0.1
  //   answers initialize, notifications/initialized (202), tools/list and
  //   tools/call of a read tool, each a POST to /mcp.
  // - tools/list carries the tools the source publishes; tools/call returns
  //   the fake API's payload, and the fake API saw the API bearer token.
  // - A tools/call without the MCP bearer token is answered 401 and never
  //   reaches the API.
  it(
    "answers initialize, tools/list and tools/call over streamable HTTP, and refuses a request without its bearer",
    { timeout: 60_000 },
    async () => {
      const api = await startFakeApi();
      const port = await freePort();
      const companion = spawnCompanion({
        PORTFOLIXIR_API_BASE_URL: api.baseUrl,
        PORTFOLIXIR_API_TOKEN: apiToken,
        PORTFOLIXIR_MCP_TRANSPORT: "http",
        PORTFOLIXIR_MCP_TOKEN: mcpToken,
        PORTFOLIXIR_MCP_HOST: "127.0.0.1",
        PORTFOLIXIR_MCP_PORT: String(port)
      });

      try {
        // The listener announces itself on stderr once it is bound.
        const announcement = `listening on http://127.0.0.1:${port}/mcp`;
        const announced = new Promise<void>((resolve) => {
          const heard = (): void => {
            if (companion.stderr().includes(announcement)) {
              companion.child.stderr.off("data", heard);
              resolve();
            }
          };
          companion.child.stderr.on("data", heard);
          heard();
        });
        await within(Promise.race([announced, companion.died]), 15_000, "the HTTP listener");

        const base = `http://127.0.0.1:${port}`;
        const call = {
          jsonrpc: "2.0",
          id: 3,
          method: "tools/call",
          params: { name: toolName, arguments: toolArguments }
        };

        const anonymous = await postMcp(base, call, {});
        assert.equal(anonymous.status, 401, anonymous.body);
        assert.deepEqual(JSON.parse(anonymous.body), { errors: { detail: "unauthorized" } });
        assert.deepEqual(api.hits, [], "a refused request never reaches the API");

        const bearer = { authorization: `Bearer ${mcpToken}` };
        const initialize = await postMcp(
          base,
          { jsonrpc: "2.0", id: 1, method: "initialize", params: initializeParams },
          bearer
        );
        assert.equal(initialize.status, 200, initialize.body);
        assert.equal(initialize.messages.length, 1, initialize.body);

        const negotiated = { ...bearer, "mcp-protocol-version": LATEST_PROTOCOL_VERSION };
        const initialized = await postMcp(
          base,
          { jsonrpc: "2.0", method: "notifications/initialized" },
          negotiated
        );
        assert.equal(initialized.status, 202, initialized.body);
        assert.deepEqual(initialized.messages, []);

        const list = await postMcp(
          base,
          { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} },
          negotiated
        );
        assert.equal(list.status, 200, list.body);
        assert.equal(list.messages.length, 1, list.body);

        const answered = await postMcp(base, call, negotiated);
        assert.equal(answered.status, 200, answered.body);
        assert.equal(answered.messages.length, 1, answered.body);

        assertConversation(
          { initialize: initialize.messages[0], list: list.messages[0], call: answered.messages[0] },
          api,
          "streamable HTTP"
        );
      } finally {
        await companion.stop();
        await api.close();
      }
    }
  );

  // User story (#1137):
  // As an operator whose PORTFOLIXIR_MCP_HOST is set but empty (an `.env`
  // line left blank),
  // I want the companion to bind the loopback default, as an unset host does,
  // so that a blank value never opens the listener on every interface.
  //
  // Acceptance criteria:
  // - With PORTFOLIXIR_MCP_HOST empty or blank, `node dist/index.js` over HTTP
  //   announces `listening on http://127.0.0.1:<port>/mcp`, never `http://:…`.
  // - The listener answers on 127.0.0.1 under its own Host (401 without the
  //   token).
  for (const value of ["", "   "]) {
    it(`binds 127.0.0.1 when PORTFOLIXIR_MCP_HOST is ${JSON.stringify(value)}`, { timeout: 60_000 }, async () => {
      const port = await freePort();
      const companion = spawnCompanion({
        PORTFOLIXIR_API_BASE_URL: "http://127.0.0.1:9",
        PORTFOLIXIR_API_TOKEN: apiToken,
        PORTFOLIXIR_MCP_TRANSPORT: "http",
        PORTFOLIXIR_MCP_TOKEN: mcpToken,
        PORTFOLIXIR_MCP_HOST: value,
        PORTFOLIXIR_MCP_PORT: String(port)
      });

      try {
        const announced = new Promise<string>((resolve) => {
          const heard = (): void => {
            const line = companion
              .stderr()
              .split(/\r?\n/)
              .find((candidate) => candidate.includes("MCP server listening on"));

            if (line !== undefined) {
              companion.child.stderr.off("data", heard);
              resolve(line);
            }
          };
          companion.child.stderr.on("data", heard);
          heard();
        });
        const line = await within(Promise.race([announced, companion.died]), 15_000, "the HTTP listener");

        assert.equal(line, `Portfolixir MCP server listening on http://127.0.0.1:${port}/mcp`);

        const anonymous = await postMcp(`http://127.0.0.1:${port}`, { jsonrpc: "2.0", id: 1, method: "tools/list" }, {});
        assert.equal(anonymous.status, 401, anonymous.body);
      } finally {
        await companion.stop();
      }
    });
  }

  // User story (#1043, Sprint 19 plan, PR β B3):
  // As an operator who starts the companion on a port something else holds,
  // I want it to stop with a line naming the host, the port and the cause,
  // so that I am not told it listens while it serves nothing.
  //
  // Acceptance criteria:
  // - With PORTFOLIXIR_MCP_TRANSPORT=http on a port another listener holds,
  //   `node dist/index.js` exits 1.
  // - stderr carries one line naming the address it could not listen on and
  //   EADDRINUSE, and no "listening" line and no stack trace.
  it("exits 1 naming the host, the port and the cause when its port is taken", { timeout: 60_000 }, async () => {
    const holder = createNetServer();
    holder.listen(0, "127.0.0.1");
    await once(holder, "listening");
    const { port } = holder.address() as AddressInfo;

    const companion = spawnCompanion({
      PORTFOLIXIR_API_BASE_URL: "http://127.0.0.1:9",
      PORTFOLIXIR_API_TOKEN: apiToken,
      PORTFOLIXIR_MCP_TRANSPORT: "http",
      PORTFOLIXIR_MCP_TOKEN: mcpToken,
      PORTFOLIXIR_MCP_HOST: "127.0.0.1",
      PORTFOLIXIR_MCP_PORT: String(port)
    });
    const exited = once(companion.child, "close");

    try {
      const [code] = await within(exited, 15_000, "the companion's exit");
      const stderr = companion.stderr();

      assert.equal(code, 1, stderr);
      assert.ok(
        stderr
          .split(/\r?\n/)
          .includes(
            `Portfolixir MCP server could not listen on http://127.0.0.1:${port}/mcp: EADDRINUSE (the port is in use)`
          ),
        stderr
      );
      assert.doesNotMatch(stderr, /listening/);
      assert.doesNotMatch(stderr, /^\s+at /m, "no stack trace");
    } finally {
      await companion.stop();
      holder.close();
      await once(holder, "close");
    }
  });

  // User story (#1043 review round):
  // As an operator who sets PORTFOLIXIR_MCP_PORT to something that is not a
  // port,
  // I want the companion to stop with a line naming the variable and the
  // value I set,
  // so that it neither listens on a port I did not choose nor reports NaN.
  //
  // Acceptance criteria:
  // - With PORTFOLIXIR_MCP_TRANSPORT=http and PORTFOLIXIR_MCP_PORT set to
  //   `abc`, `4001x` or `70000`, `node dist/index.js` exits 1.
  // - stderr carries one line naming the variable, the range and the value as
  //   set, and no "listening" line and no stack trace.
  for (const value of ["abc", "4001x", "70000"]) {
    it(`exits 1 naming the variable and the value when the port is ${value}`, { timeout: 60_000 }, async () => {
      const companion = spawnCompanion({
        PORTFOLIXIR_API_BASE_URL: "http://127.0.0.1:9",
        PORTFOLIXIR_API_TOKEN: apiToken,
        PORTFOLIXIR_MCP_TRANSPORT: "http",
        PORTFOLIXIR_MCP_TOKEN: mcpToken,
        PORTFOLIXIR_MCP_HOST: "127.0.0.1",
        PORTFOLIXIR_MCP_PORT: value
      });
      const exited = once(companion.child, "close");

      try {
        const [code] = await within(exited, 15_000, "the companion's exit");
        const stderr = companion.stderr();

        assert.equal(code, 1, stderr);
        assert.ok(
          stderr
            .split(/\r?\n/)
            .includes(
              "PORTFOLIXIR_MCP_PORT must be a whole number from 1 to 65535, or unset (4001); " +
                `it is set to "${value}"`
            ),
          stderr
        );
        assert.doesNotMatch(stderr, /listening|NaN/);
        assert.doesNotMatch(stderr, /^\s+at /m, "no stack trace");
      } finally {
        await companion.stop();
      }
    });
  }

  // User story (security review 2026-10-12, K16):
  // As the operator whose environment switches on Node's proxy for every
  // Node tool,
  // I want the built companion never to send its API calls through that
  // proxy,
  // so that the API token and my records never pass through a third process.
  //
  // Acceptance criteria:
  // - Started with NODE_USE_ENV_PROXY=1, HTTP_PROXY pointing at a loopback
  //   stand-in for a proxy and a NO_PROXY that does not name the API host,
  //   the companion exits 1 naming NO_PROXY, before any call.
  // - Neither the fake API nor the stand-in proxy receives anything.
  it("refuses to start when Node's environment proxy would carry its API calls", { timeout: 60_000 }, async () => {
    const api = await startFakeApi();
    let proxyConnections = 0;
    const fakeProxy = createNetServer((socket) => {
      proxyConnections += 1;
      socket.end("HTTP/1.1 403 Forbidden\r\ncontent-length: 0\r\n\r\n");
    });
    fakeProxy.listen(0, "127.0.0.1");
    await once(fakeProxy, "listening");
    const { port: proxyPort } = fakeProxy.address() as AddressInfo;

    const companion = spawnCompanion({
      PORTFOLIXIR_API_BASE_URL: api.baseUrl,
      PORTFOLIXIR_API_TOKEN: apiToken,
      PORTFOLIXIR_MCP_TRANSPORT: "stdio",
      NODE_USE_ENV_PROXY: "1",
      HTTP_PROXY: `http://127.0.0.1:${proxyPort}`,
      NO_PROXY: "localhost"
    });
    const exited = once(companion.child, "close");

    try {
      // A companion that started would wait on stdin and miss this deadline.
      const [code] = await within(exited, 15_000, "the companion's exit");
      assert.equal(code, 1, companion.stderr());
      assert.match(companion.stderr(), /NO_PROXY/);
      assert.doesNotMatch(companion.stderr(), /^\s+at /m, "no stack trace");
      assert.deepEqual(api.hits, []);
      assert.equal(proxyConnections, 0, "the proxy stand-in received a connection");
    } finally {
      await companion.stop();
      await api.close();
      fakeProxy.close();
    }
  });
});
