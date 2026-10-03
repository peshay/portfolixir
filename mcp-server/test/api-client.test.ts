import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { describe, it } from "node:test";

import {
  ApiOutcomeUnknownError,
  ApiReadTimeoutError,
  ApiRedirectError,
  createApiClient
} from "../src/api-client.js";

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

  // User story (E25 S7, G31):
  // As the agent whose write got no answer in time,
  // I want the companion to tell me the outcome is unknown and to re-read
  // before retrying,
  // so that a retry does not leave a permanent duplicate the server had
  // already committed.
  //
  // Acceptance criteria:
  // - A POST, PUT, PATCH or DELETE that times out or is aborted answers
  //   ApiOutcomeUnknownError, naming the request, the unknown outcome and the
  //   re-read.
  // - A GET that times out answers no such error: a read changes nothing.
  it("answers a write that got no answer in time as outcome unknown", async () => {
    const hanging = (reason?: () => unknown) =>
      createApiClient({
        baseUrl: "http://portfolixir.test",
        token: "api-token",
        timeoutMs: 20,
        fetch: (_url, init) =>
          new Promise<Response>((_resolve, reject) => {
            if (reason !== undefined) {
              reject(reason());
              return;
            }

            // The deadline's own timer does not hold the event loop open; this
            // one does, and fails the test if the deadline never fires.
            const guard = setTimeout(() => reject(new Error("the deadline never fired")), 5_000);
            init?.signal?.addEventListener("abort", () => {
              clearTimeout(guard);
              reject(init.signal?.reason);
            });
          })
      });

    for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
      await assert.rejects(hanging().request(method, "/api/v1/transactions/9", {}), (error: unknown) => {
        assert.ok(error instanceof ApiOutcomeUnknownError, `${method}: ${String(error)}`);
        assert.equal(error.name, "ApiOutcomeUnknownError");
        assert.match(error.message, new RegExp(`${method} /api/v1/transactions/9`));
        assert.match(error.message, /outcome unknown/);
        assert.match(error.message, /may still have committed it/);
        assert.match(error.message, /Re-read/);
        return true;
      });
    }

    await assert.rejects(
      hanging(() => new DOMException("aborted", "AbortError")).request("POST", "/api/v1/splits", {}),
      ApiOutcomeUnknownError
    );

    await assert.rejects(hanging().request("GET", "/api/v1/transactions"), (error: unknown) => {
      assert.ok(!(error instanceof ApiOutcomeUnknownError), String(error));
      assert.ok(error instanceof ApiReadTimeoutError, String(error));
      return true;
    });

    // E25 S7 review round (R3): a read-only tool routed through POST says
    // so, and its timeout is a read's.
    await assert.rejects(
      hanging().request("POST", "/api/v1/holdings/reconcile", {}, { readOnly: true }),
      (error: unknown) => {
        assert.ok(error instanceof ApiReadTimeoutError, String(error));
        assert.match((error as Error).message, /POST \/api\/v1\/holdings\/reconcile/);
        assert.match((error as Error).message, /changes nothing/);
        return true;
      }
    );
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

  // User story (#955, the G31 finding widened):
  // As the agent whose write lost its connection after the request had left
  // the companion,
  // I want the companion to tell me the outcome is unknown, as it does for a
  // timeout,
  // so that I re-read before retrying instead of storing a duplicate the
  // server had already committed.
  //
  // Acceptance criteria:
  // - A POST, PUT, PATCH or DELETE whose connection fails after the request
  //   was sent (a reset, a socket closed while the answer arrives, any
  //   failure the request cannot be shown to have missed the server by)
  //   answers ApiOutcomeUnknownError, naming the request, the lost
  //   connection, its code and the re-read.
  // - A failure that proves the request never reached the server (connection
  //   refused, name not resolved, host unreachable, the connect timing out)
  //   stays a plain error, which is safe to retry.
  // - A read's failure stays a plain error, whatever its cause: a read
  //   changes nothing.
  // - Against real sockets: a server that drops the connection after reading
  //   the request, and one that drops it mid-answer, both answer outcome
  //   unknown for a POST; a closed port answers a plain refusal.
  describe("a lost connection", () => {
    const failing = (error: unknown) =>
      createApiClient({
        baseUrl: "http://portfolixir.test",
        token: "api-token",
        fetch: async () => {
          throw error;
        }
      });

    const fetchFailed = (code: string) =>
      new TypeError("fetch failed", { cause: Object.assign(new Error(code), { code }) });

    it("answers a write cut off after it was sent as outcome unknown", async () => {
      const cutOff = [
        fetchFailed("ECONNRESET"),
        fetchFailed("UND_ERR_SOCKET"),
        fetchFailed("EPIPE"),
        fetchFailed("ETIMEDOUT"),
        new TypeError("terminated", {
          cause: Object.assign(new Error("other side closed"), { code: "UND_ERR_SOCKET" })
        }),
        new TypeError("fetch failed")
      ];

      for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
        for (const error of cutOff) {
          await assert.rejects(
            failing(error).request(method, "/api/v1/transactions/9", {}),
            (raised: unknown) => {
              assert.ok(raised instanceof ApiOutcomeUnknownError, `${method}: ${String(raised)}`);
              assert.match(raised.message, new RegExp(`${method} /api/v1/transactions/9`));
              assert.match(raised.message, /outcome unknown/);
              assert.match(raised.message, /lost its connection/);
              assert.match(raised.message, /may still have committed it/);
              assert.match(raised.message, /Re-read/);
              return true;
            }
          );
        }
      }

      await assert.rejects(failing(fetchFailed("ECONNRESET")).request("POST", "/x", {}), /ECONNRESET/);
    });

    it("keeps a failure that never reached the server a plain, retryable error", async () => {
      for (const code of [
        "ECONNREFUSED",
        "ENOTFOUND",
        "EAI_AGAIN",
        "EHOSTUNREACH",
        "ENETUNREACH",
        "UND_ERR_CONNECT_TIMEOUT"
      ]) {
        const error = fetchFailed(code);

        await assert.rejects(failing(error).request("POST", "/api/v1/transactions", {}), (raised) => {
          assert.equal(raised, error, code);
          return true;
        });
      }
    });

    it("keeps a read's failure a plain error", async () => {
      const error = fetchFailed("ECONNRESET");

      await assert.rejects(failing(error).request("GET", "/api/v1/transactions"), (raised) => {
        assert.equal(raised, error);
        return true;
      });

      await assert.rejects(
        failing(error).request("POST", "/api/v1/holdings/reconcile", {}, { readOnly: true }),
        (raised) => {
          assert.equal(raised, error);
          return true;
        }
      );
    });

    it("answers a write whose socket a real server drops as outcome unknown", async () => {
      const received: string[] = [];
      const dropping = createServer((req, res) => {
        received.push(`${req.method} ${req.url}`);

        if (req.url === "/mid-answer") {
          res.writeHead(201, { "content-type": "application/json" });
          res.write('{"data": {"id"');
          setTimeout(() => res.socket?.destroy(), 10);
        } else {
          req.resume();
          req.on("end", () => req.socket.destroy());
        }
      });
      const port = await listen(dropping);

      try {
        const client = createApiClient({ baseUrl: `http://127.0.0.1:${port}`, token: "t" });

        for (const path of ["/before-answer", "/mid-answer"]) {
          await assert.rejects(client.request("POST", path, { amount: "1" }), (raised: unknown) => {
            assert.ok(raised instanceof ApiOutcomeUnknownError, `${path}: ${String(raised)}`);
            return true;
          });
        }

        assert.deepEqual(received, ["POST /before-answer", "POST /mid-answer"]);
      } finally {
        await shut(dropping);
      }
    });

    it("keeps a refused connection to a real port a plain error", async () => {
      const closed = createServer();
      const port = await listen(closed);
      await shut(closed);

      const client = createApiClient({ baseUrl: `http://127.0.0.1:${port}`, token: "t" });

      await assert.rejects(client.request("POST", "/api/v1/transactions", {}), (raised: unknown) => {
        assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
        return true;
      });
    });
  });
});
