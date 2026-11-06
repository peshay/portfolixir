// Board 04's layout and text. build.js captures the frames into frames/ and
// hands over their sizes; this file places them as <iframe>s with the
// reasons and the pins' legend, and writes
//   04-delete-dialogs.html      (the desktop board, rendered at 1200 px)
//   04-delete-dialogs-390.html  (the phone board, rendered at 390 px)
// `node board.js` alone rebuilds the boards from frames/sizes.json.
// BOARD_CSS is the Sprint 23 and 24 boards' artboard chrome, unchanged but
// for the synthetic key's label.
const fs = require('fs');
const path = require('path');

const BOARD_CSS = `
/* Artboard chrome only; everything inside a frame is priv/static/app.css. */
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 1120px; margin: 0 auto 36px; }
.mock-head h1 { margin: 0 0 6px; font-size: 20px; }
.mock-head h1 small, .mock-board > h2 small { font-weight: 500; color: var(--color-text-muted); margin-left: 6px; font-size: 12.5px; }
.mock-board > h2 { margin: 0 0 4px; font-size: 16px; font-weight: 760; }
.mock-rec { font-size: 11px; font-weight: 700; color: var(--color-accent); background: var(--color-accent-soft); padding: 2px 8px; border-radius: 999px; margin-left: 6px; vertical-align: 2px; }
.mock-board p.mock-note, .mock-notes { font-size: 12.5px; color: var(--color-text-muted); line-height: 1.5; }
.mock-board p.mock-note { margin: 0 0 12px; max-width: 110ch; }
.mock-board b { color: var(--color-text); }
.mock-board code { font-size: 11.5px; }
.mock-pickbar { margin: 0 0 16px; padding: 10px 14px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 12.5px; line-height: 1.5; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-fig { margin: 0 0 18px; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; }
.mock-tag--before { color: var(--color-danger); background: var(--color-danger-soft); }
.mock-tag--after { color: var(--color-positive); background: #ecfdf5; }
.mock-tag--alt { color: var(--color-text-muted); background: var(--color-bg-muted); }
.mock-frame { width: max-content; max-width: 100%; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg); overflow: hidden; box-shadow: var(--shadow-panel); }
.mock-frame iframe { display: block; border: 0; }
.mock-pin { display: inline-grid; place-items: center; width: 18px; height: 18px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 11px/1 var(--font-sans); vertical-align: 1px; margin-right: 4px; }
.mock-why { margin: 0 0 18px; padding: 8px 12px; border-left: 3px solid var(--color-accent); background: var(--color-bg-elevated); font-size: 12.5px; line-height: 1.5; color: var(--color-text-muted); }
.mock-why p { margin: 0 0 6px; } .mock-why p:last-child { margin: 0; }
.mock-why ul { margin: 0; padding-left: 18px; } .mock-why li { margin: 0 0 4px; }
table.mock-rules { width: 100%; border-collapse: collapse; font-size: 12.5px; background: var(--color-bg-elevated); border: 1px solid var(--color-border); border-radius: var(--radius-md); margin: 0 0 12px; }
table.mock-rules th { text-align: left; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); padding: 8px 10px; }
table.mock-rules td { padding: 7px 10px; border-top: 1px solid var(--color-border); vertical-align: top; }
.mock-key { display: inline-block; width: 22px; height: 12px; vertical-align: -1px; margin: 0 4px 0 2px; border-radius: 3px; }
.mock-key--new { outline: 2px dashed var(--color-accent); outline-offset: -2px; }
.mock-key--synth { box-shadow: inset 4px 0 0 #f59e0b; background: var(--color-bg-elevated); border: 1px solid var(--color-border); }
.mock-key--native { background: #fff; border: 1px solid #747775; }
/* The phone board: the frames are the 390 px viewport. */
body.mock-phone { padding: 16px 0; }
body.mock-phone .mock-board > :not(.mock-fig), body.mock-phone .mock-head > * { margin-left: 16px; margin-right: 16px; }
body.mock-phone .mock-fig > .mock-tag { margin-left: 16px; }
body.mock-phone .mock-desk-only { display: none; }
body.mock-phone .mock-frame { width: 100%; border-radius: 0; border-left: 0; border-right: 0; box-shadow: none; }
`;

module.exports.main = function main(sizes) {
  sizes = sizes || JSON.parse(fs.readFileSync(path.join(__dirname, 'frames', 'sizes.json'), 'utf8'));
  const size = (key) => { const s = sizes[key]; if (!s) throw new Error('frame not captured: ' + key); return s; };
  const iframe = (key, title) => {
    const s = size(key);
    return `<iframe src="${s.file}" width="${s.width}" height="${s.height}" title="${title}" scrolling="no"></iframe>`;
  };
  const fig = (kind, label, key) => `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame">${iframe(key, label.replace(/<[^>]+>/g, ''))}</div></figure>`;
  const pin = (n) => `<span class="mock-pin">${n}</span>`;
  const NATIVE = 'Vorher — heute: <code>data-confirm</code>, der native Dialog des Browsers (Nachbildung von Chrome; der Text ist der des Katalogs)';

  const page = (title, sub, phone, body) => `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — ${title}${phone ? ' — 390 px' : ''} (Sprint 26)</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js and board.js from the review instance on the
     synthetic review seed. Each frame is a static page under frames/ that
     links app.css; "Vorher" frames are the shipped page with today's native
     confirmation drawn over it (an approximation of Chrome's, labelled),
     "Nachher" frames carry the proposed dialog in their markup and the
     story's CSS in <style id="proposal">. The block below is artboard
     chrome only. No script runs on this page or in a frame. -->
<style id="board">${BOARD_CSS}</style>
</head>
<body class="${phone ? 'mock-phone' : ''}" data-widths="${phone ? '390' : '1200'}">
<div class="mock-board mock-head">
  <h1>${title} <small>${sub}${phone ? ' · 390 px' : ''}</small></h1>
  ${body.head}
  <p class="mock-note"><span class="mock-key mock-key--new"></span> gestrichelt = neu · <span class="mock-key mock-key--synth"></span> bernsteinfarbener Streifen = ein Zustand, den der Seed so nicht hat (die Zahlen sind trotzdem seine Zeilen) · <span class="mock-key mock-key--native"></span> heller Kasten oben = Nachbildung des nativen Browser-Dialogs · ${pin(1)}–${pin(4)} verweisen auf die Regeln oben. Jede Zeile ist die des synthetischen Review-Seeds; nichts davon ist echt. Synthetic data only.</p>
</div>
${phone ? body.phone : body.desk}
</body>
</html>
`;
  const write = (file, html) => {
    fs.writeFileSync(path.join(__dirname, file), html.split('\n').map((l) => l.replace(/[ \t]+$/, '')).join('\n'));
    console.log('wrote', file);
  };

  const head = `<div class="mock-pickbar">
    <p><b>F21 (#894): die drei kaskadierenden Löschungen bestätigen in einem Dialog der App, der sagt, was das Löschen entfernt</b> — eine Klassifizierung, eine Kategorie, eine Ansicht. Heute fragt der native Dialog „Diese Kategorie löschen?“ und nennt nichts; was mit verschwindet, steht nirgends. Sprint 25 hat <code>dry_run=true</code> gebaut (Plan D-4): das echte Löschen in einer Transaktion, die immer zurückrollt, antwortet je Art mit Anzahl und IDs — oder mit der Ablehnung, die das Löschen gäbe. <b>Der Dialog liest genau diese Antwort</b>, beim Öffnen; eine Zählung daneben gibt es nicht.</p>
    <p><b>Anatomie: die des Buchungs-Löschdialogs</b> (DESIGN.md, „Deleting a booking“): <code>.modal.booking-delete-dialog</code> auf dem ModalDialog-Hook, 460 px, unter 720 px das Bottom-Sheet; ${pin(1)} der Gegenstand im Kasten der Liste, aus der er gewählt wurde; ${pin(2)} <b>was das Löschen entfernt</b>, je Art eine Zeile mit ihrer Anzahl, Arten mit 0 entfallen, und nichts außer dem Gegenstand: „Sonst wird nichts mit gelöscht.“; ${pin(3)} was bleibt, dann das Journal; ${pin(4)} Abbrechen (Fokus) und der Gefahr-Knopf, der die Tat nennt — eine Bestätigung, kein <code>data-confirm</code> mehr danach. <b>Lehnt der Probelauf ab</b> (eine Regel liest das Objekt), zeigt derselbe Dialog die Ablehnung im Wortlaut von „Kann nicht gelöscht werden“ der Wertpapiere statt eines Lösch-Knopfs: der Fuß hat nur „Schließen“.</p>
    <p><b>Die eine Wahl: Anzahlen (A, empfohlen) oder Anzahlen mit Namen (B)</b> — gezeigt an der Klassifizierung. Schweigen übernimmt A; ein Kommentar „F21 B“ ändert es.</p>
  </div>
  <table class="mock-rules mock-desk-only">
    <tr><th>Löschen</th><th>Was der Probelauf nennt (Art → Zeile im Dialog)</th><th>Im Seed</th></tr>
    <tr><td>Klassifizierung</td><td>categories → „6 Kategorien“, assignments → „9 Wertpapierzuordnungen“, target_plans → „2 Soll-Pläne“, targets → „18 Zielgewichte“ (classifications, der Gegenstand selbst, keine Zeile)</td><td>„Strategies“: abgelehnt, zwei Regeln lesen sie</td></tr>
    <tr><td>Kategorie</td><td>categories → „Stability“ und 1 Kategorie darunter (der Gegenstand zählt mit), assignments, targets</td><td>„Stability“: 2 / 2 / 4; „Growth“: abgelehnt</td></tr>
    <tr><td>Ansicht</td><td>target_plans, targets, depot_snapshots → „1 Snapshot“; die Bucket-Auswahl der Ansicht (view_include/exclude_buckets) ist die Ansicht selbst und steht schon im Kasten</td><td>„Ohne Krypto“: nichts sonst; „Nur Neuzugang“: abgelehnt</td></tr>
  </table>`;

  const desk = `
<section class="mock-board">
  <h2>Klassifizierung löschen <small>Klassifizierungen → Strategies → „Klassifizierung löschen“ (das Index-Menü öffnet denselben Dialog) · 1200 px, Seitenleiste offen</small></h2>
  ${fig('before', NATIVE, 'cls-before@1200')}
  ${fig('after', 'Nachher — der Seed: zwei Regeln lesen „Strategies“, der Probelauf lehnt ab', 'cls-refused@1200')}
  <div class="mock-why">
    <p>${pin(2)} <b>Die Ablehnung kommt jetzt vor dem Klick, nicht danach.</b> Heute sagt der native Dialog „Diese Klassifizierung und alle ihre Kategorien löschen?“, und erst nach „OK“ meldet das Band oben, dass Regeln sie lesen. Der Dialog zeigt dieselben Worte, die der Lösch-Weg heute in das Band schreibt (<code>PolicyRuleReferences</code>: jede Regel ein Link nach „Vermögen → Risiko“ in ihrer Ansicht), in der Form von „Kann nicht gelöscht werden“ der Wertpapiere — Titel, Satz, Liste, Begründung in der leisen Stimme. ${pin(3)} Die Begründung ist neu: Beenden stoppt die Auswertung, gibt den Bezug aber nicht frei (ADR-0049 §8), darum sagt sie „bleibt gesperrt“. ${pin(4)} Kein Lösch-Knopf; „Schließen“ hat den Fokus.</p>
  </div>
  ${fig('after', 'A — Anzahlen, empfohlen · so, als läse keine Regel sie (bernstein)', 'cls-after-a@1200')}
  ${fig('alt', 'B — Anzahlen mit Namen · dieselben Zeilen', 'cls-after-b@1200')}
  <div class="mock-why">
    <p><b>Warum A:</b> die Frage, die der Dialog beantworten muss, ist „wie viel geht mit?“ — genau das fehlte dem nativen Dialog. Die Namen wiederholen, was hinter dem Dialog steht (der Baum listet die Kategorien, die Plan-Auswahl die Pläne), und ihre Länge wächst mit den Daten: „Währung“ hat 26 Kategorien, und im Sheet auf dem Telefon würde B zur Wand. Vollständig wäre B ohnehin nicht — bei 9 Zuordnungen nennt es zwei und „7 weitere“. Die IDs bleiben in der Antwort von API und MCP, wo ein Agent sie liest.</p>
    <p><b>Was für B spricht:</b> der archivierte Plan „Earlier mix“ verliert seine Zielgewichte mit, und er steht nirgends auf dem Bildschirm (die Plan-Auswahl zeigt den aktiven). Wer das für wichtig hält, kommentiert „F21 B“.</p>
  </div>
</section>
<section class="mock-board">
  <h2>Kategorie löschen <small>Klassifizierungen → Strategies → „×“ in der Zeile „Stability“ · 1200 px</small></h2>
  ${fig('before', NATIVE, 'cat-before@1200')}
  ${fig('after', 'Nachher — A: „Stability“, Quality darunter, 2 Zuordnungen, 4 Zielgewichte (die Zeilen des Seeds)', 'cat-after@1200')}
  <div class="mock-why">
    <p>${pin(1)} Der Kasten nennt die Kategorie wie die Zeile, aus der sie gewählt wurde, und wo sie steht („Kategorie in Strategies“), mit ihren Positionen — keinen Betrag. ${pin(2)} Die Kategorie zählt im Probelauf mit; die Zeile sagt es so („Stability“ und 1 Kategorie darunter), damit „2 Kategorien“ nicht nach zwei <i>weiteren</i> klingt. Ohne Unterkategorie entfällt die Zeile. ${pin(3)} Was bleibt: die Wertpapiere — sie stehen danach unter „Nicht zugeordnet“, wo der Baum sie schon zeigt. ${pin(4)} „Kategorie löschen“, der Katalogtext des Buttons, der heute nur <code>aria-label</code> des „×“ ist.</p>
  </div>
  ${fig('after', 'Nachher, dunkel', 'cat-after-dark@1200')}
  ${fig('after', 'Nachher — geändert, während der Dialog offen war: nichts gelöscht, der neue Stand (bernstein: eine dritte Zuordnung, die der Seed nicht hat)', 'cat-changed@1200')}
  <div class="mock-why">
    <p><b>Urteil, umkehrbar:</b> der Dialog verspricht eine Liste, also hält der Klick sich daran. „Kategorie löschen“ löscht nur, wenn das Löschen genau die Zeilen entfernt, die der Dialog gezeigt hat (dieselbe Transaktion: Probelauf, Vergleich der IDs, dann Commit oder Rollback); sonst ist nichts gelöscht, und der Dialog zeigt den neuen Stand mit dem Hinweis — die Form, die die Split-Löschung schon hat („Der Split hat sich geändert, während dieser Dialog offen war …“). Ein Kommentar „F21 ohne Abgleich“ lässt den Klick ohne Vergleich löschen. Antwortet der Probelauf <code>concurrent_change</code> (409), zeigt der Dialog statt der Liste den Hinweis „Während der Prüfung hat sich etwas geändert …“ und den Knopf „Erneut prüfen“ (nicht gezeichnet; README).</p>
  </div>
</section>
<section class="mock-board">
  <h2>Ansicht löschen <small>Ansichten → „Ohne Krypto“ → ⋮ → „Löschen“ · 1200 px</small></h2>
  ${fig('before', NATIVE, 'view-before@1200')}
  ${fig('after', 'Nachher — nichts sonst: an „Ohne Krypto“ hängen kein Soll-Plan und kein Snapshot', 'view-after@1200')}
  <div class="mock-why">
    <p>${pin(1)} Der Kasten nennt die Ansicht wie ihre Zeile: Name, Regel („Alles · außer Crypto“), Positionen und Konten — ihren Betrag nicht. ${pin(2)} Entfernt das Löschen nichts außer dem Gegenstand, steht statt der Liste „Sonst wird nichts mit gelöscht.“ — die Antwort auf die Frage, die der native Dialog offenließ, auch wenn sie „nichts“ lautet. Die Bucket-Auswahl der Ansicht (im Probelauf <code>view_exclude_buckets: 1</code>) ist die Ansicht selbst und keine Zeile wert; ${pin(3)} die Buckets und ihre Zuordnungen bleiben.</p>
  </div>
  ${fig('after', 'Nachher — abgelehnt: „Nur Neuzugang“ ist der Kontext einer Regel', 'view-refused@1200')}
</section>`;

  const phone = `
<section class="mock-board">
  <h2>390 px: das Bottom-Sheet</h2>
  <p class="mock-note">Unter 720 px ist <code>.booking-delete-dialog</code> das Sheet des Merge-Dialogs: volle Breite, höchstens 88 % hoch, der Gefahr-Knopf auf einer eigenen Zeile über „Abbrechen“, 44-px-Knöpfe. Nichts davon ist neu; der Dialog tritt nur in die vorhandenen Selektorlisten ein.</p>
  ${fig('after', 'Kategorie löschen — A, Stability', 'cat-after@390')}
  ${fig('after', 'Kategorie löschen — abgelehnt, Growth', 'cat-refused@390')}
  ${fig('after', 'Ansicht löschen — nichts sonst, Ohne Krypto', 'view-after@390')}
</section>`;

  write('04-delete-dialogs.html', page('F21 — Löschdialoge, die sagen, was mitgeht', 'Klassifizierung · Kategorie · Ansicht (#894)', false, { head, desk }));
  write('04-delete-dialogs-390.html', page('F21 — Löschdialoge, die sagen, was mitgeht', 'Klassifizierung · Kategorie · Ansicht (#894)', true, { head, phone }));
};

if (require.main === module) module.exports.main();
