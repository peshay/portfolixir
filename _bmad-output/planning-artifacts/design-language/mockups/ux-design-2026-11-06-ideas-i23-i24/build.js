// Idea boards for I23 (a stacked chart with levels) and I24 (what a market
// dip hit, and what it spared), drawn on 2026-11-06 while the ideas were
// being triaged, so the owner can see the shapes before the conversation
// that works them out.
//
// Unlike the sprint boards, these frames are not captured from the review
// instance: neither surface exists yet, so the charts are drawn here as
// inline SVG from SYNTHETIC series generated below (a seeded random walk).
// The page chrome around them uses the app's own classes and links the real
// priv/static/app.css, so the controls, panels and tokens are the shipped
// ones. Every name is generic and every figure is synthetic; the shock
// windows carry public market dates only, with invented moves.
//
// Usage:
//   node build.js    # writes 01-stacked-chart.html and 02-dip-bars.html
//   node render.js   # renders both to PNG, light and dark
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Synthetic data

function rng(seed) {
  // mulberry32: deterministic, so a rebuild draws the same board
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20261106);
const gauss = () => {
  let u = 0, v = 0;
  while (u === 0) u = rand();
  while (v === 0) v = rand();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
};

// The app's category palette in tree order (portfolio_live.ex
// @category_palette) and its cash colour (@cash_color).
const CATS = [
  { key: 'welt', name: 'Aktien Welt', color: '#2563eb', secs: [
    { n: 'MSCI World ETF', v: 38000, beta: 1.0, vol: 0.004 },
    { n: 'S&P 500 ETF', v: 16000, beta: 1.1, vol: 0.005 }] },
  { key: 'em', name: 'Schwellenländer', color: '#0d9488', secs: [
    { n: 'Emerging Markets ETF', v: 7000, beta: 1.15, vol: 0.007, buyAt: 128, buy: 4000 }] },
  { key: 'einzel', name: 'Einzelwerte', color: '#d97706', secs: [
    { n: 'Tech-Einzelwert A', v: 7000, beta: 1.7, vol: 0.016 },
    { n: 'Industrie-Einzelwert B', v: 5000, beta: 1.2, vol: 0.01 },
    { n: 'Versorger-Einzelwert C', v: 4000, beta: 0.45, vol: 0.006 }] },
  { key: 'anl', name: 'Anleihen', color: '#db2777', secs: [
    { n: 'Staatsanleihen ETF', v: 12000, beta: -0.12, vol: 0.002 }] },
  { key: 'roh', name: 'Rohstoffe', color: '#65a30d', secs: [
    { n: 'Gold ETC', v: 6000, beta: 0.05, vol: 0.007 }] },
  { key: 'krypto', name: 'Krypto', color: '#7c3aed', secs: [
    { n: 'Bitcoin', v: 4500, beta: 1.9, vol: 0.025 }] },
  { key: 'cash', name: 'Cash', color: '#0ea5e9', secs: [
    { n: 'Verrechnungskonto', v: 5000, beta: 0, vol: 0, cash: true }] },
];

// Business days of one year, 07.11.2025 to 06.11.2026.
const DATES = [];
for (let d = new Date(Date.UTC(2025, 10, 7)); d <= new Date(Date.UTC(2026, 10, 6)); d.setUTCDate(d.getUTCDate() + 1)) {
  const wd = d.getUTCDay();
  if (wd !== 0 && wd !== 6) DATES.push(new Date(d));
}
const N = DATES.length;
// The market factor, with a correction in spring and a two-day sell-off at
// the very end (the "Abverkauf" of the owner's example).
const MARKET = DATES.map((_, i) => {
  let r = 0.00045 + 0.0075 * gauss();
  if (i >= 95 && i < 108) r -= 0.006;
  if (i === N - 2) r = -0.021;
  if (i === N - 1) r = -0.017;
  return r;
});
for (const c of CATS) for (const s of c.secs) {
  s.values = []; s.flows = [];
  let v = s.v;
  for (let i = 0; i < N; i++) {
    let flow = 0;
    if (i > 0 && !s.cash) {
      let r = s.beta * MARKET[i] + s.vol * gauss() + 0.0001;
      if (s.n === 'Gold ETC' && i >= N - 2) r = 0.006; // gold rises in the sell-off
      v *= 1 + r;
    }
    if (s.buyAt === i) { v += s.buy; flow = s.buy; }
    if (s.cash && i === 128) { v -= 4000; flow = -4000; } // the EM purchase is paid from cash
    s.values.push(v); s.flows.push(flow);
  }
  s.cat = c;
}
for (const c of CATS) {
  c.values = DATES.map((_, i) => c.secs.reduce((a, s) => a + s.values[i], 0));
  c.flows = DATES.map((_, i) => c.secs.reduce((a, s) => a + s.flows[i], 0));
}
const TOTAL = DATES.map((_, i) => CATS.reduce((a, c) => a + c.values[i], 0));

// ---------------------------------------------------------------------------
// Formatting

const nf0 = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const eur = (x) => nf0.format(Math.round(x)) + ' €';
const pct = (x) => (x > 0 ? '+' : x < 0 ? '−' : '') + nf1.format(Math.abs(x)) + ' %';
const signedEur = (x) => (x > 0 ? '+' : x < 0 ? '−' : '') + nf0.format(Math.abs(Math.round(x))) + ' €';
const MONTHS = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

function shade(hex, t) {
  // t < 0 darkens, t > 0 lightens towards white
  const n = parseInt(hex.slice(1), 16);
  let r = n >> 16, g = (n >> 8) & 255, b = n & 255;
  const f = (c) => Math.round(t >= 0 ? c + (255 - c) * t : c * (1 + t));
  return '#' + [f(r), f(g), f(b)].map((c) => c.toString(16).padStart(2, '0')).join('');
}

// ---------------------------------------------------------------------------
// Charts

function niceTicks(min, max, count) {
  const span = max - min || 1;
  const step0 = span / count;
  const mag = Math.pow(10, Math.floor(Math.log10(step0)));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((s) => s >= step0);
  const ticks = [];
  for (let t = Math.ceil(min / step) * step; t <= max + 1e-9; t += step) ticks.push(t);
  return ticks;
}

function xLabels(x) {
  const out = [];
  let last = -1;
  DATES.forEach((d, i) => {
    if (d.getUTCMonth() !== last && d.getUTCDate() <= 7) {
      last = d.getUTCMonth();
      if (i > 3) out.push(`<text x="${x(i).toFixed(1)}" y="0" text-anchor="middle">${MONTHS[last]}</text>`);
    }
  });
  return out.join('');
}

// series: [{ name, color, values[] }], bottom first. mode: 'value' | 'share' | 'contrib' | 'line'
function areaChart(series, { mode = 'value', w = 700, h = 270, mark = [], highlight = null, dimOthers = false } = {}) {
  const pad = { l: 64, r: 12, t: 12, b: 26 };
  const iw = w - pad.l - pad.r, ih = h - pad.t - pad.b;
  const x = (i) => pad.l + (i / (N - 1)) * iw;
  let layers, lo, hi;
  if (mode === 'contrib') {
    // each band: the series' cumulative result since day 0, flows removed;
    // positives stack upwards from 0, negatives downwards
    const res = series.map((s) => {
      let flows = 0;
      return s.values.map((v, i) => { flows += i ? s.flows[i] : 0; return v - s.values[0] - flows; });
    });
    const posBase = new Array(N).fill(0), negBase = new Array(N).fill(0);
    layers = res.map((r) => r.map((v, i) => {
      if (v >= 0) { const y0 = posBase[i]; posBase[i] += v; return [y0, posBase[i]]; }
      const y0 = negBase[i]; negBase[i] += v; return [y0, negBase[i]];
    }));
    lo = Math.min(...negBase); hi = Math.max(...posBase);
    const m = (hi - lo) * 0.06; lo -= m; hi += m;
  } else {
    const base = new Array(N).fill(0);
    const totals = DATES.map((_, i) => series.reduce((a, s) => a + s.values[i], 0));
    layers = series.map((s) => s.values.map((v, i) => {
      const val = mode === 'share' ? (v / totals[i]) * 100 : v;
      const y0 = base[i]; base[i] += val; return [y0, base[i]];
    }));
    if (mode === 'share') { lo = 0; hi = 100; } else { lo = 0; hi = Math.max(...base) * 1.04; }
    if (mode === 'line') { lo = Math.min(...totals) * 0.96; hi = Math.max(...totals) * 1.03; }
  }
  const y = (v) => pad.t + ih - ((v - lo) / (hi - lo)) * ih;
  const ticks = mode === 'share' ? [0, 25, 50, 75, 100] : niceTicks(lo, hi, 4);
  const fmtTick = (t) => mode === 'share' ? `${t} %` : (mode === 'contrib' && t > 0 ? '+' : '') + nf0.format(t / 1000) + ' T€';
  let svg = `<svg class="mock-chart" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" role="img">`;
  svg += `<g class="mock-grid">` + ticks.map((t) => `<line x1="${pad.l}" x2="${w - pad.r}" y1="${y(t).toFixed(1)}" y2="${y(t).toFixed(1)}"/>`).join('') + `</g>`;
  svg += `<g class="mock-ylab">` + ticks.map((t) => `<text x="${pad.l - 8}" y="${(y(t) + 4).toFixed(1)}" text-anchor="end">${fmtTick(t)}</text>`).join('') + `</g>`;
  if (mode === 'line') {
    const totals = DATES.map((_, i) => series.reduce((a, s) => a + s.values[i], 0));
    const d = totals.map((v, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join('');
    svg += `<path d="${d}L${x(N - 1)},${y(lo)}L${x(0)},${y(lo)}Z" fill="var(--color-accent)" opacity="0.10"/>`;
    svg += `<path d="${d}" fill="none" stroke="var(--color-accent)" stroke-width="2"/>`;
  } else {
    layers.forEach((L, k) => {
      const s = series[k];
      const top = L.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p[1]).toFixed(1)}`).join('');
      const bot = L.map((p, i) => [i, p[0]]).reverse().map(([i, v]) => `L${x(i).toFixed(1)},${y(v).toFixed(1)}`).join('');
      const dim = dimOthers && highlight && s.name !== highlight;
      svg += `<path d="${top}${bot}Z" fill="${s.color}" fill-opacity="${dim ? 0.18 : 0.78}" stroke="${s.color}" stroke-width="${mode === 'contrib' ? 0 : 1}" stroke-opacity="${dim ? 0.3 : 1}"/>`;
    });
    if (mode === 'contrib') svg += `<line class="mock-zero" x1="${pad.l}" x2="${w - pad.r}" y1="${y(0).toFixed(1)}" y2="${y(0).toFixed(1)}"/>`;
  }
  // markers: [{ i, label }]
  for (const m of mark) {
    svg += `<line class="mock-marker" x1="${x(m.i).toFixed(1)}" x2="${x(m.i).toFixed(1)}" y1="${pad.t}" y2="${pad.t + ih}"/>`;
    svg += `<text class="mock-marker-label" x="${(x(m.i) + (m.anchor === 'end' ? -5 : 5)).toFixed(1)}" y="${pad.t + 12}" text-anchor="${m.anchor || 'start'}">${esc(m.label)}</text>`;
  }
  svg += `<g class="mock-xlab" transform="translate(0 ${h - 8})">${xLabels(x)}</g>`;
  svg += `</svg>`;
  return svg;
}

// ---------------------------------------------------------------------------
// Shared chrome

const seg = (opts, active, extra = '') => `<div class="segmented-control${extra}" role="group">${opts.map((o) => `<button type="button" class="segmented-control__option${o === active ? ' is-active' : ''}">${esc(o)}</button>`).join('')}</div>`;
const PERIODS = seg(['1M', '3M', '6M', 'YTD', '1J', '3J', '5J', 'Max'], '1J');
const tag = (kind, label) => `<span class="mock-tag mock-tag--${kind}">${label}</span>`;

function legend(rows, { title = 'Kategorie', sortedBy = 'Wert', showEur = true, clickable = true } = {}) {
  return `<table class="mock-legend"><thead><tr><th>${title}</th>${showEur ? `<th class="num">Wert</th>` : ''}<th class="num">Anteil</th><th class="num">${sortedBy === 'chg' ? 'Veränd. ▾' : 'Veränd.'}</th></tr></thead><tbody>` +
    rows.map((r) => `<tr class="${r.active ? 'is-active' : ''}${r.dim ? ' is-dim' : ''}"><td><span class="mock-sw" style="background:${r.color}"></span>${clickable && r.drill ? `<a>${esc(r.name)}</a> <span class="mock-drill">›</span>` : esc(r.name)}</td>${showEur ? `<td class="num">${eur(r.value)}</td>` : ''}<td class="num">${nf1.format(r.share)} %</td><td class="num ${r.chg < 0 ? 'neg' : 'pos'}">${pct(r.chg)}</td></tr>`).join('') +
    `</tbody></table>`;
}

function rowFor(item, total) {
  // the period change of a series, flows removed (money-weighted enough for a legend)
  const flows = item.flows.slice(1).reduce((a, b) => a + b, 0);
  const start = item.values[0];
  const end = item.values[N - 1];
  return { name: item.name || item.n, color: item.color, value: end, share: (end / total) * 100, chg: ((end - flows - start) / start) * 100 };
}

const CSS = `
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 1120px; margin: 0 auto 28px; }
.mock-head h1 { margin: 0 0 6px; font-size: 20px; }
.mock-board > h2 { margin: 0 0 4px; font-size: 16px; font-weight: 760; }
.mock-board > h2 small { font-weight: 500; color: var(--color-text-muted); margin-left: 6px; font-size: 12.5px; }
p.mock-note { margin: 0 0 12px; max-width: 115ch; font-size: 12.5px; color: var(--color-text-muted); line-height: 1.5; }
.mock-board b { color: var(--color-text); }
.mock-pickbar { margin: 0 0 18px; padding: 10px 14px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 12.5px; line-height: 1.5; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-synth { display: inline-block; padding: 1px 8px; border-radius: 999px; background: #fef3c7; color: #92400e; font-size: 11px; font-weight: 700; letter-spacing: .04em; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; }
.mock-tag--before { color: var(--color-text-muted); background: var(--color-bg-muted); }
.mock-tag--rec { color: var(--color-on-accent, #fff); background: var(--color-accent); }
.mock-tag--alt { color: var(--color-accent); background: var(--color-accent-soft); }
.mock-tag--no { color: var(--color-text-muted); background: var(--color-bg-muted); text-decoration: line-through; }
.mock-fig { margin: 0 0 20px; }
.mock-frame { border: 1px solid var(--color-border-strong); border-radius: 10px; background: var(--color-bg-elevated); box-shadow: var(--shadow-panel); padding: 14px 16px 12px; }
.mock-frame .section-head { display: flex; flex-wrap: wrap; gap: 8px 14px; align-items: center; justify-content: space-between; margin: 0 0 10px; }
.mock-frame .section-head h2 { margin: 0; font-size: 16px; }
.mock-frame .section-head-controls { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 3px; border-radius: 8px; }
.mock-subbar { display: flex; flex-wrap: wrap; gap: 8px 14px; align-items: center; margin: 0 0 10px; font-size: 12.5px; color: var(--color-text-muted); }
.mock-subbar label { font-weight: 600; color: var(--color-text-muted); margin-right: 4px; }
.mock-select { display: inline-flex; align-items: center; gap: 6px; min-height: 30px; padding: 4px 10px; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg); color: var(--color-text); font-size: 12.5px; }
.mock-crumbs { font-size: 13px; font-weight: 600; }
.mock-crumbs a { color: var(--color-accent); text-decoration: none; }
.mock-crumbs span { color: var(--color-text-muted); margin: 0 6px; }
.mock-body { display: grid; grid-template-columns: 700px 1fr; gap: 16px; align-items: start; }
.mock-chart { display: block; background: var(--color-chart-surface); border-radius: 6px; }
.mock-grid line { stroke: var(--color-border); stroke-width: 1; }
.mock-ylab text, .mock-xlab text { fill: var(--color-text-muted); font: 11px var(--font-sans); }
.mock-zero { stroke: var(--color-text); stroke-width: 1.2; stroke-dasharray: 4 3; }
.mock-marker { stroke: var(--color-text-muted); stroke-width: 1; stroke-dasharray: 3 3; }
.mock-marker-label { fill: var(--color-text-muted); font: 600 10.5px var(--font-sans); }
table.mock-legend { width: 100%; border-collapse: collapse; font-size: 12.5px; }
table.mock-legend th { text-align: left; font-size: 10.5px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); padding: 4px 6px; border-bottom: 1px solid var(--color-border); }
table.mock-legend td { padding: 5px 6px; border-bottom: 1px solid var(--color-border); white-space: nowrap; }
table.mock-legend .num { text-align: right; font-variant-numeric: tabular-nums; }
table.mock-legend tr.is-active td { background: var(--color-selected, var(--color-accent-soft)); }
table.mock-legend tr.is-dim td { opacity: .45; }
table.mock-legend a { color: var(--color-text); text-decoration: underline dotted; text-underline-offset: 3px; }
.mock-drill { color: var(--color-accent); font-weight: 700; }
.mock-sw { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 7px; vertical-align: -1px; }
.neg { color: var(--color-danger); } .pos { color: var(--color-positive); }
.mock-basis { margin: 8px 0 0; font-size: 11.5px; color: var(--color-text-muted); }
.mock-why { margin: 8px 0 0; padding: 8px 12px; border-left: 3px solid var(--color-accent); background: var(--color-bg-muted); font-size: 12.5px; line-height: 1.5; color: var(--color-text-muted); }
.mock-why p { margin: 0 0 5px; } .mock-why p:last-child { margin: 0; }
.mock-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
.mock-pair .mock-body { grid-template-columns: 1fr; }
.mock-pair > * { min-width: 0; }
.mock-pair .mock-chart { width: 100%; height: auto; }
.mock-pair .section-head-controls .segmented-control[role=group]:last-child { display: none; }
.mock-chips { display: flex; flex-wrap: wrap; gap: 8px; margin: 0 0 12px; }
.mock-chip { display: inline-flex; flex-direction: column; gap: 1px; padding: 6px 12px; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg); font-size: 12.5px; }
.mock-chip small { color: var(--color-text-muted); font-size: 11px; }
.mock-chip.is-active { border-color: var(--color-accent); background: var(--color-accent-soft); box-shadow: inset 0 0 0 1px var(--color-accent); }
.mock-chip--add { justify-content: center; color: var(--color-accent); border-style: dashed; font-weight: 600; }
.mock-bars { display: grid; grid-template-columns: 210px 1fr 74px 92px; gap: 0 10px; align-items: center; font-size: 12.5px; }
.mock-bars .h { font-size: 10.5px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); padding: 0 0 5px; border-bottom: 1px solid var(--color-border); }
.mock-bars .c { padding: 5px 0; border-bottom: 1px solid var(--color-border); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mock-bars .num { text-align: right; font-variant-numeric: tabular-nums; }
.mock-bars .cat td { font-weight: 700; }
.mock-bars .c.catrow { font-weight: 700; }
.mock-bars .c.sub { padding-left: 18px; color: var(--color-text-muted); }
.mock-bars .c.gap { color: var(--color-text-muted); font-style: italic; }
.mock-track { position: relative; height: 16px; }
.mock-track .bar { position: absolute; top: 2px; height: 12px; border-radius: 3px; }
.mock-track .zero { position: absolute; top: -6px; bottom: -6px; width: 1px; background: var(--color-text); opacity: .6; }
.mock-track .bm { position: absolute; top: -6px; bottom: -6px; width: 0; border-left: 2px dashed var(--color-text-muted); }
.mock-axis { position: relative; height: 16px; font-size: 10.5px; color: var(--color-text-muted); }
.mock-axis span { position: absolute; transform: translateX(-50%); white-space: nowrap; }
.mock-bm-key { display: inline-block; width: 0; height: 12px; border-left: 2px dashed var(--color-text-muted); margin: 0 6px 0 2px; vertical-align: -2px; }
table.mock-heat { border-collapse: separate; border-spacing: 3px; font-size: 12.5px; }
table.mock-heat th { font-size: 10.5px; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; color: var(--color-text-muted); padding: 2px 6px; text-align: center; }
table.mock-heat th:first-child { text-align: left; }
table.mock-heat td { padding: 6px 10px; text-align: right; font-variant-numeric: tabular-nums; border-radius: 4px; min-width: 92px; }
table.mock-heat td:first-child { text-align: left; min-width: 190px; padding-left: 0; }
table.mock-heat td.na { color: var(--color-text-muted); font-style: italic; text-align: center; background: var(--color-bg-muted); }
.mock-switch-row { display: flex; gap: 8px; align-items: center; }
.mock-mask { display: inline-block; width: 4.4em; height: 0.7em; border-radius: 999px; background: linear-gradient(90deg, color-mix(in oklab, currentColor 32%, transparent), color-mix(in oklab, currentColor 14%, transparent)); filter: blur(0.08em); }
`;

function page(title, body) {
  return `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js. Idea board: the charts are drawn as inline SVG from
     synthetic series, the chrome uses the app's own classes and app.css.
     No script runs here. -->
<style id="board">${CSS}</style>
</head>
<body>
${body}
</body>
</html>
`;
}

// ---------------------------------------------------------------------------
// Board 01: I23, the stacked chart

function board01() {
  const total = TOTAL[N - 1];
  const bySize = [...CATS].sort((a, b) => b.values[N - 1] - a.values[N - 1]); // largest at the bottom
  const catRows = bySize.map((c) => ({ ...rowFor(c, total), drill: c.secs.length > 1 })).reverse(); // the legend reads like the stack: top band first
  const einzel = CATS.find((c) => c.key === 'einzel');
  const einzelSecs = einzel.secs.map((s, k) => ({ name: s.n, color: shade(einzel.color, [-0.25, 0.1, 0.45][k]), values: s.values, flows: s.flows }));
  const einzelTotal = einzel.values[N - 1];
  const buy = { i: 128, label: 'Kauf EM-ETF' };
  const dip = { i: N - 2, label: 'Abverkauf', anchor: 'end' };

  const head = (controls, series = ['% (TTWROR)', 'Wert (EUR)'], active = 'Wert (EUR)') => `<header class="section-head"><h2>Performance</h2><div class="section-head-controls">${seg(series, active, series.length > 2 ? ' mock-new' : '')}${PERIODS}</div></header>${controls}`;
  const levelBar = (level, crumbs, sort = 'Größe') => `<div class="mock-subbar mock-new">${crumbs}<span style="flex:1"></span><span><label>Ebene</label></span>${seg(['Gesamt', 'Kategorien', 'Einzelwerte'], level)}<span class="mock-select">Klassifikation: Anlageklassen ▾</span><span><label>Sortieren</label></span>${seg(['Größe', 'Veränderung'], sort)}</div>`;

  const today = `<figure class="mock-fig">${tag('before', 'Heute')}<div class="mock-frame">${head('')}<div class="mock-body"><div>${areaChart(CATS, { mode: 'line', mark: [buy, dip] })}</div><div><p class="mock-note" style="margin-top:8px">Eine Linie für den ganzen View. Was den Abverkauf am Ende getragen hat, zeigt erst die Beitragstabelle darunter, als Zahl, nicht im Bild.</p></div></div></div></figure>`;

  const a = `<figure class="mock-fig">${tag('rec', 'A · empfohlen · Ebene Kategorien, nach Größe gestapelt')}<div class="mock-frame">${head(levelBar('Kategorien', '<span class="mock-crumbs">Alle Kategorien</span>'))}<div class="mock-body"><div>${areaChart(bySize, { mode: 'value', mark: [buy, dip] })}<p class="mock-basis">Basis: Marktwert je Kategorie am Tagesende in EUR, Klassifikation „Anlageklassen“; Cash als eigenes Band; Veränderung ohne Ein- und Auszahlungen. Größtes Band unten; die Legende liest sich wie der Stapel, oberstes Band zuerst.</p></div><div>${legend(catRows)}<div class="mock-why"><p>Ein Klick auf eine Kategorie (› in der Legende oder auf ihr Band) öffnet sie: der Chart zeigt dann nur sie, gestapelt nach ihren Einzelwerten.</p><p>Der Kauf im Mai erscheint als <b>Stufe</b> im türkisen Band. Das ist ehrlich (der Wert stieg), aber kein Kursgewinn.</p></div></div></div></div></figure>`;

  const drillRows = einzelSecs.map((s) => ({ ...rowFor(s, einzelTotal) })).sort((p, q) => p.chg - q.chg);
  const a2 = `<figure class="mock-fig">${tag('rec', 'A · nach dem Klick auf „Einzelwerte“, sortiert nach Veränderung')}<div class="mock-frame">${head(levelBar('Einzelwerte', '<span class="mock-crumbs"><a>Alle Kategorien</a><span>›</span>Einzelwerte</span>', 'Veränderung'))}<div class="mock-body"><div>${areaChart([...einzelSecs].sort((p, q) => rowFor(q, 1).chg - rowFor(p, 1).chg), { mode: 'value', mark: [dip] })}<p class="mock-basis">Basis: Marktwert je Wertpapier der Kategorie „Einzelwerte“ in EUR; Anteil an der Kategorie. Schattierungen der Kategoriefarbe, damit man weiß, wo man ist.</p></div><div>${legend(drillRows, { title: 'Wertpapier', sortedBy: 'chg', clickable: false })}<div class="mock-why"><p>Der Brotkrumenpfad führt zurück. „Ebene: Einzelwerte“ ohne Klick auf eine Kategorie zeigt alle Wertpapiere des Views; über acht Bänder fasst der Chart die kleinsten zu „Sonstige“ zusammen.</p></div></div></div></div></figure>`;

  const b = `<div class="mock-fig">${tag('alt', 'B · dritte Ansicht „Anteil %“, 100 % gestapelt')}<div class="mock-frame">${head(levelBar('Kategorien', '<span class="mock-crumbs">Alle Kategorien</span>'), ['% (TTWROR)', 'Wert (EUR)', 'Anteil %'], 'Anteil %')}<div class="mock-body"><div>${areaChart(bySize, { mode: 'share', mark: [buy, dip] })}<p class="mock-basis">Basis: Anteil jeder Kategorie am Marktwert des Views je Tag.</p></div><div>${legend(catRows, { showEur: false })}<div class="mock-why"><p>Zeigt, wie sich die <b>Gewichte</b> verschieben, nicht die Größe. Verrät keine Beträge, passt also zum Privatsphäre-Modus (I22): dort wäre das die einzige Form.</p></div></div></div></div></div>`;

  const c = `<div class="mock-fig">${tag('alt', 'C · später: Ansicht „Beitrag“ statt Wert (eher FR-41)')}<div class="mock-frame">${head(levelBar('Kategorien', '<span class="mock-crumbs">Alle Kategorien</span>'), ['% (TTWROR)', 'Wert (EUR)', 'Beitrag'], 'Beitrag')}<div class="mock-body"><div>${areaChart(bySize, { mode: 'contrib', mark: [buy, dip] })}<p class="mock-basis">Basis: aufgelaufenes Ergebnis je Kategorie seit Periodenbeginn in EUR, ohne Käufe und Verkäufe; Bänder über und unter null; Summe = Ergebnis des Views (wie ADR-0051).</p></div><div><div class="mock-why"><p>Der Kauf erzeugt hier <b>keine</b> Stufe. Dafür liest sich ein Stapel, der in beide Richtungen wächst, schwerer. Beantwortet „wer hat das Ergebnis gemacht“, nicht „woraus besteht das Depot“.</p></div></div></div></div></div>`;

  const body = `<div class="mock-board mock-head">
<h1>Idee I23 — gestapelter Chart mit Ebenen <span class="mock-synth">SYNTHETISCHE DATEN</span></h1>
<p class="mock-note">Ideen-Board vom 06.11.2026, gezeichnet vor jeder Entscheidung. Der Performance-Abschnitt auf Vermögen › Bestände, Wert-Ansicht, Zeitraum 1J. Die gestrichelte Umrandung markiert, was neu ist. Charts als SVG aus einer synthetischen Zufallsreihe, Chrome mit den echten Klassen aus <code>app.css</code>.</p>
<div class="mock-pickbar"><p><b>Empfehlung: A</b> — eine neue Leiste über dem Chart mit <b>Ebene</b> (Gesamt · Kategorien · Einzelwerte), der Klassifikation, nach der gestapelt wird, und <b>Sortieren</b> (Größe · Veränderung). Klick auf eine Kategorie filtert und stapelt nach ihren Wertpapieren. <b>Gesamt</b> ist der heutige Chart, unverändert.</p><p><b>B</b> kommt als dritte Ansicht „Anteil %“ neben % und Wert dazu (und ist im Privatsphäre-Modus die einzige Form). <b>C</b> beantwortet eine andere Frage („wer hat das Ergebnis gemacht“) und gehört eher zur Beitragsanalyse (FR-41).</p></div>
</div>
<div class="mock-board">${today}${a}${a2}<div class="mock-pair">${b}${c}</div></div>`;
  return page('Idee I23 — gestapelter Chart mit Ebenen', body);
}

// ---------------------------------------------------------------------------
// Board 02: I24, what a dip hit

// Synthetic moves per shock window, in percent of the price at the window's
// start (today's holdings over the window's prices). null: no quotes stored.
const SHOCKS = [
  { key: 'covid', name: 'Pandemie-Crash', when: '19.02.–23.03.2020', bm: -33.9 },
  { key: 'krieg', name: 'Kriegsbeginn Ukraine', when: '16.02.–07.03.2022', bm: -9.8 },
  { key: 'zoll', name: 'Zollschock', when: '02.04.–08.04.2025', bm: -12.1 },
  { key: 'abv', name: 'Abverkauf', when: '05.–06.11.2026', bm: -3.7 },
];
const MOVES = {
  'MSCI World ETF':          { covid: -33.9, krieg: -9.8, zoll: -12.1, abv: -3.7 },
  'S&P 500 ETF':             { covid: -32.1, krieg: -8.4, zoll: -14.6, abv: -4.2 },
  'Emerging Markets ETF':    { covid: -31.4, krieg: -13.9, zoll: -10.8, abv: -4.9 },
  'Tech-Einzelwert A':       { covid: -38.7, krieg: -15.2, zoll: -22.4, abv: -8.6 },
  'Industrie-Einzelwert B':  { covid: -41.3, krieg: -12.6, zoll: -16.9, abv: -5.1 },
  'Versorger-Einzelwert C':  { covid: null,  krieg: -4.1, zoll: -6.3, abv: -1.2 },
  'Staatsanleihen ETF':      { covid: 1.8, krieg: -2.2, zoll: 0.9, abv: 0.6 },
  'Gold ETC':                { covid: -6.4, krieg: 7.9, zoll: 1.6, abv: 1.2 },
  'Bitcoin':                 { covid: -46.2, krieg: 8.3, zoll: -9.7, abv: -7.4 },
};

function heatColor(p) {
  if (p === null) return '';
  const t = Math.min(1, Math.abs(p) / 40);
  const c = p < 0 ? 'var(--color-danger)' : 'var(--color-positive)';
  return `background: color-mix(in oklab, ${c} ${Math.round(8 + t * 62)}%, transparent);${t > 0.55 ? ' color: #fff;' : ''}`;
}

function barRows(rows, { lo = -50, hi = 10, bm = null, showEur = true } = {}) {
  const pos = (v) => ((v - lo) / (hi - lo)) * 100;
  const axisTicks = [];
  for (let t = Math.ceil(lo / 10) * 10; t <= hi; t += 10) axisTicks.push(t);
  let html = `<div class="mock-bars"><div class="h">Position</div><div class="h">Bewegung im Fenster</div><div class="h num">%</div><div class="h num">${showEur ? 'EUR' : ''}</div>`;
  for (const r of rows) {
    if (r.pct === null) {
      html += `<div class="c gap${r.sub ? ' sub' : ''}">${esc(r.name)}</div><div class="c gap">keine Kurse im Fenster gespeichert</div><div class="c num gap">—</div><div class="c num gap">—</div>`;
      continue;
    }
    const z = pos(0), p = pos(r.pct);
    const left = Math.min(z, p), width = Math.abs(p - z);
    const color = r.color;
    html += `<div class="c${r.cat ? ' catrow' : ''}${r.sub ? ' sub' : ''}"><span class="mock-sw" style="background:${color}"></span>${esc(r.name)}</div>`;
    html += `<div class="c"><div class="mock-track"><div class="bar" style="left:${left}%;width:${Math.max(width, 0.4)}%;background:${r.pct < 0 ? 'var(--color-danger)' : 'var(--color-positive)'};opacity:${r.sub ? 0.55 : 0.85}"></div><div class="zero" style="left:${z}%"></div>${bm !== null ? `<div class="bm" style="left:${pos(bm)}%"></div>` : ''}</div></div>`;
    html += `<div class="c num ${r.pct < 0 ? 'neg' : 'pos'}">${pct(r.pct)}</div><div class="c num ${r.eur < 0 ? 'neg' : 'pos'}">${showEur ? signedEur(r.eur) : '<span class="mock-mask"></span>'}</div>`;
  }
  html += `<div></div><div class="mock-axis">${axisTicks.map((t) => `<span style="left:${pos(t)}%">${t > 0 ? '+' : ''}${t} %</span>`).join('')}</div><div></div><div></div></div>`;
  return html;
}

function board02() {
  const shock = SHOCKS[0];
  const secs = CATS.flatMap((c) => c.secs.filter((s) => !s.cash));
  const secRows = secs.map((s) => {
    const p = MOVES[s.n][shock.key];
    return { name: s.n, color: s.cat.color, pct: p, eur: p === null ? 0 : (s.values[N - 1] * p) / 100 };
  });
  const known = secRows.filter((r) => r.pct !== null).sort((a, b) => a.pct - b.pct);
  const posRows = [...known, ...secRows.filter((r) => r.pct === null)];

  const catRows = [];
  for (const c of CATS.filter((c) => c.key !== 'cash')) {
    const rs = c.secs.map((s) => secRows.find((r) => r.name === s.n));
    const withQ = rs.filter((r) => r.pct !== null);
    const base = c.secs.filter((s) => MOVES[s.n][shock.key] !== null).reduce((a, s) => a + s.values[N - 1], 0);
    const e = withQ.reduce((a, r) => a + r.eur, 0);
    catRows.push({ name: c.name, color: c.color, cat: true, pct: (e / base) * 100, eur: e, members: rs });
  }
  catRows.sort((a, b) => a.pct - b.pct);
  const catFlat = [];
  for (const r of catRows) {
    catFlat.push(r);
    if (r.name === 'Einzelwerte') for (const m of r.members) catFlat.push({ ...m, sub: true });
  }

  const chips = `<div class="mock-chips mock-new">${SHOCKS.map((s, k) => `<span class="mock-chip${k === 0 ? ' is-active' : ''}"><b>${esc(s.name)}</b><small>${s.when}</small></span>`).join('')}<span class="mock-chip mock-chip--add">+ Fenster festhalten</span></div>`;
  const head = (controls) => `<header class="section-head"><h2>Schock-Fenster</h2><div class="section-head-controls">${controls}</div></header>`;
  const ctrls = (level, unit = '%') => `${seg(['Positionen', 'Kategorien'], level)}${seg(['%', 'EUR'], unit)}<span class="mock-select">Bestand: heute ▾</span><span class="mock-select">Vergleich: MSCI World ▾</span>`;
  const basis = `<p class="mock-basis">Basis: heutige Bestände (06.11.2026) über die Schlusskurse vom ${shock.when.split('–')[0]}2020 bis 23.03.2020, in EUR; Kategorie = Summe ihrer Positionen mit Kursen; <span class="mock-bm-key"></span>Vergleich: MSCI World im selben Fenster (${pct(shock.bm)}). Position ohne Kurse im Fenster: ausgewiesen, nicht geschätzt.</p>`;

  const a = `<figure class="mock-fig">${tag('rec', 'A · empfohlen · Balken je Position, sortiert nach Fall')}<div class="mock-frame">${head(ctrls('Positionen'))}${chips}${barRows(posRows, { bm: shock.bm })}${basis}<div class="mock-why"><p>Rot nach links = gefallen, grün nach rechts = gestiegen. Die gestrichelte Linie ist der Markt im selben Fenster: Balken <b>kürzer</b> als die Linie heißt „weniger getroffen als der Markt“, das ist das „gar nicht betroffen“.</p><p>Die Fenster oben sind gespeicherte, benannte Zeiträume. „+ Fenster festhalten“ legt einen neuen an (Name, von, bis), von dir oder vom Agenten über die API.</p></div></div></figure>`;

  const a2 = `<figure class="mock-fig">${tag('rec', 'A · Ebene Kategorien, eine Kategorie aufgeklappt')}<div class="mock-frame">${head(ctrls('Kategorien'))}${chips}${barRows(catFlat, { bm: shock.bm })}${basis}</div></figure>`;

  const heat = `<table class="mock-heat"><thead><tr><th>Position</th>${SHOCKS.map((s) => `<th>${esc(s.name)}<br><span style="font-weight:500;text-transform:none;letter-spacing:0">${s.when}</span></th>`).join('')}</tr></thead><tbody>` +
    `<tr><td><b>MSCI World (Vergleich)</b></td>${SHOCKS.map((s) => `<td style="${heatColor(s.bm)}"><b>${pct(s.bm)}</b></td>`).join('')}</tr>` +
    secs.map((s) => `<tr><td><span class="mock-sw" style="background:${s.cat.color}"></span>${esc(s.n)}</td>${SHOCKS.map((sh) => { const p = MOVES[s.n][sh.key]; return p === null ? `<td class="na">keine Kurse</td>` : `<td style="${heatColor(p)}">${pct(p)}</td>`; }).join('')}</tr>`).join('') +
    `</tbody></table>`;
  const b = `<figure class="mock-fig">${tag('alt', 'B · Schocks vergleichen: Matrix, Position × Fenster')}<div class="mock-frame">${head(`${seg(['Positionen', 'Kategorien'], 'Positionen')}<span class="mock-select">Bestand: heute ▾</span>`)}${heat}<p class="mock-basis">Basis: heutige Bestände je Fenster; Prozent vom Schlusskurs am Fensterbeginn bis zum Fensterende; Farbe nach Stärke, Skala bis −40 %.</p><div class="mock-why"><p>Beantwortet „was fällt in <b>jedem</b> Schock, was schützt“: hier Gold im Krieg, Anleihen fast immer. Ein zweiter Schritt nach A, sobald drei, vier Fenster gespeichert sind.</p></div></div></figure>`;

  const c = `<figure class="mock-fig">${tag('no', 'C · verworfen: indexierte Linien je Position')}<div class="mock-frame"><p class="mock-note" style="margin:0">Neun Linien, auf 100 am Fensterbeginn indexiert: zeigt den Verlauf im Fenster, aber ab fünf Positionen ist nicht mehr lesbar, welche am tiefsten liegt. Der Verlauf einer einzelnen Position steht schon im Wertpapier-Chart; ein Klick auf einen Balken in A führt dorthin, mit dem Fenster als Zeitraum.</p></div></figure>`;

  const body = `<div class="mock-board mock-head">
<h1>Idee I24 — was ein Markt-Dip getroffen hat und was nicht <span class="mock-synth">SYNTHETISCHE DATEN</span></h1>
<p class="mock-note">Ideen-Board vom 06.11.2026. Ein neuer Abschnitt, zum Beispiel unter Vermögen › Performance oder als eigene Seite „Schocks“; wo er wohnt, ist offen. Die Fenster tragen öffentliche Marktdaten (Daten), die Bewegungen sind <b>erfunden</b>. Gestrichelt umrandet: die gespeicherten Schock-Fenster, das neue Objekt.</p>
<div class="mock-pickbar"><p><b>Empfehlung: A</b> — ein waagerechtes Balkendiagramm über ein gewähltes, gespeichertes Fenster, je Position oder je Kategorie (aufklappbar), sortiert nach Fall, mit der Marktlinie zum Vergleich. Prozent als Standard, EUR als Schalter.</p><p><b>Bestand: heute</b> ist der Standard („wie anfällig bin ich jetzt“); „damals“ ist der Schalter für die echten Bestände im Fenster. <b>B</b> folgt, wenn mehrere Fenster gespeichert sind. <b>C</b> ist verworfen.</p></div>
</div>
<div class="mock-board">${a}${a2}${b}${c}</div>`;
  return page('Idee I24 — was ein Markt-Dip getroffen hat', body);
}

// One element per line inside each SVG and between the board's blocks, so
// the written files stay reviewable line by line.
const lines = (html) => html
  .replace(/<svg[\s\S]*?<\/svg>/g, (svg) => svg.replace(/></g, '>\n<'))
  .replace(/<\/(figure|div|tr|table|header)></g, '</$1>\n<');
fs.writeFileSync(path.join(__dirname, '01-stacked-chart.html'), lines(board01()));
fs.writeFileSync(path.join(__dirname, '02-dip-bars.html'), lines(board02()));
console.log('wrote 01-stacked-chart.html and 02-dip-bars.html');
