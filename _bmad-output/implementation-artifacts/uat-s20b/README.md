# Sprint 20 β closing act: UAT persona, round trip 4 and β's surfaces

Each surface was shot at 390 and 1200 px, light (`l`) and dark (`d`):
`<surface>-<width>-<l|d>.png`. The UI is German (`Accept-Language: de-DE`).
The app ran at β's head on its own database. Each file is cropped to its
surface and reduced to a 256-colour palette, as the boards and `uat-s20a`
are.

**Before BDC-1's fix.** The shots predate the closing act's fix of BDC-1
(`.data-table-wrap` takes `position: relative`): at 390 px a security with
a lot or a position on no cost still made its whole page scroll sideways on
the Trades and Holdings tabs.

**Data.** Everything is synthetic: one EUR portfolio "UAT-Depot" with the
cash accounts "Test-Cash" and "Reserve-Cash", "Depot A" and "Depot B", and
five invented securities. The rate is 1 EUR = 1.25 USD on every date. It was
stored as EUR-hub rows of the kind the app reads. The API has no rate write,
so nothing came from the network.

## Round trip 4: the cross-currency trade (identity 1)

The pair is buy 10 Synthetic Inc. at 100 USD, settled 800.00 EUR with fees
5.00 and taxes 1.00 EUR, then sell 10 at 120 USD, settled 960.00 EUR with fees
3.00 EUR. It was first booked through `POST /api/v1/transactions`. Those two
rows were then deleted and the pair was booked again through the booking
screen. Both routes stored the same rows and gave byte-identical trades and
realized-gains reads. The shots show the pair booked through the screen.

| Shot | What it proves |
|---|---|
| `booking-buy-*` | The booking screen offers the cross-currency fields: Preis (USD), Abrechnungsbetrag (EUR) and Kurs EUR je USD (0,8). It states that fees and taxes are in EUR. At 1200 px the drawer's lower part (taxes, save) is below the captured area. |
| `trades-synthetic-*` | The Trades tab reads realized **+188,75** and +18,7 %. At 390 px the row says **USD**. At 1200 px the table names no currency, and no EUR figure is shown at either width. |
| `overview-closed-trades-*` | The Overview's closed-trades card reads Synthetic Inc. **+151,00 EUR**, +18,7 % gesamt. |
| `income-realized-*` | Income's realized list reads Einstand **1.007,50 USD**, Erlös **1.196,25 USD** and Ergebnis **+151,00 EUR**. Realized in total, +481,00 EUR, includes the bonus trade. |
| `test-cash-*` | The Test-Cash filter with its running balance: the buy is −806,00 (10.000,00 → 9.194,00) and the sell +957,00 (8.229,00 → 9.186,00). The pair moved 957,00 − 806,00 = **151,00**. |

## β's other surfaces

| Shot | Issue | What it proves |
|---|---|---|
| `trades-bonus-*` | #1142 | Bonus shares bought at 0,00, 8 of 12 sold. The closed trade's % and p. a. read the reason dash ("keine Rendite, keine Kostenbasis"), as does the open lot's %, which at 390 px sits in a table scrolled sideways. |
| `holdings-gratis-*` | #1142 | A free delivery of 15 shares: Ø Kosten 0,00 and % "—", with the gain +336,00 kept. |
| `wealth-positions-*` | #1142 | Wealth's positions with Marktwert, G&V and G&V % picked: the zero-cost rows read "—" at 1200 px. At 390 px the phone rows show only the quantity. |
| `overview-closed-trades-*` | #1142 | The bonus trade reads +330,00 EUR "— keine Kostenbasis". |
| `overview-dq-*` | #1101 | The data-quality line: "ein gehaltenes Wertpapier, dessen Kurse nicht zu seinen Buchungen passen" (Problem), linked to the list. |
| `wealth-dq-*` | #1101 | Wealth's note names the security, booking and quote: "Ausreisser Kurs GmbH (Kauf 01.06.2026 zu 48,2 EUR · Kurs 01.06.2026: 4.820 EUR, das 100,00-Fache)". |
| `securities-dq-*` | #1101 | The link opens the filtered list "Kurs passt nicht zu Buchungen" with that one security. |
| `costs-*`, `costs-july-*` | #1107 | Identity 2 (buy 10 at 100 USD settled 790.00 EUR, fees 5.00, taxes 1.00 EUR, July): July reads Gebühren **5,00** and Steuern **1,00**. The Gesamt row has no monthly cells, so 6,00 is not shown. March (5,00 / 1,00) and August (3,00) are identity 1's legs. |
| `wealth-view-*` | #1124 | View "Nur Kurzfrist" selected: the positions table shows only Depot B's Synthetic Two Inc., and the cash shows only Reserve-Cash. Full page; the sidebar artefact comes from the full-page capture. |
| `class-before-*` | #1110 | The region tree before the edits: Europa 4 positions · 97.735,20, with USA (Synthetic Two Inc.) filed under Europa, and Amerika at 0. |
| `class-after-move-*` | #1110 | Synthetic Two Inc. moved to Amerika with the selection bar and no reload: Europa 3 · 96.903,20, USA 0, Amerika 1 · 832,00 · Einstand 790,00 · +42,00. |
| `class-after-delete-*` | #1110 | The emptied USA category deleted, still with no reload. Its sold-out member now shows under "Nicht zugeordnet +1 ohne Bestand". |
