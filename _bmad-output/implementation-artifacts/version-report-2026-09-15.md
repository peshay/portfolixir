# Version Report — 2026-09-15 (Sprint 11 maintenance lane)

Point-in-time dependency and toolchain picture, regenerated with
`scripts/version-report.sh` (#676) **at lane time**, before the closing act
starts (the Sprint 11 plan's Lane M: "#727 triggers reported either way,
version report written at lane time"). The lane reports what it deliberately
did not update and why; a row whose reasoning is unchanged since the
2026-09-05 report carries that reasoning again rather than a cross-reference,
so this report reads on its own.

## Applied this batch

| Dependency | From | To | Where |
| --- | --- | --- | --- |
| plug_cowboy / cowboy / cowlib | 2.7 / 2.13 / 2.19.0 | removed | Lane D (#772, the triage's D-3): Bandit 1.12.5 serves the endpoint, cowlib leaves the tree with its three advisories, the Hex pin in CI and the `mix deps.audit` ignore go with it, and the Actions are pinned to commit SHAs. |
| mint | 1.9.3 | 1.10.0 | Surfaced by `mix hex.audit` under the current Hex (2.5.1) the moment the CI pin was removed: EEF-CVE-2026-82728 (HIGH) and EEF-CVE-2026-82729 (MEDIUM). Its own commit. |
| phoenix | 1.8.13 | 1.8.14 | Patch release (2026-09-14): LongPoll timer-leak fix, nil-host handling aligned, path validation unified. The browser client is served straight from the dependency, so nothing vendored moved. |
| dialyxir (dev, test) | 1.4.7 | 1.4.8 | Supersedes Dependabot **#781**, closed with the reason. Adds the OTP 28 warning kinds the #727 move will need; `mix dialyzer` clean on the rebuilt PLT. |
| hono (mcp-server, transitive) | 4.13.0 | 4.13.8 | `npm audit` reported three moderate advisories below 4.13.5 (GHSA-gqvv-2mrq-wpjv, GHSA-g6gw-c38x-mqfc, GHSA-crvj-82cr-hjcx); the companion uses none of the affected paths, but the audit gate is the gate. Lockfile only. |
| zod / @types/node (mcp-server) | 4.5.4 / 24.13.3 | 4.6.5 / 24.13.4 | In-range `npm update`; package.json untouched. |

## Deliberately not updated

| Row | Current | Reason |
| --- | --- | --- |
| Elixir / OTP (#727) | 1.18.3 / 27 | Both halves still blocked upstream. Re-check triggers, checked 2026-09-15: an excoveralls release naming Elixir 1.20 cover support — excoveralls 0.18.5 (2025-01-26) is still the newest; an Ecto or Elixir release reconciling `Ecto.Multi`/`MapSet` opaqueness — ecto 3.14.2 and ecto_sql 3.14.0 are the versions the 2026-09-05 report saw. Neither fired. Dependabot **#775** (the `elixir:1.20.3-otp-29-slim` image) is #727's move, not a routine bump, and is closed with this reason; the re-check date is recorded on #727. |
| Node runtime image (#782; #774 was closed by Dependabot on 2026-09-11 in favour of it) | `node:24.20.0-alpine3.24` | Node 26 is *Current*, not LTS, until October 2026, and the runtime is pinned in four places by an invariant test (#728). Closed with the reason; the trigger is the LTS promotion. |
| @types/node major (mcp-server) | 24.x (latest 26.5.1) | Types follow the pinned Node 24 runtime (Sprint 8 decision, Dependabot ignore is major-wide). |
| Dockerfile `HEX_VERSION` | 2.4.2 | The image pin reproduces the image; the advisory gate runs in CI on the current Hex release, unpinned since Lane D, which is what surfaced the mint advisories. Moving the image pin is a release-image concern with no gate behind it this batch. |
| PostgreSQL image | `postgres:18-alpine` | Unchanged; the current major, and the production Compose file keeps the same image so the report script and the development stack read one line. |
| BMAD core / bmm | 6.11.0 (npm: 6.12.0) | An installer run rewrites agent files across `_bmad/**` and is its own commit group; no batch feature needed anything the release gained. |
| BMAD external modules (tea, cis, bmb, automator) | v1.19.0 / v0.2.1 / v1.8.1 pinned, automator on `main` | The pinned rows carry no runtime code and are updated when a batch needs a feature they gained. npm's `latest` tags (tea 1.26.0, cis 0.1.9, bmb 1.1.0) do not track the GitHub releases the installer pins, so the manifest SHAs, not npm, are the record. |

## Audit state at lane time

- `mix hex.audit` (Hex 2.5.1, no CI pin any more): no retired or security-advisory packages.
- `mix deps.audit`: no vulnerabilities; the ignore list is gone with cowlib.
- `mix deps.unlock --check-unused`: nothing unused.
- `npm audit` (mcp-server): 0 vulnerabilities after the hono bump (87 tests, build clean).
- `mix sobelow --skip --exit`: no findings and **no `--ignore`** — the CSP nonce and the stated HTTPS posture (Lane C, #382) cleared the two long-standing ignores.
- `mix dialyzer` (dialyxir 1.4.8, rebuilt PLT): 0 errors.
- Full suite at lane time: 2221 tests, 8 properties, 0 failures; coverage 91.2 % (gate green).
