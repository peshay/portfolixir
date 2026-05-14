# Portfolixir

Portfolixir is a self-hosted Elixir/Phoenix app for local portfolio tracking.
This branch is a controlled foundation reset, not a finished MVP.

The reboot foundation focuses on a narrow manual workflow:

1. Create securities.
2. Create one portfolio.
3. Create one depot linked to one cash account.
4. Record manual buy and sell transactions.
5. Calculate current holdings from transactions.
6. Store quote history.
7. Display a security detail chart from stored quotes.

Portfolixir is not a broker, bank, payment, trading, order, rebalance, import,
document intake, LLM, or MCP system.

## Reboot Foundation Scope

The active foundation contains:

- Phoenix and LiveView shell;
- neutral, unbranded HTML surfaces for the MVP workflow;
- securities master data;
- portfolios, cash accounts, and linked securities accounts;
- manual buy and sell transactions using `Decimal`;
- derived current holdings from stored transactions;
- manually stored security quote history;
- a security detail price history chart;
- tests for the basic schema workflow and dashboard/navigation path.

Future MVP functionality will be added through human-reviewed Epics. Each Epic
should pass local checks, deploy to staging, receive staging review, and only
then be considered for production promotion.

Deferred work includes PDF import, CSV import, broker sync, bank sync, document
intake, MCP tools, LLM features, advanced reports, advanced classifications,
trading, payments, orders, and rebalancing.

For MVP trade entry, each depot has exactly one linked cash account. Buy and
sell transactions derive the cash account from the selected depot instead of
asking the user to choose one independently.

Visual product design and branding are intentionally deferred. The foundation
keeps the UI plain so design can restart in a separate reviewed PR.

## Local Development

Prerequisites:

- Elixir and Erlang compatible with `mix.exs`;
- PostgreSQL;
- optionally Docker and Docker Compose.

Run with Docker Compose:

```bash
docker compose up --build
```

If the checkout already has a prototype-era Docker database volume, reset it
before first reboot use:

```bash
docker compose down -v
docker compose up --build
```

Run on the host:

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

If the host database already contains prototype-era migrations, run
`mix ecto.reset` once for the reboot foundation.

Open the app at the Phoenix port shown by the server, usually
`http://localhost:4000`.

## Deployment Process Scaffolding

Deployment is intentionally a process handoff in this foundation branch. Runtime
deployment should use reviewed container image digests, staging review, and
explicit production promotion. The foundation does not claim production
readiness.

The deployment scaffolding is documented in
[docs/deployment.md](docs/deployment.md). Local development continues to use the
root `docker-compose.yml`; runtime deployments use `deploy/compose.yml` with a
reviewed GHCR image digest. Internal Compose examples set `DATABASE_SSL=false`
because the app and PostgreSQL share a Compose network.

## Quality Gate

Run these before opening a PR:

```bash
mix format
mix test
pre-commit run --all-files
```

Development keeps the user story, TDD, and user documentation together. For each
user-visible story, follow this order:

1. User Story documented.
2. Functional test written directly below the User Story comment.
3. Test failure confirmed for the expected reason.
4. Smallest implementation code written.
5. Required gates run.
6. User documentation reviewed and updated when visible behavior changed.

Future MVP functionality is added through human-reviewed Epics on staging.
See [docs/development/story-workflow.md](docs/development/story-workflow.md)
for the full story, test, implementation, and documentation process.

Install pre-commit once per checkout:

```bash
pre-commit install --install-hooks
```

## Safety

Use synthetic data for development and tests. Do not commit real account
numbers, broker statements, wallet addresses, personal names, or private
portfolio files.

Tests must not make external network calls. Market data integration is deferred;
quote history in the MVP is stored manually.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
