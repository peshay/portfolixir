# ADR 0001: Tech Stack

## Status

Accepted for MVP.

## Decision

Portfolixir uses:

- Elixir + Phoenix as a modular monolith
- Phoenix LiveView for the web UI
- PostgreSQL as canonical database
- Ecto for schema, queries and migrations
- Oban for background jobs
- Tailwind CSS + daisyUI for styling and themes
- Apache ECharts for portfolio charts
- ExUnit, Mox, StreamData and ExCoveralls for testing
- Credo, Dialyxir, Sobelow and mix_audit for quality checks
- Docker multi-arch images for `linux/amd64` and `linux/arm64`

## Rationale

The system needs a web UI, API, background jobs, deterministic domain logic and future MCP/LLM integration. Phoenix provides a compact full-stack framework and LiveView avoids a separate frontend application during the MVP.

PostgreSQL is the canonical store because the core domain is relational and ledger-like. TimescaleDB may be evaluated later for large time-series workloads. InfluxDB is not part of the MVP because market prices are not the core data model and can be stored relationally at first.

## Consequences

- Keep the app as one Phoenix application at first.
- Do not split into microservices during MVP.
- Do not add a separate React/Svelte frontend during MVP.
- Do not add TimescaleDB/InfluxDB until there is a proven need.
