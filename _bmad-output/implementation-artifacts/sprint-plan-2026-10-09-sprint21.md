# Sprint 21 — after the first import: the second sale, the coupon, the re-export, and the screens that waited

**Status: ADOPTED by the merge of the Sprint 21 planning PR.**
The merge is the signature (ADR-0026 step 1, as amended on 2026-10-08). This
is the first plan written for ADR-0026's two-PR shape from the start: a fresh
implementation session builds it on `agent/<provider>/sprint-21`, as one
sprint PR and one stacked PR (D-8).

## What you need to do

1. **Merge, to sign four risk-tier amendments**, each dated 2026-10-09:
   - [ADR-0015](../../docs/decisions/0015-cross-currency-settlement-fx-rate.md):
     a closed trade is in one currency, whatever booked its lots (#1198,
     #1199, #1196);
   - [ADR-0053](../../docs/decisions/0053-a-pp-csv-books-its-gesamtpreis.md):
     what the parsers refuse, and what the correction lists (#1188, #1193,
     #1194, #1205, and #1177's negative fee);
   - [ADR-0050](../../docs/decisions/0050-lifecycle-merges-under-a-reimport-contract.md):
     the rename probe reads the dry run, so a re-drop whose rows are all
     booked stops asking (#1195);
   - [ADR-0051](../../docs/decisions/0051-contribution-analysis.md): a
     bond's coupon is its position's income (#928, answered by Sprint 20's
     D-4 and signed here, as that answer said).

   The merge also adopts D-1 to D-14 and the design picks N2 to N21 (D-10).
2. **One pick only you can make: N1, the Overview's count-up (#1169).** It
   reverses your ruling of 2026-08-05, so silence does not adopt it.
   - **Silence keeps your ruling**, and #1169 closes as not planned right
     after the merge.
   - **"N1 B" in a comment builds B** (recommended). The waiting stays as
     today: the last known year-to-date figure, or a skeleton, while the
     total computes. When the computed total arrives, it appears at once,
     instead of counting up from 0,00 over 600 ms. A count runs only between
     two real figures, which on today's code is almost never, so B is close
     to "no count on money" (D-3). Board 01 draws A, B and C.
3. **Hold the live correction until this sprint merges.** #1098's correction
   is on your instance's next upgrade, but today it overwrites a booking you
   edited by hand since its import (#1194), and it does not list a row whose
   re-export drifted (#1205). This sprint fixes both. Not a question: it
   only asks you to wait with that one confirm.

**Not asked:** the announcement. It stays yours (Sprint 17's D-1), launch
readiness v3 is its input, and this sprint neither waits for it nor changes
its recommendation. That page's advice also stands: upgrade the live
instance by Compose before announcing, because no CI job tests an existing
volume. Making `compose-smoke` a required check stays a branch-protection
setting only you can change.

Nothing here is `DRAFT` or `Proposed`. A decision you reject is removed on
the PR before the merge. A closure you reject is undone by a comment naming
its issue.

**Verification basis:**

- **`main` and CI:** `main` at `6f9d7d1`, the Sprint 20 close-out. CI 1776
  and Commit authorship 790 on it are green.
- **Sprint 20's two merges, as its close-out asked this plan to record:**
  - #1184 merged at 05:04 UTC on 2026-10-09 and made release **2026.10.13**
    (contract version 16);
  - #1215 merged at 07:18 UTC and made release **2026.10.14** (contract
    version 17).

  Both CI runs on `main` were green: CI 1773 for #1184 and CI 1776 for the
  head after #1215.
- **The open-issue list of 2026-10-09:** 84 open: 66 `agentic`, 10
  `needs-decision`, 6 trackers, 2 `needs-uat`. One open pull request,
  Dependabot's #977 (Node 26).
- **Every open issue, read for this plan:** all 78 non-tracker bodies and
  their comments, each checked against the code on `6f9d7d1` by five
  read-only triage passes. Every one still reproduces except:
  - **#1190** cannot happen: the bucket read and its write run inside the
    import's transaction, on accounts only that run created (D-4);
  - **#1138**'s focus-ring half was fixed by #1062; its padding half stands;
  - **#1125**'s grouping half does not reproduce; its rounding and its
    suffix space do.
- **The code, read for every claim this plan makes about it**, by module:
  `TradeMatcher`, `Ledger.transaction_for_matcher/2`, `RealizedGains`, the
  transaction currency check, `Ledger.SettlementBackfill`, `Fx.RateSync`
  (ADR-0015); the two PP parsers, `Imports.Correction`, the applier's
  old-reading check, `DedupKey` and the journal's actor fields (ADR-0053);
  the applier's unseen-names probe and the preview's async refinement
  (ADR-0050); the applier's interest attrs, the performance walk's interest
  clause and `Derived.Registry` (ADR-0051); `CappedAsync` and `HeapCap`
  (#1204); the ledger's and the cash merge's lock order (#1214).
- **The design pass this PR carries:** nine boards, rendered with the real
  `priv/static/app.css` (D-10).

## State of play, in five lines

1. **E26's four exit criteria all passed.** What is left of the launch is
   your announcement decision and one upgrade no CI job tests. No agent work
   moves either.
2. **The first import is now right; what follows it is not.** Sprint 20
   fixed what a switcher's first drop books. The triage found what the
   second step gets wrong:
   - a hand-booked sale of an imported foreign position sums two currencies
     in its FIFO lots (#1198);
   - a bond's coupon never reaches its position (#928);
   - a delivery with a negative tax rolls the whole JSON file back (#1188);
   - a re-export dropped again meets a correction that overwrites hand edits
     and misses drifted rows (#1194, #1205).
3. **The UI batch has waited two sprints.** Sprint 20's D-13 named 27
   repairs. Sprint 20's design pass, build and closing acts filed more on
   the same screens, and α changes three of them. All 51 are drawn on this
   PR.
4. **Two two-way debts are due.** The screen still cannot correct a
   dividend's facts in place (#1052, missed on purpose since Sprint 19). No
   screen books the tax refund that the import's refusal names as its remedy
   (#1206).
5. **The backlog is small enough to empty a class of it.** 84 are open. The
   sprint closes 64 by keyword if it lands whole. What stays is the
   trackers, the owner's runs, the later lanes D-11 names, the eight this
   PR files, and what the build files.

## Why this cut

- **Money first, then the agent's surface, then the screens.** The sprint
  PR carries everything that books, converts or reports money (α), and
  everything with no rendered change (β). The stacked PR carries the UI
  batch (γ) and the close-out. The money fixes reach your instance with
  the first merge. The screens follow without waiting on them.
- **Four amendments, all signed here, so α can start the morning after the
  merge.** Each is a dated amendment of an existing ADR, written on this PR
  with its identities.
- **Every UI change is on a board.** Nine boards draw 51
  issues. The recommendation is the default, except N1.
- **The decision pass leaves no question unanswered.** All ten
  `needs-decision` issues get an answer: nine are built, and one closes as
  not planned. Two `agentic` issues, #1190 and #1177, need a decision
  rather than a build, and get one.
- **The stack is the commit budget's answer, not a preference.** The
  estimate is about 66 commits for Lane M, α and β, and about 63 for γ with
  the close-out. That is above 90 together, so γ rides a stacked PR, as
  Sprint 20's γ did (D-8).

## Lanes

### Lane M, maintenance (always present; the sprint PR's first commits)

- The version report before α's closing act, with the BMAD, Hex, npm,
  Elixir/OTP, PostgreSQL and module checks of Sprint 20's report. The two
  triggers #727 tracked are re-checked there.
- **Node 26 is declined again, with its date.** #977 stays open: Node 26
  becomes LTS on 2026-10-28, after this sprint's window. The first sprint
  that runs on or after that date takes it, with `@types/node` 26, in one
  commit across the four pinned places.

### α — the money after the first import (risk tier; the sprint PR)

Every story here is TDD first, with exact `Decimal` fixtures, its own commit
group, and a dedicated verification pass (sprint workflow, "Risk-tier
attention").

- **α1, a trade priced in a third currency is refused (#1199; the ADR-0015
  amendment, point 1).**
  - **The rule:** it covers every write path and the importer's copy of the
    check. The check runs on insert, and on an update that changes the
    currency, the security, the cash account or the type, as
    `Ledger.SettlementGuard` does. A notes-only edit of a stored row passes.
  - **After it lands:** the full suite runs, and a fixture it refuses is
    fixed. `ClosedTradeCurrencyTest`'s third-currency case books its row
    another way, because the decision changes it, not to weaken a gate.
  - **Order:** α1 comes first, because α3 assumes two currencies at most.
- **α2, a first import's settlement legs follow the history (#1196; the
  ADR-0015 amendment, point 6).**
  - **The rule:** after the automatic FX history stores rates, the same
    SingleFlight run derives the legs those rates make derivable, journaled
    under a system actor.
  - **The candidates narrow:** only rows booked in their account's currency
    with none of the three legs stored. Today
    `Ledger.SettlementBackfill.candidates/0` would also overwrite a stored
    third-currency row's rate. The mix task narrows with it.
  - **Pinned:** the derived legs equal, field for field, what the import
    stores when the rate is already there (800,00 EUR, 1.000,00 USD,
    0,800000), and a row with legs gets no journal entry.
    `HistoryBackfillTest` and `SettlementBackfillTest` grow.
  - **Limits, both fail closed:** an import applied while the backfill is
    storing rates can miss both. The daily sync derives no legs. A trade
    then reads unavailable, never wrong.
- **α3, a closed trade is in one currency (#1198; the ADR-0015 amendment,
  points 2 to 5).**
  - **The rule:** every lot a sell closes enters in the sell's currency
    through its own stored legs, in both directions. A lot without the leg
    it needs makes the closed trade unavailable, with the reason
    `missing_settlement_leg`. It is named in `excluded`, told apart from a
    missing close-date rate, and drawn on board 09 (pick N8).
  - **What stays the same:** a trade whose sell and lots share one currency
    reads byte-identical figures, the import form's included.
  - **Red tests first:** identities 1 and 2b, then 3, then 4 as a diff of
    every payload before and after.
  - **The basis and the docs:** `Ledger.trade_fees_basis/0` drops its "#1198,
    an open decision" clause. The assertions in `docs_test.exs`,
    `api_v1_contract_test.exs` and `api_v1_cross_currency_trades_test.exs`,
    and the EN and DE guides, follow.
  - **No computation version moves:** no registered analytic reads closed
    trades or legs.
- **α4, a bond's coupon is its position's income (#928; the ADR-0051
  amendment).**
  - **Order:**
    1. I11's digest list and its re-drop and re-export tests, on unchanged
       code, where they pass;
    2. the red tests of I10, I12 and I13;
    3. the attrs, which turn I10 green and I11's re-export test red;
    4. the key's reading with no security, which turns I11 green again;
    5. the walk's clause, with the basis text and the version;
    6. the docs, the screen's note under the Zinsen line (EN, DE), the
       create tool's sentence, and a dated note on ADR-0029.

    The verification pass takes I11 first.
  - **Versions and contract:** `performance_contribution` and
    `performance_view_contribution` move from computation version 3 to 4;
    the walk stays at 4. Contract entry 18 names the three contribution
    routes and their two tools, the income read
    (`GET /api/v1/portfolios/:portfolio_id/income`,
    `portfolixir.portfolios.income`), whose per-position rows move, and the
    `transactions.create` description's new sentence.
  - **What changes value on screen** (board 09): Wealth's contribution
    table, where a bond's row rises by its coupons and the Zinsen line falls
    by as much, with a new note under that line; and Income's per-position
    table, Top-Beiträge and year detail. The matrix, the bars and every
    total stay.
  - **Found by the amendment, built here:** two equal coupons of two bonds
    in one file stop collapsing into one booking.
- **α5, a refund the row cannot carry is a row error (#1188, and #1177's
  negative fee; ADR-0053's A8 and A9).**
  - **In both parsers (A8):** a negative tax unit on a delivery, a security
    transfer or a cash transfer is a named row error with its remedy. The
    rest of the file previews (K16, K17).
  - **In a JSON file (A9):** a negative FEE unit is a row error (K18). A PP
    CSV already reads its Gebühren signed (the note of 2026-10-06, pinned
    by `csv_parser_test.exs`), so the CSV path does not change.
  - **Hashes:** every stored hash stays byte-identical. K25's hash list of
    every row is taken first, on unchanged code.
  - **What stays open:** #1177 itself, for its two PP types (D-4).
- **α6, the drawer books and corrects the one-amount cash kinds (#1052,
  #1206; board 03, pick N12; D-6).** It covers dividend, interest, deposit,
  removal, fee, tax and tax refund. It goes through the ledger functions the
  API already uses, so it brings no new money semantics.
  - **An edit keeps the kind and the cash account,** since the account fixes
    the amount's currency. A one-amount booking stored in another currency
    than its account's keeps the notes-only drawer, so a corrected amount
    never sits beside a stale rate. That fails closed, and it flips by a
    comment.
  - **The sheet's foot stays at its edge** on a phone, because the form
    grows past the sheet's height (board 03).
  - **Order:** it comes before α7, whose refused rows name a hand booking of
    a fee or a tax refund as their remedy.
- **α7, what the correction lists (#1194, #1205, #1193, with #1197;
  ADR-0053's A10 to A12; board 07, pick N21).**
  - **#1193 (A10):** a stored booking whose row the preview now refuses is
    listed per cash account, its stored figure against the file's, without
    a confirm (K19, K20). Stored JSON transfers are listed too.
  - **#1194 (A11):** a booking edited by hand since its import is named, not
    rewritten. "Edited" means an update that changes the cash, the price,
    the quantity, the fees or the taxes, so α2's legs and a merge's
    re-pointing do not block a correction (K21). A JSON trade is listed on
    a cash or a price difference (K22).
  - **#1205 (A12):** a drifted re-export's row is matched by its figures,
    under ADR-0053's A4 old-reading key. It gets a confirm only when no twin
    exists, and a row with a hash hit claims only the booking it hits (K23,
    K24).
  - **Order:** red tests K19 to K24 first; A10, then A11 (the journal, then
    the price), then A12 (the match, then the twin rule); the section's
    screen states last, against board 07.
  - **#1197:** the confirm dialog names a later set balance that absorbs the
    change, and the part it absorbs where it absorbs only part.
  - **Found while drawing, fixed here (board 07):**
    - the correction table fills its note and wraps, instead of widening
      past it;
    - the cause sentence covers only the lines the confirm corrects, and a
      second sentence names the lines that stay and why;
    - `stored_refusals/2` also covers A8's new refusals, not credits only;
    - a booking that is both refused and edited by hand reads as edited, and
      is kept.
  - **No API route,** because the import is an operator action (ADR-0029).
    The PR says so.
- **α8, the rename probe stops asking about a name it can place (#1195; the
  ADR-0050 amendment).**
  - **The rule:** a name whose importable rows the dry run finds all
    already booked on its resolution keeps its prefill once the dry run
    answers. Until then the row stays withheld. A choice made before the
    answer stands, and a stopped dry run releases nothing.
  - **What it does not do:** a remembered former name counts for nothing on
    its own. `former_names` records no author, so counting it could prefill
    the wrong account. A remembered name in a later export with a new
    booking therefore asks once more, by design.
  - **Order:** four commits in one group: the dry-run release and the
    timing in `Applier`, then `ImportsLive`, then the docs that
    `Portfolixir.DocsTest` pins. P1 to P5 are re-run first, then P6 to P10.
  - **A test seam:** P10 needs a way for a test to read the page before the
    dry run answers. The story adds one.
- **α9, the preview resolves a security as the apply will (#1203).** The
  preview simulates the run's own creations in file order. This is import
  idempotency, so it gets its own commit group.
- **α10, an account move and a cash merge no longer deadlock (#1214).**
  - **The change:** the edit takes the new account's lock before the
    booking's row lock, and a 40P01 becomes a retryable answer. Contract
    entry 18 names that answer.
  - **Lock order, as Sprint 20's retrospective asked:** the commit carries a
    lock-order table of every writer of `cash_accounts` and `transactions`
    rows, beside the lock-race harness (D-7).
  - **Pinned in both orders** in the existing lock-race tests.
- **α11, the history and the trades say what they count (#1209, #1212,
  #1213).**
  - **#1209:** the history's Betrag is the cash the balance moves, and its
    header sum equals the balance change. The drawer's own same-currency buy
    stores no `gross_amount` either, so the fix reads the projection's cash
    rule, not the write path (board 03).
  - **#1212:** the holdings, category-result and trades payloads and the
    tooltip state whether fees and taxes are in a figure. The figures do not
    change.
  - **#1213:** each money figure of a cross-currency row names its currency
    (board 09, pick N9; board 03).

**Contract entry 18** carries α's changes and β's below:

- α1's 422;
- α3's converted figures, the unavailable fields and the reason in
  `excluded`;
- α2's counts in the history-backfill answer;
- α4's versions and moved rows;
- α10's retryable answer;
- α11's stated definitions;
- the MCP descriptions that change with them.

### β — nothing a screen shows changes (the sprint PR)

- **β1, the converter prompt says what the importer reads (#1216).** It
  covers the decimal rule with its own example, the description,
  `first_setup`'s second path, and the heading. All of it is pinned in
  `prompts.test.ts`. It costs no schema bytes, because prompts are not
  budgeted.
- **β2, an agent reads back a draft plan's targets (#1185).**
  - **The change:** `targets.list` and `targets.list_positions` take the
    writes' `plan_id`, with the same refusals. The drift basis says when it
    reads a draft.
  - **Bytes:** about 190 per profile, paid by trimming (D-9).
- **β3, a metric sort sorts (#1186).** The plain securities list sorts by
  the metric and pages after sorting, as the data-quality path already does.
- **β4, the Release workflow watches what enters the images (#1189).** Both
  `.dockerignore` files join its paths, and `ci_test` follows.
- **β5, two helpers without callers go (#1192).**
- **β6, a token's floor and its randomness (#1202; D-4, answer (a)).**
  - The docs say "a random token from `openssl rand -base64 48`". That
    covers SECURITY.md, `.env.example`, the guides EN and DE, `llms.txt`
    and contract entry 18.
  - ADR-0045's note of 2026-10-08 gains a dated correction: the floor
    checks length only.
- **β7, a capped load that hits its cap shows its own failure (#1204; D-4,
  answer (b)).**
  - **The change:** inside `CappedAsync` only, a linked, uncapped wrapper
    monitors the capped worker and exits when the worker dies, so LiveView
    reports `{:exit, reason}`. No call site changes.
  - **Pinned** with a lowered-cap reproduction on Wealth, and the
    capped-tasks invariant stays green.
- **β8, DESIGN.md follows the chart build (#1200, variant A).** This is docs
  only, with no board, because no picture changes.
- **β9, the import apply's per-row cost, measured (#971).** It is a
  measurement only, with a synthetic large-file generator and a timed run
  on two commits. The numbers go into #971 and decide #925. It is the first
  item the shrink order cuts.

### γ — the UI batch (the stacked PR; boards 01 to 08)

Each group is one board's surface, built against its board. Each story writes
the board's anatomy into `DESIGN.md` (the sprint workflow's rule 3). The
design critic reviews each built surface against its board.

- **γ1, the Overview (board 01):** #1114 (N2), #1121's card half (N3),
  #1122 (N4, option 3), #1171 and #1208. It also carries #1169 if N1 is
  picked.
- **γ2, the securities list and a security's page (board 02):** #1104 (N6),
  #1121's list half (N3.2), #1112 (N7), #1139, #1151, #1163 and #1201.
- **γ3, the history (board 03):** #1147 (N10) and #1148 (N11). α11 and α6
  carry the drawer's half of the board in α.
- **γ4, Wealth, Income and Cash flow (board 04):** #1125 (N5), #1123,
  #1149, #1210 and #1150.
  - **#1149 changes the shared `Format.money` and `Format.percent`.** It
    gets its own commit and a sweep test over exact strings.
  - **#1210 adds a month's total to the Costs read.** Its computation basis
    and contract entry 19 follow.
- **γ5, Accounts and depots (board 05):** #1145 (N15), #1162 (N16) and
  #1161.
- **γ6, Classifications (board 06):** #1165 (N17), #1211 (N18), #1158 and
  #1187.
  - #1187 moves the archived-plan guard into the Targets context, so the
    screen and the API share one rule.
- **γ7, the Imports page (board 07):** #1180 (N20), #1130, #1178, #1179,
  #1181, #962 and #1207.
  - **#1180, variant A, is close to risk tier:** the recount must equal
    what the apply skips. It gets its own commit and an equality test.
- **γ8, shared components and copy (board 08):** #1166 (N13), #1155 (N14),
  #1138, #1160, #1157 and #1191.

**Contract entry 19** carries #1210's Costs total.

### Lane Z — registry (small)

- **Right after the merge:**
  - close #1182 and #1190 by hand, each with its reason and what reopens it
    (D-4);
  - if the merge brought no comment naming N1, close #1169 as not planned,
    with your ruling of 2026-08-05 as the reason;
  - relabel #1177 `needs-decision`, with its answer and what builds it
    (D-4);
  - relabel the nine answered `needs-decision` issues `agentic`;
  - file the eight issues the UX document lists, each under its area
    tracker, after a title search: six findings from the boards and the
    deferred asks of ADR-0053 and ADR-0050, three of them `needs-decision`
    with their recommended answer (D-10);
  - give #951, #894 and #899 an area parent, because their parent #883 is
    closed (D-12).
- **On the sprint PR and the stacked PR:**
  - the body carries Lane Z as a checklist, covering the issues each PR
    files as well as the ones it builds;
  - a filing searches the open titles first, and sets the area parent as it
    files.
- **Registry edits already on this PR:**
  - `sprint-status.yaml` gains the PLANNED entry;
  - the Tracker Index's E26 line names Sprint 21;
  - FR-2's, FR-5's, FR-6's and FR-41's rows name the ADR-0015, ADR-0053,
    ADR-0050 and ADR-0051 amendments.

## Decisions

### D-1: what this sprint is for, and its four exit criteria (recommended)

**Sprint 21 makes the figures right after the first import, and builds every
screen repair that has waited for its board.** It passes when all four
hold:

1. **Every money issue closes by keyword:** #1198, #1199, #1196, #928,
   #1188, #1193, #1194, #1205, #1195, #1209, #1212, #1214 and #1052. A miss
   names the issue and its step.
2. **The round trips pass at α's closing act**, run by the UAT persona on
   synthetic data in the German UI:
   1. **Import, then sell.** A PP JSON file buys a USD security from a EUR
      account. A sale booked in the drawer in USD closes it, and the realized
      result reads the ADR-0015 amendment's identity 1: **188,75 USD =
      151,00 EUR**, which is the cash the two bookings moved (957,00 −
      806,00). Today it reads 312,20 EUR. A lot without legs reads
      unavailable, named, and outside the totals (identity 3).
   2. **The coupon.** A bond's INTEREST row imports with its security. On
      Wealth's contribution table the coupon is the bond's income, and the
      interest line is that much smaller. ADR-0051's I12: the bond reads
      **525,00 EUR** and the Zinsen line **1,10 EUR**, against 125,00 and
      401,10 before, and the result stays **526,10 EUR**. A second drop books
      nothing, and neither does a re-export with a moved time (I11).
   3. **The re-export.** A JSON history imported under the old reading is
      dropped again, with one booking edited by hand, one row whose time
      drifted, and one stored sale the preview now refuses. The correction
      lists exactly the expected lines:
      - the hand edit is named and kept;
      - the drifted row is matched by its figures, with a confirm;
      - the refused sale is listed without a confirm.

      The figures put ADR-0053's K19, K21 and K23 on one account, which PP
      shows at 1.049,23 EUR:
      - the account stored **1.099,23 EUR**, the refused sale's 25,00 and
        the drifted sale's 25,00 too high;
      - it reads 1.099,30 after the hand edit of 0,07;
      - it reads **1.074,30** after the confirm, which corrects the drifted
        sale alone.

      The 25,07 left is the refused sale's 25,00 and the kept edit's 0,07,
      each named on the page.
   4. **The delivery with a negative tax.** The file previews with one named
      row error, and the rest books.
   5. **A dividend corrected on screen.** Its amount is changed in the
      drawer. The balance moves by the difference, and the journal records
      the edit.
3. **The UI batch matches its boards.**
   - The design critic finds every built surface matching its board, at 390
     and 1200 px, light and dark, in German.
   - The UAT persona walks the Overview, the securities pages, the history,
     Wealth, Accounts, Classifications and Imports on the review seed.
4. **The count:**
   - **Fewer than 60 open issues at the close-out.** The merge leaves 90:
     two closed by hand, eight filed. It leaves 89 if #1169 closes. The
     sprint closes 64 by keyword, or 65 if N1 is picked, which leaves 25.
     That allows 34 filings, against the 31 Sprint 20's build and closing
     acts filed.
   - **Every `needs-decision` issue open at the close-out carries its
     recommended answer** and what would reopen it if closed.
   - **Scope Lock still binds:** a finding is filed, never withheld to make
     the count (D-13).

**To flip by comment:** name a criterion to drop, or a different threshold
for the fourth.

### D-2: the four amendments, in one paragraph each (recommended; signed by the merge)

- **ADR-0015, a closed trade is in one currency (#1198, #1199, #1196).**
  - **Why:** today a security's FIFO queue sums lots in two booking
    currencies, under the sell's currency code. That happens on ordinary
    paths:
    - a PP import, then a sale in the drawer;
    - an API booking in the account's currency;
    - one security held in depots of two account currencies.

    The basis does not say so, and the totals carry it.
  - **The fix:** a foreign lot is converted through its own legs (option d).
    A lot without legs makes its trade unavailable rather than wrong (option
    c, as the fallback).
  - **Why not the other options:**
    - moving imported rows into the security's currency (a) changes every
      import-only trade;
    - moving hand-booked rows into the account's currency (b) breaks the
      2026-10-07 amendment's identity 1;
    - splitting the queue per currency breaks FIFO order and leaves
      orphaned sells.
  - **With it:** #1199 refuses a third currency, and #1196 gives a fresh
    import's lots their legs once the history arrives.
- **ADR-0053, what the parsers refuse and the correction lists (#1188,
  #1177's fee, #1193, #1194, #1205).**
  - **Refused:** a refund that the row's own cash leg cannot carry, and a
    negative fee, become row errors instead of a rolled-back file or a
    flipped sign.
  - **Listed by the correction:**
    - a stored booking the preview now refuses, without a confirm;
    - a booking edited by hand since its import, named and never rewritten;
    - a drifted row matched by its figures, confirmable only when it has no
      twin.
  - **Hashes:** every stored hash stays byte-identical.
- **ADR-0050, the rename probe (#1195).** The 2026-10-07 probe withholds the
  prefill of any name with no hash hit, so a same-file re-drop and a
  drifted re-export ask on every drop. The amendment lets the probe read the
  dry run's answer: a name whose rows are all booked on its resolution is
  released. A real rename still waits, so P1 to P5 hold.
  - **What was decided against:** counting a remembered former name as seen
    was dropped, because the store does not record who wrote a name. A
    wrong prefill would book a history twice. That half is deferred, with
    its trigger.
- **ADR-0051, the coupon (#928).**
  - **The change:** an imported interest row keeps the security its row
    names, and a security-linked interest booking is that position's
    income. Rows stored without their security stay in the interest line,
    as its basis says.
  - **What stays the same:** cash, balances and the walk's return figures
    are untouched.
  - **The cost:** the contribution analytics move to computation version 4.

### D-3: #1169 is your pick, and silence keeps your ruling (owner)

**Why it is yours.** On 2026-08-05 you ruled the count-up "acceptable and
wanted, provided it is visually evident that the number is still counting".
#1169 says a glance or a screenshot can still read a figure that never
existed. A recommendation that reverses your own ruling is not adopted by
silence.

**What happens today, step by step** (read from `dashboard_live.ex` and the
CountUp hook in `layout_view.ex`):

1. **The total is computed in the background** once the page connects, and
   that takes as long as the valuation takes. Meanwhile the card shows its
   pending state: the last known year-to-date figure, dimmed and labelled
   "Letzter Stand … Wird neu berechnet", or a skeleton with "wird
   berechnet". The total in EUR has no stored last value, because the
   valuation is not memoised.
2. **Only when the computed total has arrived does the count-up start.** It
   runs from 0,00 to that already-known figure over 600 ms.

So the count-up does not cover the computing time. It adds 600 ms of
figures that never existed after the real one is known. Every variant below
leaves step 1 as it is.

**The variants, on board 01:**

- **A:** no count on money figures.
- **B, recommended:** when the computed total arrives, it appears as it is,
  and a count runs only between two real figures. The reason you gave, the
  three dots, belongs to the pending state of step 1, which B leaves
  alone.
  - **What B means in practice, measured on the code:** almost never a
    count. The Overview has no view or period control. Wealth's view switch
    is a full page load, and its period does not change the counted
    figures. A count would run only when Wealth re-values in place after a
    rate sync. So B is close to A, and it is honest to read it that way.
- **C:** the digits are hidden while counting. That brings back the blank you
  disliked.

**Silence:** your ruling stands, and #1169 closes as not planned after the
merge. **"N1 B"** (or A, or C) builds it in γ1.

### D-4: the decision pass: every open question gets an answer (recommended; each row flips by naming its issue)

**Answered and built this sprint (nine), relabelled `agentic` at the
merge:**

| Issue | Answer | Where |
|---|---|---|
| **#1188** | (a) a named row error in both parsers; the rest previews | α5; ADR-0053 |
| **#1193** | (a) listed with both cash figures and no confirm | α7; ADR-0053 |
| **#1194** | (a) a hand edit is named, not rewritten; a price difference lists a JSON trade | α7; ADR-0053 |
| **#1195** | (a), without its former-name half: a name the dry run finds all booked keeps its prefill; a former name alone counts for nothing | α8; ADR-0050 |
| **#1196** | (a) the history's run derives the missing legs, journaled | α2; ADR-0015 |
| **#1198** | (d), with (c) as its fallback | α3; ADR-0015 |
| **#1202** | (a) the docs say a random token; the floor stays length-only | β6; a dated note on ADR-0045 §1 |
| **#1204** | (b) a linked, uncapped wrapper inside `CappedAsync`; no call site changes | β7 |
| **#1205** | (a) with the twin rule | α7; ADR-0053 |

**Answered here and not built (one):**

| Issue | Answer | Reason | Reopened by |
|---|---|---|---|
| **#1182** | closed as not planned | 32 is a cycle guard written into the API and MCP contract. No import builds trees, and capping the indent with the level printed as text (option b) makes any depth readable without a contract change | a real tree deeper than about 8 to 10 levels, or a tree import; then (b) |

**`agentic` issues that needed a decision rather than a build:**

| Issue | Answer | Reason | Reopened or built by |
|---|---|---|---|
| **#1190** | closed as not planned | it cannot happen: the bucket read and its locked write run inside the import's transaction, on accounts that run created, which no other transaction sees before the commit | a writer that tags an account another transaction can see before the import commits |
| **#1177** | split: the negative FEE unit becomes a row error in α5; the two PP types stay open, relabelled `needs-decision`, with the answer "two new ledger kinds, `interest_charge` (cash out, a cost in the Costs report) and `fee_refund` (cash in, a negative cost), by an ADR-0028 amendment" | a new ledger kind changes the data model and the Costs report, and needs its own record. Until then the preview names the row, and nothing books silently | a switcher's export carrying either type, or the first sprint after the announcement |

**A rule carried from Sprint 20:** a `needs-decision` issue a closing act
files carries its recommended answer and what would reopen it if closed.

### D-5: the sprint does not wait for the announcement (recommended)

The plan holds whether or not you announce during the sprint.

- **If you announce first,** the money fixes reach newcomers with the
  sprint PR's merge, before the stacked PR.
- **If you do not,** nothing changes.

**What the close-out adds instead of a launch readiness v4:** a dated
"Since version 3" section at the end of
`launch-readiness-2026-10-09-sprint20.md`. It holds:

- the money list, which this sprint should empty except #1177's two types;
- the count;
- the upgrade notes of both merges.

A fifth page would repeat four.

### D-6: #1052 and #1206 — the drawer books and corrects the one-amount cash kinds (recommended; board 03, pick N12)

**Why now.**

- **#1052** is the two-way finding Sprint 19's D-6 missed on purpose and
  Sprint 20 kept missed. The API corrects a dividend's facts in place, and
  the screen cannot.
- **#1206** is the remedy the import's refusal of a credit row names:
  "book the tax refund by hand". No screen can do that today, so a refusal
  sends the operator to the API.
- **ADR-0053's amendment** sends #1193's listed sale to the same remedy.

**The answer.** The drawer gains booking and in-place correction of
dividend, interest, deposit, removal, fee, tax and tax refund.

- **How:** one form with the kind first, then date, cash account and amount,
  plus a security where the kind takes one (pick N12, variant A).
- **What is reused:** it runs through `Ledger.create_transaction/3` and
  `Ledger.update_transaction/3`, the functions the API already uses. A new
  route to them is no new money semantics.
- **What an edit keeps:** the kind and the cash account. A booking stored in
  another currency than its account's stays notes-only (board 03).
- **What keeps delete-and-re-import:** transfers, deliveries and balance
  snapshots, which have two legs or a snapshot's own rule. The PR states
  the reason, as the coverage rule allows.

**Risk tier.** It writes money, so it gets its own commit group and a
verification pass. Every identity in it is pinned against the API's answer
for the same write.

### D-7: #1214 and the lock-order table (standing; Sprint 20's retrospective)

**The rule from Sprint 20's retrospective.** A new lock is reviewed against
every writer that locks the same rows in another order, not only against the
race it closes.

**α10 writes the table first, as a module doc beside the lock-race harness.**
It lists every writer of `cash_accounts` and `transactions` rows, with its
order:

- the cash merge;
- booking create, update and delete;
- the account's currency change and identity freeze;
- the importer;
- the import correction;
- the bucket writers;
- the depot merge;
- α6's drawer.

α10's change is then checked against each row. The verification pass runs
the lock-race harness with both orders of #1214's pair.

### D-8: one sprint PR and one stacked PR (standing, ADR-0026's two-PR amendment)

| PR | Commit groups | Estimate | Why this order |
|---|---|---|---|
| **sprint PR** `agent/<provider>/sprint-21` | Lane M, α, β, their closing acts | about 66 | the money reaches your instance first; β is independent and small |
| **stacked PR** `agent/<provider>/sprint-21-ui` | γ, its closing act, the close-out | about 63 | the screens build on α's drawer and α11's labels (board 03, board 09) |

**Why two.** About 129 commits is above the 90 of the two-PR amendment. The
stacked PR opens on the sprint PR's head as soon as β's closing act is done.
Its base moves to `main` when the sprint PR merges. You merge both, the
sprint PR first, each by rebase.

**Sprint 20's retrospective, carried forward as duties from the first
commit:**

1. **An agent commits each test-first step as it lands.** A paused rebase is
   resumable by anyone, because two container restarts lost running agents.
2. **A dependency change gets its own deps directory** (`MIX_DEPS_PATH`)
   until it lands.
3. **A new lock gets the lock-order table** (D-7).
4. **A test module that creates securities takes ISINs of its own.** The
   implementation session turns Sprint 20's scan into a test in β's first
   commit, so the next collision fails a test rather than a gate run.
5. **Stack early.** γ runs α's and β's invariants on its branch from its
   first commit, since parallel groups met only when stacked.
6. **A scripted rebase continues with `-c commit.cleanup=verbatim`**, since
   the message cleanup cut three Sprint 20 messages.
7. **Work recovered from a lost agent runs the full gates** before its
   commit.
8. **An "only the owner can" claim is checked against what CI can do**
   before it enters a plan or a briefing. This plan's one owner pick (N1) is
   the owner's own ruling, which no CI can make.
9. **Every agent brief names its base commit and says to read a gate's exit
   status directly, never through a pipe.** Every push runs all fifteen
   gates.

### D-9: the schema budget (standing rule, stated with its cost)

The ceilings stand where Sprint 20 left them: read 103,261, book 176,275 and
full 206,672 bytes (`mcp-server/test/support/schema-budget.ts`). Prompts are
not budgeted.

- **α** adds no tool and no parameter. Descriptions whose basis sentences
  change (α3, α4, α11) pay for themselves.
- **β** adds `plan_id` to two read tools (β2), about 190 bytes in each
  profile.
- **γ** adds no tool or parameter. #1210's month total is a payload field.

**Each group trims existing descriptions by at least what it adds, then
lowers the ceilings to the new figures.** A raised ceiling is a weakened
gate and a review reject.

### D-10: the design picks (recommended; silence adopts them, except N1)

Nine boards, under
`planning-artifacts/design-language/mockups/ux-design-2026-10-09/`, argued
in `planning-artifacts/ux-design-2026-10-09-sprint21.md`. The pick letter is
**N**: it skips M, which names the maintenance lane.

| Pick | Item | Board | Plan | Recommended |
|---|---|---|---|---|
| **N1** | The Overview's total counts up from 0,00 (#1169) | `01-overview` | γ1, only if picked | **your pick**; silence keeps your ruling; B recommended (D-3) |
| **N2** | The KPI strip's dates between 561 and about 665 px (#1114) | `01-overview` | γ1 | **A**: the two-by-two switch moves from 560 to 680 px |
| **N3** | A wrongly valued holding and the total, the card half (#1121) | `01-overview` | γ1 | **A**: the data-quality findings say what they do to the total; the card stays silent |
| **N3.2** | `?dq=two_scales` lists bonds with no direction or remedy (#1121) | `02-securities` | γ2 | **A**: a problem note per direction above the list, each bond linking to its remedy |
| **N4** | "Details in Vermögen →" (#1122) | `01-overview` | γ1 | **option 3**, adopted by Sprint 20's D-4: `?period=ytd`, read on arrival, never stored |
| **N5** | Wealth's value columns print "2.569,676EUR" (#1125) | `04-wealth-income` | γ4 | **A**: money through `Format.money`, prices by R10c, a space before the suffix |
| **N6** | A boolean chip reads "Stillgelegt = false" (#1104) | `02-securities` | γ2 | **A**: "Stillgelegt: nein", one rule for every boolean field |
| **N7** | The detail page is silent about a reverse two-scales bond and an implausible quote (#1112) | `02-securities` | γ2 | **A**: both as problem notes on the Overview tab, linking to Kurse |
| **N8** | A closed trade whose lot has no leg in the sell's currency (#1198) | `09-money-states` | α3 | **A**: the Trades tab keeps the row with the reason dash and its remedy; Income and the Overview card name it in their exclusion note |
| **N9** | A cross-currency row's money figures name no currency (#1213) | `09-money-states` | α11 | **A**: a suffix on every money cell of a cross-currency row, only there |
| **N10** | An inflow and an outflow differ only by a minus (#1147) | `03-history-drawer` | γ3 | **A**: an explicit "+" on inflows, no colour |
| **N11** | The Preis cell names no currency (#1148) | `03-history-drawer` | γ3 | **A**: always the price's own currency |
| **N12** | The drawer books and corrects the one-amount cash kinds (#1052, #1206) | `03-history-drawer` | α6 | **A**: one drawer, the kind first; an edit opens the same form, kind and cash account fixed |
| **N13** | Dismissing an inline result drops focus to the body (#1166) | `08-shared-copy` | γ8 | **A**: the control that produced the result, else the section's heading |
| **N14** | A twin security named inside a sentence (#1155) | `08-shared-copy` | γ8 | **A**: the `.twin-id` tag after the name |
| **N15** | The accounts table is cut at 768 and 1024 px (#1145) | `05-accounts` | γ5 | **A**: the shipped cards wherever the table does not fit, by a container query (840 px) |
| **N16** | The Buckets ⓘ on a phone card explains a word it never shows (#1162) | `05-accounts` | γ5 | **A**: the card opens the bucket cell with "Buckets ⓘ" |
| **N17** | The tree's name column collapses between 561 and 720 px (#1165) | `06-classifications` | γ6 | **A**: the two-line rows up to 720 px, written as a container query |
| **N18** | A category cannot be moved under another parent (#1211) | `06-classifications` | γ6 | **A**: "Übergeordnet" in the edit form, without itself and its descendants |
| **N20** | A mapping row's count ignores the operator's choice (#1180) | `07-imports` | γ7 | **A**: recount through the existing dry run, with the computing cue |
| **N21** | The correction section's three new line states (#1193, #1194, #1205) | `07-imports` | α7 | **A**: one table, each state a line under its booking; the confirm counts only what it writes |
| — | #1171, #1208; #1139, #1151, #1163, #1201; #1209, #1213's drawer label; #1123, #1149, #1210, #1150; #1161, #1160; #1158, #1187; #1188 and the fee, #1195, #1130, #1179, #1207, #1197, #1178, #962, #1181; #1166's ring, #1155's tables, #1138, #1157, #1191; #928 | each surface's board | their groups | before/after: after |

**N19 is not used:** #1187 needed no choice. The UX document argues every
pick, gives the German and English strings and the measured sizes, and says
what each story writes into `DESIGN.md`.

**Items with no board:**

- every story of β, which renders nothing, and #1200 (β8), whose picture the
  build already shows;
- α1, α2, α9 and α10, which change values or refusals inside an anatomy a
  board already draws, or render nothing. α5's row errors and α8's
  withheld and released rows are drawn on board 07.

**The "found while drawing" items** carry the verdicts the UX document
gives them:

- fixed in the story that touches the surface (D-13);
- or filed at the merge under their area tracker (Lane Z).

### D-11: what stays open on purpose (recommended)

| Issue | Action | Reason |
|---|---|---|
| **#328**, **#354** | stay open | the owner's runs on real data |
| **#1177** | stays open, `needs-decision` | its two PP types need new ledger kinds (D-4) |
| **#1115** | stays open: the MCP SDK v2, its own risk-tier lane | v1 has fixes until at least 2027-01-27. The lane is planned no later than the first sprint of January 2027, or at once if a v1 advisory has no 1.x fix. The companion publishes its own schemas through a raw `tools/list` handler, so the budgeted bytes do not move |
| **#957**, **#1070** | stay open: one later risk-tier lane | the merge preview's flow effects and bond data, under one ADR-0050 reading |
| **#925** | stays open | after #971's measurement (β9) shows the hash check dominates |
| **#951** | stays open | about 0.4 KB with `maxLength` alone, or about 2 KB with the cap sentence. It needs a description-trim lane of that size |
| **#894** | stays open | size L; its shape (a parameter or a read tool) is open, and nobody has mis-deleted |
| **#899**, **#900** | stay open | after the announcement decision, as Sprint 20 kept them |
| **#416–#420**, **#991** | trackers | #991 holds its 100 and closes with the announcement decision |

### D-12: a parent for every open issue (standing, Sprint 20's D-14)

#951, #894 and #899 hang under #883, which is closed. Lane Z moves them:

- #951 to #419;
- #894 and #899 to #420.

#1052 and #1070 keep #991 until it closes. Every filing gets its area
parent when it is filed.

### D-13: the closing act, one lens per risk class, and on-surface findings (standing)

| Group | Lenses |
|---|---|
| **α** | correctness hunter; **a money and idempotency lens over each amendment's identities, one at a time**: ADR-0015's import-then-sell identity first, ADR-0053's digest list first, ADR-0051's I11 first; the **lock-race lens** over α10 against D-7's table; an edge-case hunter on α7's twin rule and α8's timing; a **design critic** against boards 03, 07 and 09 in German at 390 and 1200 px, light and dark; **the UAT persona runs round trips 1 to 5** |
| **β** | correctness hunter; **a security lens over β6 and β7** (the docs' claim, and the wrapper's exit path under a cancel and a dying page); the agent's lens over β1 and β2 (the prompt against the importer, a draft plan read back) |
| **γ** | correctness hunter; **a design critic per board**, 01 to 08, each against its board and `DESIGN.md`; an accessibility pass over #1166, #1147 and #1138; **the UAT persona walks D-1's criterion 3** |

Sprint 20's rule stands. A finding on a surface the PR already changes,
small and with its answer in the spec, is fixed on the branch. A finding off
the PR's surface, or one that needs a choice, is filed under Scope Lock with
its area parent. **Nothing is withheld to make D-1's count.** A cascade
stops when a layer yields no major finding. Each PR reserves its closing
act and its briefing before its first story. If the weekly usage limit
comes into view, the shrink order applies from its first step, and the
closing acts are not what is cut.

### D-14: the review seed carries what the round trips need (recommended)

The UAT persona and the design critic need the round trips' shapes on the
review seed:

- a USD security imported from a EUR account and sold by hand;
- a bond with a coupon;
- a delivery with a negative tax;
- twin names;
- an archived plan version;
- a classification tree three levels deep.

Each story that needs a shape adds it to the seed in the commit that
builds its surface. The seed stays synthetic, and a second run of it leaves
every row alone (#1126).

## Sequencing

```text
after the merge ── Lane Z: #1182, #1190 closed (and #1169 if silent);
                   #1177 relabelled; nine relabelled agentic; the
                   design pass's off-surface findings filed; three re-parented
sprint PR opens ─▶ Lane M ─▶ α: α1 #1199 ─▶ α2 #1196 ─▶ α3 #1198
                   ─▶ α4 #928 (I11 digests ▶ red I10/I12 ▶ attrs ▶ key ▶ walk)
                   ─▶ α5 #1188 + fee (K25 hash list ▶ red ▶ parsers)
                   ─▶ α6 the drawer #1052 #1206 (so α7's remedy has a screen)
                   ─▶ α7 #1193 #1194 #1205 #1197 ─▶ α8 #1195 ─▶ α9 #1203
                   ─▶ α10 #1214 (lock-order table first) ─▶ α11
                   α's closing act, round trips 1–5
                 ─▶ β: β1 … β9; β's closing act ─▶ promoted
stacked PR opens ▶ (on the sprint PR's head) γ1 … γ8, board by board
                   γ's closing act ─▶ close-out records ─▶ promoted
the owner ──────── merges the sprint PR (a release), then the stacked PR
                   (a release)
```

## Shrink order (cut from the top, name the cut in the briefing)

1. **β9**, #971's measurement (#925 waits on).
2. **γ8's #1155 note half** (N14), then **#1163**.
3. **γ6's #1211** (N18) and **#1187**. The boards stay signed for the next
   batch.
4. **α9, #1203.**
5. **γ7's #962 and #1207.**

**What does not shrink:**

- every money issue of D-1's first criterion, and the four amendments'
  builds;
- the round trips;
- α6, the two-way debt;
- the decision pass's closures.

## What is deliberately not in this sprint

- **New features.** #894, #899 and #900 wait (D-11).
- **New ledger kinds** for PP's `INTEREST_CHARGE` and `FEE_REFUND` (#1177,
  D-4).
- **The MCP SDK v2** (#1115, D-11).
- **An import route under `/api/v1`**: the import stays an operator action
  (ADR-0029).
- **B3.3, B3.5, B3.7, B3.8** and ladder level (d): shut.
- **Phone access as a product** (the widening phase). γ repairs the screens
  at 390 px as the spec already requires; it adds no phone feature.

## What "done" means for this sprint

1. **Both PRs are merged in order**, each green on its head, each with its
   closing acts under D-13 and its briefing.
2. **The four amendments are built as signed:**
   - ADR-0015's identities;
   - ADR-0053's K-identities;
   - ADR-0050's P-identities;
   - ADR-0051's I10 to I13.

   Each identity is pinned, seen failing first, and mutation-checked.
3. **D-1's four exit criteria are recorded**, each pass or fail with its
   step.
4. **The decision pass is carried out:** two closed by hand at the merge
   (three if silent on N1), nine relabelled, #1177 relabelled with its
   answer, and the design pass's findings filed with their parents.
5. **#1052 and #1206 close, so the two-way debt Sprint 19 recorded is
   paid.** #1185 closes the read half of Sprint 20's #1133.
6. **Each merge produced a calendar release**, and contract entries 18 and
   19 name what changed.
7. **The schema budget's ceilings are no higher than today's.**
8. **The close-out's surface check** names:
   - β2's `plan_id` across the target family's reads and writes;
   - β3's metric sort across the securities list's two paths;
   - #1210's month total across the Costs read, its MCP tool and the
     screen;
   - α3's unavailable state across the trades, realized-gains, Income and
     Overview reads.
9. **The "Since version 3" section** is appended to launch readiness (D-5).
