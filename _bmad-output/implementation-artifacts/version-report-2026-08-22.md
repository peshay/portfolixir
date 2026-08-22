# Version Report — 2026-08-22 (Sprint 8 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time** — the Sprint 8 plan makes
that explicit after Sprint 7's one process miss (the report was written at
close-out instead). The lane reports what it deliberately did not update and
why; the applied rows are argued in their own commits.

A row whose reasoning is unchanged since the 2026-08-19 report carries that
reasoning again rather than a cross-reference: a maintenance report that says
"see the previous report" stops being readable exactly when someone reads only
the latest one.

## Applied this batch

| Dependency | From | To | Where |
| --- | --- | --- | --- |
| Elixir (CI, Dockerfile, PLT key) | 1.18.3 | 1.20.3 | **attempted and reverted, blocked upstream**: under 1.20.3 the `test` job dies before any test runs — `:cover.do_compile_beam2` returns `:error` and excoveralls raises `MatchError` — so `mix coveralls.json`, and with it the coverage gate, cannot run at all. CI is the evidence: `594f452` (the last pre-bump commit) is green, `7ec41fa` (the bump) is the first red, and every commit after it inherits the failure. excoveralls 0.18.5 (2025-01-26) is the newest release, so no dependency update clears it, and disabling coverage to get green would weaken a quality gate. Re-check trigger: an excoveralls release naming Elixir 1.20 cover support. Recorded on #727, which now carries BOTH halves again |
| Node (CI `setup-node`, `engines`, Dockerfile) | unpinned / node:22 | 24 LTS | Lane D, #728 |
| phoenix | 1.8.11 | 1.8.12 | maintenance commit |
| phoenix_live_view | 1.2.9 | 1.2.10 | maintenance commit |
| req | 0.7.2 | 0.7.3 | maintenance commit |

The toolchain rows rode Lane D as their own commit groups (ADR-0036 risk-tier
shape); the three Hex patch rows are one maintenance commit with all gates
green on the new toolchain.

## Deliberately not updated

| Dependency | Current | Available | Reason |
| --- | --- | --- | --- |
| OTP | 27 | 28.5.0.5 / 29.0.5 | **blocked upstream, with evidence**: OTP 28 reinstated strict opaqueness checking in dialyzer, and under both 28.5.0.5 and 29.0.5 the analysis reports 68 identical `call_without_opaque` false positives on idiomatic `Ecto.Multi`/`MapSet` code (the `names` field resolves to the stdlib's opaque `:sets.set/1`). ecto 3.14.0 / ecto_sql 3.14.0 / gettext 1.0.2 are already the latest, so no update clears them, and baselining 68 dialyzer ignores would weaken the gate. Evidence and the re-check trigger (an Ecto/Elixir release reconciling those specs) are recorded on #727, which stays open narrowed to this move |
| cowlib (transitive) | 2.19.0 | none | unchanged: three advisories (two MEDIUM, one LOW), 2.19.0 still the newest release, nothing to update to; posture documented in `ci.yml`. Re-checked this lane via `mix hex.audit` — no fixed release has appeared |
| @types/node (mcp-server) | 24.13.3 | 26.2.0 | **decided this batch, the way #728 prescribed**: the runtime is now pinned to the 24 LTS line (CI, `engines`, Dockerfile), types follow the pinned runtime major, and 24.13.3 is already the newest 24.x. The 24 → 26 major is declined, not deferred — it becomes a candidate when the runtime pin moves |
| PostgreSQL | 18 (CI and compose) | 18.x current; 19 in beta | unchanged: current stable major, floating major tags pick up patches without a commit, 19 is beta — no action |
| BMAD core + bmm | 6.11.0 | 6.11.0 | up-to-date; `6.11.1-next.25` is a prerelease on the `next` dist-tag and not a candidate |
| BMAD external `tea` | v1.19.0 (sha `8734d51f`) | 1.23.2 on npm | **changelog reviewed this lane** (the ask the Sprint 8 plan recorded), from the 1.23.2 npm tarball's own `CHANGELOG.md`. Two findings: (1) 1.22.0 switches all skill activation to `uv run` — a new machine prerequisite (`uv` installed) replacing the bare-`python3` path that could silently mis-resolve customization; (2) 1.23.0 adds a write-time enforcement hook that the framework workflow installs into the target project's `.claude/settings.json`. Both change the operator's environment and belong in an owner-run `bmad update` with the prerequisite in place, not in an agent batch. No security-relevant fix in the range forces urgency. **Recommendation to the owner: install `uv`, then `bmad update` for tea** |
| BMAD external `cis` | v0.2.1 (sha `07a8dd03`) | npm `latest` reads 0.1.9 | unchanged: installed from its git repo by sha, so the npm dist-tag is not a comparator (it reads *older* than the install). A real comparison needs the repo's tags, which this session's GitHub scope does not reach. Held |
| BMAD external `bmb` | v1.8.1 (sha `3410d952`) | npm `latest` reads 1.1.0 | same shape as `cis` — repo-by-sha install, npm dist-tag not comparable. Held |
| BMAD external `automator` | `main` @ `0b94fd7`, channel `next` | — | unchanged decision from 2026-08-19: upstream deprecated the module at 6.10 in favour of `bmad-loop`, the installer cannot pin what the plan asked to pin, and the manifest records the installed sha, so the current state is reproducible. The exposure is at the next owner-run `bmad update`; hand-editing a generated manifest would break silently, which is worse |

## Security posture

- `mix hex.audit` (EEF advisory feed): the three cowlib advisories above, no
  others; no fixed release exists for any of them.
- `mix deps.audit` — the gate CI runs, with its documented ignore list: **no
  vulnerabilities**.
- `npm audit --audit-level=high` (mcp-server): **0 vulnerabilities**.

## Limitations

The BMAD external-module comparison still has no trustworthy remote comparator
from this session for `cis` and `bmb` (repo-by-sha installs, npm dist-tags
demonstrably wrong). `tea` is the exception this time: its npm package is the
real distribution channel, so the tarball's changelog is a valid review source,
and that review is what this lane did instead of holding blind.
