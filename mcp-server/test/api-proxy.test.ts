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
  // I want the companion to keep its API calls, which carry the API token,
  // off that proxy, or to refuse to start naming NO_PROXY where it cannot,
  // so that no proxy ever reads my token or my records.
  //
  // Acceptance criteria:
  // - Without NODE_USE_ENV_PROXY, NODE_OPTIONS=--use-env-proxy or the
  //   --use-env-proxy flag, or without a proxy for the API's scheme, the
  //   client goes direct and nothing is changed.
  // - With the environment proxy in effect and a proxy for the scheme (an
  //   https base falls back to HTTP_PROXY), the API host is added to NO_PROXY
  //   and no_proxy, keeping what they named and every proxy variable.
  // - A NO_PROXY that already names the host exactly, or *, changes nothing.
  // - On a Node that cannot reconfigure its proxy at run time, the companion
  //   refuses to start, naming NO_PROXY and the host, never the proxy's
  //   address.
  it("keeps the API host off the environment proxy, or refuses naming NO_PROXY", () => {
    assert.deepEqual(apiProxyDecision(base, { HTTP_PROXY: proxy }, [], true), { kind: "direct" });
    assert.deepEqual(apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1" }, [], true), {
      kind: "direct"
    });
    assert.deepEqual(
      apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1", HTTPS_PROXY: proxy }, [], true),
      { kind: "direct" },
      "an https proxy leaves a plain-http base direct"
    );

    const optIns: Array<[NodeJS.ProcessEnv, string[]]> = [
      [{ NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy }, []],
      [{ NODE_OPTIONS: "--max-old-space-size=256 --use-env-proxy", http_proxy: proxy }, []],
      [{ HTTP_PROXY: proxy }, ["--use-env-proxy"]]
    ];

    for (const [env, execArgv] of optIns) {
      const decision = apiProxyDecision(base, { ...env, NO_PROXY: "localhost" }, execArgv, true);
      assert.equal(decision.kind, "exclude", JSON.stringify(env));

      if (decision.kind === "exclude") {
        assert.equal(decision.proxyEnv.NO_PROXY, "localhost,127.0.0.1");
        assert.equal(decision.proxyEnv.no_proxy, "localhost,127.0.0.1");
        assert.equal(decision.proxyEnv.HTTP_PROXY ?? decision.proxyEnv.http_proxy, proxy);
      }
    }

    const https = apiProxyDecision(
      "https://portfolio.example.test",
      { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy },
      [],
      true
    );
    assert.equal(https.kind, "exclude");

    if (https.kind === "exclude") {
      assert.equal(https.proxyEnv.NO_PROXY, "portfolio.example.test");
    }

    for (const noProxy of ["127.0.0.1", "localhost, 127.0.0.1", "*"]) {
      assert.deepEqual(
        apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy, no_proxy: noProxy }, [], true),
        { kind: "direct" },
        noProxy
      );
    }

    const refused = apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy }, [], false);
    assert.equal(refused.kind, "refuse");

    if (refused.kind === "refuse") {
      assert.match(refused.message, /NO_PROXY/);
      assert.match(refused.message, /127\.0\.0\.1/);
      assert.doesNotMatch(refused.message, /synthetic|proxy\.example\.test/);
    }
  });
});
