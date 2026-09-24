import assert from "node:assert/strict";
import { once } from "node:events";
import { STATUS_CODES } from "node:http";
import type { AddressInfo } from "node:net";
import { describe, it } from "node:test";

import type { NextFunction, Request, Response } from "express";

import {
  isAllowedOrigin,
  isAuthorizedMcpRequest,
  requireMcpToken,
  allowedHostsFor,
  createFailureThrottle,
  createHttpApp,
  mcpAuthMiddleware,
  MCP_TOKEN_MIN_BYTES
} from "../src/http.js";

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
  it("allows localhost origins and rejects non-local origins", () => {
    assert.equal(isAllowedOrigin(undefined), true);
    assert.equal(isAllowedOrigin("http://127.0.0.1:4001"), true);
    assert.equal(isAllowedOrigin("http://localhost:4001"), true);
    assert.equal(isAllowedOrigin("https://example.com"), false);
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

  // User story (E25 S1, F01):
  // As an operator whose companion listens over HTTP,
  // I want repeated wrong tokens from one source locked out for a growing interval,
  // so that guessing the MCP token is bounded the way guessing the API token is.
  //
  // Acceptance criteria:
  // - Wrong tokens are answered 401 and counted per source.
  // - From the threshold on, the source is answered 429 with Retry-After before
  //   the token is compared, right token or wrong; the lock doubles per further failure.
  // - Another source is unaffected; after the lock the right token passes and clears the count.
  it("answers repeated failures from one source with 429", () => {
    let now = 1_000;
    const throttle = createFailureThrottle();
    const auth = mcpAuthMiddleware(soundToken, throttle, () => now);

    for (let attempt = 1; attempt < throttle.maxFailures; attempt += 1) {
      assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
    }

    assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);

    const locked = authenticate(auth, `Bearer ${soundToken}`, "10.0.0.5");
    assert.equal(locked.statusCode, 429);
    assert.equal(locked.nextCalled, false);
    assert.equal(locked.headers["retry-after"], String(throttle.baseLockSeconds));

    assert.equal(authenticate(auth, `Bearer ${soundToken}`, "10.0.0.6").nextCalled, true);

    now += throttle.baseLockSeconds;
    assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
    assert.equal(
      authenticate(auth, `Bearer ${soundToken}`, "10.0.0.5").headers["retry-after"],
      String(throttle.baseLockSeconds * 2)
    );

    now += throttle.baseLockSeconds * 2;
    assert.equal(authenticate(auth, `Bearer ${soundToken}`, "10.0.0.5").nextCalled, true);
    assert.equal(throttle.check("10.0.0.5", now).locked, false);
    assert.equal(authenticate(auth, "Bearer wrong", "10.0.0.5").statusCode, 401);
  });

  // Issue #761: the SDK's DNS-rebinding protection is fed the names this
  // listener actually answers under, with and without the port.
  it("lists the bound host and the loopback names as allowed hosts", () => {
    assert.deepEqual(allowedHostsFor("127.0.0.1", 4001), [
      "127.0.0.1:4001",
      "127.0.0.1",
      "localhost:4001",
      "localhost"
    ]);

    assert.deepEqual(allowedHostsFor("0.0.0.0", 4001, "mcp.lan"), [
      "127.0.0.1:4001",
      "127.0.0.1",
      "localhost:4001",
      "localhost",
      "mcp.lan:4001",
      "mcp.lan"
    ]);
  });
});

// The companion's HTTP app on a loopback port the OS picks; nothing leaves
// the machine and the API client is never called.
async function withApp(run: (base: string) => Promise<void>): Promise<void> {
  const app = createHttpApp({
    client: {
      request: async () => {
        throw new Error("the API is not reached by these requests");
      }
    },
    token: soundToken,
    allowedHosts: allowedHostsFor("127.0.0.1", 0)
  });
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");

  try {
    await run(`http://127.0.0.1:${(server.address() as AddressInfo).port}`);
  } finally {
    server.close();
    await once(server, "close");
  }
}

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

  it("runs in Express's production mode", () => {
    const app = createHttpApp({
      client: { request: async () => null },
      token: soundToken,
      allowedHosts: []
    });

    assert.equal(app.get("env"), "production");
  });
});
