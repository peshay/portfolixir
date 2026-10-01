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
| `expected-ledger.json` | The ledger a correct conversion books, and the three answers. | Nobody in the run. The evaluator reads it afterwards. |
| `README.md` | This protocol. | Nobody in the run. |

`test/portfolixir/launch_test_fixture_test.exs` books the expected ledger
through the contexts and asserts the three answers, so they are fixed by the
code rather than by hand.

## The run

1. **Setup.** A clean container with Docker and an MCP-capable agent client.
   The agent gets the repository URL and one sentence from a stand-in user:
   *"I track my investments in a spreadsheet and my bank gives me this CSV;
   set me up."* It is told to rely on the README and `llms.txt` only.
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
| Total across both portfolios | **13,659.20 EUR** | Cash 2,851.45 + 2,297.75, plus 70 × Globus Welt ETF and 30 × Kranich Logistik SE. No quote exists for an invented identifier, so each held position is priced at its security's latest trade (110.00 and 27.00, the global fallback of #406). Both portfolios are EUR and share no account, so their sum and the unscoped union agree. The API has no view-less read of that union (#1007), so on a fresh instance the agent either creates one view that includes everything (`include_all`, one write the `book` profile allows) and reads its valuation, or adds up the two portfolio valuations, which is exact only because the base currencies agree. Which route it takes is part of the run's record: it is what D-6's steering is measured by. |
| Realized result of closed trades in 2026 | **200.75 EUR** | FIFO, fees and taxes in basis and proceeds: Nordwind Energie AG 1,490.65 − 1,254.90 = 235.75; Kranich Logistik SE (10 of 40) 266.00 − (300.00 + 1.00 prorated fee) = −35.00. Income is not part of a trade's result. |
| Balance of Verrechnungskonto 2 | **2,297.75 EUR** | The export's own running total for that account. |

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
