import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { isAllowedOrigin, isAuthorizedMcpRequest } from "../src/http.js";

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
});
