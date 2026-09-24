import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { NextFunction, Request, Response } from "express";

import {
  isAllowedOrigin,
  isAuthorizedMcpRequest,
  requireMcpToken,
  allowedHostsFor,
  createFailureThrottle,
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
