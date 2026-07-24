---
project_name: 'portfolixir'
user_name: 'Andi'
date: '2026-06-11'
sections_completed:
  ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'quality_rules', 'workflow_rules', 'anti_patterns']
status: 'complete'
rule_count: 60
optimized_for_llm: true
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
- **Microcopy voice (owner rule 2026-07-23):** write UI and doc text
  **impersonally** — state the fact/state/consequence, do not address the
  user. Prefer no address at all ("Konfiguration bleibt unverändert", not
  "mir ist klar, dass…"; "Mapping required", not "you must map"). Where
  address is genuinely unavoidable, use **du**, never Sie. Keep it **terse
  and self-explanatory**: the UI is not a tutorial. A control that is clear
  from its label carries no helper prose; genuinely needed domain
  explanation (TTWROR, split basis, cost-basis effects) lives in an
  on-demand **ⓘ tooltip** (UX-DR11), not permanently in the sightline.
  Warnings are a statement of fact plus the remedy, not a paragraph. This
  is a review-blocking standard: second-person address and tutorial prose
  in user-facing strings are findings.
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

### Code Quality & Style Rules

CI-enforced formatting/linting is covered in the Language Rules preamble.
What agents must know beyond "run the gates":

- **Credo thresholds are grandfathered, not targets:** `max_complexity: 15` /
  `max_nesting: 4` baseline the current worst offenders; new code aims at the
  defaults (9 / 2). Ratchet per touched file — never raise a threshold.
  Lowering the baseline is tracked in issue #314.
- **Dialyzer has no ignore file — keep it at zero;** the first ignore entry is
  the beginning of the end. **Sobelow ignores are deliberate and documented:**
  `--ignore Config.CSP,Config.HTTPS` (TLS is the operator's reverse-proxy
  concern; CSP needs nonce support first — follow-up tracked in #314), and
  per-function `# sobelow_skip` annotations require a written reason. Never
  add a skip without one.
- **Pre-commit hooks modify files** (whitespace/EOF/line-ending fixers) —
  re-stage and re-commit. The `llm-commit-footer` hook rejects commits without
  the `Model:`/`Thinking level:` footer.
- **Repository language is English** for ALL artifacts — commits, PRs, issues,
  ADRs, docs, code comments (repo contract, PR #341).
- **`docs/` is a published Jekyll site** (GitHub Pages): pages need YAML
  frontmatter, internal links use `.html` (not `.md`), `docs_test.exs` asserts
  on required files. User-visible changes update `product-documentation.md`.
- **Coverage runs via Codecov** (`mix coveralls.json` → codecov-action,
  `fail_ci_if_error: true`). There is deliberately **no 100% goal** (decided
  2026-06-11, supersedes the earlier #314 comment): targets ratchet up per
  issue #314 toward ~90%+ on changed lines. Tests must assert exact behavior —
  assertion-free "line-touching" tests are a review reject, regardless of
  coverage effect.

### Quality Gate Roadmap (agreed 2026-06; all CI gates verified green on 2026-06-11)

Gates land ONLY as dedicated stories — this roadmap is a record of decisions,
not an invitation to add gates opportunistically inside feature work.
Renovate/Dependabot PRs are reviewed like any dep-update PR, never auto-merged.

1. **`mix compile --warnings-as-errors`** in CI — catches the classic agent
   artifacts (unused vars, unreachable patterns, deprecated calls).
2. **Coverage ratchet, not 100%:** raise Codecov targets incrementally
   (#314); raising the ratchet is part of periodic maintenance PRs. Target
   ~90%+ on changed lines. Rationale: 100% forces agents into coverage gaming.
3. **Dependency hygiene:** `mix hex.audit` + `mix deps.audit` (mix_audit) +
   `npm audit --audit-level=high` (mcp-server) in CI; Renovate/Dependabot as
   housekeeping; `mix deps.unlock --check-unused` (must run AFTER `deps.get` —
   false-positives on unfetched deps). Known debt: 2 moderate npm
   vulnerabilities in mcp-server (below the `high` gate) — fix in the first
   dependency-update PR.
4. **Migration roundtrip in CI:** `ecto.migrate && ecto.rollback --all &&
   ecto.migrate` — self-hosted users upgrade their own DBs; irreversible
   migrations are support cases.
5. **Invariant gates (cheap meta-tests):** no `:float` in schemas/migrations
   (Decimal-only persistence); no DB-driver deps in `mcp-server/package.json`
   (ADR-0002); context-boundary enforcement (evaluate `boundary` library vs.
   web-layer `Repo.` scan — currently convention only, biggest unguarded
   invariant); no catch-all clause in `Ledger.Projection.effects/1` (AST
   meta-test — preserves crash-by-design for unknown kinds); migration-diff
   check against `main` (applied migrations are never edited).
6. **Domain-correctness tests (highest ROI):** golden-master corpus for PP
   import parity (synthetic PP files + checked-in Decimal-exact expected
   outputs); StreamData property tests for ledger/money invariants
   (bookings sum to zero, no rounding drift; import idempotency:
   `import(x); import(x) == import(x)`).

Deliberately NOT adopted: 100% coverage gate; mutation testing as gate
(instead: occasional manual mutation session on the money domain); E2E browser
suite (at most one smoke test, later, non-blocking); live-provider tests in
CI; performance/load gates; SBOM (no reader yet — revisit with audit tooling);
API/MCP parity gate (stays a PR-review checklist item); `mix xref` cycle gate
(add when the first real cycle appears).

### Development Workflow Rules

AGENTS.md is the binding contract (branch naming `agent/<provider>/<topic>`,
Model/Thinking-level commit footer — enforced by pre-commit —, required local
checks, story workflow, scope lock). On top:

- **Conventional commits with scope** (`feat(cash):`, `refactor(ledger):`,
  `chore(deps):`) — applies to commits AND PR titles.
- **PRs are squash-merged onto `main`** (`required_linear_history` is enforced;
  the PR title becomes the main commit — write it as a conventional-commit
  line). Direct pushes and force-pushes to `main` are blocked.
- **Merge blockers agents must expect:** required status check `test` with
  `strict: true` (branch must be up to date with `main` — rebase when main
  moves) and `required_conversation_resolution` (every PR conversation must be
  resolved). **Only the maintainer merges** — agents never merge their own PRs.
- **CI = three jobs:** `pre-commit` (Python 3.12), `test` (postgres:18
  service, `MIX_ENV=test mix coveralls.json` → Codecov), `quality` (Credo,
  Sobelow, Dialyzer with version-keyed PLT cache). Run all locally before
  pushing; `mix coveralls` needs running PostgreSQL.
- **PR bodies carry evidence per iteration step** (AGENTS.md AI Authoring
  Contract): story → tests-first proof → minimal implementation → API/MCP
  coverage review → docs → security pass.
- **Architecture changes need an ADR** (`docs/decisions/NNNN-*.md`, next free
  number; supersede instead of editing) — landed in the same PR as the change
  (see ADR-0009 / PR #324).
- **BMad artifacts under `_bmad-output/` are committed** — they are part of
  the story record, not local state.
- **Cross-references are cheap, use them:** issues (`#314`), ADRs
  (`ADR-0009`) in commits, PR bodies, and code comments.

### Critical Don't-Miss Rules

The expensive mistakes — rule, failure symptom, and source location each.
AGENTS.md "Hard Rules"/"Security Boundaries" apply verbatim on top.

1. **Holdings are never stored** — derived from transactions (ADR-0004;
   no holdings table exists). Wrong holdings ⇒ fix projection or data,
   never add a table/cache.
2. **`Ledger.Projection.effects/1` owns ALL booking semantics** (ADR-0011)
   and is **pure** — no Repo/clock/config inside the reducer. The kind set is
   closed (`Transaction.kinds/0`: 13 PP kinds + `balance_adjustment` — note:
   ADR-0009's "snapshot" concept is spelled `balance_adjustment` in data).
   Unknown kinds raise BY DESIGN — a defensive `_ ->` fallback turns
   crash-by-design into silent corruption. New kind = one `effects/1` clause
   + `Transaction` validation, nothing else.
3. **Amounts are positive magnitudes — the sign comes from the kind**
   (changeset guards: `ledger/transaction.ex` `validate_number ... > 0`).
   Single exception: `balance_adjustment.gross_amount` is an absolute balance,
   may be negative (overdraft). PP exports with signed values are normalized
   at import, never stored signed.
4. **Cost-basis views filter to priced `buy`/`sell` only**
   (`ledger/trade_matcher.ex`, moving-average holdings): transfers and
   deliveries move quantity, not cost basis. Symptom: avg-cost test "breaks"
   after importing a delivery ⇒ by design, not a bug.
5. **Cash = balance snapshots, not a mirrored ledger** (ADR-0009): `{:set,
   absolute}` anchors beat same-day `{:add}` legs. Same-day ordering is
   deterministic: `sort_by {date, intra_day_order, id}` (`projection.ex:135`)
   — never reorder. Symptom: cash balance off while ledger looks right ⇒
   check anchor ordering, not the reducer.
6. **Transactions are written only through `Ledger`/`Imports` public
   functions** — read models never write back; financial fields never via
   `Repo.update_all`/raw SQL. Editing IS allowed (`update_transaction/2`,
   `delete_transaction/1`): auditability = reproducibility from inputs, not
   append-only immutability — do not build soft-delete workarounds.
7. **FX always triangulates through the EUR hub** (ADR-0007, `fx.ex`; ECB
   semantics `1 EUR = rate`). Never store or compute direct cross rates.
8. **Import idempotency is content-hash based** (`import_hash`): re-applying
   the same PP export is a no-op. Every import-path change must preserve this.
9. **Never edit an applied migration** — additive migrations only.

Known open invariant gaps (do NOT invent behavior — tracked as issues):
currency mismatch between transaction and account is not yet validated (#343);
no written rounding policy exists yet (#344).

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code; read the matching exemplar
  file (Framework Rules section) before writing in that layer.
- Follow ALL rules exactly as documented. When in doubt, prefer the more
  restrictive option — and AGENTS.md always wins on conflict.
- Claims here were verified against the codebase on 2026-06-11; if code and
  this file disagree, flag it in the PR instead of silently picking one.

**For Humans:**

- Keep this file lean and focused on agent needs — rules CI already enforces
  do not belong here.
- Update when the stack, gates, or domain invariants change; review
  periodically and remove rules that became obvious or mechanically enforced.

Last Updated: 2026-06-11
