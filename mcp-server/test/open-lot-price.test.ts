import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { listTools } from "../src/tools.js";

// User story (#1369, Sprint 23 R4; ADR-0010's amendment of 2026-06-10):
// As the operating LLM agent reading a security's open lots,
// I want trades.list to say which price an open lot is valued at and that
// the lot names where it comes from,
// so that I read a lot of a security without a quote at the holdings'
// figure, its source named, instead of taking its price for a quote.
//
// Acceptance criteria:
// - trades.list says an open lot's latest_price follows holdings.list's
//   rule (a quote, else the last own trade price) and names price_source
//   and price_date.
describe("an open lot's price and its source (#1369)", () => {
  const description = (name: string) =>
    listTools().find((tool) => tool.name === name)?.description ?? "";

  it("trades.list names the open lots' price rule and source", () => {
    const text = description("portfolixir.trades.list");
    assert.match(text, /latest_price \(quote, else last own trade price\), price_source, price_date/);
  });
});
