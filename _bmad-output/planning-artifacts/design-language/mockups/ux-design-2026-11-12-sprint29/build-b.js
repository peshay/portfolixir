// Sprint 29 planning boards 03 to 06, drawn on 2026-11-12 before any code:
//
//   03 the Research tab shows a note's headline, event type and tone (the
//      two-way coverage gap Sprint 28's close-out recorded; ADR-0044's
//      amendment of 2026-11-06, ADR-0056 §8, A2 and D8), and the research
//      form that writes them (the plan's N4, frames 03h to 03q, added
//      before its story);
//   04 the Overview counts data-quality findings over held securities
//      first, the catalog count beside it (#1417; OQ-4 of 2026-11-07);
//   05 translucent bands in the stacked chart (idea I33);
//   06 labelled controls start on one edge: the bars that break it, before
//      and after the shared component (#1435; the inventory is
//      06-control-bar-inventory.md).
//
// The chrome is the app's own markup: the shell, the Research tab's basis
// line and thesis block, the Overview's data-quality line, the KPI cell and
// the bars of board 06 are captured from the review instance on the
// synthetic review seed by capture-b.js; the rest uses the classes the
// shipped templates use, so app.css draws it. What does not exist yet is
// in each frame's <style id="proposal">. Charts are inline SVG from a
// SYNTHETIC series (a seeded random walk, Sprint 28's). Every name is
// generic and every figure is invented or the seed's; no instance data,
// name or machine detail appears.
//
// Usage:
//   node capture-b.js            # optional: re-captures (review instance on :4012)
//   node capture-b-inventory.js  # optional: re-measures the bars and paragraphs
//   node build-b.js              # writes frames/03* to 06* and the four boards
//   node render-b.js             # renders each board to PNG, light and dark
const fs = require('fs');
const path = require('path');

const FRAMES = path.join(__dirname, 'frames');
fs.mkdirSync(FRAMES, { recursive: true });
const CSS_FROM_FRAME = '../../../../../../priv/static/app.css';
const STATIC_FROM_FRAME = '../../../../../../priv/static/';
const CSS_FROM_BOARD = '../../../../../priv/static/app.css';
const read = (f) => fs.readFileSync(path.join(__dirname, f), 'utf8');

// ---------------------------------------------------------------------------
// Synthetic data (Sprint 28's generator, its seed and its tree)

function rng(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20261108);
const gauss = () => {
  let u = 0, v = 0;
  while (u === 0) u = rand();
  while (v === 0) v = rand();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
};
const DATES = [];
for (let d = new Date(Date.UTC(2025, 10, 13)); d <= new Date(Date.UTC(2026, 10, 11)); d.setUTCDate(d.getUTCDate() + 1)) {
  const wd = d.getUTCDay();
  if (wd !== 0 && wd !== 6) DATES.push(new Date(d));
}
const N = DATES.length;
const MARKET = DATES.map((_, i) => {
  let r = 0.0004 + 0.0072 * gauss();
  if (i >= 95 && i < 108) r -= 0.006;
  return r;
});
const PALETTE = ['#2563eb', '#16a34a', '#ffab01', '#db2777', '#0d9488', '#7c3aed', '#65a30d', '#ea580c'];
const TREE = [
  { name: 'Aktien', color: PALETTE[0], secs: [
    { n: 'Welt-Aktien ETF', v: 30000, beta: 1.0, vol: 0.004 }, { n: 'USA-Aktien ETF', v: 12000, beta: 1.1, vol: 0.005 },
    { n: 'Schwellenländer ETF', v: 6000, beta: 1.15, vol: 0.007, buyAt: 128, buy: 4000 },
    { n: 'Technik-Einzelwert A', v: 6500, beta: 1.7, vol: 0.016 }, { n: 'Industrie-Einzelwert B', v: 4500, beta: 1.2, vol: 0.01 }] },
  { name: 'Anleihen', color: PALETTE[1], secs: [{ n: 'Staatsanleihen ETF', v: 11000, beta: -0.12, vol: 0.002 }] },
  { name: 'Rohstoffe', color: PALETTE[2], secs: [{ n: 'Gold ETC', v: 5500, beta: 0.05, vol: 0.007 }] },
  { name: 'Krypto', color: PALETTE[3], secs: [{ n: 'Krypto-Wert', v: 3500, beta: 1.9, vol: 0.025 }] },
];
const UNCLASSIFIED = [{ n: 'Nebenwert E', v: 2500, beta: 1.3, vol: 0.012 }, { n: 'Altfonds F', v: 1800, beta: 0.7, vol: 0.006 }];
// The cash account is overdrawn for a stretch (a buy booked before the
// money that pays it), so the stack has a part below zero (#1426).
const CASH = { n: 'Cash', v: 6000, cash: true };
function walk(s) {
  s.values = []; s.flows = [];
  let v = s.v;
  for (let i = 0; i < N; i++) {
    let flow = 0;
    if (i > 0 && !s.cash) v *= 1 + s.beta * MARKET[i] + s.vol * gauss() + 0.0001;
    if (s.buyAt === i) { v += s.buy; flow = s.buy; }
    if (s.cash && i === 128) { v -= 4000; flow = -4000; }
    const dip = s.cash && i >= 186 && i <= 214 ? 9500 : 0;
    s.values.push(v - dip); s.flows.push(flow);
  }
  return s;
}
for (const c of TREE) c.secs.forEach(walk);
UNCLASSIFIED.forEach(walk);
walk(CASH);
const sum = (secs) => DATES.map((_, i) => secs.reduce((a, s) => a + s.values[i], 0));
const flows = (secs) => DATES.map((_, i) => secs.reduce((a, s) => a + s.flows[i], 0));

const nf0 = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const nf2 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const pct = (x) => (x > 0 ? '+' : x < 0 ? '−' : '') + nf1.format(Math.abs(x * 100)) + '%';
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const dmy = (d) => `${String(d.getUTCDate()).padStart(2, '0')}.${String(d.getUTCMonth() + 1).padStart(2, '0')}.${d.getUTCFullYear()}`;

// ---------------------------------------------------------------------------
// The stacked chart as stacked_chart.ex renders it (viewBox 960 x 320, the
// plot 56..936 x 16..292): a band that changes sign first, next to zero,
// its part below zero a separate path.stack-band--negative.

const W = 960, H = 320, L = 56, R = 936, T = 16, B = 292;
const xAt = (i) => L + (R - L) * i / (N - 1);
function niceMax(v) {
  const mag = Math.pow(10, Math.floor(Math.log10(v)));
  return [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].map((m) => m * mag).find((s) => s >= v);
}
function band(name, color, secs, extra = {}) {
  const values = sum(secs), fl = flows(secs);
  const start = values[0], end = values[N - 1];
  const net = fl.reduce((a, f) => a + f, 0);
  return { name, color, values, end, change: start > 0 ? (end - start - net) / start : null, ...extra };
}
function stackSvg(bands, opts = {}) {
  const changesSign = (b) => b.values.some((v) => v < 0) && b.values.some((v) => v > 0);
  const order = [...bands.filter(changesSign), ...bands.filter((b) => !changesSign(b))];
  const posTop = DATES.map((_, i) => order.reduce((a, b) => a + Math.max(0, b.values[i]), 0));
  const negBot = DATES.map((_, i) => order.reduce((a, b) => a + Math.min(0, b.values[i]), 0));
  const scale = opts.scale || 1;
  const max = niceMax(Math.max(...posTop) * scale * 1.02);
  const lo = Math.min(...negBot) < 0 ? -niceMax(-Math.min(...negBot) * scale * 1.1) : 0;
  const y = (v) => B - (B - T) * (v * scale - lo) / (max - lo);
  const pos = DATES.map(() => 0), neg = DATES.map(() => 0);
  const poly = (top, bot) => 'M' + top.map((v, i) => `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`).join('L') + 'L' + bot.map((v, i) => [i, v]).reverse().map(([i, v]) => `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`).join('L') + 'Z';
  const paths = [];
  for (const b of order) {
    const pTop = [], pBot = [], nTop = [], nBot = [];
    for (let i = 0; i < N; i++) {
      const v = b.values[i];
      pBot.push(pos[i]); pos[i] += Math.max(0, v); pTop.push(pos[i]);
      nTop.push(neg[i]); neg[i] += Math.min(0, v); nBot.push(neg[i]);
    }
    const click = b.drill ? ' phx-click="drill_stack"' : '';
    const hover = opts.hover === b.name ? ' mock-hover' : '';
    paths.push(`<path class="stack-band${hover}" d="${poly(pTop, pBot)}" fill="${b.color}" data-band="${esc(b.name)}"${click}><title>${esc(b.name)}</title></path>`);
    if (b.values.some((v) => v < 0)) paths.push(`<path class="stack-band stack-band--negative${hover}" d="${poly(nTop, nBot)}" fill="${b.color}" data-part="negative"${click}><title>${esc(b.name)}</title></path>`);
  }
  const ticks = lo < 0 ? [lo, 0, max / 2, max] : [0, max / 4, max / 2, 3 * max / 4, max];
  const fmt = opts.axis || ((t) => nf0.format(t));
  const grid = ticks.map((t) => `<line x1="${L}" y1="${y(t / scale).toFixed(2)}" x2="${R}" y2="${y(t / scale).toFixed(2)}"></line>`).join('');
  const labels = ticks.map((t, k) => `<text class="chart-axis-y${k === ticks.length - 1 ? ' is-top' : ''}" x="50" y="${y(t / scale).toFixed(2)}" text-anchor="end" dominant-baseline="central">${fmt(t)}</text>`).join('');
  const zero = lo < 0 ? `<line class="chart-zeroline" x1="${L}" x2="${R}" y1="${y(0).toFixed(1)}" y2="${y(0).toFixed(1)}"></line>` : '';
  return `<svg class="stack-chart" role="img" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" width="100%"><g class="chart-axes" stroke="currentColor" stroke-opacity="0.15">${grid}</g>${paths.join('')}${zero}<g class="chart-axis-labels">${labels}<text class="chart-axis-x" x="${L}" y="314" text-anchor="start">${dmy(DATES[0])}</text><text class="chart-axis-x" x="${R}" y="314" text-anchor="end">${dmy(DATES[N - 1])}</text></g></svg>`;
}
function legend(rows, opts = {}) {
  const tot = rows.reduce((a, b) => a + b.end, 0);
  const body = rows.map((r) => `<tr><td class="stack-legend__name"><span class="stack-swatch" style="background: ${r.color}" aria-hidden="true"></span>${r.drill ? `<a class="stack-legend__drill">${esc(r.name)}</a><span class="stack-legend__chevron" aria-hidden="true">›</span>` : esc(r.name)}</td>${opts.privacy ? '' : `<td class="num">${nf2.format(r.end)}</td>`}<td class="num">${pct(r.end / tot)}</td><td class="num">${r.change === null ? '—' : pct(r.change)}</td></tr>`).join('');
  return `<table class="stack-legend" id="stack-legend"><thead><tr><th scope="col">Kategorie</th>${opts.privacy ? '' : '<th scope="col" class="num">Wert</th>'}<th scope="col" class="num">Anteil</th><th scope="col" class="num">Veränd.</th></tr></thead><tbody>${body}</tbody></table>`;
}
function seg(label, id, options, active) {
  return `<span class="stack-bar__group"><span class="stack-bar__label" id="${id}">${label}</span><div class="segmented-control" role="group" aria-labelledby="${id}">${options.map((o) => `<a class="segmented-control__option${o === active ? ' is-active' : ''}">${o}</a>`).join('')}</div></span>`;
}
const stackBar = `<div class="stack-bar" data-role="stack-bar"><nav class="stack-crumbs" aria-label="Stapel"><span aria-current="location">Alle Kategorien</span></nav><div class="stack-bar__controls">${seg('Ebene', 'stack-level-label', ['Gesamt', 'Kategorien', 'Wertpapiere'], 'Kategorien')}<form class="stack-bar__tree"><label for="stack-classification">Klassifizierung</label><select id="stack-classification"><option>Strategie</option></select></form>${seg('Sortieren', 'stack-sort-label', ['Größe', 'Veränderung'], 'Größe')}</div></div>`;
const modeSeg = (active) => `<div class="section-head-controls" style="justify-content: flex-start; margin: 0 0 12px;"><div class="segmented-control" role="group">${['% (TTWROR)', active].map((o, k) => `<a class="segmented-control__option${k === 1 ? ' is-active' : ''}">${o}</a>`).join('')}</div><div class="segmented-control" role="group">${['YTD', '1J', '3J', '5J', 'Max'].map((o) => `<a class="segmented-control__option${o === '1J' ? ' is-active' : ''}">${o}</a>`).join('')}</div></div>`;
const tip = (text) => `<details class="metric-tooltip metric-tooltip--inline metric-tooltip--section"><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">${text}</p></details>`;

// ---------------------------------------------------------------------------
// Frames and boards (Sprint 28's writer and layout; the sizes file is this
// half's own, so the boards drawn beside these keep theirs)

const SHELL = read('shell-b.html').replace(/src="\/images\//g, `src="${STATIC_FROM_FRAME}images/`);
const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 2px; border-radius: 8px; }
.mock-pad { padding: 16px 20px; }
.mock-crop { margin: 0; padding: 8px 12px; border: 1px dashed var(--color-border-strong); border-radius: var(--radius-md); font-size: 12px; color: var(--color-text-muted); }
.mock-gone { padding: 10px 14px; border: 1px dashed var(--color-border-strong); border-radius: var(--radius-md); font-size: 12.5px; color: var(--color-text-muted); background: var(--color-bg-muted); }
`;
const BREAK_BEFORE = /><(?=\/?(?:path|g|svg|line|circle|text|tr|td|th|thead|tbody|table|div|section|figure|nav|aside|header|form|select|label|button|a|p|h[1-6]|li|ol|dl|details|span class="(?:stack-bar__group|control-bar|badge|research-entry|filter-chips__family)))/g;
const multiline = (s) => s.replace(BREAK_BEFORE, '>\n<');

function writeFrame(name, rawBody, { css = '', width = 1000, shell = false, title = '', subtitle = '', active = null } = {}) {
  const body = multiline(rawBody);
  let html = body;
  if (shell) {
    html = SHELL.replace('%%MAIN%%', body)
      .replace(/<h1 id="app-topbar-title">[^<]*<\/h1>/, `<h1 id="app-topbar-title">${title}</h1>`)
      .replace(/<p id="app-topbar-subtitle">[^<]*<\/p>/, `<p id="app-topbar-subtitle">${subtitle}</p>`)
      .replace(/class="nav-link is-active"/g, 'class="nav-link "');
    if (active) html = html.replace(new RegExp(`id="${active}" class="nav-link "`), `id="${active}" class="nav-link is-active"`);
  }
  const doc = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${name}</title>
<link rel="stylesheet" href="${CSS_FROM_FRAME}">
<style id="frame">${FRAME_CSS}</style>
<style id="proposal">${css}</style>
</head>
<body>${html}</body>
</html>
`;
  fs.writeFileSync(path.join(FRAMES, name + '.html'), doc.replace(/[ \t]+$/gm, ''));
  return { file: name + '.html', width };
}

const BOARD_CSS = (cols) => `
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: ${cols}px; margin: 0 auto 28px; }
.mock-head h1 { margin: 0 0 6px; font-size: 22px; }
.mock-board > h2 { margin: 0 0 4px; font-size: 17px; font-weight: 760; }
.mock-board > h2 small { font-size: 12px; font-weight: 700; color: var(--color-accent); background: var(--color-accent-soft); padding: 2px 8px; border-radius: 999px; margin-left: 6px; vertical-align: 2px; }
p.mock-note { margin: 0 0 12px; max-width: 130ch; font-size: 13px; color: var(--color-text-muted); line-height: 1.5; }
.mock-pickbar { margin: 0 0 16px; padding: 12px 16px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 13px; line-height: 1.55; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-row { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
.mock-fig { margin: 0; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); }
.mock-frame { width: max-content; border: 1px solid var(--color-border-strong); border-radius: 10px; overflow: hidden; box-shadow: var(--shadow-panel); background: var(--color-bg); }
.mock-frame iframe { display: block; border: 0; }
`;
function board(file, title, cols, intro, sections) {
  const sec = sections.map((s) => `
<section class="mock-board">${s.lead ? `
  <div class="mock-pickbar">${s.lead}</div>` : ''}
  <h2>${s.title}${s.recommended ? ' <small>empfohlen</small>' : ''}${s.decided ? ' <small>entschieden</small>' : ''}${s.option ? ' <small>Option, nicht Standard</small>' : ''}</h2>
  <p class="mock-note">${s.note}</p>
  <div class="mock-row">${s.frames.map((f) => `<figure class="mock-fig">${f.tag ? `<span class="mock-tag">${f.tag}</span>` : ''}<div class="mock-frame"><iframe src="frames/${f.file}" width="${f.width}" height="${f.height}" title="${f.file}"></iframe></div></figure>`).join('')}</div>
</section>`).join('\n');
  fs.writeFileSync(path.join(__dirname, file), `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<link rel="stylesheet" href="${CSS_FROM_BOARD}">
<!-- Generated by build-b.js. Each frame under frames/ is a static page that
     links app.css; the block below is artboard chrome only. No script runs
     here. Synthetic data only. -->
<style id="board">${BOARD_CSS(cols)}</style>
</head>
<body>
<div class="mock-board mock-head"><h1>${esc(title)}</h1>${intro}</div>
${sec}
</body>
</html>
`);
}
let SIZES = {};
try { SIZES = JSON.parse(fs.readFileSync(path.join(FRAMES, 'sizes-b.json'), 'utf8')); } catch (e) { /* first run */ }
const sized = (f, tag) => ({ ...f, tag, height: SIZES[f.file] || 700 });

// ===========================================================================
// Board 03 — the Research tab shows a note's headline, event type and tone

const RESEARCH_CSS = `
.research-entry__headline { margin: 0; display: flex; gap: 8px; align-items: flex-start; font-size: 14.5px; font-weight: 650; line-height: 1.35; overflow-wrap: anywhere; }
.research-entry__tone { flex: none; margin-top: 2.5px; }
.research-entry__tone circle { fill: var(--color-text-muted); stroke: var(--color-bg-elevated); stroke-width: 1.5; }
.research-entry__tone--pos circle { fill: var(--color-positive); }
.research-entry__tone--neg circle { fill: var(--color-danger); }
.research-entry__tone path { fill: none; stroke: var(--color-bg-elevated); stroke-width: 1.6; stroke-linecap: round; }
.research-entry__label { margin: 0; display: flex; flex-wrap: wrap; gap: 6px; align-items: center; font-size: 12px; color: var(--color-text-muted); }
.research-entry--superseded .research-entry__headline { font-weight: 600; }
.research-entry--superseded .research-entry__tone circle { fill: var(--color-border-strong); }
.research-filter { margin: 0 0 var(--space-3); }
`;
const toneGlyph = (tone) => {
  const cls = tone > 0 ? 'pos' : tone < 0 ? 'neg' : 'neu';
  const word = tone > 0 ? 'positiv' : tone < 0 ? 'negativ' : 'neutral';
  const glyph = tone > 0 ? '<path d="M4 7H10M7 4V10"></path>' : tone < 0 ? '<path d="M4 7H10"></path>' : '';
  return `<svg class="research-entry__tone research-entry__tone--${cls}" width="14" height="14" viewBox="0 0 14 14" role="img" aria-label="Tonalität ${word}"><circle cx="7" cy="7" r="6"></circle>${glyph}</svg>`;
};
const TONE_WORD = { 1: 'positiv', 0: 'neutral', '-1': 'negativ' };
const KIND = { evidence: 'Beleg', event_result: 'Ereignisergebnis', thesis: 'These' };
const QUALITY = { primary: 'Primärquelle', secondary_multi: 'Mehrere Sekundärquellen', awareness: 'Wahrnehmung', unverified: 'Ungeprüft' };
const MACHINE_TITLE = 'Ereignisart und Tonalität aus der Einordnung eines Modells übernommen; mit dem Schreiben bestätigt';
// Synthetic entries of „Beispiel Technik AG“, newest first.
const ENTRIES = [
  { id: 41, kind: 'evidence', q: 'primary', as_of: '06.11.2026', author: 'Agent', headline: 'Quartalsbericht: Umsatz über dem eigenen Ausblick', event: 'Zahlen', tone: 1, machine: true,
    body: 'Umsatz im dritten Quartal rund 6 % über dem Ausblick vom Juli, Marge unverändert. Aus dem Bericht des Emittenten übernommen.', url: 'https://ir.example/berichte/q3-2026' },
  { id: 39, kind: 'event_result', q: 'secondary_multi', as_of: '30.10.2026', author: 'Operator', headline: 'Klage wegen eines Patents eingereicht', event: 'Recht', tone: -1, machine: false,
    body: 'Zwei Meldungen nennen eine Klage eines Wettbewerbers; der Streitwert ist offen. Beobachten bis zur ersten Anhörung.', url: 'https://wire.example/2026/10/30/klage' },
  { id: 37, kind: 'evidence', q: 'primary', as_of: '22.10.2026', author: 'Agent', headline: 'Vorstand bestätigt den Ausblick', event: 'Ausblick', tone: 0, machine: true, supersedes: 35,
    body: 'Der Vorstand bestätigt den Ausblick für das Gesamtjahr; die Warnung aus #35 trifft nicht zu.', url: 'https://ir.example/mitteilungen/2026-10-22' },
  { id: 35, kind: 'evidence', q: 'unverified', as_of: '18.10.2026', author: 'Agent', headline: 'Bericht erwartet eine Gewinnwarnung', event: 'Ausblick', tone: -1, machine: true, supersededBy: [37],
    body: 'Ein einzelner Bericht erwartet eine Senkung des Ausblicks; keine Bestätigung durch den Emittenten.', url: 'https://blog.example/2026/10/18/ausblick' },
  { id: 30, kind: 'evidence', q: 'primary', as_of: '15.07.2026', author: 'Operator',
    body: 'Hauptversammlung: Dividende wie vorgeschlagen beschlossen, Rückkauf bis 5 % des Kapitals genehmigt.', url: 'https://ir.example/hv-2026' },
];
function entryHtml(e, mode) {
  const sup = e.supersededBy ? ' research-entry--superseded' : '';
  const head = `<div class="research-entry__head"><span class="badge badge--kind-${e.kind}">${KIND[e.kind]}</span><span class="badge badge--quality-${e.q}">${QUALITY[e.q]}</span>${mode === 'B' && e.event ? `<span class="badge badge--neutral mock-new">${e.event}</span>` : ''}<span class="research-entry__meta">#${e.id} · ${e.as_of} · ${e.author}</span></div>`;
  const markers = (e.supersedes ? `<p class="research-entry__marker">Ersetzt #${e.supersedes}</p>` : '') + (e.supersededBy ? `<p class="research-entry__marker research-entry__marker--superseded">Ersetzt durch #${e.supersededBy.join(', #')}</p>` : '');
  const machine = e.machine ? ` <span class="badge badge--neutral" title="${MACHINE_TITLE}">maschinell</span>` : '';
  let shown = '';
  if (e.headline && mode === 'A') {
    shown = `<div class="mock-new" style="display: grid; gap: 4px;"><p class="research-entry__headline">${toneGlyph(e.tone)}<span>${esc(e.headline)}</span></p><p class="research-entry__label">${e.event} · ${TONE_WORD[e.tone]}${machine}${e.supersededBy ? ' · nicht im Diagramm, weil ersetzt' : ''}</p></div>`;
  } else if (e.headline && mode === 'B') {
    shown = `<p class="research-entry__headline mock-new">${toneGlyph(e.tone)}<span>${esc(e.headline)}</span>${e.machine ? `<span class="badge badge--neutral" title="${MACHINE_TITLE}">maschinell</span>` : ''}</p>`;
  }
  const facts = `<dl class="research-entry__facts"><div><dt>Quellenlink</dt><dd><a href="${e.url}" rel="noopener noreferrer" target="_blank">${e.url}</a></dd></div></dl>`;
  return `<li id="research-entry-${e.id}" data-entry-id="${e.id}" data-kind="${e.kind}" class="research-entry research-entry--${e.kind}${sup}">${head}${markers}${shown}<p class="research-entry__body">${esc(e.body)}</p>${facts}</li>`;
}
const RESEARCH_TOP = read('research-b.html')
  .replace(/Services mix keeps margins above 40% through the cycle; hold while capex stays flat\./, 'Das Servicegeschäft hält die Marge über den Zyklus über 40 %; halten, solange die Investitionen nicht steigen.');
const filterChips = `<div class="filter-chips research-filter mock-new" role="group" aria-label="Einträge filtern"><span class="filter-chips__family">Ereignisart</span><button type="button" class="filter-chip is-active" aria-pressed="true">Alle</button><button type="button" class="filter-chip" aria-pressed="false">Zahlen · 1</button><button type="button" class="filter-chip" aria-pressed="false">Ausblick · 2</button><button type="button" class="filter-chip" aria-pressed="false">Recht · 1</button><button type="button" class="filter-chip" aria-pressed="false">ohne · 1</button></div>`;
const researchTabs = ['Übersicht', 'Diagramm', 'Transaktionen', 'Trades', 'Kurse', 'Bestände', 'Klassifizierungen', 'Research', 'Nachrichten', 'Prognosen', 'Termine'];
const researchPane = (mode, opts = {}) => `<aside class="detail-pane" id="security-detail-pane" style="position: static; max-height: none;"><header class="detail-pane-head"><div class="detail-pane-head__title"><span class="security-logo security-logo--lg security-logo--initial" aria-hidden="true">B</span><div><h2>Beispiel Technik AG</h2><p class="detail-pane-sub">XX0000000041 · BTA · EUR · Letzter 142,18 (11.11.2026)</p></div></div><div class="detail-pane-head__actions"><button type="button" class="button-ghost">Bearbeiten</button><button type="button" class="button-ghost">Split erfassen</button></div></header><nav class="detail-pane-tabs" role="tablist">${researchTabs.map((t) => `<button type="button" role="tab" class="detail-pane-tab${t === 'Research' ? ' is-active' : ''}" aria-selected="${t === 'Research'}">${t}</button>`).join('')}</nav><section id="detail-tab-panel-research" role="tabpanel" class="detail-tab-panel detail-tab-panel--research">${RESEARCH_TOP}<form class="research-entry-form"><h3>Eintrag anhängen</h3><p class="mock-crop">Das Formular steht unverändert hier; das Board lässt es aus.</p></form>${opts.filter ? filterChips : ''}<ol class="research-timeline" aria-label="Research-Zeitleiste">${(opts.only ? ENTRIES.filter(opts.only) : ENTRIES).map((e) => entryHtml(e, mode)).join('')}</ol></section></aside>`;
const B3 = {};
B3.before = sized(writeFrame('03a-research-heute', researchPane('today'), { width: 1000 }), 'heute, 1200 px (der Bereich)');
B3.afterA = sized(writeFrame('03b-research-a', researchPane('A'), { width: 1000, css: RESEARCH_CSS }), 'A — Überschrift, darunter Ereignisart · Tonalität');
B3.afterB = sized(writeFrame('03c-research-b', researchPane('B', { only: (e) => e.id >= 37 }), { width: 1000, css: RESEARCH_CSS }), 'B — Ereignisart als Badge im Kopf');
B3.phoneBefore = sized(writeFrame('03d-research-heute-390', researchPane('today', { only: (e) => e.id >= 39 }), { width: 390 }), 'heute, 390 px');
B3.phoneA = sized(writeFrame('03e-research-a-390', researchPane('A', { only: (e) => e.id >= 39 }), { width: 390, css: RESEARCH_CSS }), 'A, 390 px');
B3.filter = sized(writeFrame('03f-research-filter', researchPane('A', { filter: true, only: (e) => e.id >= 37 }), { width: 1000, css: RESEARCH_CSS }), 'C — Filter nach Ereignisart');
B3.shell = sized(writeFrame('03g-research-a-shell', `<div class="workspace-page" style="padding: 16px 20px;">${researchPane('A', { only: (e) => e.id === 41 })}</div>`, { width: 1200, css: RESEARCH_CSS, shell: true, title: 'Wertpapiere', subtitle: 'Suchen, filtern und pflegen des investierbaren Universums.', active: 'nav-securities' }), 'A im Rahmen der App, 1200 px');

// ---------------------------------------------------------------------------
// Board 03, N4 — the research form takes a headline, an event type and a
// tone (the plan's N4, D-8 item 3: a frame added before the story starts).
// The form is securities_live.ex's #research-entry-form as rendered today
// (its labels, controls and classes, in German); the three fields copy the
// story promotion form's controls (stories_tab.ex: „Ereignisart“, „Tonalität“
// with „— nicht angegeben —“ first, „Überschrift“), whose labels and option
// words PortfolixirWeb.EventTypeLabel holds. Shown only while the kind is
// SecurityNote.marker_kinds() — Beleg or Ereignisergebnis — as the thesis
// fields show only for a thesis.

const FORM_KINDS = [['thesis', 'These'], ['evidence', 'Beleg'], ['invalidation_check', 'Invalidierungsprüfung'], ['event_result', 'Ereignisergebnis'], ['risk', 'Risiko'], ['retraction', 'Widerruf'], ['decision', 'Entscheidung']];
const FORM_QUALITIES = ['Primärquelle', 'Mehrere Sekundärquellen', 'Wahrnehmung', 'Ungeprüft'];
const EVENT_TYPES = [['earnings', 'Zahlen'], ['guidance', 'Ausblick'], ['capital_measure', 'Kapitalmaßnahme'], ['legal', 'Recht'], ['m_and_a', 'Übernahme oder Fusion'], ['product', 'Produkt'], ['regulatory', 'Regulierung'], ['macro', 'Makro']];
const TONES = [['1', 'positiv'], ['0', 'neutral'], ['-1', 'negativ']];
const MARKER_KINDS = ['evidence', 'event_result'];
const HEADLINE_HINT = 'Höchstens 80 Zeichen, eine Zeile. Nur ein Eintrag mit Überschrift steht als Nadel im Diagramm.';
const FORM_CSS = `
.research-entry-form__more { grid-column: 1 / -1; }
.research-entry-form__more > summary { color: var(--color-accent); }
.research-entry-form__more[open] > summary { margin-bottom: var(--space-2); }
.research-entry-form__grid [aria-invalid="true"] { border-color: var(--color-danger); }
`;
const opt = (value, label, selected) => `<option value="${value}"${selected ? ' selected' : ''}>${esc(label)}</option>`;
const sel = (name, options, value, blank) => `<select name="note[${name}]">${blank ? opt('', blank, !value) : ''}${options.map(([v, l]) => opt(v, l, v === value)).join('')}</select>`;
const chevron = '<svg class="disclosure-chevron" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9 6 6 6-6 6"></path></svg>';
function markerFields(v, { invalid = false } = {}) {
  return `<label class="research-entry-form__full"><span>Überschrift</span><input type="text" name="note[headline]" value="${esc(v.headline || '')}" aria-describedby="research-headline-hint"${invalid ? ' aria-invalid="true"' : ''} /></label>`
    + `<p class="hint research-entry-form__full" id="research-headline-hint">${HEADLINE_HINT}</p>`
    + `<label><span>Ereignisart</span>${sel('event_type', EVENT_TYPES, v.event_type, '— nicht angegeben —')}</label>`
    + `<label><span>Tonalität</span>${sel('tone', TONES, v.tone, '— nicht angegeben —')}</label>`;
}
// mode: 'today' | 'A' | 'B' (B takes opts.open)
function researchForm(mode, v = {}, opts = {}) {
  const kind = v.kind || 'evidence';
  const marks = mode !== 'today' && MARKER_KINDS.includes(kind);
  let markerBlock = '';
  if (marks && mode === 'A') markerBlock = `<div class="research-entry-form__full research-entry-form__grid mock-new" data-role="research-marker-fields">${markerFields(v, opts)}</div>`;
  if (marks && mode === 'B') markerBlock = `<details class="research-entry-form__more mock-new" data-role="research-marker-fields"${opts.open ? ' open' : ''}><summary class="disclosure-summary">${chevron}Überschrift und Einordnung</summary>${opts.open ? `<div class="research-entry-form__grid">${markerFields(v, opts)}</div>` : ''}</details>`;
  const thesis = kind === 'thesis'
    ? `<label><span>Überzeugung</span><select name="note[conviction]"><option value="">— nicht angegeben —</option><option>Niedrig</option><option>Mittel</option><option>Hoch</option></select></label><label class="research-entry-form__full"><span>Invalidierungsbedingung</span><input type="text" name="note[invalidation_condition]" value="" /></label><label><span>Zeitstopp</span><input type="text" placeholder="YYYY-MM-DD" pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}" maxlength="10" name="note[time_stop]" value="" /></label>`
    : '';
  const errors = opts.errors && opts.errors.length ? `<ul class="research-entry-form__errors" role="alert">${opts.errors.map((e) => `<li>${esc(e)}</li>`).join('')}</ul>` : '';
  return `<form id="research-entry-form" class="research-entry-form" aria-label="Eintrag anhängen"><h3>Eintrag anhängen</h3><div class="research-entry-form__grid">`
    + `<label><span>Art</span>${sel('kind', FORM_KINDS, kind)}</label>`
    + `<label><span>Quellenqualität</span>${sel('source_quality', FORM_QUALITIES.map((q) => [q, q]), v.quality || 'Primärquelle')}</label>`
    + `<label><span>Stichtag</span><input type="text" placeholder="YYYY-MM-DD" pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}" maxlength="10" name="note[as_of]" value="${v.as_of || '2026-11-12'}" required /></label>`
    + `<label><span>Ersetzt</span><select name="note[supersedes_id]"><option value="">— nichts —</option></select></label>`
    + markerBlock
    + `<label class="research-entry-form__full"><span>Eintrag</span><textarea name="note[body]" rows="3" required>${esc(v.body || '')}</textarea></label>`
    + `<label class="research-entry-form__full"><span>Quellenlink</span><input type="url" name="note[source_url]" inputmode="url" value="${esc(v.url || '')}" /></label>`
    + `<label><span>Gültig bis</span><input type="text" placeholder="YYYY-MM-DD" pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}" maxlength="10" name="note[valid_until]" value="" /></label>`
    + thesis
    + `</div>${errors}<button type="submit" class="button">Eintrag anhängen</button></form>`;
}
const formPane = (form) => `<aside class="detail-pane" id="security-detail-pane" style="position: static; max-height: none;"><header class="detail-pane-head"><div class="detail-pane-head__title"><span class="security-logo security-logo--lg security-logo--initial" aria-hidden="true">B</span><div><h2>Beispiel Technik AG</h2><p class="detail-pane-sub">XX0000000041 · BTA · EUR · Letzter 142,18 (11.11.2026)</p></div></div><div class="detail-pane-head__actions"><button type="button" class="button-ghost">Bearbeiten</button><button type="button" class="button-ghost">Split erfassen</button></div></header><nav class="detail-pane-tabs" role="tablist">${researchTabs.map((t) => `<button type="button" role="tab" class="detail-pane-tab${t === 'Research' ? ' is-active' : ''}" aria-selected="${t === 'Research'}">${t}</button>`).join('')}</nav><section id="detail-tab-panel-research" role="tabpanel" class="detail-tab-panel detail-tab-panel--research"><p class="mock-crop">Basis und These wie in ①; unverändert.</p>${form}<p class="mock-crop">Die Zeitleiste wie in ① bis ④.</p></section></aside>`;
// Synthetic values: #41's entry of this board, as the operator would type it.
const N4_FILLED = { kind: 'evidence', headline: 'Quartalsbericht: Umsatz über dem eigenen Ausblick', event_type: 'earnings', tone: '1',
  body: 'Umsatz im dritten Quartal rund 6 % über dem Ausblick vom Juli, Marge unverändert. Aus dem Bericht des Emittenten übernommen.', url: 'https://ir.example/berichte/q3-2026' };
const N4_LONG = { ...N4_FILLED, headline: 'Quartalsbericht: Umsatz im dritten Quartal rund sechs Prozent über dem eigenen Ausblick vom Juli' };
if ([...N4_LONG.headline].length <= 80) throw new Error('the long headline must pass 80 code points');
const N4_EVENT = { kind: 'event_result', quality: 'Mehrere Sekundärquellen', headline: 'Klage wegen eines Patents eingereicht', event_type: 'legal', tone: '-1',
  body: 'Zwei Meldungen nennen eine Klage eines Wettbewerbers; der Streitwert ist offen. Beobachten bis zur ersten Anhörung.', url: 'https://wire.example/2026/10/30/klage' };
const N4 = {};
N4.today = sized(writeFrame('03h-form-heute', formPane(researchForm('today')), { width: 1000 }), 'heute, 1200 px (der Bereich), Art Beleg');
N4.todayPhone = sized(writeFrame('03i-form-heute-390', formPane(researchForm('today')), { width: 390 }), 'heute, 390 px');
N4.a = sized(writeFrame('03j-form-a', formPane(researchForm('A', N4_FILLED)), { width: 1000, css: FORM_CSS }), 'A, Art Beleg, ausgefüllt');
N4.aEvent = sized(writeFrame('03k-form-a-ereignis', formPane(researchForm('A', N4_EVENT)), { width: 1000, css: FORM_CSS }), 'A, Art Ereignisergebnis');
N4.aThesis = sized(writeFrame('03l-form-a-these', formPane(researchForm('A', { kind: 'thesis' })), { width: 1000, css: FORM_CSS }), 'A, Art These: die drei fehlen, die These-Felder erscheinen (wie heute)');
N4.aError = sized(writeFrame('03m-form-a-fehler', formPane(researchForm('A', N4_LONG, { invalid: true, errors: ['Überschrift: darf höchstens 80 Zeichen lang sein'] })), { width: 1000, css: FORM_CSS }), 'A, abgelehnt: Überschrift über 80 Zeichen');
N4.aPhone = sized(writeFrame('03n-form-a-390', formPane(researchForm('A', N4_FILLED)), { width: 390, css: FORM_CSS }), 'A, 390 px');
N4.bClosed = sized(writeFrame('03o-form-b-zu', formPane(researchForm('B', {})), { width: 1000, css: FORM_CSS }), 'B, geschlossen (der Standard)');
N4.bOpen = sized(writeFrame('03p-form-b-offen', formPane(researchForm('B', N4_FILLED, { open: true })), { width: 1000, css: FORM_CSS }), 'B, geöffnet, ausgefüllt');
N4.bPhone = sized(writeFrame('03q-form-b-390', formPane(researchForm('B', {})), { width: 390, css: FORM_CSS }), 'B, 390 px, geschlossen');

const N4_LEAD = '<p><strong>N4 — das Research-Formular</strong> (Plan Sprint 29, N4; D-8 Punkt 3: als Rahmen vor der Story ergänzt). <strong>Entschieden:</strong> das Formular „Eintrag anhängen“ nimmt an Beleg und Ereignisergebnis eine optionale Überschrift (höchstens 80 Zeichen, ADR-0054 §4), eine Ereignisart und eine Tonalität, mit derselben Prüfung wie <code>notes.append</code>; der Autor bleibt der Operator, <code>news_label_id</code> bleibt leer (kein Label, aus dem etwas übernommen wurde).</p><p><strong>Was dieser Rahmen vorschlägt (per Kommentar umkehrbar):</strong> A — die drei Felder stehen im Raster, sobald die Art sie trägt, ohne Disclosure, in der Reihenfolge des Eintrags und mit den Steuerelementen von „Ins Research-Log“. Der Kommentar „Research-Formular B“ legt sie hinter die Disclosure „Überschrift und Einordnung“.</p>';
board('03-research-entry.html', 'Sprint 29 — Board 03: Überschrift, Ereignisart und Tonalität im Research-Tab', 1260,
  `<div class="mock-pickbar"><p><strong>Was entschieden und gebaut ist (ADR-0044, Amendment 2026-11-06; ADR-0056 §8, A2, D6, D8; Sprint 28 N5, N9):</strong> ein Eintrag der Art Beleg oder Ereignisergebnis kann eine Überschrift (höchstens 80 Zeichen), eine Ereignisart aus acht und eine Tonalität −1 · 0 · +1 tragen, einmal geschrieben, nie geändert; wird er aus einer Meldung übernommen, merkt er sich das Label, aus dem er Ereignisart oder Tonalität nahm (<code>news_label_id</code>). API und MCP schreiben und lesen alle vier; das Diagramm zeichnet jeden nicht ersetzten Eintrag mit Überschrift als Nadel in der Farbe und mit dem Zeichen seiner Tonalität. Die Tonalität ist eine gespeicherte Lesart, nie ein Filter, eine Sortierung oder ein Signal. <strong>Der Research-Tab zeigt keines der vier</strong> — die Lücke, die der Abschluss von Sprint 28 festhielt.</p><p><strong>Was dieses Board vorschlägt (per Kommentar umkehrbar):</strong> A — die Überschrift als erste Zeile des Eintrags, davor das Zeichen der Nadel (+, −, keins), darunter „Ereignisart · Tonalität“ in Worten, wie der Tooltip der Nadel sie liest; „maschinell“ dahinter, wenn der Eintrag Ereignisart oder Tonalität aus dem Label eines Modells nahm. Ein älterer Eintrag ohne Überschrift bleibt, wie er ist. Ein ersetzter Eintrag mit Überschrift sagt, warum er im Diagramm fehlt. Der Quellenlink steht wie heute unter dem Text. Kein Filter als Standard. Gestrichelt: was neu ist.</p><p><strong>Ergänzt vor N4:</strong> das Formular, das die drei Felder schreibt — ⑦ bis ⑪.</p></div>`,
  [
    { title: '① Heute', note: 'Der Tab, wie gebaut (Basis und These von der Review-Instanz, die Einträge synthetisch in der Markup der Vorlage): Art, Quellgüte, Nummer, Datum, Autor, Text und Quellenlink. Dass #41 im Diagramm als grüne Nadel „Quartalsbericht: Umsatz über dem eigenen Ausblick“ steht, sieht man hier nicht.', frames: [B3.before] },
    { title: '② A — die Zeilen des Tooltips im Eintrag', note: 'Die Überschrift fett mit dem Zeichen der Nadel davor (Farbe und Form, UX-DR7: nie Farbe allein), darunter „Zahlen · positiv“ und „maschinell“ (Titel: „Ereignisart und Tonalität aus der Einordnung eines Modells übernommen; mit dem Schreiben bestätigt“). „maschinell“ steht nur bei gesetztem <code>news_label_id</code>; <code>machine_generated</code> bleibt dem lokalen Modell vorbehalten und behält seinen Text „maschinell erzeugter Vorschlag“. #35 ist durch #37 ersetzt und sagt „nicht im Diagramm, weil ersetzt“ (D8). #30 hat keine Überschrift und sieht aus wie heute.', frames: [B3.afterA], recommended: true },
    { title: '③ B — Ereignisart als Badge im Kopf', note: 'Kompakter: die Ereignisart als dritte Badge neben Art und Quellgüte, die Tonalität nur als Zeichen vor der Überschrift. Spart eine Zeile, aber die Tonalität steht dann nur als Farbe und Form, ohne ihr Wort, und der Kopf liest sich anders als der Tooltip am Diagramm.', frames: [B3.afterB] },
    { title: '④ A bei 390 px', note: 'Die Überschrift bricht um, das Zeichen bleibt vor ihrer ersten Zeile; „Ereignisart · Tonalität“ und „maschinell“ brechen als eine Zeile um.', frames: [B3.phoneBefore, B3.phoneA], recommended: true },
    { title: '⑤ C — ein Filter nach Ereignisart', note: 'Chips der Ereignisarten, die die Einträge tragen, mit Anzahl, und „ohne“. Verdient seinen Platz erst, wenn ein Wertpapier Dutzende Einträge hat: heute liest man die Zeitleiste ganz. Er wäre eine neue Fähigkeit und braucht nach der Regel beider Wege einen Parameter <code>event_type</code> an <code>GET …/notes</code> und an notes.list; einen Filter nach Tonalität gibt es nie (ADR-0044). Daher nicht Standard.', frames: [B3.filter], option: true },
    { title: '⑥ A im Rahmen der App', note: 'Der Wertpapierbereich maximiert, 1200 px, mit der Navigation (Nachrichten nach Wertpapiere).', frames: [B3.shell] },
    { lead: N4_LEAD, title: 'N4 — das Research-Formular · ⑦ Heute', note: 'Das Formular „Eintrag anhängen“, wie <code>securities_live.ex</code> es rendert (<code>#research-entry-form</code>, seine Beschriftungen, Steuerelemente und Klassen): Art, Quellenqualität, Stichtag, Ersetzt, Eintrag, Quellenlink, Gültig bis; bei der Art These zusätzlich Überzeugung, Invalidierungsbedingung und Zeitstopp. Überschrift, Ereignisart und Tonalität setzt der Operator heute nur über „Ins Research-Log“ aus einer Meldung; ein Agent setzt sie über <code>notes.append</code> an jedem Beleg und Ereignisergebnis.', frames: [N4.today] },
    { title: 'N4 · ⑧ A — die drei Felder im Raster, sobald die Art sie trägt', recommended: true, note: 'Bei Beleg und Ereignisergebnis (<code>SecurityNote.marker_kinds()</code>) stehen über „Eintrag“ die Überschrift über die ganze Breite, darunter ihr Hinweis, dann Ereignisart und Tonalität — die Reihenfolge des Eintrags, den N3 zeichnet (Überschrift, darunter „Ereignisart · Tonalität“, dann der Text). Die Steuerelemente sind die von „Ins Research-Log“ (<code>stories_tab.ex</code>): dieselben Beschriftungen, „— nicht angegeben —“ als erste Wahl, die acht Ereignisarten und positiv · neutral · negativ in den Worten von <code>EventTypeLabel</code>. Ein Zeichenzähler fehlt mit Absicht: die App hat keinen, und ein neuer wäre ein eigenes Bauteil; der Hinweis nennt die Grenze und warum das Feld zählt. Kein <code>maxlength</code>: der Browser zählt UTF-16-Einheiten, der Server Codepunkte, und ein stilles Abschneiden beim Einfügen wäre schlechter als die Ablehnung. Bei jeder anderen Art fehlen die drei, wie die These-Felder bei jeder Art außer These fehlen — dieselbe Regel über dasselbe <code>phx-change</code>.', frames: [N4.a, N4.aEvent, N4.aThesis] },
    { title: 'N4 · ⑨ A — abgelehnt', recommended: true, note: 'Dieselbe Prüfung wie <code>notes.append</code> (<code>SecurityNote.changeset/3</code>): eine Überschrift über 80 Codepunkte, mit Zeilenumbruch oder unsichtbarem Zeichen wird abgelehnt, und die Meldung steht, wie heute jede Meldung des Formulars, in der Liste über dem Knopf, mit dem Feldnamen auf Deutsch („Überschrift: darf höchstens 80 Zeichen lang sein“; <code>research_field_label/1</code> braucht dafür <code>:headline</code>, <code>:event_type</code> und <code>:tone</code>). Die Eingaben bleiben stehen. Das Feld trägt <code>aria-invalid</code>; damit sein Rand rot wird, braucht das Raster eine Regel (<code>.research-entry-form__grid [aria-invalid="true"]</code>): heute gewinnt der Rand des Rasters gegen die allgemeine Regel, auch in „Ins Research-Log“.', frames: [N4.aError] },
    { title: 'N4 · ⑩ B — hinter der Disclosure „Überschrift und Einordnung“', note: 'Das Formular bleibt bei Beleg so kurz wie heute; die drei Felder öffnen sich unter einer Disclosure (die Form von „Kosten und Notiz“ im Buchungsformular, die Zusammenfassung in Akzentfarbe, weil sie Felder öffnet, nicht Daten). Der Preis: die Felder, die einen Eintrag ins Diagramm bringen, liegen einen Klick tiefer — die Lücke, die N4 schließt, bleibt halb offen; die Disclosure braucht den Hook <code>DisclosureState</code>, damit sie den Patch jeder Art-Änderung übersteht, muss sich bei einer abgelehnten Überschrift selbst öffnen (wie #869 bei den Kosten), und zwei Regeln schachteln sich (die Art entscheidet, ob es die Disclosure gibt, die Disclosure, ob man die Felder sieht). Eine neue Zeichenkette.', frames: [N4.bClosed, N4.bOpen] },
    { title: 'N4 · ⑪ Bei 390 px: heute, A, B', note: 'Das Raster legt zwei Spalten: Ereignisart und Tonalität stehen nebeneinander unter der Überschrift, der Hinweis bricht auf zwei Zeilen um. A verlängert das Formular bei Beleg um rund 180 px (bei 1200 px um rund 160), B um eine Zeile von rund 40 px.', frames: [N4.todayPhone, N4.aPhone, N4.bPhone] },
  ]);

// ===========================================================================
// Board 04 — the Overview counts data-quality findings over held securities first

const COUNTS = JSON.parse(read('counts-b.json'));
const DQ_CSS = '.data-note--clamped .data-note__text, .data-note__actions { max-height: none !important; -webkit-line-clamp: unset !important; } .data-note__more { display: none; } .dq-catalog { color: var(--color-text-muted); } .dq-catalog a { color: inherit; }';
const dqToday = read('dq-b.html');
const kpiToday = read('kpi-b.html');
const c = (id, k) => COUNTS[id][k];
const sep = '<span aria-hidden="true"> · </span>';
// A: each clause the held count, its link with holding=held; the catalog
// count beside it in parentheses, its own link, only where it differs.
const clauseA = (held, heldHref, text, catalog, catHref, effect, role) => `<a href="${heldHref}" data-role="${role}">${text}</a>${catalog !== held ? ` <span class="dq-catalog" data-catalog-of="${role}">(<a href="${catHref}">im Katalog ${catalog}</a>)</span>` : ''}${effect ? ` <span data-effect-of="${role}">${effect}</span>` : ''}`;
const heldLine = (kind) => {
  const clauses = [
    clauseA(c('stale_quote', 'held'), '/securities?dq=stale_quote&amp;holding=held', `${c('stale_quote', 'held')} gehaltene Wertpapiere ohne Kurs seit 7 Tagen`, c('stale_quote', 'catalog'), '/securities?dq=stale_quote', '', 'dq-quotes'),
    clauseA(1, '/securities?filter[]=asset_class%3Ais_nil&amp;holding=held', 'eins ohne Anlageklasse', 1, '#', '', 'dq-class'),
    clauseA(c('missing_logo', 'held'), '/securities?dq=missing_logo&amp;holding=held', `${c('missing_logo', 'held')} ohne Logo`, c('missing_logo', 'catalog'), '/securities?dq=missing_logo', '', 'dq-logo'),
    clauseA(c('two_scales', 'held'), '/securities?dq=two_scales&amp;holding=held', `${c('two_scales', 'held')} gehaltene Anleihen auf zwei Skalen bepreist`, c('two_scales', 'catalog'), '/securities?dq=two_scales', '— jede zählt in der Summe oben hundertfach zu hoch oder zu niedrig', 'dq-two-scales'),
    clauseA(1, '/securities?dq=implausible_quote&amp;holding=held', 'ein gehaltenes Wertpapier, dessen Kurse nicht zu seinen Buchungen passen', 1, '#', '— sein Wert in der Summe oben oder sein Einstand ist daher falsch', 'dq-implausible-quote'),
  ];
  if (kind === 'B') {
    const plain = clauses.map((s) => s.replace(/ <span class="dq-catalog"[^>]*>\(<a[^>]*>im Katalog \d+<\/a>\)<\/span>/, ''));
    return plain.join(sep) + `${sep}<span class="dq-catalog" data-role="dq-catalog">im ganzen Katalog: <a href="/securities?dq=stale_quote">${c('stale_quote', 'catalog')} ohne Kurs</a>, <a href="/securities?dq=missing_logo">${c('missing_logo', 'catalog')} ohne Logo</a></span>`;
  }
  return clauses.join(sep);
};
const dqWith = (actions) => dqToday.replace(/(<div class="data-note__actions">)[\s\S]*?(<\/div>\s*<\/div>\s*<button)/, `$1${actions}$2`);
const kpiHeld = kpiToday.replace('href="/securities?dq=stale_quote"', 'href="/securities?dq=stale_quote&amp;holding=held"').replace(/<span>\d+ veraltet im Katalog<\/span>/, `<span class="mock-new">${c('stale_quote', 'held')} gehaltene veraltet</span>`);
const kpiQuiet = kpiToday.replace('href="/securities?dq=stale_quote"', 'href="/securities?dq=stale_quote&amp;holding=held"').replace(/<small class="kpi-strip__sub[\s\S]*?<\/small>/, '');
const kpiWrap = (cell) => `<div class="kpi-strip" style="max-width: 260px; margin: 0 0 16px;">${cell}</div>`;
const B4 = {};
B4.today = sized(writeFrame('04a-dq-heute', `<div class="mock-pad">${kpiWrap(kpiToday)}${dqToday}</div>`, { css: DQ_CSS, width: 1000 }), 'heute, 1200 px (der Bereich)');
B4.a = sized(writeFrame('04b-dq-a', `<div class="mock-pad">${kpiWrap(kpiHeld)}${dqWith(`<span class="mock-new" style="display: inline;">${heldLine('A')}</span>`)}</div>`, { css: DQ_CSS, width: 1000 }), 'A — der Katalog in Klammern, je Menge');
B4.b = sized(writeFrame('04c-dq-b', `<div class="mock-pad">${kpiWrap(kpiHeld)}${dqWith(`<span class="mock-new" style="display: inline;">${heldLine('B')}</span>`)}</div>`, { css: DQ_CSS, width: 1000 }), 'B — der Katalog als letzte Klausel');
B4.phoneToday = sized(writeFrame('04d-dq-heute-390', `<div class="mock-pad">${kpiWrap(kpiToday)}${dqToday}</div>`, { css: DQ_CSS, width: 390 }), 'heute, 390 px');
B4.phoneA = sized(writeFrame('04e-dq-a-390', `<div class="mock-pad">${kpiWrap(kpiHeld)}${dqWith(`<span class="mock-new" style="display: inline;">${heldLine('A')}</span>`)}</div>`, { css: DQ_CSS, width: 390 }), 'A, 390 px');
const chips = JSON.parse(read('bars-b.json'))['securities-chips'].before;
B4.zero = sized(writeFrame('04f-dq-null', `<div class="mock-pad">${kpiWrap(kpiQuiet)}<p class="mock-gone">Kein Abschnitt „Datenqualität“: über die gehaltenen Wertpapiere ist jede Menge 0. (Hinweis des Boards, nicht der App.)</p></div>`, { css: DQ_CSS, width: 1000 }), 'gehalten überall 0, im Katalog nicht');
B4.where = sized(writeFrame('04g-dq-wo-katalog', `<div class="mock-pad">${chips.replace('id="sec-chip-stale_quote" class="filter-chip "', 'id="sec-chip-stale_quote" class="filter-chip is-active mock-new"').replace(/(id="sec-chip-stale_quote"[^>]*aria-pressed=)"false"/, '$1"true"')}</div>`, { width: 1000 }), 'wo der Katalog dann steht: Wertpapiere');
board('04-dq-held-first.html', 'Sprint 29 — Board 04: die Übersicht zählt Datenqualität zuerst über gehaltene Wertpapiere (#1417)', 1040,
  `<div class="mock-pickbar"><p><strong>Was entschieden ist (deine Antwort vom 2026-11-07, OQ-4 der Triage; kehrt J1.2 aus Sprint 19 D-3 um):</strong> jede Zahl der Datenqualität auf der Übersicht zählt zuerst die gehaltenen Wertpapiere, und ihr Link öffnet die Liste mit dem Filter „Im Bestand“. Die Zahl über den ganzen Katalog steht daneben als zweite Zahl, mit eigenem Link. Ist die gehaltene Zahl jeder Menge 0, zeigt die Übersicht keinen Hinweis. Die Mengen selbst und die Wertpapierliste bleiben, wie sie sind.</p><p><strong>Was dieses Board vorschlägt (per Kommentar umkehrbar):</strong> A — die Katalogzahl in Klammern hinter ihrer Klausel, „(im Katalog 26)“, nur wo sie von der gehaltenen abweicht; die Wirkung auf die Summe oben verliert ihr „gehalten“, weil die Zahl jetzt gehaltene zählt. Die Kurs-Zelle der Kennzahlenleiste zählt ebenso die gehaltenen („19 gehaltene veraltet“) und verlinkt die gehaltene Liste; eine zweite Zahl hat dort keinen Platz, weil die Zelle selbst ein Link ist. Die drei Prüfungen des Hauptbuchs zählen Buchungen, nicht Wertpapiere, und bleiben unverändert. Zahlen: die des Seeds (gehalten und Katalog aus der Liste gelesen).</p></div>`,
  [
    { title: '① Heute', note: 'Die Zeile, wie gebaut (Review-Instanz, synthetischer Seed): „26 Wertpapiere im Katalog ohne Kurs seit 7 Tagen“, der Link ohne Bestandsfilter; die Kurs-Zelle sagt „26 veraltet im Katalog“. Ein verkauftes, nicht ausgemustertes Wertpapier hält den Hinweis für immer offen.', frames: [B4.today] },
    { title: '② A — gehalten zuerst, der Katalog in Klammern', note: 'Jede Klausel nennt die gehaltenen und verlinkt <code>/securities?dq=…&amp;holding=held</code> — der Parameter der Liste heißt <code>holding</code>, nicht <code>holding_status</code> wie in der API. Wo beide Zahlen gleich sind (zwei Skalen, unplausibel), steht keine Klammer. Die Schwere folgt den gehaltenen Zahlen.', frames: [B4.a], recommended: true },
    { title: '③ B — der Katalog als eine letzte Klausel', note: 'Die Klauseln bleiben kurz; die Katalogzahlen, die abweichen, stehen gesammelt am Ende. Liest sich ruhiger, trennt aber jede Zahl von ihrer Menge, und die Zeile wird bei mehreren Mengen schwer zu lesen.', frames: [B4.b] },
    { title: '④ Bei 390 px', note: 'Die Zeile bricht um wie heute; die Klammer bleibt an ihrer Klausel.', frames: [B4.phoneToday, B4.phoneA], recommended: true },
    { title: '⑤ Gehalten überall 0, im Katalog nicht', note: 'Kein Abschnitt, keine Zeile, die Kurs-Zelle ohne Unterzeile. Die Katalogzahl bleibt erreichbar: auf Wertpapiere über die Chips der Datenqualität (Kurs veraltet, Kein Kurs, Kein Wechselkurs, Währung abweichend, Ohne Anlageklasse) oder <code>?dq=missing_logo</code>, <code>two_scales</code>, <code>implausible_quote</code>, und für den Agenten über <code>GET /api/v1/securities?data_quality=…</code> und securities.list. Nur die Prüfungen des Hauptbuchs halten den Abschnitt dann noch offen.', frames: [B4.zero, B4.where] },
  ]);

// ===========================================================================
// Board 05 — translucent bands (I33)

const roots = TREE.map((t) => band(t.name, t.color, t.secs, { drill: true }));
const cashBand = band('Cash', '#0ea5e9', [CASH]);
const unclBand = band('Nicht zugeordnet', '#9ca3af', UNCLASSIFIED, { drill: true });
const BANDS = [...roots, cashBand, unclBand].sort((a, b) => b.end - a.end);
const opacityCss = (base) => {
  if (base === 1) return '.mock-hover { opacity: 0.85; }';
  const neg = Math.round(base * 0.75 * 100) / 100;
  return `/* I33 at ${base}: the base, the part below zero at 0.75 of it (fill-opacity replaces, it does not multiply), the hover's opacity multiplies by itself. */
.stack-band { fill-opacity: ${base}; }
.stack-band--negative { fill-opacity: ${neg}; }
.stack-swatch { opacity: ${base}; }
.mock-hover { opacity: 0.85; }`;
};
const stackFrame = (name, base, { privacy = false, tag, hover = 'Anleihen' } = {}) => {
  const start = BANDS.reduce((a, b) => a + b.values[0], 0);
  const svg = privacy ? stackSvg(BANDS, { hover, scale: 100 / start, axis: (t) => nf0.format(Math.round(t)) + ' %' }) : stackSvg(BANDS, { hover });
  const privacyLine = privacy ? '<p class="hint" style="margin: 0 0 8px;"><strong>Privatsphäre-Modus an</strong> — die Achse in Prozent des Gesamtwerts am ersten Tag</p>' : '';
  const body = `<div class="mock-pad">${privacyLine}${modeSeg(privacy ? 'Wert (%)' : 'Wert (EUR)')}${stackBar}<figure class="perf-figure stack-figure" data-scale="${privacy ? 'percent' : 'value'}"><div class="stack-figure__body"><div class="stack-figure__chart" data-axis-inside="" style="--chart-upx: 1.5;">${svg}</div>${legend(BANDS, { privacy })}</div></figure><div class="hint stack-basis" style="display: flex; gap: 6px; align-items: center; flex-wrap: wrap;"><span>Marktwert je Kategorie von „Strategie“ · ${dmy(DATES[0])} – ${dmy(DATES[N - 1])} · berechnet ${dmy(DATES[N - 1])} 14:14 UTC</span>${tip('Marktwert je Kategorie am Tagesende in EUR.')}</div></div>`;
  return sized(writeFrame(name, body, { width: 1000, css: opacityCss(base) }), tag);
};
const B5 = {};
B5.today = stackFrame('05a-baender-heute', 1, { tag: 'heute — deckend (1)' });
B5.c80 = stackFrame('05b-baender-080', 0.8, { tag: '0,8 — der Teil unter null 0,6' });
B5.c65 = stackFrame('05c-baender-065', 0.65, { tag: '0,65 — der Teil unter null 0,49' });
B5.priv = stackFrame('05d-baender-080-privat', 0.8, { privacy: true, tag: '0,8 im Privatsphäre-Modus' });
board('05-translucent-bands.html', 'Sprint 29 — Board 05: durchscheinende Bänder im gestapelten Chart (Idee I33)', 1040,
  `<div class="mock-pickbar"><p><strong>Was die Idee festlegt (I33, als „no-brainer“ eingetragen):</strong> die Bänder der Kategorien leicht durchscheinend, ein <code>fill-opacity</code> auf <code>.stack-band</code> um 0,8, die Farbfelder der Legende in derselben Deckkraft, damit sie weiter passen. Zwei Stile nutzen schon Transparenz und müssen unterscheidbar bleiben: der Teil unter null (<code>fill-opacity: 0.75</code>, #1426) und das Überfahren eines klickbaren Bands (<code>opacity: 0.85</code>); beide wandern mit der Basis nach unten.</p><p><strong>Was dieses Board vorschlägt (per Kommentar umkehrbar):</strong> 0,8. Die Gitterlinien scheinen durch, jede Farbe bleibt in beiden Themen erkennbar, auch Gelb auf Weiß. Der Teil unter null bekommt 0,6 (0,8 × 0,75): <code>fill-opacity</code> auf demselben Pfad ersetzt die Basis, statt sie zu multiplizieren — ließe man die 0,75 stehen, wäre der negative Teil fast so kräftig wie der positive. Das Überfahren bleibt <code>opacity: 0.85</code>; es multipliziert sich mit der Basis (0,68) und wandert so von selbst. In jedem Frame ist „Anleihen“ überfahren gezeichnet, Cash taucht im Herbst unter null.</p></div>`,
  [
    { title: '① Heute', note: 'Deckend; nur der Teil unter null ist heller (0,75).', frames: [B5.today] },
    { title: '② 0,8', note: 'Leicht durchscheinend: die Gitterlinie scheint durch das Band „Aktien“, die Farben bleiben satt; der Teil unter null (0,6) bleibt deutlich heller als sein Band, das überfahrene Band (0,68) liegt dazwischen und ist durch seine ganze Fläche von beiden zu unterscheiden. Die Farbfelder der Legende in 0,8.', frames: [B5.c80], recommended: true },
    { title: '③ 0,65', note: 'Stärker: Gelb und Grün verblassen auf Weiß, im dunklen Thema werden alle Bänder trüb; der Teil unter null (0,49) und das überfahrene Band (0,55) liegen nah beieinander.', frames: [B5.c65] },
    { title: '④ 0,8 im Privatsphäre-Modus', note: 'Die Form wie ohne Modus, die Achse in Prozent des ersten Tages, die Legende ohne Wert; die Deckkraft ändert nichts daran.', frames: [B5.priv], recommended: true },
  ]);

// ===========================================================================
// Board 06 — labelled controls start on one edge (#1435)

const BARS = JSON.parse(read('bars-b.json'));
// The account chips carry the seed's account names; the board names them
// generically.
let acct = 0;
const genericAccounts = (s) => s.replace(/(id="tx-chip-account-\d+"[^>]*>)\s*[^<]+?\s*(<\/button>)/g, (_, a, b) => `${a} Verrechnungskonto ${++acct} ${b}`);
const CONTROL_BAR_CSS = `
/* The shared component (proposal): a bar of labelled controls. One row of
   groups while they fit (.control-bar--line); A, a label column as wide as
   the longest label, every control from one edge; B, every label above its
   control. A chip family is one control and wraps inside its column. */
.control-bar { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 12px; align-items: baseline; margin: 0 0 12px; font-size: 12.5px; color: var(--color-text-muted); }
.control-bar__group { display: contents; }
.control-bar__label { font-size: 12px; font-weight: 600; color: var(--color-text-muted); white-space: nowrap; }
.control-bar__control { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; min-width: 0; color: var(--color-text); }
.control-bar__control .filter-chips__family { display: none; }
.control-bar--b { grid-template-columns: minmax(0, 1fr); gap: 4px; }
.control-bar--b .control-bar__control { margin-bottom: 8px; }
.control-bar .segmented-control { width: auto; }
.control-bar__control input[type=text] { width: calc(12ch + 20px); flex: none; }
`;
const group = (label, controls) => `<div class="control-bar__group"><span class="control-bar__label">${label}</span><div class="control-bar__control">${controls}</div></div>`;
const buttonsAfter = (html, family) => {
  const m = html.match(new RegExp(`<span class="filter-chips__family">${family}<\\/span>([\\s\\S]*?)(?=<\\/span>|<span class="filter-chips__family">|<span id="changed-since|<button type="button" id="more-filters)`));
  return m ? m[1] : '';
};
const pad = (w, html) => `<div class="mock-pad" style="width: ${w}px; box-sizing: border-box;">${html}</div>`;
const B6 = {};
// ① the journal at 390: the chips and the form, one bar after.
const jc = BARS['journal-chips'].before, jf = BARS['journal-filters'].before;
const jKind = jf.match(/<select[\s\S]*?<\/select>/)[0];
const jSince = jf.match(/<input type="text"[^>]*>/)[0];
const jScen = jf.match(/<label class="journal-filters__scenarios">[\s\S]*?<\/label>/)[0];
const journalAfter = `<div class="workspace-page"><section class="workspace-section"><div class="control-bar mock-new" role="group" aria-label="Journal filtern">${group('Akteur', buttonsAfter(jc, 'Akteur'))}${group('Vorgang', buttonsAfter(jc, 'Vorgang'))}${group('<label for="journal-kind">Art</label>', jKind)}${group('<label for="journal-since">Seit</label>', jSince)}${group('', jScen)}</div></section></div>`;
const jForm = jf.match(/<form[\s\S]*?<\/form>/)[0];
const journalBefore = jc.replace(/<\/section><\/div>$/, `${jForm}</section></div>`);
B6.journalBefore = sized(writeFrame('06a-journal-heute', pad(390, journalBefore), { width: 390 }), 'Journal heute, 390 px');
B6.journalAfter = sized(writeFrame('06b-journal-neu', pad(390, journalAfter), { width: 390, css: CONTROL_BAR_CSS }), 'Journal neu (A), 390 px');
// ② the sale's comparison in its rate mode at 390: B, the floor.
const hs = BARS['hindsight-rate'].before;
const hsSeg = hs.match(/<nav class="segmented-control"[\s\S]*?<\/nav>/)[0];
const hsRate = hs.match(/<input type="text"[\s\S]*?<\/button>/)[0];
const hsAfter = (mod) => `<div class="workspace-page"><section class="hs-section workspace-section"><div class="hs-controls control-bar ${mod} mock-new" data-role="hindsight-compare">${group('Vergleich', hsSeg)}${group('<label for="sale-hindsight-rate">Fester Zins % p. a.</label>', hsRate)}</div></section></div>`;
B6.hsBefore = sized(writeFrame('06c-vergleich-heute', pad(390, hs), { width: 390 }), 'Vergleich heute, 390 px');
B6.hsAfter = sized(writeFrame('06d-vergleich-neu', pad(390, hsAfter('control-bar--b')), { width: 390, css: CONTROL_BAR_CSS + '.hs-controls.control-bar { display: grid; }' }), 'Vergleich neu (B), 390 px');
// ③ Wertpapiere at 1200: every family named, A.
const sc = BARS['securities-chips'].before;
const chipIds = (ids) => ids.map((id) => (sc.match(new RegExp(`<button type="button" id="sec-chip-${id}"[\\s\\S]*?<\\/button>`)) || [''])[0]).join('');
const since = (sc.match(/<button type="button" id="changed-since-chips-today"[\s\S]*?id="changed-since-chips-30d"[\s\S]*?<\/button>/) || [''])[0];
const more = (sc.match(/<button type="button" id="more-filters-toggle"[\s\S]*?<\/button>/) || [''])[0];
const secAfter = `<section class="workspace-panel"><div id="securities-filter-chips" class="control-bar mock-new" role="group" aria-label="Liste filtern">${group('Bestand', chipIds(['held', 'not_held']))}${group('Datenqualität', chipIds(['unclassified', 'stale_quote', 'missing_quote', 'missing_fx', 'currency_mismatch']))}${group('Währung', buttonsAfter(sc, 'Währung'))}${group('Anlageklasse', buttonsAfter(sc, 'Anlageklasse'))}${group('Geändert seit', since)}${group('', more)}</div></section>`;
B6.secBefore = sized(writeFrame('06e-wertpapiere-heute', pad(1020, sc), { width: 1020 }), 'Wertpapiere heute, 1200 px (980 px Leiste)');
B6.secAfter = sized(writeFrame('06f-wertpapiere-neu', pad(1020, secAfter), { width: 1020, css: CONTROL_BAR_CSS }), 'Wertpapiere neu (A)');
// ④ Transaktionen at 1200: A.
const tc = genericAccounts(BARS['transaction-chips'].before);
acct = 0;
const tcAfterSrc = genericAccounts(BARS['transaction-chips'].before);
const tcSince = (tcAfterSrc.match(/<button type="button" id="[a-z-]*-today"[\s\S]*?-30d"[\s\S]*?<\/button>/) || [''])[0];
const tcAfter = `<div class="workspace-page"><div class="transactions-columns "><section class="workspace-section"><div id="transaction-chips" class="control-bar mock-new" role="group" aria-label="Historie filtern">${group('Konto', buttonsAfter(tcAfterSrc, 'Konto'))}${group('Typ', buttonsAfter(tcAfterSrc, 'Typ'))}${group('Geändert seit', tcSince)}</div></section></div></div>`;
B6.txBefore = sized(writeFrame('06g-transaktionen-heute', pad(964, tc), { width: 964 }), 'Transaktionen heute, 1200 px (924 px Leiste)');
B6.txAfter = sized(writeFrame('06h-transaktionen-neu', pad(964, tcAfter), { width: 964, css: CONTROL_BAR_CSS }), 'Transaktionen neu (A)');

// ⑤ to ⑩ — open prose (#1435 (4), Sprint 29 L5; inventory §3): the six
// paragraphs past one sentence of at most 25 words, today and with their
// method sentences behind the line's ⓘ (DESIGN.md, amendment 2026-11-02, I1).
// The text is the shipped German; each "after" frame draws its ⓘ opened in
// the flow under its line, so the frame shows where every sentence went.
const PROSE_W = 520;
const PROSE_CSS = `
.mock-open .metric-tooltip--section { position: static; display: block; margin: 8px 0 0; }
.mock-open .metric-tooltip--section summary { display: none; }
.mock-open .metric-tooltip--section p { position: static; display: block; width: auto; max-width: none; translate: none; }
.mock-open .mock-i { display: inline-flex; align-items: center; justify-content: center; width: 1.25rem; height: 1.25rem; margin-left: var(--space-1); border-radius: 50%; border: 1px solid var(--color-border); background: var(--color-bg-muted); color: var(--color-text-muted); font-size: 0.75rem; vertical-align: middle; }
`;
// The ⓘ as the app draws it (AppShell.section_info): closed, or opened
// below its line (the board's way of showing the panel's lines).
const sectionInfo = (lines, open) => open
  ? `<span class="mock-i mock-new" aria-hidden="true">ⓘ</span><details class="metric-tooltip metric-tooltip--inline metric-tooltip--section" open><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">${lines.join('<br>')}</p></details>`
  : `<details class="metric-tooltip metric-tooltip--inline metric-tooltip--section"><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">${lines.join('<br>')}</p></details>`;
const proseFrame = (name, html, tag, open) =>
  sized(writeFrame(name, `<div class="mock-pad${open ? ' mock-open' : ''}" style="width: ${PROSE_W}px; box-sizing: border-box;">${html}</div>`, { width: PROSE_W, css: PROSE_CSS }), tag);
const crop = (text) => `<p class="mock-crop">${text}</p>`;
// ⑤ Vermögen › Bestände, the positions' basis line.
const POS_ROWS = 'Eine Zeile je Depot und Wertpapier, bewertet zum zuletzt gespeicherten Kurs oder, ohne Kurs, zum letzten eigenen Handelspreis.';
const POS_SUM = 'Marktwert in EUR, wie ihn die Summe zählt.';
const posSection = (basis) => `<section class="workspace-section"><header class="section-head"><h2>Positionen</h2></header>${basis}${crop('Die Tabelle der Positionen, unverändert.')}</section>`;
B6.posBefore = proseFrame('06i-positionen-heute', posSection(`<p class="summary-basis" data-role="positions-basis">${POS_ROWS} ${POS_SUM}</p>`), 'Heute: 2 Sätze, 26 Wörter');
B6.posAfter = proseFrame('06j-positionen-neu', posSection(`<div class="summary-basis mock-new" data-role="positions-basis">${POS_ROWS}${sectionInfo([POS_SUM], true)}</div>`), 'Neu: 1 Satz, 18 Wörter; ⓘ geöffnet', true);
// ⑥ Wertpapier › Nachrichten, the stories' basis line.
const STORIES = 'Die Meldungen zu diesem Wertpapier, die die Nachrichtenschicht hält, neueste zuerst, so wie der Agent sie liest';
const STORIES_INFO = [
  'Eine Einordnung ist die Lesart eines Modells außerhalb der App, markiert als „maschinell“; sie verschiebt und schreibt nichts.',
  '„Ins Research-Log“ öffnet das Eintragsformular, vorausgefüllt aus der Meldung, wie es notes.append des Agenten mit der Meldung füllt: die Überschrift aus ihrem Titel, Ereignisart und Tonalität aus ihrer Einordnung, Datum und Quelle aus ihrer besten Quelle. Erst das Speichern schreibt den Eintrag.',
  'Nur ein Eintrag mit Überschrift erscheint im Diagramm, eine Meldung nie.'
];
const storiesPanel = (hint) => `<section class="detail-tab-panel detail-tab-panel--news">${hint}${crop('Die Meldungen, unverändert.')}</section>`;
B6.storiesBefore = proseFrame('06k-meldungen-heute', storiesPanel(`<div class="detail-tab-hint" data-role="stories-basis">${STORIES}. Zeiten in UTC. ${sectionInfo(STORIES_INFO, false)}</div>`), 'Heute: 2 Sätze, 20 Wörter');
B6.storiesAfter = proseFrame('06l-meldungen-neu', storiesPanel(`<div class="detail-tab-hint mock-new" data-role="stories-basis">${STORIES} · Zeiten in UTC${sectionInfo(STORIES_INFO, true)}</div>`), 'Neu: 1 Satz, 20 Wörter; ⓘ wie heute', true);
// ⑦ Wertpapier › Diagramm, the price basis under the chart.
const chartPanel = (hint) => `<section class="detail-tab-panel">${crop('Das Diagramm und seine Legende, unverändert.')}${hint}${crop('Die Kennzahlen unter dem Diagramm, unverändert.')}</section>`;
B6.chartBefore = proseFrame('06m-diagramm-heute', chartPanel('<p class="detail-tab-hint" data-role="chart-basis">Kursbasis: splitbereinigt. Gespeicherte Kurse werden nie verändert (siehe Tab Kurse).</p>'), 'Heute: 2 Sätze, 11 Wörter');
B6.chartAfter = proseFrame('06n-diagramm-neu', chartPanel(`<div class="detail-tab-hint mock-new" data-role="chart-basis">Kursbasis: splitbereinigt.${sectionInfo(['Gespeicherte Kurse werden nie verändert (siehe Tab Kurse).'], true)}</div>`), 'Neu: 1 Satz, 2 Wörter; ⓘ geöffnet, wie im Tab Kurse', true);
// ⑧ Wertpapier › Prognosen, the tab's line.
const PRED = 'Festgehaltene Prognosen zu diesem Wertpapier, die neueste zuerst.';
const PRED_INFO = [
  'Eine Prognose bleibt, wie sie abgegeben wurde: Sie wird nie geändert, zurückgezogen oder gelöscht. Eine korrigierte Prognose ist eine neue, und beide zählen.',
  'Ausgewertet wird beim Lesen aus gespeicherten Schlusskursen, beide Seiten in EUR zum gespeicherten Wechselkurs ihres Tages; ein Ergebnis wird nie gespeichert.',
  '… und fünf weitere Zeilen, unverändert.'
];
const predPanel = (hint) => `<section class="detail-tab-panel detail-tab-panel--predictions">${hint}${crop('Die Prognosen, unverändert.')}</section>`;
B6.predBefore = proseFrame('06o-prognosen-heute', predPanel(`<div class="detail-tab-hint" data-role="predictions-basis">${PRED} Keine wird geändert oder gelöscht. ${sectionInfo(PRED_INFO, false)}</div>`), 'Heute: 2 Sätze, 13 Wörter');
B6.predAfter = proseFrame('06p-prognosen-neu', predPanel(`<div class="detail-tab-hint mock-new" data-role="predictions-basis">${PRED}${sectionInfo(PRED_INFO, true)}</div>`), 'Neu: 1 Satz, 8 Wörter; die Regel steht in der ersten Zeile des ⓘ', true);
// ⑨ Transaktionen, the summary's basis line (synthetic figures).
const txSummary = (basis) => `<div class="transaction-summary" role="status"><span class="summary-total"><strong>128</strong> Transaktionen</span><span class="summary-type">Kauf: <strong>40</strong> · 52.300,00 EUR</span><span class="summary-type">Verkauf: <strong>12</strong> · 18.940,00 EUR</span><span class="summary-type">Dividende: <strong>31</strong> · 1.204,50 EUR</span>${basis}</div>`;
B6.txSumBefore = proseFrame('06q-summe-heute', txSummary('<p class="summary-basis" data-role="summary-basis">Anzahl und bewegtes Geld je Art der Transaktionen, die dieser Filter auswählt — je Währung in der Richtung ihrer Art summiert und nicht umgerechnet; ein Verkauf, dessen Gebühren und Steuern seinen Erlös übersteigen, mindert die Summe der Verkäufe.</p>'), 'Heute: 1 Satz, 37 Wörter');
B6.txSumAfter = proseFrame('06r-summe-neu', txSummary(`<div class="summary-basis mock-new" data-role="summary-basis">Anzahl und bewegtes Geld je Art der Transaktionen, die dieser Filter auswählt — je Währung summiert und nicht umgerechnet.${sectionInfo(['Jede Art wird in ihrer eigenen Richtung summiert; ein Verkauf, dessen Gebühren und Steuern seinen Erlös übersteigen, mindert die Summe der Verkäufe.'], true)}</div>`), 'Neu: 1 Satz, 18 Wörter; ⓘ geöffnet', true);
// ⑩ Wertpapier › Übersicht, the bond strip's basis line.
const BOND_INFO = [
  'Ein Stück im Bestand ist ein Hundertstel des Nominals, darum ist der Kurs zugleich der Preis je Stück.',
  'Laufende Rendite = Kupon ÷ Kurs.',
  'Restlaufzeit in Kalendertagen, das Jahr zu 365 Tagen.',
  'Rendite bis Fälligkeit linear angenähert: (Kupon + (100 − Kurs) ÷ Restlaufzeit in Jahren) ÷ Kurs, ohne Zinseszins.',
  'Berichtet, nicht bewertet.'
];
const bondStrip = (hint) => `<section class="bond-strip"><div class="bond-strip__head"><h3>Anleihe</h3></div>${crop('Fälligkeit, Kupon, Nominal, Restlaufzeit, laufende Rendite und Rendite bis Fälligkeit, unverändert.')}${hint}</section>`;
B6.bondBefore = proseFrame('06s-anleihe-heute', bondStrip('<p class="detail-tab-hint" data-role="bond-basis">Kupon und Kurs in Prozent vom Nennwert: Ein Stück im Bestand ist ein Hundertstel des Nominals, darum ist der Kurs zugleich der Preis je Stück. Laufende Rendite = Kupon ÷ Kurs. Restlaufzeit in Kalendertagen ab heute, das Jahr zu 365 Tagen. Rendite bis Fälligkeit linear angenähert: (Kupon + (100 − Kurs) ÷ Restlaufzeit in Jahren) ÷ Kurs, ohne Zinseszins. Ohne Stückzinsen, Gebühren und Steuern. Berichtet, nicht bewertet.</p>'), 'Heute: 6 Sätze, 65 Wörter');
B6.bondAfter = proseFrame('06t-anleihe-neu', bondStrip(`<div class="detail-tab-hint mock-new" data-role="bond-basis">Kupon und Kurs in Prozent vom Nennwert, Restlaufzeit ab heute, ohne Stückzinsen, Gebühren und Steuern.${sectionInfo(BOND_INFO, true)}</div>`), 'Neu: 1 Satz, 15 Wörter; ⓘ geöffnet', true);
const PROSE_LEAD = '<p><strong>Was entschieden ist (DESIGN.md, Amendment 2026-11-02, I1; Plan Sprint 29, L5):</strong> die Methodensätze eines Abschnitts (wie eine Zahl entsteht, was ein Begriff bedeutet, was ein Bedienelement tut) stehen in seinem ⓘ; die Basis (Ansicht, Zeitraum, Währung, Stand, die Menge der Zeilen) bleibt sichtbar. Die Schwelle aus dem Inventar (§3): ein freier Absatz ist höchstens ein Satz mit höchstens 25 Wörtern. Der Rundgang (L3) prüft das auf jeder Seite, deutsch und englisch; Ausnahmen nur mit Grund: Leerzustände (der Zustand und wo man handelt), Fehlermeldungen (der Fehler und seine Abhilfe), eine Namensliste, die Beschriftung einer Zahl.</p><p><strong>Was dieses Board zeigt:</strong> die sechs Absätze über der Schwelle, heute und neu. Der Text bleibt; nur sein Platz ändert sich. Die Anleihe (⑩) schlug das Inventar als Ausnahme bis zu einer eigenen Story vor; der Plan holt sie in L5. Gestrichelt: neu. Jedes ⓘ ist im Frame unter seiner Zeile geöffnet gezeichnet; in der App öffnet es als Popover.</p>';
// ⑪ to ⑬ — PR 2's closing act (the plan's D-8 item 3): two folds Lane L
// set without a frame, and where a section's ⓘ opens. The bars are the
// component's own markup (`ControlBar.bar/1`), drawn by app.css's container
// queries at the bar widths named; each frame pins the values it compares
// in its own style, so a later app.css does not redraw the "before".
const cbar = (cls, fold, floor, groups, extra = '') => `<div class="control-bar control-bar--fold-${fold} control-bar--floor-${floor} ${cls}${extra}"><div class="control-bar__controls">${groups}</div></div>`;
const cgroup = (label, id, control, forId) => `<span class="control-bar__group">${forId ? `<label class="control-bar__label" for="${forId}" id="${id}">${label}</label>` : `<span class="control-bar__label" id="${id}">${label}</span>`}${control}</span>`;
const cseg = (id, options, active) => `<nav class="segmented-control" aria-labelledby="${id}">${options.map((o) => `<a class="segmented-control__option${o === active ? ' is-active' : ''}" href="#">${o}</a>`).join('')}</nav>`;
// ⑪ „Nach dem Verkauf“, its comparison with a benchmark: the line needs
// about 790 px (the walk measured it wrapping up to a 793 px bar).
const hsBar = (fold, extra = '') => cbar('hs-compare-bar', fold, 560,
  cgroup('Vergleich', 'hs-c', cseg('hs-c', ['Ohne', 'Fester Zins', 'Wertpapier', 'Anschlusskauf'], 'Wertpapier')) +
  `<form class="control-bar__group control-bar__group--bare"><span class="hs-compare-bar__field"><label for="hs-b" class="visually-hidden">Benchmark</label><select id="hs-b"><optgroup label="Benchmarks"><option>Welt-Aktien ETF thesaurierend · Benchmark · zuletzt 112,40 EUR</option></optgroup></select></span></form>`, extra);
const HS_FOLD_W = 870; // a 790 px bar in its section
// The fold 840 as app.css drew it until ⑮ moved the bar to 860: pinned, so
// the frame keeps showing what it compared.
const FOLD = (w) => `@container control-bar (max-width: ${w}px) { .control-bar--fold-${w} > .control-bar__controls { --control-bar-display: grid; --control-bar-columns: max-content minmax(0, 1fr); --control-bar-gap: var(--space-2) 10px; --control-bar-width: 100%; --control-bar-group: contents; --control-bar-label-margin: 0; --control-bar-select-width: auto; } }`;
B6.hsFoldBefore = sized(writeFrame('06u-vergleich-falz-760', pad(HS_FOLD_W, `<section class="hs-section workspace-section">${hsBar(760)}</section>`), { width: HS_FOLD_W }), 'Falz 760: eine Zeile, die umbricht (790 px Leiste)');
B6.hsFoldAfter = sized(writeFrame('06v-vergleich-falz-840', pad(HS_FOLD_W, `<section class="hs-section workspace-section">${hsBar(840, ' mock-new')}</section>`), { width: HS_FOLD_W, css: FOLD(840) }), 'Falz 840: Labelspalte (A)');
// ⑫ Vermögen › Risiko, the Crashes bar: the window's select at its cap,
// the line about 880 px; at 1200 px the bar is 924 px.
const crashOption = 'Synthetic dip · 04.10.2026–24.10.2026 · manuell';
// `cap` null: the select as app.css draws it.
const crashBar = (fold, cap, extra = '') => cbar('crash-bar', fold, 330,
  `<form class="control-bar__group"><label class="control-bar__label" for="cw">Fenster</label><select id="cw"${cap ? ` style="max-width: ${cap}"` : ''}><option>${crashOption}</option></select></form>` +
  cgroup('Liste', 'cl', cseg('cl', ['Verlierer', 'Gewinner', 'Erholer'], 'Verlierer')) +
  cgroup('Wertpapiere', 'cu', cseg('cu', ['Im Depot', 'Ganzer Katalog'], 'Im Depot')), extra);
const CR_FOLD_W = 954; // an 870 px bar in its section
const CR_LINE_W = 1008; // the 924 px bar at a 1200 px window
// The window's group as it stood before ⑮ let it take the room the line
// leaves: pinned in ⑫'s frames (and ⑮'s "today"), so they keep showing
// what they compared.
const CRASH_GROUP_FIXED = '.crash-bar .control-bar__group:has(> select) { flex: 0 1 auto; min-width: auto; max-width: none; } .crash-bar select { min-width: auto; }';
const crashFrame = (name, w, html, tag, css = CRASH_GROUP_FIXED) => sized(writeFrame(name, pad(w, `<section class="crash-section workspace-section">${html}</section>`), { width: w, css }), tag);
B6.crashFoldBefore = crashFrame('06w-crashes-falz-760', CR_FOLD_W, crashBar(760, '19.5rem'), 'Falz 760: eine Zeile, die umbricht (870 px Leiste)');
B6.crashFoldAfter = crashFrame('06x-crashes-falz-900', CR_FOLD_W, crashBar(900, '19.5rem', ' mock-new'), 'Falz 900: Labelspalte (A)');
B6.crashCapBefore = crashFrame('06y-crashes-1200-19-5rem', CR_LINE_W, crashBar(900, '19.5rem'), '1200 px heute: Auswahl bis 19,5rem, „… · manue“');
B6.crashCapAfter = crashFrame('06z-crashes-1200-20-5rem', CR_LINE_W, crashBar(900, '20.5rem', ' mock-new'), '1200 px neu: bis 20,5rem, „… · manuell“');
// ⑬ a section's ⓘ on its basis line, opened: today above its line, over
// the sentence it belongs to; new under it (`data-place="below"`), above
// only where the window has no room below. `--tip-shift` is what the
// app's placement sets to keep the panel 1 rem inside a 390 px screen.
const INFO_W = 390;
const infoLine = (place) => `<section class="workspace-section"><header class="section-head"><h2>Positionen</h2></header><div class="summary-basis" data-role="positions-basis">${POS_ROWS}<details class="metric-tooltip metric-tooltip--inline metric-tooltip--section${place ? ' mock-new' : ''}" open${place ? ` data-place="${place}"` : ''} style="--tip-shift: -152px"><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">${POS_SUM}</p></details></div>${crop('Die Tabelle der Positionen, unverändert.')}</section>`;
B6.infoBefore = sized(writeFrame('06za-info-oben', pad(INFO_W, `<div style="height: 72px"></div>${infoLine(null)}`), { width: INFO_W }), 'Heute, 390 px: über der eigenen Zeile');
B6.infoAfter = sized(writeFrame('06zb-info-unten', pad(INFO_W, `<div style="height: 72px"></div>${infoLine('below')}<div style="height: 48px"></div>`), { width: INFO_W }), 'Neu: unter der Zeile');
// ⑭ Vermögen, the stacked chart's bar at a 332 px bar (a 364 px window),
// German: its label column and its level control need 334 px. A frame
// pins the floor it shows in its own style (the floor class names the
// width; the rule is drawn here as app.css draws its 330).
const STACK_W = 372; // a 332 px bar
const FLOOR_340 = `@container control-bar (max-width: 340px) { .control-bar--floor-340 > .control-bar__controls { --control-bar-display: grid; --control-bar-columns: minmax(0, 1fr); --control-bar-gap: var(--space-1); --control-bar-width: 100%; --control-bar-group: contents; --control-bar-label-margin: 0; --control-bar-select-width: auto; --control-bar-control-margin: 6px; } }`;
const stackBar14 = (floor, extra = '') => cbar('', 760, floor,
  cgroup('Ebene', 'sl', cseg('sl', ['Gesamt', 'Kategorien', 'Wertpapiere'], 'Kategorien')) +
  `<form class="control-bar__group"><label class="control-bar__label" for="sc">Klassifizierung</label><select id="sc"><option>Strategien</option></select></form>` +
  cgroup('Sortieren', 'ss', cseg('ss', ['Größe', 'Veränderung'], 'Größe')), extra);
B6.stackFloorBefore = sized(writeFrame('06zc-stapel-boden-330', pad(STACK_W, stackBar14(330)), { width: STACK_W, css: FLOOR_340 }), 'Boden 330: Labelspalte, 2 px über die Leiste');
B6.stackFloorAfter = sized(writeFrame('06zd-stapel-boden-340', pad(STACK_W, stackBar14(340, ' mock-new')), { width: STACK_W, css: FLOOR_340 }), 'Boden 340: Labels darüber (B)');
// ⑮ PR 2's closing act after CI: the app ships no web font, so a device
// without Inter draws it in its own sans; CI's runner drew it in DejaVu
// Sans, the widest of the common ones, where the folds and floors measured
// in Inter alone broke the rule. Each frame names its font and draws it
// (`--font-sans`); the "today" frames pin the rules they compare.
const DEJAVU = ':root { --font-sans: "DejaVu Sans"; }';
const crashBar15 = (extra = '') => crashBar(900, null, extra);
const CR_FONT_W = 989; // a 905 px bar, a 1181 px window: the walk found the break at 1177 to 1208 px
B6.crashFontBefore = crashFrame('06ze-crashes-ersatz-heute', CR_FONT_W, crashBar15(), 'DejaVu Sans, 905 px Leiste heute: die Zeile bricht um, zwei Kanten', DEJAVU + CRASH_GROUP_FIXED);
B6.crashFontAfter = crashFrame('06zf-crashes-ersatz-neu', CR_FONT_W, crashBar15(' mock-new'), 'DejaVu Sans, 905 px Leiste neu: die Auswahl nimmt den Rest der Zeile', DEJAVU);
B6.crashInterAfter = crashFrame('06zg-crashes-1200-inter-neu', CR_LINE_W, crashBar15(' mock-new'), 'Inter, 1200 px neu: unverändert, „… · manuell“', '');
const STACK_380_W = 388; // a 348 px bar, a 380 px window
const STACK_390_W = 398; // a 358 px bar, a 390 px window
const FLOOR = (w) => `@container control-bar (max-width: ${w}px) { .control-bar--floor-${w} > .control-bar__controls { --control-bar-display: grid; --control-bar-columns: minmax(0, 1fr); --control-bar-gap: var(--space-1); --control-bar-width: 100%; --control-bar-group: contents; --control-bar-label-margin: 0; --control-bar-select-width: auto; --control-bar-control-margin: 6px; } }`;
B6.stackFontBefore = sized(writeFrame('06zh-stapel-ersatz-boden-340', pad(STACK_380_W, stackBar14(340)), { width: STACK_380_W, css: DEJAVU + FLOOR(340) }), 'DejaVu Sans, 380 px heute: Boden 340, die Ebene 9 px über die Leiste');
B6.stackFontAfter = sized(writeFrame('06zi-stapel-390-boden-380', pad(STACK_390_W, stackBar14(380, ' mock-new')), { width: STACK_390_W }), 'Inter, 390 px neu: Boden 380, Labels darüber (B)');
const STACK_FOLD_W = 810; // a 770 px bar
const stackBarFold = (fold, extra = '') => stackBar14(330, extra).replace('control-bar--fold-760', `control-bar--fold-${fold}`);
B6.stackFoldBefore = sized(writeFrame('06zj-stapel-falz-760', pad(STACK_FOLD_W, stackBarFold(760)), { width: STACK_FOLD_W, css: DEJAVU }), 'DejaVu Sans, 770 px Leiste heute: Falz 760, eine Zeile, 17 px Luft');
B6.stackFoldAfter = sized(writeFrame('06zk-stapel-falz-780', pad(STACK_FOLD_W, stackBarFold(780, ' mock-new')), { width: STACK_FOLD_W, css: DEJAVU }), 'DejaVu Sans, 770 px Leiste neu: Falz 780, Labelspalte (A)');
const HS_860_W = 930; // an 850 px bar in its section
B6.hsFontBefore = sized(writeFrame('06zl-vergleich-falz-840-ersatz', pad(HS_860_W, `<section class="hs-section workspace-section">${hsBar(840)}</section>`), { width: HS_860_W, css: DEJAVU + FOLD(840) }), 'DejaVu Sans, 850 px Leiste heute: Falz 840, die Zeile bricht um, zwei Kanten');
B6.hsFontAfter = sized(writeFrame('06zm-vergleich-falz-860', pad(HS_860_W, `<section class="hs-section workspace-section">${hsBar(860, ' mock-new')}</section>`), { width: HS_860_W, css: DEJAVU }), 'DejaVu Sans, 850 px Leiste neu: Falz 860, Labelspalte (A)');
const CLOSING_LEAD = '<p><strong>Nachgetragen im Abschlussakt von PR 2 (Plan Sprint 29, D-8 Punkt 3):</strong> zwei Falze, die Lane L aus der Messung des Rundgangs gesetzt hat, ohne Frame, und wohin das ⓘ einer Basiszeile öffnet. Die Leisten sind das Markup der Komponente, gezeichnet von den Container-Abfragen in app.css bei der genannten Leistenbreite.</p>';
board('06-control-bar.html', 'Sprint 29 — Board 06: beschriftete Bedienelemente beginnen an einer Kante (#1435)', 1100,
  `<div class="mock-pickbar"><p><strong>Was entschieden ist (DESIGN.md, Amendment 2026-11-08, Board 07 ④ von Sprint 28, Wahl A; Amendment D-A5):</strong> eine Leiste beschrifteter Bedienelemente (ein Label neben einem Segmentschalter, einer Auswahl oder einer Chip-Familie) ist eine Komponente. Solange sie passt, eine Zeile; bricht sie um, eine Labelspalte so breit wie das längste Label und jedes Feld an derselben Kante (A); passt auch das nicht, jedes Label über seinem Feld (B). Die Leiste des gestapelten Charts ist der erste Nutzer und hält die Regel schon (390 px: alle drei Felder bei 100 px).</p><p><strong>Was dieses Board zeigt und vorschlägt:</strong> die Leisten, die die Regel heute brechen, gemessen an der Review-Instanz bei 390 und 1200 px (<code>capture-b-inventory.js</code>; das Inventar steht in <code>06-control-bar-inventory.md</code>), vorher wie ausgeliefert und nachher in der gemeinsamen Komponente. Vorgeschlagen: eine Chip-Familie ist ein Feld und bricht in ihrer Spalte um; jede Familie trägt ihr Label, auch „Bestand“ und „Datenqualität“, die heute nur das Filterblatt nennt; das Journal wird eine Leiste statt zwei. Gestrichelt: neu.</p></div>`,
  [
    { title: '① Journal bei 390 px', note: 'Heute: „Akteur“ und „Vorgang“ stehen vor ihren Chips, die umbrechenden Chips beginnen an der linken Kante; die ersten Felder liegen bei 58, 0, 70 und 0 px. Das Formular darunter: „Seit“ steht vor seinem Feld (29 px), die Auswahl der Art hat nur ein verstecktes Label. Neu (A): eine Leiste mit der Labelspalte Akteur, Vorgang, Art, Seit; jedes Feld bei derselben Kante, das Kontrollkästchen in der Feldspalte.', frames: [B6.journalBefore, B6.journalAfter], recommended: true },
    { title: '② „Nach dem Verkauf“, Vergleich „Fester Zins“, bei 390 px', note: 'Heute steht „Vergleich“ allein über dem Schalter (der Schalter ist auf dem Telefon volle Breite), das Zinsfeld aber hinter seinem Label (113 px): zwei Felder, zwei Kanten. Neu: B, der Boden der Regel, weil der volle Schalter neben einer Labelspalte nicht passt; beide Labels über ihrem Feld, alles an der linken Kante. Bei 1200 px bleibt die Leiste eine Zeile.', frames: [B6.hsBefore, B6.hsAfter], recommended: true },
    { title: '③ Wertpapiere bei 1200 px', note: 'Heute fließen die Familien in einer Reihe, und ein Label bleibt am Zeilenende stehen, während seine Chips in der nächsten Zeile beginnen (gemessen an der Review-Instanz: „Währung“ am Ende der ersten Zeile; die ersten Felder der Gruppen bei 18, 18, 364 und 854 px; im Frame trifft es „Geändert seit“). „Bestand“ und „Datenqualität“ haben kein sichtbares Label. Neu (A): eine Zeile je Familie, jede benannt wie im Filterblatt des Telefons, alle Chips von einer Kante. Kostet zwei Zeilen Höhe.', frames: [B6.secBefore, B6.secAfter], recommended: true },
    { title: '④ Transaktionen bei 1200 px', note: 'Heute brechen die Kontochips über mehrere Zeilen, und jede weitere Zeile beginnt unter dem Label „Konto“ statt unter dem ersten Chip (gemessen mit den Namen des Seeds: 52, 0, 0, 33, 0 px; „Typ“ begann mitten in einer Zeile, „Geändert seit“ stand am Zeilenende, seine Chips in der nächsten). Die Kontonamen sind auf dem Board generisch, daher brechen die Zeilen im Frame etwas anders. Neu (A): alle Kontochips von einer Kante.', frames: [B6.txBefore, B6.txAfter], recommended: true },
    { lead: PROSE_LEAD, title: '⑤ Vermögen › Bestände, die Zeile über den Positionen', note: 'Heute zwei Sätze, 26 Wörter. Neu: die Menge der Zeilen und ihre Bewertung bleiben die Zeile; „Marktwert in EUR, wie ihn die Summe zählt.“ sagt, was die Summe rechnet, und geht ins ⓘ am Ende der Zeile. Die Währung steht in jeder Zelle des Marktwerts.', frames: [B6.posBefore, B6.posAfter], recommended: true },
    { title: '⑥ Wertpapier › Nachrichten', note: 'Heute zwei Sätze. „Zeiten in UTC“ ist eine Basis (die Zeitzone), keine Methode: sie bleibt sichtbar, als „·“-Fakt derselben Zeile. Das ⓘ bleibt, wie es ist.', frames: [B6.storiesBefore, B6.storiesAfter], recommended: true },
    { title: '⑦ Wertpapier › Diagramm, die Kursbasis', note: 'Heute zwei Sätze. Neu wie die Zeile des Tabs Kurse (I1 von Sprint 23): „Kursbasis: …“ bleibt, „Gespeicherte Kurse werden nie verändert (siehe Tab Kurse).“ geht ins ⓘ.', frames: [B6.chartBefore, B6.chartAfter], recommended: true },
    { title: '⑧ Wertpapier › Prognosen', note: 'Heute zwei Sätze; der zweite („Keine wird geändert oder gelöscht.“) ist die Regel, die die erste Zeile des ⓘ schon vollständig sagt. Neu: er entfällt aus der Zeile, wie im Tab Research.', frames: [B6.predBefore, B6.predAfter], recommended: true },
    { title: '⑨ Transaktionen, die Zeile unter der Summe', note: 'Heute ein Satz mit 37 Wörtern Methode. Neu: die Menge (was der Filter auswählt) und die Währung (je Währung, nicht umgerechnet) bleiben; die Richtung je Art und der Verkauf, dessen Kosten den Erlös übersteigen, gehen ins ⓘ.', frames: [B6.txSumBefore, B6.txSumAfter], recommended: true },
    { title: '⑩ Wertpapier › Übersicht, die Anleihe', note: 'Heute sechs Sätze, 65 Wörter, der längste freie Absatz der App. Neu: die Basis in einer Zeile (in Prozent vom Nennwert, ab heute, ohne Stückzinsen, Gebühren und Steuern); jede Formel und „Berichtet, nicht bewertet.“ als eigene Zeile im ⓘ.', frames: [B6.bondBefore, B6.bondAfter], recommended: true },
    { lead: CLOSING_LEAD, title: '⑪ „Nach dem Verkauf“ mit Wertpapier: Falz 840', note: 'Mit einer Benchmark braucht die Zeile etwa 790 px (gemessen: Umbruch bis 793 px Leiste). Mit dem Standardfalz 760 bleibt sie darüber eine Zeile und bricht um: die Auswahl rutscht unter „Vergleich“ an die linke Kante, der Schalter beginnt hinter dem Label, zwei Kanten. Gebaut: Falz 840, darunter die Labelspalte (A), darüber eine Zeile; der Boden 560 (B) bleibt.', frames: [B6.hsFoldBefore, B6.hsFoldAfter], decided: true },
    { title: '⑫ Vermögen › Risiko, Crashes: Falz 900 und die Breite der Auswahl', note: 'Mit der Auswahl des Fensters an ihrer Obergrenze braucht die Zeile etwa 880 px (gemessen: Umbruch bis 877 px Leiste, deutsch). Gebaut: Falz 900, darunter die Labelspalte (A). Bei 1200 px ist die Leiste 924 px, eine Zeile; dort schnitt die Obergrenze 19,5rem den Namen eines manuellen Fensters ab („… · manue“, 319 px nötig). Neu: 20,5rem; die Zeile bleibt unter 924 px.', frames: [B6.crashFoldBefore, B6.crashFoldAfter, B6.crashCapBefore, B6.crashCapAfter], recommended: true },
    { title: '⑬ Das ⓘ einer Basiszeile öffnet unter ihr', note: 'Heute öffnet das ⓘ der sechs Zeilen aus ⑤ bis ⑩ nach oben, wie jedes ⓘ, und legt sich über den Satz, zu dem es gehört (390 px; Nachrichten auch bei 1200 px über die Tab-Leiste). Neu, wie ⑤ bis ⑩ es zeichnen: ein ⓘ in einer Basiszeile (.summary-basis, .detail-tab-hint) öffnet darunter, nach oben nur, wenn unten kein Platz ist. Jedes andere ⓘ bleibt, wie es ist.', frames: [B6.infoBefore, B6.infoAfter], recommended: true },
    { title: '⑭ Vermögen, die Leiste des gestapelten Charts: Boden 340', note: 'Der breitere Rundgang des Abschlussakts (jede Breite, an der eine Leiste ihren Falz oder Boden kreuzt, ±1 px) fand bei 363 und 364 px Fenster (331 und 332 px Leiste, deutsch) die Ebene 2 px über der Leiste: „Klassifizierung“ und „Gesamt · Kategorien · Wertpapiere“ brauchen in der Labelspalte 334 px. Neu: Boden 340 für diese Leiste, darunter jedes Label über seinem Feld (B); bei 390 px bleibt die Labelspalte (A), bei 320 px B wie bisher. Abgelöst von ⑮: Boden 380.', frames: [B6.stackFloorBefore, B6.stackFloorAfter], recommended: true },
    { title: '⑮ Die Ersatzschrift: Falze und Böden für jede Schrift', note: 'Die App liefert keine Webschrift: --font-sans nennt Inter zuerst, ein Gerät ohne Inter zeichnet in seiner eigenen Schrift. Der Browser-Job von CI hatte kein Inter und zeichnete in DejaVu Sans, der breitesten der üblichen; dort brach die Regel, weil ⑪ bis ⑭ nur in Inter gemessen waren. Gemessen in beiden Schriften (deutsch, englisch), neu je Falz und Boden mindestens 16 px über der breiteren: Crashes, die Zeile mit der Auswahl an ihrer Obergrenze 888 (Inter) und 939 px (DejaVu Sans), mehr als die 924 px Leiste bei 1200 px; neu nimmt die Gruppe „Fenster“ den Rest der Zeile, von 16rem bis zu ihrer eigenen Breite, die Zeile braucht so 770 und 805 px, Falz 900 bleibt; in Inter ändert sich nichts, in DejaVu Sans wird der Name bei 1200 px gekürzt, die Auswahl zeigt ihn ganz. Gestapelter Chart, deutsch: Labelspalte 333 und 357 px, Boden 380 (bei 390 px nun B, in jeder Schrift); die Zeile 704 und 753 px, Falz 780. „Nach dem Verkauf“, englisch mit Benchmark: 798 und 834 px, Falz 860. Der Rundgang misst jede Leiste in beiden Schriften und scheitert, wenn eine fehlt.', frames: [B6.crashFontBefore, B6.crashFontAfter, B6.crashInterAfter, B6.stackFontBefore, B6.stackFontAfter, B6.stackFoldBefore, B6.stackFoldAfter, B6.hsFontBefore, B6.hsFontAfter], recommended: true },
  ]);

console.log('wrote frames/03* to 06* and boards 03 to 06');
