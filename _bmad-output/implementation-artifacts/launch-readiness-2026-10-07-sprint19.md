# Launch readiness, version 2 — 2026-10-07 (Sprint 19 close-out)

This is the one page the Sprint 19 plan asks for ("What the owner decides
after this sprint"), in the shape of `launch-readiness-2026-10-04-sprint18.md`.
The announcement stays the owner's call (Sprint 17's D-1). Passing all four
exit criteria is necessary for it, and not sufficient. The full records are in
`sprint-status.yaml`'s Sprint 19 entry. `main` is at `95bc398e`, release
2026.10.12, API contract version 15.

## The recommendation, first

**Do not announce yet. The sprint failed its own exit test.** Two of its
four exit criteria did not hold:

- **Criterion 4 failed outright:** 132 open issues, against fewer than 100.
- **Criterion 3 is unproven on the route it names.** The Docker build needs a
  Debian mirror that this machine cannot reach. The agent therefore ran the
  README's from-source route, and there all three answers were exact.

Three things follow from that:

- **The plan's rule decides what comes next:** "If a criterion fails, the
  summary names it, and that becomes Sprint 20's plan."
- **The money and the first run are in better shape than the count
  suggests.** Every H issue the plan named is closed, the first-look test
  passed with "is this everything?", and nothing the closing acts found was
  withheld.
- **But the backlog grew by 15 in a sprint cut to shrink it**, and eight open
  issues fit the plan's own H definition again (see below). Two of them give
  a wrong money figure on a cross-currency trade.

**What would change the count, and what would not.** Sprint 19 closed 56
issues, more than any lane plan expected. It still filed 71, because each
lane PR reviews the surfaces it touches and files what lies next to them.
Another sprint of the same shape fails criterion 4 the same way.

Two levers exist, and both are the owner's:

1. **Decide the 46 `needs-decision` issues in one pass.** Many are "decisions
   waiting for a need" (D-12). Closing one as "not planned, reopens when …"
   is a decision, not a cut, and it is the only lever that shrinks the list
   without a review that refills it.
2. **Run a sprint with no new surface:**
   - the eight H-class leftovers;
   - the nine E25 follow-ups, which D-12 names as "a clean lane of nine
     closures with no rendered change";
   - agentic L issues that ride no board.

   No closing act on a new screen means few new findings.

If the owner wants the threshold changed instead, D-1 allows it: "name a
criterion to drop, or a different threshold for the fourth."

## The four exit criteria

| Criterion | Result | Record |
|---|---|---|
| 1. Every H issue closed | **PASS** | #1076, #1081, #1055, #1051, #1048 and #1068 by PR α's keywords; #1042 and #1092 by PR β's. |
| 2. The operator's first-look test, with "is this everything?" and a PP round trip | **PASS** | At γ's closing act, on the synthetic seed, German UI, 1440 and 390 px, light and dark. The four figures were exact (total 73.657,92 EUR; largest contributor this year +1.257,50; a closed trade's +17,8 % p. a.; a cash balance 4.274,90 EUR). Every "is this everything?" was answered from the screen. The correction from the screen worked. The rewritten `sample.csv` read Test-Cash **4.017,68 EUR**, exact, and the re-drop booked nothing (0 created, 13 skipped). |
| 3. The agent's launch test on the documented build route | **NOT PROVEN on the build route**; the agent's part **PASSES** | The documented Compose build installs Debian packages first, and this machine reaches no Debian mirror. Every variant in the deployment guide needs a reachable mirror or a second machine. That is the one prerequisite, and no file stood in for it. On the README's "Run from source" route, the agent connected the companion (`book`), converted the bank export through `import_converter`, and got a preview with no warning. Its three answers were exact: 13,659.20, 200.75 and 2,297.75 EUR. |
| 4. Fewer than 100 open issues | **FAIL** | **132 open**, against 117 at the planning. That is 33 more than the criterion allows (99 or fewer). Closed 56, filed 71: see "Open issues by label". |

### The agent's launch test, step by step

The run: 2026-10-07, against `main` at `95bc398e`, under #998's protocol. A
fresh Claude Code subagent worked in an export of that tree without
`test/fixtures/launch_test/` and without git history.

1. **Setup.** The agent read the README, `llms.txt` and the pages they link.
   - **The Compose route cannot get past its first build step here.** That
     step installs Debian packages, and this machine's egress denies
     `deb.debian.org` and `security.debian.org`; eleven other mirrors
     answer 403 too.
   - **The session's permission check also refused** the agent's
     `docker compose up --build -d` and the documented override file, so
     the build itself never ran. The prerequisite rests on probing the same
     hosts through the same proxy.
   - **The agent then took "Run from source"** on a database of its own.
     It changed no tracked file, checked by hash.
2. **The agent's part.**
   - It connected the companion over stdio with the `book` profile: 114
     tools, contract version 15.
   - It used `first_setup` read-only and wrote nothing that needed the
     operator.
   - Through `import_converter` it wrote a deterministic converter and a
     CSV with nine bookings.
   - The preview, as a dry run, showed no error and no warning.
3. **The drop.** The stand-in user kept every proposal except the one the
   agent named, leaving the bucket tag off. 9 bookings were created, with 0
   duplicates.
4. **The three questions:**
   - 13,659.20 EUR, through `portfolixir.views.valuation` without an id;
   - 200.75 EUR, through `portfolixir.cashflow.realized_gains`;
   - 2,297.75 EUR, through `cash_accounts.list`.

   All three are exact, and every answering call was a read.
5. **The audit.** The transcript shows nothing read under the maintainer's
   checkout, `test/` or `_bmad-output/`, and no GitHub or web tool.
6. **The findings:**
   - #1172: the from-source route is missing from `llms.txt` and misstated
     in `.env.example`;
   - #1173: `first_setup`'s "first portfolio" on an empty instance;
   - #1174, needs-decision: the preview's default bucket tag on a converted
     bank file.

## Open issues that touch money or an upgrade path

The plan expected none to be known. These are known, all filed during this
sprint under Scope Lock:

**Money, a wrong figure (agentic):**

- **#1108**: on a cross-currency trade (a USD security bought through a EUR
  account), a closed trade's basis, proceeds and realized result add the
  account-currency fees to a price-currency amount. Question 2 of the launch
  test reads exactly this figure, though its fixture has no such trade.
- **#1107**: the Costs report converts the same trade's fees and taxes from
  the price currency. The performance walk has read them in the account's
  currency since #1051.

**Money, a decision first:**

- **#1098**: does the JSON import count a split-off negative tax twice? If PP's
  `amount` already includes the refund, the cash is off by the refund. **The
  owner's instance came in as JSON** (the answer to D-2).
- **#1118**: a PP CSV sale whose fees exceed its proceeds, with a split-off
  tax refund, is skipped at apply and leaves the position held. The preview
  shows no error.
- **#1117**: foreign cash paid in and spent on the same day, before its
  currency's first rate, is not named. The position bought with it carries
  no base-currency cost, and its value lands in the currency effect,
  unexplained.
- **#1101**: a quote series from a mis-mapped ticker values a holding far from
  its own trade prices, and no finding names it. This was observed on the
  live instance.

**Install and upgrade:**

- **#1132 (agentic)**: `mix.exs` allows Elixir 1.16, but the code needs 1.17.
  A stranger on the README's "Run from source" route with Elixir 1.16 gets a
  compile error instead of a version refusal.
- **#1172 (agentic)**: the from-source route, the one the launch test ran on,
  has three gaps. `llms.txt` does not name it, `.env.example` misstates its
  database setting, and the README does not say how to lock its UI.

## Open issues by label

| | Sprint 19 planning | After this close-out |
|---|---|---|
| Open issues | 117 | 132 |
| agentic | 73 | 78 |
| needs-decision | 36 | 46 |
| needs-uat | 2 | 2 |
| tracking | 6 | 6 |

**What happened during the sprint:**

- **Closed: 56.**
  - 52 by the three lane PRs' keywords: α 8, β 16, γ 28.
  - 4 by hand: #1079 and #1080, not planned (D-5); and at this close-out
    #1134 and #1105, both duplicates.
- **Opened: 71**, all under Scope Lock:
  - 2 at the planning merge: ADR-0053's deferrals, #1097 and #1098;
  - 4 outside the lanes: #1101 from the live instance, and #1103–#1105 from
    the review of #1102;
  - 62 from the three lane PRs: α 20, β 13, γ 29;
  - 3 from this close-out's launch test: #1172–#1174.

  The plan allowed the closing acts 33 before the criterion failed.
- **Waiting on a decision among them: 16.** They are #1097, #1098, #1101,
  #1103, #1111, #1117, #1118, #1119, #1120, #1122, #1127, #1128, #1133,
  #1140, #1156 and #1174. Six of them are the questions PR α's body put to the
  owner, still open: #1111, #1118, #1119, #1120, #1122 and #1127.

**One bookkeeping gap.** 61 open issues filed during this sprint have no
parent. PR α's findings were never attached, and tracker #991 then reached
GitHub's maximum of 100 sub-issues. Sprint 20's plan decides where they go.

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

- **#1098 on the live instance.** The PP history came in as JSON. Does a
  dividend or a sale with a negative tax in that history book its refund
  twice? Compare one such account's balance with Portfolio Performance's.
- **#328 and #354**, the runs on real data (D-12): merging, renaming and
  deleting accounts and depots, and the documented backup and restore.
- **The ADR-0053 note, for completeness.** The owner's "JSON" answer cut the
  correction. A PP CSV that was ever dropped on the live instance before
  2026.10.10 keeps PP's gross value as its cash, and a re-drop does not
  correct it.
- **The build route on a host that reaches a Debian mirror (criterion 3).**
  The route could not run here. `docker compose up --build -d` on the
  owner's own host, from a fresh clone of `95bc398e` or later, is the check
  that closes it. Behind a blocked mirror, use the `DEBIAN_MIRROR` variant of
  `docs/home-deployment.md`.
