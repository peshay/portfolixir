# Story 19.2: Tax parameters, taxpayer profile and configured Freistellungsaufträge

Status: ready-for-dev

## Story

As a local portfolio maintainer,
I want the statutory numbers and my own tax situation to be data with a validity period rather than constants in the code,
so that a statement from an earlier year still validates correctly and a change in my situation does not rewrite the past.

## Acceptance Criteria

**AC-1 — `tax_parameters` is year-scoped statutory data, not constants.**
Given the seeded `tax_parameters` rows per `(jurisdiction, tax_year)`,
when the consistency engine (story 19.4) evaluates a snapshot,
then it receives the year's rates and Sparer-Pauschbetrag ceilings **as an argument** and hardcodes nothing — a pre-2023 statement resolves 801/1602 €, a 2023+ statement resolves 1000/2000 €.

**AC-2 — `tax_profiles` is effective-dated per `(holder, valid_from)`.**
Church-tax liability defaults to **not liable**, the rate is `0` in that case (enforced by DB CHECK **and** changeset), and `assessment_type` (`single`/`joint`) selects which ceiling applies.

**AC-3 — the profile in force is resolved by date, never by exact match.**
`Tax.profile_in_force(holder, on_date)` returns the row with the greatest `valid_from <= on_date`, or `nil` when none exists. Asserted with at least three profile rows and a lookup between them.

**AC-4 — profile edits never rewrite the past.**
A later profile row (or an edit to an existing one) does not change what an already-recorded snapshot reconstructs to. Story 19.3 stores the resolved rate on the snapshot row; **this story proves the resolution is a pure function of `(holder, on_date)`** — a test adds a newer profile row and asserts `profile_in_force/2` for an earlier date is unchanged.

**AC-5 — `allowance_orders` records the instructed amount per `(holder, institution, tax_year)`**, unique on that triple, `amount_granted >= 0`.

**AC-6 — all three write paths are journaled, including `tax_parameters`.**
A rate edit changes every consistency finding for that year, so it must be traceable. Each table is guard-armed; a raw write without a journal actor raises.

**AC-7 — seeded parameters survive `mix test` and the CI migration roundtrip.**
The German history is seeded by a migration (not `priv/repo/seeds.exs` — see Dev Notes §1), is idempotent on re-run, is reversible, and never overwrites a value the operator has edited.

**AC-8 — an unseeded year fails loudly.**
`Tax.fetch_parameters(jurisdiction, tax_year)` returns `{:error, :not_found}` for a year with no row. It never falls back to "the nearest year" or to a hardcoded default — a silently wrong ceiling is exactly what this story exists to prevent.

## Scope Lock — read before writing code

**IN:** three tables, three migrations, the `Portfolixir.Tax` context + three schemas, the seed, journal arming, the two meta-test list updates, the `AGENTS.md` amendment, the ADR status flip.

**OUT — do not build these, they are later stories in this epic:**

- **No JSON API routes, no controllers, no MCP tools.** That is story 19.5. Adding a `/api/v1/tax…` route here **fails `test/portfolixir/docs_test.exs`**, which scrapes every route out of `router.ex` and requires it to appear verbatim in `docs/integration/api-and-mcp.md`.
- **No LiveView, no gettext strings, no CSS.** That is story 19.6.
- **No `tax_statement_snapshots` table.** That is story 19.3.
- **No `Tax.Consistency` engine.** That is story 19.4. This story only has to make the parameter row *fetchable* so 19.4 can take it as an argument.
- **No `tax_bucket` on securities.** Deferred behind its own gate (ADR-0031 §7).

## Tasks / Subtasks

- [ ] **Task 1 — Migrations (AC: 1, 2, 5, 6, 7)**
  - [ ] 1.1 `priv/repo/migrations/20260725120000_create_tax_configuration.exs` — DDL for all three tables (`change/0`; pure schema). Column specs in Dev Notes §3.
  - [ ] 1.2 `priv/repo/migrations/20260725130000_arm_tax_journal.exs` — attach `portfolixir_require_journal_actor()` to all three tables. Copy the shape of `priv/repo/migrations/20260716130000_arm_targets_journal.exs:18-33` verbatim (`up/0` + `down/0`).
  - [ ] 1.3 `priv/repo/migrations/20260725140000_seed_tax_parameters.exs` — `up/0` calls `Tax.seed_builtin_parameters(Actor.system_job("tax_parameters_seed"))`, `down/0` calls the rollback. **Separate file from 1.1 on purpose:** the seed goes through the context on a separate Repo connection and cannot share the DDL transaction (same reason as `20260712120000` / `20260712130000`).
  - [ ] 1.4 Run `MIX_ENV=test mix ecto.migrate` — `mix test` does **not** migrate (there is no `test:` alias; see Dev Notes §1).
  - [ ] 1.5 Verify the roundtrip locally: `MIX_ENV=test mix ecto.migrate && MIX_ENV=test mix ecto.rollback && MIX_ENV=test mix ecto.migrate`.

- [ ] **Task 2 — Meta-test lists (AC: 6) — DO THIS BEFORE RUNNING THE SUITE**
  - [ ] 2.1 `test/write_actor_test.exs:63-76` — add `tax_parameters`, `tax_profiles`, `allowance_orders` to `@armed_tables`. The test asserts `armed_tables_in_db() == @armed_tables` **exactly**; arming without this edit fails the suite with a confusing diff.
  - [ ] 2.2 `test/write_actor_test.exs:16-24` — add `Portfolixir.Tax => "lib/portfolixir/tax.ex"` to `@context_files`, so every public writer is checked for actor-first shape.
  - [ ] 2.3 Do **not** touch `lib/portfolixir/journal/allowlist.ex` — it is the *exemption* list (quote/FX sync only) and is pinned by `test/portfolixir/journal/allowlist_test.exs`.

- [ ] **Task 3 — Tests first (AC: all)**
  - [ ] 3.1 `test/portfolixir/tax/parameters_test.exs` — user-story comment block, then: seeded years resolve the right ceilings (801/1602 for ≤2022, 1000/2000 for ≥2023, exact `Decimal`); unseeded year → `{:error, :not_found}`; upsert is journaled.
  - [ ] 3.2 `test/portfolixir/tax/profiles_test.exs` — default is not liable with rate 0; `church_tax_liable: false` + non-zero rate rejected; `profile_in_force/2` picks the greatest `valid_from <= date` across three rows; adding a newer row leaves an earlier lookup unchanged (AC-4).
  - [ ] 3.3 `test/portfolixir/tax/allowance_orders_test.exs` — put/list/delete, uniqueness on the triple, negative amount rejected, journaled, and `"comdirect"` vs `"Comdirect"` resolve to the SAME order (§5a).
  - [ ] 3.4 `test/portfolixir/tax/seed_test.exs` — re-running the seed is a no-op; an operator-edited row is not overwritten by a re-run.
  - [ ] 3.5 Confirm each test fails for the expected reason before writing implementation.

- [ ] **Task 4 — Schemas (AC: 1, 2, 5)**
  - [ ] 4.1 `lib/portfolixir/tax/parameters.ex`
  - [ ] 4.2 `lib/portfolixir/tax/profile.ex`
  - [ ] 4.3 `lib/portfolixir/tax/allowance_order.ex`
  - [ ] Each: `@type t :: %__MODULE__{}`, parenthesised `field(...)` calls, `@moduledoc` citing ADR-0031 §3, `unique_constraint` named to match the migration index, `check_constraint` echoing each DB CHECK.

- [ ] **Task 5 — Context (AC: 1, 3, 5, 6, 8)**
  - [ ] 5.1 `lib/portfolixir/tax.ex` with the public API in Dev Notes §4. Every writer takes `%Actor{}` first.
  - [ ] 5.2 `seed_builtin_parameters/1` + `rollback_builtin_parameters/1`, idempotent, marker-scoped.
  - [ ] 5.3 No `Date.utc_today()` inside schemas or query builders — inject `today`/`on_date` from the context shell (AR-2).

- [ ] **Task 6 — Repo contract updates (AC: 6)**
  - [ ] 6.1 `AGENTS.md` "Active Architecture" — add `Portfolixir.Tax  # recorded tax-statement snapshots and consistency checks`.
  - [ ] 6.2 `docs/decisions/0031-recorded-tax-statement-snapshots.md` — flip Status from `Proposed (… owner sign-off pending)` to `Accepted` with the sign-off date 2026-07-25 (issue #612, closed by the owner). Update the row in `docs/decisions/index.md` to `Accepted`.

- [ ] **Task 7 — Gates**
  - [ ] `mix format` · `mix test` · `mix coveralls` · `mix credo --strict` · `mix dialyzer --format short` · `mix sobelow --skip --exit --ignore Config.CSP,Config.HTTPS` · `pre-commit run --all-files`
  - [ ] mcp-server gates are **n/a** (untouched) — say so explicitly in the PR.

## Dev Notes

### §1 — Two environment facts that will bite you

1. **`mix test` does not migrate.** `mix.exs:73-79` defines only `setup`, `ecto.setup`, `ecto.reset` — there is no `test:` alias, and `test/test_helper.exs` is just `ExUnit.start()` + sandbox mode. After adding migrations you must run `MIX_ENV=test mix ecto.migrate` yourself. CI does it explicitly (`.github/workflows/ci.yml:74-75`).
2. **`priv/repo/seeds.exs` is never run by `mix test` or by CI** — it is wired only into the `ecto.setup` alias, and its current content is two comment lines. **Therefore the German tax history must be seeded by a migration**, or every test and every CI run sees an empty `tax_parameters` table. The `migration-roundtrip` job runs `migrate → rollback → migrate` (`ci.yml:246-248`), so the seed migration needs a working `down/0` and an `up/0` that is safe to re-apply.

### §2 — The journal contract (AC-6)

`Portfolixir.Journal` is the only module that writes `audit_journal`. The write shape, copied from the exemplar `lib/portfolixir/portfolios/snapshots.ex:30-38`:

```elixir
def create_x(%Actor{} = actor, attrs) do
  Multi.new()
  |> Multi.insert(:x, X.changeset(%X{}, attrs))
  |> Journal.record(actor, resource_type: "tax_parameters", operation: :create, source: :x)
  |> Repo.transaction()
  |> normalize()
end

defp normalize({:ok, %{x: x}}), do: {:ok, x}
defp normalize({:error, :x, changeset, _changes}), do: {:error, changeset}
```

- `Journal.record/3` opts: `:resource_type` (required, free string — there is **no** closed code list), `:operation` (closed: `:create | :update | :delete | :upsert`), `:source` (the Multi step name), `:before` (required for update/delete).
- Use resource types `"tax_parameters"`, `"tax_profile"`, `"allowance_order"`.
- `Journal.Serializer` is **generic** — it reflects over `schema.__schema__(:fields)`; no per-schema clause needed. It handles `Decimal` (→ string), `Date` (→ ISO-8601), and lists element-wise, so `{:array, :decimal}` serializes fine. Any type outside its table raises `ArgumentError` at journal time — do not introduce custom Ecto types here.
- Arming is what makes the guarantee real: after `20260725130000`, any write to these tables that does not go through `Journal.record/3` raises `requires a journal actor`.
- **Counter-precedent, deliberately not followed:** `depot_snapshots` is journaled at the context seam but *not* armed. These tables are armed because ADR-0031 makes traceability of a rate edit load-bearing.

### §3 — Column specs (AC: 1, 2, 5)

All money and rate columns are `:decimal` with explicit `precision`/`scale`. `test/invariants/decimal_persistence_test.exs` AST-scans schemas and migrations and fails on any `:float`, including `{:array, :float}`.

**`tax_parameters`** — unique index on `(jurisdiction, tax_year)`

| Column | Type | Constraints |
|---|---|---|
| `jurisdiction` | `:string, size: 2, null: false` | CHECK `jurisdiction = 'DE'` (widen when a second jurisdiction lands) |
| `tax_year` | `:integer, null: false` | CHECK `BETWEEN 1990 AND 2200` (int4 bound discipline, ADR-0028 fix round) |
| `capital_gains_tax_rate` | `:decimal, precision: 6, scale: 4, null: false` | CHECK `>= 0 AND < 1` |
| `solidarity_surcharge_rate` | `:decimal, precision: 6, scale: 4, null: false` | CHECK `>= 0 AND < 1` |
| `saver_allowance_single` | `:decimal, precision: 20, scale: 6, null: false` | CHECK `>= 0` |
| `saver_allowance_joint` | `:decimal, precision: 20, scale: 6, null: false` | CHECK `>= 0` |
| `church_tax_rates` | `{:array, :decimal}, null: false, default: []` | see note below |
| `built_in` | `:boolean, null: false, default: false` | seed marker |

> **`church_tax_rates` note:** Ecto's Postgres adapter emits `numeric[]` for `{:array, :decimal}` and does **not** apply `precision`/`scale` to the element type — do not pass those options, they are silently ignored. Element validation lives in the changeset (`0 <= r < 1` for every element). This column is prefill/advisory input only; nothing computes with it in this story.

**`tax_profiles`** — unique index on `(lower(holder), valid_from)`, see §5a

| Column | Type | Constraints |
|---|---|---|
| `holder` | `:string, null: false` | trimmed + whitespace-collapsed, non-empty, case-preserving (§5a) |
| `valid_from` | `:date, null: false` | — |
| `jurisdiction` | `:string, size: 2, null: false, default: "DE"` | CHECK `= 'DE'` |
| `church_tax_liable` | `:boolean, null: false, default: false` | **not liable is the default** |
| `church_tax_rate` | `:decimal, precision: 6, scale: 4, null: false, default: 0` | CHECK `>= 0 AND < 1` **and** CHECK `church_tax_liable OR church_tax_rate = 0` |
| `assessment_type` | `:string, null: false, default: "single"` | CHECK `IN ('single','joint')` + `validate_inclusion` |
| `note` | `:text` | — |

**`allowance_orders`** — unique index on `(lower(holder), lower(institution), tax_year)`, see §5a

| Column | Type | Constraints |
|---|---|---|
| `holder` | `:string, null: false` | trimmed + whitespace-collapsed, non-empty, case-preserving (§5a) |
| `institution` | `:string, null: false` | same normalisation (§5a) |
| `tax_year` | `:integer, null: false` | CHECK `BETWEEN 1990 AND 2200` |
| `amount_granted` | `:decimal, precision: 20, scale: 6, null: false` | CHECK `>= 0` |
| `note` | `:text` | — |

CHECK house style — `create(constraint(:table, :name_check, check: """ … """))` with a comment tying it to the Elixir-side list; see `priv/repo/migrations/20260720120000_add_split_transaction_kind.exs:33-70`.

### §4 — Public context API (`lib/portfolixir/tax.ex`)

```elixir
# parameters
Tax.fetch_parameters(jurisdiction, tax_year)     # {:ok, %Parameters{}} | {:error, :not_found}
Tax.list_parameters(opts \\ [])                  # filter: :jurisdiction
Tax.upsert_parameters(%Actor{}, attrs)
Tax.seed_builtin_parameters(%Actor{})            # idempotent
Tax.rollback_builtin_parameters(%Actor{})        # marker-scoped

# profiles
Tax.profile_in_force(holder, %Date{} = on_date)  # %Profile{} | nil
Tax.list_profiles(holder)                        # newest valid_from first
Tax.create_profile(%Actor{}, attrs)
Tax.update_profile(%Actor{}, profile, attrs)
Tax.delete_profile(%Actor{}, profile_or_id)

# allowance orders
Tax.list_allowance_orders(opts \\ [])            # filter: :holder, :tax_year, :institution
Tax.put_allowance_order(%Actor{}, attrs)
Tax.delete_allowance_order(%Actor{}, order_or_id)
```

**AC-8 is a design rule, not just a return value:** `fetch_parameters/2` must not fall back to a neighbouring year or to a default. An unseeded year is an error the caller handles.

### §5 — The as-of idiom (AC-3) — do not invent a new one

The repo already has exactly this pattern, named `at_or_before/2` in two places. Copy it.

`lib/portfolixir/fx.ex:52-60`:

```elixir
def at_or_before(base, quote, %Date{} = date) do
  base_quote(base, quote)
  |> where([r], r.date <= ^date)
  |> order_by([r], desc: r.date)
  |> limit(1)
  |> Repo.one()
end
```

`lib/portfolixir/catalog/quotes.ex:72-79` is the same shape for quotes. `profile_in_force/2` is this query over `tax_profiles` filtered by `holder`, ordered `desc: valid_from`, `limit(1)`.

**Nearest-earlier-or-equal, never exact match.** A profile written on 2020-03-01 governs 2024 until a newer row exists.

### §5a — Decide identity normalisation HERE, or stories 19.3–19.5 will diverge

`holder` and `institution` are free text (ADR-0031 accepts this — Portfolixir has
no institution entity). Three tables key off them, across three stories:

- `tax_profiles(holder, valid_from)` — this story
- `allowance_orders(holder, institution, tax_year)` — this story
- `tax_statement_snapshots(institution, holder, tax_year, as_of)` — story 19.3

Story 19.4's checks **join across these** (C7 compares an order against a
snapshot for the same holder + institution; C8 sums orders per holder). If
`"comdirect"` and `"Comdirect"` land as different rows, C7 silently reports a
missing instruction and C8 under-counts the allowance budget — a wrong advisory
that looks like a real finding.

**Binding rule for this story, so 19.3 inherits it:** normalise on write in the
changeset — trim leading/trailing whitespace, collapse internal runs of
whitespace to one space, reject empty. Store **case-preserving** (the operator's
capitalisation is theirs), and make the unique indexes **case-insensitive** so
`"comdirect"` and `"Comdirect"` collide instead of diverging:

```elixir
# in the migration
create(unique_index(:allowance_orders, ["lower(holder)", "lower(institution)", :tax_year],
  name: :allowance_orders_holder_institution_year_index))
create(unique_index(:tax_profiles, ["lower(holder)", :valid_from],
  name: :tax_profiles_holder_valid_from_index))
```

Lookups (`profile_in_force/2`, the order filters) must match with the same
case-folding, e.g. `where([p], fragment("lower(?)", p.holder) == ^String.downcase(holder))`.
Add a test asserting `"comdirect"` and `"Comdirect"` are the same order.

### §6 — Seeding (AC-7)

House pattern, synthesised from `20260712130000_seed_portfolio_scope_buckets.exs` and `lib/portfolixir/classifications.ex:461-620`:

1. Seed **through the context**, never raw SQL — the tables are armed, so the write must carry an actor and commit with its journal entry.
2. Actor: `Actor.system_job("tax_parameters_seed")`.
3. Idempotent: pre-check by `(jurisdiction, tax_year)` and `on_conflict: :nothing`. A re-run must insert nothing and produce no journal noise.
4. **Never overwrite an operator edit.** Follow the classifications precedent (`classifications.ex:596-611`, "backfill … but never overwrite a user-chosen one"): an existing row is left alone entirely.
5. Reversible, marker-scoped: `down/0` deletes only `built_in = true` rows. Rows the operator created survive a rollback.

**Seed data — German history, `jurisdiction: "DE"`.** `capital_gains_tax_rate` `0.25`, `solidarity_surcharge_rate` `0.055` and `church_tax_rates` `[0.08, 0.09]` for every year (the 2021 partial Soli abolition did not touch Abgeltungsteuer). Allowances:

| Years | `saver_allowance_single` | `saver_allowance_joint` |
|---|---|---|
| 2009–2022 | `801.00` | `1602.00` |
| 2023–2026 | `1000.00` | `2000.00` |

Start at 2009 (introduction of the Abgeltungsteuer); end at 2026 (the current year). **Do not seed future years** — inventing a ceiling for a year whose law is not written is the same class of fabrication this epic exists to avoid. AC-8 makes the gap explicit instead.

Build every seed value with `Decimal.new("801.00")` — a string literal.
`Decimal.new/1` **raises on a float**, and `Decimal.from_float/1` belongs only at
display boundaries, never in persisted values.

**Known hazard, accepted by precedent:** a migration that calls context code
(`Tax.seed_builtin_parameters/1`) breaks if that function is later renamed or
its signature changes — migrations are otherwise immutable and self-contained.
`20260712130000_seed_portfolio_scope_buckets.exs` already accepts this trade-off
for the same reason (armed tables cannot be seeded with raw SQL). Keep the two
seed functions' signatures stable, and note them in the moduledoc as
migration-referenced.

### §7 — Test conventions

- `use Portfolixir.DataCase, async: true`.
- Actor built inline at each call site: `Actor.owner_ui()`. No factory, no setup block — there is no central fixtures module and the repo wants it that way.
- User-story comment block **directly above** the test, in this shape (from `test/portfolixir/portfolios/snapshots_test.exs:9-22`):

```elixir
  # User story (2026-07-25, ADR-0031, story 19.2):
  # As a local portfolio maintainer,
  # I want the statutory numbers and my own tax situation to be data with a
  # validity period rather than constants in the code,
  # so that an earlier year's statement still validates correctly.
  #
  # Acceptance criteria:
  # - ...
```

- Exact `Decimal` expectations: `Decimal.equal?/2` or exact serialized strings. **Never** `==` on Decimals (`Decimal.new("1.0") == Decimal.new("1")` is `false`), never float tolerance.
- Journal assertions: `Journal.list_entries(resource_type: "tax_parameters")` and match on `%{operation: :create}`.
- The seed test needs the seeded rows to exist. They do — the migration runs before the suite. Assert against the real seeded values, not a locally inserted copy.

### §8 — Why this story exists (keep it in view while implementing)

ADR-0031 rejects deriving the German tax pots because Portfolixir folds cost basis as a running average while the tax code mandates strict FIFO. The whole feature therefore rests on *recorded* numbers being checkable. Checking them requires the year's law — and the Sparer-Pauschbetrag changed in 2023. A hardcoded ceiling would flag every correct transcription of a pre-2023 statement as inconsistent, which is the failure mode the epic is built to avoid. That is why the configuration layer ships **before** the snapshot table, not after.

### Project Structure Notes

- New directory `lib/portfolixir/tax/` for schemas; context module at `lib/portfolixir/tax.ex`. This mirrors `lib/portfolixir/portfolios.ex` + `lib/portfolixir/portfolios/`.
- New test directory `test/portfolixir/tax/`.
- **New bounded context.** ADR-0031 §1 argues it belongs neither in `Portfolios` (structure) nor `Catalog` (instruments) nor `Ledger` (these rows are explicitly *not* ledger events). The `AGENTS.md` amendment in Task 6.1 is what makes that non-silent.
- `Portfolixir.Settings` is **not** a home for this: it is one row per key with a plain string value, deliberately unjournaled, and not actor-first (`lib/portfolixir/settings.ex:8-9`). Structured, effective-dated, Decimal, journaled data cannot live there.
- Credo strict: new code targets the defaults (complexity 9, nesting 2), not the grandfathered baseline of 15/4. Alias ordering is enforced.

### References

- [Source: docs/decisions/0031-recorded-tax-statement-snapshots.md#3-configuration-that-changes-over-time] — the authoritative column spec, the effective-dating rationale, the instruction-vs-reality split
- [Source: docs/decisions/0031-recorded-tax-statement-snapshots.md#6-write-path-api-and-mcp] — the context API surface and the journaling rationale for `tax_parameters`
- [Source: docs/decisions/0017-append-only-audit-journal.html] + AR-1 — journal write in the same DB transaction
- [Source: docs/decisions/0003-decimal-for-money.html] — Decimal-only persistence
- [Source: _bmad-output/planning-artifacts/epics.md#story-192] — acceptance criteria this story implements; FR-36 in section I
- [Source: lib/portfolixir/portfolios/snapshots.ex] — exemplar context (actor-first, Multi + Journal, `normalize/1`)
- [Source: lib/portfolixir/portfolios/snapshot.ex] — exemplar schema (injected clock, named `unique_constraint`)
- [Source: lib/portfolixir/fx.ex:52-60] · [Source: lib/portfolixir/catalog/quotes.ex:72-79] — the `at_or_before` as-of idiom
- [Source: priv/repo/migrations/20260716130000_arm_targets_journal.exs:18-33] — journal arming shape
- [Source: priv/repo/migrations/20260712130000_seed_portfolio_scope_buckets.exs] — seed-through-context, idempotent, marker-scoped rollback
- [Source: lib/portfolixir/classifications.ex:596-611] — never overwrite an operator-set value
- [Source: test/write_actor_test.exs:16-24,63-76] — `@context_files` and `@armed_tables`, both must be updated
- [Source: test/invariants/decimal_persistence_test.exs] — no `:float` in schemas or migrations
- [Source: test/portfolixir/docs_test.exs:229,681-702] — why no API route may be added in this story
- Issue #612 — decision gate, closed by the owner 2026-07-25

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
