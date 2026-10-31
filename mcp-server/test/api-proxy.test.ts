import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { apiProxyDecision } from "../src/api-proxy.js";

// Every proxy address and token here is synthetic; nothing is contacted.
const base = "http://127.0.0.1:4000";
const proxy = "http://synthetic-user:synthetic-pass@proxy.example.test:3128";

describe("the companion's API client and Node's environment proxy", () => {
  // User story (security review 2026-10-12, K16):
  // As the operator running the companion in an environment where Node's
  // proxy is switched on,
  // I want the companion to refuse to start, naming NO_PROXY, whenever that
  // proxy would carry its API calls,
  // so that no proxy ever reads my API token or my records.
  //
  // Acceptance criteria:
  // - Without NODE_USE_ENV_PROXY, NODE_OPTIONS=--use-env-proxy or the
  //   --use-env-proxy flag, or without a proxy for the API's scheme, the
  //   client goes direct.
  // - With the environment proxy in effect and a proxy for the scheme (an
  //   https base falls back to HTTP_PROXY), and NO_PROXY not naming the API
  //   host, the companion refuses, naming NO_PROXY and the host, never the
  //   proxy's address; NO_PROXY=localhost does not cover 127.0.0.1.
  // - A NO_PROXY (or no_proxy) that names the host, or *, lets it start.
  it("refuses to start naming NO_PROXY whenever the environment proxy would carry its API calls", () => {
    assert.deepEqual(apiProxyDecision(base, { HTTP_PROXY: proxy }, []), { kind: "direct" });
    assert.deepEqual(apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1" }, []), { kind: "direct" });
    assert.deepEqual(
      apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1", HTTPS_PROXY: proxy }, []),
      { kind: "direct" },
      "an https proxy leaves a plain-http base direct"
    );

    const optIns: Array<[NodeJS.ProcessEnv, string[]]> = [
      [{ NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy }, []],
      [{ NODE_OPTIONS: "--max-old-space-size=256 --use-env-proxy", http_proxy: proxy }, []],
      [{ HTTP_PROXY: proxy }, ["--use-env-proxy"]]
    ];

    for (const [env, execArgv] of optIns) {
      const decision = apiProxyDecision(base, { ...env, NO_PROXY: "localhost" }, execArgv);
      assert.equal(decision.kind, "refuse", JSON.stringify(env));

      if (decision.kind === "refuse") {
        assert.match(decision.message, /NO_PROXY/);
        assert.match(decision.message, /127\.0\.0\.1/);
        assert.doesNotMatch(decision.message, /synthetic|proxy\.example\.test/);
      }
    }

    assert.equal(
      apiProxyDecision(
        "https://portfolio.example.test",
        { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy },
        []
      ).kind,
      "refuse"
    );

    for (const noProxy of ["127.0.0.1", "localhost, 127.0.0.1", "127.0.0.1:4000", "*"]) {
      assert.deepEqual(
        apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy, no_proxy: noProxy }, []),
        { kind: "direct" },
        noProxy
      );
    }

    assert.deepEqual(
      apiProxyDecision(
        "http://app:4000",
        { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy, NO_PROXY: "127.0.0.1,localhost,app" },
        []
      ),
      { kind: "direct" }
    );
  });

  // User story (security review 2026-10-12, K16, review round):
  // As the operator who names hosts in NO_PROXY,
  // I want the companion to read NO_PROXY exactly as Node's fetch reads it,
  // so that it never starts while the proxy would still carry its API calls.
  //
  // Acceptance criteria:
  // - A plain entry covers that host only, never its subdomains.
  // - An entry starting with "." or "*." covers subdomains only, never the
  //   domain itself; "*" covers everything.
  // - The lower-case no_proxy wins over NO_PROXY even when it is blank.
  // - An entry with a port covers that port only; entries split on commas
  //   and on spaces.
  it("reads NO_PROXY the way Node's fetch does", () => {
    const on = { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy };
    const decide = (url: string, env: NodeJS.ProcessEnv) =>
      apiProxyDecision(url, { ...on, ...env }, []).kind;

    assert.equal(decide("http://api.home.invalid:4000", { NO_PROXY: "home.invalid" }), "refuse");
    assert.equal(decide("http://home.invalid:4000", { NO_PROXY: ".home.invalid" }), "refuse");
    assert.equal(decide("http://home.invalid:4000", { NO_PROXY: "*.home.invalid" }), "refuse");
    assert.equal(
      decide("http://x1.invalid:4000", { no_proxy: "", NO_PROXY: "x1.invalid" }),
      "refuse"
    );
    assert.equal(decide(base, { NO_PROXY: "127.0.0.1:5000" }), "refuse");

    assert.equal(decide("http://home.invalid:4000", { NO_PROXY: "home.invalid" }), "direct");
    assert.equal(decide("http://api.home.invalid:4000", { NO_PROXY: ".home.invalid" }), "direct");
    assert.equal(decide("http://api.home.invalid:4000", { NO_PROXY: "*.home.invalid" }), "direct");
    assert.equal(decide("http://x1.invalid:4000", { no_proxy: "x1.invalid", NO_PROXY: "" }), "direct");
    assert.equal(decide(base, { NO_PROXY: "localhost 127.0.0.1" }), "direct");
    assert.equal(decide(base, { NO_PROXY: "127.0.0.1:4000" }), "direct");
    assert.equal(decide(base, { NO_PROXY: "*" }), "direct");
  });
});
