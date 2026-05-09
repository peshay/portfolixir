# Portfolixir

Portfolixir is an early-stage, self-hosted portfolio analytics and wealth graph
platform built with Elixir, Phoenix, and LiveView.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="priv/static/images/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="priv/static/images/logo-light.svg">
    <img alt="Portfolixir logo" src="priv/static/images/logo-wordmark.svg" width="420" />
  </picture>
</p>

[![CI](https://github.com/peshay/portfolixir/actions/workflows/ci.yml/badge.svg)](https://github.com/peshay/portfolixir/actions/workflows/ci.yml)
[![Elixir](https://img.shields.io/badge/Elixir-Phoenix-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![License](https://img.shields.io/github/license/peshay/portfolixir)](LICENSE)

[![Support maintenance via bunq](https://img.shields.io/badge/Support-Maintenance-4CAF50?style=flat-square&logo=ko-fi&logoColor=white)](https://bunq.me/ahuservices?description=portfolixir-maintenance-support)

## What it is

Portfolixir helps self-hosters and portfolio tinkerers model investments through
an explicit ledger, then inspect read-only portfolio, security, allocation, and
import views.

It exists to make portfolio data flows transparent, testable, and auditable
without adding broker, banking, payment, order, or rebalance capabilities.

## Current MVP scope

The MVP can currently support local exploration of:

- portfolio, account, and transaction records;
- securities workbench and security detail views;
- classification and fund-allocation workbench pages;
- read-only report pages such as fund allocations and payments;
- import overview and document/factsheet review flows;
- authenticated read API and read-only MCP wrapper boundaries.

The MVP cannot provide financial advice, connect to brokers for execution,
move money, place orders, rebalance accounts, or promise production readiness.

## Product documentation

Detailed product material lives outside this README:

- [GitHub Page / product overview](https://portfolixir.dev/)
- [GitHub Pages publishing notes](docs/product/github-pages.md)
- [Product backlog](docs/product/pp-inspired-product-backlog.md)
- [LLM story workflow](docs/product/llm-story-workflow.md)
- [Portfolio boundaries](docs/architecture/portfolio-boundaries.md)

## Quick start

### Prerequisites

- Docker Engine
- Docker Compose plugin (`docker compose`)

### Run locally

```sh
docker compose up --build
```

Open the app and health endpoint at the local Phoenix port shown by the
running server.

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

Generate the CycloneDX dependency SBOM locally with:

```sh
mix sbom.ci
```

The SBOM is written to `sbom/portfolixir.cdx.json`. CI uploads the same
path as the `portfolixir-sbom` artifact. Runtime and local PostgreSQL 18
upgrade notes live in [Dependency inventory and runtime baseline](docs/process/dependency-sbom.md).

CI also enforces a coverage non-regression floor at **87.8%**
(ExCoveralls/Cobertura line coverage).

## Safety boundaries

Portfolixir is:

- **not financial advice**;
- **not a broker**;
- **not a trading, banking, payment, order, or rebalance platform**;
- **not intended for real-money actions** in its current state.

MVP direction also excludes write-capable LLM/MCP tools.

## Contributing

- Read [AGENTS.md](AGENTS.md) before making changes.
- Keep changes scoped to a single story.
- Keep public artifacts concise and repo-facing.
- Follow the repository pull request template.

## Portfolio Performance inspiration note

Portfolixir is inspired by Portfolio Performance workflow ideas. It is an
independent project and is not affiliated with or endorsed by the Portfolio
Performance project.

## Support

Support payments help fund ongoing maintenance work. They do not automatically
create entitlement to support, features, consulting, SLA, or invoice-based
engagement.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
