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

  The development stack is a Compose project of its own, `portfolixir-dev`,
  with a database volume of its own (#932), so its reset never reaches the
  database of a production stack in the same checkout. The name is fixed, so
  a second checkout or git worktree on the same host shares that project and
  its volume: give it a project of its own with `-p` (for example
  `docker compose -p portfolixir-dev-2 -f docker-compose.dev.yml up --build`,
  and the same `-p` on its `down -v`), or the second `up` replaces the first
  checkout's containers and its reset deletes the first checkout's data. A development stack
  started before #932 runs under the checkout directory's project instead and
  holds the ports: stop it once before the first start
  (`docker compose -p <project> -f docker-compose.dev.yml down`, where
  `docker compose ls` names the project). Its database stays in that
  project's `portfolixir-postgres-data` volume, the one a production stack in
  this checkout would start on; "Moving off the development stack" in
  [Home Deployment](../home-deployment.html) removes it.

- Phoenix from source:

  - `mix deps.get`
  - `mix ecto.setup`
  - `mix phx.server`

  The development configuration reads `DATABASE_NAME`, `DATABASE_HOST` and
  `DATABASE_PORT` (default `portfolixir_dev` on `127.0.0.1:5432`), `PORT`
  (default `4000`), `PHX_HOST`, `PHX_BIND_ALL`, `PORTFOLIXIR_ALLOWED_HOSTS`
  and `PORTFOLIXIR_BACKGROUND_FETCH`; prefix every command of a recipe with
  the same values. Logo discovery and the quote and FX sync run in
  development as they do in production; `PORTFOLIXIR_BACKGROUND_FETCH=off`
  leaves all three off, and every demo seed command in `priv/demo/README.md`
  sets it, so a seed run makes no outbound call. A release reads the same
  switch ([Home Deployment](../home-deployment.html)).

- The test suite on a database of its own, for a second checkout or git
  worktree running it at the same time: `mix test` neither creates nor
  migrates a database, so create and migrate it once, then run the suite with
  the same name.

  ```bash
  DATABASE_NAME=portfolixir_test_2 MIX_ENV=test mix ecto.create
  DATABASE_NAME=portfolixir_test_2 MIX_ENV=test mix ecto.migrate
  DATABASE_NAME=portfolixir_test_2 mix test
  ```

## Required local checks

Run the list in `AGENTS.md` at the repository root ("Required Local Checks")
before opening a PR. It is CI's `pre-commit`, `test`
and `quality` jobs, so a branch that passes it locally passes them; it is not
copied here, because a copy is what fell behind before (#1022).

The `npm` checks need **Node 24** (the Active LTS line). That version is
pinned in three places that must agree: `actions/setup-node` in CI,
`engines.node` in `mcp-server/package.json`, and the Node 24 base image in
`mcp-server/Dockerfile` (an exact tag pinned by digest) —
`test/portfolixir/ci_test.exs` asserts that they do, and that `@types/node`
describes the same major. Running the checks on another
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

## Upgrade migrations over legacy rows

Tests and CI migrate an empty database; a release migrates the database an
instance already holds, at boot. A migration that adds a CHECK, a NOT NULL, a
backfill, a UNIQUE index, a foreign key or an exclusion constraint to a table
that already exists can therefore pass every test and still stop an upgrade
on a row only an older instance has: a value the check refuses, a duplicate
the index refuses, an orphan the foreign key refuses. So every new migration
that adds one of the six needs a **seeded case**: a test that inserts, with
plain SQL, the rows an instance on an earlier release can hold, migrates to
head and asserts the migrated shape. An index built `CONCURRENTLY` or behind a
cleanup step is no exception, because the cleanup is what the case proves.
`test/portfolixir/seeded_upgrade/rule_test.exs` fails, naming the migration,
until the case exists.

A case uses `Portfolixir.SeededUpgrade`. `from:` is the version the scratch
database is migrated to before the seed (the last migration of the release
whose rows you seed), the seed runs in one transaction with a journal actor
set, and the tag names the migration the case covers:

```elixir
@moduletag :seeded_upgrade

@tag seeded_upgrade: 20_261_002_120_000
test "the new check does not stop the upgrade over a legacy row" do
  upgrade =
    SeededUpgrade.upgrade!(
      from: 20_260_926_121_500,
      seed: fn db ->
        %{rows: [[id]]} = SeededUpgrade.query!(db, "INSERT INTO ... RETURNING id", [])
        id
      end
    )

  assert %{rows: [[_value]]} =
           SeededUpgrade.query!(upgrade, "SELECT ... WHERE id = $1", [upgrade.seeded])
end
```

Each case gets a scratch database of its own, dropped when the test exits,
so the cases run in the default `mix test` and, on their own, in CI's
`migration-roundtrip` job (`mix test --only seeded_upgrade`). Prove a new
case once by putting the defect back locally and watching it fail;
`test/portfolixir/seeded_upgrade/sprint16_test.exs` holds the first two.

**A migration that calls application code** runs today's code against the
schema of its own version. A column a later migration adds to a table that
code reads or writes (the journal's `audit_journal` is the usual one) then
stops every upgrade from before that version, and every fresh install too if
the call runs on an empty database. Avoid it: write the migration with plain
SQL, naming only the columns its version has. Where a migration already does
it, one of two answers holds (#1015):

- **freeze it**: the migration file itself is immutable (CI rejects any
  change to it), so freeze the code it calls instead, in a module that names
  only the columns of the migration's version and no schema, as
  `Portfolixir.Tax.BuiltinSeed` does for `20260725140000` with the statutory
  data, its columns and its journal write; or
- **pin it**: keep the call and give the migration a seeded case over the
  rows that reach the call, so the later schema change turns that case red
  in the pull request that makes it. The policy-rule author backfill
  (`20260926121500`) is pinned this way, by `sprint16_test.exs`.

## Scope guardrails

- Use synthetic fixture data only.
- Keep tests free from external network calls.
- Keep financial values in Decimal-backed fields.
- Keep architecture decisions local and explicit to the three domain modules plus web.

## Cross-links

- [Home Deployment](../home-deployment.html)
- [Story Workflow](story-workflow.html)
