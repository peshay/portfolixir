# Sprint 20 α closing act: the UAT persona's screenshots

Taken on 2026-10-09 by the UAT persona (the plan's D-15) on the α branch at
`b023a14e9`, in the German UI, with Playwright and Chromium, as the design
critic's input against boards 01 and 03 of
`planning-artifacts/design-language/mockups/ux-design-2026-10-07/`.

**Synthetic data only.** Every account, depot, security, figure and date is
invented: the fixtures `sample_with_negative_tax.json` and
`sale_with_negative_tax.json`, their PP CSV twin, and small files written for
the walk ("Test-Cash", "Muster-Cash", "Girokonto", "Tagesgeld", "Arbolia
Inc.", "Wrenfield Gardens AG", "Larkspur Rail AG").

**Naming.** `<surface>-<width>-<l|d>.png`: a 390 px or 1200 px viewport,
light or dark (`prefers-color-scheme`). Each file is cropped to its surface
and reduced to a 256-colour palette, as the boards are.

| Surface | What it shows | Board |
|---|---|---|
| `fresh-portfolio` | A fresh instance's preview names the portfolio record the import creates: "Noch kein Portfoliodatensatz: Der Import legt „Default“ (EUR) an und bucht darin." (#1173) | 01 ⑥ |
| `bucket-tag` | The bucket-tag panel with its field empty and the placeholder "z. B. PP Import" (#1174) | 01 ⑦ |
| `redrop-nothing-new` | A re-drop of an applied file: the "nothing will be booked" note leads, the mapping row has no select (#1168) | 01 ② |
| `unseen-name-row` | A cash-account name the stored history never saw ("Tagesgeld Extra", renamed in PP): no prefill ("Entscheiden…") and the note naming both remedies (pick L1 A, #904) | 01 ① |
| `unseen-name-apply` | Apply waits: the still-to-map hint and the disabled "Import bestätigen" | 01 ① |
| `unseen-name-mapped` | The same row mapped onto its old account, with "Zuordnung merken" ticked | 01 ① |
| `correction-section` | "Bereits importiert, mit anderem Betrag" for a JSON sale booked under the old reading: +120,00 → +95,00, price 12,50 → 10,00 | 01 ⑧, 03 |
| `correction-dialog` | Its own confirm, "Gebuchte Beträge korrigieren", with the "Differenz" caption | 03 |
| `correction-result` | The result line that replaces the section | 01 ⑧ |
| `row-errors-fresh` | The parser-warnings note of a CSV: a refused credit row (#1118) and a transfer without a counter-account, each with the line a spreadsheet shows (#1128); at 390 px the note's body takes the full width (#1140) | 01 ③ ④ ⑤ |
| `row-errors-imported` | The refused credit row of a JSON file whose sale the previous release already booked: "bereits importiert und hier nicht zu korrigieren" (#1118, #1193) | 01 ③ |
| `done-page` | The done page with the skip reasons in German and a real plural ("2 nicht importierbare Datensätze übersprungen") | 01 |

**Refreshed after the second fix round** (2026-10-09, the same scripts on a
database of their own, the old release at `12117072` booking the old reading
first): `correction-section-*` (the middle column reads "Korrigiert", board
03 ④; the two 390 px files come out byte-identical, as the phone rows carry
no column word), `row-errors-fresh-*` and `row-errors-imported-*` (the
refused credit row in board 01 ③'s sentence, "Steuererstattung", the figures
in the page's notation). `correction-dialog-*` is unchanged: the dialog shows
no column word.
