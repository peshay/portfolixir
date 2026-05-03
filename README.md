<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="priv/static/images/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="priv/static/images/logo-light.svg">
    <img alt="Portfolixir logo" src="priv/static/images/logo-wordmark.svg" width="580" />
  </picture>
</p>

# Portfolixir

<p>
  <a href="https://bunq.me/ahuservices?description=portfolixir-maintenance-support">
    <img src="https://img.shields.io/badge/Support-Maintenance-4CAF50?style=flat-square&logo=ko-fi&logoColor=white" alt="Support Portfolixir maintenance" />
  </a>
</p>

Portfolixir is an early-stage, self-hosted portfolio analytics and wealth graph platform built with Elixir, Phoenix, and LiveView.

[![CI](https://github.com/peshay/portfolixir/actions/workflows/ci.yml/badge.svg)](https://github.com/peshay/portfolixir/actions/workflows/ci.yml)
[![Elixir](https://img.shields.io/badge/Elixir-Phoenix-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/)

## What is Portfolixir

Portfolixir focuses on transparent, ledger-driven portfolio analysis with a strong read/reporting surface. It is designed to keep financial logic explicit, testable, and auditable.

## Why Portfolixir

- Elixir/Phoenix foundation for reliable server-side state and testability.
- Deterministic read models for reports and portfolio insights.
- Clear safety boundaries: no broker execution, no real-money actions, no write-capable AI tooling in MVP direction.

## Current status

- Early-stage MVP in active development.
- Not production-ready.
- Feature set is evolving through small scoped story cards.

## What works today

Current merged surface includes:

- Portfolio, account, and transaction management basics.
- Securities workbench and security detail views.
- Stored-quote charting on security detail pages.
- Classification and fund-allocation workbench pages.
- Read-only report pages (for example fund allocations and payments).
- Import overview and document/factsheet review flows.

Representative routes available in local runs include:

- `/`
- `/securities`
- `/reports/payments`
- `/imports`

## Product direction

Near-term direction is to harden portfolio read/reporting capabilities around:

- quote and valuation reliability,
- richer classifications/exposure reporting,
- safer import/reimport flows,
- read-only API/MCP boundaries.

## Safety and non-goals

Portfolixir is:

- **not financial advice**,
- **not a broker**,
- **not a trading/payment/order execution platform**,
- **not intended for real-money actions** in its current state.

MVP direction also excludes write-capable LLM/MCP tools.

## Quick start

### Prerequisites

- Docker Engine
- Docker Compose plugin (`docker compose`)

### Run locally

```sh
docker compose up --build
```

Open:

- http://localhost:4000
- http://localhost:4000/health

Stop and remove local volumes:

```sh
docker compose down -v
```

## Development workflow

Project quality gates:

```sh
mix format
mix test
```

## Read API authentication

`/api/read/*` can be protected with an API key.

- `READ_API_AUTH_ENABLED=true` enables API key checks.
- `READ_API_KEY=<your-key>` sets the expected key.
- Clients send the key with header `x-api-key`.

In production, read API auth is fail-closed by default (`READ_API_AUTH_ENABLED` defaults to `true`). Setting `READ_API_AUTH_ENABLED=false` in production raises at boot. In local dev/test, auth may be left disabled.

## Roadmap and next milestones

Roadmap execution is tracked through Planka story cards and PR handoffs. Product-level story sources:

- [`docs/product/pp-inspired-product-backlog.md`](docs/product/pp-inspired-product-backlog.md)
- [`docs/product/llm-story-workflow.md`](docs/product/llm-story-workflow.md)

## Contributing / AI agent workflow

- Read [`AGENTS.md`](AGENTS.md) before making changes.
- Keep changes scoped to a single story.
- Keep public artifacts concise and repo-facing.

## Portfolio Performance inspiration note

Portfolixir is inspired by Portfolio Performance workflow ideas. It is an independent project and is not affiliated with or endorsed by the Portfolio Performance project.

## Support

<a href="https://bunq.me/ahuservices?description=portfolixir-maintenance-support">
  <img src="https://img.shields.io/badge/Support-Portfolixir%20Maintenance-4CAF50?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Support Portfolixir maintenance">
</a>

Support payments help fund ongoing maintenance work. They do not automatically create entitlement to support, features, consulting, SLA, or invoice-based engagement.

## License

This project is licensed under the MIT License. See [`LICENSE`](LICENSE).
