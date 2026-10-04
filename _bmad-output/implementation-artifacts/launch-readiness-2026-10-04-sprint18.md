# Launch readiness — 2026-10-04 (Sprint 18 close-out)

The one page the Sprint 18 plan asks for ("What the owner decides after this
sprint"). The announcement stays the owner's call (Sprint 17's D-1). Passing
both tests is necessary for it and not sufficient. The full records are in
`sprint-status.yaml`'s Sprint 18 entry. `main` is at `64b65923`, release
2026.10.7.

## The recommendation, first

**Do not announce yet.** Both tests passed, but two open decisions sit on
exactly what the 2026-09-30 research says a switcher checks first: whether
the numbers are right and whether the app can say why.

1. **#1076, a money defect on the import path.** A Portfolio Performance CSV
   export is booked with its `Betrag`, the gross value in PP's own export, as
   the cash effect.
   - A buy debits too little, by its fees and taxes; a sell, a dividend or an
     interest credit too much, by theirs.
   - The JSON v1 path and files written by `import_converter` are not
     affected.
   - Fixing it changes the import's content hash, so it needs an ADR (risk
     tier) before code.
   - It also bears on the owner's own instance if its PP history came in as
     CSV.
2. **#1081, the first figure a stranger sees is silently incomplete.** The
   Overview's total leaves out cash accounts without an exchange rate and
   positions without any price, and says so only on Wealth.

Both are small to decide and bounded to build. Settled, they make a strong
first slice of Sprint 19, ahead of the announcement.

## The two tests

| Test | Where | Result |
|---|---|---|
| The operator's first-look test (D-1, #1041) | δ's closing act, synthetic seed, German UI, 1440 and 390 px, light and dark | **PASS**. Four figures exact at both widths (total, the largest contributor this year, a closed trade's p. a., a cash balance). The planted wrong booking was deleted from the screen and the balance came back. No step needed the documentation. |
| The agent's launch test (Sprint 17 D-1) | this close-out, against the tree `main` carries | **PASS**. The agent installed, connected the companion (`book`), converted the bank export through `import_converter`, and the preview showed no warning. Three answers were exact: 13,659.20, 200.75 and 2,297.75 EUR. As in Sprint 17, the build needed a machine-local Dockerfile because this machine's egress blocks the Debian mirrors (#1092). |

## Open issues that touch money or an upgrade path

The plan expected none to be known. These are:

**Money, decision first:**

- **#1076** — a PP CSV's `Betrag` read as the cash effect.
- **#1081** — the Overview's total omits what it cannot value, unnamed.

**Money, agentic:**

- **#1055** — a foreign-currency cash balance held before its first stored
  rate counts zero, unnamed, then reads as a currency gain.
- **#1051** — cross-currency fees in the contribution's trade cost.
- **#1048** — the category result sums cost across portfolios in mixed
  currencies.

**Upgrade and install:**

- **#1042** — four more migrations call application code (agentic).
- **#1092** — the build CA does not reach the apt steps, and there is no
  documented route when the Debian mirrors are blocked (agentic).

## Open issues by label

| | Sprint 18 planning | After this close-out |
|---|---|---|
| Open issues | 119 | 117 |
| agentic | — | 73 |
| needs-decision | — | 36 |
| needs-uat | — | 2 |
| tracking | 6 | 6 |

**What happened during the sprint:**

- **Closed:** 53, of which 48 by the four lane PRs' keywords and five by hand
  (#964, #1025, #1038, and at this close-out #1024 and #1041).
- **Opened:** 51, all under Scope Lock, from the four closing acts, the
  first-look test, the surface check and the launch test.
- **Waiting on a decision among them:** six — #1076, #1079, #1080, #1081,
  #1082 and #1083.

## What Portfolixir deliberately does not do

As `docs/llms.txt` and the features page state it:

- **Trading and money:** no order-placing broker connection, no trading or
  payment, no bank or broker sync.
- **Advice:** none. The display-only rebalancing hint is arithmetic beside a
  drift figure.
- **Hosting:** no hosted service, no cloud and no tenancy.
- **Platforms and models:** no phone app, and no language model inside the
  app.
- **Readiness:** no claim of production readiness and no upgrade guarantee.

## Checks only the owner can run

- **#1023 on the live instance (D-4).** Re-import the transfer that was
  booked twice and confirm it lands once, in the right direction.
- **#330's UAT.** The PR asked for it before the merge, and the owner merged.
  If it was not run, it is the ten-minute plan in the issue, against a real
  statement on the live instance.
- **#1076 on the live instance.** Did the PP history come in as CSV or as
  JSON? If CSV, the cash balances of accounts with fees or taxes are off by
  those amounts until #1076 is decided and its correction applied.
