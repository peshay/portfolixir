# Portfolixir

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="priv/static/images/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="priv/static/images/logo-light.svg">
    <img alt="Portfolixir logo" src="priv/static/images/logo-wordmark.svg" width="420">
  </picture>
</p>

[![CI](https://github.com/peshay/portfolixir/actions/workflows/ci.yml/badge.svg)](https://github.com/peshay/portfolixir/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/peshay/portfolixir/branch/main/graph/badge.svg)](https://codecov.io/gh/peshay/portfolixir)
[![Elixir](https://img.shields.io/badge/Elixir-Phoenix-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![License](https://img.shields.io/github/license/peshay/portfolixir)](LICENSE)
[![BMad Method](https://img.shields.io/badge/BMad_Method-6.11.0-7c3aed)](https://bmad-method.org)

[![Support via bunq](https://img.shields.io/badge/Support-bunq-00A1E0?style=flat-square&logo=bunq&logoColor=white)](https://bunq.me/ahuservices?description=portfolixir-maintenance-support)

## What is Portfolixir

Portfolixir is a self-hosted Elixir/Phoenix portfolio system with two
first-class users: the person who owns the portfolio, and the LLM agent they
run. Everything it knows is reachable through a local JSON API and an MCP
companion, and everything it knows is also visible on a screen. One dataset,
one instance, one operator — your holdings, your agent, your machine. No cloud,
no tenancy, no broker.

It exists because portfolio facts that live *next to* a system rot. Target
weights kept in three places, a note keyed to a taxonomy that died a month ago,
a date that exists only in the text of a scheduled prompt — a stale fact and a
current one look identical there, and only a contradiction downstream reveals
which was which. Giving every such fact a home with an identity, a source and
an age is the goal the project is built toward; the records, classifications
and targets below are the part of it that exists today.

Concretely, it is the place to answer questions like these:

- *Which categories drifted away from their targets, and what would it take to
  correct them?* — the target/actual breakdown with per-category drift and an
  indicative corrective quantity, computed once on the server instead of
  reassembled by hand.
- *How did this position actually do, and what did it cost?* — moving-average
  cost basis, unrealized P&L, and a price chart from local quote history.
- *What did my agent base that on?* — the same figures the agent read over the
  API and MCP, on a page a person can look at, rather than a second pipeline
  that could disagree.

The project focuses on transparent portfolio records and read-only inspection.
It is not a broker, bank, trading, payment, order, or rebalance platform, and
it never calls an LLM itself: agents call Portfolixir, not the other way round.
Supported functions are also available through a local JSON API and an MCP
companion that wraps that API.

**Before you run it anywhere but a trusted network:** the web UI is
unauthenticated by design — an instance must sit behind reverse-proxy
authentication or on a network you control. There is no release, versioning or
upgrade guarantee yet, and no claim of production readiness. See
[home deployment](docs/home-deployment.md) for what that means in practice.

## See it in action

A quick tour of the portfolio view — switching the accent colour (violet, teal,
coral), flipping to dark mode, and a custom strategy classification showing the
target-vs-actual allocation with per-category drift for rebalancing:

![Portfolixir tour: accent colours, dark mode, and target-vs-actual rebalancing](docs/screenshots/tour.gif)

| Portfolio & allocation | Securities |
| --- | --- |
| ![Portfolio valuation and allocation](docs/screenshots/portfolio.png) | ![Securities list](docs/screenshots/securities.png) |

_All screenshots use the synthetic demo dataset in
[`priv/demo/`](priv/demo/) — no real financial data._

## What works today

- Create securities, one portfolio, and linked cash/depot accounts.
- Group depots, accounts and positions with buckets and read every figure
  under a bucket view — the household or strategy scope of your choice.
- Record manual buy and sell transactions, plus the other Portfolio
  Performance transaction kinds (dividends, interest, deposits, removals,
  fees, taxes, transfers, deliveries) and stock splits as ledger events.
- Review derived holdings, cash balances, and stored quote history.
- See each holding's moving-average cost basis and unrealized P&L, split into
  the price effect and the currency effect.
- Read the holdings performance summary — true time-weighted return, IRR,
  invested capital and wealth multiple — per portfolio and per bucket view,
  with the computation basis stated next to the figure.
- Organise securities into classification trees (custom, plus built-in
  asset-class and currency trees); the asset-class tree is an editable taxonomy
  seeded from an inferred default and corrected by dragging.
- Set per-category and per-position target weights in versioned plans, and
  read a target/actual allocation breakdown with per-category drift and
  display-only rebalancing hints.
- Freeze a snapshot of the current holdings and later compare against it:
  would keeping exactly those holdings have done better?
- Record the tax block of a broker statement (loss pots, allowance) and read
  the tax-free trim budget off it — recorded, never derived.
- Keep a research log per security: dated, sourced entries that are never
  edited or removed, with the current thesis state derived from them and a
  retraction as the way to be wrong on the record.
- Value multi-currency portfolios by converting through stored exchange rates,
  including a one-shot backfill of the historical ECB series for past booking
  dates.
- Import a Portfolio Performance CSV or JSON export: drag in the file, preview
  the records, then apply them atomically; re-applying the same export is a
  no-op that preserves everything maintained in the app.
- Open a security detail chart from local quote history.
- Read the Cash-flow area's four facets — income (dividends and interest),
  realized gains from closed sales, deposits and withdrawals, and costs (fees
  and taxes) — each stating on the page what it counts, what it excludes, and
  the exchange-rate basis behind every converted figure.
- Ask "what changed since I last looked?": the transactions and securities
  lists take a `?since=` cut with one-tap windows, mirroring the API's delta
  reads, and say plainly that deletions are not represented.
- Narrow the securities list with one-tap filter chips (unclassified, stale
  quote, missing rate, and more — the same predicates the dashboard counts),
  and pick the columns the transaction history and holdings tables show.
- Use `/api/v1` and the MCP companion for the same supported local actions,
  including update/delete, live portfolio valuation with cash, and a
  contract-version read that says what the surface offers and when it last
  changed.

## Quick start

### Prerequisites

- Elixir and Erlang compatible with [mix.exs](mix.exs)
- PostgreSQL
- optional: Docker and Docker Compose

### Run with Docker Compose

```sh
docker compose up --build
```

Open the app and MCP companion at:

```text
http://localhost:4000
http://127.0.0.1:4001/mcp
```

Stop and remove local volumes:

```sh
docker compose down -v
```

### Run from source

```sh
mix deps.get
mix ecto.setup
mix phx.server
```

Open the Phoenix URL printed by the server, usually
`http://localhost:4000`.

### API and MCP

Set a local API token before using `/api/v1`:

```sh
export PORTFOLIXIR_API_TOKEN=replace-me
```

Run the MCP companion separately when you do not use Docker Compose:

```sh
npm install --prefix mcp-server
npm run build --prefix mcp-server
PORTFOLIXIR_API_BASE_URL=http://127.0.0.1:4000 \
PORTFOLIXIR_API_TOKEN=replace-me \
npm start --prefix mcp-server
```

## Development

Common local checks:

```sh
mix format
mix test
pre-commit run --all-files
npm test --prefix mcp-server
npm run build --prefix mcp-server
```

Install pre-commit once per checkout:

```sh
pre-commit install --install-hooks
```

## Documentation

- [docs](docs/index.md)

- Product documentation
  - [Product docs home](docs/index.md)
  - [Product feature documentation](docs/product-documentation.md)
  - [Home Deployment](docs/home-deployment.md)
- Architecture documentation
  - [Architecture overview](docs/architecture.md)
  - [Architecture decisions (ADRs)](docs/decisions/index.md)
- Development documentation
  - [Story workflow](docs/development/story-workflow.md)
  - [Developer guide](docs/development/guide.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [AGENTS.md](AGENTS.md)

## Safety

Use synthetic data for development and tests. Do not commit real account
numbers, broker statements, wallet addresses, personal names, or private
portfolio files.

Tests must not make external network calls.

## Governance

- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Security policy: [SECURITY.md](SECURITY.md)
- Code of conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- AI-agent guide: [AGENTS.md](AGENTS.md)
- License: [LICENSE](LICENSE)

## Support

If this app is useful to you, you can [support its ongoing maintenance via bunq](https://bunq.me/ahuservices?description=portfolixir-maintenance-support). Support is voluntary and appreciated, but does not create any entitlement to support, features, consulting, an SLA, or invoice-based work.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
