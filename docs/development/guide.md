---
layout: docs
title: Development Guide
description: Local development guide for Portfolixir contributors.
---

# Development documentation

## Purpose

This guide contains the minimum local context needed for contributors. It keeps
the branch changes small and aligned with the project reset scope.

## Local runbook

Start the project with either:

- Docker Compose:

  - `docker compose -f docker-compose.dev.yml up --build` (the development
    stack; the root `docker-compose.yml` is the production release)
  - `docker compose -f docker-compose.dev.yml down -v` to reset local data

- Phoenix from source:

  - `mix deps.get`
  - `mix ecto.setup`
  - `mix phx.server`

## Required local checks

Run before opening a PR:

- `mix format`
- `mix test`
- `mix coveralls`
- `pre-commit run --all-files`
- `npm test --prefix mcp-server`
- `npm run build --prefix mcp-server`

The two `npm` checks need **Node 24** (the Active LTS line). That version is
pinned in three places that must agree: `actions/setup-node` in CI,
`engines.node` in `mcp-server/package.json`, and the `node:24-alpine` image in
`mcp-server/Dockerfile` — `test/portfolixir/ci_test.exs` asserts that they do,
and that `@types/node` describes the same major. Running the checks on another
major produces an `EBADENGINE` warning rather than an error; CI is the
authority.

If pre-commit is not installed:

- `pre-commit install --install-hooks`

## Measuring before activating a derived value

Which analytics run the `:durable` lifetime is a configuration decision
informed by measurement, never an architectural one
([ADR-0039](../decisions/0039-durable-derived-values.html) §2). The command
that produces the measurement seeds a deterministic synthetic ledger and times
every figure a surface waits on, twice, with the derived layer off:

```bash
DATABASE_NAME=portfolixir_bench mix ecto.create
DATABASE_NAME=portfolixir_bench mix ecto.migrate
DATABASE_NAME=portfolixir_bench mix portfolixir.derived.measure
```

It **writes synthetic transactions**, so point it at a throwaway database as
above — the same convention `priv/demo` uses — and it refuses to run in `:prod`.
`--securities`, `--bookings` and `--years` size the ledger; `--skip-seed`
measures whatever is already there.

An analytic that turns out cheap enough not to need a lifetime is a finding and
is printed as one. Record the run in ADR-0039 next to the existing measurement
rather than in a commit message, so the next activation decision has something
to be compared against.

## Scope guardrails

- Use synthetic fixture data only.
- Keep tests free from external network calls.
- Keep financial values in Decimal-backed fields.
- Keep architecture decisions local and explicit to the three domain modules plus web.

## Cross-links

- [Home Deployment](../home-deployment.html)
- [Story Workflow](story-workflow.html)
