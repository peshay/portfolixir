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

Portfolixir is a self-hosted portfolio analytics and wealth graph platform built with Elixir, Phoenix and LiveView; it is currently early-stage.

[![CI](https://github.com/peshay/portfolixir/actions/workflows/ci.yml/badge.svg)](https://github.com/peshay/portfolixir/actions/workflows/ci.yml)
[![Elixir](https://img.shields.io/badge/Elixir-Phoenix-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)

## What it can do today

- Run locally with Docker Compose.
- Manage securities and edit their metadata.
- Manage taxonomies/categories with descriptions.
- Assign taxonomies/categories to securities.
- Access a health endpoint for runtime checks.
- Use the early branded Phoenix LiveView product shell at:
  - `http://localhost:4000`
  - `http://localhost:4000/securities`
  - `http://localhost:4000/taxonomies`

## Product direction

Portfolixir is moving toward a full ledger-driven portfolio platform:

- Ledger-like portfolio model with immutable history.
- Securities and cash accounts as first-class objects.
- Transaction capture (buy/sell/dividends/cash flows) for reproducible state.
- Calculated security holdings and cash balances from transactions.
- Manual quotes first, and provider-based quotes afterwards.
- Valuation and allocation reporting driven by positions and quotes.
- Import/export-friendly data handling.
- A future read-only API and MCP path for AI-assisted analysis.

## Quick start

### Prerequisites

- Docker Engine
- Docker Compose plugin (`docker compose`)

### Run locally

```sh
docker compose up --build
```

Then open:

- http://localhost:4000
- http://localhost:4000/health
- http://localhost:4000/securities
- http://localhost:4000/taxonomies

When done:

```sh
docker compose down -v
```

## Project status

- Early MVP / active development.
- Not production-ready.
- No real-money actions.
- No broker execution.
- No financial advice.

## Read API authentication

`/api/read/*` can be protected with an API key.

- `READ_API_AUTH_ENABLED=true` enables API key checks.
- `READ_API_KEY=<your-key>` sets the expected key.
- Clients send the key with header `x-api-key`.

In production, read API auth is fail-closed by default (`READ_API_AUTH_ENABLED` defaults to `true`). Setting `READ_API_AUTH_ENABLED=false` in production raises at boot. In local dev/test, auth may be left disabled.

## Technical stack

- Elixir
- Phoenix
- LiveView
- PostgreSQL
- Docker Compose
- ExUnit / Phoenix.ConnTest / Phoenix.LiveViewTest

## Support

<a href="https://bunq.me/ahuservices?description=portfolixir-maintenance-support">
  <img src="https://img.shields.io/badge/Support-Portfolixir%20Maintenance-4CAF50?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Support Portfolixir maintenance">
</a>

Support payments help fund ongoing maintenance work. They do not automatically create entitlement to support, features, consulting, SLA, or invoice-based engagement.

## Contribution notes

- Human contributors and AI coding agents should read [`AGENTS.md`](AGENTS.md) before making changes.
- Story workflow lives in [`docs/product/llm-story-workflow.md`](docs/product/llm-story-workflow.md).
- Product backlog lives in [`docs/product/pp-inspired-product-backlog.md`](docs/product/pp-inspired-product-backlog.md).

## GitHub Pages landing page

- Static landing page files live in [`docs/`](docs/).
- Setup instructions live in [`docs/product/github-pages.md`](docs/product/github-pages.md).
- This setup is intentionally docs/static-only and does not change Phoenix runtime behavior.

## Repository metadata

- Repository metadata/social-preview target state is documented in [`docs/product/repository-metadata-and-social-preview.md`](docs/product/repository-metadata-and-social-preview.md).
- Manual GitHub settings (description/topics/social preview upload) are listed explicitly there.

## License

This project is licensed under the MIT License. See [`LICENSE`](LICENSE).
