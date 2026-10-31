import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { listTools } from "../src/tools.js";

// User story (#1212, Sprint 21 α11):
// As the operating LLM agent,
// I want the holdings, category-result and trades tools to say whether a
// buy's and a sell's fees and taxes are in the figures they serve,
// so that I do not set an open position's cost against a closed trade's
// basis as if they counted the same.
//
// Acceptance criteria:
// - holdings.list: cost_basis and base_cost leave out the buys' fees and
//   taxes, and the payload's computation_basis states it.
// - portfolios.category_results: invested leaves them out, so the result
//   is before them.
// - trades.list: a closed trade's basis includes the buy's, its proceeds are
//   net of the sell's; an open lot's prices, base_cost and P&L leave them
//   out, and its buy_fees/buy_taxes are the whole buy's, for
//   original_quantity, the share already sold being in the closed trade's.
describe("fees and taxes in the figures (#1212)", () => {
  const description = (name: string) =>
    listTools().find((tool) => tool.name === name)?.description ?? "";

  it("holdings.list says its costs leave out the buys' fees and taxes", () => {
    const text = description("portfolixir.holdings.list");
    assert.match(text, /cost_basis and base_cost leave out the buys' fees and taxes/);
    assert.match(text, /computation_basis/);
  });

  it("category_results says invested leaves them out", () => {
    const text = description("portfolixir.portfolios.category_results");
    assert.match(text, /invested \(the members' base_cost, without the buys' fees and taxes\)/);
  });

  it("trades.list says which of its figures carry them", () => {
    const text = description("portfolixir.trades.list");
    assert.match(text, /basis includes the buys' fees and taxes, proceeds are net of the sell's/);
    assert.match(
      text,
      /an open lot's prices, base_cost and P&L leave them out; its buy_fees\/buy_taxes are the whole buy's, for original_quantity, the share already sold being in the closed trade's/
    );
  });
});
