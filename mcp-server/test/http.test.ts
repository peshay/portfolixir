import assert from "node:assert/strict";
import { once } from "node:events";
import { STATUS_CODES, createServer, request as httpRequest } from "node:http";
import { Server, type AddressInfo } from "node:net";
import { describe, it } from "node:test";

import type { NextFunction, Request, Response } from "express";

import {
  isAllowedOrigin,
  isAuthorizedMcpRequest,
  requireMcpToken,
  allowedHostsFor,
  allowedOriginsFor,
  mcpHost,
  createFailureThrottle,
  createHttpApp,
  mcpAuthMiddleware,
  MCP_TOKEN_MIN_BYTES,
  mcpUrl,
  startHttpServer
} from "../src/http.js";
import type { McpProfile } from "../src/profiles.js";

const soundToken = "k".repeat(32);

interface FakeResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: unknown;
  nextCalled: boolean;
}

// One request through the auth middleware, with the peer address and the
// authorization header given; no socket is opened.
function authenticate(
  middleware: ReturnType<typeof mcpAuthMiddleware>,
  authorization: string | undefined,
  remoteAddress: string
): FakeResponse {
  const headers: Record<string, string | undefined> = { authorization };
  const outcome: FakeResponse = { statusCode: 200, headers: {}, body: undefined, nextCalled: false };

  const req = {
    get: (name: string) => headers[name.toLowerCase()],
    socket: { remoteAddress }
  } as unknown as Request;

  const res = {
    status(code: number) {
      outcome.statusCode = code;
      return this;
    },
    set(name: string, value: string) {
      outcome.headers[name.toLowerCase()] = value;
      return this;
    },
    json(body: unknown) {
      outcome.body = body;
      return this;
    }
  } as unknown as Response;

  const next: NextFunction = () => {
    outcome.nextCalled = true;
  };

  middleware(req, res, next);
  return outcome;
}

describe("MCP HTTP security helpers", () => {
  // User story (#956):
  // As an operator whose companion listens over HTTP,
  // I want a browser request's Origin compared whole, scheme, name and port,
  // against the addresses the companion answers under,
  // so that a page served from another loopback port cannot drive it, while
  // the IPv6 loopback, a proxy name and a browser client I name still can.
  //
  // Acceptance criteria:
  // - A request without an Origin (a non-browser client) passes, as before.
  // - The loopback names with the listener's port pass over http, the IPv6
  //   loopback in the brackets a URL gives it included; under another port,
  //   no port, or https they are refused, and so is a foreign or opaque origin.
  // - A name in PORTFOLIXIR_MCP_ALLOWED_HOSTS passes over http or https, with
  //   the listener's port or none; an entry that carries its own port (a
  //   browser client on another loopback port) passes under that port only.
  it("admits an Origin only under a name and port the companion answers under", () => {
    const loopback = allowedOriginsFor("127.0.0.1", 4001);

    assert.equal(isAllowedOrigin(undefined, loopback), true);

    for (const origin of ["http://127.0.0.1:4001", "http://localhost:4001", "http://[::1]:4001"]) {
      assert.equal(isAllowedOrigin(origin, loopback), true, origin);
    }

    for (const origin of [
      "http://localhost:4002",
      "http://127.0.0.1:6274",
      "http://[::1]:5173",
      "http://localhost",
      "https://localhost:4001",
      "http://LOCALHOST:4001/",
      "https://example.com",
      "http://rebound.example:4001",
      "null",
      "file://"
    ]) {
      assert.equal(isAllowedOrigin(origin, loopback), false, origin);
    }

    const named = allowedOriginsFor("0.0.0.0", 4001, " mcp.lan ", "localhost:6274", "");

    for (const origin of [
      "https://mcp.lan",
      "http://mcp.lan",
      "http://mcp.lan:4001",
      "http://localhost:6274",
      "http://localhost:4001"
    ]) {
      assert.equal(isAllowedOrigin(origin, named), true, origin);
    }

    for (const origin of ["https://mcp.lan:8443", "http://localhost:6275", "http://0.0.0.0:4001"]) {
      assert.equal(isAllowedOrigin(origin, named), false, origin);
    }
  });

  it("requires the configured MCP bearer token when one is configured", () => {
    assert.equal(isAuthorizedMcpRequest("Bearer mcp-token", "mcp-token"), true);
    assert.equal(isAuthorizedMcpRequest("Bearer wrong", "mcp-token"), false);
    assert.equal(isAuthorizedMcpRequest(undefined, "mcp-token"), false);
    assert.equal(isAuthorizedMcpRequest(undefined, undefined), false);
    assert.equal(isAuthorizedMcpRequest(undefined, ""), false);
  });

  // Issue #761: the comparison is length-guarded and constant-time, so a
  // header that shares a prefix with the token is refused exactly like one
  // that does not, and a header of another length never reaches the compare.
  it("refuses prefixes, suffixes and other lengths of the token", () => {
    assert.equal(isAuthorizedMcpRequest("Bearer mcp-tok", "mcp-token"), false);
    assert.equal(isAuthorizedMcpRequest("Bearer mcp-token-x", "mcp-token"), false);
    assert.equal(isAuthorizedMcpRequest("bearer mcp-token", "mcp-token"), false);
    assert.equal(isAuthorizedMcpRequest("Bearer  mcp-token", "mcp-token"), false);
  });

  // Issue #761: HTTP mode without a token fails at startup with a named
  // variable, never silently with a listener that answers 401 forever.
  it("names the missing token for HTTP mode instead of starting closed", () => {
    assert.equal(requireMcpToken(soundToken), soundToken);
    assert.throws(() => requireMcpToken(undefined), /PORTFOLIXIR_MCP_TOKEN/);
    assert.throws(() => requireMcpToken("   "), /PORTFOLIXIR_MCP_TOKEN/);
  });

  // User story (E25 S1, F01):
  // As an operator starting the companion over HTTP,
  // I want a short or placeholder MCP token refused at start with the variable named,
  // so that the companion holds its token to the same policy as the API token.
  //
  // Acceptance criteria:
  // - A token shorter than the API token's 32-byte floor is refused.
  // - The placeholders the example files ship are refused whatever their length.
  // - A sound token is returned unchanged.
  it("refuses short or placeholder tokens at start", () => {
    assert.equal(MCP_TOKEN_MIN_BYTES, 32);
    assert.equal(requireMcpToken(`  ${soundToken} `), soundToken);
    assert.throws(() => requireMcpToken("k".repeat(31)), /PORTFOLIXIR_MCP_TOKEN must be at least 32 bytes/);

    for (const placeholder of [
      "replace-with-openssl-rand-base64-48",
      "replace-me-too",
      "dev-mcp-token",
      "changeme",
      "Example-token"
    ]) {
      assert.throws(
        () => requireMcpToken(placeholder.padEnd(40, "x")),
        /PORTFOLIXIR_MCP_TOKEN is a placeholder/,
        placeholder
      );
    }
  });

  // User story (E25 S1, F01; #974, the Sprint 20 plan's D-11):
  // As an operator whose companion listens over HTTP,
  // I want repeated wrong tokens from one source locked out for a growing interval,
  // so that guessing the MCP token is bounded the way guessing the API token is.
  //
  // Acceptance criteria:
  // - Wrong tokens are answered 401 and counted per source.
  // - From the threshold on, a wrong token is answered 429 with Retry-After,
  //   and it counts: the lock doubles with each one, the lock in force or not.
  // - Another source is unaffected; once the lock has run out, the right token
  //   passes and clears the count.
  it("answers repeated failures from one source with 429", () => {
    let now = 1_000;
    const throttle = createFailureThrottle();
    const auth = mcpAuthMiddleware(soundToken, throttle, () => now);

    for (let attempt = 1; attempt < throttle.maxFailures; attempt += 1) {
      assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
    }

    assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
    assert.deepEqual(throttle.check("10.0.0.5", now), { locked: true, retryAfter: throttle.baseLockSeconds });

    const locked = authenticate(auth, "Bearer wrong", "10.0.0.5");
    assert.equal(locked.statusCode, 429);
    assert.equal(locked.nextCalled, false);
    assert.deepEqual(locked.body, { errors: { detail: "too many failed attempts; retry later" } });
    assert.equal(locked.headers["retry-after"], String(throttle.baseLockSeconds * 2));

    assert.equal(authenticate(auth, `Bearer ${soundToken}`, "10.0.0.6").nextCalled, true);

    now += throttle.baseLockSeconds * 2;
    assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
    assert.equal(
      authenticate(auth, "Bearer wrong", "10.0.0.5").headers["retry-after"],
      String(throttle.baseLockSeconds * 8)
    );

    now += throttle.baseLockSeconds * 8;
    assert.equal(authenticate(auth, `Bearer ${soundToken}`, "10.0.0.5").nextCalled, true);
    assert.equal(throttle.check("10.0.0.5", now).locked, false);
    assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
  });

  // User story (#974, the Sprint 20 plan's D-11):
  // As an operator whose host clients all reach the companion's published
  // port from one address,
  // I want my agent's correct token to pass while that address is locked,
  // so that a stale client sending an old token after a rotation never locks
  // my agent out, while its wrong tokens stay refused.
  //
  // Acceptance criteria:
  // - While the source is locked, the right token reaches the next handler.
  // - The lock stays as it was: the source is still locked for the same time,
  //   and the next wrong token from it is answered 429 and counted.
  // (The 32-byte floor `requireMcpToken` holds the token to is what makes a
  // locked guesser's correct guess infeasible.)
  it("lets a correct token through a locked source, and keeps the lock", () => {
    const now = 1_000;
    const throttle = createFailureThrottle();
    const auth = mcpAuthMiddleware(soundToken, throttle, () => now);

    for (let attempt = 1; attempt <= throttle.maxFailures; attempt += 1) {
      assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
    }

    const lock = throttle.check("10.0.0.5", now);
    assert.equal(lock.locked, true);

    const admitted = authenticate(auth, `Bearer ${soundToken}`, "10.0.0.5");
    assert.equal(admitted.nextCalled, true);
    assert.equal(admitted.statusCode, 200);
    assert.deepEqual(throttle.check("10.0.0.5", now), lock);

    const refused = authenticate(auth, "Bearer wrong", "10.0.0.5");
    assert.equal(refused.statusCode, 429);
    assert.equal(refused.nextCalled, false);
    assert.equal(refused.headers["retry-after"], String(throttle.baseLockSeconds * 2));
  });

  // Issue #761: the SDK's DNS-rebinding protection is fed the names this
  // listener actually answers under.
  //
  // #956: exact by name and port, as the guides say. The loopback names (the
  // IPv6 one in brackets, as a Host header writes it) and the bound address
  // carry the listener's port only; a name in PORTFOLIXIR_MCP_ALLOWED_HOSTS
  // is listed with the port and without it (a proxy on 443 passes it bare),
  // and an entry that carries its own port is listed as it is.
  it("lists the bound host and the loopback names as allowed hosts", () => {
    assert.deepEqual(allowedHostsFor("127.0.0.1", 4001), [
      "127.0.0.1:4001",
      "localhost:4001",
      "[::1]:4001"
    ]);

    assert.deepEqual(allowedHostsFor("192.0.2.10", 4001), [
      "127.0.0.1:4001",
      "localhost:4001",
      "[::1]:4001",
      "192.0.2.10:4001"
    ]);

    assert.deepEqual(allowedHostsFor("0.0.0.0", 4001, "mcp.lan", "127.0.0.1:14001"), [
      "127.0.0.1:4001",
      "localhost:4001",
      "[::1]:4001",
      "mcp.lan:4001",
      "mcp.lan",
      "127.0.0.1:14001"
    ]);
  });

  // #1137: the host the index hands the listener; the spawned companion's
  // test in transport.test.ts pins the same through PORTFOLIXIR_MCP_HOST.
  it("reads an unset, empty or blank host as the loopback default", () => {
    assert.equal(mcpHost(undefined), "127.0.0.1");
    assert.equal(mcpHost(""), "127.0.0.1");
    assert.equal(mcpHost(" \t "), "127.0.0.1");
    assert.equal(mcpHost(" 0.0.0.0 "), "0.0.0.0");
    assert.equal(mcpHost("::1"), "::1");
  });

  // User story (#1137, Sprint 20 γ closing act):
  // As an operator who writes PORTFOLIXIR_MCP_HOST=[] (brackets around
  // nothing, as a URL would hold an IPv6 address),
  // I want the companion to bind the loopback default, as an empty value does,
  // so that an empty pair of brackets never opens the listener on every
  // interface.
  //
  // Acceptance criteria:
  // - One pair of brackets is unwrapped and its inside trimmed: `[]`, ` [] `
  //   and `[ ]` read as 127.0.0.1, `[::1]` and `[ ::1 ]` as ::1.
  // - The listener is handed 127.0.0.1 for `[]` and ` [] `, never an empty
  //   address, which Node binds on every interface. The listen is captured,
  //   never made, so the test binds nothing.
  it("reads an empty pair of brackets as the loopback default", () => {
    assert.equal(mcpHost("[]"), "127.0.0.1");
    assert.equal(mcpHost(" [] "), "127.0.0.1");
    assert.equal(mcpHost("[ ]"), "127.0.0.1");
    assert.equal(mcpHost("[::1]"), "::1");
    assert.equal(mcpHost("[ ::1 ]"), "::1");
  });

  it("hands the listener 127.0.0.1 for an empty pair of brackets", async () => {
    const original = Server.prototype.listen;
    const listened: unknown[][] = [];

    // A listen that records its arguments and fails, so nothing is bound.
    Server.prototype.listen = function (this: Server, ...args: unknown[]) {
      listened.push(args);
      process.nextTick(() => this.emit("error", Object.assign(new Error("captured"), { code: "EACCES" })));
      return this;
    } as typeof Server.prototype.listen;

    try {
      for (const host of ["[]", " [] "]) {
        await assert.rejects(
          startHttpServer({ client: { request: async () => null }, token: soundToken, host, port: 4001 }),
          /could not listen on http:\/\/127\.0\.0\.1:4001\/mcp/
        );
      }
    } finally {
      Server.prototype.listen = original;
    }

    assert.deepEqual(
      listened.map((args) => args.slice(0, 2)),
      [
        [4001, "127.0.0.1"],
        [4001, "127.0.0.1"]
      ]
    );
  });

  // User story (#1137):
  // As an operator who binds the companion to an IPv6 address,
  // I want it to answer the Host header a client sends for the URL it prints,
  // so that a client following that URL is not refused by the companion's own
  // Host guard.
  //
  // Acceptance criteria:
  // - For a bind to an IPv6 address, the allowed hosts hold the address in
  //   brackets with the port, as a URL's Host writes it, and never the bare
  //   form with the port glued on (`::1:4001`); its origin is listed the same
  //   way.
  // - For every bind, the Host of the URL the companion prints is allowed.
  // - A bare IPv6 address in PORTFOLIXIR_MCP_ALLOWED_HOSTS is listed in
  //   brackets too.
  it("answers an IPv6 bind under its own URL's Host", () => {
    assert.deepEqual(allowedHostsFor("::1", 4001), ["127.0.0.1:4001", "localhost:4001", "[::1]:4001"]);
    assert.deepEqual(allowedHostsFor("fd00::7", 4001), [
      "127.0.0.1:4001",
      "localhost:4001",
      "[::1]:4001",
      "[fd00::7]:4001"
    ]);
    assert.ok(allowedOriginsFor("fd00::7", 4001).includes("http://[fd00::7]:4001"));

    for (const host of ["127.0.0.1", "localhost", "192.0.2.10", "::1", "[::1]", "fd00::7", "[fd00::7]"]) {
      const printed = new URL(mcpUrl(host, 4001));
      assert.ok(allowedHostsFor(host, 4001).includes(printed.host), `${host}: ${printed.host}`);
      assert.ok(allowedOriginsFor(host, 4001).includes(printed.origin), `${host}: ${printed.origin}`);
    }

    assert.deepEqual(allowedHostsFor("127.0.0.1", 4001, "fd00::9").slice(3), ["[fd00::9]:4001", "[fd00::9]"]);
  });
});

// The companion's HTTP app on a loopback port the OS picks, answering under
// the Host names that port gives it; nothing leaves the machine and the API
// client is never called.
async function withApp(
  run: (base: string, port: number) => Promise<void>,
  profile: McpProfile = "full",
  boundHost = "127.0.0.1",
  extraHosts: string[] = []
): Promise<void> {
  const server = createServer();
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const port = (server.address() as AddressInfo).port;

  const app = createHttpApp({
    client: {
      request: async () => {
        throw new Error("the API is not reached by these requests");
      }
    },
    token: soundToken,
    allowedHosts: allowedHostsFor(boundHost, port, ...extraHosts),
    allowedOrigins: allowedOriginsFor(boundHost, port, ...extraHosts),
    profile
  });
  server.on("request", app);

  try {
    await run(`http://127.0.0.1:${port}`, port);
  } finally {
    server.close();
    await once(server, "close");
  }
}

interface RawAnswer {
  status: number;
  body: string;
}

// A request with headers the fetch API would not let a test set (Host).
function rawRequest(
  port: number,
  headers: Record<string, string>,
  body = "{}"
): Promise<RawAnswer> {
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      { host: "127.0.0.1", port, path: "/mcp", method: "POST", headers },
      (response) => {
        let text = "";
        response.setEncoding("utf8");
        response.on("data", (chunk: string) => (text += chunk));
        response.on("end", () => resolve({ status: response.statusCode ?? 0, body: text }));
      }
    );
    request.on("error", reject);
    request.end(body);
  });
}

const initialize = JSON.stringify({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: { name: "portfolixir-test-host", version: "0.0.0" }
  }
});

function post(base: string, body: string, authorization?: string): Promise<globalThis.Response> {
  const headers: Record<string, string> = { "content-type": "application/json" };

  if (authorization !== undefined) {
    headers.authorization = authorization;
  }

  return fetch(`${base}/mcp`, { method: "POST", headers, body });
}

describe("MCP HTTP transport", () => {
  // User story (E25 S2, F19):
  // As an operator whose companion listens over HTTP,
  // I want a request authenticated before its body is read, and every error
  // answered as a short JSON error,
  // so that an unauthenticated caller cannot make the companion parse a body,
  // and no error answer carries a stack trace or a local path.
  //
  // Acceptance criteria:
  // - A malformed or oversized body without the token is answered 401 JSON.
  // - A malformed body with the token is answered 400, an oversized one 413,
  //   each as {"errors": {"detail": <reason phrase>}} and nothing else.
  // - The app runs in Express's production mode whatever NODE_ENV says.
  it("authenticates before it reads a body", async () => {
    await withApp(async (base) => {
      for (const body of ["{", JSON.stringify({ x: "a".repeat(2 * 1024 * 1024) })]) {
        const response = await post(base, body);
        assert.equal(response.status, 401);
        assert.deepEqual(await response.json(), { errors: { detail: "unauthorized" } });
      }
    });
  });

  it("answers a malformed or oversized body with a short JSON error", async () => {
    await withApp(async (base) => {
      const malformed = await post(base, "{", `Bearer ${soundToken}`);
      assert.equal(malformed.status, 400);
      assert.match(malformed.headers.get("content-type") ?? "", /^application\/json/);
      assert.deepEqual(await malformed.json(), { errors: { detail: STATUS_CODES[400] } });

      const oversized = await post(
        base,
        JSON.stringify({ x: "a".repeat(2 * 1024 * 1024) }),
        `Bearer ${soundToken}`
      );
      assert.equal(oversized.status, 413);
      const text = await oversized.text();
      assert.deepEqual(JSON.parse(text), { errors: { detail: STATUS_CODES[413] } });
      assert.doesNotMatch(text, /\bat\s|node_modules|\.js:\d+/);
    });
  });

  // User story (E25 S2, F19, review round):
  // As an MCP client pointed at the wrong path,
  // I want the companion's 404 in the same short JSON shape as its other errors,
  // so that no answer the companion gives itself is Express's HTML page.
  //
  // Acceptance criteria:
  // - An authenticated request to a path other than /mcp is answered 404
  //   {"errors": {"detail": "Not Found"}} as JSON, for any method.
  // - Without the token the same request is still answered 401 first.
  it("answers an unknown path with a JSON 404", async () => {
    await withApp(async (base) => {
      for (const method of ["GET", "POST"]) {
        const response = await fetch(`${base}/elsewhere`, {
          method,
          headers: { authorization: `Bearer ${soundToken}` }
        });
        assert.equal(response.status, 404);
        assert.match(response.headers.get("content-type") ?? "", /^application\/json/);
        assert.deepEqual(await response.json(), { errors: { detail: STATUS_CODES[404] } });
      }

      const anonymous = await fetch(`${base}/elsewhere`);
      assert.equal(anonymous.status, 401);
    });
  });

  // User story (E25 S7, F22):
  // As an operator whose companion listens over HTTP,
  // I want a request under a Host this listener does not answer to refused
  // before anything else about it is read,
  // so that a page that rebinds its own name onto my loopback cannot drive the
  // companion, whatever the SDK's own check does.
  //
  // Acceptance criteria:
  // - A foreign Host is answered 403 before the origin and the token are
  //   checked, and it counts no failed token attempt.
  // - A loopback name under another port than the listener's is foreign.
  // - Under an allowed Host, a foreign Origin is answered 403 and a missing
  //   bearer 401; the right Host, Origin and token reach the MCP server.
  it("refuses a foreign Host ahead of the origin and the token", async () => {
    await withApp(async (_base, port) => {
      const bearer = `Bearer ${soundToken}`;
      const foreignHosts = [
        "rebound.example",
        `rebound.example:${port}`,
        "127.0.0.1:1",
        `localhost:${port + 1}`,
        // #956: a loopback name without the port is port 80, not the listener's.
        "127.0.0.1",
        "localhost"
      ];

      for (const host of foreignHosts) {
        const answer = await rawRequest(port, {
          host,
          origin: "https://rebound.example",
          "content-type": "application/json"
        });
        assert.equal(answer.status, 403, host);
        assert.deepEqual(JSON.parse(answer.body), { errors: { detail: "host not allowed" } }, host);
      }

      // The refused Hosts counted no failed attempts: the right token passes.
      for (let attempt = 0; attempt < 12; attempt += 1) {
        await rawRequest(port, { host: "rebound.example", authorization: "Bearer wrong" });
      }

      const foreignOrigin = await rawRequest(port, {
        host: `127.0.0.1:${port}`,
        origin: "https://rebound.example",
        authorization: bearer,
        "content-type": "application/json"
      });
      assert.equal(foreignOrigin.status, 403);
      assert.deepEqual(JSON.parse(foreignOrigin.body), { errors: { detail: "origin not allowed" } });

      const anonymous = await rawRequest(port, {
        host: `localhost:${port}`,
        "content-type": "application/json"
      });
      assert.equal(anonymous.status, 401);

      const admitted = await rawRequest(
        port,
        {
          host: `127.0.0.1:${port}`,
          origin: `http://127.0.0.1:${port}`,
          authorization: bearer,
          "content-type": "application/json",
          accept: "application/json, text/event-stream"
        },
        initialize
      );
      assert.equal(admitted.status, 200, admitted.body);
      assert.match(admitted.body, /"serverInfo":\{"name":"portfolixir"/);
    });
  });

  // User story (#956):
  // As an operator whose companion listens over HTTP,
  // I want a browser page on another loopback port refused by its Origin,
  // before its token is read,
  // so that the Origin check guards the port I configured, not every port of
  // the machine.
  //
  // Acceptance criteria:
  // - Under the right Host and with the right token, an Origin on another
  //   loopback port, or on the loopback name without a port, is answered 403
  //   "origin not allowed".
  // - The IPv6 loopback's origin on the listener's port reaches the MCP server.
  it("refuses an Origin on another loopback port, and admits the IPv6 loopback's", async () => {
    await withApp(async (_base, port) => {
      const headers = {
        host: `127.0.0.1:${port}`,
        authorization: `Bearer ${soundToken}`,
        "content-type": "application/json",
        accept: "application/json, text/event-stream"
      };

      for (const origin of [`http://localhost:${port + 1}`, `http://127.0.0.1:${port + 1}`, "http://localhost"]) {
        const answer = await rawRequest(port, { ...headers, origin }, initialize);
        assert.equal(answer.status, 403, origin);
        assert.deepEqual(JSON.parse(answer.body), { errors: { detail: "origin not allowed" } }, origin);
      }

      const ipv6 = await rawRequest(port, { ...headers, origin: `http://[::1]:${port}` }, initialize);
      assert.equal(ipv6.status, 200, ipv6.body);
      assert.match(ipv6.body, /"serverInfo":\{"name":"portfolixir"/);
    });
  });

  // User story (#1137):
  // As an operator who binds the companion to an IPv6 address,
  // I want a request under the Host of the URL the companion prints to reach
  // the MCP server,
  // so that neither the companion's Host guard nor the SDK's refuses it.
  //
  // Acceptance criteria:
  // - With the lists of an IPv6 bind, a request under `[address]:port` with
  //   the matching origin and the token reaches the MCP server; the bare form
  //   `address:port` is refused 403. (The app listens on IPv4 loopback here;
  //   the lists are what is under test.)
  it("lets a request under an IPv6 bind's own Host through both Host checks", async () => {
    await withApp(
      async (_base, port) => {
        const headers = {
          authorization: `Bearer ${soundToken}`,
          "content-type": "application/json",
          accept: "application/json, text/event-stream"
        };

        const own = await rawRequest(
          port,
          { ...headers, host: `[fd00::7]:${port}`, origin: `http://[fd00::7]:${port}` },
          initialize
        );
        assert.equal(own.status, 200, own.body);
        assert.match(own.body, /"serverInfo":\{"name":"portfolixir"/);

        const bare = await rawRequest(port, { ...headers, host: `fd00::7:${port}` }, initialize);
        assert.equal(bare.status, 403, bare.body);
      },
      "full",
      "fd00::7"
    );
  });

  // User story (#956, Sprint 20 γ closing act):
  // As an operator who writes a name with capitals in
  // PORTFOLIXIR_MCP_ALLOWED_HOSTS or PORTFOLIXIR_MCP_HOST (`MCP.Example.LAN`),
  // I want a browser's request under that name, which it sends in lower case,
  // to reach the MCP server,
  // so that the companion's own Host guard, which ignores case, and the SDK's
  // check, which compares exactly, give the same answer.
  //
  // Acceptance criteria:
  // - The allowed hosts hold a configured name in lower case, a bare one and
  //   one with its own port alike, and so does a bound host name.
  // - A request under the lower-case name with its origin and the token is
  //   answered 200 by the MCP server, through both Host checks.
  it("answers a configured name with capitals under its lower-case Host", async () => {
    await withApp(
      async (_base, port) => {
        const headers = {
          authorization: `Bearer ${soundToken}`,
          "content-type": "application/json",
          accept: "application/json, text/event-stream"
        };

        for (const host of [`mcp.example.lan:${port}`, "mcp.example.lan", "localhost:6274", `mybox.lan:${port}`]) {
          const answer = await rawRequest(port, { ...headers, host, origin: `http://${host}` }, initialize);
          assert.equal(answer.status, 200, `${host}: ${answer.body}`);
          assert.match(answer.body, /"serverInfo":\{"name":"portfolixir"/, host);
        }
      },
      "full",
      "MyBox.LAN",
      ["MCP.Example.LAN", "LocalHost:6274"]
    );

    assert.deepEqual(allowedHostsFor("MyBox.LAN", 4001, "MCP.Example.LAN", "LocalHost:6274"), [
      "127.0.0.1:4001",
      "localhost:4001",
      "[::1]:4001",
      "mybox.lan:4001",
      "mcp.example.lan:4001",
      "mcp.example.lan",
      "localhost:6274"
    ]);
  });

  // E25 S7, G26 and A1 (#992): the profile reaches the HTTP transport, whose
  // every request builds its own server: read lists no write, book no admin
  // tool, full every tool.
  it("serves each profile's tool list over HTTP", async () => {
    const listTools = JSON.stringify({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });

    for (const profile of ["read", "book", "full"] as const) {
      await withApp(async (_base, port) => {
        const answer = await rawRequest(
          port,
          {
            host: `127.0.0.1:${port}`,
            authorization: `Bearer ${soundToken}`,
            "content-type": "application/json",
            accept: "application/json, text/event-stream"
          },
          listTools
        );
        assert.equal(answer.status, 200, answer.body);
        assert.equal(
          answer.body.includes('"name":"portfolixir.transactions.delete"'),
          profile === "full",
          profile
        );
        assert.equal(
          answer.body.includes('"name":"portfolixir.transactions.update"'),
          profile !== "read",
          profile
        );
        assert.ok(answer.body.includes('"name":"portfolixir.transactions.list"'), profile);
      }, profile);
    }
  });

  it("runs in Express's production mode", () => {
    const app = createHttpApp({
      client: { request: async () => null },
      token: soundToken,
      allowedHosts: [],
      allowedOrigins: []
    });

    assert.equal(app.get("env"), "production");
  });

  // #1043 review round: the line that names an IPv6 address brackets it, as
  // a URL does. The port is held on ::1 where the host has IPv6; where it has
  // none, the bind fails on the address instead. Either way the listen fails,
  // so nothing is left listening.
  it("brackets an IPv6 host in the line a failed listen names", async () => {
    const holder = createServer();
    let port = 4001;

    try {
      holder.listen(0, "::1");
      await once(holder, "listening");
      port = (holder.address() as AddressInfo).port;
    } catch {
      // No IPv6 here: any port fails on the address.
    }

    try {
      await assert.rejects(
        startHttpServer({ client: { request: async () => null }, token: soundToken, host: "::1", port }),
        new RegExp(`^Error: Portfolixir MCP server could not listen on http://\\[::1\\]:${port}/mcp: E[A-Z]+`)
      );
    } finally {
      if (holder.listening) {
        holder.close();
        await once(holder, "close");
      }
    }
  });

  // User story (#1137):
  // As an operator who writes PORTFOLIXIR_MCP_HOST=[::1], as a URL writes it,
  // I want the listener to bind the IPv6 loopback as it does for ::1,
  // so that the bracketed form the URL and the allow-lists accept also starts.
  //
  // Acceptance criteria:
  // - `::1` and `[::1]` reach the same bind and fail it with the same cause:
  //   the port held on ::1 where the host has IPv6 (EADDRINUSE), the address
  //   family where it has none. Neither is looked up as a name (ENOTFOUND).
  // - The line naming either reads http://[::1]:<port>/mcp.
  it("binds a bracketed IPv6 host as its bare address", async () => {
    const holder = createServer();
    let port = 4001;
    let expected: string | undefined;

    holder.once("error", (error: NodeJS.ErrnoException) => {
      expected = error.code;
    });
    holder.listen(0, "::1");
    await Promise.race([once(holder, "listening"), once(holder, "error")]).catch(() => undefined);

    if (holder.listening) {
      port = (holder.address() as AddressInfo).port;
      expected = "EADDRINUSE";
    }

    try {
      assert.ok(expected !== undefined && expected !== "ENOTFOUND", `a bind on ::1 failed with ${expected}`);

      for (const host of ["::1", "[::1]"]) {
        await assert.rejects(
          startHttpServer({ client: { request: async () => null }, token: soundToken, host, port }),
          (error: Error) => {
            const prefix = `Portfolixir MCP server could not listen on http://[::1]:${port}/mcp: `;

            assert.ok(error.message.startsWith(prefix), `${host}: ${error.message}`);
            assert.equal(/^E[A-Z]+/.exec(error.message.slice(prefix.length))?.[0], expected, `${host}: ${error.message}`);
            return true;
          }
        );
      }
    } finally {
      if (holder.listening) {
        holder.close();
        await once(holder, "close");
      }
    }
  });

  // #1043 review round: PORTFOLIXIR_MCP_HOST=[::1] is an IPv6 host already
  // in brackets; the line naming it reads http://[::1]:…, never
  // http://[[::1]]:…. Read without a listen, so no name is resolved.
  it("brackets an IPv6 host once, and leaves a bracketed one as it is", () => {
    assert.equal(mcpUrl("::1", 4001), "http://[::1]:4001/mcp");
    assert.equal(mcpUrl("[::1]", 4001), "http://[::1]:4001/mcp");
    assert.equal(mcpUrl("[fd00::7]", 4002), "http://[fd00::7]:4002/mcp");
    assert.equal(mcpUrl("127.0.0.1", 4001), "http://127.0.0.1:4001/mcp");
    assert.equal(mcpUrl("localhost", 4001), "http://localhost:4001/mcp");
  });
});
