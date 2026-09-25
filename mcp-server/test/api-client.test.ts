import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { describe, it } from "node:test";

import { ApiRedirectError, createApiClient } from "../src/api-client.js";

async function listen(server: Server): Promise<number> {
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return (server.address() as AddressInfo).port;
}

async function shut(server: Server): Promise<void> {
  server.close();
  await once(server, "close");
}

describe("the companion's API client", () => {
  // User story (E25 S7, F23):
  // As an operator whose API answers the companion with a redirect (forced
  // TLS in front of the internal address, a moved base URL),
  // I want the companion to stop at the redirect with an error that says so,
  // so that a write's body and the bearer token are never resent to wherever
  // the redirect points.
  //
  // Acceptance criteria:
  // - Every request asks for no redirect to be followed.
  // - Any 3xx answer is refused with ApiRedirectError, naming the status, the
  //   request and the variable to correct; nothing is parsed from it.
  // - Against a real listener, the redirect's target is never contacted.
  it("refuses any redirect by name", async () => {
    const inits: RequestInit[] = [];

    for (const status of [300, 301, 302, 303, 307, 308]) {
      const client = createApiClient({
        baseUrl: "http://portfolixir.test",
        token: "api-token",
        fetch: async (_url, init) => {
          inits.push(init ?? {});
          return new Response(null, {
            status,
            headers: { location: "http://elsewhere.test/api/v1/transactions" }
          });
        }
      });

      await assert.rejects(
        client.request("POST", "/api/v1/transactions", { transaction: {} }),
        (error: unknown) => {
          assert.ok(error instanceof ApiRedirectError, String(error));
          assert.equal(error.name, "ApiRedirectError");
          assert.equal(error.status, status);
          assert.match(error.message, new RegExp(`\\b${status}\\b`));
          assert.match(error.message, /POST \/api\/v1\/transactions/);
          assert.match(error.message, /PORTFOLIXIR_API_BASE_URL/);
          assert.doesNotMatch(error.message, /elsewhere\.test/);
          return true;
        }
      );
    }

    assert.ok(inits.length === 6 && inits.every((init) => init.redirect === "manual"));
  });

  it("never contacts a redirect's target", async () => {
    const reached: string[] = [];
    const target = createServer((req, res) => {
      reached.push(`${req.method} ${req.url} ${req.headers.authorization ?? ""}`);
      res.writeHead(200, { "content-type": "application/json" }).end("{}");
    });
    const targetPort = await listen(target);

    const origin = createServer((req, res) => {
      res.writeHead(307, { location: `http://127.0.0.1:${targetPort}${req.url}` }).end();
    });
    const originPort = await listen(origin);

    try {
      const client = createApiClient({
        baseUrl: `http://127.0.0.1:${originPort}`,
        token: "api-token"
      });

      await assert.rejects(
        client.request("POST", "/api/v1/transactions", { transaction: { notes: "x" } }),
        ApiRedirectError
      );
      await assert.rejects(client.request("GET", "/api/v1/securities"), ApiRedirectError);
      assert.deepEqual(reached, []);
    } finally {
      await shut(origin);
      await shut(target);
    }
  });
});
