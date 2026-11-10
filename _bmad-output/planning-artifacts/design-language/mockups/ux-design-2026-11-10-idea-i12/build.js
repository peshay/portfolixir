// Idea board for I12, the Bitcoin four-year cycle chart, drawn on
// 2026-11-10 at the owner's request ("kannst du auf der basis schon ein
// mock chart bauen?"), so the conversation that works it out starts from a
// picture. It is an idea board, not a sprint's planning board.
//
// Nothing here is captured from the review instance: the surface does not
// exist yet. The price line is SYNTHETIC: a seeded random walk bent through
// public anchor points (halving dates, cycle tops and lows, rounded) up to
// October 2025; everything after 2025-10-06 is invented. The chrome around
// the charts uses the app's own classes and links the real
// priv/static/app.css. No portfolio figure, name or machine detail appears.
//
// Usage:
//   node build.js    # writes the boards 01, 02 and 03
//   node render.js   # renders it to PNG, light and dark
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Synthetic series

function rng(seed) {
  // mulberry32: deterministic, so a rebuild draws the same board
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20261110);

const D = (s) => new Date(s + 'T00:00:00Z');
const DAY = 86400000;
const days = (a, b) => Math.round((b - a) / DAY);
const addDays = (a, n) => new Date(a.getTime() + n * DAY);
const fmtDate = (d) => `${String(d.getUTCDate()).padStart(2, '0')}.${String(d.getUTCMonth() + 1).padStart(2, '0')}.${d.getUTCFullYear()}`;
const fmtMonth = (d) => `${['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'][d.getUTCMonth()]} ${d.getUTCFullYear()}`;
const fmtUsd = (v) => (v >= 1000 ? (v / 1000).toLocaleString('de-DE', { maximumFractionDigits: v >= 100000 ? 0 : 1 }) + ' k' : Math.round(v).toLocaleString('de-DE')) + ' $';
const fmtPct = (v) => (v > 0 ? '+' : '−') + Math.abs(v * 100).toLocaleString('de-DE', { maximumFractionDigits: 0 }) + ' %';
const fmtX = (v) => '×' + v.toLocaleString('de-DE', { maximumFractionDigits: v >= 10 ? 0 : 1 });

// Public anchor points, rounded, until the cycle top of October 2025. The
// stored series of the default provider starts in September 2014, so the
// line does too. After 2025-10-06 every anchor is INVENTED.
const ANCHORS = [
  ['2014-09-17', 460], ['2015-01-14', 152], ['2015-08-24', 210], ['2015-12-15', 450],
  ['2016-06-17', 760], ['2016-07-09', 650], ['2016-12-31', 960], ['2017-06-12', 2600],
  ['2017-09-14', 3200], ['2017-12-17', 19650], ['2018-02-06', 6900], ['2018-05-05', 9700],
  ['2018-11-20', 4500], ['2018-12-15', 3122], ['2019-06-26', 12900], ['2019-12-17', 6600],
  ['2020-02-12', 10300], ['2020-03-12', 4900], ['2020-05-11', 8600], ['2020-10-21', 12800],
  ['2021-01-08', 40000], ['2021-04-13', 63500], ['2021-07-20', 29800], ['2021-11-10', 69000],
  ['2022-01-24', 36000], ['2022-03-28', 47500], ['2022-06-18', 19000], ['2022-11-21', 15476],
  ['2023-04-13', 30300], ['2023-09-11', 25000], ['2024-01-11', 46500], ['2024-03-13', 73000],
  ['2024-04-20', 64000], ['2024-08-05', 54000], ['2024-12-16', 106000], ['2025-04-08', 77000],
  ['2025-05-22', 111000], ['2025-08-14', 123000], ['2025-10-06', 126000],
  // invented from here on
  ['2025-11-21', 84000], ['2026-01-14', 96000], ['2026-03-20', 66000], ['2026-06-10', 74000],
  ['2026-09-08', 52000], ['2026-11-06', 61000],
].map(([d, p]) => ({ d: D(d), p }));

// Daily closes: log-linear between anchors plus a small seeded wobble that
// fades to zero at every anchor and stays strictly between its two anchors,
// so every top and low falls on an anchor's own day.
const SERIES = [];
for (let i = 0; i < ANCHORS.length - 1; i++) {
  const a = ANCHORS[i], b = ANCHORS[i + 1];
  const n = days(a.d, b.d);
  let w = 0;
  for (let k = 0; k < n; k++) {
    const t = k / n;
    w = 0.9 * w + 0.035 * (rand() - 0.5) * 2;
    const fade = Math.sin(Math.PI * t);
    const raw = Math.log(a.p) * (1 - t) + Math.log(b.p) * t + w * fade;
    // clamped between the two anchors, so every top and low is an anchor
    const lp = k === 0 ? Math.log(a.p) : Math.min(Math.max(raw, Math.log(Math.min(a.p, b.p)) + 0.01), Math.log(Math.max(a.p, b.p)) - 0.01);
    SERIES.push({ d: addDays(a.d, k), p: Math.exp(lp) });
  }
}
SERIES.push({ d: ANCHORS[ANCHORS.length - 1].d, p: ANCHORS[ANCHORS.length - 1].p });
const TODAY = D('2026-11-10');
const priceOn = (d) => {
  let best = SERIES[0];
  for (const q of SERIES) { if (q.d <= d) best = q; else break; }
  return best.p;
};

// ---------------------------------------------------------------------------
// Halvings and the cycle figures, computed the way the app would: the top is
// the highest stored close in a halving-to-halving window, the low the
// lowest close after that top inside the same window.

const HALVINGS = [
  { d: D('2012-11-28'), block: 210000, state: 'confirmed' },
  { d: D('2016-07-09'), block: 420000, state: 'confirmed' },
  { d: D('2020-05-11'), block: 630000, state: 'confirmed' },
  { d: D('2024-04-20'), block: 840000, state: 'confirmed' },
  { d: D('2028-04-14'), block: 1050000, state: 'estimated' }, // invented estimate
];
const FIRST_STORED = SERIES[0].d;

// The top and the low of a window are the peak and the trough of the
// window's maximum drawdown. The naive rule ("the highest close in the
// window") picks the wrong top for 2020-2024: the rally of March 2024 closed
// above the November 2021 top inside the same window, a month before the
// next halving.
function windowStats(from, to) {
  const inWin = SERIES.filter((q) => q.d >= from && q.d < to && q.d <= TODAY);
  if (!inWin.length) return null;
  let peak = inWin[0], best = { dd: 0, top: inWin[0], low: null };
  for (const q of inWin) {
    if (q.p > peak.p) peak = q;
    const dd = q.p / peak.p - 1;
    if (dd < best.dd) best = { dd, top: peak, low: q };
  }
  return { top: best.top, low: best.low, start: inWin[0] };
}

const CYCLES = [];
for (let i = 0; i < HALVINGS.length - 1; i++) {
  const h = HALVINGS[i], next = HALVINGS[i + 1];
  const complete = h.d >= FIRST_STORED && next.state === 'confirmed';
  const s = windowStats(h.d, next.d);
  CYCLES.push({ label: `${h.d.getUTCFullYear()}–${next.state === 'confirmed' ? next.d.getUTCFullYear() : 'heute'}`, h, next, s, complete, partial: h.d < FIRST_STORED, current: next.state !== 'confirmed' });
}
// The 2012 window starts before the stored series: its top (Dec 2013) is not
// stored, so what the window shows after 2014-09 is not its top.
const C12 = CYCLES[0], C16 = CYCLES[1], C20 = CYCLES[2], C24 = CYCLES[3];
C12.s.top = null; // not in the stored series
C12.s.low = { d: D('2015-01-14'), p: 152 };

const stored = [C16, C20];
const hToTop = [C16, C20, C24].map((c) => days(c.h.d, c.s.top.d));
const topToLow = stored.map((c) => days(c.s.top.d, c.s.low.d));
const drawdown = stored.map((c) => c.s.low.p / c.s.top.p - 1);
const topToTop = [[C16, C20], [C20, C24]].map(([a, b]) => ({ n: days(a.s.top.d, b.s.top.d), r: b.s.top.p / a.s.top.p }));
const lowToLow = [[C12, C16], [C16, C20]].map(([a, b]) => ({ n: days(a.s.low.d, b.s.low.d), r: b.s.low.p / a.s.low.p }));
const LT = [[C12.s.low, C16.s.top], [C16.s.low, C20.s.top], [C20.s.low, C24.s.top]].map(([l, t]) => ({ n: days(l.d, t.d), r: t.p / l.p }));
const TL = [[C16.s.top, C16.s.low], [C20.s.top, C20.s.low]].map(([t, l]) => ({ n: days(t.d, l.d), r: l.p / t.p - 1 }));
const min = (a) => Math.min(...a), max = (a) => Math.max(...a);

// The analog band: the past cycles' extremes applied to the current anchors.
const curTop = C24.s.top;
// The price side of a band. Every price relation has shrunk from cycle to
// cycle (drawdowns, low-to-low, top-to-top and low-to-top factors), so the
// past minimum and maximum would place the next value inside a range it has
// left every time. The band therefore runs from the last cycle's factor
// ("the shrinking stops") to that factor shrunk once more at its last rate,
// measured on the logarithm ("the shrinking goes on"). One step, no fit.
// Durations show no trend and keep the min-max of the stored cycles.
// (The first draw used min-max for prices too; board 03 records the error.)
function trendBand(factors) {
  const a = Math.log(factors[factors.length - 2]), b = Math.log(factors[factors.length - 1]);
  const last = Math.exp(b), next = Math.exp(b * (b / a));
  return [Math.min(last, next), Math.max(last, next)];
}
const minMax = (factors) => [min(factors), max(factors)];

const ddF = drawdown.map((d) => 1 + d);
const lowBand = {
  from: addDays(curTop.d, min(topToLow)), to: addDays(curTop.d, max(topToLow)),
  lo: curTop.p * trendBand(ddF)[0], hi: curTop.p * trendBand(ddF)[1], n: stored.length,
  mm: minMax(ddF).map((f) => curTop.p * f),
};
const lowSoFar = (() => { let l = null; for (const q of SERIES) if (q.d > curTop.d && q.d <= TODAY && (!l || q.p < l.p)) l = q; return l; })();
const H5 = HALVINGS[4];
// The chain estimate of the next halving is a window, not a day (invented
// here as +-10 days); the top band's time inherits it.
const H5_SPREAD = 10;
const topBand = {
  from: addDays(H5.d, min(hToTop) - H5_SPREAD), to: addDays(H5.d, max(hToTop) + H5_SPREAD),
  lo: curTop.p * trendBand(topToTop.map((x) => x.r))[0], hi: curTop.p * trendBand(topToTop.map((x) => x.r))[1], n: topToTop.length, nTime: hToTop.length,
  mm: minMax(topToTop.map((x) => x.r)).map((f) => curTop.p * f),
};

// One band per relation, each from that relation alone, so a line can run
// into the band of its own kind (board 03). They need not agree.
const ttBand = {
  from: addDays(curTop.d, min(topToTop.map((x) => x.n))), to: addDays(curTop.d, max(topToTop.map((x) => x.n))),
  lo: curTop.p * trendBand(topToTop.map((x) => x.r))[0], hi: curTop.p * trendBand(topToTop.map((x) => x.r))[1], n: topToTop.length,
  mm: minMax(topToTop.map((x) => x.r)).map((f) => curTop.p * f),
};
const lastLow = C20.s.low;
const llBand = {
  from: addDays(lastLow.d, min(lowToLow.map((x) => x.n))), to: addDays(lastLow.d, max(lowToLow.map((x) => x.n))),
  lo: lastLow.p * trendBand(lowToLow.map((x) => x.r))[0], hi: lastLow.p * trendBand(lowToLow.map((x) => x.r))[1], n: lowToLow.length,
  mm: minMax(lowToLow.map((x) => x.r)).map((f) => lastLow.p * f),
};
// The combined band of one event (owner, 2026-11-10): the hull of every
// relation's band for it, in time and in price. Where the price ranges of
// the parts overlap, the combined band is shaded darker ("both ways agree").
// No average and no intersection: the parts share their data, so combining
// them adds no evidence, and an intersection is narrow by coincidence.
function combine(parts, names) {
  const lo = Math.max(...parts.map((b) => b.lo)), hi = Math.min(...parts.map((b) => b.hi));
  return {
    from: new Date(Math.min(...parts.map((b) => b.from))), to: new Date(Math.max(...parts.map((b) => b.to))),
    lo: Math.min(...parts.map((b) => b.lo)), hi: Math.max(...parts.map((b) => b.hi)),
    agree: lo < hi ? [lo, hi] : null, parts, names,
  };
}
const lowComb = combine([lowBand, llBand], ['top_to_low', 'low_to_low']);
const topComb = combine([topBand, ttBand], ['halving_to_top', 'top_to_top']);

const ltSpread = { n: [min(LT.map((x) => x.n)), max(LT.map((x) => x.n))], r: trendBand(LT.map((x) => x.r)), mm: minMax(LT.map((x) => x.r)) };

// A band's state is read from the stored closes, never written by hand.
function bandState(b) {
  if (TODAY < b.from) return 'offen';
  const inWin = SERIES.filter((q) => q.d >= b.from && q.d <= b.to);
  const hit = inWin.some((q) => q.p >= b.lo && q.p <= b.hi);
  if (TODAY <= b.to) return hit ? 'Fenster läuft, Kurs im Band' : 'Fenster läuft';
  return hit ? 'Fenster vorbei, Kurs war im Band' : 'Fenster vorbei, nicht erreicht';
}
// ---------------------------------------------------------------------------
// Drawing helpers

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const DEFAULT_VIEW = {
  W: 1080, H: 430, x0: D('2014-07-01'), x1: D('2030-03-01'), pMin: 70, pMax: 800000,
  pTicks: [100, 1000, 10000, 100000],
  xTicks: Array.from({ length: 16 }, (_, i) => ({ d: D(2015 + i + '-01-01'), l: String(2015 + i) })),
  conn: {}, connLabels: true, halvingWindow: false, label: 'Bitcoin, Kursverlauf mit Zyklen',
};

// The connections run between stored tops and lows only; none is extended
// past the last confirmed point (that would be a projection by line).
const ZIG = [C12.s.low, C16.s.top, C16.s.low, C20.s.top, C20.s.low, C24.s.top];
const TOPS = [C16.s.top, C20.s.top, C24.s.top];
const LOWS = [C12.s.low, C16.s.low, C20.s.low];

function timeChart(opts = {}) {
  const v = { ...DEFAULT_VIEW, ...opts };
  const { W, H, x0, x1 } = v;
  const L = 62, R = 18, T = 18, B = 34;
  const yMin = Math.log10(v.pMin), yMax = Math.log10(v.pMax);
  const X = (d) => L + ((d - x0) / (x1 - x0)) * (W - L - R);
  const Y = (p) => T + (1 - (Math.log10(p) - yMin) / (yMax - yMin)) * (H - T - B);
  const inX = (d) => d >= x0 && d <= x1;
  const clip = `clip-${v.id || 'main'}`;
  let s = `<svg class="mock-chart" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${v.label}">`;
  s += `<defs><clipPath id="${clip}"><rect x="${L}" y="${T - 14}" width="${W - L - R}" height="${H - T - B + 14}"/></clipPath></defs>`;
  s += '<g class="mock-grid">';
  for (const p of v.pTicks) s += `<line x1="${L}" x2="${W - R}" y1="${Y(p)}" y2="${Y(p)}"/>`;
  s += '</g><g class="mock-ylab">';
  for (const p of v.pTicks) s += `<text x="${L - 8}" y="${Y(p) + 4}" text-anchor="end">${fmtUsd(p)}</text>`;
  s += '</g><g class="mock-xlab">';
  for (const t of v.xTicks) s += `<text x="${X(t.d)}" y="${H - 12}" text-anchor="middle">${t.l}</text>`;
  s += `</g><g clip-path="url(#${clip})">`;
  // today
  s += `<line class="cy-today" x1="${X(TODAY)}" x2="${X(TODAY)}" y1="${T}" y2="${H - B}"/><text class="cy-today-l" x="${X(TODAY) + 4}" y="${H - B - 6}">heute</text>`;
  // halvings
  for (const h of HALVINGS) {
    if (!inX(h.d)) continue;
    const cls = h.state === 'estimated' ? 'cy-halving is-est' : 'cy-halving';
    if (h.state === 'estimated' && v.halvingWindow) {
      const a = X(addDays(h.d, -H5_SPREAD)), b = X(addDays(h.d, H5_SPREAD));
      s += `<rect class="cy-halving-win" x="${a}" y="${T}" width="${b - a}" height="${H - T - B}"/>`;
    }
    s += `<line class="${cls}" x1="${X(h.d)}" x2="${X(h.d)}" y1="${T}" y2="${H - B}"/>`;
    s += h.state === 'estimated'
      ? `<text class="cy-halving-l" x="${X(h.d) - 4}" y="${H - B - 22}" text-anchor="end">Halving ≈ ${fmtMonth(h.d)} (Schätzung${v.halvingWindow ? ' ± ' + H5_SPREAD + ' T' : ''})</text>`
      : `<text class="cy-halving-l" x="${X(h.d) + 4}" y="${T + 12}">Halving ${fmtDate(h.d)}</text>`;
  }
  // the combined bands; with the per-relation cones on, they are outlines
  const outline = v.cones ? ' is-outline' : '';
  const lb = { x: X(lowComb.from), w: Math.max(6, X(lowComb.to) - X(lowComb.from)), y: Y(lowComb.hi), h: Y(lowComb.lo) - Y(lowComb.hi) };
  s += `<rect class="cy-band cy-band--low${bandState(lowComb).startsWith('Fenster vorbei') ? ' is-past' : ''}${outline}" x="${lb.x}" y="${lb.y}" width="${lb.w}" height="${lb.h}"/>`;
  if (lowComb.agree && !v.cones) s += `<rect class="cy-agree" x="${lb.x}" y="${Y(lowComb.agree[1])}" width="${lb.w}" height="${Y(lowComb.agree[0]) - Y(lowComb.agree[1])}"/>`;
  if (!v.cones) {
    // four short lines, ending at the band's left edge, below the price line
    const ll = [`Tief-Band ${fmtUsd(lowComb.lo)}–${fmtUsd(lowComb.hi)}`, `${fmtDate(lowComb.from).slice(0, 6)}–${fmtDate(lowComb.to)}`,
      ...(lowComb.agree ? [`beide Wege ${fmtUsd(lowComb.agree[0])}–${fmtUsd(lowComb.agree[1])}`] : []), bandState(lowComb)];
    ll.forEach((t, k) => { s += `<text class="cy-band-l" x="${lb.x - 6}" y="${lb.y + lb.h + 14 + 12 * k}" text-anchor="end">${t}</text>`; });
  }
  const tb = { x: X(topComb.from), w: Math.max(6, X(topComb.to) - X(topComb.from)), y: Y(topComb.hi), h: Y(topComb.lo) - Y(topComb.hi) };
  s += `<rect class="cy-band cy-band--top${outline}" x="${tb.x}" y="${tb.y}" width="${tb.w}" height="${tb.h}"/>`;
  if (!v.cones) {
    s += `<text class="cy-band-l" x="${tb.x - 6}" y="${tb.y + 4}" text-anchor="end">Top-Band ${fmtUsd(topComb.lo)}–${fmtUsd(topComb.hi)}</text>`;
    s += `<text class="cy-band-l" x="${tb.x - 6}" y="${tb.y + 17}" text-anchor="end">${fmtDate(topComb.from)}–${fmtDate(topComb.to)}</text>`;
    if (v.bandDetail) s += `<text class="cy-band-l" x="${tb.x + tb.w}" y="${tb.y + tb.h + 14}" text-anchor="end">Zeit: Halving → Top n = ${topBand.nTime}, Top → Top n = ${ttBand.n} · Kurs: Top → Top n = ${ttBand.n}</text>`;
  }
  // cones: from the last confirmed point of a relation into its own band;
  // a cone, never one line, because a band has no single target point
  const cone = (a, r, cls, label, below) => {
    const xa = X(a.d), ya = Y(a.p), xl = X(r.from), xr = Math.max(xl + 6, X(r.to)), yt = Y(r.hi), yb = Y(r.lo);
    let out = `<polygon class="cy-cone ${cls}" points="${xa},${ya} ${xl},${yt} ${xr},${yt} ${xr},${yb} ${xl},${yb}"/>`;
    out += `<line class="cy-cone-edge ${cls}" x1="${xa}" y1="${ya}" x2="${xl}" y2="${yt}"/><line class="cy-cone-edge ${cls}" x1="${xa}" y1="${ya}" x2="${xl}" y2="${yb}"/>`;
    out += `<rect class="cy-band ${cls}" x="${xl}" y="${yt}" width="${xr - xl}" height="${yb - yt}"/>`;
    if (label) {
      // to the right of the band, or, near the right edge, below it and ending at its right side
      const right = xr + 200 < W - R;
      const lx = right ? xr + 6 : xr, ly = right ? (below ? yb + 14 : yt - 18) : yb + 14;
      const anchor = right ? '' : ' text-anchor="end"';
      out += `<text class="cy-cone-l ${cls}" x="${lx}" y="${ly}"${anchor}>${label[0]}</text><text class="cy-cone-l ${cls}" x="${lx}" y="${ly + 12}"${anchor}>${label[1]}</text>`;
    }
    return out;
  };
  if (v.cones) {
    if (v.cones.zig) s += cone(curTop, lowBand, 'cy-cone--zig is-past', [`Top→Tief ${fmtUsd(lowBand.lo)}–${fmtUsd(lowBand.hi)}`, `${fmtDate(lowBand.from)}–${fmtDate(lowBand.to)} · n = ${lowBand.n}`], true);
    if (v.cones.tt) s += cone(curTop, ttBand, 'cy-cone--tt', [`Top–Top ${fmtUsd(ttBand.lo)}–${fmtUsd(ttBand.hi)}`, `${fmtDate(ttBand.from)}–${fmtDate(ttBand.to)} · n = ${ttBand.n}`]);
    if (v.cones.ll) s += cone(lastLow, llBand, 'cy-cone--ll', [`Tief–Tief ${fmtUsd(llBand.lo)}–${fmtUsd(llBand.hi)}`, `${fmtDate(llBand.from)}–${fmtDate(llBand.to)} · n = ${llBand.n}`], true);
  }
  // the line
  const vis = SERIES.filter((q) => inX(q.d));
  const step = (x1 - x0) / DAY > 3000 ? 3 : 1;
  const pts = vis.filter((_, i) => i % step === 0).map((q) => `${X(q.d).toFixed(1)},${Y(q.p).toFixed(1)}`).join(' ');
  const ptsInv = vis.filter((q) => q.d > curTop.d).filter((_, i) => i % step === 0).map((q) => `${X(q.d).toFixed(1)},${Y(q.p).toFixed(1)}`).join(' ');
  s += `<polyline class="quote-line cy-line" fill="none" points="${pts}"/>`;
  s += `<polyline class="cy-line-invented" fill="none" points="${ptsInv}"/>`;
  // connections
  const seg = (a, b, cls, label, dy) => {
    let out = `<line class="cy-conn ${cls}" x1="${X(a.d)}" y1="${Y(a.p)}" x2="${X(b.d)}" y2="${Y(b.p)}"/>`;
    if (v.connLabels && label) {
      const mx = (X(a.d) + X(b.d)) / 2, my = (Y(a.p) + Y(b.p)) / 2 + dy;
      out += `<text class="cy-conn-l ${cls}" x="${mx}" y="${my}" text-anchor="middle">${label}</text>`;
    }
    return out;
  };
  if (v.conn.zig) for (let i = 0; i < ZIG.length - 1; i++) {
    const a = ZIG[i], b = ZIG[i + 1], up = b.p > a.p;
    const lab = `${days(a.d, b.d)} T · ${up ? fmtX(b.p / a.p) : fmtPct(b.p / a.p - 1)}`;
    s += seg(a, b, 'cy-conn--zig', lab, up ? -6 : 14);
  }
  if (v.conn.tt) for (let i = 0; i < TOPS.length - 1; i++) s += seg(TOPS[i], TOPS[i + 1], 'cy-conn--tt', `Top–Top ${days(TOPS[i].d, TOPS[i + 1].d)} T · ${fmtX(TOPS[i + 1].p / TOPS[i].p)}`, -22);
  if (v.conn.ll) for (let i = 0; i < LOWS.length - 1; i++) s += seg(LOWS[i], LOWS[i + 1], 'cy-conn--ll', `Tief–Tief ${days(LOWS[i].d, LOWS[i + 1].d)} T · ${fmtX(LOWS[i + 1].p / LOWS[i].p)}`, 26);
  // tops and lows
  const mark = (q, kind, label) => {
    if (!inX(q.d)) return '';
    const x = X(q.d), y = Y(q.p);
    const tri = kind === 'top' ? `${x - 5},${y - 9} ${x + 5},${y - 9} ${x},${y - 2}` : `${x - 5},${y + 9} ${x + 5},${y + 9} ${x},${y + 2}`;
    const ly = kind === 'top' ? y - 14 : y + 21;
    // a label near the left edge starts at its marker instead of centring on it
    const anchor = x - L < 50 ? `x="${x - 4}" text-anchor="start"` : `x="${x}" text-anchor="middle"`;
    return `<polygon class="cy-mark cy-mark--${kind}" points="${tri}"/><text class="cy-mark-l" ${anchor} y="${ly}">${label}</text>`;
  };
  for (const c of [C16, C20, C24]) s += mark(c.s.top, 'top', `${fmtUsd(c.s.top.p)} · ${fmtMonth(c.s.top.d)}`);
  for (const c of [C12, C16, C20]) s += mark(c.s.low, 'low', `${fmtUsd(c.s.low.p)} · ${fmtMonth(c.s.low.d)}`);
  s += mark(lowSoFar, 'low', `bisher ${fmtUsd(lowSoFar.p)} · vorläufig`);
  s += '</g></svg>';
  return s;
}

function alignedChart() {
  const W = 1080, H = 360, L = 62, R = 18, T = 18, B = 34;
  const xMax = 1460;
  const yMin = Math.log10(0.2), yMax = Math.log10(60);
  const X = (n) => L + (n / xMax) * (W - L - R);
  const Y = (r) => T + (1 - (Math.log10(r) - yMin) / (yMax - yMin)) * (H - T - B);
  let s = `<svg class="mock-chart" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="Zyklen übereinander, ab Halving ausgerichtet">`;
  s += '<g class="mock-grid">';
  for (const r of [0.25, 1, 4, 16]) s += `<line x1="${L}" x2="${W - R}" y1="${Y(r)}" y2="${Y(r)}"/>`;
  s += '</g><g class="mock-ylab">';
  for (const r of [0.25, 1, 4, 16]) s += `<text x="${L - 8}" y="${Y(r) + 4}" text-anchor="end">${fmtX(r)}</text>`;
  s += '</g><g class="mock-xlab">';
  for (let n = 0; n <= 1460; n += 365) s += `<text x="${X(n)}" y="${H - 12}" text-anchor="${n === 0 ? 'start' : n === 1460 ? 'end' : 'middle'}">${n === 0 ? 'Halving' : 'Tag ' + n}</text>`;
  s += '</g>';
  s += `<line class="cy-one" x1="${L}" x2="${W - R}" y1="${Y(1)}" y2="${Y(1)}"/>`;
  // band for the current low, in cycle days
  const base24 = priceOn(C24.h.d);
  const bx = X(days(C24.h.d, lowComb.from)), bw = Math.max(6, X(days(C24.h.d, lowComb.to)) - bx);
  const by = Y(lowComb.hi / base24), bh = Y(lowComb.lo / base24) - by;
  s += `<rect class="cy-band cy-band--low is-past" x="${bx}" y="${by}" width="${bw}" height="${bh}"/>`;
  if (lowComb.agree) s += `<rect class="cy-agree" x="${bx}" y="${Y(lowComb.agree[1] / base24)}" width="${bw}" height="${Y(lowComb.agree[0] / base24) - Y(lowComb.agree[1] / base24)}"/>`;
  s += `<text class="cy-band-l" x="${bx + bw + 6}" y="${by + bh / 2 + 4}">Tief-Band (zwei Wege, je n = 2)</text>`;
  const lines = [
    { c: C12, cls: 'cy-c12', name: '2012 (Kurse erst ab Tag ' + days(C12.h.d, FIRST_STORED) + ')' },
    { c: C16, cls: 'cy-c16', name: '2016' },
    { c: C20, cls: 'cy-c20', name: '2020' },
    { c: C24, cls: 'cy-c24', name: '2024 (laufend)' },
  ];
  const base12 = 12; // the 2012 halving close is public, not stored
  for (const { c, cls, name } of lines) {
    const base = c === C12 ? base12 : priceOn(c.h.d);
    const end = c.current ? TODAY : c.next.d;
    const pts = SERIES.filter((q, i) => q.d >= c.h.d && q.d < end && i % 3 === 0)
      .map((q) => `${X(days(c.h.d, q.d)).toFixed(1)},${Y(q.p / base).toFixed(1)}`).join(' ');
    s += `<polyline class="cy-aligned ${cls}" fill="none" points="${pts}"><title>${name}</title></polyline>`;
    if (c.s.top) {
      const x = X(days(c.h.d, c.s.top.d)), y = Y(c.s.top.p / base);
      s += `<circle class="cy-dot ${cls}" cx="${x}" cy="${y}" r="4"/><text class="cy-mark-l" x="${x}" y="${y - 9}" text-anchor="middle">Top Tag ${days(c.h.d, c.s.top.d)}</text>`;
    }
    if (c.s.low && c !== C12) {
      const x = X(days(c.h.d, c.s.low.d)), y = Y(c.s.low.p / base);
      s += `<circle class="cy-dot ${cls}" cx="${x}" cy="${y}" r="4"/><text class="cy-mark-l" x="${x}" y="${y + 17}" text-anchor="middle">${c.current ? 'Tief bisher, Tag ' : 'Tief Tag '}${days(c.h.d, c.s.low.d)}${c.current ? ' (vorläufig)' : ''}</text>`;
    }
  }
  s += `<line class="cy-today" x1="${X(days(C24.h.d, TODAY))}" x2="${X(days(C24.h.d, TODAY))}" y1="${T}" y2="${H - B}"/>`;
  s += '</svg>';
  s += '<div class="cy-legend">' + lines.map(({ cls, name }) => `<span><i class="${cls}"></i>${name}</span>`).join('') + '<span>y: Kurs ÷ Schlusskurs am Halving-Tag, log</span></div>';
  return s;
}

function cycleTable() {
  const row = (label, vals, basis) => `<tr><td>${label}</td>${vals.map((v) => `<td class="num">${v}</td>`).join('')}<td class="cy-basis">${basis}</td></tr>`;
  const r = [];
  r.push(row('Halving → Top', [`—`, `${hToTop[0]} T`, `${hToTop[1]} T`, `${hToTop[2]} T`], `n = 3 · 2012 nicht gespeichert`));
  r.push(row('Top → Tief', [`—`, `${TL[0].n} T · ${fmtPct(TL[0].r)}`, `${TL[1].n} T · ${fmtPct(TL[1].r)}`, `offen`], `n = 2`));
  r.push(row('Tief → Top', [`${LT[0].n} T · ${fmtX(LT[0].r)}`, `${LT[1].n} T · ${fmtX(LT[1].r)}`, `${LT[2].n} T · ${fmtX(LT[2].r)}`, `—`], `n = 3 · Faktor fällt jeden Zyklus`));
  r.push(row('Top → Top', [`—`, `—`, `${topToTop[0].n} T · ${fmtX(topToTop[0].r)}`, `${topToTop[1].n} T · ${fmtX(topToTop[1].r)}`], `n = 2`));
  r.push(row('Tief → Tief', [`—`, `${lowToLow[0].n} T · ${fmtX(lowToLow[0].r)}`, `${lowToLow[1].n} T · ${fmtX(lowToLow[1].r)}`, `—`], `n = 2`));
  r.push(row('Tief vor dem nächsten Halving', [`${days(C12.s.low.d, C16.h.d)} T`, `${days(C16.s.low.d, C20.h.d)} T`, `${days(C20.s.low.d, C24.h.d)} T`, `—`], `n = 3`));
  return `<table class="mock-legend cy-table"><thead><tr><th>Strecke</th><th class="num">Zyklus 2012</th><th class="num">2016</th><th class="num">2020</th><th class="num">2024</th><th>Basis</th></tr></thead><tbody>${r.join('')}</tbody></table>`;
}

const iso = (d) => d.toISOString().slice(0, 10);
function payload() {
  const j = {
    security_id: 'sec_btc',
    series: { source: 'stored closes', currency: 'USD', first_close: '2014-09-17', gaps: 'none filled; a missing day is skipped' },
    halvings: HALVINGS.slice(-2).map((h) => ({
      block: h.block, date: h.d.toISOString().slice(0, 10), confirmed: h.state === 'confirmed',
      source_quality: h.state === 'confirmed' ? 'primary' : 'unverified',
      ...(h.state === 'estimated' ? { basis: 'tip height + (1050000 - tip) x mean block time of the last 2016 blocks', checked_at: '2026-11-10' } : {}),
    })),
    cycles: [C20, C24].map((c) => ({
      halving: c.h.d.toISOString().slice(0, 10), complete: !c.current,
      top: { date: c.s.top.d.toISOString().slice(0, 10), close: c.s.top.p.toFixed(2) },
      low: c.current ? null : { date: c.s.low.d.toISOString().slice(0, 10), close: c.s.low.p.toFixed(2) },
    })),
    projection: {
      kind: 'analog_band', not_a_forecast: true,
      next_low: {
        window: [lowComb.from, lowComb.to].map(iso), close: [lowComb.lo.toFixed(0), lowComb.hi.toFixed(0)],
        agree: lowComb.agree && lowComb.agree.map((x) => x.toFixed(0)), status: 'window_passed_not_reached',
        parts: lowComb.parts.map((b, i) => ({ relation: lowComb.names[i], window: [b.from, b.to].map(iso), close: [b.lo.toFixed(0), b.hi.toFixed(0)], n: b.n })),
        low_so_far: { date: iso(lowSoFar.d), close: lowSoFar.p.toFixed(2) },
      },
      next_top: {
        window: [topComb.from, topComb.to].map(iso), close: [topComb.lo.toFixed(0), topComb.hi.toFixed(0)], status: 'pending',
        parts: topComb.parts.map((b, i) => ({ relation: topComb.names[i], window: [b.from, b.to].map(iso), close: [b.lo.toFixed(0), b.hi.toFixed(0)] })),
      },
      basis: 'each part: time from min to max of the stored cycles\' intervals, price from the last cycle\'s factor to that factor shrunk once more at its last rate, on the logarithm; the band is the hull of its parts, agree is where their prices overlap; time: min and max of the stored cycles\' intervals; price: from the last cycle\'s factor to that factor shrunk once more at its last rate, on the logarithm; applied to the current cycle\'s anchors; no fit, no line between the ends',
    },
    chain_source: { url: 'https://mempool.space/api', fallback: 'https://blockstream.info/api', last_ok: '2026-11-10T06:00:00Z', stale: false },
  };
  return esc(JSON.stringify(j, null, 2));
}

// ---------------------------------------------------------------------------
// The page

const BOARD_CSS = fs.readFileSync(path.join(__dirname, 'board.css'), 'utf8');

const html = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Idee I12 — Bitcoin-Vierjahreszyklus</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js. Idea board: the charts are inline SVG from a
     synthetic series; the chrome uses the app's own classes and app.css.
     No script runs here. -->
<style id="board">
${BOARD_CSS}</style>
</head>
<body>
<div class="mock-board mock-head">
  <h1>Idee I12 · Bitcoin-Vierjahreszyklus <span class="mock-synth">SYNTHETISCH</span></h1>
  <p class="mock-note">Ideen-Board vom 10.11.2026, kein Sprint-Board. Die Kurslinie ist eine Zufallsreihe, durch öffentliche, gerundete Eckpunkte gezogen (Halvings, Zyklus-Tops und -Tiefs bis Okt. 2025). <b>Alles nach dem 06.10.2025 ist erfunden</b> (gestrichelt), ebenso das geschätzte Halving-Datum 2028. Alle Kennzahlen sind aus dieser Reihe gerechnet, so wie die App sie rechnen würde.</p>
  <div class="mock-pickbar">
    <p><b>Empfohlen (A):</b> kein eigener Bildschirm, sondern ein Schalter <b>„Zyklen“</b> im Wertpapier-Chart. Er erscheint nur bei einem Wertpapier mit mindestens zwei Halving-Ereignissen und blendet Halvings, Tops, Tiefs und die Analog-Bänder ein; ein zweiter Modus <b>„Ausgerichtet“</b> legt die Zyklen ab Halving übereinander.</p>
    <p><b>Gegen den langen Weg</b> (Wertpapiere → Bitcoin → Chart): eine kleine Karte <b>„Bitcoin-Zyklus“</b> auf dem Dashboard öffnet das Chart mit eingeschaltetem Schalter, ein Klick. <b>B</b> (eigene Seite „Zyklen“ in der Navigation) ist die Alternative, wenn mehr als ein Wertpapier Halvings bekommt.</p>
    <p><b>Agent:</b> dieselben Zahlen über <code>GET /api/v1/securities/:id/cycles</code> und das MCP-Tool <code>get_security_cycles</code>, bei jedem Lesen aus gespeicherten Kursen und Ereignissen gerechnet, mit Rechenbasis und n.</p>
  </div>
</div>

<section class="mock-board">
  <span class="mock-tag mock-tag--rec">A · empfohlen</span>
  <h2>Wertpapier-Chart mit Schalter „Zyklen“ <small>Zeitachse, Log-Skala, 2014 bis 2030</small></h2>
  <p class="mock-note">Halvings als senkrechte Linien (gestrichelt: geschätzt), Tops ▲ und Tiefs ▼ mit Datum und Kurs, das <b>Tief-Band</b> (abgelaufen: das Fenster ist vorbei, das Band ist ausgegraut, und sein Stand, getroffen oder nicht, wird aus den Kursen gelesen) und das <b>Top-Band</b> nach dem nächsten Halving. Jedes Band umfasst alle Wege, die zum selben Ereignis führen (Board 03: Top → Tief und Tief → Tief für das Tief); wo sich ihre Kursbereiche decken, ist es dunkler. Ein Band ist ein Rechteck: in der Zeit kleinster bis größter Abstand der gespeicherten Zyklen; im Kurs vom Faktor des letzten Zyklus bis zu diesem Faktor, noch einmal so stark geschrumpft wie zuletzt, denn jeder Kursfaktor ist bisher von Zyklus zu Zyklus kleiner geworden. Keine Linie dazwischen.</p>
  <figure class="mock-fig">
    <div class="mock-frame">
      <div class="section-head">
        <h2>Bitcoin <small class="cy-sub">BTC-USD · Kurse ab 17.09.2014</small></h2>
        <div class="section-head-controls">
          <div class="chart-toggles">
            <button type="button" class="chart-toggle is-active">Log-Skala</button>
            <button type="button" class="chart-toggle">Transaktionen</button>
            <button type="button" class="chart-toggle">Notizen</button>
            <button type="button" class="chart-toggle">MA200</button>
            <button type="button" class="chart-toggle is-active mock-new">Zyklen</button>
          </div>
        </div>
      </div>
      <div class="mock-subbar mock-new" style="padding:6px 8px">
        <label>Zyklen</label>
        <span class="segmented-control" role="group"><button type="button" class="chart-toggle is-active">Zeitachse</button><button type="button" class="chart-toggle">Ausgerichtet</button></span>
        <span>· Bänder <b>an</b> · Kettenquelle: mempool.space, zuletzt 06:00 <span class="cy-ok">aktuell</span></span>
      </div>
      ${timeChart()}
      <p class="mock-basis">Rechenbasis: gespeicherte Tagesschlusskurse in USD; Top und Tief = Gipfel und Talsohle des größten Rückgangs im Fenster Halving bis Halving (nicht der höchste Schluss: im Fenster 2020–24 schloss der März 2024 über dem Top von 2021); Lücken werden übersprungen, nicht gefüllt. Das Halving 2012 und das Top vom Dez. 2013 liegen vor den gespeicherten Kursen (ab 09/2014); manuell nachgetragene Kurse würden den Zyklus vervollständigen. Bänder: Zeit = Min/Max der gespeicherten Zyklen; Kurs = letzter Faktor bis letzter Faktor einmal weiter geschrumpft, auf dem Logarithmus (Tief n = ${lowBand.n}, Top-Zeit n = ${topBand.nTime}, Top-Kurs n = ${topBand.n}).</p>
    </div>
  </figure>

  <span class="mock-tag mock-tag--rec">A · Modus „Ausgerichtet“</span>
  <h2>Die Zyklen übereinander <small>x: Tage seit Halving · y: Kurs ÷ Kurs am Halving-Tag</small></h2>
  <p class="mock-note">Das eigentliche Vierjahreszyklus-Chart. Der laufende Zyklus ist kräftig, die alten blass; der 2012er beginnt erst, wo die gespeicherten Kurse beginnen. Hier sieht man, was die Tabelle sagt: der <b>Zeitpunkt</b> der Tops liegt eng beieinander, die <b>Höhe</b> schrumpft jeden Zyklus.</p>
  <figure class="mock-fig"><div class="mock-frame">${alignedChart()}</div></figure>

  <h2>Die Strecken zwischen den Punkten <small>unter dem Chart, aufklappbar</small></h2>
  <figure class="mock-fig"><div class="mock-frame">${cycleTable()}
    <div class="mock-why"><p><b>Warum ein Band und kein Einzelwert:</b> mit n = 2 oder 3 ist jede einzelne Zahl eine Kurve durch zwei oder drei Punkte. Wer sich auf ein Datum und einen Kurs festlegen will, legt eine Prognose an (ADR-0055); die wird gegen die Kurse aufgelöst und für die Kalibrierung bewertet. Die App rechnet, der Mensch oder der Agent sagt an.</p></div>
  </div></figure>
</section>

<section class="mock-board">
  <div class="mock-pair mock-pair--top">
    <div>
      <span class="mock-tag mock-tag--rec">A · Abkürzung</span>
      <h2>Dashboard-Karte <small>ein Klick ins Chart</small></h2>
      <div class="mock-frame cy-card mock-new">
        <div class="section-head"><h2>Bitcoin-Zyklus</h2><a class="mock-link" href="#">Im Chart öffnen →</a></div>
        <dl class="cy-dl">
          <dt>Tag im Zyklus</dt><dd>${days(C24.h.d, TODAY)} von ≈ ${days(C24.h.d, H5.d)}</dd>
          <dt>Nächstes Halving</dt><dd>≈ ${fmtMonth(H5.d)} <small>Block 1.050.000 · Schätzung</small></dd>
          <dt>Top dieses Zyklus</dt><dd>${fmtUsd(curTop.p)} · ${fmtDate(curTop.d)}</dd>
          <dt>Tief-Band</dt><dd>${fmtUsd(lowComb.lo)}–${fmtUsd(lowComb.hi)} <small class="cy-warn">${bandState(lowComb)}</small></dd>
          <dt>Tief bisher</dt><dd>${fmtUsd(lowSoFar.p)} · ${fmtDate(lowSoFar.d)} <small>vorläufig</small></dd>
        </dl>
      </div>
    </div>
    <div>
      <span class="mock-tag mock-tag--alt">B · Alternative</span>
      <h2>Eigene Seite „Zyklen“ <small>erst sinnvoll ab zwei Wertpapieren</small></h2>
      <div class="mock-frame">
        <p class="mock-note" style="margin:0">Ein Eintrag „Zyklen“ in der Navigation, eine Zeile je Wertpapier mit Halving-Ereignissen, jede mit dem ausgerichteten Chart. Heute gäbe es genau eine Zeile; eine Seite für einen Eintrag ist ein Umweg, den A mit der Karte kürzer löst. Kommt Litecoin dazu, zeigt die Seite es <b>an Bitcoins Halvings</b> ausgerichtet, nicht an seinen eigenen (Triage I12, Punkt 6).</p>
      </div>
      <span class="mock-tag mock-tag--alt" style="margin-top:14px">Für den Agenten</span>
      <h2>Was <code>get_security_cycles</code> liefert <small>gekürzt: je zwei Halvings und Zyklen</small></h2>
      <pre class="cy-json">${payload()}</pre>
    </div>
  </div>
</section>
</body>
</html>
`;

fs.writeFileSync(path.join(__dirname, '01-cycle-chart.html'), html);
console.log('wrote 01-cycle-chart.html');

// ---------------------------------------------------------------------------
// Board 02: the connections between tops and lows, and the zoom on the bands

const RANGES = ['1M', '3M', '6M', 'YTD', '1J', '3J', '5J', 'Max'];
function frame({ range, conn, chart, note }) {
  const chip = (on, label) => `<button type="button" class="chart-toggle${on ? ' is-active' : ''}">${label}</button>`;
  return `<div class="mock-frame">
      <div class="section-head">
        <h2>Bitcoin <small class="cy-sub">BTC-USD · Kurse ab 17.09.2014</small></h2>
        <div class="section-head-controls">
          <div class="range-buttons" role="group">${RANGES.map((r) => `<button type="button" class="range-button${r === range ? ' is-active' : ''}">${r}</button>`).join('')}<button type="button" class="range-button mock-new${range === 'Zyklus' ? ' is-active' : ''}">Zyklus</button></div>
          <div class="chart-toggles"><button type="button" class="chart-toggle is-active">Log-Skala</button><button type="button" class="chart-toggle is-active">Zyklen</button></div>
        </div>
      </div>
      <div class="mock-subbar mock-new" style="padding:6px 8px">
        <label>Zyklen</label>
        <span class="segmented-control" role="group"><button type="button" class="chart-toggle is-active">Zeitachse</button><button type="button" class="chart-toggle">Ausgerichtet</button></span>
        <label style="margin-left:10px">Strecken</label>
        ${chip(conn.zig, 'Top ↔ Tief')}${chip(conn.tt, 'Top – Top')}${chip(conn.ll, 'Tief – Tief')}
        <span>· Bänder <b>an</b></span>
      </div>
      ${chart}
      ${note ? `<p class="mock-basis">${note}</p>` : ''}
    </div>`;
}

const ZOOM = {
  id: 'zoom', H: 470, x0: addDays(C24.h.d, -90), x1: addDays(topComb.to, 120), pMin: 12000, pMax: 700000,
  pTicks: [20000, 50000, 100000, 200000, 500000],
  xTicks: ['2024-07-01', '2025-01-01', '2025-07-01', '2026-01-01', '2026-07-01', '2027-01-01', '2027-07-01', '2028-01-01', '2028-07-01', '2029-01-01', '2029-07-01', '2030-01-01']
    .map((d) => ({ d: D(d), l: fmtMonth(D(d)) })),
  conn: { zig: true }, halvingWindow: true, bandDetail: true, label: 'Bitcoin, Zeitraum Zyklus',
};

const html2 = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Idee I12 — Strecken und Zoom auf die Bänder</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js; see board 01 for what is synthetic. -->
<style id="board">
${BOARD_CSS}</style>
</head>
<body>
<div class="mock-board mock-head">
  <h1>Idee I12 · Strecken und Zoom auf die Bänder <span class="mock-synth">SYNTHETISCH</span></h1>
  <p class="mock-note">Zweites Ideen-Board vom 10.11.2026. Der Owner hat A und das Band übernommen („Ja find ich gut“) und zwei Dinge dazu gewollt: Linien von Top zu Top, Tief zu Tief und zwischen Top und Tief, und einen Zeitraum, in dem die Bänder groß zu sehen sind. Dieselbe synthetische Reihe wie Board 01; alles nach dem 06.10.2025 ist erfunden.</p>
  <div class="mock-pickbar">
    <p><b>Strecken, empfohlen:</b> drei Schalter in der Zyklen-Leiste. <b>Top ↔ Tief</b> ist an, wenn „Zyklen“ an ist; <b>Top – Top</b> und <b>Tief – Tief</b> sind aus und einzeln zuschaltbar. Jede Strecke trägt Tage und Veränderung, die Zahlen der Tabelle. Keine Strecke läuft über den letzten bestätigten Punkt hinaus: verlängert wäre sie eine Prognose per Lineal, und die zeigt das Band.</p>
    <p><b>Zoom, empfohlen:</b> ein Zeitraum <b>„Zyklus“</b> neben 1M bis Max, nur bei eingeschalteten Zyklen: von drei Monaten vor dem letzten Halving bis vier Monate nach dem Ende des Top-Bands. Heute enden alle Zeiträume am heutigen Tag; mit Zyklen reicht die Achse in die Zukunft, und der eigene Zeitraum darf ein Enddatum nach heute haben. Die Kursachse passt sich an Linie und Bänder an.</p>
  </div>
</div>

<section class="mock-board">
  <span class="mock-tag mock-tag--rec">Strecken · empfohlen</span>
  <h2>Nur „Top ↔ Tief“ <small>Standard, wenn Zyklen an sind</small></h2>
  <p class="mock-note">Ein Zickzack durch die Tops und Tiefs, jede Strecke mit Tagen und Veränderung. Er liest sich als Zyklusrhythmus und deckt Tief → Top und Top → Tief der Tabelle ab.</p>
  <figure class="mock-fig">${frame({ range: 'Max', conn: { zig: true }, chart: timeChart({ id: 'zig', conn: { zig: true } }) })}</figure>

  <span class="mock-tag mock-tag--alt">Alle drei an</span>
  <h2>Top ↔ Tief, Top – Top und Tief – Tief zusammen <small>so sieht „überladen“ aus</small></h2>
  <p class="mock-note">Mit allen drei Strecken und ihren Beschriftungen liegen in der Gesamtansicht drei Linienarten und sieben Beschriftungen über Kurs, Halvings und Bändern. Lesbar, aber nur, wenn man genau das sucht; deshalb sind Top – Top und Tief – Tief zuschaltbar statt Standard. Auf dem Log-Maßstab zeigt die Top – Top-Linie den Knick, den die Tabelle in Zahlen sagt: jeder Anstieg flacher als der davor.</p>
  <figure class="mock-fig">${frame({ range: 'Max', conn: { zig: true, tt: true, ll: true }, chart: timeChart({ id: 'all', conn: { zig: true, tt: true, ll: true } }) })}</figure>
</section>

<section class="mock-board">
  <span class="mock-tag mock-tag--rec">Zoom · empfohlen</span>
  <h2>Zeitraum „Zyklus“ <small>${fmtMonth(ZOOM.x0)} bis ${fmtMonth(ZOOM.x1)}, Kursachse ${fmtUsd(ZOOM.pMin)} bis ${fmtUsd(ZOOM.pMax)}</small></h2>
  <p class="mock-note">Die Bänder sind hier groß genug, um sie zu lesen. Das abgelaufene Tief-Band steht grau mit seinem Stand aus den Kursen, der dunklere Streifen ist der Bereich, in dem beide Tief-Wege übereinstimmen; das bisherige Tief steht als vorläufig daneben. Das Top-Band erbt die Unsicherheit der Halving-Schätzung: das Halving-Fenster (± ${H5_SPREAD} Tage, schraffiert) verbreitert seine Zeitspanne. Die Beschriftung nennt n getrennt für Zeit und Kurs.</p>
  <figure class="mock-fig">${frame({ range: 'Zyklus', conn: { zig: true }, chart: timeChart(ZOOM), note: `Zeitraum „Zyklus“: letztes Halving − 3 Monate bis Ende des Top-Bands + 4 Monate. Die Achse rechts von „heute“ ist leer bis auf Halving-Schätzung und Bänder; der Kurs wird nicht fortgeschrieben.` })}</figure>
  <div class="mock-why"><p><b>Im Modus „Ausgerichtet“</b> heißt derselbe Zeitraum „Tag 700–1.100“ und zeigt das Tief-Fenster der Zyklen übereinander; auf dem Board nicht gezeichnet, weil es dasselbe Prinzip ist.</p></div>
</section>
</body>
</html>
`;
fs.writeFileSync(path.join(__dirname, '02-connections-and-zoom.html'), html2.replace(/[ \t]+$/gm, ''));
console.log('wrote 02-connections-and-zoom.html');

// ---------------------------------------------------------------------------
// Board 03: the lines continue into the bands, as cones

const CONES = {
  id: 'cones', H: 500, x0: D('2022-06-01'), x1: D('2030-03-01'), pMin: 10000, pMax: 700000,
  pTicks: [20000, 50000, 100000, 200000, 500000],
  xTicks: ['2023-01-01', '2024-01-01', '2025-01-01', '2026-01-01', '2027-01-01', '2028-01-01', '2029-01-01', '2030-01-01'].map((d) => ({ d: D(d), l: d.slice(0, 4) })),
  conn: { zig: true, tt: true, ll: true }, cones: { zig: true, tt: true, ll: true }, halvingWindow: true, label: 'Bitcoin, Strecken mit Fortsetzung',
};
const bandRow = (name, b, rel, note) => `<tr><td>${name}</td><td>${rel}</td><td class="num">${fmtDate(b.from)}–${fmtDate(b.to)}</td><td class="num">${fmtUsd(b.lo)}–${fmtUsd(b.hi)}</td><td class="num">${b.n ?? '2 + 2'}</td><td>${note}</td></tr>`;

const html3 = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Idee I12 — Strecken laufen in die Bänder</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js; see board 01 for what is synthetic. -->
<style id="board">
${BOARD_CSS}</style>
</head>
<body>
<div class="mock-board mock-head">
  <h1>Idee I12 · Strecken laufen in die Bänder <span class="mock-synth">SYNTHETISCH</span></h1>
  <p class="mock-note">Drittes Ideen-Board vom 10.11.2026. Der Owner will, dass die Strecken vorausschauend weiterlaufen, „genau in diese Bänder rein“. Dieselbe synthetische Reihe; alles nach dem 06.10.2025 ist erfunden.</p>
  <div class="mock-pickbar">
    <p><b>Empfohlen:</b> jede eingeschaltete Strecke läuft vom letzten bestätigten Punkt als <b>Kegel</b> in ihr eigenes Band: zwei gestrichelte Kanten zu den Ecken des Bands, die Fläche dazwischen schwach gefüllt. Ein Kegel, keine einzelne Linie, weil ein Band keinen Zielpunkt hat; eine Linie müsste auf einen Punkt zeigen, und das wäre der Einzelwert, gegen den die Entscheidung gefallen ist.</p>
    <p><b>Jede Strecke hat ihr eigenes Band</b>, aus genau ihrer Beziehung gerechnet. Zwei Bänder für dasselbe Ereignis (zwei für das Tief, zwei für das Top) sind eine Probe: wo sie sich überdecken, stützen sich zwei Wege; wo nicht, stimmt etwas an der Regel nicht.</p>
    <p><b>Gemeinsames Band (Owner, 10.11.2026):</b> in der Standardansicht steht je Ereignis ein Band, die Hülle aller Wege dorthin; wo sich ihre Kursbereiche decken, ist es dunkler. Kein Mittelwert, keine Schnittmenge: die Wege teilen sich ihre Daten, zusammen sind sie nicht mehr Evidenz als einzeln. Mit eingeschalteten Strecken steht das gemeinsame Band als Umriss, die Kegel zeigen seine Teile.</p>
    <p><b>Korrigiert nach der Durchsicht des Owners:</b> der erste Entwurf nahm im Kurs Min bis Max der alten Zyklen, und die beiden Tief-Bänder lagen weit auseinander. Das lag nicht an den synthetischen Daten (alle Eckpunkte bis Okt. 2025 sind öffentliche Werte), sondern an der Regel; die Tabelle unten zeigt beide.</p>
  </div>
</div>

<section class="mock-board">
  <span class="mock-tag mock-tag--rec">Empfohlen · alle drei Strecken an</span>
  <h2>Strecken mit Fortsetzung <small>Juni 2022 bis März 2030</small></h2>
  <p class="mock-note"><b>Top ↔ Tief</b> (grau): vom Top Okt. 2025 in das Tief-Band aus Top → Tief, abgelaufen. <b>Tief – Tief</b> (rot): vom Tief Nov. 2022 in sein Band aus Tief → Tief. <b>Top – Top</b> (grün): vom Top Okt. 2025 in sein Band aus Top → Top. Die Fortsetzung von Tief → Top fehlt, bis das Tief dieses Zyklus bestätigt ist: ohne bestätigten Startpunkt gibt es keinen Kegel.</p>
  <figure class="mock-fig">${frame({ range: 'Zyklus', conn: { zig: true, tt: true, ll: true }, chart: timeChart(CONES) })}</figure>
  <figure class="mock-fig"><div class="mock-frame">
    <table class="mock-legend cy-table"><thead><tr><th>Band</th><th>aus</th><th class="num">Zeitfenster</th><th class="num">Kurs</th><th class="num">n</th><th>Stand</th></tr></thead><tbody>
      ${bandRow('<b>Tief, gemeinsam</b>', lowComb, 'Hülle der beiden Tief-Wege' + (lowComb.agree ? `; beide Wege: ${fmtUsd(lowComb.agree[0])}–${fmtUsd(lowComb.agree[1])}` : ''), bandState(lowComb) )}
      ${bandRow('<b>Top, gemeinsam</b>', topComb, 'Hülle der beiden Top-Wege; Kurs bei beiden aus Top → Top', bandState(topComb))}
      ${bandRow('Tief (Top ↔ Tief)', lowBand, 'Top → Tief: Tage und Rückgang', bandState(lowBand))}
      ${bandRow('Tief (Tief – Tief)', llBand, 'Tief → Tief: Tage und Faktor', bandState(llBand) )}
      ${bandRow('Top (Top – Top)', ttBand, 'Top → Top: Tage und Faktor', bandState(ttBand))}
      ${bandRow('Top (Halving)', topBand, 'Halving → Top: Tage; Top → Top: Faktor', bandState(topBand) + ' · das Band aus Board 01')}
      <tr><td>Top (Tief ↔ Top)</td><td>Tief → Top: Tage und Faktor</td><td class="num">${ltSpread.n[0]}–${ltSpread.n[1]} T nach dem Tief</td><td class="num">${fmtX(ltSpread.r[0])} bis ${fmtX(ltSpread.r[1])} des Tiefs</td><td class="num">${LT.length}</td><td>wartet auf das bestätigte Tief</td></tr>
    </tbody></table>
    <div class="mock-why">
      <p><b>Der Denkfehler des ersten Entwurfs:</b> Min bis Max der alten Zyklen nimmt an, der nächste Zyklus liege irgendwo zwischen den alten. Jeder Kursfaktor ist aber von Zyklus zu Zyklus kleiner geworden (Rückgang −87 %, −84 %, −78 %; Tief → Tief ×21, ×5; Top → Top ×3,5, ×1,8), der nächste lag also jedes Mal außerhalb der alten Spanne. Min/Max schob das Top → Tief-Band zu tief und das Tief → Tief-Band zu hoch, darum schlossen sie einander aus.</p>
      <p><b>Die Regel jetzt:</b> im Kurs vom Faktor des letzten Zyklus („das Schrumpfen hört auf“) bis zu diesem Faktor, noch einmal so stark geschrumpft wie zuletzt, auf dem Logarithmus gemessen („es geht weiter wie zuletzt“). Ein Schritt, keine Kurve. In der Zeit bleibt Min/Max: die Abstände zeigen keinen Trend. Damit überdecken sich die beiden Tief-Bänder bei ${fmtUsd(llBand.lo)} bis ${fmtUsd(lowBand.hi)}: zwei Wege, ein Bereich.</p>
      <p><b>Was das für das Top heißt:</b> das Top-Band fällt von ${fmtUsd(topBand.mm[0])}–${fmtUsd(topBand.mm[1])} auf ${fmtUsd(topBand.lo)}–${fmtUsd(topBand.hi)}. Geht das Schrumpfen weiter wie zuletzt, läge das nächste Top kaum über dem letzten. Auch das ist eine Regel aus n = 2, nicht mehr.</p>
      <table class="mock-legend cy-table" style="margin-top:8px"><thead><tr><th>Band</th><th class="num">erster Entwurf: Min/Max</th><th class="num">jetzt: Trend</th></tr></thead><tbody>
        <tr><td>Tief aus Top → Tief</td><td class="num">${fmtUsd(lowBand.mm[0])}–${fmtUsd(lowBand.mm[1])}</td><td class="num">${fmtUsd(lowBand.lo)}–${fmtUsd(lowBand.hi)}</td></tr>
        <tr><td>Tief aus Tief → Tief</td><td class="num">${fmtUsd(llBand.mm[0])}–${fmtUsd(llBand.mm[1])}</td><td class="num">${fmtUsd(llBand.lo)}–${fmtUsd(llBand.hi)}</td></tr>
        <tr><td>Top aus Top → Top</td><td class="num">${fmtUsd(ttBand.mm[0])}–${fmtUsd(ttBand.mm[1])}</td><td class="num">${fmtUsd(ttBand.lo)}–${fmtUsd(ttBand.hi)}</td></tr>
        <tr><td>Top aus Tief → Top (Faktor des Tiefs)</td><td class="num">${fmtX(ltSpread.mm[0])}–${fmtX(ltSpread.mm[1])}</td><td class="num">${fmtX(ltSpread.r[0])}–${fmtX(ltSpread.r[1])}</td></tr>
      </tbody></table>
    </div>
  </div></figure>
</section>
</body>
</html>
`;
fs.writeFileSync(path.join(__dirname, '03-lines-into-bands.html'), html3.replace(/[ \t]+$/gm, ''));
console.log('wrote 03-lines-into-bands.html');
