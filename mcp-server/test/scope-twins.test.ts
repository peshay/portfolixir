import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { publishedTools } from "./support/companion.js";

// Sprint 17, Lane A2 (#993; plan D-6): three reads exist at two scopes. They
// are steered, not merged: each names its twin, with the scope difference.
const PAIRS = [
  ["portfolixir.portfolios.valuation", "portfolixir.views.valuation"],
  ["portfolixir.portfolios.performance", "portfolixir.views.performance"],
  ["portfolixir.portfolios.benchmark", "portfolixir.views.benchmark"]
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
  // - Both sides say the view tool needs an existing view id, and how a view
  //   that matches every account is made; the portfolio side says when its
  //   totals add up and that returns do not.
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
        assert.match(text, /needs an existing view id/, name);
        assert.match(text, /include_all/, name);
      }
    }

    // PR β closing act, note 6: "without a view" read against the tool's own
    // view parameter; the sentence is about a view existing at all.
    for (const [portfolioTool] of PAIRS) {
      assert.match(description(portfolioTool), /Until a view exists this tool is the only read/);
      assert.doesNotMatch(description(portfolioTool), /Without a view/);
    }

    assert.match(
      description("portfolixir.portfolios.valuation"),
      /add up only when they share one base currency/
    );

    for (const name of ["portfolixir.portfolios.performance", "portfolixir.portfolios.benchmark"]) {
      assert.match(description(name), /returns of several portfolios do not add up/, name);
    }
  });
});
