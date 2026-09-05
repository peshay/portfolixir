import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { isAllowedOrigin, isAuthorizedMcpRequest, requireMcpToken, allowedHostsFor } from "../src/http.js";

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
    assert.equal(requireMcpToken("mcp-token"), "mcp-token");
    assert.throws(() => requireMcpToken(undefined), /PORTFOLIXIR_MCP_TOKEN/);
    assert.throws(() => requireMcpToken("   "), /PORTFOLIXIR_MCP_TOKEN/);
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
