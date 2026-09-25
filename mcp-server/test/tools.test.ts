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
      "portfolixir.contract.get",
      "portfolixir.securities.list",
      "portfolixir.securities.get",
      "portfolixir.securities.create",
      "portfolixir.securities.update",
      "portfolixir.securities.delete",
      "portfolixir.securities.isin_change",
      "portfolixir.securities.delete_isin_alias",
      "portfolixir.securities.search_online",
      "portfolixir.securities.metrics",
      "portfolixir.events.list",
      "portfolixir.events.create",
      "portfolixir.events.update",
      "portfolixir.events.delete",
      "portfolixir.events.upcoming",
      "portfolixir.events.unconfirmed",
      "portfolixir.events.stale",
      "portfolixir.notes.list",
      "portfolixir.notes.append",
      "portfolixir.notes.unreviewed",
      "portfolixir.notes.uncorroborated",
      "portfolixir.notes.expiring",
      "portfolixir.quotes.sync",
      "portfolixir.quotes.list",
      "portfolixir.quotes.upsert",
      "portfolixir.quotes.release",
      "portfolixir.portfolios.list",
      "portfolixir.portfolios.create",
      "portfolixir.cash_accounts.list",
      "portfolixir.cash_accounts.create",
      "portfolixir.cash_accounts.update",
      "portfolixir.cash_accounts.delete",
      "portfolixir.cash_accounts.remove_former_name",
      "portfolixir.securities_accounts.list",
      "portfolixir.securities_accounts.create",
      "portfolixir.securities_accounts.update",
      "portfolixir.securities_accounts.delete",
      "portfolixir.securities_accounts.remove_former_name",
      "portfolixir.transactions.list",
      "portfolixir.transactions.create",
      "portfolixir.transactions.update",
      "portfolixir.transactions.delete",
      "portfolixir.splits.preview",
      "portfolixir.splits.create",
      "portfolixir.holdings.list",
      "portfolixir.cashflow.realized_gains",
      "portfolixir.cashflow.external_flows",
      "portfolixir.cashflow.costs",
      "portfolixir.holdings.by_security",
      "portfolixir.holdings.negative",
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
    "portfolixir.portfolios.category_results",
      "portfolixir.portfolios.risk",
      "portfolixir.policy_rules.list",
      "portfolixir.policy_rules.get",
      "portfolixir.policy_rules.create",
      "portfolixir.policy_rules.add_version",
      "portfolixir.policy_rules.rename",
      "portfolixir.policy_rules.retire",
      "portfolixir.policy_rules.delete",
      "portfolixir.portfolios.policy_findings",
      "portfolixir.portfolios.cash_target",
      "portfolixir.portfolios.set_cash_target",
      "portfolixir.cash_accounts.set_balance",
      "portfolixir.portfolios.income",
      "portfolixir.portfolios.performance",
      "portfolixir.portfolios.benchmark",
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
      "portfolixir.views.performance",
      "portfolixir.views.benchmark",
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
      "portfolixir.snapshots.comparison",
      "portfolixir.tax_parameters.list",
      "portfolixir.tax_parameters.upsert",
      "portfolixir.tax_profiles.list",
      "portfolixir.tax_profiles.create",
      "portfolixir.tax_profiles.update",
      "portfolixir.tax_profiles.delete",
      "portfolixir.allowance_orders.list",
      "portfolixir.allowance_orders.put",
      "portfolixir.allowance_orders.delete",
      "portfolixir.tax_snapshots.list",
      "portfolixir.tax_snapshots.get",
      "portfolixir.tax_snapshots.create",
      "portfolixir.tax_snapshots.update",
      "portfolixir.tax_snapshots.delete",
      "portfolixir.tax_snapshots.trim_budget"
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
    // The settlement guard (#395) is stated where the agent reads the tool:
    // which figure must agree with which, and which patches re-check it.
    assert.match(transactionCreate?.description ?? "", /settlement_amount \+ fees \+ taxes/);
    assert.match(transactionCreate?.description ?? "", /settlement_amount - fees - taxes/);
    const transactionUpdate = tools.find((tool) => tool.name === "portfolixir.transactions.update");
    assert.match(transactionUpdate?.description ?? "", /re-checks the cross-currency settlement/);
    assert.match(transactionUpdate?.description ?? "", /notes or date on an older booking/);

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

    // E25 S6, F20 (decision T-9): a quote an agent writes is manual, so the
    // schema offers `manual` alone and may omit it; a provider source is the
    // sync's to state and is refused before any request (#508's closed set,
    // narrowed).
    const quoteUpsert = tools.find((tool) => tool.name === "portfolixir.quotes.upsert");
    assert.deepEqual(
      quoteUpsert?.inputSchema.properties.quotes.items.properties.source.enum,
      ["manual"]
    );
    assert.deepEqual(quoteUpsert?.inputSchema.properties.quotes.items.required, ["date", "close"]);
    for (const quote of [
      { date: "2026-06-19", close: "100.00", source: "manual" },
      { date: "2026-06-19", close: "100.00" }
    ]) {
      assert.doesNotThrow(() => quoteUpsert?.zodSchema.parse({ security_id: 1, quotes: [quote] }));
    }
    for (const source of ["e2e", "auto", "coingecko", "portfolio_performance"]) {
      assert.throws(() =>
        quoteUpsert?.zodSchema.parse({
          security_id: 1,
          quotes: [{ date: "2026-06-19", close: "100.00", source }]
        })
      );
    }

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

    // #568 (ADR-0034): both performance tools document the money-weighted
    // companions riding the response — invested capital, wealth multiple
    // (null when net invested is not positive) and the period MWR.
    for (const name of ["portfolixir.portfolios.performance", "portfolixir.views.performance"]) {
      const description = tools.find((tool) => tool.name === name)?.description ?? "";
      assert.match(description, /invested_capital/);
      assert.match(description, /wealth_multiple/);
      assert.match(description, /mwr/);
      // ADR-0039 C4 (I4): freshness and the computation basis ride every
      // performance payload; the tool descriptions must say so, so the agent
      // reads as_of/stale instead of assuming a just-computed figure.
      assert.match(description, /as_of/);
      assert.match(description, /stale/);
      assert.match(description, /computation_basis/);
    }

    // ADR-0046 (#572): the two benchmark tools require the benchmark selector
    // and document both comparisons, the excluded flows, the freshness pair,
    // the computation basis and the frictionless assumption.
    for (const name of ["portfolixir.portfolios.benchmark", "portfolixir.views.benchmark"]) {
      const benchmarkTool = tools.find((tool) => tool.name === name);
      const description = benchmarkTool?.description ?? "";
      assert.ok(benchmarkTool?.inputSchema.required.includes("benchmark"), name);
      assert.equal(benchmarkTool?.inputSchema.properties.benchmark.type, "string");
      assert.match(description, /bought_once/);
      assert.match(description, /savings_plan/);
      assert.match(description, /end_value_delta/);
      assert.match(description, /excluded_flows/);
      assert.match(description, /rebase_day/);
      assert.match(description, /benchmark_mwr/);
      assert.match(description, /frictionless/);
      assert.match(description, /as_of/);
      assert.match(description, /stale/);
      assert.match(description, /computation_basis/);
    }

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

  // User story (#705):
  // As the LLM agent maintaining this catalog,
  // I want the data-quality sets as a named predicate on securities.list,
  // so that I can work the sets the dashboard counts instead of only being
  // told how many there are.
  //
  // Acceptance criteria:
  // - The tool exposes exactly the predicates the engine defines — since
  //   #717 that includes missing_fx (priced, but no stored rate to the
  //   base currency).
  // - It forwards the choice to the API rather than filtering client-side.
  // - Its description says what "stale" means, so an agent needs no second
  //   call to find out.
  it("exposes the data-quality predicates on securities.list and forwards them", async () => {
    const tools = listTools();
    const securitiesList = tools.find((tool) => tool.name === "portfolixir.securities.list");

    assert.deepEqual(securitiesList?.inputSchema.properties.data_quality.enum, [
      "stale_quote",
      "missing_quote",
      "missing_logo",
      "missing_fx"
    ]);

    // The threshold and the stale/missing distinction travel with the tool.
    assert.match(securitiesList?.description ?? "", /7 days/);
    assert.match(securitiesList?.description ?? "", /INCLUDING never-priced/);

    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.securities.list", {
      data_quality: "stale_quote",
      holding_status: "held"
    });

    assert.equal(
      requests[0].path,
      "/api/v1/securities?holding_status=held&data_quality=stale_quote"
    );
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

  // User story (FR-37, issue #665):
  // As the operating LLM agent,
  // I want sparse fieldsets, roll-up-only aggregates and the drift threshold
  // available over MCP exactly as over the API,
  // so that the read-ergonomics win reaches the surface I actually use.
  //
  // Acceptance criteria:
  // - transactions.list / holdings.list forward `fields` as a comma list.
  // - portfolios.valuation / portfolios.allocation forward include_positions;
  //   allocation also forwards min_drift (a Decimal string).
  // - The fields enums mirror the API whitelists.
  it("forwards the FR-37 read-ergonomics params (fields, include_positions, min_drift)", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.transactions.list", {
      fields: ["id", "type", "date", "gross_amount"]
    });
    assert.equal(requests[0].path, "/api/v1/transactions?fields=id%2Ctype%2Cdate%2Cgross_amount");

    await callTool(client, "portfolixir.holdings.list", {
      portfolio_id: 3,
      fields: ["security_id", "quantity", "market_value"]
    });
    assert.equal(
      requests[1].path,
      "/api/v1/portfolios/3/holdings?fields=security_id%2Cquantity%2Cmarket_value"
    );

    await callTool(client, "portfolixir.portfolios.valuation", {
      portfolio_id: 3,
      include_positions: false
    });
    assert.equal(requests[2].path, "/api/v1/portfolios/3/valuation?include_positions=false");

    await callTool(client, "portfolixir.portfolios.allocation", {
      portfolio_id: 3,
      classification_id: 2,
      include_positions: false,
      min_drift: "0.05"
    });
    assert.equal(
      requests[3].path,
      "/api/v1/portfolios/3/allocation?classification_id=2&include_positions=false&min_drift=0.05"
    );
  });

  // User story (issue #724):
  // As the operating LLM agent,
  // I want the realized-gains roll-up as a tool,
  // so that the figure the operator reads on the Cash-flow facet is the
  // same figure I reason over — FX basis and exclusions included.
  //
  // Acceptance criteria:
  // - cashflow.realized_gains reads GET /api/v1/realized_gains.
  // - The description states the D-1 basis: close-date EUR-hub conversion,
  //   unconvertible sales excluded and named.
  it("serves the realized-gains roll-up with its stated FX basis", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.cashflow.realized_gains", {});
    assert.equal(requests[0].path, "/api/v1/realized_gains");

    const tools = listTools();
    const tool = tools.find((t) => t.name === "portfolixir.cashflow.realized_gains");
    assert.ok(tool, "cashflow.realized_gains tool missing");
    assert.match(tool!.description ?? "", /EUR hub/);
    assert.match(tool!.description ?? "", /excluded/i);
    assert.match(tool!.description ?? "", /close date/i);
  });

  // User story (issue #725):
  // As the operating LLM agent,
  // I want the deposits-and-withdrawals roll-up as a tool,
  // so that the "Ersparnis" figure and its stated difference from
  // invested_capital are readable where I reason.
  it("serves the external-flows roll-up and states the invested-capital difference", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.cashflow.external_flows", {});
    assert.equal(requests[0].path, "/api/v1/external_flows");

    const tools = listTools();
    const tool = tools.find((t) => t.name === "portfolixir.cashflow.external_flows");
    assert.ok(tool, "cashflow.external_flows tool missing");
    assert.match(tool!.description ?? "", /invested_capital/);
    assert.match(tool!.description ?? "", /EUR hub/);
    assert.match(tool!.description ?? "", /excluded/i);
  });

  // User story (issue #726):
  // As the operating LLM agent,
  // I want the fees-and-taxes roll-up as a tool,
  // so that the costs figure carries its legs-not-gross basis where I
  // reason, not in a doc page.
  it("serves the costs roll-up and states the legs-not-gross basis", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.cashflow.costs", {});
    assert.equal(requests[0].path, "/api/v1/costs");

    const tools = listTools();
    const tool = tools.find((t) => t.name === "portfolixir.cashflow.costs");
    assert.ok(tool, "cashflow.costs tool missing");
    assert.match(tool!.description ?? "", /legs/);
    assert.match(tool!.description ?? "", /gross/i);
    assert.match(tool!.description ?? "", /EUR hub/);
    assert.match(tool!.description ?? "", /excluded/i);
  });

  // User story (issue #732, extending FR-37):
  // As the operating LLM agent syncing the catalog,
  // I want `fields` on securities.list too,
  // so that the one list that already had the operator's column picker stops
  // being the one list without the agent's sparse fieldset.
  //
  // Acceptance criteria:
  // - securities.list forwards `fields` as a comma list.
  // - The enum mirrors the API's full-projection whitelist (spot-checked on
  //   full-only fields), and the description states that fields supersedes
  //   projection.
  it("forwards fields on securities.list and documents that it supersedes projection", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.securities.list", {
      fields: ["id", "name", "exchange_code"]
    });
    assert.equal(requests[0].path, "/api/v1/securities?fields=id%2Cname%2Cexchange_code");

    const tools = await listTools(client);
    const list = tools.find((t) => t.name === "portfolixir.securities.list");
    assert.ok(list, "securities.list tool missing");
    const fieldsSchema = (list!.inputSchema as any).properties.fields;
    assert.ok(fieldsSchema, "securities.list has no fields property");
    for (const fullOnly of ["exchange_code", "note", "attributes", "updated_at"]) {
      assert.ok(
        fieldsSchema.items.enum.includes(fullOnly),
        `fields enum misses full-projection field ${fullOnly}`
      );
    }
    assert.match(list!.description ?? "", /supersedes projection/i);
  });

  // User story (issue #667):
  // As the operating LLM agent deciding a trim from the allocation drift,
  // I want tax_context=true on the allocation tool and the activity-aware
  // staleness named in the tax tool descriptions,
  // so that the tax headroom and its freshness are readable where the
  // decision is made.
  //
  // Acceptance criteria:
  // - portfolios.allocation forwards tax_context.
  // - The tax_snapshots.list and trim_budget descriptions name the
  //   staleness object and its activity condition.
  it("forwards tax_context and documents the staleness assessment (#667)", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.portfolios.allocation", {
      portfolio_id: 3,
      classification_id: 2,
      tax_context: true
    });
    assert.equal(
      requests[0].path,
      "/api/v1/portfolios/3/allocation?classification_id=2&tax_context=true"
    );

    const tools = listTools();
    const snapshotList = tools.find((tool) => tool.name === "portfolixir.tax_snapshots.list");
    assert.match(String(snapshotList?.description), /staleness/);
    assert.match(String(snapshotList?.description), /activity_since_count/);

    const trimBudget = tools.find(
      (tool) => tool.name === "portfolixir.tax_snapshots.trim_budget"
    );
    assert.match(String(trimBudget?.description), /staleness/);
    assert.match(String(trimBudget?.description), /activity_since_count/);
  });

  // User story (FR-38, issue #666):
  // As the operating LLM agent on a recurring run,
  // I want ?since= delta reads on transactions.list and securities.list over
  // MCP,
  // so that a sync run transfers only what changed since the last run —
  // pull-only by design (push delivery stays gated at B3.7).
  //
  // Acceptance criteria:
  // - Both list tools forward `since` as a query parameter.
  it("forwards since= for delta reads on transactions.list and securities.list", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.transactions.list", {
      since: "2026-06-01T00:00:00Z"
    });
    assert.equal(requests[0].path, "/api/v1/transactions?since=2026-06-01T00%3A00%3A00Z");

    await callTool(client, "portfolixir.securities.list", {
      since: "2026-06-01T00:00:00Z"
    });
    assert.equal(requests[1].path, "/api/v1/securities?since=2026-06-01T00%3A00%3A00Z");
  });

  // User story (issue #831, Sprint 14 D2):
  // As the operating LLM agent reading the research log and the calendar,
  // I want the re-import guarantee stated in the descriptions of the reads it
  // protects,
  // so that I stop re-asking whether a Portfolio Performance re-import wipes
  // them — the answer arrives where I read, not on a page I never open.
  //
  // Acceptance criteria:
  // - Every research-log read (notes.list, notes.unreviewed,
  //   notes.uncorroborated, notes.expiring) and every security-events read
  //   (events.list, events.upcoming, events.unconfirmed, events.stale) states
  //   that a Portfolio Performance re-import does not destroy the research
  //   log or the security events.
  it("states the re-import guarantee on every research-log and events read", () => {
    const tools = listTools();

    for (const name of [
      "portfolixir.notes.list",
      "portfolixir.notes.unreviewed",
      "portfolixir.notes.uncorroborated",
      "portfolixir.notes.expiring",
      "portfolixir.events.list",
      "portfolixir.events.upcoming",
      "portfolixir.events.unconfirmed",
      "portfolixir.events.stale"
    ]) {
      const description = String(tools.find((tool) => tool.name === name)?.description);

      assert.match(
        description,
        /A Portfolio Performance re-import does not destroy the research log or the security events/,
        name
      );
    }
  });

  // User story (FR-38, issue #830, Sprint 14 D-5):
  // As the operating LLM agent on a scheduled run,
  // I want since= on the other row-collection reads I poll — a security's
  // research log and events, the category and position target reads —
  // so that every read of the family is a delta read, not a full re-read.
  //
  // Acceptance criteria:
  // - notes.list, events.list, targets.list and targets.list_positions expose
  //   since as a string and forward it as a query parameter.
  // - The time-derived queues (notes.unreviewed/expiring/uncorroborated,
  //   events.upcoming/stale/unconfirmed) and the derived projections do NOT
  //   expose since: their membership moves with time or a basis, not a row.
  it("forwards since= on the row-collection reads of #830 and keeps it off the queues", async () => {
    const { client, requests } = createRecordingClient({ data: {} });
    const since = "2026-06-01T00:00:00Z";
    const encoded = "since=2026-06-01T00%3A00%3A00Z";

    await callTool(client, "portfolixir.notes.list", { security_id: 7, since });
    await callTool(client, "portfolixir.events.list", { security_id: 7, since });
    await callTool(client, "portfolixir.targets.list", { portfolio_id: 3, since });
    await callTool(client, "portfolixir.targets.list_positions", { portfolio_id: 3, since });

    assert.deepEqual(
      requests.map((request) => request.path),
      [
        `/api/v1/securities/7/notes?${encoded}`,
        `/api/v1/securities/7/events?${encoded}`,
        `/api/v1/portfolios/3/targets?${encoded}`,
        `/api/v1/portfolios/3/position_targets?${encoded}`
      ]
    );

    const tools = listTools();
    const byName = (name: string) => tools.find((tool) => tool.name === name) as any;

    for (const name of [
      "portfolixir.notes.list",
      "portfolixir.events.list",
      "portfolixir.targets.list",
      "portfolixir.targets.list_positions"
    ]) {
      assert.equal(byName(name).inputSchema.properties.since?.type, "string", name);
      assert.match(String(byName(name).description), /since/, name);
    }

    for (const name of [
      "portfolixir.notes.unreviewed",
      "portfolixir.notes.expiring",
      "portfolixir.notes.uncorroborated",
      "portfolixir.events.upcoming",
      "portfolixir.events.stale",
      "portfolixir.events.unconfirmed",
      "portfolixir.portfolios.valuation",
      "portfolixir.portfolios.allocation",
      "portfolixir.portfolios.performance",
      "portfolixir.portfolios.risk"
    ]) {
      const tool = byName(name);
      assert.ok(tool, name);
      assert.equal(tool.inputSchema.properties?.since, undefined, name);
    }
  });

  // User story (Sprint 7 closing act, #414 parity gap):
  // As the operating LLM agent,
  // I want the per-booking running balance of a cash account that the
  // Transactions page shows,
  // so that I can audit a statement over MCP without re-deriving the fold
  // myself from the bookings.
  //
  // Acceptance criteria:
  // - transactions.list accepts running_balance_for and forwards it.
  // - The tool description states the two properties an agent gets wrong
  //   otherwise: the whole-history fold, and null on untouched rows.
  it("forwards running_balance_for on transactions.list", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.transactions.list", {
      from: "2026-02-01",
      running_balance_for: 7
    });
    assert.equal(requests[0].path, "/api/v1/transactions?from=2026-02-01&running_balance_for=7");

    const listTool = listTools().find((tool) => tool.name === "portfolixir.transactions.list");
    assert.match(String(listTool?.description), /whole history/i);
    assert.match(String(listTool?.description), /null/i);
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

  // User story (#406):
  // As the operating LLM agent,
  // I want the holdings/valuation tools to teach me the honest unvalued
  // states (no_price vs missing_fx with the native price kept visible),
  // so that I can tell an import gap from a missing exchange rate instead of
  // reporting "no price at all" for a priced position.
  it("passes the unvalued_reason fields through and documents them", async () => {
    const { client } = createRecordingClient({
      data: {
        currency: "EUR",
        as_of: "2026-06-14",
        note: "unvalued_reason says which",
        holdings: [
          {
            security_id: 9,
            quantity: "5",
            market_value: null,
            valued: false,
            latest_price: "120",
            price_currency: "USD",
            price_source: "quote",
            unvalued_reason: "missing_fx"
          }
        ]
      }
    });

    const result = await callTool(client, "portfolixir.holdings.by_security", {});
    assert.match(result.content[0].text, /missing_fx/);
    assert.match(result.content[0].text, /120/);

    const bySecurity = listTools().find((tool) => tool.name === "portfolixir.holdings.by_security");
    assert.match(bySecurity?.description ?? "", /unvalued_reason/);
    assert.match(bySecurity?.description ?? "", /missing_fx/);

    const valuation = listTools().find((tool) => tool.name === "portfolixir.portfolios.valuation");
    assert.match(valuation?.description ?? "", /unvalued_reason/);

    const viewValuation = listTools().find((tool) => tool.name === "portfolixir.views.valuation");
    assert.match(viewValuation?.description ?? "", /unvalued_reason/);
  });

  // User story (#570):
  // As the operating LLM agent,
  // I want the negative-holdings data-quality report as a tool,
  // so that import debris from unmodeled corporate actions is visible to
  // automation the same way the Wealth page reports it.
  it("issues a GET to /holdings/negative for portfolixir.holdings.negative", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        as_of: "2026-08-01",
        note: "negative holdings are import debris",
        rows: [
          {
            portfolio_id: 1,
            securities_account_id: 4,
            depot_name: "Main Depot",
            security_id: 9,
            security_name: "Doomed Co.",
            isin: null,
            quantity: "-400",
            total_quantity: "-350"
          }
        ],
        totals: [{ security_id: 9, security_name: "Doomed Co.", total_quantity: "-350" }]
      }
    });

    const result = await callTool(client, "portfolixir.holdings.negative", {});

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/holdings/negative");
    assert.equal(requests[0].token, "Bearer api-token");
    assert.match(result.content[0].text, /-400/);
    assert.match(result.content[0].text, /Doomed Co./);
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

  // E25 S6, G27 under decision T-9: the journaled release of manual quotes,
  // agent-first — its control on the security page is Sprint 17's.
  it("releases a security's manual quotes of a range through the API", async () => {
    const { client, requests } = createRecordingClient({
      data: { security_id: 42, from: "2026-02-01", to: "2026-02-28", released: ["2026-02-02"] }
    });

    const result = await callTool(client, "portfolixir.quotes.release", {
      security_id: 42,
      from: "2026-02-01",
      to: "2026-02-28"
    });

    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].path, "/api/v1/securities/42/quotes/release");
    assert.deepEqual(requests[0].body, { from: "2026-02-01", to: "2026-02-28" });
    assert.match(result.content[0].text, /2026-02-02/);

    const release = listTools().find((tool) => tool.name === "portfolixir.quotes.release");
    assert.deepEqual(release?.inputSchema.required, ["security_id", "from", "to"]);
    assert.match(release?.description ?? "", /journal/i);
    assert.match(release?.description ?? "", /Sprint 17/);
    assert.throws(() => release?.zodSchema.parse({ security_id: 42, from: "2026-02-01" }));

    const upsert = listTools().find((tool) => tool.name === "portfolixir.quotes.upsert");
    assert.match(upsert?.description ?? "", /stored as manual/);
    assert.match(upsert?.description ?? "", /replaced/);
  });

  // E25 S6, F45 and T-10: view-definition writes are journaled with the sets
  // before and after, and a bucket delete rewrites every owner through its
  // journaled writer, an emptied override staying explicit-empty.
  it("states the journaled view writes and the bucket delete's explicit-empty rule", () => {
    const description = (name: string) =>
      listTools().find((tool) => tool.name === name)?.description ?? "";

    for (const name of ["portfolixir.views.update", "portfolixir.views.set_buckets"]) {
      assert.match(description(name), /journaled/i);
      assert.match(description(name), /before and after/);
    }

    assert.match(description("portfolixir.views.delete"), /journaled/);

    const bucketDelete = description("portfolixir.buckets.delete");
    assert.match(bucketDelete, /journaled/);
    assert.match(bucketDelete, /explicit-empty/);
    assert.match(bucketDelete, /does not inherit/);
  });

  // E25 S6, F44 and G09: an entry's as_of and an event's checked_at cannot
  // lie in the future, and the tools say so where the agent reads the schema.
  it("states the future-date refusals on the research and event writes", () => {
    const property = (name: string, path: string[]) => {
      let node: any = listTools().find((tool) => tool.name === name)?.inputSchema;
      for (const key of path) node = node?.properties?.[key];
      return (node?.description as string | undefined) ?? "";
    };

    assert.match(property("portfolixir.notes.append", ["note", "as_of"]), /not after today/);
    for (const name of ["portfolixir.events.create", "portfolixir.events.update"]) {
      assert.match(property(name, ["event", "checked_at"]), /no later than tomorrow/, name);
    }
  });

  // E25 S6, G01: the append-only and journaled knowledge text is capped in
  // code points, and the schemas carry the cap where the agent reads them.
  it("caps the research, event and rule-version text in code points", () => {
    const find = (name: string) => listTools().find((tool) => tool.name === name);
    const at = (name: string, path: string[]) => {
      let node: any = find(name)?.inputSchema;
      for (const key of path) node = node?.properties?.[key];
      return node;
    };

    assert.equal(at("portfolixir.notes.append", ["note", "body"]).maxLength, 20000);
    assert.equal(at("portfolixir.notes.append", ["note", "invalidation_condition"]).maxLength, 10000);
    assert.equal(at("portfolixir.events.create", ["event", "note"]).maxLength, 10000);
    assert.equal(at("portfolixir.events.update", ["event", "note"]).maxLength, 10000);
    assert.equal(at("portfolixir.policy_rules.create", ["rule", "version", "note"]).maxLength, 10000);
    assert.equal(at("portfolixir.policy_rules.add_version", ["version", "note"]).maxLength, 10000);

    const append = find("portfolixir.notes.append");
    const note = (body: string) => ({
      security_id: 1,
      note: { kind: "evidence", body, source_quality: "primary", as_of: "2026-01-02" }
    });
    // The cap counts code points, as the server does: 20000 astral characters
    // are 40000 UTF-16 units and still inside it.
    assert.doesNotThrow(() => append?.zodSchema.parse(note("\u{1F4C8}".repeat(20000))));
    assert.throws(() => append?.zodSchema.parse(note("a".repeat(20001))));
  });

  // E25 S6, F20: a tax statement's source is the system's to state.
  it("offers no source on the tax statement write tools", () => {
    for (const name of ["portfolixir.tax_snapshots.create", "portfolixir.tax_snapshots.update"]) {
      const tool = listTools().find((candidate) => candidate.name === name);
      assert.equal(tool?.inputSchema.properties.source, undefined, name);
    }
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
  });

  // User story (issue #686, gaps D2/D3):
  // As an agent that just met a tax refund on a loss sale,
  // I want the create tool's direction enumeration to name the kind that
  // credits a refund, the "never send negative values" prohibition to carry
  // its remedy, and the reconcile tool's repair list to reach tax_refund,
  // so that the surface leads me to the correct booking instead of a
  // set_balance anchor.
  //
  // Acceptance criteria:
  // - The direction enumeration's credit list names tax_refund.
  // - The prohibition sentence is followed by the tax_refund remedy.
  // - holdings.reconcile's repair guidance names tax_refund explicitly.
  it("leads a tax refund to tax_refund in the direction enumeration and the reconcile repair list (#686)", () => {
    const tools = listTools();

    const transactionCreate = tools.find(
      (tool) => tool.name === "portfolixir.transactions.create"
    );
    const description = String(transactionCreate?.description);
    // The credit half of the direction enumeration names the refund kind.
    assert.match(description, /deposit\/dividend\/interest\/tax_refund credit/);
    // The prohibition carries its remedy instead of stopping at the rule.
    assert.match(description, /never send negative values:.*?tax_refund/);

    const reconcile = tools.find((tool) => tool.name === "portfolixir.holdings.reconcile");
    assert.match(String(reconcile?.description), /tax_refund/);
  });

  it("creates every ledger kind directly over the API (FR-31, request shape)", async () => {
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

  // ADR-0050 §11 (#831's lesson: agents read descriptions, not docs): the
  // three lifecycle deletes say what a referenced row answers — the counted
  // referenced_by, the remedy and its route — and that the memberships an
  // unreferenced row carries are removed journaled, never by a cascade.
  it("states the hardened delete answer on the three lifecycle delete tools", () => {
    const tools = listTools();
    const describe = (name: string) => tools.find((tool) => tool.name === name)?.description ?? "";

    const cash = describe("portfolixir.cash_accounts.delete");
    assert.match(cash, /either leg/);
    assert.match(cash, /referenced_by/);
    assert.match(cash, /remedy "merge"/);
    assert.match(cash, /GET \/api\/v1\/cash_accounts\/:id\/merge_preview\?target_id=/);
    assert.match(cash, /bucket links are removed first, journaled/);

    const depot = describe("portfolixir.securities_accounts.delete");
    assert.match(depot, /either leg/);
    assert.match(depot, /referenced_by/);
    assert.match(depot, /remedy "merge"/);
    assert.match(depot, /GET \/api\/v1\/securities_accounts\/:id\/merge_preview\?target_id=/);
    assert.match(depot, /position overrides are removed first, journaled/);

    const security = describe("portfolixir.securities.delete");
    assert.match(security, /referenced_by/);
    assert.match(security, /GET \/api\/v1\/securities\/:id\/merge_preview\?target_id=/);
    assert.match(security, /retire/);
    assert.match(security, /policy_rules/);
    assert.match(security, /category assignments, position targets, position bucket overrides/);
    assert.match(security, /no cascade/);
  });

  // ADR-0050 §11 first bullet, §16 invariant 15 (#831's lesson: agents read
  // descriptions, not docs): the two update tools that expose a currency say
  // when it freezes and what a frozen change answers, on the tool and on the
  // currency_code property itself; the depot update exposes no portfolio_id,
  // so its binding cannot be moved from here at all.
  it("states the identity-field freezes on the update tools that expose a currency", () => {
    const tools = listTools();
    const find = (name: string) => tools.find((tool) => tool.name === name);
    const currencyDescription = (name: string, wrapper: string) => {
      const schema = find(name)?.inputSchema as {
        properties: Record<string, { properties: Record<string, { description?: string }> }>;
      };
      return schema.properties[wrapper].properties.currency_code.description ?? "";
    };

    const cash = find("portfolixir.cash_accounts.update")?.description ?? "";
    assert.match(cash, /currency_code and its portfolio binding freeze/);
    assert.match(cash, /either leg/);
    assert.match(cash, /linked depot/);
    assert.match(cash, /422/);
    assert.match(
      currencyDescription("portfolixir.cash_accounts.update", "cash_account"),
      /Frozen once a transaction \(either leg\) or a linked depot references the account/
    );

    const security = find("portfolixir.securities.update")?.description ?? "";
    assert.match(security, /currency_code freezes once the security has a transaction or a quote/);
    assert.match(security, /422/);
    assert.match(
      currencyDescription("portfolixir.securities.update", "security"),
      /Frozen once the security has a transaction or a quote/
    );

    const depotSchema = find("portfolixir.securities_accounts.update")?.inputSchema as {
      properties: { securities_account: { properties: Record<string, unknown> } };
    };
    assert.equal("portfolio_id" in depotSchema.properties.securities_account.properties, false);
  });

  // ADR-0050 §3, §4 (L2, #884; #831's lesson: agents read descriptions, not
  // docs): a rename over these tools is the agent's half of the re-import
  // hazard, so the two account update tools say what the next import of the
  // same export does after a rename, and where that stops.
  it("states what a rename means for the next import on the account update tools", () => {
    const tools = listTools();
    const describe = (name: string) => tools.find((tool) => tool.name === name)?.description ?? "";

    for (const name of ["portfolixir.cash_accounts.update", "portfolixir.securities_accounts.update"]) {
      const description = describe(name);
      assert.match(description, /checks each row's content hash before it resolves an account/);
      assert.match(description, /creates an account only with its first new booking/);
      assert.match(description, /no empty account appears under the old name/);
    }
  });

  // ADR-0050 §4 (L2, #884; #831's lesson: agents read descriptions, not
  // docs): a rename keeps the previous name as a former name, the import
  // resolves a file's account name by live name, then former name, and the
  // rename tools say which case applies; the removal tools say what a
  // removal costs; create and rename name the guard's 422.
  it("states the former-name cases on the account tools", () => {
    const tools = listTools();
    const describe = (name: string) => tools.find((tool) => tool.name === name)?.description ?? "";

    for (const [kind, noun] of [
      ["cash_accounts", "cash account"],
      ["securities_accounts", "securities account"]
    ]) {
      const update = describe(`portfolixir.${kind}.update`);
      assert.match(update, /keeps the previous name as a former name of this account/);
      assert.match(update, /listed in former_names/);
      assert.match(update, /live name first, then by the former names/);
      assert.match(update, /re-export that changed inside Portfolio Performance/);
      assert.match(update, /Renaming back to a former name consumes it/);
      assert.match(
        update,
        new RegExp(`While another ${noun} in the portfolio still carries the previous name as its live name, the previous name is not kept`)
      );
      assert.match(update, /an import naming it books to that other account/);
      assert.match(update, /422/);

      assert.match(describe(`portfolixir.${kind}.create`), /live or former name.*422/);
      assert.match(describe(`portfolixir.${kind}.list`), /former_names/);

      const remove = describe(`portfolixir.${kind}.remove_former_name`);
      assert.match(remove, /journaled/);
      assert.match(remove, /An import that still names '<name>' will then create a new account\./);
    }
  });

  it("routes the former-name removal to DELETE with the name as a query parameter", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 3 } });

    await callTool(client, "portfolixir.cash_accounts.remove_former_name", {
      id: 3,
      name: "Giro & Savings"
    });
    await callTool(client, "portfolixir.securities_accounts.remove_former_name", {
      id: 4,
      name: "Depot"
    });

    assert.equal(requests[0].method, "DELETE");
    assert.equal(requests[0].path, "/api/v1/cash_accounts/3/former_names?name=Giro+%26+Savings");
    assert.equal(requests[0].body, undefined);
    assert.equal(requests[1].method, "DELETE");
    assert.equal(requests[1].path, "/api/v1/securities_accounts/4/former_names?name=Depot");
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

  // ADR-0046 (#572): the benchmark twins forward the selector and the period
  // parameters to the two benchmark reads; a malformed selector never leaves
  // the companion.
  it("issues a GET to /performance/benchmark for the two benchmark tools", async () => {
    const { client, requests } = createRecordingClient({
      data: {
        portfolio_id: 3,
        period: "ytd",
        savings_plan: { end_value_delta: "200", benchmark_end_value: "1500" }
      }
    });

    const result = await callTool(client, "portfolixir.portfolios.benchmark", {
      portfolio_id: 3,
      benchmark: "rate:0.02",
      period: "ytd",
      series: true,
      view: 5
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(
      requests[0].path,
      "/api/v1/portfolios/3/performance/benchmark?benchmark=rate%3A0.02&period=ytd&series=true&view=5"
    );
    assert.equal((result.structuredContent as any).data.savings_plan.end_value_delta, "200");

    await callTool(client, "portfolixir.views.benchmark", {
      id: 2,
      benchmark: "security:7",
      year: 2025
    });

    assert.equal(requests[1].method, "GET");
    assert.equal(requests[1].path, "/api/v1/views/2/performance/benchmark?benchmark=security%3A7&year=2025");

    await assert.rejects(
      callTool(client, "portfolixir.portfolios.benchmark", { portfolio_id: 3, benchmark: "index:7" })
    );
    assert.equal(requests.length, 2);
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

  // User story (#577): as an MCP client I want a view's cross-portfolio
  // TTWROR/IRR from one tool, so that the performance figures cover exactly
  // the accounts the view valuation covers.
  it("issues a GET to /views/:id/performance for portfolixir.views.performance", async () => {
    const { client, requests } = createRecordingClient({
      data: { view_id: 2, ttwror: "0.15", irr: "0.12" }
    });

    const result = await callTool(client, "portfolixir.views.performance", {
      id: 2,
      period: "ytd",
      series: true
    });

    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/views/2/performance?period=ytd&series=true");
    assert.equal((result.structuredContent as any).data.ttwror, "0.15");
  });

  // User story (#563): as an MCP client I want a previous year or a custom
  // from/to range as the performance period, matching the UI's period picker.
  it("forwards year and from/to period params on the performance tools", async () => {
    const { client, requests } = createRecordingClient({
      data: { portfolio_id: 1, ttwror: "0.1" }
    });

    await callTool(client, "portfolixir.portfolios.performance", {
      portfolio_id: 1,
      year: 2025
    });
    await callTool(client, "portfolixir.portfolios.performance", {
      portfolio_id: 1,
      from: "2025-01-01",
      to: "2025-12-31"
    });
    await callTool(client, "portfolixir.views.performance", {
      id: 2,
      year: 2025
    });

    assert.equal(requests[0].path, "/api/v1/portfolios/1/performance?year=2025");
    assert.equal(
      requests[1].path,
      "/api/v1/portfolios/1/performance?from=2025-01-01&to=2025-12-31"
    );
    assert.equal(requests[2].path, "/api/v1/views/2/performance?year=2025");
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

  // User story (E25 S5, G23):
  // As the operating agent, I want the ISIN-change and security-update tools
  // to state which identifiers the catalog refuses, so that a lookalike never
  // replaces the identifier the exports carry and a 422 reads as a rule.
  it("states the catalog's identifier rules on isin_change and securities.update", () => {
    const find = (name: string) => listTools().find((tool) => tool.name === name);
    const isin = find("portfolixir.securities.isin_change")?.description ?? "";
    assert.match(isin, /check digit/);
    const update = find("portfolixir.securities.update")?.description ?? "";
    assert.match(update, /check digit/);
    assert.match(update, /WKN of six letters or digits/);
    assert.match(update, /printable ASCII/);
    assert.match(update, /format characters/);
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

  // User story (2026-07-25, ADR-0031, story 19.5):
  // As the operating LLM agent,
  // I want the recorded tax snapshots and the trim budget over MCP,
  // so that I can size a trim without scraping PDFs.
  it("routes the tax configuration tools to their /tax endpoints", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.tax_parameters.list", { jurisdiction: "DE" });
    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/tax/parameters?jurisdiction=DE");

    await callTool(client, "portfolixir.tax_parameters.upsert", {
      tax_year: 2027,
      capital_gains_tax_rate: "0.25",
      solidarity_surcharge_rate: "0.055",
      saver_allowance_single: "1100.00",
      saver_allowance_joint: "2200.00"
    });
    assert.equal(requests[1].method, "PUT");
    assert.equal(requests[1].path, "/api/v1/tax/parameters");
    assert.equal(requests[1].body.parameters.jurisdiction, "DE");
    assert.equal(requests[1].body.parameters.saver_allowance_single, "1100.00");

    await callTool(client, "portfolixir.tax_profiles.create", {
      holder: "Owner",
      valid_from: "2024-01-01"
    });
    assert.equal(requests[2].method, "POST");
    assert.equal(requests[2].path, "/api/v1/tax/profiles");
    assert.deepEqual(requests[2].body, {
      profile: { holder: "Owner", valid_from: "2024-01-01" }
    });

    await callTool(client, "portfolixir.tax_profiles.update", {
      profile_id: 4,
      church_tax_liable: true,
      church_tax_rate: "0.09"
    });
    assert.equal(requests[3].method, "PATCH");
    assert.equal(requests[3].path, "/api/v1/tax/profiles/4");
    // The path id does not ride along in the body.
    assert.deepEqual(requests[3].body, {
      profile: { church_tax_liable: true, church_tax_rate: "0.09" }
    });

    await callTool(client, "portfolixir.allowance_orders.put", {
      holder: "Owner",
      institution: "Example Bank",
      tax_year: 2025,
      amount_granted: "1000.00"
    });
    assert.equal(requests[4].method, "PUT");
    assert.equal(requests[4].path, "/api/v1/tax/allowance_orders");
    assert.equal(requests[4].body.allowance_order.amount_granted, "1000.00");

    await callTool(client, "portfolixir.allowance_orders.delete", { allowance_order_id: 9 });
    assert.equal(requests[5].method, "DELETE");
    assert.equal(requests[5].path, "/api/v1/tax/allowance_orders/9");
  });

  it("routes the tax snapshot tools and exposes every money field as a string", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.tax_snapshots.list", { holder: "Owner", tax_year: 2025 });
    assert.equal(requests[0].method, "GET");
    assert.equal(requests[0].path, "/api/v1/tax/statement_snapshots?holder=Owner&tax_year=2025");

    await callTool(client, "portfolixir.tax_snapshots.create", {
      institution: "Example Bank",
      holder: "Owner",
      tax_year: 2025,
      as_of: "2025-12-31",
      loss_pot_equities: "2500.00"
    });
    assert.equal(requests[1].method, "POST");
    assert.equal(requests[1].path, "/api/v1/tax/statement_snapshots");
    assert.equal(requests[1].body.statement_snapshot.loss_pot_equities, "2500.00");

    await callTool(client, "portfolixir.tax_snapshots.update", {
      snapshot_id: 3,
      allowance_used: "400.00"
    });
    assert.equal(requests[2].method, "PATCH");
    assert.equal(requests[2].path, "/api/v1/tax/statement_snapshots/3");
    assert.deepEqual(requests[2].body, { statement_snapshot: { allowance_used: "400.00" } });

    await callTool(client, "portfolixir.tax_snapshots.trim_budget", {
      holder: "Owner",
      tax_year: 2025
    });
    assert.equal(requests[3].method, "GET");
    assert.equal(requests[3].path, "/api/v1/tax/trim_budget?holder=Owner&tax_year=2025");

    const tools = listTools();
    const create = tools.find((tool) => tool.name === "portfolixir.tax_snapshots.create");

    for (const field of [
      "taxable_income",
      "allowance_granted",
      "allowance_used",
      "loss_pot_equities",
      "loss_pot_other",
      "loss_carryforward_prior_years",
      "withholding_tax_pot",
      "withholding_tax_credited",
      "capital_gains_tax_withheld",
      "solidarity_surcharge_withheld",
      "church_tax_withheld"
    ]) {
      assert.equal(create?.inputSchema.properties[field].type, "string", field);
    }
  });

  // The agent must not try to reconstruct the pots from holdings: average cost
  // vs. mandated FIFO makes a derived pot wrong and invisibly so.
  it("tells the agent the tax pots are recorded, not derived, and why", async () => {
    const tools = listTools();
    const list = tools.find((tool) => tool.name === "portfolixir.tax_snapshots.list");

    assert.ok(list?.description.includes("RECORDED, NOT DERIVED"));
    assert.ok(list?.description.includes("FIFO"));

    const budget = tools.find((tool) => tool.name === "portfolixir.tax_snapshots.trim_budget");
    assert.ok(budget?.description.includes("as_of"));
    assert.ok(budget?.description.includes("DECISION INPUT"));
  });

  it("rejects a tax snapshot without its identity before any API request", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await assert.rejects(
      callTool(client, "portfolixir.tax_snapshots.create", { institution: "Example Bank" })
    );

    assert.equal(requests.length, 0);
  });

  // User story (ADR-0044 §7, issue #750):
  // As the operating agent starting a research run,
  // I want the security's research log, the append tool and the three
  // hygiene reads as MCP tools wrapping the JSON API 1:1,
  // so that a run starts from one call and a refuted finding is withdrawn
  // by appending — the tool set has no update and no delete, by design.
  // ADR-0047 (FR-39): the per-security derived metrics, agent-first. The tool
  // wraps the read and its description carries the two things an agent would
  // otherwise get wrong — an insufficient_data marker is not an error to
  // retry, and the payload carries no verdict of any kind (§7, identity I6).
  it("wraps the per-security derived metrics and says what they are not", async () => {
    const { client, requests } = createRecordingClient({ data: { metrics: {} } });

    await callTool(client, "portfolixir.securities.metrics", { security_id: 7 });
    await callTool(client, "portfolixir.securities.metrics", {
      security_id: 7,
      as_of: "2026-09-19"
    });

    assert.deepEqual(requests, [
      {
        method: "GET",
        path: "/api/v1/securities/7/metrics",
        body: undefined,
        token: "Bearer api-token"
      },
      {
        method: "GET",
        path: "/api/v1/securities/7/metrics?as_of=2026-09-19",
        body: undefined,
        token: "Bearer api-token"
      }
    ]);

    const metrics = listTools().find((tool) => tool.name === "portfolixir.securities.metrics");
    assert.match(metrics?.description ?? "", /own currency/);
    assert.match(metrics?.description ?? "", /insufficient_data/);
    assert.match(metrics?.description ?? "", /NOT a reason to retry/);
    assert.match(metrics?.description ?? "", /no signal, recommendation, rating, score or action/);
  });

  // #838 (ADR-0047 §6 as amended 2026-09-19): the description tells the
  // agent where the threshold is — `required`, on every metric, in both
  // states — so it does not have to read the basis prose to find it.
  it("names `required` in the per-security metrics description", () => {
    const metrics = listTools().find((tool) => tool.name === "portfolixir.securities.metrics");
    assert.match(metrics?.description ?? "", /required/);
    assert.match(metrics?.description ?? "", /window null/);
  });

  // FR-40 (ADR-0047 §3 and §9): the portfolio and view figures ride the
  // existing risk read, additively. risk_free_rate is passed through as a
  // Decimal string, and the description states the invariant (flow-adjusted
  // factors, never the value series), the conversion of the matrix, and that
  // nothing here is a verdict.
  it("passes risk_free_rate to the risk read and describes the portfolio metrics", async () => {
    const { client, requests } = createRecordingClient({ data: { metrics: {} } });

    await callTool(client, "portfolixir.portfolios.risk", {
      portfolio_id: 3,
      view: 5,
      risk_free_rate: "0.02"
    });

    assert.equal(requests[0].path, "/api/v1/portfolios/3/risk?view=5&risk_free_rate=0.02");

    const risk = listTools().find((tool) => tool.name === "portfolixir.portfolios.risk");
    const description = risk?.description ?? "";
    assert.match(description, /flow-adjusted/);
    assert.match(description, /square root of 365/);
    assert.match(description, /risk_free_rate/);
    assert.match(description, /converted to the base currency/);
    assert.match(description, /required/);
    assert.match(description, /no signal, recommendation, rating, score or action/);
    assert.equal(
      (risk?.inputSchema as any).properties.risk_free_rate.type,
      "string"
    );
  });

  // ADR-0049 (FR-43): policy rules as versioned objects. The agent reads the
  // operator's standard from the instance instead of restating it from a
  // prompt, and an edit is a new version, never an overwrite.
  it("wraps the policy-rules surface: list, show, create, add a version, retire, delete", async () => {
    const { client, requests } = createRecordingClient({ data: { rules: [] } });

    await callTool(client, "portfolixir.policy_rules.list", {
      portfolio_id: 3,
      view: 5,
      as_of: "2026-09-01",
      include_retired: true,
      since: "2026-09-01T00:00:00Z",
      limit: 20
    });
    await callTool(client, "portfolixir.policy_rules.get", { id: 9 });
    await callTool(client, "portfolixir.policy_rules.create", {
      portfolio_id: 3,
      rule: {
        name: "Single name at most 10 %",
        version: {
          subject_type: "security",
          security_id: 7,
          measure: "weight",
          kind: "cap",
          threshold: "10",
          severity: "hard"
        }
      }
    });
    await callTool(client, "portfolixir.policy_rules.add_version", {
      id: 9,
      version: {
        subject_type: "basis",
        measure: "volatility",
        window: "90d",
        kind: "cap",
        threshold: "15",
        severity: "warn",
        valid_from: "2026-10-01"
      }
    });
    await callTool(client, "portfolixir.policy_rules.retire", { id: 9 });
    await callTool(client, "portfolixir.policy_rules.delete", { id: 9 });

    assert.deepEqual(
      requests.map((request) => `${request.method} ${request.path}`),
      [
        "GET /api/v1/portfolios/3/policy_rules?view=5&as_of=2026-09-01&include_retired=true&since=2026-09-01T00%3A00%3A00Z&limit=20",
        "GET /api/v1/policy_rules/9",
        "POST /api/v1/portfolios/3/policy_rules",
        "POST /api/v1/policy_rules/9/versions",
        "POST /api/v1/policy_rules/9/retire",
        "DELETE /api/v1/policy_rules/9"
      ]
    );

    const create = listTools().find((tool) => tool.name === "portfolixir.policy_rules.create");
    const version = (create?.inputSchema as any).properties.rule.properties.version;
    assert.equal(version.properties.threshold.type, "string");
    assert.equal(version.properties.lower.type, "string");
    assert.equal(version.properties.upper.type, "string");
    assert.deepEqual(version.properties.measure.enum, [
      "weight",
      "drift",
      "hhi",
      "volatility",
      "max_drawdown"
    ]);

    const addVersion = listTools().find(
      (tool) => tool.name === "portfolixir.policy_rules.add_version"
    );
    assert.match(addVersion?.description ?? "", /new version/);
    assert.match(addVersion?.description ?? "", /never changed or deleted/);

    // The validator agrees with the schema: a create without its version's
    // required fields fails before the round trip, and a decimal passed as a
    // number is refused rather than silently floated.
    await assert.rejects(
      callTool(client, "portfolixir.policy_rules.create", {
        portfolio_id: 3,
        rule: { name: "x", version: {} }
      })
    );
    await assert.rejects(
      callTool(client, "portfolixir.policy_rules.add_version", {
        id: 9,
        version: { subject_type: "basis", measure: "hhi", kind: "cap", threshold: 2500, severity: "warn" }
      })
    );
    assert.equal(requests.length, 6);

    const retire = listTools().find((tool) => tool.name === "portfolixir.policy_rules.retire");
    assert.match(retire?.description ?? "", /stay readable/);

    // ADR-0049 §8 and #831's lesson: the re-import guarantee lives where the
    // agent reads — in the descriptions of the reads it protects.
    for (const name of [
      "portfolixir.policy_rules.list",
      "portfolixir.policy_rules.get",
      "portfolixir.portfolios.policy_findings"
    ]) {
      const description = listTools().find((tool) => tool.name === name)?.description ?? "";
      assert.match(description, /re-import does not destroy the policy rules/, name);
    }
  });

  // #872 (ADR-0049 §4 and §8 as amended by the Sprint 16 plan D-6): the name
  // is the operator's label, so a rename is a rule-level edit outside the
  // versioning, and the description says so where the agent reads it.
  it("wraps the rename of a policy rule: the name only, no version", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 9 } });

    await callTool(client, "portfolixir.policy_rules.rename", {
      id: 9,
      name: "Cash at least 2 %"
    });

    assert.equal(requests.length, 1);
    assert.equal(requests[0].method, "PATCH");
    assert.equal(requests[0].path, "/api/v1/policy_rules/9");
    assert.deepEqual(requests[0].body, { name: "Cash at least 2 %" });

    const rename = listTools().find((tool) => tool.name === "portfolixir.policy_rules.rename");
    const description = rename?.description ?? "";
    assert.match(description, /creates NO version/);
    assert.match(description, /versions do not change/);
    assert.match(description, /journal/i);
    assert.match(description, /retired/);
    assert.match(description, /portfolixir\.policy_rules\.add_version/);
    assert.deepEqual((rename?.inputSchema as any).required, ["id", "name"]);
    assert.equal((rename?.inputSchema as any).additionalProperties, false);
    assert.equal((rename?.inputSchema as any).properties.name.maxLength, 255);

    // The validator agrees with the schema: an empty name and a predicate
    // field are refused before the round trip.
    await assert.rejects(callTool(client, "portfolixir.policy_rules.rename", { id: 9, name: "" }));
    await assert.rejects(
      callTool(client, "portfolixir.policy_rules.rename", { id: 9, name: "x", threshold: "12" })
    );
    assert.equal(requests.length, 1);
  });

  // ADR-0049 §5: the findings read — did anything cross a line? — as one
  // call, with status=breached as the pull-only alarm list.
  it("wraps the findings read: status narrows, view scopes, no action", async () => {
    const { client, requests } = createRecordingClient({ data: { findings: [] } });

    await callTool(client, "portfolixir.portfolios.policy_findings", { portfolio_id: 3 });
    await callTool(client, "portfolixir.portfolios.policy_findings", {
      portfolio_id: 3,
      view: 5,
      status: "breached,undetermined"
    });

    assert.deepEqual(
      requests.map((request) => `${request.method} ${request.path}`),
      [
        "GET /api/v1/portfolios/3/policy_findings",
        "GET /api/v1/portfolios/3/policy_findings?view=5&status=breached%2Cundetermined"
      ]
    );

    const findings = listTools().find(
      (tool) => tool.name === "portfolixir.portfolios.policy_findings"
    );
    const description = findings?.description ?? "";
    assert.match(description, /undetermined/);
    assert.match(description, /NEVER a pass/);
    assert.match(description, /PULL ONLY/);
    assert.match(description, /no action/);
    assert.deepEqual(
      Object.keys((findings?.inputSchema as any).properties).sort(),
      ["portfolio_id", "status", "view"]
    );
  });

  // ADR-0048 (FR-44): security events, agent-first. The whole point of the
  // object is the DEFAULT SCOPE — the catalog, not the holdings — so the
  // upcoming tool's description has to say so where the agent reads it.
  it("wraps the security-events surface and defaults to the whole catalog", async () => {
    const { client, requests } = createRecordingClient({ data: { events: [] } });

    await callTool(client, "portfolixir.events.list", { security_id: 7 });
    await callTool(client, "portfolixir.events.create", {
      security_id: 7,
      event: {
        kind: "earnings",
        date: "2026-11-04",
        timing: "exact",
        source_quality: "primary"
      }
    });
    await callTool(client, "portfolixir.events.update", {
      id: 3,
      event: { confirmed: true, checked_at: "2026-09-19" }
    });
    await callTool(client, "portfolixir.events.delete", { id: 3 });
    await callTool(client, "portfolixir.events.upcoming", { days: 14 });
    await callTool(client, "portfolixir.events.unconfirmed", {});
    await callTool(client, "portfolixir.events.stale", { days: 90 });

    assert.deepEqual(
      requests.map((request) => `${request.method} ${request.path}`),
      [
        "GET /api/v1/securities/7/events",
        "POST /api/v1/securities/7/events",
        "PATCH /api/v1/security_events/3",
        "DELETE /api/v1/security_events/3",
        "GET /api/v1/events/upcoming?days=14",
        "GET /api/v1/events/unconfirmed",
        "GET /api/v1/events/stale?days=90"
      ]
    );

    const upcoming = listTools().find((tool) => tool.name === "portfolixir.events.upcoming");
    assert.match(upcoming?.description ?? "", /WHOLE CATALOG/);
    assert.match(upcoming?.description ?? "", /NEVER the default/);
    assert.match(upcoming?.description ?? "", /ANY day it could fall on/);
    assert.match(upcoming?.description ?? "", /PULL ONLY/);

    // The two queues are deliberately different questions, and the
    // descriptions have to keep them apart.
    const stale = listTools().find((tool) => tool.name === "portfolixir.events.stale");
    assert.match(stale?.description ?? "", /different read/);

    // Every parameter a tool advertises has to be one its route reads.
    // GET /api/v1/events/unconfirmed takes no horizon — every unconfirmed
    // past date belongs in the queue — so the schema must not offer `days`,
    // which would otherwise be accepted, dropped, and never echoed.
    const unconfirmed = listTools().find(
      (tool) => tool.name === "portfolixir.events.unconfirmed"
    );
    const unconfirmedProps = Object.keys(
      (unconfirmed?.inputSchema as { properties?: Record<string, unknown> })?.properties ?? {}
    );
    assert.deepEqual(unconfirmedProps.sort(), ["held_only", "kind", "limit", "security_id"]);

    const staleProps = Object.keys(
      (stale?.inputSchema as { properties?: Record<string, unknown> })?.properties ?? {}
    );
    assert.ok(staleProps.includes("days"));

    const create = listTools().find((tool) => tool.name === "portfolixir.events.create");
    assert.match(create?.description ?? "", /HOW WELL YOU KNOW THE DATE/);

    // The validator has to agree with the schema it advertises: a create
    // without the four required fields fails here, not after a round trip
    // to the API. An update body stays partial by definition.
    assert.equal(requests.length, 7);
    await assert.rejects(
      callTool(client, "portfolixir.events.create", { security_id: 7, event: {} })
    );
    await callTool(client, "portfolixir.events.update", { id: 3, event: { note: "partial" } });
    assert.equal(requests.length, 8);

    // An event is never converted into a transaction, and the tool set says
    // so rather than leaving an agent to invent the reconciliation.
    const list = listTools().find((tool) => tool.name === "portfolixir.events.list");
    assert.match(list?.description ?? "", /never converted into a transaction/);
  });

  it("wraps the research log: list, append and the three hygiene reads", async () => {
    const { client, requests } = createRecordingClient({ data: { entries: [] } });

    await callTool(client, "portfolixir.notes.list", { security_id: 7 });
    await callTool(client, "portfolixir.notes.append", {
      security_id: 7,
      note: {
        kind: "retraction",
        body: "checked the 10-Q; withdrawn",
        source_quality: "primary",
        as_of: "2026-08-02",
        supersedes_id: 41
      }
    });
    await callTool(client, "portfolixir.notes.unreviewed", { days: 90 });
    await callTool(client, "portfolixir.notes.uncorroborated", {
      security_id: 7,
      include_superseded: true
    });
    await callTool(client, "portfolixir.notes.expiring", { days: 7 });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path]),
      [
        ["GET", "/api/v1/securities/7/notes"],
        ["POST", "/api/v1/securities/7/notes"],
        ["GET", "/api/v1/notes/unreviewed?days=90"],
        ["GET", "/api/v1/notes/uncorroborated?security_id=7&include_superseded=true"],
        ["GET", "/api/v1/notes/expiring?days=7"]
      ]
    );

    assert.deepEqual(requests[1].body, {
      note: {
        kind: "retraction",
        body: "checked the 10-Q; withdrawn",
        source_quality: "primary",
        as_of: "2026-08-02",
        supersedes_id: 41
      }
    });

    const names = listTools().map((tool) => tool.name);
    assert.ok(!names.includes("portfolixir.notes.update"));
    assert.ok(!names.includes("portfolixir.notes.delete"));

    // The descriptions carry the contract: entries never vanish, retraction
    // is the withdrawal, source quality is set rather than guessed.
    const list = listTools().find((tool) => tool.name === "portfolixir.notes.list");
    assert.match(list?.description ?? "", /NEVER vanish/);
    assert.match(list?.description ?? "", /retraction/);
    assert.match(list?.description ?? "", /thesis_state/);

    const append = listTools().find((tool) => tool.name === "portfolixir.notes.append");
    assert.match(append?.description ?? "", /SET, not guessed/);
    assert.deepEqual(append?.inputSchema.properties.note.properties.kind.enum, [
      "thesis",
      "evidence",
      "invalidation_check",
      "event_result",
      "risk",
      "retraction",
      "decision"
    ]);
    assert.deepEqual(append?.inputSchema.properties.note.properties.source_quality.enum, [
      "primary",
      "secondary_multi",
      "awareness",
      "unverified"
    ]);
  });

  it("rejects a research-log entry outside the closed sets before any API request", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await assert.rejects(
      callTool(client, "portfolixir.notes.append", {
        security_id: 7,
        note: { kind: "hunch", body: "x", source_quality: "vibes", as_of: "2026-08-01" }
      })
    );

    assert.equal(requests.length, 0);
  });

  // #749: the security detail carries the derived thesis state, and the
  // sparse-fieldset whitelist can select it.
  it("exposes thesis_state on securities.get and in the fields whitelist", () => {
    const get = listTools().find((tool) => tool.name === "portfolixir.securities.get");
    assert.match(get?.description ?? "", /thesis_state/);

    const list = listTools().find((tool) => tool.name === "portfolixir.securities.list");
    assert.ok(list?.inputSchema.properties.fields.items.enum.includes("thesis_state"));
  });

  // User story (issue #740): FR-37's read-ergonomics parameters on the two
  // reads that skipped them — the view-scoped valuation and the
  // position-target listing — with the spelling the shipped tools use.
  it("passes include_positions to views.valuation and min_drift to targets.list_positions", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.views.valuation", { id: 2, include_positions: false });
    await callTool(client, "portfolixir.views.valuation", { id: 2 });
    await callTool(client, "portfolixir.targets.list_positions", {
      portfolio_id: 3,
      min_drift: "0.02"
    });

    assert.deepEqual(
      requests.map((request) => request.path),
      [
        "/api/v1/views/2/valuation?include_positions=false",
        "/api/v1/views/2/valuation",
        "/api/v1/portfolios/3/position_targets?min_drift=0.02"
      ]
    );

    const positions = listTools().find((tool) => tool.name === "portfolixir.targets.list_positions");
    assert.equal(positions?.inputSchema.properties.min_drift.type, "string");
    assert.match(positions?.description ?? "", /min_drift/);

    const viewValuation = listTools().find((tool) => tool.name === "portfolixir.views.valuation");
    assert.equal(viewValuation?.inputSchema.properties.include_positions.type, "boolean");
    assert.match(viewValuation?.description ?? "", /positions_included/);
  });

  // User story (issue #737): the one-shot historical backfill rides the
  // existing sync tool as scope=history; the default stays the daily feed.
  it("passes scope=history to exchange_rates.sync and keeps the empty body by default", async () => {
    const { client, requests } = createRecordingClient({ data: { scope: "history" } });

    await callTool(client, "portfolixir.exchange_rates.sync", { scope: "history" });
    await callTool(client, "portfolixir.exchange_rates.sync", {});

    assert.deepEqual(requests[0].method, "POST");
    assert.deepEqual(requests[0].path, "/api/v1/exchange_rates/sync");
    assert.deepEqual(requests[0].body, { scope: "history" });
    assert.deepEqual(requests[1].body, {});

    const sync = listTools().find((tool) => tool.name === "portfolixir.exchange_rates.sync");
    assert.deepEqual(sync?.inputSchema.properties.scope.enum, ["latest", "history"]);
    assert.match(sync?.description ?? "", /BACKFILL/);
    assert.match(sync?.description ?? "", /stays excluded/);

    await assert.rejects(
      callTool(client, "portfolixir.exchange_rates.sync", { scope: "everything" })
    );
  });

  // User story (ADR-0044 §8, issue #752): the contract-version read as a tool,
  // so an agent that cached the tool list can notice the surface moved.
  it("issues a GET to /contract for portfolixir.contract.get, with since=", async () => {
    const { client, requests } = createRecordingClient({
      data: { version: 2, last_changed_at: "2026-09-03", changed: true, entries: [] }
    });

    const result = await callTool(client, "portfolixir.contract.get", {});
    await callTool(client, "portfolixir.contract.get", { since: "2026-09-01" });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path]),
      [
        ["GET", "/api/v1/contract"],
        ["GET", "/api/v1/contract?since=2026-09-01"]
      ]
    );
    assert.equal((result.structuredContent as any).data.version, 2);

    const contract = listTools().find((tool) => tool.name === "portfolixir.contract.get");
    assert.match(contract?.description ?? "", /last_changed_at/);
    assert.match(contract?.description ?? "", /re-read the tool list/);
  });

  // Issue #771: the bounded list reads take limit on both halves, spelled once.
  it("passes limit through on the bounded list reads", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.exchange_rates.list", { limit: 5 });
    await callTool(client, "portfolixir.quotes.list", { security_id: 3, limit: 7 });
    await callTool(client, "portfolixir.transactions.list", { limit: 9 });

    assert.deepEqual(
      requests.map((request) => request.path),
      [
        "/api/v1/exchange_rates?limit=5",
        "/api/v1/securities/3/quotes?limit=7",
        "/api/v1/transactions?limit=9"
      ]
    );

    await assert.rejects(callTool(client, "portfolixir.securities.list", { limit: 0 }));
  });

  // ADR-0046 §1/§4: the benchmark flag rides the securities read as a filter
  // and the writes as a field.
  it("forwards is_benchmark on the securities read and the writes", async () => {
    const { client, requests } = createRecordingClient({ data: [] });

    await callTool(client, "portfolixir.securities.list", { is_benchmark: true });
    await callTool(client, "portfolixir.securities.list", { is_benchmark: false, limit: 5 });
    await callTool(client, "portfolixir.securities.create", {
      security: { name: "World Index ETF", currency_code: "EUR", is_benchmark: true }
    });
    await callTool(client, "portfolixir.securities.update", {
      id: 7,
      security: { is_benchmark: false }
    });

    assert.deepEqual(
      requests.map((request) => request.path),
      [
        "/api/v1/securities?is_benchmark=true",
        "/api/v1/securities?is_benchmark=false&limit=5",
        "/api/v1/securities",
        "/api/v1/securities/7"
      ]
    );
    assert.deepEqual(requests[2].body, {
      security: { name: "World Index ETF", currency_code: "EUR", is_benchmark: true }
    });
    assert.deepEqual(requests[3].body, { security: { is_benchmark: false } });

    await assert.rejects(callTool(client, "portfolixir.securities.list", { is_benchmark: "yes" }));
  });

  // Issue #776: the limit surface finished — the four research-log reads, the
  // snapshot list and the three cash-flow roll-ups take limit on both halves;
  // the trades read keeps from/to as its bound and carries no limit.
  it("passes limit through on the eight further bounded reads and not on trades", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await callTool(client, "portfolixir.notes.list", { security_id: 7, limit: 3 });
    await callTool(client, "portfolixir.notes.unreviewed", { days: 90, limit: 4 });
    await callTool(client, "portfolixir.notes.uncorroborated", { limit: 6 });
    await callTool(client, "portfolixir.notes.expiring", { limit: 8 });
    await callTool(client, "portfolixir.snapshots.list", { limit: 2 });
    await callTool(client, "portfolixir.cashflow.realized_gains", { limit: 1 });
    await callTool(client, "portfolixir.cashflow.external_flows", { limit: 1 });
    await callTool(client, "portfolixir.cashflow.costs", { limit: 1 });
    await callTool(client, "portfolixir.trades.list", { security_id: 42 });

    assert.deepEqual(
      requests.map((request) => request.path),
      [
        "/api/v1/securities/7/notes?limit=3",
        "/api/v1/notes/unreviewed?days=90&limit=4",
        "/api/v1/notes/uncorroborated?limit=6",
        "/api/v1/notes/expiring?limit=8",
        "/api/v1/snapshots?limit=2",
        "/api/v1/realized_gains?limit=1",
        "/api/v1/external_flows?limit=1",
        "/api/v1/costs?limit=1",
        "/api/v1/securities/42/trades"
      ]
    );

    await assert.rejects(callTool(client, "portfolixir.notes.list", { security_id: 7, limit: 0 }));
    await assert.rejects(callTool(client, "portfolixir.cashflow.costs", { limit: -1 }));

    const trades = listTools().find((tool) => tool.name === "portfolixir.trades.list");
    assert.match(trades?.description ?? "", /no limit/i);
    assert.equal("limit" in (trades?.inputSchema as { properties: object }).properties, false);
  });

  // Issue #766: the research-log append no longer accepts provenance claims.
  it("rejects author and machine_generated on notes.append", () => {
    const append = listTools().find((tool) => tool.name === "portfolixir.notes.append");
    const noteProperties = append?.inputSchema.properties.note.properties ?? {};

    assert.ok(!("author" in noteProperties));
    assert.ok(!("machine_generated" in noteProperties));
  });

  // E25 S4, F70 (#889): every date a write stores is an ISO date inside one
  // bounded range; each write tool's date fields say so where the agent reads
  // the schema.
  it("states the bounded date range on every date a write tool stores", () => {
    const dateKeys = new Set([
      "date",
      "date_end",
      "checked_at",
      "as_of",
      "valid_from",
      "valid_until",
      "time_stop",
      "changed_on"
    ]);
    const writeTools = [
      "portfolixir.securities.isin_change",
      "portfolixir.events.create",
      "portfolixir.events.update",
      "portfolixir.notes.append",
      "portfolixir.quotes.upsert",
      "portfolixir.transactions.create",
      "portfolixir.transactions.update",
      "portfolixir.splits.preview",
      "portfolixir.splits.create",
      "portfolixir.policy_rules.create",
      "portfolixir.policy_rules.add_version",
      "portfolixir.policy_rules.retire",
      "portfolixir.cash_accounts.set_balance",
      "portfolixir.snapshots.create",
      "portfolixir.tax_profiles.create",
      "portfolixir.tax_profiles.update",
      "portfolixir.tax_snapshots.create"
    ];

    const found: string[] = [];

    const walk = (toolName: string, schema: unknown, path: string) => {
      if (!schema || typeof schema !== "object") return;
      const node = schema as { properties?: Record<string, unknown>; items?: unknown };

      for (const [key, child] of Object.entries(node.properties ?? {})) {
        if (dateKeys.has(key)) {
          const description = (child as { description?: string }).description ?? "";
          found.push(`${toolName} ${path}${key}`);
          assert.match(description, /1900-01-01/, `${toolName} ${path}${key}`);
          assert.match(description, /2999-12-31/, `${toolName} ${path}${key}`);
        }

        walk(toolName, child, `${path}${key}.`);
      }

      walk(toolName, node.items, `${path}[].`);
    };

    for (const name of writeTools) {
      const definition = listTools().find((candidate) => candidate.name === name);
      assert.ok(definition, name);
      walk(name, definition?.inputSchema, "");
    }

    assert.ok(found.includes("portfolixir.transactions.create transaction.date"));
    assert.ok(found.includes("portfolixir.policy_rules.create rule.version.valid_from"));
    assert.ok(found.includes("portfolixir.snapshots.create as_of"));
  });

  // E25 S4, G11 (#889): a target batch is bounded, and the schema says so
  // with the API's fixed maximum.
  it("caps the target batch at the API's maximum", async () => {
    const setTool = listTools().find((tool) => tool.name === "portfolixir.targets.set");
    assert.equal(setTool?.inputSchema.properties.targets.maxItems, 10000);
    assert.match(setTool?.description ?? "", /once per batch/);

    const { client } = createRecordingClient();
    const row = { category_id: 1, target_weight: "0.1" };

    await assert.rejects(
      callTool(client, "portfolixir.targets.set", {
        portfolio_id: 1,
        classification_id: 1,
        targets: Array.from({ length: 10001 }, () => row)
      })
    );
  });

  // E25 S4, G14 (#889): the weight scale and the zero-value gap are stated
  // where the agent reads the tools.
  it("states the weight scale and the zero-value drift gap", () => {
    const describe = (name: string) =>
      listTools().find((tool) => tool.name === name)?.description ?? "";

    assert.match(describe("portfolixir.targets.set"), /at most 6 decimal places/);
    assert.match(describe("portfolixir.portfolios.allocation"), /valued at 0/);
    assert.match(describe("portfolixir.portfolios.allocation"), /computation_basis/);
  });

  // E25 S4, G16 and G17 (#889): a ledger amount is rounded to the column's
  // scale before it is checked, and one past the column's precision is a 422.
  it("states the ledger's amount scale and bound on the booking tools", () => {
    for (const name of [
      "portfolixir.transactions.create",
      "portfolixir.transactions.update",
      "portfolixir.cash_accounts.set_balance"
    ]) {
      const description = listTools().find((tool) => tool.name === name)?.description ?? "";
      assert.match(description, /rounded half up to 6 decimal places/, name);
      assert.match(description, /14 digits before the decimal point/, name);
    }
  });

  // E25 S4, G16 and G17, with S3 F26 (the S3/S4 review round): the same column
  // rule reaches the quote and tax writers, and the tools say so.
  it("states the stored scale and bound on the quote and tax write tools", () => {
    for (const name of [
      "portfolixir.quotes.upsert",
      "portfolixir.tax_parameters.upsert",
      "portfolixir.tax_profiles.create",
      "portfolixir.tax_profiles.update",
      "portfolixir.allowance_orders.put",
      "portfolixir.tax_snapshots.create",
      "portfolixir.tax_snapshots.update"
    ]) {
      const description = listTools().find((tool) => tool.name === name)?.description ?? "";
      assert.match(description, /rounded half up to/, name);
      assert.match(description, /14 digits before the decimal point/, name);
    }
  });

  // E25 S4, F70 and G24 (the S3/S4 review round): a read's date and text
  // filters meet the writers' rules, and the read tools say so.
  it("states the bounded date and the text rule on the read tools' filters", () => {
    const property = (name: string, key: string) => {
      const schema = listTools().find((tool) => tool.name === name)?.inputSchema as
        | { properties?: Record<string, { description?: string }> }
        | undefined;
      return schema?.properties?.[key]?.description ?? "";
    };

    for (const [name, key] of [
      ["portfolixir.transactions.list", "from"],
      ["portfolixir.transactions.list", "to"],
      ["portfolixir.quotes.list", "from"],
      ["portfolixir.quotes.list", "to"],
      ["portfolixir.trades.list", "from"],
      ["portfolixir.securities.metrics", "as_of"],
      ["portfolixir.policy_rules.list", "as_of"]
    ]) {
      assert.match(property(name, key), /1900-01-01/, `${name} ${key}`);
    }

    for (const [name, key] of [
      ["portfolixir.securities.list", "query"],
      ["portfolixir.journal.list", "resource_type"],
      ["portfolixir.tax_profiles.list", "holder"],
      ["portfolixir.allowance_orders.list", "institution"],
      ["portfolixir.tax_snapshots.list", "holder"]
    ]) {
      assert.match(property(name, key), /at most 255 characters/, `${name} ${key}`);
    }
  });

  // E25 S4, G24 (the S3/S4 review round): a security's free-form attributes
  // meet the text rule at any depth, and the security tools say so.
  it("states the attributes text rule on the security write tools", () => {
    for (const name of ["portfolixir.securities.create", "portfolixir.securities.update"]) {
      const description = listTools().find((tool) => tool.name === name)?.description ?? "";
      assert.match(description, /Every key of attributes, at any depth/, name);
    }
  });

  // E25 S4, F11 (#889): a parent that loops the tree or sits in another
  // classification is refused; the category tools say so.
  it("states the parent rule on the category write tools", () => {
    for (const name of [
      "portfolixir.classifications.categories.create",
      "portfolixir.classifications.categories.update"
    ]) {
      const description = listTools().find((tool) => tool.name === name)?.description ?? "";
      assert.match(description, /same classification/, name);
    }

    const update =
      listTools().find((tool) => tool.name === "portfolixir.classifications.categories.update")
        ?.description ?? "";
    assert.match(update, /nor one of its descendants/);
  });

  // E25 S4, F72 (#889): the risk read's top_n has a maximum, and the
  // correlation matrix covers a bounded number of leading names.
  it("bounds the risk read's top_n and states the correlation bound", async () => {
    const risk = listTools().find((tool) => tool.name === "portfolixir.portfolios.risk");
    assert.equal(risk?.inputSchema.properties.top_n.maximum, 1000);
    assert.match(risk?.description ?? "", /capped at 1000/);
    assert.match(risk?.description ?? "", /at most the 20 leading names/);
    assert.match(risk?.description ?? "", /leading_names/);

    const { client } = createRecordingClient();
    await assert.rejects(
      callTool(client, "portfolixir.portfolios.risk", { portfolio_id: 1, top_n: 1001 })
    );
  });

  // E25 S4, G12 (#889): a security's splits, each by its own magnitude,
  // multiply to at most 10^12; the split tools say so.
  it("states the cumulative split bound on the split tools", () => {
    for (const name of ["portfolixir.splits.preview", "portfolixir.splits.create"]) {
      const description = listTools().find((tool) => tool.name === name)?.description ?? "";
      assert.match(description, /10\^12/, name);
    }
  });
});
