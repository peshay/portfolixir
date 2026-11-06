# Sprint 26 planning board 04: delete confirmations that say what a delete removes (F21, #894)

Drawn on 2026-11-06, before any code. Sprint 25 built the agent's half of
F21: `dry_run=true` on `DELETE` of a classification, a category and a view
(`dry_run: true` on their MCP tools) runs the real delete in a transaction
that always rolls back and answers, per kind, the count and the ids it
would remove, or the refusal the delete would answer (Sprint 25 plan D-4;
`PortfolixirWeb.Api.V1.DryRunParam`, `Portfolixir.DryRun`). The screen's
half is this board: the three deletes stop confirming with the browser's
native `window.confirm` (`data-confirm`: "Diese Klassifizierung und alle
ihre Kategorien löschen?", "Diese Kategorie löschen?", "Diese Ansicht
löschen?"), which names no count, and confirm in an in-app dialog that
lists what the dry run says the delete removes.

| File | What it is |
|---|---|
| `04-delete-dialogs.html` → `04-delete-dialogs--1200.png` | The desktop board, rendered at 1200 px: per delete, today's native confirmation and the proposed dialog; the refusal, the state where nothing else goes, the changed state, the dark theme, and the one choice (A, B). |
| `04-delete-dialogs-390.html` → `04-delete-dialogs--390.png` | The phone board, rendered at 390 px: the dialog as the bottom sheet — a category with what goes, a category refused, a view with nothing else. |
| `build.js` | Captures the frames from the running review instance, writes the dialogs into the live DOM, writes `frames/` and both boards. Holds the proposed strings (`NEW`) and the story's CSS (`PROPOSAL_CSS`). |
| `board.js` | Lays out the boards from `frames/sizes.json`. |
| `render.js` | Renders both boards to PNG. |
| `frames/` | One static page per frame and width; each links the real `priv/static/app.css`. |

**Synthetic data only.** Every row is the synthetic review seed's
(`priv/demo/finding_surfaces_seed.exs`). Two frames show a state the seed
does not have, marked with the amber stripe on the board: the
classification's dialog drawn as if no rule read it (the counts are still
the seed's rows), and the changed state's third assignment. No real
portfolio, name or machine detail appears.

## What the board proposes (conformance to an existing anatomy)

The dialog is the booking delete's (DESIGN.md, "Deleting a booking";
`PortfolixirWeb.Transactions.BookingDeleteDialog`): a native
`<dialog class="modal booking-delete-dialog">` on the `ModalDialog` hook,
460 px, under 720 px the merge dialog's bottom sheet with the stacked band
foot. Nothing in that anatomy changes; the three deletes join it.

1. **The subject box** (`.booking-delete__subject`) names what was chosen
   the way the list it was chosen from names it: a classification with
   "6 Kategorien · 2 Ebenen" (the index row's line), a category with
   "Kategorie in Strategies" and its positions, a view with its rule
   ("Alles · außer Crypto"), positions and accounts. No amount in any of
   them.
2. **What the delete removes**, read from the dry run when the dialog
   opens: "Das Löschen entfernt:" and one line per kind with its count, in
   a fixed order; a kind with 0 is left out; the subject itself is no line
   (a category counts itself, so its line reads "„Stability“ und 1
   Kategorie darunter"). A view's bucket set (`view_include_buckets`,
   `view_exclude_buckets`) is the view itself, already in the box, and is
   no line. When nothing but the subject goes: "Sonst wird nichts mit
   gelöscht."
3. **What stays**, one `.hint` per delete, then the journal sentence.
4. **The band foot**: Abbrechen (ghost, focused on open), the spacer, the
   danger button that names the act. One confirmation: the `data-confirm`
   goes.
5. **A refusal** (a policy rule reads the subject, ADR-0049 §8) is the
   dry run's answer too, so it shows before the click instead of after
   "OK": the same dialog titled "Kann nicht gelöscht werden", the
   securities' refusal text (`.confirm-delete-blocked`: the sentence, the
   rule list with each rule linked to Wealth → Risk in its view, the quiet
   reason), and a foot with "Schließen" only.

**The one choice:** A, counts only (recommended); B, counts with the
names the page holds (categories, the first two securities and "7
weitere", plans with their status). Silence adopts A; a comment "F21 B"
changes it. Why A: the count is the question the native dialog left open;
the names repeat what stands behind the dialog and grow with the data
("Währung" has 26 categories), and B is incomplete anyway (two of nine
assignments). For B: the archived plan "Earlier mix" loses its targets
too and is shown nowhere on the screen.

**Judgement calls, each flippable by a comment:**

- **The confirm holds to the list it showed** ("F21 ohne Abgleich" flips
  it): the delete commits only when it removes exactly the ids the dialog
  showed (dry run, compare, then commit or roll back, in one transaction);
  otherwise nothing is deleted and the dialog shows the new state with an
  attention note — the split delete's existing "changed while this dialog
  was open" shape.
- **The refusal's reason says the delete stays blocked**: retiring a rule
  stops its evaluation but keeps its subject (ADR-0049 §8;
  `PolicyConflict`'s own detail), so the sentence does not promise that
  retiring frees the delete.
- **The category's button reads "Kategorie löschen"**, the catalogue's
  string that today is only the "×"'s `aria-label`.

**Not drawn:** a dry run that answers `concurrent_change` (409) shows the
attention note below instead of the list, and the foot offers
"Erneut prüfen" (the catalogue's "Check again") beside Abbrechen. The
classification index's row menu opens the same dialog as the detail
head's button.

## Where the counts come from

No delete was sent, not even its dry run (the build is GET-only). The
counts are the seed's rows that each dry run's kinds name, read from the
review database: "Strategies" holds 6 categories, 9 assignments and 2
target plans (the active "Plan", the archived "Earlier mix") with 18
targets; "Stability" holds "Quality" below it, Quality's 2 assignments,
and 2 targets each; "Ohne Krypto" has no plan and no snapshot. The seed's
rules: "Wachstum im Band" (reads Growth) and "Helios nahe am Ziel" (a
drift rule in Strategies) refuse the classification; "Wachstum im Band"
refuses Growth; "Neuzugang: Schwankung unter 20 %" (context "Nur
Neuzugang") refuses that view. The story's test pins the dialog's lines to
the dry run's answer.

## Strings

Existing, from `priv/gettext/de/LC_MESSAGES/default.po`: "Klassifizierung
löschen", "Kategorie löschen", "Kann nicht gelöscht werden", "Abbrechen",
"Schließen", "%{count} Kategorie(n)", "%{count} Ebene(n)", "%{count}
Position(en)", "%{count} Konto/Konten", "%{name} wird von eigenen Regeln
gelesen:", "„%{name}“ (%{status}, Ansicht „%{view}“)", "gilt", "Alles",
"aktiv", "archiviert", "%{first} und %{second}", "Erneut prüfen", and the
three native confirmations the board shows as "before".

Proposed (English source → German):

| English | German |
|---|---|
| Delete view | Ansicht löschen |
| The delete removes: | Das Löschen entfernt: |
| Nothing else is removed with it. | Sonst wird nichts mit gelöscht. |
| “%{name}” and %{count} category below it / categories below it | „%{name}“ und %{count} Kategorie darunter / Kategorien darunter |
| %{count} security assignment / assignments | %{count} Wertpapierzuordnung / Wertpapierzuordnungen |
| %{count} target plan / plans | %{count} Soll-Plan / Soll-Pläne |
| %{count} target weight / weights | %{count} Zielgewicht / Zielgewichte |
| %{count} snapshot / snapshots | %{count} Snapshot / Snapshots |
| Category in %{classification} | Kategorie in %{classification} |
| The securities themselves, their bookings and quotes stay. | Die Wertpapiere selbst, ihre Buchungen und Kurse bleiben. |
| The securities themselves stay; in this classification they then sit under “Unassigned”. | Die Wertpapiere selbst bleiben; in dieser Klassifizierung stehen sie danach unter „Nicht zugeordnet“. |
| The buckets and their assignments stay. | Die Buckets und ihre Zuordnungen bleiben. |
| The audit journal records each deletion with every value; none of it can be restored. | Das Audit-Journal hält jede Löschung mit allen Werten fest; wiederherstellen lässt sich nichts davon. |
| A rule that has been in force keeps its subject as part of its history, so the delete stays blocked; retiring the rule on Wealth → Risk stops its evaluation. | Eine Regel, die gegolten hat, behält ihren Bezug als Teil ihrer Geschichte; darum bleibt das Löschen gesperrt. Sie auf „Vermögen → Risiko“ zu beenden, stoppt ihre Auswertung. |
| What the delete removes changed while this dialog was open. Nothing was deleted; the dialog now shows the new state. | Was das Löschen entfernt, hat sich geändert, während dieser Dialog offen war. Nichts wurde gelöscht; der Dialog zeigt jetzt den neuen Stand. |
| Something changed while the check ran, and nothing was deleted. Check again to see what the delete removes now. *(not drawn)* | Während der Prüfung hat sich etwas geändert, und nichts wurde gelöscht. Erneut prüfen, um zu sehen, was das Löschen jetzt entfernt. |
| %{names} and %{count} more *(variant B only)* | %{names} und %{count} weitere |

Three catalogue strings leave the screen with the native confirmations:
"Delete this classification and all its categories?", "Delete this
category?" and "Delete this view?".

## The story's CSS (the frames' `<style id="proposal">`)

```css
.delete-preview { margin: 0; }
.delete-preview__lead { margin: 0 0 4px; font-size: 13px; color: var(--color-text); }
.delete-preview__list { margin: 0; padding-left: 18px; font-size: 13px; line-height: 1.55; color: var(--color-text); }
.delete-preview__list li { overflow-wrap: anywhere; }
.delete-preview__list li + li { margin-top: 2px; }
.delete-preview__list li::marker { color: var(--color-text-muted); }
.delete-preview__names { color: var(--color-text-muted); }
.confirm-delete-blocked .modal-body ul { margin: 0; padding-left: 18px; font-size: 13px; line-height: 1.55; }
```

The dialog's own classes are the shipped ones; `.delete-preview__names`
is B's only.

## Frame chrome (not proposed)

The frames draw what the browser paints and a static page cannot: the
scrim takes `dialog.modal::backdrop`'s colours from app.css; the "before"
box is an approximation of Chrome's native confirmation (origin line,
message, OK and Abbrechen), labelled as such on the board, its message the
catalogue's; the control that was clicked carries a red ring. The dashed
accent outline marks the new dialog, the amber stripe a state the seed
does not have, the magenta pins the four rules above.

## How to regenerate

Run the review instance on port 4011 with the synthetic review seed, as
`../ux-design-2026-11-06-sprint26-i22/README.md` ("Rebuilding") says. Then,
from this folder (`PLAYWRIGHT_CHROMIUM_EXECUTABLE` names a Chromium of
your own, if Playwright's is not installed):

```bash
node build.js    # captures every frame, writes frames/ and both boards
node render.js   # renders 04-delete-dialogs--1200.png and 04-delete-dialogs--390.png
```

The build sends GET requests only; on /buckets it clicks a view's kebab,
which opens its row menu and writes nothing. `ONLY=<regex>` recaptures the
matching frames and keeps the rest of `frames/sizes.json`.
