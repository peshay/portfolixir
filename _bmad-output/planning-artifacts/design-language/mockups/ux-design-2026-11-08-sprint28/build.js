// Sprint 28 planning boards, drawn on 2026-11-08 before any code:
//
//   01 the news view (ADR-0056 §10) and the note markers on a security's
//      chart (ADR-0056 A2, ADR-0044's amendment of 2026-11-06);
//   02 the stacked chart's filter and levels through sub-categories (FR-56,
//      idea I29), and a band that changes sign (#1426);
//   03 the stacked chart's levels in the TTWROR mode (FR-57, idea I28);
//   04 the running instance's version at the foot of the menu (FR-55, I27);
//   05 the currency_mismatch data-quality set on the Overview and as a
//      filter on Wertpapiere (#1415);
//   06 the stacked chart in the privacy mode, the shape kept (the Sprint 28
//      amendment of 2026-11-08).
//
// The chrome (sidebar, top bar, tabs, segmented controls, tables, the
// stacked chart's bar and legend) is the app's own markup: the shell is
// captured from the review instance on the synthetic review seed by
// capture.js (shell.html), and the rest uses the classes the shipped
// templates use, so app.css draws it. Charts are inline SVG drawn here from
// SYNTHETIC series (a seeded random walk), because the states they show do
// not exist yet. Every name is generic and every figure is invented; no
// instance data, name or machine detail appears.
//
// Usage:
//   node capture.js   # optional: re-captures shell.html (review instance on :4011)
//   node build.js     # writes frames/ and the four boards
//   node render.js    # renders each board to PNG, light and dark
const fs = require('fs');
const path = require('path');

const FRAMES = path.join(__dirname, 'frames');
fs.mkdirSync(FRAMES, { recursive: true });
const CSS_FROM_FRAME = '../../../../../../priv/static/app.css';
const STATIC_FROM_FRAME = '../../../../../../priv/static/';
const CSS_FROM_BOARD = '../../../../../priv/static/app.css';

// ---------------------------------------------------------------------------
// Synthetic data

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

// Business days, 09.11.2025 to 06.11.2026.
const DATES = [];
for (let d = new Date(Date.UTC(2025, 10, 10)); d <= new Date(Date.UTC(2026, 10, 6)); d.setUTCDate(d.getUTCDate() + 1)) {
  const wd = d.getUTCDay();
  if (wd !== 0 && wd !== 6) DATES.push(new Date(d));
}
const N = DATES.length;
const MARKET = DATES.map((_, i) => {
  let r = 0.0004 + 0.0072 * gauss();
  if (i >= 95 && i < 108) r -= 0.006;
  return r;
});

// A two-level tree: "Aktien" has three sub-categories and one security filed
// in itself; the other roots have none. The palette is the app's
// (@category_palette) in tree order; cash and the remainder in their colours.
const PALETTE = ['#2563eb', '#16a34a', '#ffab01', '#db2777', '#0d9488', '#7c3aed', '#65a30d', '#ea580c'];
const TREE = [
  { key: 'aktien', name: 'Aktien', color: PALETTE[0], subs: [
    { key: 'welt', name: 'Welt', secs: [
      { n: 'Welt-Aktien ETF', v: 30000, beta: 1.0, vol: 0.004 },
      { n: 'USA-Aktien ETF', v: 12000, beta: 1.1, vol: 0.005 }] },
    { key: 'em', name: 'Schwellenländer', secs: [
      { n: 'Schwellenländer ETF', v: 6000, beta: 1.15, vol: 0.007, buyAt: 128, buy: 4000 }] },
    { key: 'einzel', name: 'Einzelwerte', secs: [
      { n: 'Tech-Einzelwert A', v: 6500, beta: 1.7, vol: 0.016 },
      { n: 'Industrie-Einzelwert B', v: 4500, beta: 1.2, vol: 0.01 }] }],
    direct: [{ n: 'Dividenden-Fonds D', v: 5000, beta: 0.8, vol: 0.005 }] },
  { key: 'anleihen', name: 'Anleihen', color: PALETTE[1], subs: [], direct: [
    { n: 'Staatsanleihen ETF', v: 11000, beta: -0.12, vol: 0.002 }] },
  { key: 'rohstoffe', name: 'Rohstoffe', color: PALETTE[2], subs: [], direct: [
    { n: 'Gold ETC', v: 5500, beta: 0.05, vol: 0.007 }] },
  { key: 'krypto', name: 'Krypto', color: PALETTE[3], subs: [], direct: [
    { n: 'Bitcoin', v: 3500, beta: 1.9, vol: 0.025 }] },
];
const UNCLASSIFIED = [
  { n: 'Nebenwert E', v: 2500, beta: 1.3, vol: 0.012 },
  { n: 'Altfonds F', v: 1800, beta: 0.7, vol: 0.006 }];
const CASH = { n: 'Cash', v: 6000, cash: true };

function walk(s) {
  s.values = []; s.flows = []; s.prices = [];
  let v = s.v, price = 100;
  for (let i = 0; i < N; i++) {
    let flow = 0;
    if (i > 0 && !s.cash) {
      let r = s.beta * MARKET[i] + s.vol * gauss() + 0.0001;
      v *= 1 + r; price *= 1 + r;
    }
    if (s.buyAt === i) { v += s.buy; flow = s.buy; }
    if (s.cash && i === 128) { v -= 4000; flow = -4000; }
    // #1426: a buy booked two days before the money that pays it
    const dip = s.cash && (i === 200 || i === 201) ? 7500 : 0;
    s.values.push(v - dip); s.flows.push(flow); s.prices.push(price);
  }
  return s;
}
const ALL = [];
for (const c of TREE) {
  for (const sc of c.subs) for (const s of sc.secs) ALL.push(walk(s));
  for (const s of c.direct) ALL.push(walk(s));
}
for (const s of UNCLASSIFIED) ALL.push(walk(s));
walk(CASH);

const sum = (secs) => DATES.map((_, i) => secs.reduce((a, s) => a + s.values[i], 0));
const flows = (secs) => DATES.map((_, i) => secs.reduce((a, s) => a + s.flows[i], 0));
const secsOf = (c) => [...c.subs.flatMap((sc) => sc.secs), ...c.direct];

// TTWROR of a group: chain of daily returns with its own flows as flows,
// starting on the first day the group holds a value (ADR-0051's net flows).
function ttwror(values, fl) {
  const out = [];
  let acc = null;
  for (let i = 0; i < N; i++) {
    if (acc === null) { if (values[i] > 0) { acc = 1; out.push(0); } else out.push(null); continue; }
    const prev = values[i - 1];
    const r = prev > 0 ? (values[i] - fl[i]) / prev - 1 : 0;
    acc *= 1 + r; out.push(acc - 1);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Formatting

const nf0 = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const nf2 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const money = (x) => nf2.format(x);
const pct = (x) => (x > 0 ? '+' : x < 0 ? '−' : '') + nf1.format(Math.abs(x * 100)) + '%';
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const dmy = (d) => `${String(d.getUTCDate()).padStart(2, '0')}.${String(d.getUTCMonth() + 1).padStart(2, '0')}.${d.getUTCFullYear()}`;

// ---------------------------------------------------------------------------
// Chart geometry, as the shipped stacked chart: viewBox 960 x 320, plot
// 56..936 x 16..292, axis labels inside the plot (data-axis-inside).

const W = 960, H = 320, L = 56, R = 936, T = 16, B = 292;
const xAt = (i) => L + (R - L) * i / (N - 1);

function niceMax(v) {
  const mag = Math.pow(10, Math.floor(Math.log10(v)));
  return [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].map((m) => m * mag).find((s) => s >= v);
}

function axes(ticks, y, fmt) {
  const grid = ticks.map((t) => `<line x1="${L}" y1="${y(t).toFixed(2)}" x2="${R}" y2="${y(t).toFixed(2)}"></line>`).join('');
  const labels = ticks.map((t, k) => `<text class="chart-axis-y${k === ticks.length - 1 ? ' is-top' : ''}" x="50" y="${y(t).toFixed(2)}" text-anchor="end" dominant-baseline="central">${fmt(t)}</text>`).join('');
  return { grid: `<g class="chart-axes" stroke="currentColor" stroke-opacity="0.15">${grid}</g>`,
    labels: `<g class="chart-axis-labels">${labels}<text class="chart-axis-x" x="${L}" y="314" text-anchor="start">${dmy(DATES[0])}</text><text class="chart-axis-x" x="${R}" y="314" text-anchor="end">${dmy(DATES[N - 1])}</text></g>` };
}

// Bands bottom to top. mode 'diverging' is today's stack/1 (a negative day
// goes below zero, the path joins the days, #1426's sweep); mode 'split'
// places a band that changes sign next to zero and draws its positive and
// negative parts as separate polygons meeting at zero.
function stackSvg(bands, opts = {}) {
  const mode = opts.mode || 'split';
  let order = bands.slice();
  const changesSign = (b) => b.values.some((v) => v < 0) && b.values.some((v) => v > 0);
  if (mode === 'split') {
    const flip = order.filter(changesSign);
    order = [...flip, ...order.filter((b) => !changesSign(b))];
  }
  const posTop = DATES.map((_, i) => order.reduce((a, b) => a + Math.max(0, b.values[i]), 0));
  const negBot = DATES.map((_, i) => order.reduce((a, b) => a + Math.min(0, b.values[i]), 0));
  const max = niceMax(Math.max(...posTop) * 1.02);
  const min = Math.min(0, ...negBot);
  const lo = min < 0 ? -niceMax(-min * 1.1) : 0;
  const y = (v) => B - (B - T) * (v - lo) / (max - lo);
  const paths = [];
  const pos = DATES.map(() => 0), neg = DATES.map(() => 0);
  for (const b of order) {
    if (mode === 'diverging') {
      const top = [], bot = [];
      for (let i = 0; i < N; i++) {
        const v = b.values[i];
        if (v >= 0) { bot.push(pos[i]); pos[i] += v; top.push(pos[i]); } else { top.push(neg[i]); neg[i] += v; bot.push(neg[i]); }
      }
      const d = 'M' + top.map((v, i) => `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`).join('L') + 'L' + bot.map((v, i) => [i, v]).reverse().map(([i, v]) => `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`).join('L') + 'Z';
      paths.push(`<path class="stack-band" d="${d}" fill="${b.color}"><title>${esc(b.name)}</title></path>`);
    } else {
      const pTop = [], pBot = [], nTop = [], nBot = [];
      for (let i = 0; i < N; i++) {
        const v = b.values[i];
        pBot.push(pos[i]); pos[i] += Math.max(0, v); pTop.push(pos[i]);
        nTop.push(neg[i]); neg[i] += Math.min(0, v); nBot.push(neg[i]);
      }
      const poly = (top, bot) => 'M' + top.map((v, i) => `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`).join('L') + 'L' + bot.map((v, i) => [i, v]).reverse().map(([i, v]) => `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`).join('L') + 'Z';
      paths.push(`<path class="stack-band" d="${poly(pTop, pBot)}" fill="${b.color}"><title>${esc(b.name)}</title></path>`);
      if (b.values.some((v) => v < 0)) paths.push(`<path class="stack-band" d="${poly(nTop, nBot)}" fill="${b.color}" fill-opacity="0.75"><title>${esc(b.name)} (negativ)</title></path>`);
    }
  }
  const step = max / 4;
  const ticks = lo < 0 ? [lo, 0, max / 2, max] : [0, step, 2 * step, 3 * step, max];
  const ax = axes(ticks, y, opts.axis || ((t) => nf0.format(t)));
  const zero = lo < 0 ? `<line class="chart-zeroline" x1="${L}" x2="${R}" y1="${y(0).toFixed(1)}" y2="${y(0).toFixed(1)}" stroke="currentColor" stroke-opacity="0.5"></line>` : '';
  return `<svg class="stack-chart" role="img" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" width="100%">${ax.grid}${paths.join('')}${zero}${ax.labels}</svg>`;
}

function linesSvg(lines, bold) {
  const all = [...lines, bold].flatMap((l) => l.values.filter((v) => v !== null));
  const hi = Math.max(...all), lowv = Math.min(...all, 0);
  const top = Math.ceil(hi * 20) / 20, bot = Math.floor(lowv * 20) / 20;
  const y = (v) => B - (B - T) * (v - bot) / (top - bot);
  const ticks = [];
  for (let t = bot; t <= top + 1e-9; t += 0.05) ticks.push(Math.round(t * 100) / 100);
  const ax = axes(ticks, y, (t) => pct(t).replace(',0', ''));
  const path = (vals) => {
    let d = '', pen = false;
    vals.forEach((v, i) => { if (v === null) { pen = false; return; } d += (pen ? 'L' : 'M') + `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`; pen = true; });
    return d;
  };
  const ls = lines.map((l) => `<path d="${path(l.values)}" fill="none" stroke="${l.color}" stroke-width="1.6" stroke-linejoin="round"><title>${esc(l.name)}</title></path>`).join('');
  const start = lines.filter((l) => l.values[0] === null).map((l) => {
    const i = l.values.findIndex((v) => v !== null);
    return `<circle cx="${xAt(i).toFixed(1)}" cy="${y(0).toFixed(1)}" r="3.2" fill="${l.color}"></circle>`;
  }).join('');
  const zero = `<line class="chart-zeroline" x1="${L}" x2="${R}" y1="${y(0).toFixed(1)}" y2="${y(0).toFixed(1)}" stroke="currentColor" stroke-opacity="0.45"></line>`;
  const b = `<path d="${path(bold.values)}" fill="none" stroke="currentColor" stroke-width="3" stroke-linejoin="round"><title>${esc(bold.name)}</title></path>`;
  return `<svg class="stack-chart" role="img" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" width="100%">${ax.grid}${zero}${ls}${b}${start}${ax.labels}</svg>`;
}

// ---------------------------------------------------------------------------
// The stacked chart's bar, figure and legend, as stacked_chart.ex renders them

function seg(label, options, active) {
  return `<span class="stack-bar__group"><span class="stack-bar__label">${label}</span><div class="segmented-control" role="group">${options.map((o) => `<a class="segmented-control__option${o === active ? ' is-active' : ''}">${o}</a>`).join('')}</div></span>`;
}
function bar({ crumbs, level, sort = 'Größe', tree = true }) {
  const cr = crumbs.map((c, k) => (k > 0 ? '<span class="stack-crumbs__sep" aria-hidden="true">›</span>' : '') + (k < crumbs.length - 1 ? `<a>${esc(c)}</a>` : `<span aria-current="location">${esc(c)}</span>`)).join('');
  const treeSel = tree ? `<form class="stack-bar__tree"><label>Klassifizierung</label><select><option>Strategie</option></select></form>` : '';
  const sortSeg = level !== 'Gesamt' ? seg('Sortieren', ['Größe', 'Veränderung'], sort) : '';
  return `<div class="stack-bar"><nav class="stack-crumbs">${cr}</nav><div class="stack-bar__controls">${seg('Ebene', ['Gesamt', 'Kategorien', 'Wertpapiere'], level)}${treeSel}${sortSeg}</div></div>`;
}
function legend(head, rows, opts = {}) {
  const body = rows.map((r) => `<tr><td class="stack-legend__name"><span class="stack-swatch" style="background: ${r.color}" aria-hidden="true"></span>${r.drill ? `<a class="stack-legend__drill">${esc(r.name)}</a><span class="stack-legend__chevron" aria-hidden="true">›</span>` : esc(r.name)}</td>${opts.ttwror ? '' : `${opts.privacy ? '' : `<td class="num">${money(r.end)}</td>`}<td class="num">${pct(r.share)}</td>`}<td class="num">${r.change === null ? '—' : pct(r.change)}</td></tr>`).join('');
  const cols = opts.ttwror ? '<th scope="col" class="num">TTWROR</th>' : `${opts.privacy ? '' : '<th scope="col" class="num">Wert</th>'}<th scope="col" class="num">Anteil</th><th scope="col" class="num">Veränd.</th>`;
  return `<table class="stack-legend"><thead><tr><th scope="col">${head}</th>${cols}</tr></thead><tbody>${body}</tbody></table>`;
}
function figure(svg, leg, basis) {
  return `<figure class="perf-figure stack-figure" data-scale="value"><div class="stack-figure__body"><div class="stack-figure__chart" data-axis-inside="" style="--chart-upx: 1.5;">${svg}</div>${leg}</div></figure><p class="hint">${basis}</p>`;
}
function modeSeg(active) {
  return `<div class="mock-mode"><div class="segmented-control" role="group">${['% (TTWROR)', 'Wert (EUR)'].map((o) => `<a class="segmented-control__option${o === active ? ' is-active' : ''}">${o}</a>`).join('')}</div><div class="segmented-control" role="group">${['YTD', '1J', '3J', '5J', 'Max'].map((o) => `<a class="segmented-control__option${o === '1J' ? ' is-active' : ''}">${o}</a>`).join('')}</div></div>`;
}

function band(name, color, secs, extra = {}) {
  const values = sum(secs), fl = flows(secs);
  const start = values[0], end = values[N - 1];
  const net = fl.reduce((a, f) => a + f, 0);
  return { name, color, values, flows: fl, end, change: start > 0 ? (end - start - net) / start : null, ...extra };
}
function withShares(bands) {
  const tot = bands.reduce((a, b) => a + b.end, 0);
  return bands.map((b) => ({ ...b, share: b.end / tot }));
}
const bySize = (a, b) => b.end - a.end;

// ---------------------------------------------------------------------------
// Frames: one static page each, linking app.css

const SHELL = fs.readFileSync(path.join(__dirname, 'shell.html'), 'utf8')
  .replace(/src="\/images\//g, `src="${STATIC_FROM_FRAME}images/`);

const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 2px; border-radius: 8px; }
.mock-mode { display: flex; gap: 12px; margin: 0 0 12px; }
.mock-pad { padding: 16px 20px; }
`;

// One element per line, so a frame stays a readable multiline file; only a
// chart path's data stays on one line.
const BREAK_BEFORE = /><(?=\/?(?:path|g|svg|line|circle|text|tr|td|th|thead|tbody|table|div|section|figure|nav|aside|header|form|select|label|button|a|p|h[1-6]|span class="(?:stack-bar__group|news-|stack-swatch)))/g;
const multiline = (s) => s.replace(BREAK_BEFORE, '>\n<');

function writeFrame(name, rawBody, { css = '', width = 1000, shell = false, title = '', subtitle = '', active = null, extraNav = '' } = {}) {
  const body = multiline(rawBody);
  let html = body;
  if (shell) {
    let s = SHELL.replace('%%MAIN%%', body)
      .replace(/<h1 id="app-topbar-title">[^<]*<\/h1>/, `<h1 id="app-topbar-title">${title}</h1>`)
      .replace(/<p id="app-topbar-subtitle">[^<]*<\/p>/, `<p id="app-topbar-subtitle">${subtitle}</p>`)
      .replace(/class="nav-link is-active"/g, 'class="nav-link "');
    if (active) s = s.replace(`id="${active}" class="nav-link "`, `id="${active}" class="nav-link is-active"`);
    if (extraNav) s = extraNav(s);
    html = s;
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

// ---------------------------------------------------------------------------
// The boards

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
<section class="mock-board">
  <h2>${s.title}${s.recommended ? ' <small>empfohlen</small>' : ''}${s.decided ? ' <small>entschieden</small>' : ''}</h2>
  <p class="mock-note">${s.note}</p>
  <div class="mock-row">${s.frames.map((f) => `<figure class="mock-fig">${f.tag ? `<span class="mock-tag">${f.tag}</span>` : ''}<div class="mock-frame"><iframe src="frames/${f.file}" width="${f.width}" height="${f.height}" title="${f.file}"></iframe></div></figure>`).join('')}</div>
</section>`).join('\n');
  const html = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<link rel="stylesheet" href="${CSS_FROM_BOARD}">
<!-- Generated by build.js. Each frame under frames/ is a static page that
     links app.css; the block below is artboard chrome only. No script runs
     here. Synthetic data only. -->
<style id="board">${BOARD_CSS(cols)}</style>
</head>
<body>
<div class="mock-board mock-head"><h1>${esc(title)}</h1>${intro}</div>
${sec}
</body>
</html>
`;
  fs.writeFileSync(path.join(__dirname, file), html);
}

// Frame heights are measured by render.js on first render; until then a
// generous default. render.js writes sizes.json and asks for a rebuild.
let SIZES = {};
try { SIZES = JSON.parse(fs.readFileSync(path.join(FRAMES, 'sizes.json'), 'utf8')); } catch (e) { /* first run */ }
const sized = (f, tag, fixed) => ({ ...f, tag, height: fixed || SIZES[f.file] || 700 });

// ===========================================================================
// Board 02 — FR-56 and #1426

const roots = TREE.map((c) => band(c.name, c.color, secsOf(c), { drill: true }));
const cashBand = band('Cash', '#0ea5e9', [CASH]);
const unclBand = band('Nicht zugeordnet', '#9ca3af', UNCLASSIFIED, { drill: true });
const aktien = TREE[0];
const subColors = ['#2563eb', '#0d9488', '#7c3aed', '#93c5fd'];

function stackFrame(name, { crumbs, level, bands, head, basis, mode, tag }) {
  const rows = withShares(bands).sort(bySize);
  const stackOrder = rows.slice().reverse().reverse(); // largest at the bottom
  const svg = stackSvg(stackOrder, { mode });
  const legRows = rows.slice().sort(bySize);
  return sized(writeFrame(name, `<div class="mock-pad">${modeSeg('Wert (EUR)')}${bar({ crumbs, level })}${figure(svg, legend(head, legRows), basis)}</div>`), tag);
}

const B2 = {};
B2.root = stackFrame('02a-kategorien', {
  crumbs: ['Alle Kategorien'], level: 'Kategorien', head: 'Kategorie',
  bands: [...roots, cashBand, unclBand],
  basis: 'Marktwert je Kategorie von „Strategie“ am Tagesende in EUR, jede Wurzelkategorie über ihren ganzen Teilbaum; Cash und der nicht zugeordnete Rest sind eigene Bänder. Ein Klick auf eine Kategorie setzt den Filter; „Nicht zugeordnet“ ist ebenfalls ein Filter.'
});
const subBands = [
  ...aktien.subs.map((sc, k) => band(sc.name, subColors[k], sc.secs, { drill: true })),
  band('Aktien (direkt)', subColors[3], aktien.direct)
];
B2.filtered = stackFrame('02b-aktien-kategorien', {
  crumbs: ['Alle Kategorien', 'Aktien'], level: 'Kategorien', head: 'Unterkategorie',
  bands: subBands,
  basis: 'Filter „Aktien“: ihre direkten Unterkategorien als Bänder, jede über ihren Teilbaum, und „Aktien (direkt)“ für die Wertpapiere, die in „Aktien“ selbst stehen. Ohne Cash und ohne Rest; die Bänder ergeben zusammen das Band „Aktien“ der Ebene darüber. „Gesamt“ zeichnet mit diesem Filter die Linie von „Aktien“.'
});
const aktienSecs = secsOf(aktien).map((s, k) => band(s.n, PALETTE[k % PALETTE.length], [s]));
B2.secs = stackFrame('02c-aktien-wertpapiere', {
  crumbs: ['Alle Kategorien', 'Aktien'], level: 'Wertpapiere', head: 'Wertpapier',
  bands: aktienSecs,
  basis: 'Derselbe Filter auf der Ebene „Wertpapiere“: die Wertpapiere des ganzen Teilbaums von „Aktien“, die Farben der Palette der Reihe nach. Die Ebene bleibt beim Filtern, der Filter beim Wechsel der Ebene.'
});
B2.uncl = stackFrame('02d-nicht-zugeordnet', {
  crumbs: ['Alle Kategorien', 'Nicht zugeordnet'], level: 'Wertpapiere', head: 'Wertpapier',
  bands: UNCLASSIFIED.map((s, k) => band(s.n, PALETTE[k], [s])),
  basis: '„Nicht zugeordnet“ als Filter: die Wertpapiere, die „Strategie“ keiner Kategorie zuordnet — so sieht man, was fehlt. Auf „Kategorien“ bleibt es ein Band ohne Unterteilung. Cash und „Sonstige“ haben keinen Filter.'
});
const secBandsAll = [...ALL.slice(0, 7).map((s, k) => band(s.n, PALETTE[k], [s])), band('Cash', '#0ea5e9', [CASH])];
B2.before = stackFrame('02e-vorzeichen-heute', {
  crumbs: ['Alle Kategorien'], level: 'Wertpapiere', head: 'Wertpapier', mode: 'diverging',
  bands: secBandsAll,
  basis: 'Heute (#1426): Cash ist an zwei Tagen negativ (ein Kauf vor dem Geld gebucht). Der Pfad verbindet die Tage, das Band fegt diagonal unter null und zurück und schneidet die Bänder dazwischen.'
});
B2.after = stackFrame('02f-vorzeichen-neu', {
  crumbs: ['Alle Kategorien'], level: 'Wertpapiere', head: 'Wertpapier', mode: 'split',
  bands: secBandsAll,
  basis: 'Neu: ein Band, das im Zeitraum das Vorzeichen wechselt, liegt direkt an der Nulllinie; sein positiver und sein negativer Teil sind getrennte Flächen, die sich am Tag des Wechsels bei null treffen. Kein Band kreuzt ein anderes; Legende und API bleiben.'
});

board('02-stack-filter.html', 'Sprint 28 — Board 02: Filter und Ebenen durch Unterkategorien (FR-56), Vorzeichenwechsel (#1426)', 1040,
  `<div class="mock-pickbar"><p><strong>Was entschieden ist (I29, 2026-11-08):</strong> Ein Klick auf eine Kategorie setzt einen Filter und behält die Ebene. Auf „Kategorien“ sind die direkten Unterkategorien die Bänder, plus „‹Name› (direkt)“; eine Kategorie ohne Unterkategorien bleibt ein Band. Mit Filter verlassen Cash und Rest den Chart. „Nicht zugeordnet“ ist ebenfalls ein Filter. Die Standardebene wird „Kategorien“. Der Brotkrumenpfad allein zeigt die Tiefe.</p><p><strong>Was dieses Board zusätzlich festlegt (Plan D-6, per Kommentar umkehrbar):</strong> die Farben einer Unterebene — Unterkategorien und Wertpapiere nehmen die Palette der Reihe nach, wie Board 01 von Sprint 27 es für das Aufklappen festlegte; „(direkt)“ steht zuletzt in der Reihenfolge der Farben. Und #1426: ein Band mit Vorzeichenwechsel liegt an der Nulllinie.</p></div>`,
  [
    { title: '① Kategorien, kein Filter — die neue Standardansicht', note: 'Wie gebaut, nur jetzt die Voreinstellung. Wurzelkategorien über ihren Teilbaum; Cash und „Nicht zugeordnet“ als eigene Bänder; „Nicht zugeordnet“ trägt jetzt den Pfeil, weil es filterbar ist.', frames: [B2.root] },
    { title: '② Filter „Aktien“, Ebene bleibt „Kategorien“', note: 'Die drei Unterkategorien und „Aktien (direkt)“. Der Pfad „Alle Kategorien › Aktien“ führt eine Stufe zurück.', frames: [B2.filtered] },
    { title: '③ Derselbe Filter auf „Wertpapiere“', note: 'Der Wechsel der Ebene behält den Filter.', frames: [B2.secs] },
    { title: '④ „Nicht zugeordnet“ als Filter', note: 'Die Wertpapiere ohne Kategorie in diesem Baum.', frames: [B2.uncl] },
    { title: '⑤ #1426 — heute', note: 'Zum Vergleich: die diagonale Fläche um Tag 200.', frames: [B2.before] },
    { title: '⑥ #1426 — neu', note: 'Das Band mit Vorzeichenwechsel unten an der Nulllinie, negativ darunter, etwas heller.', frames: [B2.after], recommended: true },
  ]);

// ===========================================================================
// Board 03 — FR-57, TTWROR lines

function ttwrorFrame(name, { crumbs, level, lines, bold, head, basis, tag }) {
  const rows = lines.map((l) => ({ ...l, change: l.values[N - 1] }));
  const svg = linesSvg(lines, bold);
  const leg = legend(head, [{ name: bold.name + ' (fett)', color: 'currentColor', change: bold.values[N - 1] }, ...rows], { ttwror: true });
  return sized(writeFrame(name, `<div class="mock-pad">${modeSeg('% (TTWROR)')}${bar({ crumbs, level })}${figure(svg, leg, basis)}</div>`), tag);
}
const viewSecs = [...ALL, CASH];
const viewLine = { name: 'Ansicht', values: ttwror(sum(viewSecs), flows(viewSecs)) };
const rootLines = TREE.map((c) => ({ name: c.name, color: c.color, values: ttwror(sum(secsOf(c)), flows(secsOf(c))) }));
const B3 = {};
B3.root = ttwrorFrame('03a-ttwror-kategorien', {
  crumbs: ['Alle Kategorien'], level: 'Kategorien', head: 'Kategorie', lines: rootLines, bold: viewLine,
  basis: 'Je Band seine eigene zeitgewichtete Rendite über den Zeitraum, seine Käufe und Verkäufe als seine Zu- und Abflüsse (ADR-0051); nicht gestapelt, weil Renditen sich nicht addieren. Die Ansicht fett. Ohne Cash, ohne Rest und ohne „Sonstige“; höchstens acht Linien nach Wert am Ende des Zeitraums.'
});
const subLines = [
  ...aktien.subs.map((sc, k) => ({ name: sc.name, color: subColors[k], values: ttwror(sum(sc.secs), flows(sc.secs)) })),
  { name: 'Aktien (direkt)', color: subColors[3], values: ttwror(sum(aktien.direct), flows(aktien.direct)) }];
// EM bought into from scratch inside the window: draw it as a band that
// starts that day, to show the 0 % start.
const emLate = { ...subLines[1] };
emLate.values = subLines[1].values.map((v, i) => (i < 128 ? null : v - subLines[1].values[128]));
subLines[1] = { ...emLate, name: 'Schwellenländer (ab Kauf)' };
B3.filtered = ttwrorFrame('03b-ttwror-aktien', {
  crumbs: ['Alle Kategorien', 'Aktien'], level: 'Kategorien', head: 'Unterkategorie', lines: subLines,
  bold: { name: 'Aktien', values: ttwror(sum(secsOf(aktien)), flows(secsOf(aktien))) },
  basis: 'Filter „Aktien“: die Unterkategorien als Linien, „Aktien“ fett. Ein Band, das erst im Zeitraum Wert bekommt (hier: der erste Kauf in Schwellenländern), beginnt an diesem Tag bei 0 % — der Punkt markiert den Start.'
});
board('03-ttwror-levels.html', 'Sprint 28 — Board 03: Ebenen im TTWROR-Modus (FR-57)', 1040,
  `<div class="mock-pickbar"><p><strong>Was entschieden ist (I28, 2026-11-08):</strong> eine Linie je Band, die Linie der Ansicht fett dazwischen; dieselben Bänder wie im Wert-Modus, aber ohne „Sonstige“, Cash und Rest; höchstens acht Linien nach Wert am Ende; ein Band, das im Zeitraum Wert bekommt, beginnt an diesem Tag bei 0 %; der Filter aus FR-56 gilt in beiden Modi.</p><p><strong>Was dieses Board festlegt (Plan D-6):</strong> die Legende zeigt nur die TTWROR je Band, keine Beträge (die stehen im Wert-Modus), und die fette Linie steht als erste Zeile; die Linien tragen die Farben der Bänder; der Startpunkt eines späten Bandes ist ein Punkt.</p></div>`,
  [
    { title: '① TTWROR, Kategorien', note: 'Die Wurzelkategorien und die Ansicht.', frames: [B3.root] },
    { title: '② TTWROR, Filter „Aktien“', note: 'Die Unterkategorien und „Aktien“ fett; ein spätes Band beginnt bei 0 %.', frames: [B3.filtered] },
  ]);

// ===========================================================================
// Board 04 — FR-55, the version at the foot of the menu

const FOOT_CSS = `
.sidebar-version { display: grid; gap: 1px; margin: 8px 12px 4px; padding: 10px 0 2px; border-top: 1px solid var(--color-border); font-size: 11.5px; line-height: 1.35; color: var(--color-text-muted); }
.sidebar-version__label { font-size: 10.5px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; }
.sidebar-version a { color: inherit; text-decoration: none; font-family: var(--font-mono, ui-monospace, monospace); }
.sidebar-version a:hover { color: var(--color-accent); text-decoration: underline; }
.sidebar-version__ext { margin-left: 3px; opacity: .7; }
.sidebar-version__unknown { font-style: italic; }
.app-sidebar { display: flex; flex-direction: column; }
.app-sidebar .sidebar-version { margin-top: auto; }
`;
function versionFoot(kind) {
  const ext = '<span class="sidebar-version__ext" aria-hidden="true">↗</span>';
  const inner = kind === 'release' ? `<a href="#" title="Versionshinweise auf GitHub">2026.11.12${ext}</a>`
    : kind === 'build' ? `<a href="#" title="Commit auf GitHub">main · 3cba116 · 08.11.2026${ext}</a>`
    : '<span class="sidebar-version__unknown">unbekannt</span>';
  return `<div class="sidebar-version mock-new" id="sidebar-version"><span class="sidebar-version__label">Version</span>${inner}</div>`;
}
const B4 = {};
for (const kind of ['release', 'build', 'unknown']) {
  B4[kind] = sized(writeFrame(`04-${kind}`, '<div class="workspace-page mock-pad"><p class="hint">…</p></div>', {
    shell: true, title: 'Übersicht', subtitle: 'Vermögen auf einen Blick', active: 'nav-dashboard', css: FOOT_CSS, width: 940,
    extraNav: (s) => s.replace('</nav>', '</nav>' + versionFoot(kind))
  }), { release: 'Release', build: 'Entwicklungsstand', unknown: 'unbekannt' }[kind], 560);
}
B4.phone = sized(writeFrame('04-phone', '<div class="workspace-page mock-pad"><p class="hint">…</p></div>', {
  shell: true, title: 'Übersicht', subtitle: '', active: 'nav-dashboard', css: FOOT_CSS, width: 390,
  extraNav: (s) => s.replace('</nav>', '</nav>' + versionFoot('release')).replace('id="app-sidebar-toggle" class="sidebar-toggle-control" type="checkbox"', 'id="app-sidebar-toggle" class="sidebar-toggle-control" type="checkbox" checked')
}), 'Telefon, Menü offen', 760);
board('04-version.html', 'Sprint 28 — Board 04: die installierte Version am Fuß des Menüs (FR-55)', 1910,
  `<div class="mock-pickbar"><p><strong>Was entschieden ist (I27, 2026-11-08):</strong> am Fuß der Seitenleiste, auf dem Telefon unten im Menü (nicht in der Tab-Leiste); der Release-Tag, wenn der Build genau auf einem steht, sonst Branch, kurzer Hash und Datum, sonst „unbekannt“, nie geraten; ein Link zu den Versionshinweisen auf GitHub, dem der Betreiber folgt — die App fragt nichts an.</p><p><strong>Was dieses Board festlegt (Plan D-6):</strong> eine kleine Beschriftung „Version“ über dem Wert, Monospace für den Wert, eine feine Linie darüber; beim Entwicklungsstand verweist der Link auf den Commit; „unbekannt“ ohne Link und kursiv. Die Fläche ist gestrichelt markiert, nur auf dem Board.</p></div>`,
  [
    { title: '① Die drei Zustände, Seitenleiste', note: 'Release, Entwicklungsstand, unbekannt. Der Fuß sitzt unter der Navigation, unter „Abmelden“, wenn die Anmeldung aktiv ist.', frames: [B4.release, B4.build, B4.unknown], decided: true },
    { title: '② Telefon, Menü geöffnet', note: 'Unten im Menü; die Tab-Leiste bleibt unverändert.', frames: [B4.phone] },
  ]);

// ===========================================================================
// Board 01 — the news view and the note markers

const NEWS_CSS = `
.news-health { display: flex; gap: 8px; flex-wrap: wrap; margin: 0 0 16px; }
.news-chip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 10px; border-radius: 999px; font-size: 12px; font-weight: 650; background: var(--color-bg-muted); color: var(--color-text-muted); border: 1px solid var(--color-border); }
.news-chip.is-warn { color: var(--color-warning); background: var(--color-warning-soft); border-color: var(--color-warning); }
.news-chip.is-bad { color: var(--color-danger); background: var(--color-danger-soft); border-color: var(--color-danger); }
.news-tier { display: inline-block; padding: 1px 7px; border-radius: 6px; font-size: 11px; font-weight: 700; letter-spacing: .03em; background: var(--color-bg-muted); color: var(--color-text-muted); }
.news-tier--primary { background: var(--color-accent-soft); color: var(--color-accent); }
.news-tier--blocked { text-decoration: line-through; }
.news-label { display: inline-flex; gap: 4px; align-items: center; font-size: 11.5px; color: var(--color-text-muted); }
.news-machine { font-size: 10px; font-weight: 700; padding: 0 5px; border: 1px dashed var(--color-border-strong); border-radius: 5px; color: var(--color-text-muted); }
.news-tone { width: 8px; height: 8px; border-radius: 50%; display: inline-block; background: var(--color-text-muted); }
.news-tone--pos { background: #16a34a; } .news-tone--neg { background: #dc2626; }
.news-title { font-weight: 600; }
.news-sub { display: block; font-size: 12px; color: var(--color-text-muted); margin-top: 2px; }
.news-assign { display: flex; gap: 6px; align-items: center; }
.news-assign select { font-size: 12.5px; padding: 3px 6px; max-width: 150px; }
.news-assign .button-ghost { white-space: nowrap; }
.news-section { margin: 0 0 22px; }
.news-section h3 { margin: 0 0 8px; font-size: 15px; }
.area-tab-new { outline: 2px dashed var(--color-accent); outline-offset: -2px; border-radius: 6px; }
.note-pin line { stroke-width: 1.2; stroke-dasharray: 2 3; }
.note-pin circle { stroke: var(--color-bg); stroke-width: 1.5; }
.note-pin--pos circle { fill: #16a34a; } .note-pin--pos line { stroke: #16a34a; }
.note-pin--neg circle { fill: #dc2626; } .note-pin--neg line { stroke: #dc2626; }
.note-pin--neu circle { fill: #6b7280; } .note-pin--neu line { stroke: #6b7280; }
.note-dot { stroke: var(--color-bg); stroke-width: 1.5; }
.chart-toggles { display: flex; gap: 14px; font-size: 12.5px; color: var(--color-text-muted); margin: 6px 0 0; }
.chart-tip { position: absolute; padding: 8px 10px; background: var(--color-bg-elevated); border: 1px solid var(--color-border-strong); border-radius: 8px; box-shadow: var(--shadow-panel); font-size: 12px; max-width: 260px; line-height: 1.4; }
`;
const NEWS_NAV = (s) => s.replace(/(<a id="nav-transactions")/, `<a id="nav-news" class="nav-link mock-new" href="#"><span class="nav-marker" aria-hidden="true"></span><span class="nav-ico" aria-hidden="true"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"></rect><path d="M7 8h10M7 12h10M7 16h6"></path></svg></span><span class="nav-label">Nachrichten</span></a>$1`);
const tabsHtml = (active) => `<nav class="area-tabs" id="area-tabs" role="tablist">${['Meldungen', 'Feeds', 'Quellen'].map((t) => `<a class="area-tab${t === active ? ' is-active' : ''}" role="tab" aria-selected="${t === active}">${t}</a>`).join('')}</nav>`;
const health = `<div class="news-health"><span class="news-chip">5 Feeds</span><span class="news-chip is-warn">1 veraltet (kein Abruf seit 26 h)</span><span class="news-chip is-bad">3 Fehler (heute und gestern)</span><span class="news-chip">41 Meldungen in 24 h</span><span class="news-chip">2 nicht zugeordnet · 1 mehrdeutig</span></div>`;
const queue = `<section class="news-section"><h3>Zuzuordnen</h3><div class="data-table-wrapper"><table class="data-table"><thead><tr><th>Meldung</th><th>Quelle</th><th>Zeit</th><th>Zuordnen</th></tr></thead><tbody>
<tr><td><span class="news-title">Hersteller A erhöht Prognose nach starkem Quartal</span><span class="news-sub">mehrdeutig · Kandidaten: Tech-Einzelwert A · Industrie-Einzelwert B</span></td><td>wire.example <span class="news-tier">secondary</span></td><td>08.11. 09:12</td><td><div class="news-assign"><select><option>Tech-Einzelwert A</option></select><button class="button-ghost" type="button">Zuordnen</button></div><span class="news-sub">Vorschlag <span class="news-machine">maschinell</span>: Tech-Einzelwert A</span></td></tr>
<tr><td><span class="news-title">Rohstoffpreise ziehen an, Goldförderer im Fokus</span><span class="news-sub">nicht zugeordnet · kein Alias getroffen</span></td><td>markets.example <span class="news-tier">secondary</span></td><td>08.11. 07:40</td><td><div class="news-assign"><select><option>— Wertpapier wählen —</option></select><button class="button-ghost" type="button">Zuordnen</button></div></td></tr>
<tr><td><span class="news-title">Notenbank lässt Zinsen unverändert</span><span class="news-sub">nicht zugeordnet · kein Alias getroffen</span></td><td>news.example <span class="news-tier">secondary</span></td><td>07.11. 20:05</td><td><div class="news-assign"><select><option>— Wertpapier wählen —</option></select><button class="button-ghost" type="button">Zuordnen</button></div></td></tr>
</tbody></table></div></section>`;
const digest = `<section class="news-section"><h3>Neu je Wertpapier (seit gestern)</h3><div class="data-table-wrapper"><table class="data-table"><thead><tr><th>Wertpapier</th><th class="num">Meldungen</th><th>Wichtigste Meldung</th><th>Einordnung</th></tr></thead><tbody>
<tr><td>Tech-Einzelwert A</td><td class="num">4</td><td><span class="news-title">Quartalsbericht: Umsatz über Plan</span><span class="news-sub">ir.example · <span class="news-tier news-tier--primary">primary</span> · 08.11. 07:00</span></td><td><span class="news-label"><span class="news-tone news-tone--pos"></span>earnings · Materialität 2 <span class="news-machine">maschinell</span></span></td></tr>
<tr><td>Industrie-Einzelwert B</td><td class="num">2</td><td><span class="news-title">Pflichtmitteilung: Kapitalerhöhung angekündigt</span><span class="news-sub">regulator.example · <span class="news-tier news-tier--primary">primary</span> · 07.11. 18:30</span></td><td><span class="news-label"><span class="news-tone news-tone--neg"></span>capital_measure · Materialität 3 <span class="news-machine">maschinell</span></span></td></tr>
<tr><td>Welt-Aktien ETF</td><td class="num">1</td><td><span class="news-title">Indexanbieter passt Gewichtung an</span><span class="news-sub">index.example · <span class="news-tier">secondary</span> · 07.11. 12:10</span></td><td><span class="news-label">ohne Einordnung</span></td></tr>
<tr><td colspan="4" class="hint">9 Wertpapiere ohne Neues · 6 Meldungen aus Aggregatoren ohne Einordnung ausgeblendet</td></tr>
</tbody></table></div></section>`;
const feeds = `<section class="news-section"><h3>Feeds</h3><div class="data-table-wrapper"><table class="data-table"><thead><tr><th>Feed</th><th>Klasse</th><th>Bindung</th><th>Letzter Abruf</th><th class="num">24 h</th><th class="num">Fehler</th><th class="num">30 T</th><th class="num">übernommen</th><th>Zustand</th></tr></thead><tbody>
<tr><td>ir.example/feed</td><td>issuer</td><td>Tech-Einzelwert A</td><td>08.11. 10:55</td><td class="num">3</td><td class="num">0</td><td class="num">38</td><td class="num">4</td><td><span class="news-chip">ok</span></td></tr>
<tr><td>regulator.example/filings</td><td>regulatory</td><td>Industrie-Einzelwert B</td><td>08.11. 10:50</td><td class="num">1</td><td class="num">0</td><td class="num">12</td><td class="num">2</td><td><span class="news-chip">ok</span></td></tr>
<tr><td>wire.example/markets</td><td>aggregator</td><td>Universum</td><td>08.11. 10:40</td><td class="num">31</td><td class="num">3</td><td class="num">812</td><td class="num">0</td><td><span class="news-chip is-warn">wenig Ertrag</span></td></tr>
<tr><td>themen.example/rohstoffe</td><td>thematic</td><td>Rohstoffe</td><td>07.11. 08:30</td><td class="num">0</td><td class="num">0</td><td class="num">40</td><td class="num">1</td><td><span class="news-chip is-warn">veraltet</span></td></tr>
<tr><td>sec.example/company</td><td>regulatory</td><td>USA-Aktien ETF</td><td>—</td><td class="num">0</td><td class="num">0</td><td class="num">0</td><td class="num">0</td><td><span class="news-chip is-bad">Kontakt fehlt</span></td></tr>
</tbody></table></div><p class="hint">Fehler: heutiger und gestriger Servertag. „wenig Ertrag“: mindestens 50 Meldungen und keine übernommen in 30 Tagen; nichts schaltet einen Feed von selbst ab. Feeds anlegen und löschen bleibt in diesem Sprint beim Agenten und der API (Plan D-5).</p></section>`;
const sources = `<section class="news-section"><h3>Quellen</h3><div class="data-table-wrapper"><table class="data-table"><thead><tr><th>Domain</th><th>Stufe</th><th>gesetzt</th></tr></thead><tbody>
<tr><td>ir.example</td><td><span class="news-tier news-tier--primary">primary</span></td><td>von Hand</td></tr>
<tr><td>wire.example</td><td><span class="news-tier">secondary</span></td><td>Voreinstellung</td></tr>
<tr><td>spam.example</td><td><span class="news-tier news-tier--blocked">blocked</span></td><td>von Hand · 14 verworfen heute</td></tr>
</tbody></table></div></section>`;
const B1 = {};
B1.page = sized(writeFrame('01a-nachrichten-meldungen', `<div class="workspace-page">${tabsHtml('Meldungen')}<div class="mock-pad">${health}${queue}${digest}</div></div>`, {
  shell: true, title: 'Nachrichten', subtitle: 'Was die Feeds liefern, wie der Agent es sieht', active: 'nav-news', css: NEWS_CSS, width: 1220, extraNav: NEWS_NAV
}), 'A — eigene Seite, Meldungen');
B1.feeds = sized(writeFrame('01b-nachrichten-feeds', `<div class="workspace-page">${tabsHtml('Feeds')}<div class="mock-pad">${health}${feeds}${sources}</div></div>`, {
  shell: true, title: 'Nachrichten', subtitle: 'Was die Feeds liefern, wie der Agent es sieht', active: 'nav-news', css: NEWS_CSS, width: 1220, extraNav: NEWS_NAV
}), 'A — Feeds und Quellen');

// Variant B: no page of its own: feeds under Verwaltung, the queue as a
// filter chip on Wertpapiere.
const NAV_B = (s) => s.replace(/(<a id="nav-journal")/, `<a id="nav-feeds" class="nav-link mock-new" href="#"><span class="nav-marker" aria-hidden="true"></span><span class="nav-ico" aria-hidden="true"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 11a9 9 0 0 1 9 9M4 4a16 16 0 0 1 16 16"></path><circle cx="5" cy="19" r="1.2"></circle></svg></span><span class="nav-label">Feeds</span></a>$1`);
B1.b = sized(writeFrame('01c-variante-b', `<div class="workspace-page mock-pad"><div class="news-health"><span class="news-chip">Im Bestand</span><span class="news-chip">Ohne Bestand</span><span class="news-chip mock-new">Nachrichten zuzuordnen (3)</span><span class="news-chip">Kurs veraltet</span></div><p class="hint">Die Warteschlange wäre ein Filter der Wertpapierliste, Feeds und Quellen eine Seite unter „Verwaltung“; der Überblick, was neu ist, hätte keinen Ort.</p></div>`, {
  shell: true, title: 'Wertpapiere', subtitle: 'Suchen, filtern und pflegen des investierbaren Universums.', active: 'nav-securities', css: NEWS_CSS, width: 1220, extraNav: NAV_B
}), 'B — verteilt');

// The security's pane: a "Nachrichten" tab, and the markers on its chart.
const SEC = ALL[3]; // Tech-Einzelwert A
const tabs = ['Übersicht', 'Diagramm', 'Transaktionen', 'Trades', 'Kurse', 'Bestände', 'Klassifizierungen', 'Research', 'Nachrichten', 'Prognosen', 'Termine'];
const paneHead = (active) => `<aside class="detail-pane" style="position: static; max-height: none;"><header class="detail-pane-head"><div class="detail-pane-head__title"><span class="security-logo security-logo--lg security-logo--initial" aria-hidden="true">T</span><div><h2>Tech-Einzelwert A</h2><p class="detail-pane-sub">XS0000000001 · TEA · EUR · Letzter 142,18 (06.11.2026)</p></div></div></header><nav class="detail-pane-tabs" role="tablist">${tabs.map((t) => `<button type="button" role="tab" class="detail-pane-tab${t === active ? ' is-active' : ''}${t === 'Nachrichten' ? ' area-tab-new' : ''}">${t}</button>`).join('')}</nav>`;
const stories = `<section class="detail-tab-panel mock-pad"><div class="news-health"><span class="news-chip">7 Tage: 6 Meldungen · 2 primär</span><span class="news-chip">höchste Materialität 2</span></div><div class="data-table-wrapper"><table class="data-table"><thead><tr><th>Meldung</th><th>Quelle</th><th>Zeit</th><th>Einordnung</th><th></th></tr></thead><tbody>
<tr><td><span class="news-title">Quartalsbericht: Umsatz über Plan</span><span class="news-sub">3 Quellen zur selben Meldung</span></td><td>ir.example <span class="news-tier news-tier--primary">primary</span></td><td>08.11. 07:00</td><td><span class="news-label"><span class="news-tone news-tone--pos"></span>earnings · 2 <span class="news-machine">maschinell</span></span></td><td><button class="button-ghost" type="button">Ins Research-Log</button></td></tr>
<tr><td><span class="news-title">Vorstand bestätigt Ausblick</span><span class="news-sub">im Research-Log seit 01.11.</span></td><td>ir.example <span class="news-tier news-tier--primary">primary</span></td><td>31.10. 16:45</td><td><span class="news-label"><span class="news-tone"></span>guidance · 1 <span class="news-machine">maschinell</span></span></td><td><span class="news-chip">übernommen</span></td></tr>
<tr><td><span class="news-title">Analyst sieht Gegenwind im Kerngeschäft</span></td><td>wire.example <span class="news-tier">secondary</span></td><td>30.10. 11:20</td><td><span class="news-label">ohne Einordnung</span></td><td><button class="button-ghost" type="button">Ins Research-Log</button></td></tr>
</tbody></table></div><p class="hint">„Ins Research-Log“ öffnet das Notizformular, vorausgefüllt aus der Meldung: Überschrift aus dem Titel, Ereignisart und Tonalität aus der Einordnung, Quelle und Datum aus der besten Quelle; erst das Speichern macht daraus eine Notiz (NFR-10). Nur eine Notiz mit Überschrift erscheint im Diagramm.</p></section></aside>`;
B1.tab = sized(writeFrame('01d-wertpapier-nachrichten', paneHead('Nachrichten') + stories, { css: NEWS_CSS, width: 1000 }), 'Wertpapier — Tab Nachrichten');

function secChart(markers) {
  const vals = SEC.prices;
  const hi = Math.max(...vals) * 1.03, lo = Math.min(...vals) * 0.97;
  const y = (v) => B - (B - T) * (v - lo) / (hi - lo);
  const d = 'M' + vals.map((v, i) => `${xAt(i).toFixed(1)},${y(v).toFixed(1)}`).join('L');
  const area = d + `L${R},${B}L${L},${B}Z`;
  const ticks = [lo, lo + (hi - lo) / 3, lo + 2 * (hi - lo) / 3, hi];
  const ax = axes(ticks, y, (t) => nf2.format(t));
  const tx = [[60, 'buy'], [175, 'sell']].map(([i, t]) => {
    const x = xAt(i), yy = y(vals[i]);
    return t === 'buy' ? `<path class="tx-marker tx-buy" d="M${x - 5},${yy + 11}L${x + 5},${yy + 11}L${x},${yy + 3}Z"></path>` : `<path class="tx-marker tx-sell" d="M${x - 5},${yy - 11}L${x + 5},${yy - 11}L${x},${yy - 3}Z"></path>`;
  }).join('');
  const notes = [[40, 'pos', 'Produktstart'], [118, 'neg', 'Klage eingereicht'], [205, 'neu', 'Ausblick bestätigt'], [246, 'pos', 'Umsatz über Plan']];
  const pins = notes.map(([i, tone, h]) => {
    const x = xAt(i).toFixed(1);
    if (markers === 'pins') return `<g class="note-pin note-pin--${tone}"><line x1="${x}" x2="${x}" y1="${T + 9}" y2="${y(vals[i]).toFixed(1)}"></line><circle cx="${x}" cy="${T + 5}" r="5.5"></circle><title>${h}</title></g>`;
    const c = tone === 'pos' ? '#16a34a' : tone === 'neg' ? '#dc2626' : '#6b7280';
    return `<circle class="note-dot" cx="${x}" cy="${y(vals[i]).toFixed(1)}" r="5" fill="${c}"><title>${h}</title></circle>`;
  }).join('');
  const tip = markers === 'pins' ? `<div class="chart-tip" style="left: 690px; top: 40px;"><strong>Umsatz über Plan</strong><br>earnings · positiv · 08.11.2026<br><span class="hint">Research-Log · Quelle ir.example</span></div>` : '';
  return `<div class="chart-frame" data-axis-inside="" style="--chart-upx: 1.6; position: relative;"><svg class="security-chart" role="img" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid meet" width="100%">${ax.grid}<path class="quote-area" d="${area}"></path><path class="quote-line" d="${d}"></path>${tx}${pins}${ax.labels}</svg>${tip}</div><div class="chart-toggles"><label><input type="checkbox" checked> Transaktionen</label><label class="mock-new"><input type="checkbox" checked> Notizen</label></div>`;
}
B1.pins = sized(writeFrame('01e-marker-a', paneHead('Diagramm') + `<section class="detail-tab-panel mock-pad">${secChart('pins')}</section></aside>`, { css: NEWS_CSS, width: 1000 }), 'A — Nadeln am oberen Rand');
B1.dots = sized(writeFrame('01f-marker-b', paneHead('Diagramm') + `<section class="detail-tab-panel mock-pad">${secChart('dots')}</section></aside>`, { css: NEWS_CSS, width: 1000 }), 'B — Punkte auf der Linie');

board('01-news-view.html', 'Sprint 28 — Board 01: die Nachrichten-Ansicht (ADR-0056 §10) und die Notiz-Marker (A2)', 1260,
  `<div class="mock-pickbar"><p><strong>Was die Entscheidung festlegt (ADR-0056 §10, A2):</strong> der Betreiber sieht, was der Agent sieht, ohne eigene Logik — Feeds und ihr Zustand, die Meldungen eines Wertpapiers auf seiner Seite, die Warteschlange „nicht zugeordnet · mehrdeutig“ mit einer Aktion zum Zuordnen. Im Diagramm erscheinen nur Research-Notizen mit Überschrift, nie eine Meldung.</p><p><strong>Was dieses Board vorschlägt (Plan D-5, per Kommentar umkehrbar):</strong> A, eine eigene Seite „Nachrichten“ in der Hauptnavigation mit drei Reitern; ein Reiter „Nachrichten“ am Wertpapier mit „Ins Research-Log“; die Marker als Nadeln am oberen Rand, eingefärbt nach Tonalität, abschaltbar wie die Transaktionen. Gestrichelt: was neu ist (nur auf dem Board).</p></div>`,
  [
    { title: 'A — eine Seite „Nachrichten“: Meldungen', note: 'Oben der Zustand in einer Zeile (news.health), dann die Warteschlange mit Zuordnen (news.assign; ein maschineller Vorschlag steht daneben, ordnet aber nie selbst zu), dann der Überblick je Wertpapier (news.digest). Was der Digest ausblendet, sagt er in der letzten Zeile.', frames: [B1.page], recommended: true },
    { title: 'A — Feeds und Quellen', note: 'Je Feed die Felder von news.health; die Quellen mit ihrer Stufe. Anlegen, Ändern und Löschen von Feeds und Quellen bleibt in diesem Sprint bei API und Agent; die Seite zeigt sie.', frames: [B1.feeds], recommended: true },
    { title: 'B — verteilt, ohne eigene Seite', note: 'Feeds unter „Verwaltung“, die Warteschlange als Filter der Wertpapierliste. Billiger, aber der Überblick „was ist neu“ hätte keinen Ort, und der Betreiber sähe nicht, was der Agent im Digest sieht.', frames: [B1.b] },
    { title: 'Am Wertpapier: ein Reiter „Nachrichten“', note: 'Die Geschichten des Wertpapiers (news.list), je Zeile Quelle, Stufe, Zeit und Einordnung mit dem Hinweis „maschinell“; „Ins Research-Log“ ist die Übernahme aus ADR-0056 §8 als Formular, dieselbe Schreiboperation wie notes.append mit cluster_id.', frames: [B1.tab], recommended: true },
    { title: 'Marker A — Nadeln am oberen Rand', note: 'Eine Nadel je Notiz mit Überschrift an ihrem as_of, Farbe nach Tonalität (grün, rot, grau); die gestrichelte Linie führt zum Kurs. Kollidiert nicht mit den Kauf- und Verkaufsdreiecken auf der Linie. Abschaltbar („Notizen“). Der Tooltip zeigt Überschrift, Ereignisart, Tonalität, Datum. Bleibt im Privatsphäre-Modus, weil er keinen Betrag zeigt.', frames: [B1.pins], recommended: true },
    { title: 'Marker B — Punkte auf der Linie', note: 'Ruhiger, aber Punkte auf der Linie überdecken die Transaktionsdreiecke und den Kurs am selben Tag.', frames: [B1.dots] },
  ]);

// ===========================================================================
// Board 05 — #1415, the currency_mismatch set on the Overview and as a filter

const DQ = { dq: fs.readFileSync(path.join(__dirname, 'dq-line.html'), 'utf8'), chips: fs.readFileSync(path.join(__dirname, 'dq-chips.html'), 'utf8') };
const dqLine = DQ.dq.replace(/<button[^>]*data-note__more[\s\S]*?<\/button>/, '');
const NEW_CLAUSE = '<span aria-hidden="true"> · </span><a class="mock-new" href="#" data-role="dq-currency-mismatch">2 Wertpapiere, deren Anbieter eine andere Währung meldet als ihre eigene</a> <span data-effect-of="dq-currency-mismatch">— ihre Kurse sind womöglich in der falschen Währung gespeichert; gehalten ist ihr Wert in der Summe oben daher falsch</span>';
const dqAfter = dqLine.replace(/(<span data-effect-of="dq-implausible-quote">[^<]*<\/span>)/, '$1' + NEW_CLAUSE);
const chipsAfter = DQ.chips.replace(/(<button type="button" id="sec-chip-missing_fx"[\s\S]*?<\/button>)/, '$1 <button type="button" id="sec-chip-currency_mismatch" class="filter-chip mock-new" aria-pressed="false"> Währung abweichend </button>');
const DQ_CSS = '.data-note--clamped .data-note__text, .data-note__actions { max-height: none !important; -webkit-line-clamp: unset !important; }';
const B5 = {};
B5.before = sized(writeFrame('05a-dq-heute', `<div class="mock-pad">${dqLine}</div>`, { css: DQ_CSS, width: 1000 }), 'Übersicht — heute');
B5.after = sized(writeFrame('05b-dq-neu', `<div class="mock-pad">${dqAfter}</div>`, { css: DQ_CSS, width: 1000 }), 'Übersicht — neu');
B5.chips = sized(writeFrame('05c-chip-neu', `<div class="mock-pad">${chipsAfter}</div>`, { css: '', width: 1000 }), 'Wertpapiere — Filter, neu');
board('05-currency-mismatch.html', 'Sprint 28 — Board 05: die Menge „Währung abweichend“ (#1415)', 1040,
  `<div class="mock-pickbar"><p><strong>Was entschieden ist (OQ-2 der Triage vom 2026-11-07):</strong> jede Synchronisierung speichert die Währung, die der Anbieter für das Wertpapier meldet; eine neue Datenqualitätsmenge hält jedes Wertpapier, dessen gemeldete Währung von seiner eigenen abweicht, ohne Benchmarks und ausgemusterte, und zählt auf der Übersicht mit den anderen.</p><p><strong>Was dieses Board festlegt (Plan D-6):</strong> eine Klausel mehr in der Problemzeile der Übersicht, nach der unplausiblen Kursreihe, mit ihrer Wirkung auf die Summe; ein Filter-Chip „Währung abweichend“ neben „Kein Wechselkurs“, der die Liste auf die Menge filtert. Keine neue Fläche.</p></div>`,
  [
    { title: '① Übersicht, heute', note: 'Die Problemzeile der Datenqualität, wie gebaut (Review-Instanz, synthetischer Seed).', frames: [B5.before] },
    { title: '② Übersicht, neu', note: 'Die neue Klausel, gestrichelt. Der Link öffnet Wertpapiere mit dem Filter.', frames: [B5.after], recommended: true },
    { title: '③ Wertpapiere, der Filter-Chip', note: 'Wie die anderen Mengen ein Chip; aktiv zeigt er nur die abweichenden Wertpapiere.', frames: [B5.chips], recommended: true },
  ]);

// ===========================================================================
// Board 06 — the stacked chart in the privacy mode (amends FR-53 / I22's 100 %)

const PRIV_CSS = '.mock-privacy-on { display: inline-flex; gap: 6px; align-items: center; margin: 0 0 10px; padding: 3px 10px; border-radius: 999px; font-size: 12px; font-weight: 650; color: var(--color-accent); background: var(--color-accent-soft); border: 1px solid var(--color-accent); }';
const privBands = withShares([...roots, cashBand, unclBand]).sort(bySize);
// Today: each day's positive bands scaled to 100 %.
const pctBands = privBands.map((b) => ({ ...b, values: b.values.map((v, i) => {
  const pos = privBands.reduce((a, x) => a + Math.max(0, x.values[i]), 0);
  return pos > 0 ? Math.max(0, v) / pos : 0;
}) }));
const start = privBands.reduce((a, x) => a + x.values[0], 0);
const indexed = privBands.map((b) => ({ ...b, values: b.values.map((v) => v / start) }));
const pctAxis = (t) => nf0.format(Math.round(t * 100)) + ' %';
const privacyLine = '<span class="mock-privacy-on">Privatsphäre-Modus an</span>';
const B6 = {};
B6.today = sized(writeFrame('06a-privat-heute', `<div class="mock-pad">${privacyLine}${modeSeg('Wert (EUR)')}${bar({ crumbs: ['Alle Kategorien'], level: 'Kategorien' })}${figure(stackSvg(pctBands, { axis: pctAxis }), legend('Kategorie', privBands, { privacy: true }), 'Heute: im Privatsphäre-Modus ein 100-%-Stapel; jeder Tag auf 100 % gestreckt, so dass Einzahlungen, Kursverluste und das Wachstum des Ganzen aus dem Bild verschwinden.')}</div>`, { css: PRIV_CSS, width: 1000 }), 'heute — 100-%-Stapel');
B6.after = sized(writeFrame('06b-privat-neu', `<div class="mock-pad">${privacyLine}${modeSeg('Wert (EUR)')}${bar({ crumbs: ['Alle Kategorien'], level: 'Kategorien' })}${figure(stackSvg(indexed, { axis: pctAxis }), legend('Kategorie', privBands, { privacy: true }), 'Neu: dieselbe Form wie ohne den Modus. Die Achse zeigt den Wert in Prozent des Gesamtwerts am ersten Tag des Zeitraums (100 %), wie die Linie „Wert (%)“ des Modus schon heute; kein Betrag in Achse, Legende oder Tooltip.')}</div>`, { css: PRIV_CSS, width: 1000 }), 'neu — Form wie ohne Modus');
board('06-privacy-stack.html', 'Sprint 28 — Board 06: der gestapelte Chart im Privatsphäre-Modus', 1040,
  `<div class="mock-pickbar"><p><strong>Was du am 2026-11-08 gesagt hast:</strong> im Wert-Modus mit Kategorien soll der Chart im Privatsphäre-Modus genauso aussehen wie ohne, nur ohne Euro-Beträge; aus der Form allein kann niemand schätzen, ob es 10.000 oder 10 Millionen sind. Das ändert FR-53 und D-4 von Sprint 27 („die Privatsphäre zeichnet einen 100-%-Stapel“).</p><p><strong>Was dieses Board festlegt (Amendment D-A2):</strong> die Achse in Prozent des Gesamtwerts am ersten Tag, wie die Regel aus Sprint 26 für jede Euro-Achse („indexiert auf den Start des Zeitraums“) und die Linie „Wert (%)“; die Legende ohne die Spalte Wert, mit Anteil und Veränderung; der Tooltip ohne Betrag. Gilt für jede Ebene und jeden Filter.</p></div>`,
  [
    { title: '① Heute', note: 'Der 100-%-Stapel: jeder Tag gleich hoch, die Bänder als Anteile.', frames: [B6.today] },
    { title: '② Neu', note: 'Die Form des Wert-Charts bleibt; nur die Beträge verschwinden.', frames: [B6.after], recommended: true },
  ]);

console.log('wrote frames/ and boards 01 to 06');
