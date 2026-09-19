# Version Report — 2026-09-19 (Sprint 13 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 13 plan's Lane M). The lane reports what it deliberately did
not update and why; a row whose reasoning is unchanged since the last report
carries that reasoning again rather than a cross-reference, so this report
reads on its own.

## Applied this batch

| What | From → to | Why now |
| --- | --- | --- |
| `phoenix_live_view` | 1.2.11 → 1.2.12 | A patch release inside the declared `~> 1.2` range. The whole suite and the full gate set pass on it, and the batch's largest surface area is LiveViews, so being one patch behind on the library those surfaces are reviewed against is the wrong place to save a commit. |
| `@types/node` (mcp-server, dev) | 24.13.4 → 24.13.6 | A patch inside the pinned `^24.0.0` range, which is where the types are held on purpose (below). `npm run build` and the companion suite pass on it. |
| `mint` (transitive: req → finch → mint) | 1.10.0 → 1.10.1 | **Security, applied after the lane closed.** EEF-CVE-2026-82672 (CVE-2026-82672, GHSA-rj5m-69wp-cxq9, MEDIUM) was published on 2026-09-19 against the 1.10.0 this tree had pinned since 2026-09-04 — an unvalidated chunk-size line tail in the HTTP/1 client enabling response smuggling against strict intermediaries on pooled connections. It turned `mix hex.audit`, and with it the `quality` job, red on a commit that changed one Markdown file: the advisory database is read at run time, so a green job goes red with nobody pushing anything. `main` carries the same pin and fails identically. The patch released the same day, so it was ported rather than waited on; `mix deps.update mint` moved one line of `mix.lock` and nothing else. |

Both land as this lane's own commit, never mixed into a feature story
(ADR-0036 clause 1).

## Dependabot

| Dependabot | Subject | Resolution |
| --- | --- | --- |
| #819 | Node image 24.20.0-alpine3.24 → 26.8.2-alpine3.24 (mcp-server) | **Closed with the reason below** — the third time the same bump is declined for the same reason (Sprint 11 closed #774, Sprint 12 closed #782). It is not a disagreement with Dependabot: the trigger is a calendar event Dependabot cannot see. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Node runtime image (#819) | `node:24.20.0-alpine3.24` | Node 26 is **Current**, not LTS, until **October 2026**, and the runtime is pinned in four places by an invariant test (#728). The trigger is the LTS promotion; checked at lane time on 2026-09-19 and it has not landed. When it does, the bump is applied as its own commit — not declined a fourth time. |
| `@types/node` major (mcp-server) | 24.13.6 (latest 26.6.2) | The types follow the pinned Node 24 runtime (Sprint 8 decision; the Dependabot ignore is major-wide). They move when the runtime moves, and moving them first would mean type-checking the companion against a runtime it does not run on. |
| Elixir / OTP (#727) | 1.18.3 / 27 | Both halves still blocked upstream, re-checked at lane time against the issue's own triggers: an excoveralls release naming Elixir 1.20 cover support (0.18.5 of 2025-01-26 is still the newest), and an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness (`ecto_sql` 3.14.0 is what the tree carries). Neither fired. The move also stays its own branch and PR, unchanged: it moves the two CI version pins, the Dockerfile base image and the Dialyzer PLT cache key together, and CI compiles with `--warnings-as-errors`, so two Elixir minors of deprecations become a body of work rather than a version-string edit. |
| Dockerfile `HEX_VERSION` | 2.4.2 | The image pin reproduces the image; the advisory gate runs in CI against the current Hex release, so nothing this batch sits behind the pin. |
| PostgreSQL image | `postgres:18-alpine` | The current major, and the production Compose file names the same image, so the report script and the development stack read one line. |
| BMAD modules | core/bmm 6.11.0; tea v1.19.0, cis v0.2.1, bmb v1.8.1 pinned by SHA; automator on `next` | The pinned SHAs are what this sprint's own workflows were run against. Moving a module mid-batch would change the process the batch is being reviewed under; the lane re-pins between batches, never inside one. |

## The picture at lane time

- **Toolchain pins (CI is authoritative):** Elixir 1.18.3, OTP 27,
  `elixir:1.18.3-otp-27`, `postgres:18-alpine`.
- **Hex:** 21 dependencies, all *Up-to-date* after the `phoenix_live_view`
  patch. `mix hex.audit` reports no retired packages and no advisories;
  `mix deps.audit` finds no vulnerabilities. No unused lockfile entries.
- **npm (mcp-server):** `npm audit` finds 0 vulnerabilities at any level. One
  outdated package, `@types/node`, held at 24.x on purpose (above).
- **BMAD install:** manifest 6.11.0 with the four external modules at the SHAs
  the report script lists.

## A gate this lane found, and where it belongs

`AGENTS.md` → "Required Local Checks" lists six commands. CI's `quality` job
runs four more that none of them cover: `mix compile --force
--warnings-as-errors`, `mix credo --strict`, `mix sobelow --skip --exit` and
`mix dialyzer --format short`. Two real findings in this batch landed green
locally and red on the branch for exactly that reason, and were fixed in
`381e222`.

This lane does **not** edit that list — the local-check set is a documented
process rule, and changing it is a decision for the close-out or an owner call,
not a maintenance-lane edit. It is recorded here so the close-out has the
evidence in front of it rather than the memory of an inconvenience.
