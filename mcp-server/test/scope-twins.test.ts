import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { publishedTools } from "./support/companion.js";

// Sprint 17, Lane A2 (#993; plan D-6): three reads exist at two scopes. They
// are steered, not merged: each names its twin, with the scope difference.
// The contribution analysis (FR-41, ADR-0051 §6) is a fourth pair since
// Sprint 18.
// Since #1007 (Sprint 18 plan D-5) the view valuation also reads the total of
// every account when it is given no id, so its pair no longer needs a view.
// Since #1056 (Sprint 19 plan D-7) the view performance, benchmark and
// contribution do the same, every account in EUR, so no pair needs one.
const PAIRS = [
  ["portfolixir.portfolios.valuation", "portfolixir.views.valuation"],
  ["portfolixir.portfolios.performance", "portfolixir.views.performance"],
  ["portfolixir.portfolios.benchmark", "portfolixir.views.benchmark"],
  ["portfolixir.portfolios.contribution", "portfolixir.views.contribution"]
] as const;

describe("the twin scope tools", () => {
  // User story (A2, #993):
  // As the agent asked for a figure that exists at two scopes,
  // I want both tools of a pair to name each other and say how their scopes
  // differ,
  // so that I pick the scope the question asks for instead of guessing.
  //
  // Acceptance criteria:
  // - Each portfolio-scope description names its view twin, and each view
  //   description names its portfolio twin, as "Scope twin: <name>".
  // - Both sides state the difference: one portfolio record in its base
  //   currency, with a view that narrows within it, against a view across
  //   every portfolio, each account counted once, in EUR.
  // - For valuation (#1007, Sprint 18 plan D-5), both sides say the view tool
  //   without an id reads the total of every account, and the portfolio side
  //   sends a total there rather than to a sum of portfolios.
  // - For performance, the benchmark comparison and the contribution (#1056,
  //   Sprint 19 plan D-7), both sides say the view tool with no id reads
  //   every account in EUR, and the portfolio side sends the whole there;
  //   for the two returns it adds that returns of several portfolios do not
  //   add up, while a contribution, which is money, is steered away from a
  //   sum of portfolios instead.
  // - No side asks for a view to be created, or calls the portfolio tool the
  //   only read until one exists.
  // - No tool is removed or renamed.
  it("names its twin on both sides, with the scope difference", async () => {
    const published = await publishedTools();
    const description = (name: string) => {
      const tool = published.find((candidate) => candidate.name === name);
      assert.ok(tool, `${name} is still published`);
      return tool.description ?? "";
    };

    for (const [portfolioTool, viewTool] of PAIRS) {
      const portfolioSide = description(portfolioTool);
      const viewSide = description(viewTool);

      assert.ok(portfolioSide.includes(`Scope twin: ${viewTool}`), portfolioTool);
      assert.ok(viewSide.includes(`Scope twin: ${portfolioTool}`), viewTool);

      for (const [name, text] of [
        [portfolioTool, portfolioSide],
        [viewTool, viewSide]
      ]) {
        assert.match(text, /ONE portfolio record in its base currency/, name);
        assert.match(text, /narrow(s|ing) within that portfolio/, name);
        assert.match(text, /across EVERY portfolio, each account counted once, in EUR/, name);
        assert.doesNotMatch(text, /needs an existing view id/, name);
        assert.doesNotMatch(text, /include_all/, name);

        if (viewTool === "portfolixir.views.valuation") {
          assert.match(text, /with no id, the total of every account/, name);
        } else {
          assert.match(text, /with no id, every account in EUR/, name);
        }
      }
    }

    // PR β closing act, note 6: "without a view" read against the tool's own
    // view parameter. Since #1056 a view no longer has to exist for any pair,
    // so the portfolio side sends the whole to its twin.
    for (const name of ["portfolixir.portfolios.performance", "portfolixir.portfolios.benchmark"]) {
      assert.match(description(name), /For every account, read that/, name);
      assert.match(description(name), /returns of several portfolios do not add up/, name);
    }

    assert.match(
      description("portfolixir.portfolios.contribution"),
      /For every account, read that, not a sum of portfolios\./
    );
    assert.doesNotMatch(description("portfolixir.portfolios.contribution"), /returns of several/);

    for (const [portfolioTool] of PAIRS) {
      assert.doesNotMatch(description(portfolioTool), /Without a view/);
      assert.doesNotMatch(description(portfolioTool), /Until a view exists/);
    }

    // #1007: the total has a read of its own, so the portfolio side sends a
    // total there instead of explaining when a sum of portfolios is right.
    const portfolioValuation = description("portfolixir.portfolios.valuation");
    assert.match(portfolioValuation, /read that, not a sum of portfolios/);
  });
});
