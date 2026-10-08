# Sprint 20 — the numbers a switcher's import books, and a backlog closed by decision

> **Amended 2026-10-08 by ADR-0026's two-PR amendment** (adopted by the merge
> of the PR that carries it). α, β and γ are **commit groups of one sprint
> PR** on `agent/<provider>/sprint-20`, built in that order by a fresh
> implementation session. Wherever this plan says "PR α", "PR β", "PR γ" or
> "lane PR", read "commit group"; wherever it says "γ's merge", read "the
> sprint PR's merge". D-9 carries the details.

**Status: ADOPTED by the merge of the Sprint 20 planning PR.**
The merge is the signature (ADR-0026 step 1 as amended on PR #780). This
planning PR **signs three decision gates**, all risk-tier:

- the [ADR-0053](../../docs/decisions/0053-a-pp-csv-books-its-gesamtpreis.md)
  amendment of 2026-10-07: the JSON path's negative tax, a converter file's
  negative Steuern, and a credit row that nets to nothing (#1098, #1118);
- the [ADR-0015](../../docs/decisions/0015-cross-currency-settlement-fx-rate.md)
  amendment of 2026-10-07: a cross-currency booking's fees and taxes are in
  its cash account's currency (#1108, #1107);
- the [ADR-0050](../../docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md)
  amendment of 2026-10-07: the first limit's fail-closed probe (#904), and
  names compared as exact strings (#973).

The merge also adopts:

- the lane cut, the three lane PRs and **D-1** to **D-15**;
- **the decision pass (D-4)**: an answer for every one of the 46 open
  `needs-decision` issues, and for six `agentic` issues that need a decision
  rather than a build;
- the design picks of **D-12**, on the boards of
  `planning-artifacts/ux-design-2026-10-07-sprint20.md`.

Nothing here is `DRAFT` or `Proposed`. A decision the owner rejects is
removed on the PR before the merge. A closure the owner rejects is undone by
a comment naming its issue.

**Two checks go to the owner, and silence has a default** (D-2, D-3):

1. How many tax refunds did the live instance's JSON import split off? One
   query answers it. Silence builds the correction.
2. Who proves the build route: the owner's own host (recommended), or this
   environment with the Debian mirrors allowed?

**Verification basis:**

- **`main` and CI:** `main` at `34521a6` (the Sprint 19 close-out). CI 1757
  and Commit authorship 771 on it are green. The latest release is
  **2026.10.12** (PR γ's merge), API contract version 15.
- **The open-issue list of 2026-10-07:** 132 open: 6 trackers, 78 `agentic`,
  46 `needs-decision`, 2 `needs-uat`. One open pull request, Dependabot's
  #977 (Node 26).
- **Every open issue, read for this plan:** all 124 non-tracker bodies and
  their comments, each checked against the code on `34521a6`. Every one
  still reproduces except #958, which Sprint 16 already built.
- **Portfolio Performance's source**, read on its `master` branch for #1098:
  `json/JTransaction.java`, `model/Account.java` and
  `model/AccountTransaction.java` (no test reads it).
- **The code, read for every claim this plan makes about it:**
  - the JSON parser's unit fold and derived price, the CSV parser's
    `booked_cash/4`, `ImportHash.parts/2` and the applier's two-reading
    economic check (the ADR-0053 amendment);
  - `Ledger.transaction_for_matcher/2`, `Portfolios.Costs`, `Income` and the
    settlement guard (the ADR-0015 amendment);
  - `Fx.RateSync.backfill/1` and its two callers (D-5);
  - ADR-0050 §2 and §4 against `Applier.reimport_counts/3` (the probe).
- **This environment, for criterion 3:** `deb.debian.org` still answers
  nothing, and no Docker daemon runs here (`dockerd` is installed and not
  started).
- **The design pass this PR carries:** two boards, rendered with the real
  `priv/static/app.css` (D-12).

## State of play, in five lines

1. **Sprint 19 shipped all three lanes and failed two of its four exit
   criteria.** 132 issues are open against fewer than 100. The build route of
   the launch test was not proven, because this machine reaches no Debian
   mirror.
2. **One of Sprint 19's answers was wrong, and it is the owner's case.** Its
   D-2 said a history imported as JSON was not affected by the CSV bug. True,
   but the JSON importer has its own: it books every negative tax twice
   (#1098, confirmed against PP's source). The live instance came in as
   JSON. Its cash is too high by every tax refund PP recorded inside a
   booking, and an affected sale's realized result is too high by the same.
3. **Two more money defects meet every switcher who holds foreign
   currency.**
   - The historical exchange rates are fetched only by a button, so an
     imported multi-year history counts its foreign cash and positions at
     zero until the first daily rate, and then books them as a gain (#1120).
   - A cross-currency trade's closed result adds fees in euros to a price in
     dollars (#1108, #1107).

   The first-look test passed on seeded rates, so it could not see either.
4. **The count needs decisions, not another lane plan.** Sprint 19's
   retrospective says so. 46 questions sat at `needs-decision`, some since
   September, and no sprint answered them. This plan answers all 46. 27 of
   the answers are "not planned, reopened by …".
5. **Criterion 3 cannot run in this environment.** It has no Debian mirror
   and no Docker daemon. A criterion the environment cannot run measures the
   environment, so D-3 moves the build route to the owner's host.

## Why this cut

- **Money a switcher's first import books, first.** PR α fixes what the
  importer books (#1098, #1118, #904, #1120), and PR β what the ledger
  reports about it (#1108, #1107, #1142, #1101, #1124). Every one of them is
  an H issue: it can show a wrong or silently incomplete money figure.
- **Three records are signed here, so α and β can start the morning after
  the merge.** Each is a dated amendment of an existing ADR. No new ADR is
  needed.
- **No screen lane.** Twenty-seven open UI repairs wait for the first design
  pass after this sprint (D-13). The two boards on this PR draw only what
  the money and import stories change on screen. That is the retrospective's
  "little new surface".
- **One lane with no rendered change takes the rest.** PR γ carries 34
  issues: the install gaps, the agent's reads, E25's nine defence-in-depth
  follow-ups, two security fixes and the test tooling. A closing act on
  screens it did not touch has little to file.
- **The decision pass closes 33 at the merge**, 27 of them `needs-decision`.
  Each closure names what reopens it. Closing a question nobody needs
  answered is a decision, not a cut, and the table is there to be read.

## Lanes

### PR α — what the importer books

A1 to A4 are risk-tier: each is its own commit group, TDD first, with exact
`Decimal` fixtures.

- **A1, a negative tax books once, in every format (#1098, #1118; the
  ADR-0053 amendment A1–A5, A7).**
  - **Order:** K10's digest list is the first commit, taken while the code
    is unchanged. K9's and K12's red tests come next (`181.49` against
    today's `181.50`; the synthetic sale's `1,120.00` against `1,145.00`).
  - **Then the change:** the cash cell minus the refund in every format, the
    JSON price from the gross, the hash's price input, the two-reading key,
    and the refusal of a credit row that nets to nothing.
  - **The converter prompt** gains A7's sentence.
  - **Carried forward:** the new JSON fixture is checked against PP's source
    before it is written (ADR-0053 §7), and the story names the source
    files it read in its commit message.
- **A2, the correction for a JSON or a converter file (the amendment's A6;
  Sprint 19's board 09, pick J9 A, signed).** A re-dropped file whose rows
  hit stored hashes with a different cash shows §6's correction section,
  with its own confirm. For a JSON trade the confirm also rewrites the
  price. Each correction is journaled.
  - **Coverage:** none on the API, because the import is an operator action
    (ADR-0029). The PR states that.
  - **Shrinkable only by the owner's count** (D-2).
- **A3, a renamed account is not booked twice (#904; the ADR-0050
  amendment, P1–P5; pick L1).** A file name with no hash hit, in a file whose
  other names have hits, gets no prefill, and Apply waits for a choice.
- **A4, the historical exchange rates arrive by themselves (#1120; D-5).**
- **A5, the import preview's own surface (board 01).**
  - A re-dropped file whose rows all hit leads with "nothing will be booked"
    and asks for no mapping it does not need (#1168). What Apply sends does
    not change.
  - The parser-warnings note takes the full width under 560 px (#1140).
  - A row error's number is the row a spreadsheet shows (#1128). No hash
    reads it.
  - On a fresh instance the preview says which portfolio the import
    creates, and `first_setup` stops promising "the first portfolio"
    (#1173).
  - New accounts get no bucket tag by default (#1174).

**Lane M, maintenance (always present):**

- **BMAD 6.12.1 is α's first commit**, before any story, as Sprint 16 took
  6.12.0. That commit also says whether #1099's seeding of the BMAD user
  config is still needed under 6.12.1's defaults.
- the version report, before α's closing act;
- **Node 26 is declined again with its date** (#977, LTS on 2026-10-28,
  after this sprint's window);
- the images' Debian date and #1136, only if a release build can run (D-3);
- the BMAD modules and the two upstream triggers #727 tracked (D-4 closes
  #727 and keeps its check here).

### PR β — what the ledger reports about it

B1 to B3 and B7 are risk-tier. B4 to B6 name or reload; they convert
nothing.

- **B1, a closed trade in one currency (#1108; the ADR-0015 amendment,
  identities 1, 3 and 4).** The matcher receives a cross-currency trade's
  fees and taxes converted at the trade's own rate.
  - **Found while triaging, fixed here under D-14:** a security booked both
    by hand across currencies and from a PP import may mix price currencies
    inside its FIFO lots. B1 checks it with a red test first. If it
    reproduces and needs no choice, B1 fixes it; otherwise it is filed.
- **B2, the Costs and income reports read the account's currency (#1107;
  identity 2).** The income report's sibling defect has no issue of its own.
  It is proved by a red test before anything changes, and fixed in the same
  group.
- **B3, a zero cost basis has no return (#1142; D-6; board 02).** That
  covers the realized side and the unrealized side, whose `ledger.ex`
  sibling the triage found.
- **B4, a quote series that contradicts the holding's own trades is named
  (#1101; D-7; pick L2).**
- **B5, Wealth's positions follow the page's scope (#1124; D-8).**
- **B6, the category result reloads after a tree edit (#1110).** Only an edit
  that changes the tree restarts the computation: a create, a delete, an
  assignment or a move. A filter change does not.
- **B7, the account row is locked in the same-currency check (#922).** It
  covers the ledger and the importer's copy, pinned with the existing
  lock-race harness.

**Contract entry 16** carries B1–B4's computation versions and payloads. B4's
new data-quality value is paid for inside β (D-10).

### PR γ — nothing a screen shows changes

Every story here has an identical picture, or changes a value inside an
anatomy a signed board already draws. The one exception, #940's refusal
text, is drawn on board 02.

- **C1, a stranger's install (#1132, #1172, #898).**
  - `mix.exs` refuses an Elixir the code cannot build with, at the floor the
    code, the suite and the dev tooling need. The triage measured the suite
    at 1.18.
  - `llms.txt` names the from-source route. `.env.example` states the
    database setting that route reads. The README says how to lock the UI.
    The German docs follow where they carry an install page.
  - The guide documents moving an existing deployment to the owner and
    runtime database roles, in English and German (#898).
- **C2, the agent's reads and writes (#1103, #1133, #1143, #1113, #1135,
  #1154).**
  - The securities list takes `is_retired` (#1103).
  - The target writes take an optional `plan_id`, and an archived plan is
    refused (#1133).
  - A target or cash-target refusal names its row, as the plan editor does
    (#1143). This is the two-way debt due by the end of this batch.
  - A data-quality list filters before it pages (#1113).
  - The plan tools' descriptions name position targets (#1135).
  - Contribution twins without an ISIN carry their WKN (#1154), engine-side,
    with no API change.
- **C3, E25's nine (#937, #938, #940, #941 with #1058, #942, #953, #956,
  #965, #967).** These are the clean lane Sprint 19's D-12 named.
  - **#941's capped helper also carries #1058.**
  - **#956 takes its two side findings.** The `::1` origin never matches,
    because Node writes `[::1]`. Proxy names are never accepted as origins.
    It also documents how a browser client on another loopback port is
    allowed.
  - **#965 needs care to stay board-free.** The stored name gets its own
    data field, and the screen keeps its sentence, pinned by a test.
  - **#967 is the FU-6 ADR on escaping in the companion.**
- **C4, two security fixes (#974, #1137).**
  - **#974 (D-11):** a correct token passes while its source is locked; a
    wrong one still counts. It covers the API and the companion, with
    SECURITY.md, the guide (EN, DE) and a dated note on ADR-0045 §1.
  - **#1137:** an IPv6 bind accepts its own URL's Host header, and an empty
    `PORTFOLIXIR_MCP_HOST` no longer binds every interface.
- **C5, merge records and names (#1159, #1167, #1146, #1152, #972).**
  - **#1159** records an ISIN choice only when one was made, and also stops
    storing an `isin_changed_on` for a change that did not happen.
  - **#1167** is a read-side fix: the stored record keeps its shape.
  - **#1146:** the new-security dialog's merge keeps attributes written while
    it was open.
  - **#1152:** twin detection folds Unicode form and inner whitespace, while
    the guard stays exact (the ADR-0050 amendment, point 6).
  - **#972:** ADR-0050 §7 gains a dated amendment. It keeps the
    `legacy_hashed_anchor`, `legacy_hashed_split` and `unstorable_anchor`
    refusals by name, and
    corrects the compound-split sentence: the build lists the difference
    between the combined and the separate positions, and enforces no bound
    per split.
- **C6, classes and live regions (#1127, #1119).**
  - **#1127:** explicit bond words map to `bond` (Anleihe,
    Schuldverschreibung, Pfandbrief, Notes, Obligation). A bare coupon-year
    pattern does not, and neither does "Bond", which company names use. It
    applies to new securities only (Sprint 19's D-5), with a dated note on
    ADR-0012.
  - **#1119:** an empty status region uses the `position: absolute` idiom
    `app.css` already has, so the picture is identical. DESIGN.md's
    sentence is corrected.
- **C7, tests and tooling (#1131, #1126, #1116, #314, #926, #1170).**
  - Three more test-isolation keys (#1131).
  - A second run of the review seed leaves quotes alone (#1126).
  - The Finch pool experiment closes #1116 either way.
  - Credo's complexity ceiling moves from 13 to 12 (#314). The nesting step
    is declined in D-4, so #314 closes.
  - The B3 test's header names the vendored Python manifests as outside B3
    (#926).
  - DESIGN.md's chart contrast rows measure against the page background
    (#1170).

**Contract entry 17** carries C2's parameters and refusals and C4's
behaviour. The schema bytes are paid inside γ (D-10).

### Lane Z — registry (small)

- **Right after the merge:**
  - the 33 closures of D-4 are made by hand, each with its reason and what
    reopens it;
  - the 18 answered issues lose `needs-decision` and gain `agentic` (D-4);
  - six issues are filed, each under its area tracker:
    - the ADR-0053 amendment's deferral, under #416: PP JSON's
      `INTEREST_CHARGE` and `FEE_REFUND` types, and a negative FEE unit;
    - the design pass's five findings off the lanes' surfaces, as the UX
      document lists them;
  - #1112 gets a comment: its story draws the security page's
    implausible-quote note beside the two-scales one;
  - **every open issue without a parent gets its area tracker** (D-14).
- **At each lane PR's opening and filing:**
  - the PR body carries Lane Z as a checklist, ticked before the closing
    act, covering the issues the PR **files** as well as the ones it builds
    (Sprint 19 retrospective);
  - a filing searches the open titles first, and sets the area parent when
    it files.
- **Registry edits already on this PR:**
  - the Tracker Index's E26 line names Sprint 20 as planned;
  - FR-5's row names the ADR-0053 amendment;
  - `sprint-status.yaml` gains the PLANNED entry.

## Decisions

### D-1: what this sprint is for, and its four exit criteria (recommended)

**Sprint 20 makes the figures a switcher's first import produces right, and
answers every open question.** It passes when all four hold:

1. **Every H issue is closed by keyword:** #1098, #1118, #904 and #1120 (α);
   #1108, #1107, #1142, #1101 and #1124 (β); #1132 and #1172 (γ). A miss
   names the issue and its step.
2. **The switcher's round trips pass**, at α's and β's closing acts, on
   synthetic data in the German UI:
   1. **The negative tax.** `sample_with_negative_tax.json` dropped into a
      fresh portfolio reads Test-Cash **181,49 EUR**. The synthetic sale and
      its PP CSV twin each read **1.120,00 EUR**. A second drop of either
      books nothing.
   2. **The rename.** A file is dropped, one account is renamed in it, and
      it is dropped again. The renamed row shows no prefill and Apply waits.
      Mapped onto its old account, the drop books nothing.
   3. **The rates.** A fresh instance gets a synthetic history with a USD
      security and a USD cash account reaching back two years. Without
      pressing anything, the historical rates arrive and no first-rate jump
      remains in the result. An integration test with the fake provider pins
      it. The persona checks it on the closing act's instance where the
      ECB's host is reachable; where it is not, the record says so.
   4. **The cross-currency trade** (β). It reads identity 1's figures on the
      Trades tab and through the realized-gains read: **151,00 EUR**.
3. **The build route is proven, as D-3 splits it:**
   - the owner's `docker compose up --build -d` on their own host, from a
     fresh clone of γ's merge, comes up;
   - the agent's part of the launch test passes against that merge, here,
     from source.
4. **The count:**
   - **Fewer than 100 open issues at the close-out.** The merge leaves 104:
     33 closed by hand and #973 by keyword, six filed. The lanes close 50
     by keyword. The closing acts can then file 45 before the criterion
     fails, against Sprint 19's 62 across three PRs.
   - **Every `needs-decision` issue open at this planning has an answer**,
     which D-4 gives at the merge.
   - **Scope Lock still binds.** A finding is filed, never withheld to make
     the count (D-15).

**Passing all four is necessary for the announcement and not sufficient**:
the owner decides (see "What the owner decides after this sprint").

**To flip by comment:** name a criterion to drop, or a different threshold
for the fourth.

### D-2: the ADR-0053 amendment is signed, and one count on the owner's instance (recommended)

**The record, in four sentences.**

1. PP's JSON `amount` already holds a negative tax, so a refund split off
   beside it is booked twice. The same goes for a converter CSV with a
   negative Steuern.
2. In every format the parent books the cash cell minus the refund, and a
   JSON price is derived from the gross value. A sale's realized result then
   leaves the refund out.
3. The hash keeps reading the old amount and the old price, so every stored
   hash stays valid and a re-drop books nothing.
4. A credit row that nets to nothing is refused in the preview (#1118), and
   §6's correction is built for JSON and converter files.

**The owner's check, on the live instance.** One query counts the refunds
the JSON import split off, per account:

```sql
SELECT cash_account_id, currency_code, count(*), sum(gross_amount)
FROM transactions
WHERE type = 'tax_refund' AND notes LIKE 'Auto-split tax refund from row %'
GROUP BY 1, 2;
```

Each row's sum is that account's overstatement, as long as every PP file on
the instance was JSON (the owner's D-2 answer of 2026-10-04).

- **Rows:** after α merges, re-export the history from Portfolio Performance
  as JSON, drop it, and confirm the correction section (A2).
- **None:** nothing on the instance is affected, and A2 moves to the shrink
  order's top.
- **Silence builds A2.** Building it unneeded costs about a day. Not building
  it when it is needed leaves wrong balances with no remedy.

**To flip by comment:** "price-free" keeps the derived price as it is. A
JSON sale's realized result then keeps the refund, and the PR states it.
That is variant (b), smaller by the hash's price input.

### D-3: the build route moves to the owner's host, in two halves (recommended)

**Why the criterion changes.** Criterion 3 needs a release build. This
environment has neither:

- **no Debian mirror:** every one Sprint 19 probed answers 403;
- **no Docker daemon:** `dockerd` is installed and not started, and whether
  it can run in this container is unproven.

Sprint 19 recorded "not proven" for that reason. A criterion an environment
cannot run measures the environment.

**The split:**

- **The build route is the owner's.** A fresh clone of γ's merge on the
  owner's own host, `docker compose up --build -d`, the page answers, and
  the owner comments "it came up" (or what failed) on the close-out PR.
  About ten minutes on a host with ordinary egress.
- **The agent's part stays the agent's.** It runs here, under #998's
  protocol unchanged, against the same merge, on the README's from-source
  route.

**To flip by comment:**

- **"run it here"** keeps the whole test in this environment. The owner
  then allows `deb.debian.org` and `security.debian.org` under the cloud
  environment's network settings (Allowed domains, with "Allow package
  managers" left ticked), and approves the Docker commands when the session
  asks. If `dockerd` does not start in the container, the record names that
  and criterion 3 fails again.
- **"run it at home"** asks the owner to run the whole protocol with a fresh
  Claude Code session on their own host.

Either way, **the same two hosts unblock Lane M's Debian image date and
#1136**, which wait for a build that can run (Lane M).

> **Note (2026-10-08).** The owner asked why the build has to run on their
> host. It does not: the `compose-smoke` CI job proves the build half of
> criterion 3, on the sprint PR's head and on `main`. On a GitHub-hosted
> runner it runs `docker compose up --build -d` on generated secrets, waits
> for the app's health and the companion, and reads the page, an API read
> and a companion tool call. The owner's own run is no longer needed for
> criterion 3, only to upgrade their own instance. The job runs on amd64
> only and starts on an empty database, so it does not test the upgrade of
> an existing volume.

### D-4: the decision pass: every open question gets an answer (recommended; each row flips by naming its issue)

**Closed as not planned at the merge (27 of the 46 `needs-decision`
issues):**

| Issue | Answer | Reason | Reopened by |
|---|---|---|---|
| **#866** | no flow rules; state rules only | `protected` feeds the rebalancing digest, shut at B3.5. `budget` is period arithmetic that needs its own record. Nobody has asked since v1 | an owner dump asking for a "do not sell" or new-money rule, or B3.5 opening |
| **#896** | no per-portfolio rule cap | only the token holder or the operator writes rules; F74 fixed the cost's shape (one valuation plus one per subject, pinned). No timing was ever measured, and none is claimed | a profile blaming a slow findings read on the number of rule subjects |
| **#897** | keep the database-bounded `as_of` | rows can be re-delivered, never lost, and the tool text says so; a new cursor bumps seven reads for no observed failure | a delta consumer reporting a committed row it never received, or a write under a second database role |
| **#902** | no tombstone; the refusal and "merge the other way" stay | it would amend ADR-0044 and ADR-0049 for a case nobody has hit | a security merge refused in both directions on a real instance |
| **#903** | no generalised aliases | `identity_unresolvable` is a safe, named refusal; it is risk-tier import idempotency | an operator hitting `identity_unresolvable` on a merge they need |
| **#905** | keep set semantics on the economic layer | **a genuine twin can be absorbed after an account merge, but never silently**: the preview counts it, and the result opens the `economics` group by default | an `economics` group listing a row the operator identifies as a real second booking (the owner's #328 run is where it would show) |
| **#906** | no unmerge | the merge record's manifest and the journal's before-images reconstruct every merge | a merge applied in error that cannot practically be undone by hand |
| **#907** | no merger or spin-off kind | the delivery-pair idiom books one; a kind needs an ADR-0028 amendment and risk-tier projection work | the operator having to book one, or a PP export carrying one the importer cannot map |
| **#931** | no size cap on the throttle table | an entry per failing source is tiny; the flood that fills it saturates the instance first; the port is published on loopback | the guide documenting a port exposed to the internet, or a memory profile showing the table |
| **#939** | keep the two rate-parsing paths | the echoed rate differs from the used one only beyond the 15th decimal; no displayed figure moves | a third fixed-rate input, or a consumer whose recomputation disagrees with the basis |
| **#946** | the gap stays until ADR-0024 §5 | a second portfolio arises only through deprecated API writes; a portfolio control in the UI would reverse ADR-0024 | a policy rule in a non-first portfolio on some instance, or ADR-0024 §5 scheduled |
| **#950** | the provenance guard stays at the controllers | no external path sets `machine_generated` today | a new caller of the note or event writers, above all machine-extracted intake |
| **#970** | no spacing sweep and no gate now | about 180 off-scale declarations exist, not 40; a "fail on new" gate needs a baseline (a review reject) or a repaint | a design pass scheduling a spacing repaint of a surface, which then gains its gate |
| **#987**, **#988**, **#989** | not now | ADR-0051 §1, §2 and §7's own reasons; #989 needs an ADR-0033 amendment first | each ADR section's own trigger |
| **#990** | not now | it applies today's grouping to a period figure, the tension ADR-0041 §1 removed | the owner asking for a category view of a period's result |
| **#999** | no write-scoped tokens | an agent with a shell on the operator's host reads the token's environment anyway; an HTTP client is bounded by its profile | a deployment where the agent or companion runs on another host with its own token |
| **#1000** | income stays outside per-trade figures | the trades basis says so | the operator asking whether a payer's trade was worth it including its income |
| **#1001** | one FIFO queue per security stays | both effects are stated on screen, and delivered-in sells are named as `unmatched_sells` | **the owner's one read:** a non-empty `unmatched_sells` in `portfolixir.cashflow.realized_gains` on the live instance flips this row to a build (lots opened by inbound deliveries, size M, risk-tier, an ADR) |
| **#1002**, **#1003**, **#1004** | not now | after the announcement decision (Sprint 18's D-2); #1004's launch reason does not hold, since every public screenshot is synthetic | the announcement decision and a feature lane, or a request |
| **#1097** | no suspect list without a file | ADR-0053's reason: exact for no dividend, a list sometimes wrong about money is worse than none | an operator who imported a PP CSV before 2026.10.10 and can no longer export from PP |
| **#1111** | keep the base-currency key | no figure is summed wrong; a member is excluded and named | an excluded member whose cost was in fact paid in EUR, seen on a live instance |
| **#1117** | keep closing balances, as the basis already says | its phantom has #1120's cause, and A4 removes it for every currency the ECB publishes | an unexplained `cash_currency_effect` jump on an instance whose history backfill has run |
| **#1156** | accept the exception EXPERIENCE.md records | the digits never break; γ's docs story rewrites "an open decision (issue 1156)" as decided | digits that break, or a wrapped suffix someone misreads |

**Closed at the merge, six `agentic` issues that need a decision, not a
build:**

| Issue | Answer | Reason | Reopened by |
|---|---|---|---|
| **#958** | **completed**, closed with its evidence | Sprint 16 built it: the merge preview refuses a source ISIN that fails its check digit and adopts no bad WKN or ticker (`security_merge.ex`, its tests, ADR-0050 §9, the API reference, the MCP description) | — |
| **#727** | tracked by Lane M | the version report re-checks both upstream triggers every sprint; neither has fired | a trigger firing (a new issue then carries the move) |
| **#895** | no network split | the guide puts the bridge gateway in `PORTFOLIXIR_TRUSTED_PROXIES`; a split moves it and, with `PHX_FORCE_SSL`, causes the redirect loop the guide describes. CI never starts Compose, so only a real Docker run could check it | a deployment that exposes the companion beyond loopback, or #999's trigger |
| **#949** | the select stays | it is bounded by the instance's own accounts, and the suggested `datalist` turns a strict choice into free text | an import preview measurably slow to render because of it |
| **#1141** | not planned | only an instance that booked an unsupported-currency row before #948 can see it, and the hash already blocks a double booking | an instance upgraded across #948 reporting it |
| **#1153** | the guard stays exact | the ADR-0050 amendment's point 6: names are exact strings; pickers tell twins apart (#1152, γ) | an import that resolves onto the wrong account because of a confusable name |

**Answered and built this sprint (17), relabelled `agentic` at the merge:**

| Issue | Answer | Lane |
|---|---|---|
| **#1098** | yes, it counts twice; the ADR-0053 amendment | α A1, A2 |
| **#1118** | refuse in the preview, in both parsers | α A1 |
| **#904** | the fail-closed probe; the ADR-0050 amendment | α A3 |
| **#1120** | remove the cause: the backfill runs by itself (D-5). The issue's two options close with it | α A4 |
| **#1128** | number rows as a spreadsheet shows them | α A5 |
| **#1140** | a full-width row list under 560 px | α A5 |
| **#1174** | no bucket tag by default | α A5 |
| **#1101** | a same-date guard, `implausible_quote` (D-7) | β B4 |
| **#973** | names are exact strings; the ADR-0050 amendment, closed by this PR's keyword | this PR |
| **#972** | keep the three refusals by name; correct §7's sentence | γ C5 |
| **#974** | token first; wrong tokens still count (D-11) | γ C4 |
| **#1103** | add `is_retired`; the context already takes it | γ C2 |
| **#1133** | an optional `plan_id`; archived plans refused | γ C2 |
| **#1127** | explicit bond words only | γ C6 |
| **#1119** | the `position: absolute` idiom | γ C6 |
| **#898** | a documented migration (backup, create roles, restore as owner, migrate as owner), EN and DE | γ C1 |
| **#926** | the vendored Python manifests are outside B3, said in the test's header | γ C7 |

**Answered and built later (2), relabelled `agentic` at the merge:**

| Issue | Answer | When |
|---|---|---|
| **#928** | Keep the security on imported interest bookings from now on. ADR-0051 §3 is amended by the story: a security-linked interest booking counts in that position's income term. Old rows stay in the remainder's interest line, as its basis says. | the first batch after this sprint; the amendment is signed on that batch's planning PR |
| **#1122** | The link carries the card's period, and names the active view where it differs from the card's (option 3) | the UI batch (D-13), boarded there |

**A rule so the list does not refill the same way:** a `needs-decision`
issue a closing act files carries its recommended answer and what would
reopen it if closed. The next plan's decision pass is then a table, not
research.

### D-5: #1120 — the historical exchange rates arrive by themselves (recommended)

**The cause.** The routine sync fetches only the ECB's daily file. The
historical series runs only from Cash flow's backfill control or from the
API's `scope=history`, and neither the quick start nor `first_setup`
mentions it. A switcher who imports years of history in a foreign currency
sees it counted at zero until the first daily rate, and then booked as
result.

**The answer.** The one-shot history backfill runs **by itself, once, when
needed**:

- **When it runs:** after the boot sync and after an import apply, when a
  booking or an account in a non-EUR currency predates that currency's
  earliest stored rate.
- **How:** through the existing `SingleFlight` path, so a manual backfill and
  this one never overlap.
- **Without a network,** it fails quietly and the unvalued-cash note stays,
  as today.
- **Tests** use the fake provider only.

This amends Sprint 9's D-1 ("on demand") to "on demand, and once by itself
when needed". It needs no ADR: B3.3 gates acquisition beyond quotes and FX,
and this is FX. ADR-0051 §10 stays for what is left, which is currencies the
ECB does not publish and bookings before 1999.

### D-6: #1142 — a zero cost basis has no return (recommended; board 02)

**The rule.** A closed trade or a held position whose cost basis is zero
has no percentage return:

- the API and MCP answer `null` with the reason in the payload's basis, not
  `0`;
- the screens show the existing dash with the reason, through #1089's
  reason anatomy (Sprint 19's pick J4).

**Why not 0 %.** A delivery booked at zero cost rose by an undefined
percentage, not by none. "0.0 % total" reads as "no gain".

**Contract entry 16** names the `null`.

### D-7: #1101 — `implausible_quote`, and its parameters (recommended; pick L2)

**The predicate.** For each buy, sell or priced delivery of a held
security, the stored quote on that booking's date is compared with the
booking's price per unit, in the same currency. Where that date has no
quote, the latest quote within **7 days before** it is used. The security is
named when the ratio falls outside **[1/2, 2]**.

**Why the same date.** A share that rose twentyfold cannot trip it, because
its quote on each booking's date matched the price paid then. A ticker
mapped wrong from day one does trip it, and so does a pence/pound scale
slip.

**Its basis, in the payload:**

- input series: the stored quotes;
- reference: each booking's price per unit;
- window: 7 days before the booking date;
- gaps: a booking with no quote in the window is not compared;
- threshold: 2.

**Overlap.** A security already in `two_scales` is not counted again, since
`two_scales` names the cause more precisely.

**Severity (pick L2): problem.** When it fires, the total above it is wrong.

**Records.** A dated note on ADR-0052 §4, its sibling. It is not risk-tier:
it names and converts nothing.

**To flip by comment:** another threshold or window ("k=3", "14 days"), or
"L2 B" for attention severity.

### D-8: #1124 — Wealth's positions follow the page's scope (recommended)

The positions table reads the scope the page reads (ADR-0024), the selected
view included, so a second portfolio's holdings appear where the view holds
them. **No new copy:** the page's scope line already names the scope. The
rows change, and the anatomy does not.

### D-9: three lane PRs, merged in order, and the retrospective's carry-forwards (standing, amended)

> **Amended 2026-10-08** (ADR-0026, two-PR amendment). The table's order
> stands as the commit-group order, and "merged" reads "built". Carry-forward
> 1 lapses: no PR's base moves under another. Each closing act still runs
> when its group is done: α's and β's round trips, γ's launch test. One
> briefing, one Lane Z checklist and one close-out ride the sprint PR, and
> the retrospective is its last commits before promotion. The sprint PR
> estimates its commit count when it opens; above 90 it splits γ off as a
> stacked PR and says why. The owner merges once, by rebase-merge.

| PR | Lanes | Merged | Why this order |
|---|---|---|---|
| **α** | A (the importer), Lane M | first | the cash a switcher's first drop books, and the correction the owner's instance may need |
| **β** | B (the ledger's reports) | second | its closed trades and costs read α's corrected bookings |
| **γ** | C (no rendered change) | third | independent of α and β; it may open in parallel on `main` and is rebased before its merge. Its close-out runs the launch test |

**The Sprint 19 retrospective's carry-forwards, each a duty from the first
commit:**

1. **When a lane PR merges, the next PR's base moves to `main` first, then
   the moved head is pushed.**
2. **A history rebuild proves the invariants of every commit it writes**:
   the gettext catalogs, the localization test, `errors.pot`.
3. **Lane Z's checklist covers the issues a PR files**, not only the ones it
   builds. A filing pass searches the open titles first.
4. **Every agent brief names its base commit and says to read a gate's exit
   status directly**, never through a pipe. Three γ commits in Sprint 19
   carried stale gettext references because a failing check was piped into
   `tail`.
5. **A fixture that encodes an external format is checked against that
   format's source** (ADR-0053 §7). It applies to α's JSON fixtures.
6. **Every push runs all fifteen gates.**

Each PR opens as a draft with its first commit, carries its own briefing, is
promoted under `AGENTS.md`'s four conditions, and is rebase-merged by the
owner.

### D-10: the schema budget (standing rule, stated with its cost)

The ceilings stand where Sprint 19's close-out left them: read 103,454, book
176,536 and full 206,884 bytes. α re-measures them at its opening.

- **α** adds no tool and no parameter. `first_setup`'s text changes inside
  its own bytes.
- **β** adds one data-quality value (`implausible_quote`).
- **γ** adds `is_retired` and `plan_id` and changes #1135's descriptions.

**Each PR trims existing descriptions by at least what it adds, then lowers
the ceilings to the new figures.** A raised ceiling is a weakened gate and a
review reject.

### D-11: #974 — a correct token passes a locked source (recommended; security, risk-tier)

**The trouble.** Under Compose every host client is one source. A stale
client that still sends an old token after a rotation locks the operator's
own agent out for the hour the escalation is kept.

**The answer.** The token is compared first, in `api_auth_plug.ex` and in
the companion's `http.ts`, in one commit group. A wrong token still counts
and still locks.

**The cost, stated.** A locked guesser who guesses right is let in. The
boot floor of 32 bytes makes that guess infeasible.

**What stays lock-first:** the UI password, which a person chooses. That is
a separate question, and nobody has asked it.

**Records.** A dated note on ADR-0045 §1, SECURITY.md, the guide (EN, DE),
and a line in contract entry 17.

### D-12: the design picks (recommended; silence adopts them)

Two boards, under
`planning-artifacts/design-language/mockups/ux-design-2026-10-07/`, argued
in `planning-artifacts/ux-design-2026-10-07-sprint20.md`. The pick letter is
**L**: it skips K, so it does not collide with ADR-0053's identities K1–K15.

| Pick | Item | Board | Lane | Kind | Recommended |
|---|---|---|---|---|---|
| **L1** | A file name the stored history never saw (#904) | `01-import-preview` | α A3 | variants | **A**: no prefill; Apply waits |
| — | A re-dropped file with nothing new (#1168); the parser-warnings note at 390 px (#1140); a credit row that nets to nothing (#1118); the row number (#1128); the fresh instance's portfolio (#1173); no default bucket tag (#1174); the correction's wording for a JSON file (A2) | `01-import-preview` | α A1, A2, A5 | before/after | after |
| **L2** | `implausible_quote` on the Overview, in Wealth's notes and in its list (#1101) | `02-money-findings` | β B4 | variants | **A**: problem severity |
| — | A zero cost basis, realized and unrealized (#1142); a tree deeper than its limit (#940) | `02-money-findings` | β B3, γ C3 | before/after | after |

**Items with no board:** every other story in this plan. They change
values, not anatomy (A1, A4, B1, B2, B5, B6 and C5's #1152), or they render
nothing (the rest of γ, B7). The design critic of α and β reviews the built
surfaces against their board as well as against the spec.

### D-13: what stays open on purpose (recommended)

| Issue | Action | Reason |
|---|---|---|
| **#328**, **#354** | stay open | the owner's runs on real data |
| **#1104**, **#1112**, **#1114**, **#1121**, **#1122**, **#1123**, **#1125**, **#1130**, **#1138**, **#1139**, **#1145**, **#1147**, **#1148**, **#1149**, **#1150**, **#1151**, **#1155**, **#1157**, **#1158**, **#1160**, **#1161**, **#1162**, **#1163**, **#1165**, **#1166**, **#1169**, **#1171** | stay open: **the UI batch** | 27 repairs on screens this sprint does not touch, each needing a board. They are the first design pass after this sprint. #1169 reverses the owner's decision of 2026-08-05 (the total counts up), so its board carries options. #1145 and #1139 are the two a phone user meets first |
| **#1052** | stays open | the screen's in-place correction of the cash kinds; a two-way finding since Sprint 19's D-6, and the first design pass after the announcement decision |
| **#928** | stays open, answered | D-4 |
| **#899**, **#900** | stay open | after the announcement decision |
| **#957**, **#1070** | stay open | the security merge's preview and bond data: one later lane, risk-tier |
| **#894**, **#925**, **#951**, **#962**, **#971** | stay open | each is size L or needs a measurement (#971 before #925) or a byte budget of its own (#951) |
| **#1115** | stays open | the MCP SDK v2, its own risk-tier lane before v1's support ends |
| **#1136** | stays open | rides with the Debian image date when a release build can run (D-3; Lane M) |
| **#416–#420**, **#991** | trackers | #991 holds its 100 and closes with the owner's announcement decision |

### D-14: a parent for every open issue (recommended)

**#991 is full.** GitHub caps a parent at 100 sub-issues, and 61 issues
filed during Sprint 19 have no parent.

**Answer:** every open issue without a parent goes under its **area
tracker**, by the surface or the module it touches:

- #416: data, import, export and audit;
- #417: portfolio structure and instrument lifecycle;
- #418: analytics, dashboard and charts;
- #419: LLM and MCP;
- #420: engineering quality and process.

Issues filed from now on get their area parent when they are filed. No
second E26 tracker is opened: it would fill the same way, and the area
trackers are where the backlog lives after the announcement.

**To flip by comment:** "E26 successor" opens a second launch tracker
instead.

### D-15: the closing act, one lens per risk class, and on-surface findings (standing)

| PR | Lenses |
|---|---|
| **α** | correctness hunter; **money and idempotency lens on K9–K15 one at a time, K10 and K11 first**, then on P1–P5; edge-case hunter on the correction and the probe; design critic against board 01 in German at 390 and 1200 px, light and dark; **the UAT persona runs criterion 2's round trips 1 to 3** |
| **β** | correctness hunter; **money lens on the ADR-0015 amendment's identities, 1 and 3 first**; the lock-race lens over #922; design critic against board 02; the UAT persona runs round trip 4 |
| **γ** | correctness hunter; **security lens over #974, #956, #1137, #938 and #965**; an install lens over #1132 and #1172 (a stranger's from-source run); the agent's launch test at the close-out (D-3) |

Sprint 19's D-14 stands: a finding on a surface the PR already changes,
small and with its answer in the spec, is fixed on the branch. A finding
off the PR's surface, or one that needs a choice, is filed under Scope Lock
with its area parent. **Nothing is withheld to make D-1's count.** A cascade
stops when a layer yields no major finding, and every finding carries its
reach label. Each lane PR reserves its closing act and its briefing before
its first story. If the weekly usage limit comes into view, the shrink order
applies from its first step, and the closing acts are not what is cut.

## Sequencing

```text
after the merge ── Lane Z: 33 closed by hand; 18 relabelled; six filed;
                   every open orphan gets its area parent
PR α opens ─────▶ Lane M: BMAD 6.12.1
                   ─▶ A1 #1098 #1118 (K10 digests ▶ red K9/K12 ▶ reading ▶
                      price ▶ keys ▶ refusal) ─▶ A2 the correction
                   ─▶ A3 #904 ─▶ A4 #1120 ─▶ A5 #1168 #1140 #1128 #1173 #1174
                   closing act with round trips 1–3 ─▶ merge = a release
PR β opens ─────▶ (base moved to main when α merges, then the head pushed)
                   B1 #1108 ─▶ B2 #1107 ─▶ B3 #1142 ─▶ B4 #1101
                   ─▶ B5 #1124 ─▶ B6 #1110 ─▶ B7 #922
                   closing act with round trip 4 ─▶ merge = a release
PR γ opens ─────▶ (in parallel, on main) C1 ─▶ C2 ─▶ C3 ─▶ C4 ─▶ C5
                   ─▶ C6 ─▶ C7; rebased after β
                   closing act ─▶ merge = a release
close-out ─────── the owner's build; the agent's launch test from source; the
                   count; the two-way check; the surface check; launch
                   readiness, v3
```

## Shrink order (cut from the top, name the cut in the briefing)

1. **A2, the correction**, only if the owner's count is zero (D-2).
2. **C7's tooling tail:** #1116, #314, #1170 and #926.
3. **C3's two size-M items:** #965, and #941 with #1058.
4. **#967**, the FU-6 ADR.
5. **A5's items that are not H:** #1174 and #1140, then #1168. Their boards
   stay signed for the UI batch.

**What does not shrink:**

- every H issue (D-1, criterion 1);
- the three signed amendments' builds;
- the round trips and the launch test;
- the decision pass's closures;
- #1143, the two-way debt due by the end of this batch.

## What is deliberately not in this sprint

- **The UI batch** (D-13): 27 repairs on screens no story here touches.
- **#1052**, the screen's in-place correction of the cash kinds.
- **New features.** #1002–#1004 close as not planned (D-4), and #899 and
  #900 wait for the announcement decision.
- **An import route under `/api/v1`**: the import stays an operator action.
- **B3.3, B3.5, B3.7, B3.8** and ladder level (d): shut. The automatic FX
  backfill (D-5) is FX, which B3.3 does not gate.
- **Phone access**: the widening phase, after the announcement.

## What the owner decides after this sprint

The close-out ends with **launch readiness, version 3**, in the shape of
`launch-readiness-2026-10-07-sprint19.md`. It holds:

- all four exit criteria's records, step by step;
- the open issues that touch money or an upgrade path. The plan expects
  none known; each one that is known is named;
- the open-issue count by label, and what filled it;
- the owner's checks no agent can run: the correction on the live instance
  if D-2's count found rows; #328 and #354.

**The announcement stays the owner's call** (Sprint 17's D-1).

- **If all four criteria hold**, the summary recommends announcing to the
  small group the launch path names: self-hosters who run LLM agents, in the
  self-hosting and Portfolio Performance communities. The UI batch (D-13)
  then becomes the first sprint of the widening phase.
- **If a criterion fails**, the summary names it, and that becomes Sprint
  21's plan.

## What "done" means for this sprint

1. **PR α, β and γ are merged in order**, each green on its head, each with
   its closing act under D-15 and its briefing.
2. **The three amendments are built as signed:**
   - ADR-0053's K9–K15;
   - ADR-0015's identities 1–4;
   - ADR-0050's P1–P5.

   Each identity is pinned, seen failing first, and mutation-checked. The
   correction is built, or shrunk by the owner's count of zero.
3. **The four exit criteria of D-1 are recorded**, each pass or fail with
   its step.
4. **The decision pass is carried out:** 33 closed by hand at the merge, 18
   relabelled, six filed, and every closure's reason and reopen trigger in
   its issue.
5. **#1143 closes, so #945 holds in both directions.** #1052's miss stays
   recorded with Sprint 19's reason.
6. **Each merge that touched shipped code produced a calendar release**, and
   contract entries 16 and 17 name what changed.
7. **The schema budget's ceilings are no higher than today's.**
8. **The close-out's surface check** names:
   - the `implausible_quote` value across the data-quality family: the
     securities list, the Overview's line, and Wealth's notes and their
     reads;
   - #1142's `null` return across the trades, realized-gains, holdings and
     position reads;
   - #1103's `is_retired` and #1133's `plan_id` against their families'
     other filters and writes.
9. **Launch readiness, version 3** is in the close-out.
