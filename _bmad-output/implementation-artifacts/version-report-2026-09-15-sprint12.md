# Version Report — 2026-09-15 (Sprint 12 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 12 plan's Lane M). The lane reports what it deliberately did
not update and why; a row whose reasoning is unchanged since the report of
earlier today carries that reasoning again rather than a cross-reference, so
this report reads on its own.

**Why a second report dated 2026-09-15.** Sprint 11's lane ran this morning and
wrote `version-report-2026-09-15.md`; Sprint 12's batch opened the same day
after that batch merged. Two lanes, two reports, one date — the file name
carries the sprint so neither overwrites the other.

## Applied this batch

Nothing. Every Hex dependency and every npm dependency of the companion is at
its latest release, both audits are clean, and the three Dependabot pull
requests the plan named were already resolved by Sprint 11's lane this morning:

| Dependabot | Subject | Resolution |
| --- | --- | --- |
| #781 | dialyxir 1.4.7 → 1.4.8 (dev, test) | Applied by Sprint 11 as its own commit (`chore(deps): dialyxir 1.4.7 → 1.4.8`); the lock carries 1.4.8, the PR is closed. Nothing left for this lane. |
| #782 | Node image 24.20.0 → 26.8 (mcp-server) | Closed 2026-09-15 with the reason below. |
| #775 | Elixir image 1.20.3-otp-29 | Owned by Sprint 11's lane as #727's move, not a routine bump; closed there and not re-decided here. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP (#727) | 1.18.3 / 27 | Both halves still blocked upstream, re-checked 2026-09-15 with Sprint 11's own triggers: an excoveralls release naming Elixir 1.20 cover support (0.18.5 of 2025-01-26 is still the newest), and an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness (ecto_sql 3.14.0 is what the tree carries). Neither fired between the two lanes. |
| Node runtime image (#782) | `node:24.20.0-alpine3.24` | Node 26 is *Current*, not LTS, until October 2026, and the runtime is pinned in four places by an invariant test (#728). The trigger is the LTS promotion, which is next month's lane, not this one. |
| `@types/node` major (mcp-server) | 24.13.4 (latest 26.6.0) | The types follow the pinned Node 24 runtime (Sprint 8 decision; the Dependabot ignore is major-wide). It moves when the runtime moves. |
| Dockerfile `HEX_VERSION` | 2.4.2 | The image pin reproduces the image; the advisory gate runs in CI on the current Hex release, which is what surfaced the mint advisories in Sprint 11. No gate sits behind the image pin this batch. |
| PostgreSQL image | `postgres:18-alpine` | The current major, and the production Compose file names the same image, so the report script and the development stack read one line. |
| BMAD modules | core/bmm 6.11.0; tea v1.19.0, cis v0.2.1, bmb v1.8.1 pinned by SHA; automator on `next` | The pinned SHAs are what the sprint's own workflows were run against. Moving a module mid-batch would change the process the batch is being reviewed under; the lane re-pins between batches, not inside one. |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.3, OTP 27,
  `elixir:1.18.3-otp-27`, `postgres:18-alpine`.
- **Hex:** 22 dependencies, all *Up-to-date*. `mix hex.audit` reports no retired
  packages and no advisories; `mix deps.audit` finds no vulnerabilities. No
  unused lockfile entries.
- **npm (mcp-server):** `npm audit` finds 0 vulnerabilities at any level. One
  outdated package, `@types/node`, held at 24.x on purpose (above).
- **BMAD install:** manifest 6.11.0 with the four external modules at the SHAs
  listed above.

## Lane scope beyond dependencies

The lane also moved the review's seed script into the product tree as
`priv/demo/finding_surfaces_seed.exs` (Sprint 12's D-4) and made it idempotent:
a second run on a seeded database adds no row. Verified on a throwaway database
— first run 10 securities, 17 transactions, 4 research entries, 2 buckets, 1
view, 1 snapshot, 1 tax profile and statement; second run identical. The
walkthrough conditions and the command now live in `priv/demo/README.md` and in
the design-language `review-rubric.md`, so the next batch's closing act finds
them where it looks rather than in one review's mockup folder.
