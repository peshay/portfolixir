---
project_name: 'portfolixir'
user_name: 'Andi'
date: '2026-06-11'
sections_completed: ['technology_stack']
existing_patterns_found: 14
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

Exact versions live in `mix.lock` and `mcp-server/package-lock.json` — check there,
do not assume. Policy: track latest stable (see Dependency Update Policy below).

- **Elixir/Phoenix** — CI (authoritative) runs **Elixir 1.18.3 / OTP 27**; local
  toolchains may be newer. Do not use language features beyond the CI version.
- **LiveView 0.20.x — NOT 1.x**: verify idioms against the installed version;
  1.0-only patterns will not compile.
- **No asset pipeline**: no `assets/` dir, no esbuild/tailwind, `watchers: []`.
  CSS is hand-written in `priv/static/app.css`; no Tailwind classes, no JS build.
  Charts/UI are server-rendered (LiveView/SVG) — do not introduce a JS bundler.
- **PostgreSQL** via ecto_sql/postgrex — the only data store.
- **Tests require a running PostgreSQL** (postgres:18 in CI and docker-compose;
  defaults `postgres`/`postgres`, override via `DATABASE_*` env vars). Start it
  before TDD — never "fix" a missing DB by skipping tests.
- **decimal** — all persisted money, quantities, prices, fees, taxes, FX rates (ADR-0003).
- **req** is the HTTP client — never called in tests (synthetic fixtures/fakes only).
- **Quality gates (CI-blocking):** credo (strict), dialyxir (PLTs in `priv/plts`,
  CI cache keyed to Elixir/OTP version), sobelow, excoveralls.
- **MCP companion** (`mcp-server/`, TypeScript): MCP SDK, **express 5** (not 4 —
  changed middleware/error semantics), zod, tsc build, `node --test` via tsx.

### Dependency Update Policy

- Track **latest stable**; updates land as **dedicated dependency-update PRs**,
  never inside feature stories.
- Agents must NOT bump **or add** dependencies while implementing a story —
  a new dep is a reviewed decision (check ADRs first; e.g. no money libs, ADR-0003).
- Gate updates (credo/dialyxir/sobelow) may add new checks: fix or baseline new
  findings in the same update PR. Bump CI `elixir-version`/`otp-version` and the
  PLT cache key together with toolchain updates.
- Update PRs should note new dep features that could benefit the project
  (follow-up note only — scope lock applies).
- Follow-ups not yet implemented: automate update visibility (Renovate/Dependabot
  for hex + npm, `mix hex.outdated`, optional CycloneDX SBOM); document this
  policy in AGENTS.md/ADR.

## Critical Implementation Rules

_Documented after discovery phase_
