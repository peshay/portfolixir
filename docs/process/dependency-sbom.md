# Dependency inventory and runtime baseline

Portfolixir keeps dependency inventory reproducible with a CycloneDX SBOM generated from Mix dependencies.

## Local SBOM

Generate the local dependency SBOM with:

```sh
mix deps.get
mix sbom.ci
```

The command writes a CycloneDX JSON SBOM to:

```text
sbom/portfolixir.cdx.json
```

The generated file is intentionally ignored by Git. Recreate it locally or download the CI artifact when an inventory snapshot is needed.

## CI SBOM

The CI test job generates the same SBOM with `mix sbom.ci` and uploads it as the `portfolixir-sbom` artifact. The artifact path is `sbom/portfolixir.cdx.json`.

## Runtime version policy

Development and CI intentionally use the same application/runtime major versions:

- Elixir: `1.18.3`
- Erlang/OTP: `27`
- PostgreSQL: `18`

The Dockerfile uses `elixir:1.18.3-otp-27`.
GitHub Actions uses the same Elixir version and OTP major through
`erlef/setup-beam`.
Local Compose uses `postgres:18-alpine`, and the CI database service uses
`postgres:18`.

The application still declares `elixir: "~> 1.16"` in `mix.exs` as the minimum
compatible Elixir range.
Runtime containers and CI use the newer pinned baseline above so changes are
verified against one deliberate toolchain.

## PostgreSQL 18 local volume note

PostgreSQL major-version upgrades are not in-place data-directory upgrades.
Local development data created with PostgreSQL 16 should be treated as
incompatible with the PostgreSQL 18 Compose service.

For disposable local data, reset the Compose volumes before starting the upgraded service:

```sh
docker compose down -v
docker compose up --build
```

If local development data must be preserved, dump it from the old PostgreSQL 16 service first, then restore it into the PostgreSQL 18 service. This repository does not define a production migration plan for this change.

Compose mounts the named database volume at `/var/lib/postgresql` and sets `PGDATA=/var/lib/postgresql/18/docker` so the PostgreSQL 18 data directory is explicit and version-scoped.
