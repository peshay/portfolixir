# Portfolixir

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="priv/static/images/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="priv/static/images/logo-light.svg">
    <img alt="Portfolixir logo" src="priv/static/images/logo-wordmark.svg" width="420">
  </picture>
</p>

[![CI](https://github.com/peshay/portfolixir/actions/workflows/ci.yml/badge.svg)](https://github.com/peshay/portfolixir/actions/workflows/ci.yml)
[![Elixir](https://img.shields.io/badge/Elixir-Phoenix-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org/)
[![License](https://img.shields.io/github/license/peshay/portfolixir)](LICENSE)
[![Support maintenance via bunq](https://img.shields.io/badge/Support-Maintenance-4CAF50?style=flat-square&logo=ko-fi&logoColor=white)](https://bunq.me/ahuservices?description=portfolixir-maintenance-support)

## What is Portfolixir

Portfolixir is a self-hosted Elixir/Phoenix application for local portfolio
tracking. It helps you keep securities, portfolios, depots, cash accounts,
manual buy/sell transactions, holdings, and quote history in one auditable local
app.

The project focuses on transparent portfolio records and read-only inspection.
It is not a broker, bank, trading, payment, order, or rebalance platform.

## What works today

- Create securities, one portfolio, and linked cash/depot accounts.
- Record manual buy and sell transactions.
- Review derived holdings and stored quote history.
- Open a security detail chart from local quote history.

## Quick start

### Prerequisites

- Elixir and Erlang compatible with [mix.exs](mix.exs)
- PostgreSQL
- optional: Docker and Docker Compose

### Run with Docker Compose

```sh
docker compose up --build
```

Open the app at:

```text
http://localhost:4000
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

## Development

Common local checks:

```sh
mix format
mix test
pre-commit run --all-files
```

Install pre-commit once per checkout:

```sh
pre-commit install --install-hooks
```

## Documentation

- Product documentation
  - [Product docs home](docs/index.md)
  - [Product feature documentation](docs/product-documentation.md)
  - [Home Deployment](docs/home-deployment.md)
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

## Support

Support payments help fund ongoing maintenance work. They do not automatically
create entitlement to support, features, consulting, SLA, or invoice-based
engagement.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
