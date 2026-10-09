# Launch readiness, version 3 — 2026-10-09 (Sprint 20 close-out)

This is the one page the Sprint 20 plan asks for ("What the owner decides
after this sprint"), in the shape of `launch-readiness-2026-10-07-sprint19.md`.
The announcement stays the owner's call (Sprint 17's D-1). Passing all four
exit criteria is necessary for it, and not sufficient. The full records are in
`sprint-status.yaml`'s Sprint 20 entry.

Under ADR-0026's two-PR amendment, the sprint ran as one sprint PR with γ
split off as a stacked PR (plan D-9):

- **#1184** (Lane M, α, β) is merged: `main` is at `86c577ec`, release
  2026.10.13, API contract version 16.
- **#1215** (γ and this close-out) merges by rebase after it, with contract
  version 17. The next planning PR records that merge and its release.

## The recommendation, first

**Announce to the small group the launch path names, once #1215 merges.**
All four exit criteria pass then, and for that case the plan names the
recommendation: "the summary recommends announcing to the small group the
launch path names: self-hosters who run LLM agents, in the self-hosting and
Portfolio Performance communities. The UI batch (D-13) then becomes the first
sprint of the widening phase."

This recommends; it does not decide. The four criteria are necessary and not
sufficient, and the owner weighs what they do not cover (below).

**What the recommendation rests on:**

- **Every H issue the plan named closes by keyword:**
  - the cash a switcher's first import books (#1098, #1118, #904, #1120);
  - what the ledger reports about it (#1108, #1107, #1142, #1101, #1124);
  - a stranger's install (#1132, #1172).
- **The four round trips passed** on synthetic data in the German UI. The
  rates passed by their integration test, because the ECB's host answers 403
  from this session.
- **The build route no longer depends on one machine.**
  - CI's `compose-smoke` builds and boots the release images on every change
    that can change them.
  - The agent's launch test passed from source, with three exact answers.
- **84 open issues once #1215 merges**, against 132 at Sprint 19's
  close-out. The decision pass answered all 46 open questions at the
  planning merge, and closed 33 of the issues by hand. The build, the
  closing acts and the launch test filed 31 issues, against 51 closed by
  the sprint's keywords.

**What it does not cover:**

- **Seven open money decisions**, all filed during this sprint, among them:
  - #1198: FIFO lots that mix price currencies;
  - #1205: a re-export whose hashed fields drifted stays wrong silently.

  Two more agentic issues give a money figure that is wrong or unstated:
  #1209 and #1212. None of them changed a launch-test answer.
- **The upgrade of an existing instance.** No CI job tests it.
- **Production readiness.** None is claimed, and there is no upgrade
  guarantee.

**One order is worth keeping:** the owner's upgrade of the live instance
(check 2 below) before the announcement. It is the one route no CI job
tests, and everyone who installs after the announcement meets it at their
first upgrade.

**If #1215 does not merge**, criteria 1 and 4 do not pass: #1132 and #1172
stay open, and so do 118 issues.

## The four exit criteria

| Criterion | Result | Record |
|---|---|---|
| 1. Every H issue closed by keyword | **PASS once #1215 merges** | α's #1098, #1118, #904 and #1120 and β's #1108, #1107, #1142, #1101 and #1124 closed with #1184's merge. γ's #1132 and #1172 close with #1215's. |
| 2. The switcher's round trips, on synthetic data in the German UI | **PASS** | **1, the negative tax:** Test-Cash **181,49 EUR**; the sale and its PP CSV twin **1.120,00 EUR**; a second drop books nothing. An export imported on the release before reads 181,50 and 1.145,00 EUR, and **181,49 and 1.120,00 EUR** after the correction. **2, the rename:** the renamed row shows no prefill and Apply waits; mapped onto its old account, the drop books nothing. **3, the rates:** the integration test with the fake provider passes (14 tests, 0 failures); the ECB's host answers 403 from this session, so the live fetch is unproven here. **4, the cross-currency trade:** the realized-gains read **151**; the Overview's closed-trades card and Income's realized list **+151,00 EUR**; Test-Cash moved 957,00 − 806,00; the Trades tab **+188,75**, identity 1's figure in the trade's currency (USD). |
| 3. The build route, in two halves (D-3 and its note of 2026-10-08) | **PASS** | **The build:** CI's `compose-smoke` runs `docker compose up --build -d` on a GitHub runner, waits for the app's health and the companion, and reads the page, an API read and a companion tool call. It was green on `63c0aee9` (job 113512945741), on `f67501f5`, on `4a9ee85e` (with the Debian 20261005 images) and in `main`'s CI 1773 after #1184's merge. **The agent's part:** the launch test from source passed, with three exact answers (below). **Not covered:** the job runs on amd64 and starts on an empty database, so the upgrade of an existing volume is the owner's. |
| 4. Fewer than 100 open issues | **PASS once #1215 merges** | **118 open** after #1184's merge. #1215 closes 34, all open: **84** after it. D-4 answered every `needs-decision` issue open at the planning, at the planning merge. Nothing was withheld to make the count (D-15). |

### The agent's launch test, step by step

The run: 2026-10-09, under #998's protocol, against #1215's tree at
`bb654015` (γ stacked on #1184, before the launch test's documentation
commits).

The agent under test was a fresh Claude Code subagent:

- It worked in an export of that tree (git archive), without
  `test/fixtures/launch_test/` and without git history.
- The user's CSV lay outside the export.
- It was given `README.md`, `docs/llms.txt` and the pages they link.
- It was told only the environment's facts: no Docker daemon, PostgreSQL 16
  with its default login, the ports, and the package registries reachable.

The tree's checksum was unchanged after the run (3,277 files).

1. **Setup.** The agent took "Run from source":
   - a database of its own, on port 4300;
   - the UI password set (a generated one);
   - the server detached.

   It built the companion with `npm ci --ignore-scripts`. Node 22 gave an
   engine warning, and the build worked.
2. **The agent's part.**
   - It connected the companion over stdio with the `book` profile: 114
     tools, contract version 17.
   - It used `first_setup` read-only. The instance was empty, and nothing was
     created.
   - Through `import_converter` it chose Portfolio Performance JSON v1, as
     the prompt's rule says for an export with ISINs. A deterministic
     converter wrote nine bookings.
   - It ran the converter's self-check on a throwaway instance, and deleted
     that instance afterwards.
3. **The drop.** The stand-in user (Playwright, German UI, logged in)
   dropped the file.
   - The preview showed no error and no warning. Its note said that no
     portfolio record exists yet and that the import creates "Default"
     (EUR).
   - Every proposal was accepted: 9 created, 0 duplicates skipped.
4. **The three questions:**
   - 13,659.20 EUR, through `portfolixir.views.valuation` without an id;
   - +200.75 EUR (235.75 − 35.00), through
     `portfolixir.cashflow.realized_gains`;
   - 2,297.75 EUR, through `cash_accounts.list`.

   All three are exact, and every answering call was a read.
5. **The audit.** The agent's transcript shows 64 + 4 tool calls. They
   touched nothing under the maintainer's checkout,
   `test/fixtures/launch_test/`, `_bmad-output/`, GitHub or the web. One
   Read was of the agent's own saved tool output.
6. **The findings: seven.**
   - **Fixed on #1215** (D-14, #1172's surface), in five documentation
     commits:
     - the from-source route's port and database settings;
     - its UI password without a prompt, and a background run and stop;
     - `llms.txt`'s "not when no Docker" against the from-source route;
     - the pages name the converter's file as the prompt does;
     - beside them, `.env.example`'s `PORT` line, which nothing reads.
   - **Filed:** #1216. The `import_converter` prompt says "with a decimal
     point" where its own example writes `"20"` shares. It was widened,
     because the prompt's description and `first_setup` still say CSV only.
   - **Not findings:**
     - Node 22 worked where 24 is declared; the declared engine stands.
     - `llms.txt` links the published pages, by design.

## Open issues that touch money or an upgrade path

The plan expected none to be known. These are known. Every one was filed
during this sprint under Scope Lock.

**Money, a decision first (`needs-decision`):**

- **#1198**: a security's FIFO lots that mix price currencies. β's fees
  basis sentence now names the case, in the payload, contract entry 16 and
  the integration guide. Before, it claimed one currency for every closed
  trade.
- **#1205**: the correction finds bookings by content hash only. A Portfolio
  Performance re-export whose hashed fields drifted is skipped as an
  economic duplicate, and is not listed for correction. It stays wrong,
  silently. The handbook says so.
- **#1194**: the correction lists and overwrites a cash amount the operator
  edited by hand since the import. The journal keeps the edit.
- **#1193**: a sale stored under the old reading, whose row the preview now
  refuses. The question is how such a stored booking is corrected. The
  preview already says the row is imported, instead of asking for it by
  hand.
- **#1188**: a PP delivery with a negative tax unit rolls back the whole
  JSON import (pre-existing). It was widened to a JSON cash transfer with a
  negative tax unit.
- **#1196**: whether a first import derives its settlement legs after the
  automatic FX history.
- **#1195**: the rename probe asks on every re-drop when the rows' hashes
  drifted.

**Money, a figure (`agentic`):**

- **#1209**: the transaction list's Betrag leaves out a fee when the API
  booked without `gross_amount`, while the balance moves by more; and it
  can show −0,00. Pre-existing.
- **#1212**: a holding's Einstand excludes fees, while a closed trade's basis
  includes them, and nothing says so. Pre-existing.
- **#1199**: the ledger accepts a trade priced in a third currency.
- **#1214**: an edit that moves a booking from account S to T deadlocks with
  a merge of S into T. Pre-existing; found by β's lock-race lens.

**Security and robustness, a decision first (`needs-decision`):**

- **#1202**: the token floor checks length only.
- **#1204**: a capped async load that hits the heap cap takes its page down.
  The page reconnects, and the guide now says so.

**Install and upgrade:**

- **No CI job tests the upgrade of an existing instance.** `compose-smoke`
  runs on amd64 and starts on an empty database (D-3's note).
- **#1215's upgrade notes**, to read before upgrading:
  - **#956:** a proxy that rewrites Host to bare `localhost` must be named in
    `PORTFOLIXIR_MCP_ALLOWED_HOSTS`. So must a browser client on another
    loopback port, by its `host:port`.
  - **#974:** a from-source `PORTFOLIXIR_API_TOKEN` shorter than 32 bytes
    stays lock-first.
  - **#898:** the guide's move onto the owner and runtime database roles
    applies to an existing instance only. Its way back is the backup it takes
    first.
- **#1189**: `release.yml`'s paths miss the two `.dockerignore` files
  (pre-existing).
- **#1216** (agentic, the launch path): the `import_converter` prompt's
  decimal-point sentence contradicts its own example. Its description and
  `first_setup` still say CSV only, while the prompt sends an export with
  ISINs to JSON v1.

## Open issues by label

| | Sprint 19 close-out | Read after #1184's merge | After #1215's merge |
|---|---|---|---|
| Open issues | 132 | 118 | 84 |
| agentic | 78 | 100 | 66 |
| needs-decision | 46 | 10 | 10 |
| needs-uat | 2 | 2 | 2 |
| tracking | 6 | 6 | 6 |

The last column is the read, less #1215's 34. All of those are open and
`agentic`.

**What happened during the sprint:**

- **Closed: 85** once #1215 merges.
  - 33 by hand at the planning merge (D-4): 27 `needs-decision` issues not
    planned, each with what reopens it; #958 completed; and #727, #895,
    #949, #1141 and #1153.
  - #973 by the planning PR's keyword.
  - 17 by #1184's keywords, and 34 by #1215's.
- **Opened: 37**, all under Scope Lock.
  - 6 at the planning merge: the ADR-0053 amendment's deferral, and the
    design pass's five findings off the lanes' surfaces.
  - 30 by the build and the three closing acts: #1185–#1214.
  - 1 by this close-out's launch test: #1216.

  The plan allowed 45 filings before the criterion failed.
- **`needs-decision` went from 46 to 10.** D-4 answered all 46 at the
  planning merge:
  - 27 were closed as not planned;
  - 17 were built this sprint;
  - 2 were answered for later.

  The ten open now are #1182 and the nine this sprint filed: #1188, #1193,
  #1194, #1195, #1196, #1198, #1202, #1204 and #1205.
- **Every filing has its area parent** (D-14), and the 31 since the
  planning merge sit under:
  - #416 (data, import, export and audit): 15;
  - #417 (portfolio structure and instrument lifecycle): 3;
  - #418 (analytics, dashboard and charts): 6;
  - #419 (LLM and MCP): 3;
  - #420 (engineering quality and process): 4.

  #991, E26's tracker, holds its 100 and closes with the announcement
  decision.

## What Portfolixir deliberately does not do

These are unchanged since version 1, as `docs/llms.txt` and the features page
state them:

- **Trading and money:** no order-placing broker connection, no trading or
  payment, and no bank or broker sync.
- **Advice:** none. The display-only rebalancing hint is arithmetic beside a
  drift figure.
- **Hosting:** no hosted service, no cloud and no tenancy.
- **Platforms and models:** no phone app, and no language model inside the
  app.
- **Readiness:** no claim of production readiness, and no upgrade guarantee.

## Checks only the owner can run

1. **#1098's correction on the live instance (D-2).**
   - D-2's count went unanswered, so the correction was built (A2).
   - A fresh JSON export from Portfolio Performance, dropped on the live
     instance, lists what it corrects: the section "Bereits importiert, mit
     anderem Betrag", with a confirm of its own.
   - The query in the plan's D-2 counts, per account, the refunds the JSON
     import split off. It gives the size to expect.
   - Before confirming, two open decisions apply:
     - a booking edited by hand since its import is listed, and would be
       overwritten (#1194);
     - a re-export whose hashed fields drifted is not listed at all (#1205).
2. **The upgrade of the live instance, by Compose.** No CI job tests an
   existing volume.
   - Take a database backup first, as the deployment guide's "Upgrade"
     section says.
   - Read #1215's upgrade notes (#956, #974, #898).
   - Pull #1215's merge and follow that section's steps: `docker compose
     pull db`, `docker compose build --pull`, `docker compose up -d`.
3. **#328 and #354**, the runs on real data (D-13): merging, renaming and
   deleting accounts and depots, and the documented backup and restore.
4. **Optional: #1136's secret path.** `ci_test` proves it under `dash` only,
   and `compose-smoke` builds without the secret. One `docker build --secret
   id=build_ca,…` on the owner's host would prove it end to end.

**A setting, not a check:** making `compose-smoke` a required check is a
branch-protection setting only the owner can change.
