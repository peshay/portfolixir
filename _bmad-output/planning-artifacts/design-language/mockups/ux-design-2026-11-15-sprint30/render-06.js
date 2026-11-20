// Board 06, drawn in Sprint 30's closing act for the design critic's
// findings whose fix changes what a screen shows, before the fixes land
// (the sprint workflow's "a closing-act fix gets its frame first"):
//
//   ① finding 1: Wealth's Total at „ab 0“ on a window with an overdraft,
//      the line beside the stack at „Kategorien“;
//   ② finding 2: the Crashes list's „ggü. ‹benchmark›“ head, which never
//      wrapped;
//   ③ finding 5: the Crashes basis line, shortened to the open-prose rule;
//   ④ a board correction: board 04's frame 04i drew the movers card's link
//      with `view=`, which the built card does not carry;
//   ⑤ the UAT persona's findings whose fix changes the picture beyond ①
//      to ③: finding 2, the area under the line at „ab 0“ stands on 0,
//      not on the axis' floor (`06i`); finding 5, the basis line's last
//      part names the chosen securities (`06j`).
//
// Writes frames/06a* to 06f*, 06i*, 06j* and 06-closing-act.html (06g and 06h, the
// movers card, are build.js's: they need its card), then serves this
// repository on a loopback port (the frames link the real
// priv/static/app.css, whose @font-face rules load the app's own Inter from
// /fonts/, served from priv/static/fonts/), measures each frame
// (frames/06-probes.json) and renders the board at 1x in both themes,
// reduced to 256 colours when python3 with Pillow is available.
//
// Usage: node build.js && node render-06.js
// (PLAYWRIGHT_CHROMIUM_EXECUTABLE names a Chromium of the machine's own,
// NODE_PATH test/browser/node_modules.) Render it in Playwright 1.65.0's
// headless shell (revision 1254), the browser CI's walks run in.
//
// The fragments under captured/06-* are the app's own markup, rendered by
// LiveViewTest in German from two test worlds, synthetic all the way down:
// wealth_axis_start_live_test.exs's world with its overdraft (Alpha and
// Beta Synthetic, the tree „Strategy“, 1,000 below 0 on two days) and
// test/browser/crash_section_layout_test.exs's world with the crash
// benchmark named „Synthetic All-World Crash Index UCITS ETF USD Acc“.
// `06-gesamt-ab-0-neu.html` is the line as finding 1's fix draws it,
// rendered from a scratch build of the fix; `06-gesamt-ab-0-uat.html` the
// same line after the UAT persona's finding 2, rendered from its fix on
// the same day (19.11.2026); every other fragment is today's.
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');

const DIR = __dirname;
const FRAMES = path.join(DIR, 'frames');
const ROOT = path.resolve(DIR, '../../../../..');
const BOARD = '06-closing-act';
const WIDTH = 2060;
const cap = (f) => fs.readFileSync(path.join(DIR, 'captured', f), 'utf8');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

// The open-prose rule's own counts (test/browser/control_bar.js).
const words = (text) => text.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;

const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.workspace-section { padding: 28px; }
.mock-label { margin: 0 0 6px; font-size: 12px; font-weight: 650; color: var(--color-text-muted); }
.mock-label + * { margin-top: 0; }
.mock-gap { height: 20px; }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 2px; border-radius: 8px; }
.mock-crop { margin: 12px 0 0; padding: 8px 12px; border: 1px dashed var(--color-border-strong); border-radius: var(--radius-md); font-size: 12px; color: var(--color-text-muted); }
.mock-count { font-weight: 600; font-variant-numeric: tabular-nums; }
.mock-case { margin: 0 0 14px; }
.mock-case:last-child { margin-bottom: 0; }
`;

function writeFrame(file, body, css = '') {
  const doc = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${file.replace(/\.html$/, '')}</title>
<link rel="stylesheet" href="../../../../../../priv/static/app.css">
<style id="frame">${FRAME_CSS}</style>
<style id="rule">${css}</style>
</head>
<body><div style="width: 980px">
${body}
</div></body>
</html>
`;
  fs.writeFileSync(path.join(FRAMES, file), doc.replace(/[ \t]+$/gm, ''));
}

// ① The line and the stack. On the line, the stack's top edge as the
// board's own dashed line (`mock`), day by day at the line's x: the
// stack's first `data-points` vertices of each area above 0 are its upper
// edge, the least y the top.
const STACK = cap('06-kategorien.html');
function stackTop() {
  const points = Number(STACK.match(/data-points="(\d+)"/)[1]);
  const tops = [];
  for (const m of STACK.matchAll(/<path class="stack-band[^"]*"([^>]*?)\sd="([^"]+)"[^>]*>/g)) {
    if (/data-part="negative"/.test(m[0]) || /stack-band--negative/.test(m[0])) continue;
    const ys = [...m[2].matchAll(/[ML]\s*(-?[\d.]+),(-?[\d.]+)/g)].map((v) => Number(v[2])).slice(0, points);
    ys.forEach((y, i) => (tops[i] = tops[i] === undefined ? y : Math.min(tops[i], y)));
  }
  return tops;
}
const TOP = stackTop();
function lineWithEdge(html) {
  const xs = html.match(/<polyline class="quote-line"[^>]*points="([^"]+)"/)[1].trim().split(/\s+/).map((p) => Number(p.split(',')[0]));
  if (xs.length !== TOP.length) throw new Error(`the line draws ${xs.length} days, the stack ${TOP.length}`);
  const edge = xs.map((x, i) => `${x.toFixed(2)},${TOP[i].toFixed(2)}`).join(' ');
  const mark = `<polyline class="mock-edge" points="${edge}" fill="none" style="stroke: var(--color-accent); stroke-width: 1.6; stroke-dasharray: 5 4; vector-effect: non-scaling-stroke"></polyline>`;
  return html.replace('</svg>', mark + '</svg>');
}
const chartsFrame = (line, label) => `<section class="workspace-section" id="portfolio-performance">
<p class="mock-label">Gesamt · Achse „ab 0“ (<code>level=total&amp;axis=zero</code>) · ${label}; gestrichelt (Board): die Oberkante des Stapels darunter, Tag für Tag</p>
${lineWithEdge(line)}
<div class="mock-gap"></div>
<p class="mock-label">Kategorien, derselbe Zeitraum (1J, Ansicht Alles): der Bargeld-Band 1.000 unter 0 an zwei Tagen</p>
${STACK}
</section>`;

// ② The list: the section as the app draws it, the windows' disclosure
// left out. Each frame states its rule in its own <style id="rule">, so the
// board draws the same before and after the fix lands in app.css.
const WRAP_BEFORE = '.crash-table th.num.crash-pp { white-space: nowrap; }';
const WRAP_AFTER = '.crash-table th.num.crash-pp { white-space: normal; }';
const CRASH_CSS = '#crash-windows { display: none; }';
const crashFrame = (html) => `${html}
<p class="mock-crop">Darunter wie heute: die Crash-Fenster (zugeklappt).</p>`;

// ③ The basis line, every list × reference the screen can show, today's
// copy and the shortened one, each with its word count (at most 25 words
// for an open paragraph; today's line is excused up to 40 by the walk's
// `crash-basis` exception, which the fix deletes).
const NAME = 'Synthetic All-World Crash Index UCITS ETF USD Acc';
const TODAY = {
  losers: 'Grundlage: Kursrendite in EUR von Hoch bis Tief des Fensters',
  final: 'Grundlage: Anstieg in EUR vom eigenen Tief bis zum Ende der Erholungsspanne',
  open: 'Grundlage: Anstieg in EUR vom eigenen Tief bis zum letzten Schluss (19.11.2026), nicht bis zum Ende der Spanne',
  same: `gestrichelt ${NAME} über dieselben Tage (-25,6 %)`,
  rebound: `gestrichelt ${NAME} (+3,4 %)`,
  unpriced: `kein Vergleich: ${NAME} hat für diese Tage keinen Kurs oder Wechselkurs`,
  none: 'kein Vergleich: kein Crash-Benchmark gewählt',
  universe: 'nur Wertpapiere, die der Katalog heute führt.'
};
const NEW = {
  losers: 'Grundlage: Kursrendite in EUR, Hoch bis Tief des Fensters',
  final: 'Grundlage: Anstieg in EUR vom eigenen Tief bis zum Ende der Erholungsspanne',
  open: 'Grundlage: Anstieg in EUR vom eigenen Tief bis zum letzten Schluss (19.11.2026), Spanne offen',
  same: 'gestrichelt: Crash-Benchmark, dieselben Tage (-25,6 %)',
  rebound: 'gestrichelt: Crash-Benchmark (+3,4 %)',
  unpriced: 'kein Vergleich: Crash-Benchmark ohne Kurs',
  none: 'kein Vergleich: kein Crash-Benchmark gewählt',
  universe: 'nur Wertpapiere im Katalog.'
};
const CASES = [
  ['Verlierer, mit Crash-Benchmark', 'losers', 'same'],
  ['Verlierer, kein Crash-Benchmark gewählt', 'losers', 'none'],
  ['Erholer, Spanne zu Ende, mit Crash-Benchmark', 'final', 'rebound'],
  ['Erholer, Spanne offen, Crash-Benchmark ohne Kurs', 'open', 'unpriced']
];
const NEW_INFO = 'Gestrichelt: der Crash-Benchmark über dieselben Tage; ohne seinen Kurs oder Wechselkurs an diesen Tagen kein Vergleich.';
function basisFrame(copy, info) {
  const cases = CASES.map(([label, figure, ref]) => {
    const text = [copy[figure], copy[ref], copy.universe].join(' · ');
    const n = words(text);
    return `<div class="mock-case"><p class="mock-label">${label} · <span class="mock-count">${n} Wörter</span>${n > 25 ? ' (über 25)' : ''}</p><p class="summary-basis crash-basis">${esc(text)}</p></div>`;
  });
  const extra = info
    ? `<div class="mock-case mock-new"><p class="mock-label">ⓘ des Abschnitts, neue Zeile nach „Kurs an einem Tag …“</p><p class="summary-basis">${esc(info)}</p></div>`
    : '';
  return `<section class="workspace-section crash-section">${cases.join('\n')}${extra}</section>`;
}
// ⑤ The UAT persona's finding 5: the last part follows the universe,
// the one the API's computation basis names. Each universe with the
// losers' line and the longest line any list can have (the rebounders
// over an open span, no crash benchmark chosen).
const UNIVERSES = [
  ['Ganzer Katalog', 'nur Wertpapiere im Katalog.'],
  ['Im Depot, Ansicht Alles', 'nur heute gehaltene Wertpapiere.'],
  ['Im Depot, in einer Ansicht', 'nur heute gehaltene Wertpapiere der Ansicht.']
];
const UNIVERSE_CASES = [
  ['Verlierer, mit Crash-Benchmark', 'losers', 'same'],
  ['Erholer, Spanne offen, kein Crash-Benchmark gewählt', 'open', 'none']
];
function universeFrame() {
  const cases = UNIVERSES.flatMap(([universe, part]) =>
    UNIVERSE_CASES.map(([label, figure, ref]) => {
      const text = [NEW[figure], NEW[ref], part].join(' · ');
      const n = words(text);
      return `<div class="mock-case"><p class="mock-label">${universe} · ${label} · <span class="mock-count">${n} Wörter</span>${n > 25 ? ' (über 25)' : ''}</p><p class="summary-basis crash-basis">${esc(text)}</p></div>`;
    })
  );
  return `<section class="workspace-section crash-section">${cases.join('\n')}</section>`;
}
const universeMax = () =>
  Math.max(...UNIVERSES.flatMap(([, part]) => UNIVERSE_CASES.map(([, f, r]) => words([NEW[f], NEW[r], part].join(' · ')))));

const maxWords = (copy) => Math.max(...CASES.map(([, f, r]) => words([copy[f], copy[r], copy.universe].join(' · '))));

const FRAME_LIST = [
  { file: '06a-ab-0-heute.html', body: chartsFrame(cap('06-gesamt-ab-0-heute.html'), 'heute: die eigene Achse, 0 bis 10.000') },
  { file: '06b-ab-0-neu.html', body: chartsFrame(cap('06-gesamt-ab-0-neu.html'), 'neu: die Achse des Stapels, −2.500 bis 10.000') },
  { file: '06c-crash-kopf-heute.html', body: crashFrame(cap('06-crash-verlierer.html')), css: WRAP_BEFORE + CRASH_CSS },
  { file: '06d-crash-kopf-neu.html', body: crashFrame(cap('06-crash-verlierer.html')), css: WRAP_AFTER + CRASH_CSS },
  { file: '06e-crash-grundlage-heute.html', body: basisFrame(TODAY) },
  { file: '06f-crash-grundlage-neu.html', body: basisFrame(NEW, NEW_INFO) },
  { file: '06i-ab-0-flaeche.html', body: chartsFrame(cap('06-gesamt-ab-0-uat.html'), 'nach dem UAT: die Fläche steht auf 0') },
  { file: '06j-crash-grundlage-universum.html', body: universeFrame() }
];
const BUILT = ['06g-bewegte-ansicht-heute.html', '06h-bewegte-ansicht-neu.html'];

const fig = (tag, label, file, height) =>
  `<figure class="mock-fig"><span class="mock-tag"><b>${tag}</b>${label}</span><div class="mock-frame"><iframe src="frames/${file}" width="980" height="${height}" title="${file}"></iframe></div></figure>`;

function writeBoard(p) {
  const h = (f) => (p[f] ? p[f].height : 600);
  const n = (v) => String(v).replace('.', ',');
  const pp = (f) => p[f] || {};
  const doc = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sprint 30 · Abschlussakt — was die Designkritik am Bild ändert</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Written by render-06.js. Each frame under frames/ is a static page that
     links app.css; the block below is artboard chrome only. No script runs
     here. Synthetic data only. -->
<style id="board">
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 2010px; margin: 0 auto 28px; }
.mock-head h1 { margin: 0 0 6px; font-size: 22px; }
.mock-head p { max-width: 150ch; font-size: 13px; line-height: 1.55; }
.mock-board > h2 { margin: 0 0 4px; font-size: 17px; font-weight: 760; }
p.mock-note { margin: 0 0 12px; max-width: 150ch; font-size: 13px; color: var(--color-text-muted); line-height: 1.5; }
.mock-row { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
.mock-fig { margin: 0; }
.mock-tag { display: block; max-width: 980px; margin: 0 0 6px; font-size: 12px; font-weight: 600; color: var(--color-text-muted); }
.mock-tag b { display: inline-block; margin-right: 6px; padding: 1px 9px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; background: var(--color-bg-muted); color: var(--color-text-muted); }
.mock-frame { width: max-content; border: 1px solid var(--color-border-strong); border-radius: 10px; overflow: hidden; box-shadow: var(--shadow-panel); background: var(--color-bg); }
.mock-frame iframe { display: block; border: 0; }
</style>
</head>
<body>
<div class="mock-board mock-head"><h1>Sprint 30 · Abschlussakt: was die Designkritik am Bild ändert</h1>
<p><strong>Anlass:</strong> die Designkritik des Abschlussakts (Sprint 30). Drei ihrer Befunde ändern, was ein Bildschirm zeigt, und eine Zeichnung von Board 04 zeigt nicht, was gebaut ist. Jede Zeile hier zeigt heute und neu nebeneinander, bevor der Code folgt. Die Fragmente sind das Markup der App selbst (LiveViewTest, deutsch), aus zwei synthetischen Testwelten; nur die Linie in ① „neu“ stammt aus einem Probe-Build des Fixes, und ③ ist der Basissatz als Text.</p>
<p><strong>Was bleibt:</strong> die Achse bei „Ausschnitt“, der Stapel, die Spalten der Crash-Liste, die Grundlage der API (<code>computation_basis</code>) und der Link der Karte. Keine Zeile hier ist eine Wahl; es sind Korrekturen gegen DESIGN.md und D-1.</p></div>

<section class="mock-board">
  <h2>① Befund 1 (S3): bei „ab 0“ liegt die Linie auf der Achse des Stapels, auch unter 0</h2>
  <p class="mock-note">D-1 Kriterium 2: bei „ab 0“ trifft die Gesamt-Linie die Oberkante des Stapels bei „Kategorien“ Tag für Tag. Heute spannt die Linie ihre eigene Achse (0 bis ihr Höchstwert plus 5 %); der Stapel reicht an einem Tag mit überzogenem Konto eine runde Stufe unter 0 (−2.500), also liegen die beiden Achsen verschieden und die Linie überall neben der gestrichelten Oberkante. Neu nimmt die Linie die Achse des Stapels für dasselbe Fenster, den Boden eingeschlossen: an jedem Tag ohne Band unter 0 liegt sie auf der Oberkante, an den zwei Tagen mit dem Bargeld 1.000 unter 0 um genau diese Tiefe darunter, weil die Summe die Bänder über 0 weniger das darunter ist.</p>
  <div class="mock-row">${fig('Heute', 'die Linie auf ihrer eigenen Achse', '06a-ab-0-heute.html', h('06a-ab-0-heute.html'))}${fig('Neu', 'die Linie auf der Achse des Stapels', '06b-ab-0-neu.html', h('06b-ab-0-neu.html'))}</div>
</section>

<section class="mock-board">
  <h2>② Befund 2 (S3): der Kopf „ggü. ‹Benchmark›“ bricht um, der Name behält Platz</h2>
  <p class="mock-note">DESIGN.md, Crashes Punkt 6: „ein langer Name und der Kopf ‚ggü.‘ brechen um“. In <code>app.css</code> steht <code>.crash-table th.num { white-space: nowrap }</code> nach <code>.crash-table th.crash-pp { white-space: normal }</code>, mit derselben Spezifität, also bricht der Kopf nie um: mit dem langen Namen des Crash-Benchmarks nimmt er ${n(pp('06c-crash-kopf-heute.html').ppWidth)} px, und die Spalte „Wertpapier“ behält ${n(pp('06c-crash-kopf-heute.html').nameWidth)} px (Zeilen bis ${n(pp('06c-crash-kopf-heute.html').rowMax)} px hoch). Neu (<code>.crash-table th.num.crash-pp { white-space: normal }</code>): der Kopf ${n(pp('06d-crash-kopf-neu.html').ppWidth)} px auf ${n(pp('06d-crash-kopf-neu.html').ppLines)} Zeilen, „Wertpapier“ ${n(pp('06d-crash-kopf-neu.html').nameWidth)} px, Zeilen bis ${n(pp('06d-crash-kopf-neu.html').rowMax)} px. 1200 px, Inter.</p>
  <div class="mock-row">${fig('Heute', '„ggü. …“ in einer Zeile', '06c-crash-kopf-heute.html', h('06c-crash-kopf-heute.html'))}${fig('Neu', '„ggü. …“ bricht um', '06d-crash-kopf-neu.html', h('06d-crash-kopf-neu.html'))}</div>
</section>

<section class="mock-board">
  <h2>③ Befund 5: der Basissatz der Crash-Liste in höchstens 25 Wörtern</h2>
  <p class="mock-note">Die Regel für offene Absätze (ein Satz, höchstens 25 Wörter) hatte für <code>crash-basis</code> eine Ausnahme bis 40 Wörter, weil der Satz den gespeicherten Namen des Crash-Benchmarks trug. Neu nennt der Satz ihn „Crash-Benchmark“; der Name steht weiter im Kopf „ggü. ‹Name›“ und in der Regelzeile der Fenster. Was der Satz sagen muss, bleibt: was gemessen wird, wogegen die gestrichelte Linie misst und ihr Wert, dass nur Wertpapiere im Katalog zählen. Dass dem Benchmark Kurs oder Wechselkurs fehlen kann, sagt eine neue Zeile im ⓘ. Längster Fall heute ${maxWords(TODAY)} Wörter, neu ${maxWords(NEW)}; Englisch neu höchstens 24. Der Rundgang verliert die Ausnahme.</p>
  <div class="mock-row">${fig('Heute', 'mit dem Namen, bis ' + maxWords(TODAY) + ' Wörter', '06e-crash-grundlage-heute.html', h('06e-crash-grundlage-heute.html'))}${fig('Neu', '„Crash-Benchmark“, bis ' + maxWords(NEW) + ' Wörter', '06f-crash-grundlage-neu.html', h('06f-crash-grundlage-neu.html'))}</div>
</section>

<section class="mock-board">
  <h2>④ Berichtigung von Board 04, Rahmen 04i: die Karte „Tops und Flops“ wie gebaut</h2>
  <p class="mock-note">04i zeichnete den Link „In Vermögen ansehen →“ als <code>/portfolio?view=…&amp;from=…&amp;to=…</code>. Gebaut ist er ohne <code>view=</code> (#1081: ein Link der Übersicht ändert die Ansicht nicht, die Vermögen sich merkt); wo diese Ansicht nicht die der Karte ist, nennt ein Satz unter dem Basissatz beide (Commit „fix(dashboard): the movers card names Wealth's other view instead of linking it“). Hier merkt sich Vermögen „Alles“, die Karte zeigt „Nur Neuzugang“. 04i selbst wird im nächsten Commit so neu gezeichnet. Zahlen erfunden, wie in 04i.</p>
  <div class="mock-row">${fig('04i', 'Link mit <code>view=nur-neuzugang</code>, kein Satz', BUILT[0], h(BUILT[0]))}${fig('Gebaut', 'Link ohne <code>view=</code>, der Satz unter dem Basissatz', BUILT[1], h(BUILT[1]))}</div>
</section>

<section class="mock-board">
  <h2>⑤ UAT-Persona, Befund 2 (S3): bei „ab 0“ steht die Fläche unter der Linie auf 0</h2>
  <p class="mock-note">Seit ① nimmt die Linie bei „ab 0“ die Achse des Stapels, deren Boden eine runde Stufe unter 0 liegt; die Fläche unter der Linie schloss weiter am Fuß des Diagramms und schattierte so an jedem Tag das Band von 0 bis −2.500, obwohl die Summe nie unter 0 fällt. Neu schließt die Fläche bei 0, wo die Achse unter 0 reicht: sie liest sich als der Betrag und ist nur dort unter 0 schattiert, wo die Linie es ist. Linie, Achse und Werte bleiben wie in ① „neu“; bei „Ausschnitt“, im Privatsphäre-Modus und in % bleibt die Fläche am Fuß.</p>
  <div class="mock-row">${fig('①', 'die Fläche bis zum Boden der Achse', '06b-ab-0-neu.html', h('06b-ab-0-neu.html'))}${fig('Neu', 'die Fläche steht auf 0', '06i-ab-0-flaeche.html', h('06i-ab-0-flaeche.html'))}</div>
</section>

<section class="mock-board">
  <h2>⑥ UAT-Persona, Befund 5 (S3): der Basissatz nennt die gewählten Wertpapiere</h2>
  <p class="mock-note">③ kürzte den Schluss des Basissatzes auf „nur Wertpapiere im Katalog.“, in jeder Auswahl; unter „Im Depot“ liest die Liste aber die heute gehaltenen Wertpapiere (in einer Ansicht die der Ansicht), wie die Grundlage der API (<code>computation_basis.universe</code>) sagt. Neu folgt der Schluss der Auswahl: „nur Wertpapiere im Katalog.“, „nur heute gehaltene Wertpapiere.“ oder „nur heute gehaltene Wertpapiere der Ansicht.“, höchstens sechs Wörter, sodass der längste Satz ${universeMax()} Wörter hat; Englisch „only securities in the catalogue.“, „only securities held today.“, „only securities the view holds today.“, höchstens 25. Die Zeilen davor bleiben wie in ③ „neu“.</p>
  <div class="mock-row">${fig('③', 'derselbe Schluss in jeder Auswahl', '06f-crash-grundlage-neu.html', h('06f-crash-grundlage-neu.html'))}${fig('Neu', 'der Schluss je Auswahl, bis ' + universeMax() + ' Wörter', '06j-crash-grundlage-universum.html', h('06j-crash-grundlage-universum.html'))}</div>
</section>
</body>
</html>
`;
  fs.writeFileSync(path.join(DIR, BOARD + '.html'), doc);
}

// This repository over HTTP: /fonts/* from priv/static/fonts, the rest
// from the root, so app.css's `url("/fonts/…")` loads the app's Inter.
function serve() {
  const types = { '.html': 'text/html', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml' };
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    p = p.startsWith('/fonts/') ? path.join(ROOT, 'priv/static', p) : path.join(ROOT, p);
    if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, { 'content-type': types[path.extname(p)] || 'application/octet-stream' });
    fs.createReadStream(p).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

(async () => {
  fs.mkdirSync(FRAMES, { recursive: true });
  FRAME_LIST.forEach((f) => writeFrame(f.file, f.body, f.css));
  for (const f of BUILT) if (!fs.existsSync(path.join(FRAMES, f))) throw new Error(f + ' is missing: run node build.js first');
  writeBoard({});
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}/` + path.relative(ROOT, DIR).split(path.sep).join('/') + '/';
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const browser = await chromium.launch(launch);
  const ctx = await browser.newContext({ deviceScaleFactor: 1, locale: 'de-DE' });

  // 1. Each frame: its height, and in the crash list its head and name
  //    column and its tallest row.
  const probes = {};
  for (const file of [...FRAME_LIST.map((f) => f.file), ...BUILT]) {
    const page = await ctx.newPage();
    await page.setViewportSize({ width: 980, height: 40 });
    await page.goto(base + 'frames/' + file, { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    probes[file] = await page.evaluate(() => {
      const round = (v) => Math.round(v);
      const r = { height: Math.ceil(document.documentElement.scrollHeight) };
      const head = document.querySelector('table.crash-table th.crash-pp');
      if (head) {
        const name = document.querySelector('table.crash-table th.crash-name');
        const line = parseFloat(getComputedStyle(head).lineHeight) || 16;
        const range = document.createRange();
        range.selectNodeContents(head);
        r.ppWidth = round(head.getBoundingClientRect().width);
        r.ppLines = Math.round(range.getBoundingClientRect().height / line);
        r.nameWidth = round(name.getBoundingClientRect().width);
        r.rowMax = round(Math.max(...[...document.querySelectorAll('table.crash-table tbody tr')].map((tr) => tr.getBoundingClientRect().height)));
      }
      return r;
    });
    await page.close();
  }
  probes.browser = browser.version();
  fs.writeFileSync(path.join(FRAMES, '06-probes.json'), JSON.stringify(probes, null, 1) + '\n');
  writeBoard(probes);

  // 2. The board in both themes, the theme set in every frame too.
  const page = await ctx.newPage();
  const written = [];
  for (const theme of ['light', 'dark']) {
    await page.setViewportSize({ width: WIDTH, height: 900 });
    await page.goto(base + BOARD + '.html', { waitUntil: 'load' });
    for (const f of page.frames()) await f.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
    for (const f of page.frames()) await f.evaluate(() => document.fonts.ready);
    const full = await page.evaluate(() => document.documentElement.scrollHeight);
    await page.setViewportSize({ width: WIDTH, height: full });
    await page.waitForTimeout(300);
    const png = path.join(DIR, `${BOARD}--${theme}.png`);
    await page.screenshot({ path: png, fullPage: true });
    written.push(png);
    console.log('rendered ' + path.basename(png));
  }
  await browser.close();
  server.close();
  try {
    const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
    execFileSync('python3', ['-c', QUANTIZE, ...written]);
    console.log('reduced to 256 colours');
  } catch (e) {
    console.log('left at full colour (python3 with Pillow not found)');
  }
})();
