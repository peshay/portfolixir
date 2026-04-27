# Portfolixir

Portfolixir is a self-hosted portfolio analytics and wealth graph platform.

It is designed to import and model portfolio data, keep a canonical transaction history, calculate positions and portfolio value, and expose the data through a web UI, REST API, and later MCP for AI-assisted analysis.

## Initial product focus

The first functional milestone is intentionally small:

1. Manage portfolio categories/taxonomies with rich descriptions.
2. Create securities with symbol, currency, optional exchange and optional ISIN.
3. Record buy transactions.
4. Calculate positions from the buy history.
5. Resolve market-data candidates by symbol, for example `AAPL` -> `AAPL`, `AAPL.F`, `AAPL.SG`.
6. Fetch/store simple quotes by symbol.
7. Calculate portfolio value in the portfolio base currency.

## Chosen stack

- **Backend:** Elixir + Phoenix
- **UI:** Phoenix LiveView
- **Database:** PostgreSQL
- **Jobs:** Oban
- **Market data:** Provider behaviour first, concrete providers later
- **Charts:** Apache ECharts via LiveView hooks
- **Styling:** Tailwind CSS + daisyUI
- **Testing:** ExUnit, Phoenix.ConnTest, LiveViewTest, Mox, StreamData, ExCoveralls
- **Quality:** Credo, Dialyxir, Sobelow, mix_audit
- **Container:** Docker multi-arch, `linux/amd64` and `linux/arm64`

## Why PostgreSQL first

The core data is relational and ledger-like: portfolios, currencies, securities, categories, transactions, prices, FX rates, imports and audit logs. PostgreSQL should be the canonical database. TimescaleDB may be added later for heavy time-series workloads, but should not be required for the MVP.

## Development style

Portfolixir is developed story-by-story using TDD:

```text
User Story -> Acceptance Criteria -> Failing Test -> Minimal Code -> Green Tests -> Refactor
```

Agents must read `AGENTS.md` before making changes.

## Non-goals for the first milestone

Do not implement these yet:

- Portfolio Performance XML import beyond raw import storage
- Full TTWROR/IRR calculations
- LLM/MCP tools
- Bitcoin wallet integrations
- InfluxDB/TimescaleDB
- Broker PDF parsing
- Real-money bank or broker actions
- External market-data calls inside tests

## Support Portfolixir

Portfolixir is an independent open-source project.

If you find it useful, you can support development and maintenance with a
voluntary payment via bunq.me:

[Support Portfolixir via bunq.me](https://bunq.me/ahuservices?description=portfolixir)

Support payments are voluntary contributions. They do not create any entitlement
to support, features, consulting, commercial services, invoices, or a charitable
donation receipt.

## Suggested first Codex Spark run

Use:

```text
prompts/spark-first-batch.md
```

This asks Spark to bootstrap the app and implement only the first small stories. It should not build the entire product.
