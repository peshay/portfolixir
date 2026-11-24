import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { apiLinkWarning } from "../src/api-link.js";

// Every host and credential here is synthetic; nothing is contacted.
describe("the link the companion's API token travels on", () => {
  // User story (security review 2026-11, N-93):
  // As the operator who points the companion at an API on another host,
  // I want one line at start when the API token will cross that link over
  // plain http,
  // so that I choose https, or keep the companion beside the API, knowing
  // what the link carries.
  //
  // Acceptance criteria:
  // - A plain-http base whose host is beyond this machine (a name with a
  //   dot, an IPv4 or IPv6 address that is not loopback) is named in one
  //   line that carries the variable, the host and the remedy.
  // - It is a warning, never a refusal: the function returns text or
  //   nothing and never throws, also for a base that does not parse.
  // - The line carries no credential: the function is never handed the
  //   token, and a user or password written into the base URL is left out.
  it("names a plain-http base beyond this machine in one line", () => {
    const beyond: Array<[string, string]> = [
      ["http://192.0.2.10:4000", "192.0.2.10"],
      ["http://10.0.0.5:4000/", "10.0.0.5"],
      ["http://portfolio.example.test", "portfolio.example.test"],
      ["HTTP://Portfolio.Example.Test:4000", "portfolio.example.test"],
      ["http://nas.home.invalid:4000", "nas.home.invalid"],
      ["http://[2001:db8::1]:4000", "[2001:db8::1]"],
      ["http://synthetic-user:synthetic-pass@portfolio.example.test:4000", "portfolio.example.test"]
    ];

    for (const [base, host] of beyond) {
      const warning = apiLinkWarning(base);

      assert.equal(typeof warning, "string", base);
      assert.ok(!warning!.includes("\n"), `${base}: one line`);
      assert.ok(warning!.includes("PORTFOLIXIR_API_BASE_URL"), base);
      assert.ok(warning!.includes("PORTFOLIXIR_API_TOKEN"), base);
      assert.ok(warning!.includes(`plain http to ${host}`), `${base}: ${warning}`);
      assert.match(warning!, /https/, base);
      assert.doesNotMatch(warning!, /synthetic|:4000|@/, base);
    }
  });

  // Acceptance criteria:
  // - An https base, wherever it points, is not named.
  // - A plain-http base on this machine is not named: 127.0.0.0/8,
  //   localhost and a name under .localhost, and [::1].
  // - A plain-http base whose host is a name without a dot is not named: it
  //   is how a container network names a neighbour (Compose's `app`), and
  //   the shipped stack must start without a warning.
  it("says nothing for https, for this machine and for a container network's name", () => {
    for (const base of [
      "https://portfolio.example.test",
      "https://192.0.2.10:4000",
      "http://127.0.0.1:4000",
      "http://127.8.9.10:4000",
      "http://localhost:4000",
      "http://LOCALHOST:4000",
      "http://localhost.:4000",
      "http://api.localhost:4000",
      "http://[::1]:4000",
      "http://app:4000",
      "http://portfolixir:4000"
    ]) {
      assert.equal(apiLinkWarning(base), undefined, base);
    }
  });

  it("leaves a base that does not parse to the checks that refuse it", () => {
    for (const base of ["", "not a url", "4000", "http://"]) {
      assert.equal(apiLinkWarning(base), undefined, JSON.stringify(base));
    }
  });
});
