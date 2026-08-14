# Version Report — 2026-08-14 (Sprint 6 maintenance lane)

Point-in-time dependency and toolchain picture after the Sprint 6
maintenance-lane updates. Regenerate any time with
`scripts/version-report.sh` (#676); decisions and reasons for this batch
are recorded here and in the individual `chore(deps)` / `chore(bmad)`
commit messages.

## Applied this batch

| Dependency | From | To | Note |
| --- | --- | --- | --- |
| postgrex | 0.22.3 | 0.22.4 | fixes EEF-CVE-2026-66838 (MEDIUM, SQL injection via `:comment` in `Postgrex.stream/4`) |
| phoenix | 1.8.9 | 1.8.11 | in-range patch |
| phoenix_live_view | 1.2.8 | 1.2.9 | fixes EEF-CVE-2026-64941 (LOW, open redirect in `validate_local_url!/2`) |
| sobelow | 0.14.1 | 0.15.0 | dev/test gate tool; CI gate command re-run, no new findings |
| gettext | 0.26.2 | 1.0.2 | major; codebase already on the modern backend API, no code change |
| @types/node (mcp-server) | 24.12.4 | 24.13.3 | in-range |
| tsx (mcp-server) | 4.22.0 | 4.23.12 | in-range |
| BMAD core + bmm | 6.8.0 | 6.11.0 | #674; tea/cis/bmb converted to pinned channel at installed versions |

## Deliberately not updated

| Dependency | Current | Available | Reason |
| --- | --- | --- | --- |
| typescript (mcp-server) | 5.9.3 | 7.0.2 | two majors ahead; the 6/7 line is the native-port compiler generation — needs its own reviewed migration, not a lane decision |
| zod (mcp-server) | 3.25.76 | 4.4.3 | major; `@modelcontextprotocol/sdk` 1.30.0 depends on zod 3 (`zod-to-json-schema`), a v4 bump would fork the tree |
| @types/node (mcp-server) | 24.x | 26.x | types major should track the Node runtime baseline, which is 22.x here; bump alongside a deliberate runtime move |
| cowlib (transitive) | 2.19.0 | none | two advisories (EEF-CVE-2026-43966 MEDIUM, EEF-CVE-2026-43969 LOW) with NO fixed release; tolerated posture documented in `ci.yml`, unchanged this batch |
| Elixir/OTP toolchain | 1.18.3 / OTP 27 | 1.19.x / OTP 28 exist upstream | CI, Dockerfile and PLT cache pin 1.18.3-otp-27 together; a toolchain move is its own reviewed change (Dependency Update Policy), not a lane side effect |
| PostgreSQL | 18 (CI + compose) | — | already on the current major; no action |
| BMAD external `tea` | v1.19.0 | v1.22.2 | out of #674's scope; each external module update needs its own changelog review — now safely pinned, an explicit future decision |
| BMAD external `cis` | v0.2.1 | v0.3.0 | same as tea |
| BMAD external `bmb` | v1.8.1 | v2.2.0 | major, same as tea; conservative hold |
| BMAD external `automator` | main @ 0b94fd7 | — | upstream deprecated it (6.10) in favor of `bmad-loop`; the requested SHA pin is not installer-supported (tag pins only) and the only tag, v1.15.0, predates the installed content — see #674 notes |

## Security posture

- `mix hex.audit` (Hex 2.5.1, EEF advisory feed): only the two known cowlib
  advisories remain; the postgrex and phoenix_live_view advisories reported
  against the pre-update versions are cleared by the updates above.
- `mix deps.audit`: clean (CI additionally carries the documented cowlib
  ignore list; see `ci.yml` comments).
- `npm audit --audit-level=high`: 0 vulnerabilities.
- `mix deps.unlock --check-unused`: clean.

## Automation

`.github/dependabot.yml` (added this batch, #676) opens weekly update PRs
for Hex (`mix`), npm (`/mcp-server`) and GitHub Actions. Update PRs are
reviewed like any dependency PR and never auto-merged; the maintenance
lane stays the deciding reviewer.
