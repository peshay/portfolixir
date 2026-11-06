// The board's layout and text. build.js captures the frames into frames/
// and hands over their measured sizes; this file places them as <iframe>s
// with the reasons and the pins' legend, and writes
//   02-predictions.html      (the desktop board, rendered at 1200 px)
//   02-predictions-390.html  (the phone board, rendered at 390 px)
// `node board.js` alone rebuilds the boards from frames/sizes.json.
// BOARD_CSS is the Sprint 23 and 24 boards' artboard chrome
// (../ux-design-2026-11-05-sprint24-p1/board.js) with a recommended tag.
const fs = require('fs');
const path = require('path');

const BOARD_CSS = `
/* Artboard chrome only; everything inside a frame is priv/static/app.css. */
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 1120px; margin: 0 auto 36px; }
.mock-head h1 { margin: 0 0 6px; font-size: 20px; }
.mock-head h1 small, .mock-board > h2 small { font-weight: 500; color: var(--color-text-muted); margin-left: 6px; font-size: 12.5px; }
.mock-board > h2 { margin: 0 0 4px; font-size: 16px; font-weight: 760; }
.mock-board > h3 { margin: 18px 0 4px; font-size: 14px; font-weight: 720; }
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
.mock-tag--rec { color: #fff; background: var(--color-accent); }
.mock-frame { width: max-content; max-width: 100%; border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg); overflow: hidden; box-shadow: var(--shadow-panel); }
.mock-frame iframe { display: block; border: 0; }
.mock-row { display: flex; gap: 20px; align-items: flex-start; }
.mock-notes ul, .mock-notes ol { margin: 0; padding-left: 18px; }
.mock-notes li { margin: 0 0 6px; }
.mock-pin { display: inline-grid; place-items: center; width: 18px; height: 18px; border-radius: 50%; background: #c026d3; color: #fff; font: 700 11px/1 var(--font-sans); vertical-align: 1px; margin-right: 4px; }
.mock-why { margin: 8px 0 14px; padding: 8px 12px; border-left: 3px solid var(--color-accent); background: var(--color-bg-elevated); font-size: 12.5px; line-height: 1.5; color: var(--color-text-muted); }
.mock-why p { margin: 0 0 6px; } .mock-why p:last-child { margin: 0; }
.mock-why ul { margin: 0; padding-left: 18px; } .mock-why li { margin: 0 0 4px; }
.mock-key { display: inline-block; width: 22px; height: 12px; vertical-align: -1px; margin: 0 4px 0 2px; border-radius: 3px; }
.mock-key--new { outline: 2px dashed var(--color-accent); outline-offset: -2px; }
.mock-key--synth { box-shadow: inset 4px 0 0 #f59e0b; background: var(--color-bg-elevated); border: 1px solid var(--color-border); }
/* The phone board: the frames are the 390 px viewport. */
body.mock-phone { padding: 16px 0; }
body.mock-phone .mock-board > :not(.mock-fig), body.mock-phone .mock-head > * { margin-left: 16px; margin-right: 16px; }
body.mock-phone .mock-fig > .mock-tag { margin-left: 16px; }
body.mock-phone .mock-frame { width: 100%; border-radius: 0; border-left: 0; border-right: 0; box-shadow: none; }
`;

module.exports.main = function main(sizes) {
  sizes = sizes || JSON.parse(fs.readFileSync(path.join(__dirname, 'frames', 'sizes.json'), 'utf8'));
  const size = (key) => { const s = sizes[key]; if (!s) throw new Error('frame not captured: ' + key); return s; };
  const iframe = (key, title) => {
    const s = size(key);
    return `<iframe src="${s.file}" width="${s.width}" height="${s.height}" title="${title}" scrolling="no"></iframe>`;
  };
  const fig = (kind, label, key) => `<figure class="mock-fig"><figcaption class="mock-tag mock-tag--${kind}">${label}</figcaption><div class="mock-frame">${iframe(key, label)}</div></figure>`;
  const pin = (n) => `<span class="mock-pin">${n}</span>`;

  const legend = `<p class="mock-note"><span class="mock-key mock-key--new"></span> gestrichelt = neu · <span class="mock-key mock-key--synth"></span> amberfarbener Streifen = erfundene Prognose (der Review-Seed hat keine) · ${pin(1)} ${pin(2)} … verweisen auf die Liste unter dem Bild. Wertpapiere, Kurse und Benchmark sind die des synthetischen Review-Seeds; jede Prognose, jedes Modell („model-alpha-2“, „model-alpha-3“), jede Zahl und jede Begründung ist für das Board erfunden. Keine echten Daten.</p>`;

  const page = (title, sub, phone, body) => `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mockup — ${title}${phone ? ' — 390 px' : ''} (Sprint 26)</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js and board.js from the review instance on the
     synthetic review seed. Each frame is a static page under frames/ that
     links app.css; a frame with the proposal carries its CSS in its own
     <style id="proposal">. The block below is artboard chrome only. No
     script runs on this page or in a frame. -->
<style id="board">${BOARD_CSS}</style>
</head>
<body class="${phone ? 'mock-phone' : ''}" data-widths="${phone ? '390' : '1200'}">
<div class="mock-board mock-head">
  <h1>${title} <small>${sub}${phone ? ' · 390 px' : ''}</small></h1>
  ${body.head}
  ${legend}
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
    <p><b>F1, die menschliche Sicht auf Prognosen</b> (ADR-0055 §5; die Zwei-Wege-Regel macht sie in Sprint 26 fällig). Heute gibt es Prognosen nur über API und MCP.</p>
    <p><b>Die Wahl: wo der Kalibrierungsbericht wohnt.</b> <b>A, ein eigener Vermögen-Tab „Prognosen“, empfohlen</b>, oder B, ein Block auf „Risiko“ unter den eigenen Regeln. Schweigen übernimmt A; ein Kommentar „F1 B“ ändert es.</p>
    <p><b>Ohne Wahl, aber per Kommentar umkehrbar:</b> der Tab „Prognosen“ am Wertpapier (nach „Research“, in der Anatomie der Research- und Termine-Liste) und die zwei Zeilen von #1365 (Lösch-Bestätigung, Benchmark-Markierung) als Vorher/Nachher.</p>
  </div>`;

  const tabPins = `<div class="mock-why"><ul>
    <li>${pin(1)} <b>Der zehnte Tab, nach „Research“</b>: eine Prognose zeigt auf einen Research-Eintrag (<code>note_id</code>), also stehen die beiden nebeneinander; „Termine“ rückt eins nach rechts. Die Tab-Zeile ist seit D6 zum Überlaufen gebaut (Scroll-Snap, Kantenblende), auf dem Telefon rollt der Hook den gewählten Tab in Sicht.</li>
    <li>${pin(2)} <b>Die Grundzeile endet im ⓘ</b> (I1, Lesart 1, wie „Research“ und „Termine“): sie sagt, dass keine Prognose geändert oder gelöscht wird; das ⓘ trägt die Berechnungsgrundlage des Payloads (<code>computation_basis</code>: Start- und Endkurs, die Wartezeit auf den Endkurs, 7 Tage Veraltung, EUR, Überrendite, nur Kursrendite) und dass erfasst wird über API oder MCP.</li>
    <li>${pin(3)} <b>Der Stand als Badge</b>: „offen · noch 145 Tage“ (neutral), „offen · wartet auf den Schlusskurs“ (Amendment 2 des ADR, nur in der Liste unten zu sehen), „Treffer“ (die grüne Kontur der intakten These), „verfehlt“ (gedämpft, kein Alarm: ein Fehlschlag ist kein Datenfehler), „nicht aufgelöst“ (gestrichelt, wie „nicht bestimmbar“ der Regeln). Der linke Rand folgt: Akzent offen, grün Treffer, grau verfehlt, gestrichelt nicht aufgelöst.</li>
    <li>${pin(4)} <b>Die Aussage in einem Satz</b>, daneben die Wahrscheinlichkeit: „Übertrifft &lt;Benchmark&gt; bis &lt;Datum&gt;“, „Bleibt bis &lt;Datum&gt; hinter &lt;Benchmark&gt; zurück“, bei <code>rate:0</code> „Steigt / Fällt bis“, bei einem festen Satz „Übertrifft 2,0 % p. a. bis“. Kopfzeile: Nummer, Tag der Abgabe, Urheber und Modell, wie der Research-Eintrag sie schreibt.</li>
    <li>${pin(5)} <b>Erst aufgelöst kommen Zahlen</b>: Rendite, Benchmark-Rendite, Überrendite (Pp, tabellarische Ziffern) und die Daten der benutzten Schlusskurse. Offen und nicht aufgelöst sagt die Aussagezeile alles; eine Faktenzeile hätte sie nur wiederholt.</li>
    <li>${pin(6)} <b>Nicht aufgelöst nennt den Grund</b> (<code>no_start_close</code>, <code>no_end_close</code>, <code>no_benchmark_close</code>, <code>no_fx_rate</code>) als Wort und als Satz, nie eine Schätzung.</li>
    <li>${pin(7)} <b>Der Research-Eintrag</b>, zu dem die Prognose gehört, als Link in den Research-Tab.</li>
  </ul></div>`;

  const reportPins = `<div class="mock-why"><ul>
    <li>${pin(1)} <b>Der siebte Tab im Vermögen-Bereich</b>, Route <code>/predictions</code>. Die Kopfzeile sagt, dass der Bericht über alle Wertpapiere geht und nicht von der Ansicht abhängt; die Tab-Zeile ist seit #790 zum Überlaufen gebaut.</li>
    <li>${pin(2)} <b>Urheber und Modell</b> als Filterchips (<code>author</code>, <code>model</code> des Endpunkts); sie gelten für den Bericht und die Liste. Den Zeitraum über <code>resolves_on</code> bekommt die Story als dritte Chipfamilie, wenn sie ihn braucht; das Board zeichnet ihn nicht.</li>
    <li>${pin(3)} <b>Die Überschrift ist ein Score mit seiner Unsicherheit</b>: Brier-Score ± Standardfehler, darunter die Referenz 0,25 (immer 50 %) (Bedingung 1 des ADR). Die Karten sind die kompakten des Risiko-Tabs.</li>
    <li>${pin(4)} <b>Schärfe neben der Kalibrierung</b> (Bedingung 3), dann die Trefferquote ± Standardfehler neben der mittleren angegebenen Wahrscheinlichkeit, dann was nicht zählt.</li>
    <li>${pin(5)} <b>Die fünf Bänder</b>: solange kein Band 20 aufgelöste Prognosen hat, ein Satz, warum keine Trefferquote erscheint, und die Zählung je Band in einer Zeile. Ab 20 im ersten Band die Tabelle, in der ein Band unter 20 „zu wenige · n von 20“ sagt (unten, späterer Stand).</li>
    <li>${pin(6)} <b>Dieselben Zahlen je Urheber und je Modell</b> (Bedingung 2); auf dem Telefon als Zeilen.</li>
    <li>${pin(7)} <b>Alle Prognosen über alle Wertpapiere</b>, die neueste zuerst, mit Statuschips; „Fällig“ ist die Abfrage <code>due_before</code> (offen, Auflösungstag erreicht). Der Name führt in den Tab des Wertpapiers.</li>
  </ul></div>`;

  const whyA = `<div class="mock-why">
    <p><b>Warum A:</b> der Bericht bekommt Platz für das, was ADR-0055 §4 und §5 verlangen: Filter nach Urheber und Modell, die Gruppen, die Bänder und die Liste über alle Wertpapiere mit der Fälligkeitsabfrage, die sonst keinen Ort hätte (der Tab am Wertpapier zeigt nur dessen Prognosen). Er steht bei den anderen Auswertungen des Vermögens (Risiko, Snapshots), und ein eigener Tab lässt sich verlinken.</p>
    <p><b>Was A kostet:</b> ein siebter Tab in einer Zeile, die auf dem Telefon schon rollt, und ein Tab im Vermögen-Bereich, der nicht von der Ansicht abhängt; die Kopfzeile sagt es. Im ersten Jahr steht dort oft „zu wenige“: das ist die ehrliche Antwort (ADR §4), kein Fehler.</p>
  </div>`;
  const whyB = `<div class="mock-why">
    <p><b>Für B:</b> kein neuer Tab; der Block steht neben den eigenen Regeln, der anderen Bewertung von Entscheidungen.</p>
    <p><b>Gegen B:</b> „Risiko“ liest Konzentration und Schwankung der Ansicht, die Kalibrierung misst einen Urheber über alle Wertpapiere; die Kopfzeile „Ansicht: Alles“ stimmt für den Block nicht. Die Seite hat schon fünf Abschnitte. Für die Liste aller Prognosen und die Fälligkeitsabfrage bleibt kein Ort, und Filter nach Urheber und Modell wären ein zweites Filtersystem auf einer Seite, deren Filter die Ansicht ist.</p>
    <p><b>Erwogen, nicht gezeichnet — C, ein eigener Eintrag in der Seitenleiste:</b> unabhängig von der Ansicht, aber ein Hauptbereich für eine Seite, die ein Jahr lang meist „zu wenige“ sagt; die Seitenleiste trägt die vier Kernbereiche.</p>
  </div>`;

  const whyDelete = `<div class="mock-why"><p>${pin(1)} Die Bestätigung erscheint vor jeder Prüfung (das Wertpapiermenü liest die Verweise nicht vorab) und spricht darum allgemein; seit ADR-0055 §2 sperrt eine Prognose das Löschen, als Wertpapier wie als Benchmark (<code>delete: :restrict</code>). „Kann nicht gelöscht werden“ zählt Prognosen schon („hat noch 3 Prognosen“, <code>ReferenceCounts</code>) und bleibt, wie es ist. Neu ist nur ein Wort in einem bestehenden Satz, also ein neuer msgid.</p></div>`;
  const whyUnflag = `<div class="mock-why"><p>${pin(2)} Die Benchmark-Markierung prüft nur, welche Wertpapiere eine <b>neue</b> Prognose nennen darf; festgehaltene Prognosen messen weiter an ihr. Das Formular des Wertpapiers hat kein Feld für die Markierung: sie wird im Zeilenmenü umgeschaltet („${'Benchmark-Markierung entfernen'}“), und das Ergebnis erscheint als Hinweis über der Liste. Dort steht der Zusatz, und nur wenn Prognosen sie als Benchmark nennen, mit ihrer Zahl (hier die 13 erfundenen gegen „Kestrel Industrial Group NV Index“, die einzige Benchmark des Seeds).</p></div>`;

  const desk = `
<section class="mock-board">
  <h2>Teil 1 · Wertpapier → Prognosen <small>/securities/1, Apple Inc. · 1200 px, Seitenleiste offen (980 px Hauptspalte)</small></h2>
  ${fig('after', 'Vorschlag — vier Prognosen: offen, verfehlt, Treffer, nicht aufgelöst', 'tab@1200')}
  ${tabPins}
  ${fig('alt', 'Das ⓘ geöffnet: die Berechnungsgrundlage', 'tab-tip@1200')}
  ${fig('alt', 'Leer — /securities/36, Harborline Freight Inc', 'tab-empty@1200')}
  ${fig('alt', 'Dunkel', 'tab-dark@1200')}
</section>
<section class="mock-board">
  <h2>Teil 2 · Wo der Kalibrierungsbericht wohnt <small>die Wahl</small></h2>
  <h3>A — ein eigener Vermögen-Tab „Prognosen“ <span class="mock-tag mock-tag--rec">empfohlen</span></h3>
  ${fig('after', 'A — 12 aufgelöst: die Bänder noch ohne Trefferquote', 'report-a@1200')}
  ${reportPins}
  ${whyA}
  ${fig('alt', 'A — ein späterer Stand (erfunden): zwei Bänder über 20', 'report-a-later@1200')}
  ${fig('alt', 'A — dunkel', 'report-a-dark@1200')}
  <h3>B — ein Block auf „Risiko“ unter den eigenen Regeln</h3>
  ${fig('alt', 'B — derselbe Bericht ohne Filter und ohne Liste', 'report-b@1200')}
  ${whyB}
</section>
<section class="mock-board">
  <h2>Teil 3 · #1365, zwei Zeilen, die die Story mitnimmt <small>vorher / nachher · /securities</small></h2>
  <h3>Die Lösch-Bestätigung nennt Prognosen <small>(Zeilenmenü → Löschen, die native Bestätigung des Browsers, nachgezeichnet)</small></h3>
  ${fig('before', 'Vorher — der ausgelieferte Satz', 'delete-before@1200')}
  ${fig('after', 'Nachher', 'delete-after@1200')}
  ${whyDelete}
  <h3>Benchmark-Markierung entfernen sagt, was mit festgehaltenen Prognosen geschieht</h3>
  ${fig('before', 'Vorher — der ausgelieferte Hinweis', 'unflag-before@1200')}
  ${fig('after', 'Nachher', 'unflag-after@1200')}
  ${whyUnflag}
</section>`;

  const phone = `
<section class="mock-board">
  <h2>Wertpapier → Prognosen</h2>
  <p class="mock-note">Die Liste ist die Research-Zeitleiste; unter 480 px stapelt das ausgelieferte Faktenraster in eine Spalte, die vier kurzen Fakten einer aufgelösten Prognose bleiben zu zweit nebeneinander. Die Tab-Zeile steht, wie der Hook sie beim Ankommen rollt.</p>
  ${fig('after', 'Vorschlag', 'tab@390')}
  ${fig('alt', 'Leer', 'tab-empty@390')}
  ${fig('alt', 'Dunkel', 'tab-dark@390')}
  <h2>A — Vermögen → Prognosen <small>empfohlen</small></h2>
  <p class="mock-note">Karten zu zweit (das ausgelieferte KPI-Band unter 720 px), Gruppen und Liste als zweizeilige Zeilen (UX-DR27).</p>
  ${fig('after', 'Vorschlag', 'report-a@390')}
</section>`;

  write('02-predictions.html', page('F1 — Prognosen', 'Tab am Wertpapier und Kalibrierungsbericht · ADR-0055 §5', false, { head, desk }));
  write('02-predictions-390.html', page('F1 — Prognosen', 'Tab am Wertpapier und Kalibrierungsbericht', true, { head, phone }));
};

if (require.main === module) module.exports.main();
