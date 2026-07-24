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
      "portfolixir.securities.get",
      "portfolixir.securities.create",
      "portfolixir.securities.update",
      "portfolixir.securities.delete",
      "portfolixir.securities.isin_change",
      "portfolixir.securities.delete_isin_alias",
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
      "portfolixir.splits.preview",
      "portfolixir.splits.create",
      "portfolixir.holdings.list",
      "portfolixir.holdings.by_security",
      "portfolixir.holdings.reconcile",
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
      "portfolixir.targets.list_positions",
      "portfolixir.targets.delete_position",
      "portfolixir.portfolios.allocation",
      "portfolixir.portfolios.risk",
      "portfolixir.portfolios.cash_target",
      "portfolixir.portfolios.set_cash_target",
      "portfolixir.cash_accounts.set_balance",
      "portfolixir.portfolios.income",
      "portfolixir.portfolios.performance",
      "portfolixir.journal.list",
      "portfolixir.buckets.list",
      "portfolixir.buckets.get",
      "portfolixir.buckets.create",
      "portfolixir.buckets.update",
      "portfolixir.buckets.delete",
      "portfolixir.views.list",
      "portfolixir.views.get",
      "portfolixir.views.create",
      "portfolixir.views.update",
      "portfolixir.views.delete",
      "portfolixir.views.set_buckets",
      "portfolixir.views.valuation",
      "portfolixir.securities_accounts.set_buckets",
      "portfolixir.cash_accounts.set_buckets",
      "portfolixir.securities_accounts.set_position_buckets",
      "portfolixir.securities_accounts.clear_position_buckets",
      "portfolixir.settings.get_default_view",
      "portfolixir.settings.set_default_view",
      "portfolixir.plans.list",
      "portfolixir.plans.duplicate",
      "portfolixir.plans.activate",
      "portfolixir.plans.rename",
      "portfolixir.plans.delete",
      "portfolixir.snapshots.list",
      "portfolixir.snapshots.create",
      "portfolixir.snapshots.delete",
      "portfolixir.snapshots.comparison"
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

    // The quote `source` is a closed set in the backend (Catalog.Quote @sources);
    // expose it as an enum so an LLM does not guess a free-form value and hit an
    // opaque 422 (#508).
    const quoteUpsert = tools.find((tool) => tool.name === "portfolixir.quotes.upsert");
    assert.deepEqual(
      quoteUpsert?.inputSchema.properties.quotes.items.properties.source.enum,
      ["auto", "manual", "coingecko", "portfolio_performance"]
    );
    assert.doesNotThrow(() =>
      quoteUpsert?.zodSchema.parse({
        security_id: 1,
        quotes: [{ date: "2026-06-19", close: "100.00", source: "manual" }]
      })
    );
    assert.throws(() =>
      quoteUpsert?.zodSchema.parse({
        security_id: 1,
        quotes: [{ date: "2026-06-19", close: "100.00", source: "e2e" }]
      })
    );

    assert.doesNotThrow(() =>
      securitiesCreate?.zodSchema.parse({
        security: {
          name: "Synthetic Government Bond",
          currency_code: "EUR",
          asset_class: "government_bond"
        }
      })
    );

    const performance = tools.find((tool) => tool.name === "portfolixir.portfolios.performance");
    assert.match(performance?.description ?? "", /irr/i);

    // ADR-0020: the target read/write tools and the per-plan cash-target tools
    // expose an integer `view` scope and a string cash_target_weight.
    const targetsList = tools.find((tool) => tool.name === "portfolixir.targets.list");
    assert.equal(targetsList?.inputSchema.properties.view.type, "integer");
    const targetsSet = tools.find((tool) => tool.name === "portfolixir.targets.set");
    assert.equal(targetsSet?.inputSchema.properties.view.type, "integer");
    const targetsDelete = tools.find((tool) => tool.name === "portfolixir.targets.delete");
    assert.equal(targetsDelete?.inputSchema.properties.view.type, "integer");

    // #481 fix round: the position-target tool descriptions state the [0,1]
    // string-fraction weight, that per-category/per-level sums are NOT enforced
    // in this slice, and the stale flag so an operating LLM reacts to it.
    const listPositions = tools.find(
      (tool) => tool.name === "portfolixir.targets.list_positions"
    );
    assert.match(listPositions?.description ?? "", /string fraction in \[0, ?1\]/);
    assert.match(listPositions?.description ?? "", /not enforced/i);
    assert.match(listPositions?.description ?? "", /stale/);
    assert.match(targetsSet?.description ?? "", /not enforced/i);

    // UAT polish round: each position row names its security.
    assert.match(listPositions?.description ?? "", /security_name/);

    // #481 slice 2a: the allocation reports the EFFECTIVE targets (ADR-0030)
    // including per-position SOLL/drift and the not-yet-held rows, so the
    // slice-1 "explicit category rows" breadcrumb must be gone; the pointer
    // to targets.list_positions stays for the maintenance view.
    const allocation = tools.find((tool) => tool.name === "portfolixir.portfolios.allocation");
    assert.match(allocation?.description ?? "", /targets\.list_positions/);
    assert.match(allocation?.description ?? "", /effective/i);
    assert.match(allocation?.description ?? "", /conflict/);
    assert.match(allocation?.description ?? "", /has_stale/);
    assert.match(allocation?.description ?? "", /not yet held/i);
    assert.doesNotMatch(allocation?.description ?? "", /explicit category rows/);

    const cashTargetGet = tools.find((tool) => tool.name === "portfolixir.portfolios.cash_target");
    assert.equal(cashTargetGet?.inputSchema.properties.view.type, "integer");
    const setCashTarget = tools.find(
      (tool) => tool.name === "portfolixir.portfolios.set_cash_target"
    );
    assert.deepEqual(setCashTarget?.inputSchema.properties.cash_target_weight.type, [
      "string",
      "null"
    ]);
    assert.equal(setCashTarget?.inputSchema.properties.view.type, "integer");
  });

  // ADR-0024 modification 1: portfolios are demoted to internal compatibility
  // records. The portfolio tools stay callable (no breaking change in phase 1)
  // but their descriptions must steer agents to buckets/views for grouping.
  it("marks the portfolio list/create tools as deprecated, steering to buckets/views", () => {
    const tools = listTools();

    for (const name of ["portfolixir.portfolios.list", "portfolixir.portfolios.create"]) {
      const tool = tools.find((candidate) => candidate.name === name);
      assert.match(tool?.description ?? "", /deprecated/i, `${name} lacks a deprecation note`);
      assert.match(tool?.description ?? "", /buckets/i, `${name} does not steer to buckets`);
      assert.match(tool?.description ?? "", /views/i, `${name} does not steer to views`);
    }
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

  // User story (Andi, 2026-07-16, ADR-0027): plan versions and depot
  // snapshots are operable by an agent at API parity (FR-14, AR-11) — the
  // restructuring workflow (duplicate plan, freeze state, compare later)
  // never requires the UI.
  it("routes plan-version tools to the plans API", async () => {
    const { client, requests } = createRecordingClient({
      data: { id: 12, name: "Plan 2027", status: "draft" }
    });

    await callTool(client, "portfolixir.plans.duplicate", { plan_id: 4, name: "Plan 2027" });
    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/plans/4/duplicate");
    assert.deepEqual(requests[0].body, { name: "Plan 2027" });

    await callTool(client, "portfolixir.plans.activate", { plan_id: 12 });
    assert.equal(requests[1].method, "POST");
    assert.equal(requests[1].path, "/api/v1/plans/12/activate");
  });

  it("routes snapshot tools to the snapshots API with decimal-string output", async () => {
    const { client, requests } = createRecordingClient({
      data: { id: 3, name: "Before restructuring", as_of: "2026-02-15", view_id: null }
    });

    await callTool(client, "portfolixir.snapshots.create", {
      name: "Before restructuring",
      as_of: "2026-02-15"
    });
    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/snapshots");

    await callTool(client, "portfolixir.snapshots.comparison", {
      portfolio_id: 1,
      snapshot_id: 3
    });
    assert.equal(requests[1].method, "GET");
    assert.equal(requests[1].path, "/api/v1/portfolios/1/snapshots/3/comparison");

    const tools = listTools();
    const comparison = tools.find((tool) => tool.name === "portfolixir.snapshots.comparison");
    assert.ok(comparison?.description.includes("string"));
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

  // User story:
  // As the operating LLM agent holding an external broker position list,
  // I want a read-only reconcile tool whose description steers me toward
  // booking the missing transaction of the correct kind (ADR-0029 6, FR-35),
  // so that the fix-it hammer lands at the moment of temptation instead of a
  // balance snapshot or unpriced delivery distorting the cost basis.
  it("exposes portfolixir.holdings.reconcile with a strict schema and steering description", () => {
    const reconcile = listTools().find((tool) => tool.name === "portfolixir.holdings.reconcile");

    assert.ok(reconcile);
    assert.equal(reconcile?.inputSchema.additionalProperties, false);
    assert.deepEqual(reconcile?.inputSchema.required, ["rows"]);

    const rows = reconcile?.inputSchema.properties.rows;
    assert.equal(rows.type, "array");
    assert.equal(rows.minItems, 1);
    assert.equal(rows.maxItems, 10000);
    assert.equal(rows.items.additionalProperties, false);
    assert.deepEqual(rows.items.required, ["identifier", "quantity"]);
    assert.equal(rows.items.properties.identifier.type, "string");
    assert.equal(rows.items.properties.quantity.type, "string");
    assert.equal(rows.items.properties.currency.type, "string");
    assert.equal(rows.items.properties.security_id.type, "integer");
    assert.equal(reconcile?.inputSchema.properties.portfolio_id.type, "integer");
    assert.equal(reconcile?.inputSchema.properties.view.type, "integer");

    // FR-35: the steering must live in the description the agent reads at the
    // moment of temptation.
    const description = reconcile?.description ?? "";
    assert.match(description, /read-only/i);
    assert.match(description, /booking the missing transaction of the correct kind/);
    assert.match(description, /balance snapshots/);
    assert.match(description, /unpriced/);
    assert.match(description, /last resorts/);
    assert.match(description, /distort/);
    assert.match(description, /confirm/i);
  });

  it("routes portfolixir.holdings.reconcile to POST /holdings/reconcile with the rows body", async () => {
    const { client, requests } = createRecordingClient({
      data: { guidance: "resolve a difference by booking", matched: [], unmatched: [] }
    });

    await callTool(client, "portfolixir.holdings.reconcile", {
      rows: [
        { identifier: "DE0007100000", quantity: "12.5" },
        { identifier: "BTC", quantity: "0.25", currency: "EUR", security_id: 4 }
      ],
      portfolio_id: 3
    });

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/holdings/reconcile");
    assert.deepEqual(requests[0].body, {
      rows: [
        { identifier: "DE0007100000", quantity: "12.5" },
        { identifier: "BTC", quantity: "0.25", currency: "EUR", security_id: 4 }
      ],
      portfolio_id: 3
    });
  });

  it("rejects a comma-decimal reconcile quantity before any API request", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await assert.rejects(
      callTool(client, "portfolixir.holdings.reconcile", {
        rows: [{ identifier: "DE0007100000", quantity: "12,5" }]
      })
    );

    await assert.rejects(callTool(client, "portfolixir.holdings.reconcile", { rows: [] }));

    assert.equal(requests.length, 0);
  });

  // DoS hardening (ADR-0029 §6): the external list is user-supplied content, so
  // the row count is capped before any API request.
  it("rejects more than 10,000 reconcile rows before any API request", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    const rows = Array.from({ length: 10001 }, () => ({
      identifier: "DE0007100000",
      quantity: "1"
    }));

    await assert.rejects(callTool(client, "portfolixir.holdings.reconcile", { rows }));

    assert.equal(requests.length, 0);
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

  // User story:
  // As the operating LLM agent,
  // I want transactions_create to accept all 13 ledger kinds directly,
  // so that I can book dividends, deliveries and transfers without the
  // create-as-buy-then-update detour through momentarily-wrong ledger states.
  //
  // Acceptance criteria:
  // - Every one of the 13 kinds creates in one call, deliveries included.
  // - inbound_delivery REQUIRES a price on MCP create (an unpriced inbound
  //   delivery enters the cost basis at zero) — deliberately stricter than
  //   the API. outbound_delivery does not: the cost fold removes cost at the
  //   running average and ignores its price.
  // - balance_adjustment stays excluded (the set_balance tool owns it).
  it("creates every ledger kind directly (FR-31)", async () => {
    const transactionCreate = listTools().find(
      (tool) => tool.name === "portfolixir.transactions.create"
    );
    assert.deepEqual(transactionCreate?.inputSchema.properties.transaction.properties.type.enum, [
      "buy",
      "sell",
      "dividend",
      "interest",
      "deposit",
      "removal",
      "fee",
      "tax",
      "tax_refund",
      "cash_transfer",
      "inbound_delivery",
      "outbound_delivery",
      "security_transfer"
    ]);
    assert.match(
      String(transactionCreate?.description),
      /unpriced inbound delivery enters the cost basis at zero/i
    );
    assert.match(String(transactionCreate?.description), /positive magnitudes/i);

    const { client, requests } = createRecordingClient({ data: { id: 1 } });

    await callTool(client, "portfolixir.transactions.create", {
      transaction: {
        portfolio_id: 3,
        cash_account_id: 4,
        security_id: 9,
        type: "dividend",
        date: "2026-05-11",
        gross_amount: "12.34",
        currency_code: "EUR"
      }
    });
    // Outbound deliveries need no price — the cost fold removes cost at the
    // running average; a fabricated price would just persist a dead number.
    await callTool(client, "portfolixir.transactions.create", {
      transaction: {
        portfolio_id: 3,
        securities_account_id: 7,
        security_id: 9,
        type: "outbound_delivery",
        date: "2026-05-12",
        quantity: "615",
        currency_code: "EUR"
      }
    });
    await callTool(client, "portfolixir.transactions.create", {
      transaction: {
        portfolio_id: 3,
        securities_account_id: 7,
        counter_securities_account_id: 8,
        security_id: 9,
        type: "security_transfer",
        date: "2026-05-13",
        quantity: "4",
        currency_code: "EUR"
      }
    });

    assert.deepEqual(requests[0], {
      method: "POST",
      path: "/api/v1/transactions",
      body: {
        transaction: {
          portfolio_id: 3,
          cash_account_id: 4,
          security_id: 9,
          type: "dividend",
          date: "2026-05-11",
          gross_amount: "12.34",
          currency_code: "EUR"
        }
      },
      token: "Bearer api-token"
    });
    assert.equal(requests[1].method, "POST");
    assert.equal((requests[1].body as any).transaction.type, "outbound_delivery");
    assert.equal((requests[2].body as any).transaction.type, "security_transfer");
  });

  // User story:
  // As the operating LLM agent,
  // I want the semantic traps written into the tool descriptions I read,
  // so that I book correctly on the first attempt instead of learning by
  // mis-booking.
  //
  // Acceptance criteria:
  // - Create/update descriptions state that a dividend's gross_amount is the
  //   NET cash credited (withheld taxes ride in taxes).
  // - set_balance carries the fix-it-hammer warning (book the missing
  //   transaction of the correct kind; snapshots/unpriced deliveries are
  //   last resorts).
  it("documents booking semantics in the tool descriptions (FR-32)", () => {
    const byName = new Map(listTools().map((tool) => [tool.name, String(tool.description)]));

    for (const name of ["portfolixir.transactions.create", "portfolixir.transactions.update"]) {
      assert.match(byName.get(name) ?? "", /gross_amount is the NET cash credited/i, name);
    }

    assert.match(
      byName.get("portfolixir.cash_accounts.set_balance") ?? "",
      /book(ing)? the missing transaction of the correct kind/i
    );
    assert.match(byName.get("portfolixir.cash_accounts.set_balance") ?? "", /last resort/i);
  });

  it("rejects a delivery create without a price before any API call (FR-31 cost-basis guard)", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });

    await assert.rejects(
      callTool(client, "portfolixir.transactions.create", {
        transaction: {
          portfolio_id: 3,
          securities_account_id: 7,
          security_id: 9,
          type: "inbound_delivery",
          date: "2026-05-14",
          quantity: "50",
          currency_code: "EUR"
        }
      }),
      /price/i
    );
    // Re-typing an existing booking into an inbound delivery without a price
    // would bypass the create guard — the update schema closes that path.
    await assert.rejects(
      callTool(client, "portfolixir.transactions.update", {
        id: 7,
        transaction: { type: "inbound_delivery", quantity: "50" }
      }),
      /price/i
    );
    // Buy stays guarded too: quantity and price remain required for trades.
    await assert.rejects(
      callTool(client, "portfolixir.transactions.create", {
        transaction: {
          portfolio_id: 3,
          securities_account_id: 7,
          security_id: 9,
          type: "buy",
          date: "2026-05-14",
          currency_code: "EUR"
        }
      }),
      /quantity|price/i
    );

    assert.equal(requests.length, 0);
  });

  // User story (ADR-0028 §1/§5, issue #589):
  // As an MCP agent operating the ledger without a UI,
  // I want dedicated split preview/create tools with integer ratio parts,
  // string quantities and descriptions that explain the fan-out, the
  // same-day rejection and the before-history warning,
  // so that I preview and book a corporate action safely in two calls.
  //
  // Acceptance criteria:
  // - Both tools expose integer ratio fields (never Decimal strings) and a
  //   closed schema (additionalProperties: false) plus a zod validator.
  // - preview POSTs to /api/v1/splits/preview, create POSTs to /api/v1/splits.
  // - The descriptions state the all-positioned-portfolios fan-out, the
  //   second-same-day rejection and that the before-history warning means the
  //   quantities may already be post-split (check the preview before booking).
  it("exposes the split flow as preview/create tools with integer ratio schemas", async () => {
    const tools = listTools();

    for (const name of ["portfolixir.splits.preview", "portfolixir.splits.create"]) {
      const tool = tools.find((candidate) => candidate.name === name);
      assert.ok(tool, `${name} is missing`);
      assert.equal(tool?.inputSchema.additionalProperties, false);
      assert.deepEqual(tool?.inputSchema.required, [
        "security_id",
        "date",
        "ratio_numerator",
        "ratio_denominator"
      ]);
      assert.equal(tool?.inputSchema.properties.ratio_numerator.type, "integer");
      assert.equal(tool?.inputSchema.properties.ratio_denominator.type, "integer");
      assert.equal(tool?.inputSchema.properties.date.type, "string");

      // int4 bound (E17 review, finding 4): the ratio parts persist into
      // int4 columns — schema and zod both cap them there.
      assert.equal(tool?.inputSchema.properties.ratio_numerator.maximum, 2147483647);
      assert.equal(tool?.inputSchema.properties.ratio_denominator.maximum, 2147483647);

      // Zod mirrors the schema: non-positive, oversized or missing ratio
      // parts fail before any API call is made.
      assert.throws(() =>
        tool?.zodSchema.parse({
          security_id: 1,
          date: "2026-02-02",
          ratio_numerator: 0,
          ratio_denominator: 1
        })
      );
      assert.throws(() =>
        tool?.zodSchema.parse({
          security_id: 1,
          date: "2026-02-02",
          ratio_numerator: 3000000000,
          ratio_denominator: 1
        })
      );
      assert.doesNotThrow(() =>
        tool?.zodSchema.parse({
          security_id: 1,
          date: "2026-02-02",
          ratio_numerator: 10,
          ratio_denominator: 5
        })
      );
    }

    const create = tools.find((tool) => tool.name === "portfolixir.splits.create");
    assert.match(create?.description ?? "", /all portfolios (holding|with) a position/i);
    assert.match(create?.description ?? "", /second .*same[- ]day .*(split|booking).*reject/i);
    assert.match(create?.description ?? "", /preview/i);

    const preview = tools.find((tool) => tool.name === "portfolixir.splits.preview");
    assert.match(preview?.description ?? "", /already .*post-split/i);
    assert.match(preview?.description ?? "", /effective_date_before_history/);
    // E17 review, finding 5: the per-row bookable flag makes the
    // preview/book divergence explicit.
    assert.match(preview?.description ?? "", /bookable/);
    assert.match(preview?.description ?? "", /no_position_at_effective_date/);
  });

  it("routes the split tools to POST /splits/preview and POST /splits", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.splits.preview", {
      security_id: 9,
      date: "2026-02-02",
      ratio_numerator: 10,
      ratio_denominator: 5
    });
    await callTool(client, "portfolixir.splits.create", {
      security_id: 9,
      date: "2026-02-02",
      ratio_numerator: 2,
      ratio_denominator: 1
    });

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/splits/preview");
    assert.deepEqual(requests[0].body, {
      security_id: 9,
      date: "2026-02-02",
      ratio_numerator: 10,
      ratio_denominator: 5
    });
    assert.equal(requests[1].method, "POST");
    assert.equal(requests[1].path, "/api/v1/splits");
    assert.deepEqual(requests[1].body, {
      security_id: 9,
      date: "2026-02-02",
      ratio_numerator: 2,
      ratio_denominator: 1
    });
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

  // ADR-0028 §2 (issue #590): the per-security quote-basis override is
  // settable over MCP, and the quote/preview tools describe the adjusted
  // basis fields so an agent can act on them.
  it("forwards the treat_quotes_as_raw override and documents the quote basis (ADR-0028)", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 9 } });

    await callTool(client, "portfolixir.securities.update", {
      id: 9,
      security: { treat_quotes_as_raw: true }
    });

    assert.deepEqual(requests[0], {
      method: "PATCH",
      path: "/api/v1/securities/9",
      body: { security: { treat_quotes_as_raw: true } },
      token: "Bearer api-token"
    });

    const tools = listTools();
    const quotesList = tools.find((tool) => tool.name === "portfolixir.quotes.list");
    assert.match(quotesList!.description, /adjusted_close/);
    assert.match(quotesList!.description, /provider_mirror/);

    const preview = tools.find((tool) => tool.name === "portfolixir.splits.preview");
    assert.match(preview!.description, /quote_basis_check/);
    assert.match(preview!.description, /treat_quotes_as_raw/);
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

  it("forwards the view scope through the target weight tools (ADR-0020)", async () => {
    const { client, requests } = createRecordingClient({ data: { targets: [] } });

    await callTool(client, "portfolixir.targets.list", {
      portfolio_id: 3,
      classification_id: 5,
      view: 7
    });
    await callTool(client, "portfolixir.targets.set", {
      portfolio_id: 3,
      classification_id: 5,
      view: 7,
      targets: [{ category_id: 9, target_weight: "0.25" }]
    });
    await callTool(client, "portfolixir.targets.delete", {
      portfolio_id: 3,
      category_id: 9,
      view: 7
    });

    // GET/DELETE carry the view as a query param; PUT carries it in the body.
    assert.equal(requests[0].path, "/api/v1/portfolios/3/targets?classification_id=5&view=7");
    assert.deepEqual(requests[1].body, {
      classification_id: 5,
      view: 7,
      targets: [{ category_id: 9, target_weight: "0.25" }]
    });
    assert.equal(requests[2].path, "/api/v1/portfolios/3/targets/9?view=7");
  });

  it("routes position target tools and forwards a position security_id (ADR-0030, #481)", async () => {
    const { client, requests } = createRecordingClient({
      data: { position_targets: [], effective_targets: [] }
    });

    await callTool(client, "portfolixir.targets.set", {
      portfolio_id: 3,
      classification_id: 5,
      targets: [{ category_id: 9, security_id: 12, target_weight: "0.25" }]
    });
    await callTool(client, "portfolixir.targets.list_positions", {
      portfolio_id: 3,
      classification_id: 5
    });
    await callTool(client, "portfolixir.targets.delete_position", {
      portfolio_id: 3,
      category_id: 9,
      security_id: 12
    });

    // A position target flows through the same set endpoint, carrying security_id.
    assert.deepEqual(requests[0], {
      method: "PUT",
      path: "/api/v1/portfolios/3/targets",
      body: {
        classification_id: 5,
        targets: [{ category_id: 9, security_id: 12, target_weight: "0.25" }]
      },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[1], {
      method: "GET",
      path: "/api/v1/portfolios/3/position_targets?classification_id=5",
      body: undefined,
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[2], {
      method: "DELETE",
      path: "/api/v1/portfolios/3/position_targets/9/12",
      body: undefined,
      token: "Bearer api-token"
    });
  });

  it("routes cash_target read/write to the /cash_target endpoint with a view scope", async () => {
    const { client, requests } = createRecordingClient({
      data: { cash_target_weight: "0.05" }
    });

    await callTool(client, "portfolixir.portfolios.cash_target", { portfolio_id: 3 });
    await callTool(client, "portfolixir.portfolios.cash_target", { portfolio_id: 3, view: 7 });
    await callTool(client, "portfolixir.portfolios.set_cash_target", {
      portfolio_id: 3,
      cash_target_weight: "0.05"
    });
    await callTool(client, "portfolixir.portfolios.set_cash_target", {
      portfolio_id: 3,
      view: 7,
      cash_target_weight: "0.2"
    });
    // Omitting the weight clears the cash target.
    await callTool(client, "portfolixir.portfolios.set_cash_target", { portfolio_id: 3 });

    assert.deepEqual(requests[0], {
      method: "GET",
      path: "/api/v1/portfolios/3/cash_target",
      body: undefined,
      token: "Bearer api-token"
    });
    assert.equal(requests[1].path, "/api/v1/portfolios/3/cash_target?view=7");

    assert.deepEqual(requests[2], {
      method: "PUT",
      path: "/api/v1/portfolios/3/cash_target",
      body: { cash_target_weight: "0.05" },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[3].body, { view: 7, cash_target_weight: "0.2" });
    assert.deepEqual(requests[4].body, { cash_target_weight: null });
  });

  it("issues a GET to /allocation for portfolixir.portfolios.allocation", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        portfolio_id: 3,
        classification_id: 5,
        categories: [
          // drift_weight = actual - target (positive = overweight, ADR-0023).
          { category_id: 9, actual_weight: "0.4", target_weight: "0.25", drift_weight: "0.15" }
        ]
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.allocation", {
      portfolio_id: 3,
      classification_id: 5
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/portfolios/3/allocation?classification_id=5");
    assert.match(result.content[0].text, /0\.15/);
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

  it("forwards the view scope param on the analytics tools", async () => {
    const { client, requests } = createRecordingClient({ data: { portfolio_id: 3 } });

    await callTool(client, "portfolixir.portfolios.valuation", { portfolio_id: 3, view: 5 });
    await callTool(client, "portfolixir.portfolios.allocation", {
      portfolio_id: 3,
      classification_id: 7,
      view: 5
    });
    await callTool(client, "portfolixir.portfolios.performance", {
      portfolio_id: 3,
      period: "ytd",
      view: 5
    });
    await callTool(client, "portfolixir.portfolios.risk", { portfolio_id: 3, view: 5, top_n: 4 });

    assert.equal(requests[0].path, "/api/v1/portfolios/3/valuation?view=5");
    assert.equal(requests[1].path, "/api/v1/portfolios/3/allocation?classification_id=7&view=5");
    assert.equal(requests[2].path, "/api/v1/portfolios/3/performance?period=ytd&view=5");
    assert.equal(requests[3].path, "/api/v1/portfolios/3/risk?view=5&top_n=4");
  });

  it("routes bucket CRUD tools to the /buckets endpoints", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1, name: "Retirement" } });

    await callTool(client, "portfolixir.buckets.list", {});
    await callTool(client, "portfolixir.buckets.get", { id: 1 });
    await callTool(client, "portfolixir.buckets.create", { bucket: { name: "Retirement" } });
    await callTool(client, "portfolixir.buckets.update", { id: 1, bucket: { color: "#0f766e" } });
    await callTool(client, "portfolixir.buckets.delete", { id: 1 });

    assert.deepEqual(requests[0], {
      method: "GET",
      path: "/api/v1/buckets",
      body: undefined,
      token: "Bearer api-token"
    });
    assert.equal(requests[1].path, "/api/v1/buckets/1");
    assert.deepEqual(requests[2], {
      method: "POST",
      path: "/api/v1/buckets",
      body: { bucket: { name: "Retirement" } },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[3], {
      method: "PATCH",
      path: "/api/v1/buckets/1",
      body: { bucket: { color: "#0f766e" } },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[4], {
      method: "DELETE",
      path: "/api/v1/buckets/1",
      body: undefined,
      token: "Bearer api-token"
    });
  });

  // User story (ADR-0024, epic story 2): as an MCP client I want the bucket
  // dimension on create, so that the LLM can distinguish the exclusive scope
  // dimension from free overlapping tags.
  it("passes the bucket dimension through on create and rejects unknown values", async () => {
    const { client, requests } = createRecordingClient({
      data: { id: 1, name: "Main", dimension: "scope" }
    });

    await callTool(client, "portfolixir.buckets.create", {
      bucket: { name: "Main", dimension: "scope" }
    });

    assert.deepEqual(requests[0].body, { bucket: { name: "Main", dimension: "scope" } });

    // The zod validator (enforced by the MCP server layer) pins the closed
    // dimension taxonomy.
    const create = listTools().find((tool) => tool.name === "portfolixir.buckets.create");
    assert.ok(create?.zodSchema.safeParse({ bucket: { name: "Main", dimension: "scope" } }).success);
    assert.ok(!create?.zodSchema.safeParse({ bucket: { name: "Bad", dimension: "layer" } }).success);
  });

  it("routes view CRUD and set_buckets to the /views endpoints", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 2, name: "Liquid" } });

    await callTool(client, "portfolixir.views.list", {});
    await callTool(client, "portfolixir.views.get", { id: 2 });
    await callTool(client, "portfolixir.views.create", { view: { name: "Liquid" } });
    await callTool(client, "portfolixir.views.update", {
      id: 2,
      view: { include_all: false }
    });
    await callTool(client, "portfolixir.views.set_buckets", {
      id: 2,
      include: [3, 4],
      exclude: [9]
    });
    await callTool(client, "portfolixir.views.delete", { id: 2 });

    assert.equal(requests[0].path, "/api/v1/views");
    assert.equal(requests[1].path, "/api/v1/views/2");
    assert.deepEqual(requests[2].body, { view: { name: "Liquid" } });
    assert.deepEqual(requests[3].body, { view: { include_all: false } });
    assert.deepEqual(requests[4], {
      method: "PUT",
      path: "/api/v1/views/2/buckets",
      body: { include: [3, 4], exclude: [9] },
      token: "Bearer api-token"
    });
    // Omitted bucket sets default to empty arrays.
    assert.equal(requests[5].method, "DELETE");
    assert.equal(requests[5].path, "/api/v1/views/2");
  });

  // User story: as an MCP client I want one tool for a view's cross-portfolio
  // total wealth, so that the LLM never has to sum portfolio valuations itself.
  it("issues a GET to /views/:id/valuation for portfolixir.views.valuation", async () => {
    const { client, requests } = createRecordingClient({
      data: { view_id: 2, total_with_cash: "750", overlap: { overlapping: false } }
    });

    const result = await callTool(client, "portfolixir.views.valuation", { id: 2 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/views/2/valuation");
    assert.equal((result.structuredContent as any).data.total_with_cash, "750");
  });

  it("defaults omitted view bucket sets to empty arrays", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 2 } });

    await callTool(client, "portfolixir.views.set_buckets", { id: 2 });

    assert.deepEqual(requests[0].body, { include: [], exclude: [] });
  });

  it("routes bucket assignment tools to the depot/cash/position endpoints", async () => {
    const { client, requests } = createRecordingClient({ data: { bucket_ids: [3] } });

    await callTool(client, "portfolixir.securities_accounts.set_buckets", {
      id: 1,
      bucket_ids: [3, 4]
    });
    await callTool(client, "portfolixir.cash_accounts.set_buckets", { id: 2, bucket_ids: [5] });
    await callTool(client, "portfolixir.securities_accounts.set_position_buckets", {
      id: 1,
      security_id: 7,
      bucket_ids: [3]
    });
    await callTool(client, "portfolixir.securities_accounts.clear_position_buckets", {
      id: 1,
      security_id: 7
    });

    assert.deepEqual(requests[0], {
      method: "PUT",
      path: "/api/v1/securities_accounts/1/buckets",
      body: { bucket_ids: [3, 4] },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[1], {
      method: "PUT",
      path: "/api/v1/cash_accounts/2/buckets",
      body: { bucket_ids: [5] },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[2], {
      method: "PUT",
      path: "/api/v1/securities_accounts/1/positions/7/buckets",
      body: { bucket_ids: [3] },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[3], {
      method: "DELETE",
      path: "/api/v1/securities_accounts/1/positions/7/buckets",
      body: undefined,
      token: "Bearer api-token"
    });
  });

  // User story: as an MCP client I want to read and set the default view
  // (ADR-0024), so that the Wealth page / dashboard scope is scriptable.
  // No financial decimals are involved in this preference.
  it("routes the default-view preference tools to /settings/default_view", async () => {
    const { client, requests } = createRecordingClient({
      data: { view_id: 2, view: { id: 2, name: "Mine" } }
    });

    const result = await callTool(client, "portfolixir.settings.get_default_view", {});
    await callTool(client, "portfolixir.settings.set_default_view", { view_id: 2 });
    // Omitted view_id clears back to Everything (view_id null).
    await callTool(client, "portfolixir.settings.set_default_view", {});

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/settings/default_view");
    assert.equal((result.structuredContent as any).data.view.name, "Mine");
    assert.deepEqual(requests[1], {
      method: "PUT",
      path: "/api/v1/settings/default_view",
      body: { view_id: 2 },
      token: "Bearer api-token"
    });
    assert.deepEqual(requests[2].body, { view_id: null });
  });

  it("records the explicit-empty position override with an empty bucket_ids array", async () => {
    const { client, requests } = createRecordingClient({ data: { override: "explicit_empty" } });

    await callTool(client, "portfolixir.securities_accounts.set_position_buckets", {
      id: 1,
      security_id: 7
    });

    assert.deepEqual(requests[0].body, { bucket_ids: [] });
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

    // Zod-valid payload (all required fields present) so the call reaches the
    // API and the upstream 422 is what surfaces — schema-invalid payloads now
    // fail earlier, in callTool's own validation.
    await assert.rejects(
      callTool(client, "portfolixir.securities.create", {
        security: { name: "", currency_code: "EUR" }
      }),
      /Portfolixir API request failed/
    );
  });

  // User story:
  // As an MCP operator whose security got a new ISIN through a corporate
  // action, I want a dedicated isin_change tool plus alias visibility and a
  // journaled alias delete (ADR-0029 §3, AR-11 parity), so that imports keep
  // matching the security via its former ISIN.
  it("routes securities.get to GET /api/v1/securities/:id", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 7 } });

    await callTool(client, "portfolixir.securities.get", { id: 7 });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/securities/7");
  });

  it("routes isin_change to POST /securities/:id/isin-change with the body", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 7 } });

    await callTool(client, "portfolixir.securities.isin_change", {
      security_id: 7,
      new_isin: "DE0007654321",
      changed_on: "2026-07-01",
      note: "merger rename"
    });

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/securities/7/isin-change");
    assert.deepEqual(requests[0].body, {
      isin_change: {
        new_isin: "DE0007654321",
        changed_on: "2026-07-01",
        note: "merger rename"
      }
    });
  });

  it("rejects an isin_change call without new_isin before any API request", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 7 } });

    await assert.rejects(
      callTool(client, "portfolixir.securities.isin_change", { security_id: 7 })
    );

    assert.equal(requests.length, 0);
  });

  it("routes delete_isin_alias to DELETE /securities/:id/identifier_aliases/:alias_id", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.securities.delete_isin_alias", {
      security_id: 7,
      alias_id: 3
    });

    assert.equal(requests[0].method, "DELETE");
    assert.equal(requests[0].path, "/api/v1/securities/7/identifier_aliases/3");
  });
});
