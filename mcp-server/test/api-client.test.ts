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
  // - A POST, PUT, PATCH or DELETE whose connection fails in any way the
  //   request cannot be shown to have missed the server by (a reset, a
  //   socket closed while the answer arrives, a TLS failure, a failure that
  //   carries no code) answers ApiOutcomeUnknownError, naming the request,
  //   the failure's code, that the request may have been sent, and the
  //   re-read. It never claims the request was sent: it cannot know.
  // - A failure that proves the request never reached the server (connection
  //   refused, name not resolved, host or network unreachable, the address
  //   family unsupported or the local address unavailable, the connect
  //   timing out, a base URL that does not parse) stays a plain error, which
  //   is safe to retry.
  // - A connect that failed on every address a name resolves to (Node's
  //   happy eyeballs, one AggregateError whose own code is only its first
  //   member's) is never sent only when every member is such a failure; one
  //   member that may have carried the request makes the write's outcome
  //   unknown, and the message names every member's code (#955 review round).
  // - A read's failure stays a plain error, whatever its cause: a read
  //   changes nothing.
  // - Against real sockets: a server that drops the connection after reading
  //   the request, and one that drops it mid-answer, both answer outcome
  //   unknown for a POST; a closed port answers a plain refusal, and so does
  //   a base URL that does not parse.
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

    // What undici raises when Node's happy eyeballs (autoSelectFamily) fails
    // on every address a name resolves to: one AggregateError, one member per
    // address tried, whose own code Node copies from the first member only.
    const allAddressesFailed = (...codes: Array<string | undefined>) =>
      new TypeError("fetch failed", {
        cause: Object.assign(
          new AggregateError(codes.map((code) => Object.assign(new Error(code ?? "no code"), { code }))),
          { code: codes[0] }
        )
      });

    it("answers a write that may have been sent as outcome unknown", async () => {
      const cutOff = [
        fetchFailed("ECONNRESET"),
        fetchFailed("UND_ERR_SOCKET"),
        fetchFailed("EPIPE"),
        fetchFailed("ETIMEDOUT"),
        new TypeError("terminated", {
          cause: Object.assign(new Error("other side closed"), { code: "UND_ERR_SOCKET" })
        }),
        fetchFailed("ERR_SSL_WRONG_VERSION_NUMBER"),
        new TypeError("fetch failed", { cause: new Error("unknown scheme") }),
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
              assert.match(raised.message, /the request may have been sent/);
              assert.doesNotMatch(raised.message, /after the request was sent/);
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
        "EAFNOSUPPORT",
        "EADDRNOTAVAIL",
        "UND_ERR_CONNECT_TIMEOUT",
        "ERR_INVALID_URL"
      ]) {
        const error = fetchFailed(code);

        await assert.rejects(failing(error).request("POST", "/api/v1/transactions", {}), (raised) => {
          assert.equal(raised, error, code);
          return true;
        });
      }
    });

    it("keeps a connect that failed on every address a plain, retryable error", async () => {
      for (const codes of [
        ["EAFNOSUPPORT", "ECONNREFUSED"],
        ["EADDRNOTAVAIL", "ECONNREFUSED"],
        ["ECONNREFUSED", "ECONNREFUSED"],
        ["ENETUNREACH", "EHOSTUNREACH"]
      ]) {
        const error = allAddressesFailed(...codes);

        await assert.rejects(failing(error).request("POST", "/api/v1/transactions", {}), (raised) => {
          assert.equal(raised, error, codes.join(", "));
          return true;
        });

        // The aggregate thrown as it is, not wrapped by fetch, reads the same.
        const bare = (error as { cause: unknown }).cause;
        await assert.rejects(failing(bare).request("POST", "/api/v1/transactions", {}), (raised) => {
          assert.equal(raised, bare, codes.join(", "));
          return true;
        });
      }
    });

    it("answers a connect on every address with one member that may have been sent as outcome unknown", async () => {
      for (const [codes, named] of [
        [["EAFNOSUPPORT", "ECONNRESET"], /\(EAFNOSUPPORT, ECONNRESET\)/],
        [["ECONNREFUSED", "ETIMEDOUT"], /\(ECONNREFUSED, ETIMEDOUT\)/],
        [["ECONNREFUSED", undefined], /\(ECONNREFUSED, unknown\)/]
      ] as const) {
        await assert.rejects(
          failing(allAddressesFailed(...codes)).request("POST", "/api/v1/transactions", {}),
          (raised: unknown) => {
            assert.ok(raised instanceof ApiOutcomeUnknownError, `${codes.join(", ")}: ${String(raised)}`);
            assert.match(raised.message, named);
            assert.match(raised.message, /the request may have been sent/);
            assert.match(raised.message, /Re-read/);
            return true;
          }
        );
      }

      // An aggregate with no members proves nothing about any address.
      await assert.rejects(
        failing(new TypeError("fetch failed", { cause: new AggregateError([]) })).request("POST", "/x", {}),
        ApiOutcomeUnknownError
      );
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

    it("keeps a base URL that does not parse a plain error", async () => {
      // The real fetch: the URL fails to parse before any connect is tried.
      const client = createApiClient({ baseUrl: "not a url", token: "t" });

      await assert.rejects(client.request("POST", "/api/v1/transactions", {}), (raised: unknown) => {
        assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
        assert.equal((raised as { cause?: { code?: unknown } }).cause?.code, "ERR_INVALID_URL");
        return true;
      });
    });
  });

  // User story (#1045, Sprint 19 plan, PR β B3):
  // As the agent whose companion reaches the API through a reverse proxy,
  // I want a write the proxy answered 502 or 504 to read as outcome unknown,
  // and any answer whose body is not JSON to name its status and quote it,
  // so that I re-read before retrying a write the server may have committed,
  // and never meet a bare parse failure that hides what answered.
  //
  // Acceptance criteria:
  // - A POST, PUT, PATCH or DELETE answered 502 or 504 answers
  //   ApiOutcomeUnknownError whatever the body, naming the status, that the
  //   gateway answered instead of the server, and the re-read.
  // - A read (a GET, or a request sent readOnly) answered 502 or 504 is a
  //   plain error that names the status and says a retry is safe.
  // - A write answered 2xx with a body that is not JSON answers
  //   ApiOutcomeUnknownError: the server may have committed it, and its
  //   answer cannot be read.
  // - Any other answer whose body is not JSON is a plain error naming the
  //   status and quoting at most 120 characters of the body, whitespace
  //   collapsed, invisible characters spelled out, with the body's length in
  //   bytes when it was cut. No answer surfaces as a SyntaxError.
  // - A JSON error answer and an empty body read as they did.
  describe("an answer that is not the API's", () => {
    const answering = (status: number, body: string | null, contentType = "text/html") =>
      createApiClient({
        baseUrl: "http://portfolixir.test",
        token: "api-token",
        fetch: async () => new Response(body, { status, headers: { "content-type": contentType } })
      });

    // A reverse proxy's error page, the shape nginx answers with: longer
    // than the excerpt once its whitespace is collapsed.
    const gatewayPage = (status: number, reason: string) =>
      `<html>\r\n<head><title>${status} ${reason}</title></head>\r\n<body>\r\n` +
      `<center><h1>${status} ${reason}</h1></center>\r\n<hr><center>nginx</center>\r\n` +
      "</body>\r\n</html>\r\n";

    // The first JSON-quoted string after the status, as the message quotes it.
    const quotedExcerpt = (message: string): string => {
      const match = /: ("(?:[^"\\]|\\.)*")/.exec(message);
      assert.ok(match, `no quoted excerpt in: ${message}`);
      return JSON.parse(match[1]) as string;
    };

    const notASyntaxError = (raised: unknown): void => {
      assert.ok(raised instanceof Error, String(raised));
      assert.ok(!(raised instanceof SyntaxError), String(raised));
      assert.doesNotMatch(raised.message, /Unexpected token|is not valid JSON/);
    };

    it("answers a write a gateway answered 502 with a page as outcome unknown", async () => {
      for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
        await assert.rejects(
          answering(502, gatewayPage(502, "Bad Gateway")).request(method, "/api/v1/transactions/9", {}),
          (raised: unknown) => {
            notASyntaxError(raised);
            assert.ok(raised instanceof ApiOutcomeUnknownError, `${method}: ${String(raised)}`);
            assert.match(raised.message, new RegExp(`${method} /api/v1/transactions/9`));
            assert.match(raised.message, /outcome unknown/);
            assert.match(raised.message, /the gateway answered 502 instead\b/i);
            assert.match(raised.message, /may still have committed it/);
            assert.match(
              raised.message,
              /Re-read the records it would have changed before retrying/
            );
            assert.match(quotedExcerpt(raised.message), /^<html> <head><title>502 Bad Gateway/);
            return true;
          }
        );
      }

      // A proxy that answers 502 with no body at all reads the same.
      await assert.rejects(
        answering(502, null).request("POST", "/api/v1/transactions", {}),
        (raised: unknown) => {
          assert.ok(raised instanceof ApiOutcomeUnknownError, String(raised));
          assert.match(raised.message, /the gateway answered 502 instead\b/i);
          return true;
        }
      );

      // Against a real socket: a stand-in proxy that read the write and
      // answered its own page.
      const received: string[] = [];
      const proxy = createServer((req, res) => {
        received.push(`${req.method} ${req.url}`);
        req.resume();
        req.on("end", () => {
          res.writeHead(502, { "content-type": "text/html" }).end(gatewayPage(502, "Bad Gateway"));
        });
      });
      const port = await listen(proxy);

      try {
        const client = createApiClient({ baseUrl: `http://127.0.0.1:${port}`, token: "t" });

        await assert.rejects(
          client.request("POST", "/api/v1/transactions", { amount: "1" }),
          ApiOutcomeUnknownError
        );
        assert.deepEqual(received, ["POST /api/v1/transactions"]);
      } finally {
        await shut(proxy);
      }
    });

    it("answers a write a gateway answered 504 with JSON that is not the API's envelope as outcome unknown", async () => {
      // JSON without a top-level errors object is not the API's error
      // envelope, so a gateway wrote it.
      for (const body of [
        JSON.stringify({ message: "upstream timed out" }),
        JSON.stringify({ errors: "upstream timed out" }),
        JSON.stringify({ errors: ["upstream timed out"] }),
        JSON.stringify({ errors: null }),
        JSON.stringify([{ errors: { detail: "upstream timed out" } }]),
        "null"
      ]) {
        for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
          await assert.rejects(
            answering(504, body, "application/json").request(method, "/api/v1/splits", {}),
            (raised: unknown) => {
              notASyntaxError(raised);
              assert.ok(raised instanceof ApiOutcomeUnknownError, `${method} ${body}: ${String(raised)}`);
              assert.match(raised.message, /the gateway answered 504 instead\b/i);
              assert.match(raised.message, /Re-read/);
              assert.equal(quotedExcerpt(raised.message), body);
              return true;
            }
          );
        }
      }
    });

    // The API answers 502 itself, in its own error envelope, when the rate
    // provider fails during POST /api/v1/exchange_rates/sync, and stores
    // nothing (exchange_rate_controller.ex). That is the server's answer, not
    // a gateway's: nothing about the write is unknown. The API answers no 504,
    // so a 504 in the same envelope is a gateway's and stays unknown.
    it("keeps a write the API answered 502 in its own error envelope a plain error", async () => {
      const envelope = '{"errors":{"detail":"the rate provider could not be reached"}}';

      await assert.rejects(
        answering(502, envelope, "application/json").request("POST", "/api/v1/exchange_rates/sync", {
          scope: "latest"
        }),
        (raised: unknown) => {
          notASyntaxError(raised);
          assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
          assert.equal(
            (raised as Error).message,
            'Portfolixir API request failed: 502 {"errors":{"detail":"the rate provider could not be reached"}}'
          );
          return true;
        }
      );

      for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
        await assert.rejects(
          answering(504, '{"errors":{"amount":["is invalid"]}}', "application/json").request(
            method,
            "/api/v1/transactions/9",
            {}
          ),
          (raised: unknown) => {
            assert.ok(raised instanceof ApiOutcomeUnknownError, `${method}: ${String(raised)}`);
            assert.match(raised.message, /the gateway answered 504 instead\b/i);
            return true;
          }
        );
      }
    });

    // Cloudflare answers 520 when the origin's answer was unusable and 524
    // when the origin took the request and did not answer in time: both
    // forwarded the request, as a 502 or 504 does.
    it("answers Cloudflare's 520 and 524 as a 504 is answered", async () => {
      for (const status of [520, 524]) {
        for (const body of [gatewayPage(status, "Origin Error"), '{"errors":{"detail":"x"}}', null]) {
          await assert.rejects(
            answering(status, body).request("POST", "/api/v1/transactions", {}),
            (raised: unknown) => {
              notASyntaxError(raised);
              assert.ok(raised instanceof ApiOutcomeUnknownError, `${status} ${body}: ${String(raised)}`);
              assert.match(raised.message, new RegExp(`the gateway answered ${status} instead\\b`, "i"));
              assert.match(raised.message, /Re-read/);
              return true;
            }
          );
        }

        await assert.rejects(
          answering(status, gatewayPage(status, "Origin Error")).request("GET", "/api/v1/transactions"),
          (raised: unknown) => {
            notASyntaxError(raised);
            assert.ok(!(raised instanceof ApiOutcomeUnknownError), `${status}: ${String(raised)}`);
            assert.match((raised as Error).message, new RegExp(`GET /api/v1/transactions answered ${status}`));
            assert.match((raised as Error).message, /the call changes nothing, so it can be retried/);
            return true;
          }
        );
      }
    });

    it("answers a read a gateway answered 502 or 504 as a plain error that says a retry is safe", async () => {
      const reads = [
        (client: ReturnType<typeof answering>) => client.request("GET", "/api/v1/transactions"),
        (client: ReturnType<typeof answering>) =>
          client.request("POST", "/api/v1/holdings/reconcile", {}, { readOnly: true })
      ];

      for (const read of reads) {
        await assert.rejects(read(answering(502, gatewayPage(502, "Bad Gateway"))), (raised: unknown) => {
          notASyntaxError(raised);
          assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
          assert.match((raised as Error).message, /\b502\b/);
          assert.match(quotedExcerpt((raised as Error).message), /502 Bad Gateway/);
          assert.match((raised as Error).message, /the gateway answered 502 instead\b/i);
          assert.match((raised as Error).message, /the call changes nothing, so it can be retried/);
          return true;
        });

        // A JSON body keeps the JSON error's shape and says the same.
        await assert.rejects(
          read(answering(504, '{"message":"upstream timed out"}', "application/json")),
          (raised: unknown) => {
            notASyntaxError(raised);
            assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
            assert.match(
              (raised as Error).message,
              /^Portfolixir API request failed: 504 \{"message":"upstream timed out"\}/
            );
            assert.match((raised as Error).message, /the gateway answered 504 instead\b/i);
            assert.match((raised as Error).message, /the call changes nothing, so it can be retried/);
            return true;
          }
        );

        // The API's own envelope is the server's answer: the read is still
        // safe to retry, and no gateway is named.
        await assert.rejects(
          read(answering(502, '{"errors":{"detail":"upstream timed out"}}', "application/json")),
          (raised: unknown) => {
            assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
            assert.match(
              (raised as Error).message,
              /^Portfolixir API request failed: 502 \{"errors":\{"detail":"upstream timed out"\}\}/
            );
            assert.doesNotMatch((raised as Error).message, /gateway/);
            assert.match((raised as Error).message, /The call changes nothing, so it can be retried/);
            return true;
          }
        );
      }
    });

    it("answers a read a gateway answered with no body as such, not as null", async () => {
      for (const [status, body] of [
        [502, null],
        [504, ""],
        [524, " \r\n"]
      ] as const) {
        for (const read of [
          () => answering(status, body).request("GET", "/api/v1/transactions"),
          () => answering(status, body).request("POST", "/api/v1/holdings/reconcile", {}, { readOnly: true })
        ]) {
          await assert.rejects(read(), (raised: unknown) => {
            assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
            assert.match((raised as Error).message, new RegExp(`answered ${status} with no body\\.`));
            assert.match((raised as Error).message, /the call changes nothing, so it can be retried/);
            assert.doesNotMatch((raised as Error).message, /null/);
            return true;
          });
        }
      }
    });

    it("keeps a write's JSON error as it was", async () => {
      const client = answering(422, '{"errors":{"quantity":["must be positive"]}}', "application/json");

      await assert.rejects(client.request("POST", "/api/v1/transactions", {}), (raised: unknown) => {
        assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
        assert.equal(
          (raised as Error).message,
          'Portfolixir API request failed: 422 {"errors":{"quantity":["must be positive"]}}'
        );
        return true;
      });
    });

    it("answers a proxy's 413 page as a plain error naming the status and the excerpt", async () => {
      for (const method of ["POST", "GET"]) {
        await assert.rejects(
          answering(413, gatewayPage(413, "Request Entity Too Large")).request(
            method,
            "/api/v1/imports",
            method === "GET" ? undefined : {}
          ),
          (raised: unknown) => {
            notASyntaxError(raised);
            assert.ok(!(raised instanceof ApiOutcomeUnknownError), `${method}: ${String(raised)}`);
            assert.match((raised as Error).message, new RegExp(`${method} /api/v1/imports answered 413`));
            assert.match((raised as Error).message, /not JSON/);
            assert.match(quotedExcerpt((raised as Error).message), /413 Request Entity Too Large/);
            assert.doesNotMatch((raised as Error).message, /gateway|can be retried/);
            return true;
          }
        );
      }
    });

    it("keeps a write a proxy answered 503 a plain error", async () => {
      // A proxy answers 503 when it never forwarded the request.
      await assert.rejects(
        answering(503, gatewayPage(503, "Service Temporarily Unavailable")).request(
          "POST",
          "/api/v1/transactions",
          {}
        ),
        (raised: unknown) => {
          notASyntaxError(raised);
          assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
          assert.match((raised as Error).message, /POST \/api\/v1\/transactions answered 503/);
          assert.match(quotedExcerpt((raised as Error).message), /503 Service Temporarily Unavailable/);
          assert.doesNotMatch((raised as Error).message, /gateway answered|can be retried/);
          return true;
        }
      );

      await assert.rejects(
        answering(503, '{"errors":{"detail":"Service Unavailable"}}', "application/json").request(
          "POST",
          "/api/v1/transactions",
          {}
        ),
        (raised: unknown) => {
          assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
          assert.equal(
            (raised as Error).message,
            'Portfolixir API request failed: 503 {"errors":{"detail":"Service Unavailable"}}'
          );
          return true;
        }
      );
    });

    it("answers a write answered 2xx with a body that is not JSON as outcome unknown", async () => {
      for (const [method, status] of [
        ["POST", 200],
        ["POST", 201],
        ["PUT", 200],
        ["DELETE", 200]
      ] as const) {
        await assert.rejects(
          answering(status, "<html><body>Welcome</body></html>").request(method, "/api/v1/transactions", {}),
          (raised: unknown) => {
            notASyntaxError(raised);
            assert.ok(raised instanceof ApiOutcomeUnknownError, `${method} ${status}: ${String(raised)}`);
            assert.match(raised.message, new RegExp(`${method} /api/v1/transactions was answered ${status}`));
            assert.match(raised.message, /not JSON/);
            assert.match(raised.message, /may still have committed it/);
            assert.match(raised.message, /Re-read/);
            assert.equal(quotedExcerpt(raised.message), "<html><body>Welcome</body></html>");
            return true;
          }
        );
      }
    });

    it("answers a read answered 200 with a body that is not JSON as a plain error", async () => {
      const client = answering(200, "<html><body>Welcome</body></html>");

      for (const read of [
        () => client.request("GET", "/api/v1/securities"),
        () => client.request("POST", "/api/v1/splits/preview", {}, { readOnly: true })
      ]) {
        await assert.rejects(read(), (raised: unknown) => {
          notASyntaxError(raised);
          assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
          assert.match((raised as Error).message, /answered 200 with a body that is not JSON/);
          assert.equal(quotedExcerpt((raised as Error).message), "<html><body>Welcome</body></html>");
          return true;
        });
      }
    });

    it("answers an empty body as null", async () => {
      for (const method of ["GET", "POST", "DELETE"]) {
        const body = method === "GET" ? undefined : {};

        assert.equal(await answering(204, null).request(method, "/api/v1/transactions/9", body), null);
        assert.equal(await answering(200, " \r\n\t ").request(method, "/api/v1/transactions/9", body), null);
      }
    });

    // JSON's whitespace is space, tab, line feed and carriage return only; a
    // body of no-break or ideographic spaces is a body that is not JSON.
    it("answers a body of other blank characters as a body that is not JSON", async () => {
      const spaces = "\u00A0\u3000";

      await assert.rejects(answering(200, spaces).request("POST", "/api/v1/transactions", {}), (raised: unknown) => {
        assert.ok(raised instanceof ApiOutcomeUnknownError, String(raised));
        assert.match(raised.message, /was answered 200 with a body that is not JSON/);
        return true;
      });

      await assert.rejects(answering(200, spaces).request("GET", "/api/v1/transactions"), (raised: unknown) => {
        assert.ok(!(raised instanceof ApiOutcomeUnknownError), String(raised));
        assert.match((raised as Error).message, /answered 200 with a body that is not JSON/);
        return true;
      });
    });

    it("quotes at most 120 characters, whitespace collapsed, invisible characters spelled out", async () => {
      // Short: whole, collapsed, escaped, no length.
      await assert.rejects(
        answering(500, "  <p>\n\tdown\u200Bfor\u202Emaintenance</p>  \n").request("GET", "/api/v1/securities"),
        (raised: unknown) => {
          notASyntaxError(raised);
          const message = (raised as Error).message;
          assert.equal(quotedExcerpt(message), "<p> down[U+200B]for[U+202E]maintenance</p>");
          assert.doesNotMatch(message, /[\u200B\u202E]/);
          assert.doesNotMatch(message, /bytes/);
          return true;
        }
      );

      // Long: cut to 120 characters, never inside an escape, with the
      // body's length in bytes (a euro sign is three).
      const long = `${"€".repeat(5)}${"a".repeat(110)}\u200B${"b".repeat(400)}`;

      await assert.rejects(answering(500, long).request("GET", "/api/v1/securities"), (raised: unknown) => {
        notASyntaxError(raised);
        const message = (raised as Error).message;
        const excerpt = quotedExcerpt(message);

        assert.ok(Array.from(excerpt).length <= 120, `${Array.from(excerpt).length}: ${excerpt}`);
        // The escape would end past the limit, so the excerpt stops before it.
        assert.equal(excerpt, `${"€".repeat(5)}${"a".repeat(110)}…`);
        assert.doesNotMatch(message, /\u200B/);
        assert.match(message, new RegExp(`\\(cut from ${Buffer.byteLength(long, "utf8")} bytes\\)`));
        return true;
      });

      // A cut after `[`, `[U`, `[U+` or `[U+2` drops that much of the escape.
      for (const kept of [118, 117, 116, 115]) {
        const body = `${"a".repeat(kept)}\u200B${"b".repeat(400)}`;

        await assert.rejects(answering(500, body).request("GET", "/api/v1/securities"), (raised: unknown) => {
          assert.equal(quotedExcerpt((raised as Error).message), `${"a".repeat(kept)}\u2026`, String(kept));
          return true;
        });
      }

      // An escape that fits is kept whole.
      const fits = `${"a".repeat(100)}\u200B${"b".repeat(400)}`;

      await assert.rejects(answering(500, fits).request("GET", "/api/v1/securities"), (raised: unknown) => {
        const excerpt = quotedExcerpt((raised as Error).message);
        assert.ok(excerpt.startsWith(`${"a".repeat(100)}[U+200B]b`), excerpt);
        assert.ok(Array.from(excerpt).length <= 120, excerpt);
        return true;
      });
    });

    it("spells DEL and the C1 controls out in the excerpt", async () => {
      const body = "<p>a\u009B31mred\u007Fb\u0085c</p>";

      await assert.rejects(answering(500, body).request("GET", "/api/v1/securities"), (raised: unknown) => {
        const message = (raised as Error).message;

        assert.equal(quotedExcerpt(message), "<p>a[U+009B]31mred[U+007F]b[U+0085]c</p>");
        assert.doesNotMatch(message, /[\u007F-\u009F]/);
        return true;
      });
    });

    it("reads only the start of a large body for the excerpt, and counts all of it", async () => {
      // The words after the first few thousand characters are never read;
      // the length is the whole body's.
      const body = `${" ".repeat(10_000)}words past the scan`;

      await assert.rejects(answering(500, body).request("GET", "/api/v1/securities"), (raised: unknown) => {
        const message = (raised as Error).message;

        assert.equal(quotedExcerpt(message), "\u2026");
        assert.match(message, /\(cut from 10019 bytes\)/);
        assert.doesNotMatch(message, /words past the scan/);
        return true;
      });

      const large = `<html>${"x".repeat(2_000_000)}</html>`;

      await assert.rejects(answering(500, large).request("GET", "/api/v1/securities"), (raised: unknown) => {
        const message = (raised as Error).message;

        assert.equal(quotedExcerpt(message), `<html>${"x".repeat(113)}\u2026`);
        assert.match(message, /\(cut from 2000013 bytes\)/);
        return true;
      });
    });
  });
});
