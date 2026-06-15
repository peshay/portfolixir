import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { createApiClient } from "../src/api-client.js";
import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

describe("Portfolixir MCP tools", () => {
  it("lists API-wrapper tools with string decimal schemas", () => {
    const tools = listTools();
    const names = tools.map((tool) => tool.name);

    assert.deepEqual(names, [
      "portfolixir.securities.list",
      "portfolixir.securities.create",
      "portfolixir.securities.update",
      "portfolixir.securities.delete",
      "portfolixir.securities.search_online",
      "portfolixir.quotes.sync",
      "portfolixir.quotes.list",
      "portfolixir.quotes.upsert",
      "portfolixir.portfolios.list",
      "portfolixir.portfolios.create",
      "portfolixir.cash_accounts.list",
      "portfolixir.cash_accounts.create",
      "portfolixir.cash_accounts.update",
      "portfolixir.cash_accounts.delete",
      "portfolixir.securities_accounts.list",
      "portfolixir.securities_accounts.create",
      "portfolixir.securities_accounts.update",
      "portfolixir.securities_accounts.delete",
      "portfolixir.transactions.list",
      "portfolixir.transactions.create",
      "portfolixir.transactions.update",
      "portfolixir.transactions.delete",
      "portfolixir.holdings.list",
      "portfolixir.holdings.by_security",
      "portfolixir.portfolios.valuation",
      "portfolixir.exchange_rates.list",
      "portfolixir.exchange_rates.sync",
      "portfolixir.classifications.list",
      "portfolixir.classifications.create",
      "portfolixir.classifications.categories.create",
      "portfolixir.classifications.update",
      "portfolixir.classifications.delete",
      "portfolixir.classifications.categories.update",
      "portfolixir.classifications.categories.delete",
      "portfolixir.classifications.assign",
      "portfolixir.classifications.assign_bulk",
      "portfolixir.classifications.unassign",
      "portfolixir.trades.list",
      "portfolixir.targets.list",
      "portfolixir.targets.set",
      "portfolixir.targets.delete",
      "portfolixir.portfolios.allocation",
      "portfolixir.portfolios.risk",
      "portfolixir.portfolios.set_cash_target",
      "portfolixir.cash_accounts.set_balance",
      "portfolixir.portfolios.income",
      "portfolixir.portfolios.performance",
      "portfolixir.journal.list"
    ]);

    const transactionCreate = tools.find((tool) => tool.name === "portfolixir.transactions.create");
    assert.equal(
      transactionCreate?.inputSchema.properties.transaction.properties.quantity.type,
      "string"
    );
    assert.equal(transactionCreate?.inputSchema.properties.transaction.properties.price.type, "string");
    // Cross-currency settlement fields are exposed as Decimal strings (#388, ADR-0015).
    assert.equal(
      transactionCreate?.inputSchema.properties.transaction.properties.security_amount.type,
      "string"
    );
    assert.equal(
      transactionCreate?.inputSchema.properties.transaction.properties.settlement_amount.type,
      "string"
    );
    assert.equal(
      transactionCreate?.inputSchema.properties.transaction.properties.settlement_fx_rate.type,
      "string"
    );

    const securitiesList = tools.find((tool) => tool.name === "portfolixir.securities.list");
    assert.deepEqual(securitiesList?.inputSchema.properties.holding_status.enum, [
      "held",
      "not_held",
      "all"
    ]);

    const cashAccountCreate = tools.find((tool) => tool.name === "portfolixir.cash_accounts.create");
    assert.deepEqual(
      cashAccountCreate?.inputSchema.properties.cash_account.properties.liquidity_role.enum,
      ["free_cash", "credit_line", "reserve"]
    );

    const cashAccountUpdate = tools.find((tool) => tool.name === "portfolixir.cash_accounts.update");
    assert.deepEqual(
      cashAccountUpdate?.inputSchema.properties.cash_account.properties.liquidity_role.enum,
      ["free_cash", "credit_line", "reserve"]
    );

    const securitiesCreate = tools.find((tool) => tool.name === "portfolixir.securities.create");
    assert.equal(
      securitiesCreate?.inputSchema.properties.security.properties.asset_class.type,
      "string"
    );
    assert.equal(
      securitiesCreate?.inputSchema.properties.security.properties
        .excluded_from_allocation_targets.type,
      "boolean"
    );

    const securitiesUpdate = tools.find((tool) => tool.name === "portfolixir.securities.update");
    assert.equal(
      securitiesUpdate?.inputSchema.properties.security.properties
        .excluded_from_allocation_targets.type,
      "boolean"
    );
    assert.doesNotThrow(() =>
      securitiesCreate?.zodSchema.parse({
        security: {
          name: "Synthetic Government Bond",
          currency_code: "EUR",
          asset_class: "government_bond",
          excluded_from_allocation_targets: true
        }
      })
    );

    const performance = tools.find((tool) => tool.name === "portfolixir.portfolios.performance");
    assert.match(performance?.description ?? "", /irr/i);
  });

  it("calls the Phoenix API with bearer auth and returns structured content", async () => {
    const { client, requests } = createRecordingClient({
      data: [{ id: 7, name: "Synthetic" }]
    });

    const result = await callTool(client, "portfolixir.securities.list", {
      query: "syn",
      sort: "name",
      direction: "asc",
      holding_status: "held"
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(
      requests[0].path,
      "/api/v1/securities?query=syn&sort=name&direction=asc&holding_status=held"
    );
    assert.equal(requests[0].token, "Bearer api-token");
    assert.deepEqual(result.structuredContent, { data: [{ id: 7, name: "Synthetic" }] });
    assert.match(result.content[0].text, /Synthetic/);
  });

  it("issues a GET to /trades for portfolixir.trades.list", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        open_lots: [],
        closed_trades: [
          {
            open_date: "2026-01-10",
            close_date: "2026-04-10",
            quantity: "10",
            realized_pnl_abs: "500"
          }
        ],
        orphan_sells: []
      }
    });

    const result = await callTool(client, "portfolixir.trades.list", { security_id: 42 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/securities/42/trades");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /500/);
  });

  it("issues a GET to /valuation for portfolixir.portfolios.valuation", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        portfolio_id: 3,
        total_value: "2000",
        unvalued_count: 0,
        positions: [{ security_id: 9, market_value: "1000", weight: "0.5", valued: true }]
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.valuation", { portfolio_id: 3 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/valuation");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /0\.5/);
  });

  it("issues a GET to /holdings/by_security for portfolixir.holdings.by_security", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        currency: "EUR",
        as_of: "2026-06-14",
        note: "converted to the EUR hub",
        holdings: [{ security_id: 9, quantity: "10", market_value: "1000", valued: true }]
      }
    });

    const result = await callTool(client, "portfolixir.holdings.by_security", {});

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/holdings/by_security");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /1000/);
  });

  it("issues a GET to /income for portfolixir.portfolios.income", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        portfolio_id: 3,
        base_currency: "EUR",
        annual: [{ year: 2025, dividends_total: "200", interest_total: "15", total: "215" }],
        positions: [{ security_id: 9, gross: "200", tax: "30", net: "170" }],
        transactions: []
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.income", { portfolio_id: 3 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/income");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /170/);
  });

  it("issues a POST to /exchange_rates/sync for portfolixir.exchange_rates.sync", async () => {
    const { client, requests } = createRecordingClient({
      data: { provider: "ecb", status: "ok", upserted: 25 }
    });

    const result = await callTool(client, "portfolixir.exchange_rates.sync", {});

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/exchange_rates/sync");
    assert.deepEqual(requests[0].body, {});
    assert.match(result.content[0].text, /ecb/);
  });

  it("routes classification assignment to PUT /assignments with the body", async () => {
    const { client, requests } = createRecordingClient({
      data: { security_id: 7, classification_id: 3, category_id: 9 }
    });

    const result = await callTool(client, "portfolixir.classifications.assign", {
      classification_id: 3,
      security_id: 7,
      category_id: 9
    });

    assert.equal(requests[0].method, "PUT");
    assert.equal(requests[0].path, "/api/v1/classifications/3/assignments");
    assert.deepEqual(requests[0].body, { security_id: 7, category_id: 9 });
    assert.match(result.content[0].text, /category_id/);
  });

  it("passes richer quote sync status responses through unchanged", async () => {
    const { client, requests } = createRecordingClient({
      data: { status: "skipped", reason: "missing_ticker" }
    });

    const result = await callTool(client, "portfolixir.quotes.sync", { security_id: 42 });

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/securities/42/sync_quotes");
    assert.deepEqual(requests[0].body, {});
    assert.deepEqual(result.structuredContent, {
      data: { status: "skipped", reason: "missing_ticker" }
    });
    assert.match(result.content[0].text, /missing_ticker/);
  });

  it("pages securities.list via limit/offset query params", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.securities.list", { query: "etf", limit: 50, offset: 100 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/securities?query=etf&limit=50&offset=100");
  });

  it("routes category update to PATCH /categories/:id with the body", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 5 } });

    await callTool(client, "portfolixir.classifications.categories.update", {
      classification_id: 3,
      id: 5,
      category: { description: "Core equity", color: "#2563eb" }
    });

    assert.equal(requests[0].method, "PATCH");
    assert.equal(requests[0].path, "/api/v1/classifications/3/categories/5");
    assert.deepEqual(requests[0].body, { category: { description: "Core equity", color: "#2563eb" } });
  });

  it("routes classification delete to DELETE /classifications/:id", async () => {
    const { client, requests } = createRecordingClient({ data: { deleted: true } });

    await callTool(client, "portfolixir.classifications.delete", { id: 4 });

    assert.equal(requests[0].method, "DELETE");
    assert.equal(requests[0].path, "/api/v1/classifications/4");
  });

  it("routes bulk assign to PUT /assignments/bulk with the body", async () => {
    const { client, requests } = createRecordingClient({ data: { assigned: 3 } });

    await callTool(client, "portfolixir.classifications.assign_bulk", {
      classification_id: 3,
      category_id: 9,
      security_ids: [1, 2, 7]
    });

    assert.equal(requests[0].method, "PUT");
    assert.equal(requests[0].path, "/api/v1/classifications/3/assignments/bulk");
    assert.deepEqual(requests[0].body, { category_id: 9, security_ids: [1, 2, 7] });
  });

  it("routes update/delete tools to PATCH/DELETE on the right paths", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });

    await callTool(client, "portfolixir.transactions.update", {
      id: 7,
      transaction: { notes: "corrected" }
    });
    await callTool(client, "portfolixir.transactions.delete", { id: 7 });
    await callTool(client, "portfolixir.cash_accounts.update", {
      id: 3,
      cash_account: { name: "Renamed", liquidity_role: "reserve" }
    });
    await callTool(client, "portfolixir.securities_accounts.delete", { id: 4 });
    await callTool(client, "portfolixir.securities.update", { id: 9, security: { note: "x" } });

    assert.deepEqual(requests[0], {
      method: "PATCH",
      path: "/api/v1/transactions/7",
      body: { transaction: { notes: "corrected" } },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[1], {
      method: "DELETE",
      path: "/api/v1/transactions/7",
      body: undefined,
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[2], {
      method: "PATCH",
      path: "/api/v1/cash_accounts/3",
      body: { cash_account: { name: "Renamed", liquidity_role: "reserve" } },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[3], {
      method: "DELETE",
      path: "/api/v1/securities_accounts/4",
      body: undefined,
      token: "Bearer api-token"
    });
    assert.equal(requests[4].method, "PATCH");
    assert.equal(requests[4].path, "/api/v1/securities/9");
  });

  it("passes list filters through as query params", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.transactions.list", {
      from: "2026-01-01",
      to: "2026-03-31",
      portfolio_id: 3,
      securities_account_id: 7
    });
    await callTool(client, "portfolixir.holdings.list", { portfolio_id: 3, security_id: 9 });
    await callTool(client, "portfolixir.trades.list", { security_id: 9, from: "2026-01-01" });

    assert.equal(
      requests[0].path,
      "/api/v1/transactions?from=2026-01-01&to=2026-03-31&portfolio_id=3&securities_account_id=7"
    );
    assert.equal(requests[1].path, "/api/v1/portfolios/3/holdings?security_id=9");
    assert.equal(requests[2].path, "/api/v1/securities/9/trades?from=2026-01-01");
  });

  it("routes target weight tools to the portfolio targets endpoints", async () => {
    const { client, requests } = createRecordingClient({ data: { targets: [] } });

    await callTool(client, "portfolixir.targets.list", { portfolio_id: 3, classification_id: 5 });
    await callTool(client, "portfolixir.targets.set", {
      portfolio_id: 3,
      classification_id: 5,
      targets: [{ category_id: 9, target_weight: "0.25" }]
    });
    await callTool(client, "portfolixir.targets.delete", { portfolio_id: 3, category_id: 9 });

    assert.deepEqual(requests[0], {
      method: "GET",
      path: "/api/v1/portfolios/3/targets?classification_id=5",
      body: undefined,
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[1], {
      method: "PUT",
      path: "/api/v1/portfolios/3/targets",
      body: { classification_id: 5, targets: [{ category_id: 9, target_weight: "0.25" }] },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[2], {
      method: "DELETE",
      path: "/api/v1/portfolios/3/targets/9",
      body: undefined,
      token: "Bearer api-token"
    });
  });

  it("routes set_cash_target to PATCH /portfolios/:id with the cash target weight", async () => {
    const { client, requests } = createRecordingClient({
      data: { id: 3, cash_target_weight: "0.05" }
    });

    await callTool(client, "portfolixir.portfolios.set_cash_target", {
      portfolio_id: 3,
      cash_target_weight: "0.05"
    });
    await callTool(client, "portfolixir.portfolios.set_cash_target", { portfolio_id: 3 });

    assert.deepEqual(requests[0], {
      method: "PATCH",
      path: "/api/v1/portfolios/3",
      body: { portfolio: { cash_target_weight: "0.05" } },
      token: "Bearer api-token"
    });
    // Omitting the weight clears the cash target.
    assert.deepEqual(requests[1].body, { portfolio: { cash_target_weight: null } });
  });

  it("issues a GET to /allocation for portfolixir.portfolios.allocation", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        portfolio_id: 3,
        classification_id: 5,
        categories: [
          { category_id: 9, actual_weight: "0.4", target_weight: "0.25", drift_weight: "-0.15" }
        ]
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.allocation", {
      portfolio_id: 3,
      classification_id: 5
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/allocation?classification_id=5");
    assert.match(result.content[0].text, /-0\.15/);
  });

  it("issues a GET to /risk for portfolixir.portfolios.risk", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        portfolio_id: 3,
        steerable_basis: "1000",
        top_holdings: [{ security_id: 9, weight: "60", severity: "hard" }],
        hhi: { value: "4382", band: "concentrated" },
        asset_class_violations: []
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.risk", { portfolio_id: 3 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/risk");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /concentrated/);
    assert.match(result.content[0].text, /hard/);
  });

  it("encodes risk overrides (top_n, caps, bands) as bracketed query params", async () => {
    const { client, requests } = createRecordingClient({ data: { top_holdings: [] } });

    await callTool(client, "portfolixir.portfolios.risk", {
      portfolio_id: 3,
      top_n: 5,
      asset_class_caps: { equity: "50", etf: "30" },
      hhi_bands: { low: "1500", high: "5000" },
      etf_thresholds: { warn: "25" }
    });

    assert.equal(
      requests[0].path,
      "/api/v1/portfolios/3/risk?top_n=5&asset_class_caps%5Bequity%5D=50" +
        "&asset_class_caps%5Betf%5D=30&hhi_bands%5Blow%5D=1500&hhi_bands%5Bhigh%5D=5000" +
        "&etf_thresholds%5Bwarn%5D=25"
    );
  });

  it("routes cash_accounts.set_balance to POST /cash_accounts/:id/balance", async () => {
    const { client, requests } = createRecordingClient({
      data: { id: 12, type: "balance_adjustment" },
      status: 201
    });

    await callTool(client, "portfolixir.cash_accounts.set_balance", {
      id: 3,
      date: "2026-06-01",
      amount: "4250.00"
    });

    assert.deepEqual(requests[0], {
      method: "POST",
      path: "/api/v1/cash_accounts/3/balance",
      body: { date: "2026-06-01", amount: "4250.00" },
      token: "Bearer api-token"
    });
  });

  it("issues a GET to /performance for portfolixir.portfolios.performance", async () => {
    const { client, requests } = createRecordingClient({
      data: { portfolio_id: 3, period: "ytd", ttwror: "0.0825", irr: "0.0791" }
    });

    const result = await callTool(client, "portfolixir.portfolios.performance", {
      portfolio_id: 3,
      period: "ytd",
      series: true
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/performance?period=ytd&series=true");
    assert.match(result.content[0].text, /0\.0825/);
    // The money-weighted IRR is surfaced alongside TTWROR, unchanged.
    assert.match(result.content[0].text, /0\.0791/);
    assert.equal((result.structuredContent as any).data.irr, "0.0791");
  });

  it("issues a GET to /journal with filters for portfolixir.journal.list", async () => {
    const { client, requests } = createRecordingClient({
      data: [
        { id: 1, resource_type: "security", operation: "create", actor_type: "owner_ui" }
      ],
      meta: { as_of: "2026-06-14T00:00:00Z", order: "inserted_at:desc,id:desc", count: 1 }
    });

    const result = await callTool(client, "portfolixir.journal.list", {
      resource_type: "security",
      operation: "create",
      limit: 50
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(
      requests[0].path,
      "/api/v1/journal?resource_type=security&operation=create&limit=50"
    );
    assert.equal((result.structuredContent as any).data[0].resource_type, "security");
  });

  it("maps invalid tool names and upstream API errors to clear failures", async () => {
    const client = createApiClient({
      baseUrl: "http://portfolixir.test",
      token: "api-token",
      fetch: async () =>
        new Response(JSON.stringify({ errors: { name: ["can't be blank"] } }), {
          status: 422,
          headers: { "content-type": "application/json" }
        })
    });

    await assert.rejects(
      callTool(client, "portfolixir.unknown", {}),
      /Unknown Portfolixir MCP tool/
    );

    await assert.rejects(
      callTool(client, "portfolixir.securities.create", { security: { name: "" } }),
      /Portfolixir API request failed/
    );
  });
});
