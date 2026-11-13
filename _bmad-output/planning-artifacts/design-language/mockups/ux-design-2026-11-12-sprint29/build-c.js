// Sprint 29 planning board 07, drawn on 2026-11-12 before any code: the
// states that ADR-0059 (the chain source) and ADR-0060 (halving cycles,
// tops and lows by drawdown, the analog band) add to the I12 idea boards
// (ux-design-2026-11-10-idea-i12), which both records name as missing:
//
//   ADR-0059 §4, §8, §11: the „Halving-Kette“ choice in the security's edit
//     form and the confirmation when halving events exist; on the cycle bar
//     not bound, bound without a source, the source stale, a refused own URL;
//   ADR-0060 §2, §4, §5, §11, §12: no_top_yet, a part with too few
//     observations, parts_disjoint, one_price_relation, the partial window
//     and the stated count.
//
// The price line is SYNTHETIC, the idea boards' seeded random walk bent
// through public, rounded anchor points up to October 2025; everything after
// 2025-10-06 is invented, and so are the chain's heights and block times. The
// cycle figures are computed from that series by the rules of ADR-0060 (the
// peak and trough of each window's maximum drawdown, the 20 % anchor, the
// parts, the hull, agree and the states), so the board shows what the rule
// gives and not a drawing of it. The chrome uses the app's own classes and
// links priv/static/app.css; what is new is drawn with the CSS below. No
// portfolio figure, name, host or machine detail appears.
//
// Usage:
//   node build-c.js    # writes frames/07*.html and 07-cycle-states.html
//   node render-c.js   # measures the frames, rebuilds, renders the PNGs
//
// render-c.js passes the measured frame heights in FRAME_SIZES_C (JSON), so
// no sizes file is shared with the other boards in this folder.
const fs = require('fs');
const path = require('path');

const FRAMES = path.join(__dirname, 'frames');
fs.mkdirSync(FRAMES, { recursive: true });
const CSS_FROM_FRAME = '../../../../../../priv/static/app.css';
const CSS_FROM_BOARD = '../../../../../priv/static/app.css';

let SIZES = {};
try { SIZES = JSON.parse(process.env.FRAME_SIZES_C || '{}'); } catch (e) { /* first run */ }

// ---------------------------------------------------------------------------
// Synthetic series (the idea boards' generator, same seed and anchors)

function rng(seed) {
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
const addMonths = (a, n) => { const d = new Date(a); d.setUTCMonth(d.getUTCMonth() + n); return d; };
const fmtDate = (d) => `${String(d.getUTCDate()).padStart(2, '0')}.${String(d.getUTCMonth() + 1).padStart(2, '0')}.${d.getUTCFullYear()}`;
const fmtDM = (d) => fmtDate(d).slice(0, 6);
const MONTHS = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
const fmtMonth = (d) => `${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
const fmtUsd = (v) => (v >= 1000 ? (v / 1000).toLocaleString('de-DE', { maximumFractionDigits: v >= 100000 ? 0 : 1 }) + '&#8239;k' : Math.round(v).toLocaleString('de-DE')) + '&nbsp;$';
const fmtPct = (v) => (v > 0 ? '+' : '−') + Math.abs(v * 100).toLocaleString('de-DE', { maximumFractionDigits: 0 }) + '&nbsp;%';
const fmtX = (v) => '×' + v.toLocaleString('de-DE', { maximumFractionDigits: v >= 10 ? 0 : 1 });
const span = (a, b) => (a.getUTCFullYear() === b.getUTCFullYear() ? `${fmtDM(a)}–${fmtDate(b)}` : `${fmtDate(a)}–${fmtDate(b)}`);
const range$ = (lo, hi) => `${fmtUsd(lo)}–${fmtUsd(hi)}`;

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
  ['2026-09-08', 52000], ['2026-11-06', 61000], ['2026-11-11', 62500],
].map(([d, p]) => ({ d: D(d), p }));
const INVENTED_FROM = D('2025-10-06');

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
    const lp = k === 0 ? Math.log(a.p) : Math.min(Math.max(raw, Math.log(Math.min(a.p, b.p)) + 0.01), Math.log(Math.max(a.p, b.p)) - 0.01);
    SERIES.push({ d: addDays(a.d, k), p: Math.exp(lp) });
  }
}
SERIES.push({ ...ANCHORS[ANCHORS.length - 1] });

const TODAY = D('2026-11-12');

// The variant for parts_disjoint: the same series with every close from
// 01.06.2025 on scaled to 0.9, so the open window's top lies at about 113 k $
// instead of 126 k $. Clearly a what-if, labelled so on the board.
const VARIANT_FROM = D('2025-06-01');
const VARIANT = SERIES.map((q) => (q.d >= VARIANT_FROM ? { d: q.d, p: q.p * 0.9 } : q));

// ---------------------------------------------------------------------------
// The chain (ADR-0059): confirmed halvings, and the next one as a window
// between the recent 2,016-block rate and the target (§6). Heights and times
// after the 2024 halving are SYNTHETIC.

const HALVINGS = [
  { d: D('2012-11-28'), height: 210000 },
  { d: D('2016-07-09'), height: 420000 },
  { d: D('2020-05-11'), height: 630000 },
  { d: D('2024-04-20'), height: 840000 },
];
const TIP = { height: 974812, at: new Date('2026-11-12T05:52:00Z'), mean: 571.4 };
const NEXT_H = 1050000;
const nextWindow = (() => {
  const left = NEXT_H - TIP.height;
  const fast = new Date(TIP.at.getTime() + left * TIP.mean * 1000);
  const target = new Date(TIP.at.getTime() + left * 600 * 1000);
  const u = (d) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  return { from: u(fast), to: u(target), height: NEXT_H, left };
})();

// ---------------------------------------------------------------------------
// ADR-0060's engine over a series as of a day

const ANCHOR_THRESHOLD = -0.20;

function extremes(closes) {
  let peak = closes[0];
  let best = { dd: 0, top: null, low: null };
  for (const q of closes) {
    if (q.p >= peak.p) peak = q; // among equal highest closes, the latest
    const dd = q.p / peak.p - 1;
    if (dd < best.dd) best = { dd, top: peak, low: q }; // the earliest trough
  }
  return best;
}

function engine(series, asOf, next = nextWindow) {
  const closes = series.filter((q) => q.d <= asOf);
  const first = closes[0].d;
  const W = HALVINGS.map((h, i) => {
    const end = HALVINGS[i + 1] ? HALVINGS[i + 1].d : null;
    const wc = closes.filter((q) => q.d >= h.d && (!end || q.d < end));
    const x = extremes(wc);
    const w = { i, start: h.d, end, closes: wc };
    if (!end) {
      Object.assign(w, { kind: 'open', top: x.top, lowSoFar: x.low, dd: x.dd, anchored: x.dd <= ANCHOR_THRESHOLD, low: null });
    } else if (days(h.d, first) > 7) {
      Object.assign(w, { kind: 'partial', top: null, low: x.low });
    } else {
      Object.assign(w, { kind: 'complete', top: x.top, low: x.low });
    }
    return w;
  });
  const open = W[W.length - 1];
  const finalLow = (w) => w.kind !== 'open' && w.low;
  const anchorTop = (w) => (w.kind === 'complete' || (w.kind === 'open' && w.anchored)) && w.top;
  const obs = { halving_to_top: [], top_to_low: [], low_to_top: [], top_to_top: [], low_to_low: [], low_to_next_halving: [] };
  W.forEach((w, i) => {
    const nx = W[i + 1];
    if (anchorTop(w)) obs.halving_to_top.push({ w, days: days(w.start, w.top.d), prov: w.kind === 'open' });
    if (w.kind === 'complete') obs.top_to_low.push({ w, days: days(w.top.d, w.low.d), f: w.low.p / w.top.p });
    if (nx && finalLow(w) && anchorTop(nx)) obs.low_to_top.push({ w, days: days(w.low.d, nx.top.d), f: nx.top.p / w.low.p, partial: w.kind === 'partial', prov: nx.kind === 'open' });
    if (nx && w.kind === 'complete' && anchorTop(nx)) obs.top_to_top.push({ w, days: days(w.top.d, nx.top.d), f: nx.top.p / w.top.p, prov: nx.kind === 'open' });
    if (nx && finalLow(w) && finalLow(nx)) obs.low_to_low.push({ w, days: days(w.low.d, nx.low.d), f: nx.low.p / w.low.p, partial: w.kind === 'partial' });
    if (nx && finalLow(w)) obs.low_to_next_halving.push({ w, days: days(w.low.d, nx.start), partial: w.kind === 'partial' });
  });

  // a part (§4): time min..max from the anchor, price by the log step
  function priceSide(fs) {
    if (fs.length < 2) return null;
    const a = Math.log(fs[fs.length - 2]), b = Math.log(fs[fs.length - 1]);
    if (a === 0 || b === 0 || Math.sign(a) !== Math.sign(b)) return { lo: Math.min(...fs), hi: Math.max(...fs), rule: 'min_max' };
    const f2 = Math.exp(b), g = Math.exp(b * (b / a));
    return { lo: Math.min(f2, g), hi: Math.max(f2, g), rule: 'log_step_v1', fs: [fs[fs.length - 2], fs[fs.length - 1]] };
  }
  function part(rel, anchor, from, to, list, priceFrom = null) {
    const ds = list.map((o) => o.days);
    const base = { rel, anchor, nTime: ds.length };
    if (!anchor) return { ...base, absent: true };
    let lo, hi, nPrice, rule;
    if (priceFrom) {
      if (priceFrom.absent) return { ...base, absent: true, reason: 'too_few_observations', nPrice: priceFrom.nPrice, borrowed: true };
      ({ lo, hi, nPrice, rule } = priceFrom);
    } else {
      const ps = priceSide(list.map((o) => o.f));
      nPrice = list.length;
      if (!ps) return { ...base, absent: true, reason: 'too_few_observations', nPrice };
      lo = anchor.p * ps.lo; hi = anchor.p * ps.hi; rule = ps.rule;
    }
    if (ds.length < 2) return { ...base, absent: true, reason: 'too_few_observations', nPrice };
    return { ...base, nPrice, rule, from: addDays(from, Math.min(...ds)), to: addDays(to, Math.max(...ds)), lo, hi, own: !priceFrom, partial: list.some((o) => o.partial), prov: list.some((o) => o.prov) };
  }

  const lastFinal = [...W].reverse().find((w) => finalLow(w));
  // next low: the open window's low
  const pTL = open.anchored
    ? part('top_to_low', open.top, open.top.d, open.top.d, obs.top_to_low)
    : { rel: 'top_to_low', absent: true, reason: 'no_top_yet', nTime: obs.top_to_low.length };
  const pLL = part('low_to_low', lastFinal.low, lastFinal.low.d, lastFinal.low.d, obs.low_to_low);
  // next top: the first window without an anchored top
  const topIsNext = open.anchored;
  const lastTopW = topIsNext ? open : [...W].reverse().find((w) => w.kind === 'complete');
  const pTT = part('top_to_top', lastTopW.top, lastTopW.top.d, lastTopW.top.d, obs.top_to_top);
  const hFrom = topIsNext ? next.from : open.start, hTo = topIsNext ? next.to : open.start;
  const pHT = part('halving_to_top', { d: hFrom }, hFrom, hTo, obs.halving_to_top, pTT);
  const pLT = topIsNext
    ? { rel: 'low_to_top', absent: true, reason: 'low_not_final', nTime: obs.low_to_top.length }
    : part('low_to_top', lastFinal.low, lastFinal.low.d, lastFinal.low.d, obs.low_to_top);

  const combine = (parts) => {
    const ps = parts.filter((p) => !p.absent);
    if (!ps.length) return { parts, band: null };
    const own = ps.filter((p) => p.own);
    let agree = null, reason = null;
    if (own.length < 2) reason = 'one_price_relation';
    else {
      const lo = Math.max(...own.map((p) => p.lo)), hi = Math.min(...own.map((p) => p.hi));
      if (lo < hi) agree = [lo, hi]; else reason = 'parts_disjoint';
    }
    const band = {
      from: new Date(Math.min(...ps.map((p) => p.from))), to: new Date(Math.max(...ps.map((p) => p.to))),
      lo: Math.min(...ps.map((p) => p.lo)), hi: Math.max(...ps.map((p) => p.hi)), agree, reason,
    };
    band.state = stateOf(band);
    ps.forEach((p) => { p.state = stateOf(p); });
    return { parts, band };
  };
  function stateOf(b) {
    const ended = asOf > b.to;
    if (asOf < b.from) return { s: 'open', ended };
    const hit = closes.some((q) => q.d >= b.from && q.d <= b.to && q.p >= b.lo && q.p <= b.hi);
    if (hit) return { s: 'reached', ended };
    return { s: ended ? 'missed' : 'running', ended };
  }
  return {
    asOf, closes, first, W, open, obs, lastFinal, topIsNext,
    low: combine([pTL, pLL]), top: combine([pHT, pTT, pLT]),
    counts: { complete: W.filter((w) => w.kind === 'complete').length, partial: W.filter((w) => w.kind === 'partial').length, open: 1 },
  };
}

const NOW = engine(SERIES, TODAY);
const PAST = engine(SERIES, D('2025-02-10'));
const VAR = engine(VARIANT, TODAY);

// State words (proposed): ADR-0060 §7's four states, and window_ended.
const STATE_DE = { open: 'offen', running: 'läuft', reached: 'erreicht', missed: 'verfehlt' };
const stateDe = (st) => (st ? `${STATE_DE[st.s]}${st.ended ? ' · Fenster vorbei' : ''}` : '—');
const REL_DE = { halving_to_top: 'Halving → Top', top_to_low: 'Top → Tief', low_to_top: 'Tief → Top', top_to_top: 'Top → Top', low_to_low: 'Tief → Tief', low_to_next_halving: 'Tief → nächstes Halving' };

// ---------------------------------------------------------------------------
// Drawing: the time-axis chart

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function chart(m, v) {
  const W = v.W || 1150, H = v.H || 430;
  const L = 62, R = 18, T = 22, B = 34;
  const { x0, x1 } = v;
  const yMin = Math.log10(v.pMin), yMax = Math.log10(v.pMax);
  const X = (d) => L + ((d - x0) / (x1 - x0)) * (W - L - R);
  const Y = (p) => T + (1 - (Math.log10(p) - yMin) / (yMax - yMin)) * (H - T - B);
  const inX = (d) => d >= x0 && d <= x1;
  const clip = `clip-${v.id}`;
  const lab = v.labels || {};
  let s = `<svg class="cy-chart" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${v.aria || 'Kursverlauf mit Zyklen'}">`;
  s += `<defs><clipPath id="${clip}"><rect x="${L}" y="${T - 16}" width="${W - L - R}" height="${H - T - B + 16}"/></clipPath>`;
  s += `<pattern id="hatch-${v.id}" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" class="cy-hatch"/></pattern></defs>`;
  s += '<g class="cy-grid">';
  for (const p of v.pTicks) s += `<line x1="${L}" x2="${W - R}" y1="${Y(p)}" y2="${Y(p)}"/>`;
  s += '</g><g class="cy-ylab">';
  for (const p of v.pTicks) s += `<text x="${L - 8}" y="${Y(p) + 4}" text-anchor="end">${fmtUsd(p)}</text>`;
  s += '</g><g class="cy-xlab">';
  for (const t of v.xTicks) if (inX(t.d)) s += `<text x="${X(t.d)}" y="${H - 12}" text-anchor="middle">${t.l}</text>`;
  s += `</g><g clip-path="url(#${clip})">`;

  // the partial window: the stretch of 2012–2016 before the first close
  if (v.partial) {
    const a = X(x0), b = X(m.first);
    s += `<rect x="${a}" y="${T}" width="${b - a}" height="${H - T - B}" fill="url(#hatch-${v.id})"/>`;
  }
  // today, or the day the frame shows
  s += `<line class="cy-today" x1="${X(m.asOf)}" x2="${X(m.asOf)}" y1="${T}" y2="${H - B}"/><text class="cy-today-l" x="${X(m.asOf) + 4}" y="${H - B - 6}">${v.todayLabel || 'heute'}</text>`;
  // halvings: confirmed ones solid, the next one as a dashed window
  for (const h of HALVINGS) {
    if (!inX(h.d)) continue;
    s += `<line class="cy-halving" x1="${X(h.d)}" x2="${X(h.d)}" y1="${T}" y2="${H - B}"/>`;
    s += `<text class="cy-halving-l" x="${X(h.d) + 4}" y="${T + 10}">Halving ${fmtDate(h.d)}</text>`;
  }
  if (v.nextHalving !== false && inX(nextWindow.from)) {
    const a = X(nextWindow.from), b = X(nextWindow.to);
    s += `<rect class="cy-halving-win${v.stale ? ' is-stale' : ''}" x="${a}" y="${T}" width="${b - a}" height="${H - T - B}"/>`;
    s += `<line class="cy-halving is-est" x1="${a}" x2="${a}" y1="${T}" y2="${H - B}"/><line class="cy-halving is-est" x1="${b}" x2="${b}" y1="${T}" y2="${H - B}"/>`;
    const t = v.halvingLabel || [`Halving ≈ ${span(nextWindow.from, nextWindow.to)}`, 'Schätzung · Block 1.050.000'];
    t.forEach((line, k) => { s += `<text class="cy-halving-l${k ? ' is-sub' : ''}" x="${a - 5}" y="${H - B - 30 + 13 * k}" text-anchor="end">${line}</text>`; });
  }

  // bands
  const rect = (b) => ({ x: X(b.from), w: Math.max(5, X(b.to) - X(b.from)), y: Y(b.hi), h: Y(b.lo) - Y(b.hi) });
  const drawEvent = (ev, kind, opts = {}) => {
    if (!ev.band) return;
    const b = ev.band, r = rect(b);
    const ended = b.state.ended ? ' is-past' : '';
    if (opts.split && b.reason === 'parts_disjoint') {
      s += `<rect class="cy-band cy-band--${kind} is-hull${ended}" x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}"/>`;
      for (const p of ev.parts.filter((q) => !q.absent)) {
        const pr = rect(p);
        s += `<rect class="cy-band cy-band--${kind} is-part${ended}" x="${pr.x}" y="${pr.y}" width="${pr.w}" height="${pr.h}"/>`;
      }
    } else {
      s += `<rect class="cy-band cy-band--${kind}${ended}${b.reason === 'one_price_relation' ? ' is-one' : ''}" x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}"/>`;
      if (b.agree) s += `<rect class="cy-agree" x="${r.x}" y="${Y(b.agree[1])}" width="${r.w}" height="${Y(b.agree[0]) - Y(b.agree[1])}"/>`;
    }
    const lines = (lab[kind] && lab[kind].lines) || [];
    const at = (lab[kind] && lab[kind].at) || 'left-below';
    lines.forEach((t, k) => {
      let x, y, anchor;
      if (at === 'left-below') { x = r.x - 6; y = r.y + r.h + 14 + 12.5 * k; anchor = 'end'; }
      else if (at === 'left-top') { x = r.x - 6; y = r.y + 4 + 12.5 * k; anchor = 'end'; }
      else if (at === 'right') { x = r.x + r.w + 6; y = r.y + 4 + 12.5 * k; anchor = 'start'; }
      else { x = r.x + r.w; y = r.y + r.h + 14 + 12.5 * k; anchor = 'end'; }
      s += `<text class="cy-band-l${k === 0 ? ' is-head' : ''}" x="${x}" y="${y}" text-anchor="${anchor}">${t}</text>`;
    });
  };
  drawEvent(m.low, 'low', v);
  drawEvent(m.top, 'top', v);

  // the line, dashed where invented
  const vis = m.closes.filter((q) => inX(q.d));
  const step = (x1 - x0) / DAY > 3000 ? 3 : 1;
  // ten points to a line, so a frame stays a readable multiline file
  const pts = (list) => list.filter((_, i) => i % step === 0).map((q, i) => `${i && i % 10 === 0 ? '\n' : ''}${X(q.d).toFixed(1)},${Y(q.p).toFixed(1)}`).join(' ');
  s += `<polyline class="cy-line" fill="none" points="${pts(vis)}"/>`;
  s += `<polyline class="cy-line-invented" fill="none" points="${pts(vis.filter((q) => q.d > INVENTED_FROM))}"/>`;

  // tops ▲ and lows ▼
  const mark = (q, kind, label, o = {}) => {
    if (!q || !inX(q.d)) return '';
    const x = X(q.d), y = Y(q.p);
    const tri = kind === 'top' ? `${x - 5},${y - 9} ${x + 5},${y - 9} ${x},${y - 2}` : `${x - 5},${y + 9} ${x + 5},${y + 9} ${x},${y + 2}`;
    const ly = (kind === 'top' ? y - 14 : y + 21) + (o.dy || 0);
    const lx = x + (o.dx || 0);
    const anchor = o.anchor || (x - L < 50 ? 'start' : 'middle');
    let out = `<polygon class="cy-mark cy-mark--${kind}${o.hollow ? ' is-hollow' : ''}" points="${tri}"/>`;
    [].concat(label).forEach((t, k) => { out += `<text class="cy-mark-l${k ? ' is-sub' : ''}" x="${anchor === 'start' && !o.dx ? x - 4 : lx}" y="${ly + 12 * k}" text-anchor="${anchor}">${t}</text>`; });
    return out;
  };
  const ml = v.marks || {};
  m.W.forEach((w) => {
    if (w.kind === 'complete') {
      s += mark(w.top, 'top', `${fmtUsd(w.top.p)} · ${fmtMonth(w.top.d)}`, ml['top' + w.i]);
      s += mark(w.low, 'low', `${fmtUsd(w.low.p)} · ${fmtMonth(w.low.d)}`, ml['low' + w.i]);
    } else if (w.kind === 'partial') {
      s += mark(w.low, 'low', ml.partialLabel || `${fmtUsd(w.low.p)} · ${fmtMonth(w.low.d)} · Teilzyklus`, ml['low' + w.i]);
    } else {
      if (w.anchored) s += mark(w.top, 'top', ml.openTopLabel || `${fmtUsd(w.top.p)} · ${fmtMonth(w.top.d)}`, ml.openTop);
      else s += mark(w.top, 'top', ml.openTopLabel, { ...ml.openTop, hollow: true });
      if (w.anchored && ml.lowSoFar !== false) s += mark(w.lowSoFar, 'low', ml.lowSoFarLabel || `bisher ${fmtUsd(w.lowSoFar.p)} · vorläufig`, ml.lowSoFar);
    }
  });
  if (v.extra) s += v.extra({ X, Y, L, R, T, B, W, H });
  s += '</g></svg>';
  return s;
}

const yearTicks = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => ({ d: D(a + i + '-01-01'), l: String(a + i) }));
const quarterTicks = (a, b) => { const out = []; for (let y = a; y <= b; y++) ['01', '04', '07', '10'].forEach((mo, i) => out.push({ d: D(`${y}-${mo}-01`), l: i ? `${['', 'Apr', 'Jul', 'Okt'][i]}` : String(y) })); out.push({ d: D(`${b + 1}-01-01`), l: String(b + 1) }); return out; };
const halfTicks = (a, b) => { const out = []; for (let y = a; y <= b; y++) { out.push({ d: D(y + '-01-01'), l: String(y) }); out.push({ d: D(y + '-07-01'), l: 'Jul' }); } return out; };

// ---------------------------------------------------------------------------
// Chrome: the detail pane's chart toolbar and the cycle bar

const RANGES = ['1M', '3M', '6M', 'YTD', '1J', '3J', '5J', 'Max'];
function toolbar({ range = 'Max', cycles = 'on', zyklus = true, phone = false } = {}) {
  const ranges = `<div class="range-buttons" role="group" aria-label="Zeitraum">${RANGES.map((r) => `<button type="button" class="range-button${r === range ? ' is-active' : ''}">${r}</button>`).join('')}${zyklus && cycles === 'on' ? `<button type="button" class="range-button mock-new${range === 'Zyklus' ? ' is-active' : ''}">Zyklus</button>` : ''}</div>`;
  const custom = phone ? '' : '<details class="period-disclosure"><summary class="disclosure-summary">Benutzerdefinierter Zeitraum …</summary></details>';
  const toggles = ['Logarithmische Skala', 'Prozent', 'Transaktionen anzeigen', 'Notizen anzeigen', 'MA200'];
  let cyc = '';
  if (cycles === 'on') cyc = '<button type="button" class="chart-toggle is-active mock-new" aria-pressed="true">Zyklen</button>';
  else if (cycles === 'disabled') cyc = '<button type="button" class="chart-toggle mock-new" disabled aria-disabled="true" title="Zyklen ab zwei bestätigten Halvings: bisher 1">Zyklen</button>';
  const t = `<div class="chart-toggles">${toggles.map((x, i) => `<button type="button" class="chart-toggle${i === 0 ? ' is-active' : ''}">${x}</button>`).join('')}${cyc}<button type="button" class="chart-toggle">…</button></div>`;
  return `<div class="detail-pane-toolbar" role="toolbar" aria-label="Diagramm-Optionen">${ranges}${custom}${t}</div>`;
}

// The health line (ADR-0059 §8): host and age, or the stale line, or the
// refusal. The wording beyond „Kettenquelle seit ‹n› Std. ohne Antwort“ is
// proposed here.
const HEALTH = {
  ok: '<span class="cy-health"><span class="cy-dot is-ok" aria-hidden="true"></span>Kettenquelle: mempool.space · gelesen vor 2 Std.</span>',
  fallback: '<span class="cy-health"><span class="cy-dot is-ok" aria-hidden="true"></span>Kettenquelle: blockstream.info (Ersatz) · gelesen vor 2 Std.</span>',
  stale: '<span class="cy-health is-stale"><span class="cy-dot is-warn" aria-hidden="true"></span><b>Kettenquelle seit 31 Std. ohne Antwort</b> · zuletzt mempool.space, 11.11.2026 01:00 · Halving-Schätzung von dann</span>',
  refusedA: '<span class="cy-health is-error"><span class="cy-dot is-err" aria-hidden="true"></span><b>Eigene Kettenquelle abgelehnt:</b> node.home.arpa löst auf eine private Adresse auf · nichts gelesen seit 08.11.2026</span>',
  refusedB: '<span class="cy-health is-error"><span class="cy-dot is-err" aria-hidden="true"></span><b>Kettenquelle: Konfigurationsfehler</b></span>',
  manual: '<span class="cy-health"><span class="cy-dot is-none" aria-hidden="true"></span>Halvings von Hand · keine Kettenquelle für Litecoin</span>',
};
const infoTip = (text, open = false) => `<details class="metric-tooltip metric-tooltip--inline" data-place="below"${open ? ' open' : ''}><summary aria-label="Zur Kettenquelle">ⓘ</summary><p role="tooltip">${text}</p></details>`;
const REFUSED_TIP = 'Die eigene Quelle aus <code>PORTFOLIXIR_BITCOIN_ESPLORA_URL</code> ersetzt beide öffentlichen Quellen. Sie muss über https unter einer öffentlichen Adresse erreichbar sein; eine Adresse im eigenen Netz wird abgelehnt (url_not_allowed: private_address). Die App liest die Variable beim Start und schreibt sie nie.';
const readNow = (wait) => `<button type="button" class="button-ghost cy-readnow"${wait ? ' disabled title="wieder möglich in 7 Min."' : ''}>${wait ? 'Jetzt lesen · in 7 Min.' : 'Jetzt lesen'}</button>`;

function cycleBar({ health = 'ok', mode = 'Zeitachse', lines = ['Top ↔ Tief'], tip = null, tipOpen = false, read = true, phone = false } = {}) {
  const seg = `<span class="segmented-control" role="group" aria-label="Zyklen-Modus">${['Zeitachse', 'Ausgerichtet'].map((x) => `<button type="button" class="chart-toggle${x === mode ? ' is-active' : ''}">${x}</button>`).join('')}</span>`;
  const sw = `<span class="cy-switches">${['Top ↔ Tief', 'Top – Top', 'Tief – Tief'].map((x) => `<button type="button" class="chart-toggle${lines.includes(x) ? ' is-active' : ''}">${x}</button>`).join('')}</span>`;
  const h = HEALTH[health] + (tip ? infoTip(tip, tipOpen) : '') + (read && health !== 'manual' ? readNow(false) : '');
  return `<div class="cy-bar mock-new${phone ? ' is-phone' : ''}"><div class="cy-bar__row"><span class="cy-bar__label">Zyklen</span>${seg}<span class="cy-bar__label">Strecken</span>${sw}</div><div class="cy-bar__row cy-bar__health">${h}</div></div>`;
}

const head = (name = 'Bitcoin', sub = 'BTC-USD · USD · Kurse ab 17.09.2014') => `<header class="cy-head"><h2>${name}</h2><span class="cy-sub">${sub}</span></header>`;

// The count line (ADR-0060 §12, decided wording) and the basis.
const countLine = (m) => `<p class="cy-count"><b>${m.counts.complete} vollständige Zyklen, ${m.counts.partial} unvollständiger; Kurse ab 09/2014</b> · offen: der Zyklus seit dem Halving vom ${fmtDate(m.open.start)}</p>`;
const basis = 'Rechenbasis: gespeicherte Tagesschlusskurse in USD, Lücken übersprungen, nie gefüllt · Fenster Halving bis Halving (der Schluss am Halving-Tag gehört zum neuen Fenster) · Top und Tief = Gipfel und Talsohle des größten Rückgangs im Fenster · ein offenes Top ist Anker ab 20&nbsp;% darunter, ein Tief erst, wenn das Fenster schließt · Band: Zeit Min bis Max, Kurs vom letzten Faktor bis einen Log-Schritt weiter; Hülle der Teile, kein Mittelwert, keine Prognose.';

// ---------------------------------------------------------------------------
// Tables: the intervals with n, and the bands with their parts

function intervalTable(m) {
  const cols = m.W.map((w) => w);
  const head = cols.map((w) => `<th class="num">${w.start.getUTCFullYear()}${w.kind === 'partial' ? ' <span class="badge cy-badge">Teil</span>' : w.kind === 'open' ? ' <span class="cy-muted">offen</span>' : ''}</th>`).join('');
  const cell = (rel, w, fmt) => {
    const o = m.obs[rel].find((x) => x.w === w);
    if (!o) return '<td class="num cy-muted">—</td>';
    const flags = `${o.partial ? ' <span class="badge cy-badge">Teil</span>' : ''}${o.prov ? ' <span class="cy-muted">vorläufig</span>' : ''}`;
    return `<td class="num">${fmt(o)}${flags}</td>`;
  };
  const d = (o) => `${o.days}&nbsp;T`;
  const f = (o) => `${o.days}&nbsp;T · ${fmtX(o.f)}`;
  const c = (o) => `${o.days}&nbsp;T · ${fmtPct(o.f - 1)}`;
  const rows = [
    ['halving_to_top', d], ['top_to_low', c], ['low_to_top', f], ['top_to_top', f], ['low_to_low', f], ['low_to_next_halving', d],
  ].map(([rel, fmt]) => {
    const n = m.obs[rel].length, np = m.obs[rel].filter((o) => o.partial).length, pv = m.obs[rel].filter((o) => o.prov).length;
    return `<tr><td>${REL_DE[rel]}</td>${cols.map((w) => cell(rel, w, fmt)).join('')}<td class="num"><b>n = ${n}</b></td><td class="cy-muted">${[np ? `${np} aus dem Teilzyklus` : '', pv ? `${pv} vorläufig` : ''].filter(Boolean).join(' · ')}</td></tr>`;
  }).join('');
  return `<table class="data-table cy-table"><caption class="cy-caption">${countLine(m)}</caption><thead><tr><th>Strecke · ab Zyklus</th>${head}<th class="num">n</th><th>Kennzeichen</th></tr></thead><tbody>${rows}</tbody></table>`;
}

const REASON_DE = {
  no_top_yet: (m) => `wartet auf ein verankertes Top: bisher ${fmtPct(m.open.dd)} unter dem Top bisher, Anker ab −20&nbsp;%`,
  too_few_observations: (p) => `zu wenige Beobachtungen: ${p.borrowed ? `Kurs aus Top → Top, n = ${p.nPrice}` : `n = ${Math.min(p.nTime, p.nPrice ?? p.nTime)}`}, ab n = 2`,
  low_not_final: () => 'wartet, bis das Tief des laufenden Zyklus endgültig ist (am nächsten Halving)',
};
function bandTable(m, { hl = [] } = {}) {
  const row = (ev, name) => {
    const b = ev.band;
    const bandRow = b
      ? `<tr class="cy-row-band"><td><b>${name}</b></td><td>Hülle der Teile</td><td class="num">${span(b.from, b.to)}</td><td class="num">${range$(b.lo, b.hi)}</td><td>${b.agree ? `beide Wege ${range$(b.agree[0], b.agree[1])}` : `<span class="cy-reason${hl.includes(b.reason) ? ' is-hl' : ''}">${b.reason === 'one_price_relation' ? 'ein Kursweg — kein „beide Wege“' : 'Wege uneinig — kein gemeinsamer Kurs'}</span> <code>${b.reason}</code>`}</td><td>${stateDe(b.state)}</td></tr>`
      : `<tr class="cy-row-band"><td><b>${name}</b></td><td colspan="5" class="cy-muted">kein Band: kein Teil</td></tr>`;
    const parts = ev.parts.map((p) => {
      if (p.absent) {
        const why = p.reason === 'no_top_yet' ? REASON_DE.no_top_yet(m) : REASON_DE[p.reason](p);
        return `<tr class="cy-row-part is-absent"><td>${REL_DE[p.rel]}</td><td colspan="4"><span class="cy-reason${hl.includes(p.reason) ? ' is-hl' : ''}">${why}</span>${p.reason === 'low_not_final' ? '' : ` <code>${p.reason}</code>`}</td><td class="cy-muted">—</td></tr>`;
      }
      const from = p.rel === 'halving_to_top' ? (m.topIsNext ? 'ab dem Halving-Fenster' : `ab dem Halving ${fmtDate(m.open.start)}`) : `ab ${p.anchor.d ? (p.rel.startsWith('top') ? 'Top' : 'Tief') + ' ' + fmtMonth(p.anchor.d) : ''}`;
      const price = p.own ? `Kurs n = ${p.nPrice}${p.rule === 'min_max' ? ' · Min/Max' : ''}` : 'Kurs aus Top → Top';
      return `<tr class="cy-row-part"><td>${REL_DE[p.rel]}</td><td>${from} · Zeit n = ${p.nTime}, ${price}${p.partial ? ' <span class="badge cy-badge">Teil</span>' : ''}${p.prov ? ' <span class="cy-muted">vorläufig</span>' : ''}</td><td class="num">${span(p.from, p.to)}</td><td class="num">${range$(p.lo, p.hi)}</td><td></td><td>${stateDe(p.state)}</td></tr>`;
    }).join('');
    return bandRow + parts;
  };
  return `<table class="data-table cy-table cy-bands"><thead><tr><th>Band · Teil</th><th>Woher</th><th class="num">Zeitfenster</th><th class="num">Kurs</th><th>Wo die Wege übereinstimmen</th><th>Stand</th></tr></thead><tbody>${row(m.low, 'Nächstes Tief')}${row(m.top, 'Nächstes Top')}</tbody></table>`;
}

// ---------------------------------------------------------------------------
// Frame CSS: the idea boards' cy-* rules, then this board's

const CY_CSS = `
body { margin: 0; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 3px; border-radius: 8px; }
.cy-card { background: var(--color-bg-elevated); padding: 14px 16px 14px; }
.cy-head { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 10px; margin: 0 0 10px; }
.cy-head h2 { margin: 0; font-size: 16px; }
.cy-sub { font-size: 12.5px; color: var(--color-text-muted); }
.detail-pane-toolbar { margin: 0 0 12px; }
.chart-toggle[disabled] { opacity: .55; cursor: not-allowed; }
.cy-bar { display: flex; flex-direction: column; gap: 6px; margin: 0 0 10px; padding: 6px 8px; font-size: 12.5px; color: var(--color-text-muted); }
.cy-bar__row { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 10px; }
.cy-bar__label { font-weight: 600; }
.cy-bar__label + .segmented-control, .cy-bar__label + .cy-switches { margin-right: 8px; }
.cy-switches { display: inline-flex; flex-wrap: wrap; gap: 6px; }
.cy-health { display: inline-flex; align-items: baseline; gap: 6px; flex-wrap: wrap; }
.cy-health b { color: var(--color-text); }
.cy-health.is-stale b { color: var(--color-warning); }
.cy-health.is-error b { color: var(--color-danger); }
.cy-dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; align-self: center; margin-right: 2px; }
.cy-field p.cy-health, .cy-bar.is-phone .cy-health { display: block; }
.cy-field p.cy-health .cy-dot, .cy-bar.is-phone .cy-dot { margin-right: 6px; vertical-align: 0; }
.cy-dot.is-ok { background: var(--color-positive); }
.cy-dot.is-warn { background: var(--color-warning); }
.cy-dot.is-err { background: var(--color-danger); }
.cy-dot.is-none { background: transparent; border: 1.5px solid var(--color-text-muted); }
.cy-readnow { min-height: 26px; padding: 2px 10px; font-size: 12px; margin-left: 4px; }
.cy-before { margin: 0 0 10px; } .cy-before img { display: block; height: auto; border: 1px solid var(--color-border); border-radius: 6px; }
.cy-edge { display: block; margin: 0 0 12px; font-family: var(--font-mono); font-size: 11px; }
.cy-edge__plot { fill: var(--color-accent-soft); stroke: var(--color-border); }
.cy-edge__line { fill: none; stroke: var(--color-accent); stroke-width: 2; }
.cy-edge__top { fill: var(--color-positive); } .cy-edge__low { fill: none; stroke: var(--color-danger); stroke-width: 1.5; }
.cy-edge__label { fill: var(--color-text); paint-order: stroke; stroke: var(--color-bg); stroke-width: 3px; } .cy-edge__label.is-muted { fill: var(--color-text-muted); }
.cy-edge__note { fill: var(--color-text-muted); font-family: var(--font-sans); font-size: 11px; }
.cy-bar .metric-tooltip--inline { position: relative; bottom: auto; right: auto; }
.cy-bar .metric-tooltip p { width: 30rem; max-width: 80vw; }
.cy-bar.is-phone .cy-bar__row { gap: 6px 8px; }
.cy-bar.is-phone .cy-bar__label { width: 100%; }
.cy-bar.is-phone .cy-health { display: block; line-height: 1.45; }
.cy-chart { display: block; background: var(--color-chart-surface); border-radius: 6px; }
.cy-grid line { stroke: var(--color-border); stroke-width: 1; }
.cy-ylab text, .cy-xlab text { fill: var(--color-text-muted); font: 11px var(--font-sans); }
.cy-line { stroke: var(--color-accent); stroke-width: 1.5; }
.cy-line-invented { stroke: var(--color-chart-surface); stroke-width: 2; stroke-dasharray: 3 4; opacity: .9; }
.cy-halving { stroke: var(--color-warning); stroke-width: 1.4; }
.cy-halving.is-est { stroke-dasharray: 5 4; stroke-width: 1.1; }
.cy-halving-l { fill: var(--color-warning); font: 700 10.5px var(--font-sans); paint-order: stroke; stroke: var(--color-chart-surface); stroke-width: 3px; }
.cy-halving-l.is-sub { font-weight: 600; fill: var(--color-text-muted); }
.cy-halving-win { fill: color-mix(in oklab, var(--color-warning) 16%, transparent); }
.cy-halving-win.is-stale { fill: url(#none); fill: color-mix(in oklab, var(--color-text-muted) 14%, transparent); }
.cy-today { stroke: var(--color-text-muted); stroke-width: 1; stroke-dasharray: 1 3; }
.cy-today-l { fill: var(--color-text-muted); font: 600 10px var(--font-sans); }
.cy-hatch { stroke: color-mix(in oklab, var(--color-text-muted) 35%, transparent); stroke-width: 2; }
.cy-band { stroke-width: 1.2; }
.cy-band--top { fill: color-mix(in oklab, var(--color-positive) 22%, transparent); stroke: var(--color-positive); }
.cy-band--low { fill: color-mix(in oklab, var(--color-danger) 22%, transparent); stroke: var(--color-danger); }
.cy-band.is-past { fill: color-mix(in oklab, var(--color-text-muted) 16%, transparent); stroke: var(--color-text-muted); stroke-dasharray: 3 2; }
.cy-band.is-one { stroke-dasharray: 5 3; }
.cy-band.is-hull { fill: color-mix(in oklab, var(--color-danger) 6%, transparent); stroke-dasharray: 5 3; }
.cy-band.is-hull.is-past { fill: color-mix(in oklab, var(--color-text-muted) 6%, transparent); }
.cy-band.is-part { fill: color-mix(in oklab, var(--color-danger) 26%, transparent); stroke-width: 1; }
.cy-band.is-part.is-past { fill: color-mix(in oklab, var(--color-text-muted) 26%, transparent); stroke-dasharray: none; }
.cy-agree { fill: color-mix(in oklab, var(--color-text) 30%, transparent); stroke: none; }
.cy-band-l { fill: var(--color-text-muted); font: 600 10.5px var(--font-sans); paint-order: stroke; stroke: var(--color-chart-surface); stroke-width: 3px; }
.cy-band-l.is-head { fill: var(--color-text); }
.cy-mark--top { fill: var(--color-positive); }
.cy-mark--low { fill: var(--color-danger); }
.cy-mark.is-hollow { fill: var(--color-chart-surface); stroke: var(--color-positive); stroke-width: 1.5; }
.cy-mark-l { fill: var(--color-text); font: 600 10.5px var(--font-sans); paint-order: stroke; stroke: var(--color-chart-surface); stroke-width: 3px; }
.cy-mark-l.is-sub { fill: var(--color-text-muted); font-weight: 500; }
.cy-bracket { fill: none; stroke: var(--color-text-muted); stroke-width: 1; }
.cy-note.is-head { font-style: normal; font-weight: 700; fill: var(--color-text); }
.cy-note { fill: var(--color-text-muted); font: italic 10.5px var(--font-sans); paint-order: stroke; stroke: var(--color-chart-surface); stroke-width: 3px; }
.cy-basis { margin: 8px 0 0; font-size: 11.5px; line-height: 1.5; color: var(--color-text-muted); }
.cy-count { margin: 0; font-size: 12.5px; color: var(--color-text-muted); }
.cy-count b { color: var(--color-text); }
.cy-caption { caption-side: top; text-align: left; padding: 0 0 6px; }
.cy-table { width: 100%; margin-top: 12px; font-size: 12.5px; }
.cy-table th, .cy-table td { white-space: nowrap; }
.cy-bands td:nth-child(2), .cy-bands td[colspan] { white-space: normal; }
.cy-bands td:nth-child(5) { white-space: normal; }
.cy-disclosure { margin-top: 14px; }
.cy-disclosure > summary { font-size: 13px; font-weight: 600; }
.cy-table td.num, .cy-table th.num { text-align: right; font-variant-numeric: tabular-nums; }
.cy-muted { color: var(--color-text-muted); font-weight: 500; }
.cy-badge { font-size: 10px; padding: 0 6px; vertical-align: 1px; }
.cy-bands tr.cy-row-band td { border-top: 1px solid var(--color-border-strong); }
.cy-bands tr.cy-row-part td:first-child { padding-left: 22px; color: var(--color-text-muted); }
.cy-bands tr.is-absent td { color: var(--color-text-muted); }
.cy-reason.is-hl { color: var(--color-text); font-weight: 650; background: var(--color-accent-soft); padding: 1px 4px; border-radius: 4px; }
.cy-bands code, .cy-table code { font-size: 11px; color: var(--color-text-muted); }
.cy-h3 { margin: 12px 0 6px; font-size: 13px; }
.cy-pair { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
.cy-pair h3 { margin: 0 0 6px; font-size: 13px; }
.cy-legend { display: flex; flex-wrap: wrap; gap: 4px 16px; margin: 8px 0 0; font-size: 11.5px; color: var(--color-text-muted); }
.cy-strip { border-top: 1px solid var(--color-border); padding: 12px 0 4px; }
.cy-strip:first-child { border-top: 0; padding-top: 0; }
.cy-strip > h3 { margin: 0 0 8px; font-size: 12px; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; color: var(--color-text-muted); }
.cy-strip > h3 small { text-transform: none; letter-spacing: 0; font-weight: 600; color: var(--color-accent); margin-left: 6px; }
.cy-strip .detail-pane-toolbar { margin-bottom: 8px; }
.cy-hint { margin: 0 0 4px; font-size: 12.5px; color: var(--color-text-muted); }
/* the edit form */
.modal.cy-modal { max-width: 600px; margin: 0; box-shadow: none; border-radius: 0; }
.cy-modal .modal-body { padding-bottom: 4px; }
.cy-field { display: grid; gap: 6px; padding: 12px; margin: 14px 0 0; border-radius: 8px; }
.cy-field > label { display: grid; gap: 4px; max-width: 18rem; }
.cy-field > label > span { font-size: 13px; font-weight: 600; }
.cy-field select { min-height: 34px; }
.cy-field .form-help, .cy-field .hint { margin: 0; padding: 0; font-size: 12.5px; color: var(--color-text-muted); line-height: 1.45; }
.cy-field .cy-health { font-size: 12.5px; color: var(--color-text-muted); }
.cy-listbox { list-style: none; margin: 0; padding: 4px 0; width: 18rem; border: 1px solid var(--color-border-strong); border-radius: var(--radius-md); background: var(--color-bg-elevated); box-shadow: var(--shadow-panel); font-size: 13px; }
.cy-listbox li { padding: 5px 12px; }
.cy-listbox li.is-selected { background: var(--color-accent); color: var(--color-on-accent, #fff); }
.cy-listbox li small { color: inherit; opacity: .75; margin-left: 6px; }
.cy-elided { margin: 0 0 4px; font-size: 12.5px; color: var(--color-text-subtle); font-style: italic; }
.cy-confirm { margin: 10px 0 0; }
.cy-confirm ul { margin: 4px 0 6px; padding-left: 18px; }
.cy-confirm > div { margin-top: 6px; }
`;

const BREAK_BEFORE = /><(?=\/?(?:g|svg|line|rect|polygon|polyline|tr|td|th|thead|tbody|table|caption|div|section|header|form|select|option|label|button|p|h[1-6]|details|summary|ul|li|defs|pattern|clipPath))/g;
const multiline = (s) => s.replace(BREAK_BEFORE, '>\n<');

function writeFrame(name, body, { width = 1200, css = '' } = {}) {
  const doc = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${name}</title>
<link rel="stylesheet" href="${CSS_FROM_FRAME}">
<style id="proposal">${CY_CSS}${css}</style>
</head>
<body>
${multiline(body)}
</body>
</html>
`;
  fs.writeFileSync(path.join(FRAMES, name + '.html'), doc.replace(/[ \t]+$/gm, ''));
  return { file: name + '.html', width };
}

// ===========================================================================
// 07a: the edit form's „Halving-Kette“ (ADR-0059 §4, §11)

const formHead = (title = 'Wertpapier bearbeiten') => `<header class="modal-head"><h2>${title}</h2><button type="button" class="icon-button" aria-label="Schließen">✕</button></header>`;
const formTop = `<div class="form-grid"><label><span>Name</span><input type="text" value="Bitcoin"></label><label><span>Ticker</span><input type="text" value="BTC-USD"></label><label><span>Währung</span><select><option>USD</option></select></label><label><span>Anlageklasse</span><select><option>Kryptowährung</option></select></label></div><p class="cy-elided">… ISIN, WKN, Börse, Kursquelle und Kursquelle-URL wie heute</p>`;
const formFoot = (primary = 'Änderungen speichern') => `<div class="modal-footer"><button type="button" class="button-ghost">Abbrechen</button><button type="submit" class="button-primary">${primary}</button></div>`;
const chainSelect = (val) => `<select name="security[halving_chain]">${['Keine', 'Bitcoin', 'Bitcoin Cash', 'Litecoin'].map((x) => `<option${x === val ? ' selected' : ''}>${x}</option>`).join('')}</select>`;
const chainField = (val, help, extra = '') => `<div class="cy-field mock-new"><label><span>Halving-Kette</span>${chainSelect(val)}</label>${extra}${help}</div>`;

const HELP_BTC = '<p class="form-help">Die Halvings dieses Wertpapiers kommen aus der Bitcoin-Kette. Zyklen im Chart ab zwei bestätigten Halvings.</p>';
const f07a = writeFrame('07a-form-kette', `<div class="modal cy-modal">${formHead()}<div class="modal-body">${formTop}${chainField('Bitcoin',
  `${HELP_BTC}<p class="cy-health"><span class="cy-dot is-ok" aria-hidden="true"></span>Kettenquelle: mempool.space · gelesen vor 2 Std. · 4 Halvings bestätigt, das nächste ≈ ${span(nextWindow.from, nextWindow.to)}</p>`,
  `<ul class="cy-listbox" aria-hidden="true"><li>Keine</li><li class="is-selected">Bitcoin <small>Halvings aus der Kette</small></li><li>Bitcoin Cash <small>von Hand</small></li><li>Litecoin <small>von Hand</small></li></ul>`)}${formFoot()}</div></div>`, { width: 600 });

const f07a2 = writeFrame('07a2-form-litecoin', `<div class="modal cy-modal">${formHead()}<div class="modal-body"><div class="form-grid"><label><span>Name</span><input type="text" value="Litecoin"></label><label><span>Ticker</span><input type="text" value="LTC-USD"></label></div><p class="cy-elided">… die übrigen Felder wie heute</p>${chainField('Litecoin',
  `<p class="form-help">Für Litecoin liest die App keine Kette: Halvings trägst du als Ereignis „Halving“ von Hand ein, oder ein Agent über die API. Die App prüft die Blockhöhe gegen das Intervall der Kette (840.000 Blöcke).</p><p class="cy-health"><span class="cy-dot is-none" aria-hidden="true"></span><b>1 von 2</b> bestätigten Halvings · Zyklen erscheinen im Chart ab dem zweiten</p>`)}${formFoot()}</div></div>`, { width: 600 });

const f07a3 = writeFrame('07a3-form-abgelehnt', `<div class="modal cy-modal">${formHead()}<div class="modal-body">${formTop}${chainField('Bitcoin',
  `${HELP_BTC}<p class="cy-health is-error"><span class="cy-dot is-err" aria-hidden="true"></span><b>Eigene Kettenquelle abgelehnt:</b> node.home.arpa löst auf eine private Adresse auf. Es werden keine Halvings geschrieben.</p><p class="form-help">Eine eigene Instanz muss über https unter einer öffentlichen Adresse erreichbar sein; die Variable <code>PORTFOLIXIR_BITCOIN_ESPLORA_URL</code> wird beim Start gelesen und nie von der App geschrieben.</p>`)}${formFoot()}</div></div>`, { width: 600 });

// 07b: the confirmation when halving events exist and the binding changes
const CONFIRM_LIST = `<ul><li>4 bestätigte Halvings (2012, 2016, 2020, 2024)</li><li>1 Schätzung (Block 1.050.000, ≈ ${span(nextWindow.from, nextWindow.to)})</li></ul>`;
const f07b = writeFrame('07b-bestaetigen-a', `<div class="modal cy-modal">${formHead()}<div class="modal-body">${formTop}${chainField('Keine', `<div class="alert-warning cy-confirm" role="alert"><strong>Ohne Halving-Kette werden 5 Halving-Ereignisse gelöscht</strong><div>Sie gelten nur für dieses Wertpapier als Bitcoin:${CONFIRM_LIST}Das Journal behält jede gelöschte Zeile. Die Zyklen verschwinden aus dem Chart.</div></div>`)}${formFoot('Speichern und 5 Ereignisse löschen')}</div></div>`, { width: 600 });

const f07b2 = writeFrame('07b2-bestaetigen-b', `<div class="modal cy-modal">${formHead('Halving-Kette ändern?')}<div class="modal-body"><p>Von <b>Bitcoin</b> auf <b>Litecoin</b>: die 5 Halving-Ereignisse dieses Wertpapiers werden gelöscht.</p>${CONFIRM_LIST.replace('<ul>', '<ul class="cy-hint">')}<p class="cy-hint">Das Journal behält jede gelöschte Zeile. Für Litecoin trägst du die Halvings danach von Hand ein.</p><div class="modal-footer"><button type="button" class="button-ghost">Zurück</button><button type="button" class="button-danger button-primary">5 Ereignisse löschen und ändern</button></div></div></div>`, { width: 600 });

// ===========================================================================
// 07c: Max, cycles on: the partial window and the count (ADR-0060 §1, §12)

const viewMax = {
  id: 'max', W: 1166, H: 440, x0: D('2014-07-01'), x1: D('2030-04-01'), pMin: 70, pMax: 800000, pTicks: [100, 1000, 10000, 100000],
  xTicks: yearTicks(2015, 2030), partial: true,
  labels: {
    low: { at: 'left-below', lines: [`Tief-Band ${range$(NOW.low.band.lo, NOW.low.band.hi)}`, span(NOW.low.band.from, NOW.low.band.to), NOW.low.band.agree ? `beide Wege ${range$(...NOW.low.band.agree)}` : '', stateDe(NOW.low.band.state)].filter(Boolean) },
    top: { at: 'left-top', lines: [`Top-Band ${range$(NOW.top.band.lo, NOW.top.band.hi)}`, span(NOW.top.band.from, NOW.top.band.to), 'ein Kursweg: Top → Top, n = 2'] },
  },
  marks: { partialLabel: [`${fmtUsd(NOW.W[0].low.p)} · ${fmtMonth(NOW.W[0].low.d)}`, 'Tief des Teilzyklus'], openTopLabel: `${fmtUsd(NOW.open.top.p)} · ${fmtMonth(NOW.open.top.d)}`, lowSoFar: { dx: 0 }, low0: { dx: 10, dy: -16, anchor: 'start' } },
  halvingLabel: ['Halving ≈ Mär–Apr 2028', 'Schätzung'],
  extra: ({ X, Y }) => {
    const a = X(D('2014-07-01')), b = X(HALVINGS[1].d), y = Y(30000);
    return `<path class="cy-bracket" d="M${a + 2},${y + 8} v-8 H${b - 3} v8"/><text class="cy-note is-head" x="${a + 6}" y="${y - 6}">Teilzyklus 2012–2016: kein Top</text><text class="cy-note" x="${a + 6}" y="${y + 22}">Halving 2012 und Top 12/2013</text><text class="cy-note" x="${a + 6}" y="${y + 35}">vor den gespeicherten Kursen</text>`;
  },
};
const f07c = writeFrame('07c-max-teilzyklus', `<div class="cy-card">${head()}${toolbar({ range: 'Max' })}${cycleBar()}${chart(NOW, viewMax)}<p class="cy-basis">${basis}</p>${intervalTable(NOW)}</div>`);

// 07d: range „Zyklus“ today: one_price_relation and the band states
const zStart = addMonths(HALVINGS[3].d, -3);
const zEnd = addMonths(new Date(Math.max(NOW.top.band.to, NOW.low.band.to)), 4);
const viewZ = {
  id: 'zyk', W: 1166, H: 440, x0: zStart, x1: zEnd, pMin: 12000, pMax: 600000, pTicks: [20000, 50000, 100000, 200000, 500000],
  xTicks: yearTicks(2024, 2030),
  labels: {
    low: { at: 'left-below', lines: [`Tief-Band ${range$(NOW.low.band.lo, NOW.low.band.hi)} · ${span(NOW.low.band.from, NOW.low.band.to)}`, `beide Wege ${range$(...NOW.low.band.agree)}`, stateDe(NOW.low.band.state)] },
    top: { at: 'left-top', lines: [`Top-Band ${range$(NOW.top.band.lo, NOW.top.band.hi)}`, span(NOW.top.band.from, NOW.top.band.to), 'ein Kursweg: Top → Top (n = 2)', 'kein „beide Wege“ bis Tief → Top dazukommt', stateDe(NOW.top.band.state)] },
  },
  marks: { openTopLabel: [`${fmtUsd(NOW.open.top.p)} · ${fmtMonth(NOW.open.top.d)}`, 'verankert · vorläufig'], lowSoFarLabel: [`bisher ${fmtUsd(NOW.open.lowSoFar.p)} · ${fmtMonth(NOW.open.lowSoFar.d)}`, 'Tief bisher, vorläufig'], openTop: { dy: -10 } },
};
const f07d = writeFrame('07d-zyklus-heute', `<div class="cy-card">${head()}${toolbar({ range: 'Zyklus' })}${cycleBar()}${chart(NOW, viewZ)}<p class="cy-basis">Bereich „Zyklus“: drei Monate vor dem letzten bestätigten Halving bis vier Monate nach dem Ende des Top-Bands; rechts von „heute“ nur das Halving-Fenster und die Bänder. ${basis}</p><details class="cy-disclosure mock-new" open><summary class="disclosure-summary">Bänder und ihre Teile</summary>${bandTable(NOW, { hl: ['one_price_relation'] })}</details></div>`);

// 07e: no_top_yet, too few observations, one price relation: the screen as
// it would have stood on 10.02.2025 (a state, not a feature: the app reads
// today only)
const pStart = addMonths(HALVINGS[3].d, -3);
const pEnd = addMonths(new Date(Math.max(...[PAST.top.band, PAST.low.band].filter(Boolean).map((b) => b.to))), 4);
const viewP = {
  id: 'past', W: 1166, H: 420, x0: pStart, x1: pEnd, pMin: 12000, pMax: 600000, pTicks: [20000, 50000, 100000, 200000, 500000],
  xTicks: halfTicks(2024, 2027), todayLabel: 'Stand 10.02.2025', nextHalving: false,
  labels: {
    low: { at: 'left-below', lines: [`Tief-Band ${range$(PAST.low.band.lo, PAST.low.band.hi)}`, span(PAST.low.band.from, PAST.low.band.to), 'nur Tief → Tief (n = 2)', 'Top → Tief wartet auf ein verankertes Top'] },
    top: { at: 'left-top', lines: [`Top-Band ${range$(PAST.top.band.lo, PAST.top.band.hi)}`, span(PAST.top.band.from, PAST.top.band.to), 'nur Tief → Top (n = 2, 1 aus dem Teilzyklus)', 'Top → Top und Halving → Top: zu wenige Beobachtungen'] },
  },
  marks: { openTopLabel: [`Top bisher ${fmtUsd(PAST.open.top.p)} · ${fmtDate(PAST.open.top.d)}`, `noch kein Anker: ${fmtPct(PAST.open.dd)}, Anker ab −20&nbsp;%`], openTop: { anchor: 'middle', dy: -12 } },
};
const f07e = writeFrame('07e-ohne-top', `<div class="cy-card">${head('Bitcoin', 'BTC-USD · USD · Darstellung zum Stand 10.02.2025, synthetisch')}${toolbar({ range: 'Zyklus' })}${cycleBar()}${chart(PAST, viewP)}<details class="cy-disclosure" open><summary class="disclosure-summary">Bänder und ihre Teile</summary>${bandTable(PAST, { hl: ['no_top_yet', 'too_few_observations', 'one_price_relation'] })}</details></div>`);

// 07f: parts_disjoint, on the what-if variant (top at about 113 k $)
const vb = VAR.low.band;
const viewV = (id, split) => ({
  id, W: 1166, H: 300, x0: D('2025-08-01'), x1: D('2027-01-15'), pMin: 15000, pMax: 160000, pTicks: [20000, 50000, 100000],
  xTicks: quarterTicks(2025, 2026), nextHalving: false, split,
  labels: { low: { at: 'left-below', lines: split
    ? [`Tief-Band ${range$(vb.lo, vb.hi)}`, 'Wege uneinig: dazwischen kein Weg', stateDe(vb.state)]
    : [`Tief-Band ${range$(vb.lo, vb.hi)}`, 'Wege uneinig (kein „beide Wege“)', stateDe(vb.state)] } },
  marks: { openTopLabel: [`${fmtUsd(VAR.open.top.p)} · ${fmtMonth(VAR.open.top.d)}`, 'Variante'], lowSoFarLabel: `bisher ${fmtUsd(VAR.open.lowSoFar.p)}` },
  extra: split ? ({ X, Y }) => VAR.low.parts.filter((p) => !p.absent).map((p) => `<text class="cy-band-l" x="${X(p.to) + 6}" y="${(Y(p.hi) + Y(p.lo)) / 2 + 4}">${REL_DE[p.rel]} ${range$(p.lo, p.hi)}</text>`).join('') : null,
});
const f07f = writeFrame('07f-teile-uneinig', `<div class="cy-card">${head('Bitcoin · Variante', 'synthetisch: alle Schlusskurse ab 01.06.2025 × 0,9, das Top der offenen Phase bei ≈ 113&#8239;k&nbsp;$')}<h3 class="cy-h3">A · Hülle als Umriss, darin die beiden Teile <span class="cy-muted">(empfohlen)</span></h3>${chart(VAR, viewV('va', true))}<h3 class="cy-h3">B · nur die Hülle, gefüllt wie jedes Band, ohne Schattierung</h3>${chart(VAR, viewV('vb', false))}${bandTable(VAR, { hl: ['parts_disjoint'] }).replace(/<tr class="cy-row-band"><td><b>Nächstes Top[\s\S]*$/, '</tbody></table>')}</div>`);

// 07g: the cycle bar's states at 1200 px (ADR-0059 §8, §11; ADR-0060 §1)
const strip = (title, tag, inner) => `<section class="cy-strip"><h3>${title}${tag ? ` <small>${tag}</small>` : ''}</h3>${inner}</section>`;
const f07g = writeFrame('07g-leiste-zustaende', `<div class="cy-card">
${strip('Nicht gebunden', 'entschieden: kein Schalter (ADR-0060 §1)', `${head('Weltindex ETF', 'Kein Halving-Wertpapier')}${toolbar({ cycles: 'none' })}`)}
${strip('Gebunden, weniger als zwei bestätigte Halvings · A', 'empfohlen: wie ADR-0060 §1, kein Schalter; der Grund steht im Bearbeiten-Dialog', `${head('Litecoin', 'LTC-USD · Halving-Kette Litecoin · 1 Halving eingetragen')}${toolbar({ cycles: 'none' })}`)}
${strip('Gebunden, weniger als zwei bestätigte Halvings · B', 'Schalter ausgegraut, der Grund im Tooltip', `${toolbar({ cycles: 'disabled' })}<p class="cy-hint">Tooltip: „Zyklen ab zwei bestätigten Halvings: bisher 1“</p>`)}
${strip('Gebunden, Kette ohne Quelle', 'Litecoin, Bitcoin Cash: Halvings von Hand', `${head('Litecoin', 'LTC-USD · 3 Halvings von Hand')}${cycleBar({ health: 'manual' })}`)}
${strip('Quelle aktuell', 'Host und Alter (ADR-0059 §8)', cycleBar({ health: 'ok' }))}
${strip('Ersatzquelle hat geantwortet', '', cycleBar({ health: 'fallback' }))}
${strip('Quelle veraltet: 24 Std. ohne erfolgreiches Lesen', 'Satz entschieden (ADR-0059 §8)', cycleBar({ health: 'stale' }))}
${strip('Eigene Quelle abgelehnt · A', 'empfohlen: Grund in der Zeile', cycleBar({ health: 'refusedA', tip: REFUSED_TIP }))}
${strip('Eigene Quelle abgelehnt · B', 'kurz, der Grund im ⓘ', cycleBar({ health: 'refusedB', tip: REFUSED_TIP, tipOpen: true }))}
</div>`, { css: '.cy-strip:last-child { padding-bottom: 90px; }' });

// 07h: the cycle bar at 390 px
const f07h = writeFrame('07h-leiste-390', `<div class="cy-card">${head('Bitcoin', 'BTC-USD · USD')}${toolbar({ range: 'Zyklus', phone: true })}${cycleBar({ health: 'ok', phone: true })}<p class="cy-elided">… das Chart</p></div>`, { width: 390 });
const f07h2 = writeFrame('07h2-leiste-390-veraltet', `<div class="cy-card">${strip('Veraltet', '', cycleBar({ health: 'stale', phone: true }))}${strip('Eigene Quelle abgelehnt · A', '', cycleBar({ health: 'refusedA', phone: true, tip: REFUSED_TIP }))}${strip('Von Hand · Litecoin', '', cycleBar({ health: 'manual', phone: true }))}</div>`, { width: 390 });

// ===========================================================================
// 07i: the sprint PR's closing act on Lane H (2026-11-13), the design lens's
// five findings, each before (a crop of the built screen on the synthetic
// review coins, 2x, shown at half size) and after (drawn here).

const before = (img, w) => `<figure class="cy-before"><img src="${img}" width="${w}" alt="vorher"></figure>`;
const zBasis = 'Bereich „Zyklus“: drei Monate vor dem letzten bestätigten Halving bis vier Monate nach dem Ende des späteren Bands; rechts von „heute“ nur das Halving-Fenster und die Bänder. ';

const f07i1a = writeFrame('07i1-vorher-zyklus', `<div class="cy-card">${before('07i1-vorher-zyklus.png', 955)}<p class="cy-hint">Gebaut: „Zyklus“ auf linearer Skala, die Kursachse ab −65,55 USD, das Tief-Band 3,8&nbsp;px hoch; kein Satz unter dem Chart (nur in der zugeklappten Offenlegung).</p></div>`, { width: 1000 });
const f07i1b = writeFrame('07i1-nachher-zyklus', `<div class="cy-card">${toolbar({ range: 'Zyklus' })}${chart(NOW, viewZ)}<p class="cy-basis mock-new">${zBasis}${basis}</p></div>`);

const edgeSvg = `<svg class="cy-edge" viewBox="0 0 560 230" width="560" height="230" role="img" aria-label="Beschriftungen am Rand">
<rect class="cy-edge__plot" x="20" y="10" width="500" height="200"/>
<polyline class="cy-edge__line" points="20,170 140,150 260,196 380,120 470,30 505,90 520,80"/>
<path class="cy-edge__top" d="M464,24 h12 l-6,8 z"/><text class="cy-edge__label" x="470" y="20" text-anchor="end">1.000 USD · 10.2019</text><text class="cy-edge__label is-muted" x="470" y="40" dx="-14" text-anchor="end">verankert · vorläufig</text>
<path class="cy-edge__low" d="M254,200 h12 l-6,-8 z"/><text class="cy-edge__label" x="260" y="186" text-anchor="middle">10,00 USD · 09.2014</text>
<path class="cy-edge__low" d="M499,98 h12 l-6,-8 z"/><text class="cy-edge__label" x="516" y="112" text-anchor="end">bisher 700 USD · 03.2020</text><text class="cy-edge__label is-muted" x="516" y="126" text-anchor="end">vorläufig</text>
<text class="cy-edge__note" x="24" y="226">Am rechten Rand endet die Beschriftung am Rand; ein Tief am Boden steht über seiner Marke.</text>
</svg>`;
const alignedSvg = `<svg class="cy-edge" viewBox="0 0 560 120" width="560" height="120" role="img" aria-label="Ausgerichtet: zwei Tiefs nebeneinander">
<rect class="cy-edge__plot" x="20" y="10" width="500" height="80"/>
<path class="cy-edge__low" d="M234,58 h12 l-6,-8 z"/><text class="cy-edge__label" x="240" y="72" text-anchor="middle">Tief bisher, Tag 477 (vorläufig)</text>
<path class="cy-edge__low" d="M230,62 h12 l-6,-8 z"/><text class="cy-edge__label" x="236" y="86" text-anchor="middle">Tief Tag 476</text>
<text class="cy-edge__note" x="24" y="112">Zwei Beschriftungen, die sich decken würden: die zweite eine Zeile tiefer.</text>
</svg>`;
const f07i3a = writeFrame('07i3-vorher-beschriftung', `<div class="cy-card">${before('07i3-vorher-rand.png', 381)}${before('07i3-vorher-boden.png', 560)}${before('07i3-vorher-ausgerichtet.png', 560)}<p class="cy-hint">Gebaut: am rechten Rand abgeschnitten, das Tief am Boden auf seiner Marke, zwei Tiefs in „Ausgerichtet“ übereinander.</p></div>`, { width: 600 });
const f07i3b = writeFrame('07i3-nachher-beschriftung', `<div class="cy-card mock-new">${edgeSvg}${alignedSvg}</div>`, { width: 600 });

const f07i4a = writeFrame('07i4-vorher-lesen', `<div class="cy-card">${before('07i4-vorher-lesen.png', 621)}<p class="cy-hint">Gebaut: der gesperrte Knopf sieht aus wie ein freier (oben, während der zehn Minuten), und ohne Wartezeit rückt er an den rechten Rand, weit weg von seinem Satz (unten).</p></div>`, { width: 680 });
const f07i4b = writeFrame('07i4-nachher-lesen', `<div class="cy-card">${['wait', 'free'].map((k) => `<div class="cy-bar__row cy-bar__health mock-new"><span class="cy-health"><span class="cy-dot is-ok" aria-hidden="true"></span>Kettenquelle: mempool.space · gelesen vor 4 Min.</span><button type="button" class="button-ghost cy-readnow"${k === 'wait' ? ' disabled' : ''}>Jetzt lesen</button>${k === 'wait' ? '<span class="cy-muted">vor weniger als 10 Min. gelesen · wieder in 6 Min.</span>' : ''}</div>`).join('')}<p class="cy-hint">Gesperrt: gedämpft, ohne Hover, der Mauszeiger „nicht erlaubt“. Der Knopf steht direkt hinter seinem Satz.</p></div>`, { width: 800, css: '.cy-readnow:disabled { color: var(--color-text-muted); background: var(--color-bg-muted); border-color: var(--color-border); cursor: not-allowed; opacity: .7; } .cy-bar__health { justify-content: flex-start; margin: 6px 0; }' });

const partsRows = [
  ['b', 'Nächstes Tief', 'Hülle der Teile', '29.12.2019 – 31.12.2020', '300,00 – 382,93 USD', 'beide Wege 333,33 – 374,13 USD', 'läuft'],
  ['p', 'Top → Tief', 'ab Top 10.2019 · Zeit n = 3, Kurs n = 3 <span class="badge badge--derived">vorläufig</span>', '02.04.2020 – 31.12.2020', '300,00 – 382,93 USD', '', 'läuft'],
  ['p', 'Tief → Tief', 'ab Tief 05.2018 · Zeit n = 2, Kurs n = 2', '29.12.2019 – 01.05.2020', '333,33 – 374,13 USD', '', 'läuft'],
  ['b', 'Nächstes Top', 'Hülle der Teile', '02.03.2021 – 01.07.2022', '4.500,00 – 5.599,50 USD', 'ein Kursweg <code>one_price_relation</code>', 'offen'],
  ['p', 'Tief → Top', 'wartet, bis das Tief des laufenden Zyklus endgültig ist (am nächsten Halving)', '', '', '', '—'],
];
const partsTable = `<table class="data-table cy-table cy-parts"><thead><tr><th>Band · Teil</th><th>Woher</th><th class="num">Zeitfenster</th><th class="num">Kurs</th><th>Wo die Wege übereinstimmen</th><th>Stand</th></tr></thead><tbody>${partsRows.map(([k, a, b, c, d, e, f]) => `<tr class="${k === 'b' ? 'cy-row-band' : ''}"><td>${k === 'b' ? `<b>${a}</b>` : a}</td><td>${b}</td><td class="num">${c}</td><td class="num">${d}</td><td>${e}</td><td>${f}</td></tr>`).join('')}</tbody></table>`;
const f07i5a = writeFrame('07i5-vorher-teile', `<div class="cy-card">${before('07i5-vorher-teile.png', 490)}<p class="cy-hint">Gebaut: jede Zelle ohne Umbruch, die Tabelle 1.333&nbsp;px breit im 954&nbsp;px breiten Rahmen, „Wo die Wege übereinstimmen“ und „Stand“ nur durch Scrollen; „vorläufig“ an einem Teil, der fehlt.</p></div>`, { width: 540 });
const f07i5b = writeFrame('07i5-nachher-teile', `<div class="cy-card mock-new" style="width:954px; box-sizing:border-box">${partsTable}<p class="cy-hint">„Woher“ bricht um, nur die Zahlen bleiben auf einer Zeile; ein fehlender Teil trägt keine Kennzeichen.</p></div>`, { width: 1000, css: '.cy-parts td { white-space: normal; } .cy-parts td.num { white-space: nowrap; }' });

// ===========================================================================
// The board

const BOARD_CSS = `
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 1240px; margin: 0 auto 28px; }
.mock-head h1 { margin: 0 0 6px; font-size: 22px; }
.mock-board > h2 { margin: 0 0 4px; font-size: 17px; font-weight: 760; }
.mock-board > h2 small { font-size: 12px; font-weight: 700; color: var(--color-accent); background: var(--color-accent-soft); padding: 2px 8px; border-radius: 999px; margin-left: 6px; vertical-align: 2px; }
.mock-board > h2 small.is-decided { color: var(--color-text-muted); background: var(--color-bg-muted); }
p.mock-note { margin: 0 0 12px; max-width: 135ch; font-size: 13px; color: var(--color-text-muted); line-height: 1.5; }
p.mock-note b { color: var(--color-text); }
.mock-synth { display: inline-block; padding: 1px 8px; border-radius: 999px; background: #fef3c7; color: #92400e; font-size: 11px; font-weight: 700; letter-spacing: .04em; vertical-align: 3px; }
.mock-pickbar { margin: 0 0 16px; padding: 12px 16px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 13px; line-height: 1.55; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-pickbar code, p.mock-note code { font-size: 12px; }
.mock-row { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
.mock-fig { margin: 0; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); }
.mock-tag.is-rec { color: var(--color-accent); background: var(--color-accent-soft); }
.mock-frame { width: max-content; border: 1px solid var(--color-border-strong); border-radius: 10px; overflow: hidden; box-shadow: var(--shadow-panel); background: var(--color-bg); }
.mock-frame iframe { display: block; border: 0; }
`;

const sized = (f, tag, rec = false) => ({ ...f, tag, rec, height: SIZES[f.file] || 700 });
const bdHtml = (sections, title, intro) => {
  const sec = sections.map((s) => `
<section class="mock-board">
  <h2>${s.title}${s.recommended ? ' <small>recommended</small>' : ''}${s.decided ? ' <small class="is-decided">decided</small>' : ''}</h2>
  <p class="mock-note">${s.note}</p>
  <div class="mock-row">${s.frames.map((f) => `<figure class="mock-fig">${f.tag ? `<span class="mock-tag${f.rec ? ' is-rec' : ''}">${f.tag}</span>` : ''}<div class="mock-frame"><iframe src="frames/${f.file}" width="${f.width}" height="${f.height}" title="${f.file}"></iframe></div></figure>`).join('\n')}</div>
</section>`).join('\n');
  return `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<link rel="stylesheet" href="${CSS_FROM_BOARD}">
<!-- Generated by build-c.js. Each frame under frames/ is a static page that
     links app.css; the block below is artboard chrome only. No script runs
     here. Synthetic data only. -->
<style id="board">${BOARD_CSS}</style>
</head>
<body>
<div class="mock-board mock-head"><h1>${esc(title)} <span class="mock-synth">SYNTHETISCH</span></h1>
${intro}</div>
${sec}
</body>
</html>
`;
};

const L = NOW.low.band, T = NOW.top.band;
const intro = `<p class="mock-note">Planning board 07 of Sprint 29, drawn on 2026-11-12 before any code, for the third sprint PR (ADR-0059, ADR-0060). It draws <b>the states these two records add</b> to the adopted I12 idea boards (<code>../ux-design-2026-11-10-idea-i12/</code>, boards 01–03), in the same visual language. The price line is the idea boards' synthetic series (public, rounded anchor points up to 06.10.2025, <b>invented after</b>, drawn dashed); the chain's heights and block times are invented. Every cycle figure is computed from that series by ADR-0060's rules: tops and lows as the peak and trough of each window's maximum drawdown, the 20&nbsp;% anchor, parts, hull, <code>agree</code> and the four states. Dashed outline: new.</p>
<div class="mock-pickbar">
<p><b>Decided by the records (drawn, not proposed):</b> the „Halving-Kette“ choice with none, Bitcoin, Bitcoin Cash, Litecoin, and a question before halving events are deleted (ADR-0059 §4, §11); no „Zyklen“ toggle without the view (ADR-0060 §1); the health line in the cycle bar with host and age, and „Kettenquelle seit ‹n› Std. ohne Antwort“ when stale (ADR-0059 §8); no shade where <code>agree</code> is <code>null</code>, whether <code>one_price_relation</code> or <code>parts_disjoint</code> (ADR-0060 §5); the count line „2 vollständige Zyklen, 1 unvollständiger; Kurse ab 09/2014“ (§12); the range „Zyklus“ reaching past today (§11).</p>
<p><b>Proposed here, the recommended option the default unless you comment:</b> Q1 the field sits below the master data with its own help and the chain's health line (flip „Halving-Kette ohne Zustand“); Q2 the question is an inline warning in the dialog that names the count, and the save button says it (A; flip „Eigener Bestätigungsdialog“); Q3 a bound security with fewer than two confirmed halvings shows no toggle, as ADR-0060 §1 says, and the edit form says why (A; flip „Zyklen-Schalter ausgegraut“, which would amend §1); Q4 a refused own URL names its reason in the bar (A; flip „Quellfehler nur im ⓘ“), and the edit form shows it too, because without halvings there is no bar; Q5 a „Jetzt lesen“ button beside the health line for <code>POST /chains/:chain/refresh</code>, showing the 10-minute wait (flip „Kein Lesen-Knopf“); Q6 the state words „offen“, „läuft“, „erreicht“, „verfehlt“, with „· Fenster vorbei“ for <code>window_ended</code> (flip „Stand als Satz“, the idea boards' „Fenster vorbei, Kurs war im Band“); Q7 <code>parts_disjoint</code> draws the two parts inside the outlined hull (A; flip „Uneinig nur als Hülle“); Q8 a disclosure „Bänder und ihre Teile“ under the chart lists each band, part, n and reason (flip „Teile nur im Payload“); Q9 partial observations carry a „Teil“ badge, provisional ones „vorläufig“.</p>
</div>`;

const sections = [
  { title: '① „Halving-Kette“ in „Wertpapier bearbeiten“', recommended: true, note: `ADR-0059 §4 and §11 decide a nullable <code>halving_chain</code>, written by the operator or an agent and never guessed, with the four choices. <b>Proposed (Q1):</b> the field below the master data, the select drawn open as a browser shows it; each option says where the halvings come from; below it the chain's health and what is stored. For <b>Litecoin and Bitcoin Cash</b> (no source, §2) the help says the halvings are entered by hand and that the height is checked against the chain's interval, and it counts the confirmed halvings against the two the view needs (Q3 A). <b>A refused own URL</b> shows here as well (Q4): on a freshly bound security no halving is ever written, so the view, its toggle and its cycle bar never appear, and the form is the one screen place left.`, frames: [sized(f07a, 'Bitcoin · Quelle aktuell', true), sized(f07a2, 'Litecoin · ohne Quelle', true), sized(f07a3, 'Bitcoin · eigene Quelle abgelehnt', true)] },
  { title: '② The question before the halving events go', recommended: true, note: `ADR-0059 §4: unbinding or rebinding deletes the security's <code>halving</code> events in the same write, journaled and counted, and „the screen asks first when there are any“. <b>A (recommended, Q2):</b> choosing another value turns the field into a warning that lists what goes (confirmed and estimated) and says the journal keeps it; the primary button names the count, so one click confirms and nothing opens on top of the dialog. <b>B:</b> „Speichern“ opens a second dialog that asks. Flip: „Eigener Bestätigungsdialog“.`, frames: [sized(f07b, 'A · im Dialog', true), sized(f07b2, 'B · zweiter Dialog')] },
  { title: '③ The cycle bar: binding and the chain source', recommended: true, note: `<b>Not bound</b> and <b>too few halvings</b>: ADR-0060 §1 answers <code>cycles: []</code> with <code>no_halving_chain</code> or <code>too_few_halvings</code>, and „the chart shows no toggle“ (A, recommended; the reason lives in the edit form, ①). B greys the toggle with the reason as its tooltip, which needs a sentence in §1. <b>Bound without a source:</b> the bar has no source to report, so it says the halvings are entered by hand, with no „Jetzt lesen“. <b>Health</b> (ADR-0059 §8): host and age; the fallback named as „Ersatz“; <b>stale</b> after 24 h without a successful run, in the record's own sentence, plus the last host and time and that the halving estimate dates from then (§13 item 9 of ADR-0060: the top band's time stays as last read). <b>Refused own URL</b> (§3, <code>url_not_allowed</code>): A names the reason in the line (recommended), B says „Konfigurationsfehler“ and puts the reason in the ⓘ (drawn open). The same line carries <code>wrong_chain</code> („falsche Kette: Genesis-Block passt nicht“) and <code>tip_behind</code> („Quelle hinkt hinterher“). <b>„Jetzt lesen“</b> (Q5) is proposed because §11 gives the on-demand run to API and MCP only.`, frames: [sized(f07g, '1200 px', true)] },
  { title: '④ Max with cycles on: the partial window and the count', decided: true, note: `ADR-0060 §1 and §12: the 2012–2016 window starts more than 7 days before the first stored close (17.09.2014), so it is <b>partial</b>: no top (<code>before_first_close</code>), and its low (${fmtUsd(NOW.W[0].low.p)}, ${fmtMonth(NOW.W[0].low.d)}) counts, marked partial. The hatched stretch is the window before the stored closes. The count line is the record's own wording, above the interval table, where every row shows its n and which observations come from the partial cycle (Q9's „Teil“ badge) or are provisional (the open window's anchored top). Today's n: ${['halving_to_top', 'top_to_low', 'low_to_top', 'top_to_top', 'low_to_low'].map((r) => `${REL_DE[r]} ${NOW.obs[r].length}`).join(', ')}, as §12 says.`, frames: [sized(f07c, '1200 px · Max')] },
  { title: '⑤ Range „Zyklus“ today: one price relation, and the band states', recommended: true, note: `The next top's parts are Halving → Top (time from the next halving's window, ADR-0059 §6: ${span(nextWindow.from, nextWindow.to)}, from the recent 2,016-block rate to the target) and Top → Top; Halving → Top borrows Top → Top's price, so <code>agree</code> is <code>null</code> with <code>one_price_relation</code> and the band carries no shade and says why (dashed edge proposed). Tief → Top waits until the 2024–2028 low is final. The next low's band (${range$(L.lo, L.hi)}, ${span(L.from, L.to)}) is the hull of Top → Tief and Tief → Tief, with „beide Wege“ ${range$(...L.agree)} shaded; its state reads „${stateDe(L.state)}“ (Q6). The disclosure (Q8) lists each part with its n, rule and state.`, frames: [sized(f07d, '1200 px · Zyklus')] },
  { title: '⑥ An open top that is not yet an anchor, and parts with too few observations', recommended: true, note: `The same series <b>as it stood on 10.02.2025</b>, to show the state (the app itself reads today only, ADR-0060 §10). The 2024 window's maximum drawdown so far is ${fmtPct(PAST.open.dd)}, short of the 20&nbsp;% anchor (§2), so its top is drawn hollow as „Top bisher“ and Top → Tief answers <code>no_top_yet</code>. Top → Top has one observation (2017 → 2021; the 2013 top is before the series), so it is absent with <code>too_few_observations</code>, and so is Halving → Top, whose price it borrows. The next top is then Tief → Top alone (n = 2, one end in the partial window): <code>one_price_relation</code> again. <b>Finding:</b> here the next low's band ends after the next top's, so §11's „Zyklus“ range (to four months after the end of the top band) would cut the low band off; the frame runs to four months after the later of the two (flip „Zyklus bis zum Top-Band“). <b>Two gaps the record leaves, filled here:</b> §5 names <code>one_price_relation</code> for the top band only; here the next low also has a single part with a price side of its own, and the board gives it the same reason (proposed wording for §5: „fewer than two parts with a price side of their own“). §4 does not say whether Halving → Top is absent when the Top → Top part it borrows from is; the board treats it as absent, with the lender's n. One more case of §13 item 4 shows on the same series: five days later (15.02.2025) the drawdown reaches −21&nbsp;%, the December 2024 top anchors, and the October 2025 top replaces it.`, frames: [sized(f07e, '1200 px · Stand 10.02.2025')] },
  { title: '⑦ Parts that do not agree: parts_disjoint', recommended: true, note: `On today's series the two ways to the next low overlap (${range$(...L.agree)}). To draw <code>parts_disjoint</code>, this frame uses a <b>what-if variant</b>: every close from 01.06.2025 on scaled by 0.9, so the open window's top is about 113&#8239;k&nbsp;$. Top → Tief then ends below where Tief → Tief begins, <code>agree</code> is <code>null</code>, and the hull spans both and the gap. <b>A (recommended, Q7):</b> the hull as an outline with the two parts filled inside, so the gap reads as „no way leads here“. <b>B:</b> the hull filled like any band, with the reason in its label only; it looks like one confident range. Flip: „Uneinig nur als Hülle“.`, frames: [sized(f07f, '1200 px · Variante')] },
  { title: '⑧ The cycle bar at 390 px', recommended: true, note: 'The toolbar wraps as today; „Zyklus“ joins the range buttons. In the bar, each label starts its own line, the switches wrap, and the health line wraps under them with „Jetzt lesen“ at its end. Stale, refused (A) and by hand at the same width.', frames: [sized(f07h, '390 px · aktuell', true), sized(f07h2, '390 px · veraltet, abgelehnt, von Hand', true)] },
  { title: '⑨ After the build: the closing act’s five design findings, before and after', recommended: true, note: `Added on 2026-11-13 by the sprint PR's closing act on Lane H, before the fixes, from the design lens's crops of the built screen (synthetic review coins). <b>1 and 2:</b> the chart drew the bands with no sentence under it (only in the closed disclosure), and „Zyklus“ landed on the linear scale with the price axis below 0. After: under the chart the basis of ④ ending „keine Prognose“, on „Zyklus“ with ⑤'s range sentence; choosing „Zyklus“, or arriving with <code>cycles=1</code>, turns the logarithmic scale on, as ⑤ draws it; and a price axis' lower pad stops at 0 (a percent axis at −100&nbsp;%). <b>3:</b> a label near the right edge ends at it, a low clamped to the floor puts its label above its marker, and two labels in „Ausgerichtet“ that would cover each other step a line apart. <b>4:</b> a disabled „Jetzt lesen“ looks disabled, and the button sits right after its sentence. <b>5:</b> in „Bänder und ihre Teile“ only the figures keep to one line, so the table fits at 1200&nbsp;px, and a part that is absent carries no badge.`, frames: [sized(f07i1a, 'vorher · Zyklus'), sized(f07i1b, 'nachher · log, Satz darunter', true), sized(f07i3a, 'vorher · Beschriftung'), sized(f07i3b, 'nachher', true), sized(f07i4a, 'vorher · Jetzt lesen'), sized(f07i4b, 'nachher', true), sized(f07i5a, 'vorher · Bänder und ihre Teile'), sized(f07i5b, 'nachher · 954 px', true)] },
];

fs.writeFileSync(path.join(__dirname, '07-cycle-states.html'), bdHtml(sections, 'Sprint 29 · 07 Halving-Zyklen: die Zustände aus ADR-0059 und ADR-0060', intro));

// A short summary for the caller (stdout only).
if (process.env.CY_DEBUG) {
  const p = (b) => b && `${fmtDate(b.from)}–${fmtDate(b.to)} ${Math.round(b.lo)}–${Math.round(b.hi)} agree=${b.agree && b.agree.map(Math.round)} ${b.reason} ${b.state && b.state.s}`;
  for (const [n, m] of [['NOW', NOW], ['PAST', PAST], ['VAR', VAR]]) {
    console.log(n, 'open dd', m.open.dd.toFixed(3), 'top', fmtDate(m.open.top.d), Math.round(m.open.top.p), 'anchored', m.open.anchored);
    console.log(' low', p(m.low.band), m.low.parts.map((q) => q.rel + (q.absent ? ':' + q.reason : ':' + p(q))).join(' | '));
    console.log(' top', p(m.top.band), m.top.parts.map((q) => q.rel + (q.absent ? ':' + q.reason : ':' + p(q))).join(' | '));
    console.log(' obs', Object.entries(m.obs).map(([k, v]) => k + '=' + v.map((o) => o.days + (o.f ? '/' + o.f.toFixed(2) : '')).join(',')).join(' '));
  }
  console.log('next halving', fmtDate(nextWindow.from), fmtDate(nextWindow.to));
}
console.log('built 07-cycle-states.html and frames/07*.html');
