---
project_name: 'portfolixir'
user_name: 'Andi'
date: '2026-06-11'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules']
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

### Language-Specific Rules (Elixir)

Style that CI already enforces (mix format; Credo strict: alias order, nesting,
line length 120, mandatory substantive @moduledoc) is not repeated here — run
the gates. The rules below cause **silent failures** no gate catches:

- **Decimal discipline:**
  - Never `==`/`<`/`>` on Decimals — use `Decimal.compare/2` / `Decimal.equal?/2`
    (`Decimal.new("1.0") == Decimal.new("1")` is `false`). Sort with
    `Enum.sort(list, Decimal)`, not via float conversion.
  - `Decimal.new/1` raises on floats — `Decimal.from_float/1` only at
    display/chart boundaries, never for persisted values.
  - API/JSON: explicit `Decimal.to_string(:normal)` (see `api/v1/json.ex`) —
    never rely on Jason's numeric Decimal encoding; the contract requires
    strings, `:normal` avoids scientific notation.
  - Migrations: decimal columns carry explicit `precision`/`scale`
    (money/quotes: 20,6; volume: 30,6) — never a bare `:decimal`.
- **Atoms from input:** `String.to_existing_atom/1` for anything user/API-
  supplied. `String.to_atom/1` only where the atom space is provably fixed —
  with a comment saying so (see `catalog/security_fields.ex`).
- **Day-granular domain time:** ledger and quotes use `:date` fields, not
  datetimes. Do not introduce DateTime/timezone semantics into domain data.
- **Gettext workflow:** user-facing strings go through `gettext` (single `de`
  locale; enforced by `localization_test.exs`). After adding strings run
  `mix gettext.extract --merge` and translate in `priv/gettext/de/`.
- **Error idiom:** tagged tuples (`{:ok, _}`/`{:error, changeset}`) for
  create/update/delete; `get_*!` bang variants for fetch-or-404. Web layers
  translate both to user feedback.
- **Tests default `async: true`** on `DataCase` (sandbox-safe) unless the test
  touches shared state; `ConnCase` tests typically run sync.
- **Meta-rule:** match the existing style of the file you touch (guards vs
  `@spec` at public boundaries, small pattern-matched `defp` clauses over
  `if`/`cond` chains, `import` only `Ecto.Query` in contexts /
  `Ecto.Changeset` in schemas).

### Framework-Specific Rules (Phoenix / LiveView / MCP)

- **No CoreComponents:** `<.input>`, `<.button>`, `<.modal>` etc. do not exist.
  Function components: `app_shell`, `security_chart` only — build plain HEEx
  with the existing CSS classes from `priv/static/app.css`.
- **No `.heex` template files:** LiveViews render via inline `render/1` with
  `~H`, kept as large single-module files. Dialogs/pickers are extracted as
  **LiveComponents in a per-view subdirectory** (`live/securities/…`) — follow
  that split, do not create templates/views.
- **State is plain assigns, not streams** — `stream/3` is used once in the
  whole app; `to_form/1` for forms. Do not introduce streams by default.
- **New live routes** go inside the existing
  `live_session :browser, on_mount: PortfolixirWeb.LiveLocale` block
  (sets Gettext locale from session; `en`/`de`, fallback `en`).
- **JSON API pattern:** controllers call contexts, shape responses through the
  single shared presenter `Api.V1.JSON`, respond `json(conn, %{data: …})` /
  `%{errors: %{…}}` + status. No Phoenix.View, no per-controller JSON module,
  no `action_fallback` — do not introduce them.
- **Not-found idiom per layer:** API controllers use non-bang `get_*` +
  `not_found(conn)` (404 JSON); LiveViews use `get_*!` (crash → error page).
- **API routes** live under `/api/v1` behind `ApiAuthPlug` (bearer token from
  `:api_token` app env / `PORTFOLIXIR_API_TOKEN`). Only `/health` is public.
- **Web layer never touches `Repo`** (verified: zero `Repo.` calls in
  `lib/portfolixir_web/`) — always go through contexts. Bypassing them skips
  domain invariants (ledger projection, import idempotency) and silently breaks
  the auditability guarantee.
- **MCP companion:** tools in `mcp-server/src/tools.ts`, named
  `portfolixir.<resource>.<verb>`, each with BOTH a hand-written JSON Schema
  (`additionalProperties: false`) and a zod validator; calls go through
  `api-client.ts` to the JSON API only (ADR-0002). Financial values stay
  strings end-to-end. Every new API endpoint needs a matching MCP tool, or an
  explicit n/a note in the PR.

**Exemplar files** (read the matching one before implementing):

- small canonical LiveView: `live/transaction_management_live.ex`
- LiveComponent dialog: `live/securities/security_form_dialog.ex`
- API controller + presenter: `controllers/api/v1/security_controller.ex` + `json.ex`
- MCP tool definition: `mcp-server/src/tools.ts` (`tool(...)` helper)

### Testing Rules

AGENTS.md defines the binding test contract (user-story comment above each
functional test, DataCase/ConnCase split, TDD order, no network calls). Beyond
that, the repo-specific mechanics:

- **Fake providers, not mocks** (no Mox in this repo): external integrations
  are behaviours with a Fake in `test/support/{fx,quote_sync,security_search}/`,
  registered via `config/test.exs`; set responses with `Fake.put_response/2`.
  Fakes hold **per-process** state (`Process.put`) — visible only in the
  process that set them.
- **`async: false` is needed exactly when** (a) the test starts a supervised
  process that touches the DB (`start_supervised` GenServers — a separate
  process needs the shared sandbox mode), or (b) tests share filesystem state
  (logo store under `priv/static/security_logos`). The failure signature of a
  missing `async: false` is `DBConnection.OwnershipError` — fix the mode,
  don't "fix" the test.
- **Background syncs are off in test** (`enabled?: false`); HTTP edges are
  stubbed with Req's `plug:` option — canonical helper: `plug_stub` in
  `catalog/logo_lookup_test.exs`.
- **API auth in tests:** bearer token fixed to `test-api-token`
  (`config/test.exs`) for ConnCase API tests.
- **Import fixtures are files, not builders:**
  `test/support/fixtures/portfolio_performance/` holds valid AND deliberately
  invalid samples — extending the import means adding both kinds. All other
  test data is built inline through public context functions; there is no
  central fixtures module — keep it that way.
- **Meta-tests guard repo invariants:** `ci_test.exs`, `docs_test.exs`,
  `workflow_docs_test.exs`, `localization_test.exs` assert on CI workflow
  content, doc files, and locale completeness. Changes to `.github/`, docs, or
  UI strings can fail these — update the meta-test together with the change;
  never delete or skip it.
- **Exact Decimal expectations:** `Decimal.equal?/2` or exact serialized
  strings — never float tolerance/delta assertions on money.
