# Version Report — 2026-08-19 (Sprint 7 maintenance lane)

Point-in-time dependency and toolchain picture at the close of the Sprint 7
batch, regenerated with `scripts/version-report.sh` (#676). The Sprint 7 plan
requires the lane to report **what it deliberately did not update and why,
including the toolchain and BMAD rows** — those rows are the reason this file
exists, since the applied rows were already argued in their own commits.

A row whose reasoning is unchanged since the 2026-08-14 report carries that
reasoning again rather than a cross-reference: a maintenance report that says
"see the previous report" stops being readable exactly when someone reads only
the latest one.

## Applied this batch

| Dependency | From | To | Where |
| --- | --- | --- | --- |
| actions/checkout | v5 | v7 | `9e5c374` |
| actions/setup-python | v5 | v7 | `9e5c374` |
| actions/upload-artifact | v4 | v7 | `9e5c374` |
| actions/cache | v4 | v6 | `9e5c374` |
| codecov/codecov-action | v5 | v7 | `9e5c374` |
| zod (mcp-server) | 3.25.76 | 4.4.3 | `1b7b3d2` |
| typescript (mcp-server) | 5.9.3 | 7.0.2 | `1b7b3d2` |

Both commits argue their own rows. The short version: each action major was
checked against *how this repo uses it* rather than against "CI is green" —
`cache` still emits `cache-hit`, so the build-the-PLT-only-on-a-miss branch
still works, and `upload-artifact` v7's name change only bites under
`archive: false`, which this repo does not set. The two npm majors were
review-and-report rows that proved trivial on inspection and were therefore
applied rather than deferred.

## Deliberately not updated

| Dependency | Current | Available | Reason |
| --- | --- | --- | --- |
| Hex (21 deps) | all current | — | nothing to do; `mix hex.outdated` reports every dependency up-to-date, which is also why Dependabot's `mix` ecosystem opened no PRs |
| cowlib (transitive) | 2.19.0 | none | **three** advisories now, not the two the CI comment named: EEF-CVE-2026-43966 (MEDIUM, HTTP response splitting), EEF-CVE-2026-43971 (MEDIUM, link-header directive smuggling, new since 2026-08-14) and EEF-CVE-2026-43969 (LOW). 2.19.0 (2026-07-28) is still the newest release, so there is nothing to update to; the tolerated posture is documented in `ci.yml` and the comment was corrected in `9e5c374` |
| @types/node (mcp-server) | 24.13.3 | 26.2.0 | types should describe the runtime the code runs on, and this project pins none — no `actions/setup-node`, no `engines`. Bumping types two majors ahead of an unknown runtime lets the build typecheck against APIs that may not exist at run time. The missing pin is the real defect; filed as #728, and this row is decidable once it lands |
| Elixir / OTP | 1.18.3 / OTP 27 | 1.19.x / OTP 28 upstream | CI, the Dockerfile and the PLT cache key pin `1.18.3-otp-27` together, so a bump moves three things at once and is its own reviewed change, not a lane side effect. Filed as #727 |
| PostgreSQL | 18 (CI and compose) | 18.6 current; 19 in beta | already on the current stable major, and the pins are floating major tags (`postgres:18`, `postgres:18-alpine`), so patch releases arrive without a commit. 19 is beta — not a candidate for a data store. **No action** |
| BMAD core + bmm | 6.11.0 | 6.11.0 | up-to-date; `6.11.1-next.24` is a prerelease on the `next` dist-tag and not a candidate |
| BMAD external `tea` | v1.19.0 (sha `8734d51f`) | 1.23.2 on npm | four minors behind, one more than at the last report (1.22.2 then). Held for the same reason as then: each external module update needs its own changelog review, and it is safely sha-pinned in the meantime, so the hold costs reproducibility nothing |
| BMAD external `cis` | v0.2.1 (sha `07a8dd03`) | npm `latest` reads 0.1.9 | **the comparator disagrees with the install**, and that is the finding: the module is installed from its git repo by sha, so the npm dist-tag is not a version this install can be measured against. Held; a real comparison needs the repo's tags, which this session's GitHub scope does not reach |
| BMAD external `bmb` | v1.8.1 (sha `3410d952`) | npm `latest` reads 1.1.0 | same shape as `cis` — installed-from-repo by sha, npm dist-tag not comparable. Held |
| BMAD external `automator` | `main` @ `0b94fd7`, channel `next` | — | the row the plan singled out, because it tracks a moving branch. **Decision: leave it, and the reason is not inertia.** Upstream deprecated the module at 6.10 in favour of `bmad-loop`, and the SHA pin the plan asks for is not installer-supported (the installer pins tags, and the only tag — v1.15.0 — predates the installed content). The manifest already records the installed sha, so the *current* state is reproducible; the exposure is at the next `bmad update`, which is an owner-run installer operation. Hand-editing a generated manifest to fake a pin would break silently, which is worse than the exposure it pretends to close |

## Security posture

- `mix hex.audit` (EEF advisory feed): the three cowlib advisories above, no
  others. No fixed release exists for any of them.
- `mix deps.audit` — the gate CI runs, with its documented ignore list: **no
  vulnerabilities found.** The asymmetry is worth stating plainly, because it
  is why both commands are run: only the LOW is in `mix_audit`'s database, so
  the two MEDIUMs are visible to `mix hex.audit` alone.
- `npm audit --audit-level=high` (mcp-server): 0 vulnerabilities, under both
  new npm majors.
- No ignore was added and no gate threshold was moved this batch.

## Method note

The BMAD external rows are compared against npm dist-tags because that is the
comparator available from this session; for `cis` and `bmb` that comparator is
demonstrably wrong (it reports versions *older* than what is installed), since
those modules come from their git repos by sha. Recording the limitation is
the point — a report that quietly compared against the wrong source would read
as "checked" while checking nothing.
