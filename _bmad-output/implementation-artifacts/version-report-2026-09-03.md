# Version Report — 2026-09-03 (Sprint 9 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 9 plan's done-list item 5). The lane reports what it
deliberately did not update and why; the applied rows are argued in their own
commits. A row whose reasoning is unchanged since the 2026-08-22 report
carries that reasoning again rather than a cross-reference, so this report
reads on its own.

## Applied this batch

| Dependency | From | To | Where |
| --- | --- | --- | --- |
| phoenix (Dependabot #745) | 1.8.12 | 1.8.13 | own commit; pulls phoenix_pubsub 2.2.0 → 2.3.0 transitively |
| telemetry_metrics (Dependabot #743) | 1.1.0 | 1.2.0 | own commit |
| actions/setup-node (Dependabot #742) | v5 | v7 | own commit; the Node 24 pin (CI `node-version`, `engines.node`, `node:24-alpine`) is untouched — the four-place pin invariant stays green |
| phoenix_live_view | 1.2.10 | 1.2.11 | one maintenance commit with the two rows below |
| req | 0.7.3 | 0.7.4 | maintenance commit |
| ecto (transitive) | 3.14.1 | 3.14.2 | maintenance commit; bug fixes only (2026-08-14), nothing on the #727 opaqueness question |
| tsx (mcp-server, in range) | 4.23.12 | 4.23.13 | lockfile-only commit |
| zod (mcp-server, in range) | 4.4.3 | 4.5.4 | lockfile-only commit |
| fast-uri, qs and three more transitive npm rows | — | in range | **already on `main`** as the first commit of the plan PR (#753): the npm audit finding that turned `main` red on run 1460 (four high, two moderate advisories) |

Every applied row compiled with `--warnings-as-errors` and passed the suites
named in its commit; the full gate set runs on the batch head before the PR
is promoted.

## Deliberately not updated

| Dependency | Current | Available | Reason |
| --- | --- | --- | --- |
| Elixir (CI, Dockerfile, PLT key) | 1.18.3 | 1.20.4 (2026-08-28) | **blocked upstream, re-checked this lane**: the trigger is "an excoveralls release naming Elixir 1.20 cover support", and excoveralls is still 0.18.5 (2025-01-26) — under 1.20.x `:cover` cannot instrument the BEAMs, so `mix coveralls.json` and with it the coverage gate cannot run (CI evidence recorded on #727 from Sprint 8's attempt). The 1.20.4 changelog is a security fix (`List.to_string/1` recursion, CVE-2026-75758) plus bug fixes; nothing on cover. The CVE does not reach this codebase's inputs in a way the pinned 1.18.3 exposes differently from 1.20.3, and it does not clear the blocker. Trigger not fired; #727 stays open |
| OTP | 27 | 29.0.6 | **blocked upstream, unchanged**: OTP 28 reinstated strict opaqueness checking in dialyzer, and under 28.x/29.x the analysis reports 68 identical `call_without_opaque` false positives on idiomatic `Ecto.Multi`/`MapSet` code (the `names` field resolves to the stdlib's opaque `:sets.set/1`). The trigger is "an Ecto or Elixir release reconciling those specs": ecto 3.14.2 (applied above) is bug fixes only and gettext 1.0.2 is unchanged, so no release clears it, and baselining 68 dialyzer ignores would weaken the gate. Trigger not fired; #727 stays open |
| cowlib (transitive) | 2.19.0 | none | unchanged: three advisories (two MEDIUM, one LOW), 2.19.0 still the newest release, nothing to update to; posture documented in `ci.yml`'s `deps.audit` ignore list. Re-checked this lane via `mix hex.audit` — no fixed release has appeared |
| @types/node (mcp-server, Dependabot #744) | 24.13.3 | 26.4.1 | **declined, now major-wide**: the runtime is pinned to the 24 LTS line (CI, `engines`, Dockerfile) and types follow the pinned runtime major; 24.13.3 is the newest 24.x. Sprint 8 ignored one version (26.2.0) and the bot reopened the same major as 26.3.0, so `dependabot.yml` now ignores `@types/node` semver-major updates; the PR is closed with the reason. It becomes a candidate when the runtime pin moves |
| PostgreSQL | 18 (CI and compose) | 18.x current | unchanged: current stable major, floating major tags pick up patches without a commit — no action |
| BMAD core + bmm | 6.11.0 | 6.11.0 (`next` 6.11.1-next.44) | up-to-date; the `next` dist-tag is a prerelease and not a candidate |
| BMAD external `tea` | v1.19.0 (sha `8734d51f`) | 1.23.x on npm (2026-08-22 review) | unchanged decision, restated: the 1.22.0 switch of skill activation to `uv run` is a new machine prerequisite, and 1.23.0's write-time enforcement hook edits the target project's `.claude/settings.json` — both change the operator's environment and belong in an owner-run `bmad update` with `uv` installed, not in an agent batch. No security-relevant fix in the range forces urgency. **Recommendation to the owner stands: install `uv`, then `bmad update` for tea** |
| BMAD external `cis` | v0.2.1 (sha `07a8dd03`) | npm dist-tag not comparable | unchanged: installed from its git repo by sha; the npm `latest` reads *older* than the install, so it is not a comparator, and this session's GitHub scope does not reach the repo's tags. Held |
| BMAD external `bmb` | v1.8.1 (sha `3410d952`) | npm dist-tag not comparable | same shape as `cis` — repo-by-sha install, npm dist-tag not comparable. Held |
| BMAD external `automator` | `main` @ `0b94fd7`, channel `next` | — | unchanged decision from 2026-08-19: upstream deprecated the module at 6.10 in favour of `bmad-loop`, the installer cannot pin what the plan asked to pin, and the manifest records the installed sha, so the state is reproducible. The exposure is at the next owner-run `bmad update`; hand-editing a generated manifest would break silently, which is worse |

## Security posture

- `mix hex.audit` (EEF advisory feed): the three cowlib advisories above, no
  others; no fixed release exists for any of them.
- `mix deps.audit` — the gate CI runs, with its documented ignore list: **no
  vulnerabilities found**.
- `mix deps.unlock --check-unused`: no unused lockfile entries.
- `npm audit --audit-level=high` (mcp-server): **0 vulnerabilities**, on
  `main` since the plan PR's lockfile fix and still after this lane's rows.

## Dependabot rows open at batch start

| PR | Row | Outcome |
| --- | --- | --- |
| #742 | actions/setup-node 5 → 7 | applied as its own commit; PR closed with a pointer |
| #743 | telemetry_metrics 1.1.0 → 1.2.0 | applied as its own commit; PR closed with a pointer |
| #744 | @types/node 24 → 26.3.0 | declined; `dependabot.yml` ignores the major; PR closed with the reason |
| #745 | phoenix 1.8.12 → 1.8.13 | applied as its own commit; PR closed with a pointer |

## Limitations

The GitHub API is out of this session's scope for repositories other than
this one, so the Elixir and OTP "latest" figures come from the Hex build
index (`builds.hex.pm`) and the Elixir changelog from the raw release file;
the OTP 29.0.6 release notes were not read — the trigger #727 names is an
Ecto or Elixir release, and neither moved on the question. The BMAD
external-module comparison still has no trustworthy remote comparator from
this session for `cis` and `bmb` (repo-by-sha installs, npm dist-tags
demonstrably wrong).
