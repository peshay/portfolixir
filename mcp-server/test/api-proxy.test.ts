import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { apiProxyDecision, runtimeEnvProxy } from "../src/api-proxy.js";

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

  // User story (security review 2026-11, N-09):
  // As the operator whose environment switches on Node's proxy,
  // I want the companion to decide from what Node did with the switch, not
  // from how it was written,
  // so that no spelling of it starts the companion behind the proxy.
  //
  // Acceptance criteria:
  // - When the runtime says its environment proxy is on, the companion
  //   refuses whatever the environment and Node's own options read: with the
  //   switch written a way the companion does not read itself, or not written
  //   in either at all (a configuration file).
  // - The rest of the decision stands: no proxy for the scheme, or a NO_PROXY
  //   naming the host, is direct.
  // - The runtime's word is read off Node's global agent: Node builds it with
  //   `proxyEnv` exactly when the switch is on.
  // - The companion's own reading of the three common spellings stays as a
  //   second vote: it can add a refusal, never take one away.
  it("refuses when the runtime says its proxy is on, however the switch was written", () => {
    const spellings: Array<[NodeJS.ProcessEnv, string[]]> = [
      [{}, []],
      [{ NODE_OPTIONS: "--use_env_proxy" }, []],
      [{}, ["--use_env_proxy"]],
      [{ NODE_OPTIONS: '"--use-env-proxy"' }, []],
      [{ NODE_OPTIONS: '--use-env"-"proxy' }, []],
      [{ NODE_OPTIONS: "--use-env-proxy=true" }, []],
      [{}, ["--use-env-proxy=true"]],
      [{}, ["--use-env-proxy=false"]],
      [{}, ["--experimental-config-file=node.config.json"]]
    ];

    for (const [env, execArgv] of spellings) {
      const decision = apiProxyDecision(base, { ...env, HTTP_PROXY: proxy, NO_PROXY: "localhost" }, execArgv, true);
      const told = JSON.stringify([env, execArgv]);

      assert.equal(decision.kind, "refuse", told);

      if (decision.kind === "refuse") {
        assert.match(decision.message, /NO_PROXY/, told);
        assert.match(decision.message, /127\.0\.0\.1/, told);
        assert.doesNotMatch(decision.message, /synthetic|proxy\.example\.test/, told);
      }
    }

    assert.deepEqual(apiProxyDecision(base, {}, [], true), { kind: "direct" }, "no proxy variable");
    assert.deepEqual(
      apiProxyDecision(base, { HTTPS_PROXY: proxy }, [], true),
      { kind: "direct" },
      "an https proxy leaves a plain-http base direct"
    );
    assert.deepEqual(
      apiProxyDecision(base, { HTTP_PROXY: proxy, NO_PROXY: "127.0.0.1" }, [], true),
      { kind: "direct" },
      "NO_PROXY names the host"
    );

    assert.equal(
      apiProxyDecision(base, { NODE_USE_ENV_PROXY: "1", HTTP_PROXY: proxy }, [], false).kind,
      "refuse",
      "the companion's own reading still refuses"
    );
    assert.deepEqual(apiProxyDecision(base, { HTTP_PROXY: proxy }, [], false), { kind: "direct" });
  });

  it("reads the runtime's word off the global agent Node built", () => {
    assert.equal(runtimeEnvProxy({ options: { proxyEnv: { HTTP_PROXY: proxy } } }), true);
    assert.equal(runtimeEnvProxy({ options: { proxyEnv: {} } }), true);
    assert.equal(runtimeEnvProxy({ options: { keepAlive: true } }), false);
    assert.equal(runtimeEnvProxy({ options: { proxyEnv: undefined } }), false);
    assert.equal(runtimeEnvProxy({}), false);
    assert.equal(typeof runtimeEnvProxy(), "boolean", "this process's own agent is readable");
  });
});
