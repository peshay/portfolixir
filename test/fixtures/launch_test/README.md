# The launch test (Sprint 17 plan D-1, #998)

The exit measure under the owner's announcement decision: can a fresh agent,
given only the repository's README and `llms.txt`, set up Portfolixir for a
user who brings a bank export, and then answer three questions exactly?
Passing it is necessary for the announcement and not sufficient; the owner
decides.

Everything here is synthetic. "Beispielbank", its accounts, the three
securities and their `QX`-prefixed identifiers are invented (`QX` is no ISIN
country prefix, so no real issue can carry them), and so are all amounts and
dates.

## The files

| File | What it is | Who may read it during a run |
| --- | --- | --- |
| `beispielbank-umsaetze.csv` | The user's export, in an invented bank format: a preamble line, a blank line, a header, nine bookings across two cash accounts and two depots, German number and date formats. | The agent under test (the stand-in user hands it over as a file outside the repository). |
| `expected-ledger.json` | The ledger a correct conversion books, as the import path books it (one portfolio record holding two depot and cash-account pairs), and the three answers. | Nobody in the run. The evaluator reads it afterwards. |
| `README.md` | This protocol. | Nobody in the run. |

The answer key ships in the repository the agent works from, so the agent never
gets this directory: see step 1.

`test/portfolixir/launch_test_fixture_test.exs` books the expected ledger
through the contexts and asserts the three answers, so they are fixed by the
code rather than by hand.

## The run

1. **Setup.** A clean container with Docker and an MCP-capable agent client.
   The evaluator prepares the agent's copy of the repository **without
   `test/fixtures/launch_test/`**: `git clone` the repository, delete that
   directory before handing the clone over (or make a sparse checkout that
   leaves it out), and copy `beispielbank-umsaetze.csv` to a place outside the
   clone. The agent gets that clone, the repository URL and one sentence from
   a stand-in user: *"I track my investments in a spreadsheet and my bank gives
   me this CSV; set me up."* It is told to rely on the README and `llms.txt`
   only. **Reading anything under `test/fixtures/launch_test/`, by any route (a
   fresh clone, the web view of the repository, a raw file URL), is an
   explicit fail of the run**, recorded at the step where it happened.
2. **What the agent must do.** Install and boot an instance; connect the MCP
   companion with the `book` profile; use the `first_setup` and
   `import_converter` prompts; produce a CSV that the Imports preview accepts
   with no error.
3. **The drop.** The stand-in user drops the agent's CSV into the Imports view
   and applies it, accepting the preview's proposals unless the agent told
   them otherwise. The import stays an operator action (ADR-0029: there is no
   import route under `/api/v1`, by design).
4. **The three questions**, asked by the stand-in user after the drop, in
   these words:
   1. "What is everything worth right now, across both portfolios?"
   2. "What did my closed trades make this year?"
   3. "How much money is in Verrechnungskonto 2?"
5. **Pass:** all three answers exact (to the cent, in EUR), with nothing from
   the stand-in user beyond the sentence, the file and the drop.

## Known answers and why

| Question | Answer | Basis |
| --- | --- | --- |
| Total across both portfolios | **13,659.20 EUR** | Cash 2,851.45 + 2,297.75, plus 70 × Globus Welt ETF and 30 × Kranich Logistik SE. No quote exists for an invented identifier, so each held position is priced at its security's latest trade (110.00 and 27.00, the global fallback of #406). On the import path the two pairs land in **one portfolio record**, so one `portfolixir.portfolios.valuation` call answers exactly; a view created with `include_all` answers the same figure (see "What question 1 measures"). |
| Realized result of closed trades in 2026 | **200.75 EUR** | FIFO, fees and taxes in basis and proceeds: Nordwind Energie AG 1,490.65 − 1,254.90 = 235.75; Kranich Logistik SE (10 of 40) 266.00 − (300.00 + 1.00 prorated fee) = −35.00. Income is not part of a trade's result. |
| Balance of Verrechnungskonto 2 | **2,297.75 EUR** | The export's own running total for that account. |

### What question 1 measures

Every Portfolio Performance import binds to the instance's one default
portfolio record (`Portfolixir.Imports.Applier`, `resolve_portfolio(nil)`; the
Imports page passes no portfolio). The user's two "portfolios" therefore arrive
as two depot and cash-account pairs in **one** portfolio record, grouped, if at
all, by the bucket tag the preview gives the accounts it creates.
`launch_test_fixture_test.exs` books exactly that structure.

So question 1 is answered by one `portfolixir.portfolios.valuation` call on
that record, and a view created with `include_all` answers the same figure. It
measures whether the agent **finds the total**. It does **not** measure D-6's
scope steering: with one portfolio record the twin tools cannot disagree, and
the view-less union has no read of its own (#1007).

D-1's words, "across both portfolios", stay as adopted: they are the stand-in
user's words, and "portfolio" there means the user's two groups of accounts,
not Portfolixir's portfolio record. A question that measures steering has to be
about **one group**, which the agent can only answer through a bucket and a
view (for example *"What is the part in Depot 2 worth?"*, after Depot 2 and
Verrechnungskonto 2 are tagged with one bucket and a view includes it).
Adding or replacing a question changes D-1's adopted questions, so it is an
owner decision, not this fixture's.

The two traps a careless conversion falls into, and that the answers catch:

- **The dividend.** The export's `Betrag` for the distribution is the net
  credited amount (61.25 after 8.75 tax). A converter that books the gross
  overstates the first account, and the total, by 8.75.
- **The preamble.** The export's first two lines are not data. A converter
  that keeps them fails the preview.

## Recording a run

Record the date, the commit, the agent client and model, and for each step
of "The run": what the agent did, which files it read, and whether the step
passed. A failure names its step. The close-out's record of the run goes into
`sprint-status.yaml` with the sprint's entry.
