# Version Report — 2026-09-05 (Sprint 10 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 10 plan's execution notes). The lane reports what it
deliberately did not update and why; a row whose reasoning is unchanged since
the 2026-09-03 report carries that reasoning again rather than a
cross-reference, so this report reads on its own.

## Applied this batch

| Dependency | From | To | Where |
| --- | --- | --- | --- |
| (none) | — | — | `mix hex.outdated` reports every Hex row up to date two days after the Sprint 9 lane; no Dependabot PR was open at batch start or at lane time. |

Not a dependency but recorded here because the lane owns the image pins:
the MCP companion image moved from the floating `node:24-alpine` to the
exact `node:24.20.0-alpine3.24` (#761), and the new production image
(`Dockerfile.release`, #760) builds on `elixir:1.18.3-otp-27-slim` and runs
on `debian:bookworm-slim`. Dependabot's `docker` ecosystem now covers `/`
and `/mcp-server`, so the tags move by PR rather than by hand.

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP (#727) | 1.18.3 / 27 | Both halves still blocked upstream. Re-check triggers (an excoveralls release naming Elixir 1.20 cover support; an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness): neither fired — excoveralls 0.18.5 and ecto 3.14.2 are the same versions the 2026-09-03 report saw. |
| cowlib | 2.19.0 | Still the newest release; the three advisories (EEF-CVE-2026-43966 and -43971 MEDIUM under Hex 2.5, -43969 LOW under the pinned Hex 2.4.1) remain without a fixed version. The triage's D-3 replaces waiting with the Bandit swap, filed as **#772** for the next batch; the Hex pin in CI and its ignore stay until then. |
| PostgreSQL image | `postgres:18-alpine` | Unchanged; the production Compose file keeps the same image so `scripts/version-report.sh` and the development stack read one line. |
| @types/node (mcp-server) | 24.x | Types follow the pinned Node 24 runtime (Sprint 8 decision, Dependabot ignore is major-wide). |
| BMAD and external modules | as installed | No module update was offered by the installer this batch; unchanged from the 2026-09-03 report, restated rather than cross-referenced: the tea/cis/bmb rows carry no runtime code and are updated when a batch needs a feature they gained. |

## Audit state at lane time

- `mix hex.audit` (Hex 2.4.1, the CI pin): cowlib 2.19.0 — EEF-CVE-2026-43969 (LOW), no retirements.
- `mix deps.audit`: no vulnerabilities beyond the documented cowlib ignore.
- `npm audit --omit=dev` (mcp-server): 0 vulnerabilities (84 tests, build clean).
- `mix sobelow --skip --exit --ignore Config.CSP,Config.HTTPS`: no findings. One finding surfaced during the batch (CSRF via action reuse on the logout route, Sobelow `Config.CSRFRoute`) and was fixed before this report: the GET renders a one-button page and only the POST changes state.
