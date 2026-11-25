// Builds the Sprint 32 planning boards: the widget pass after the owner's
// feedback of 2026-11-25. All figures are synthetic: seeded random walks and
// invented names, no portfolio figure, name or machine detail.
// Usage: node build.js (then node render.js)
const fs = require('fs');
const path = require('path');

const CSS = fs.readFileSync(path.join(__dirname, 'board.css'), 'utf8');
const nf = (d) => new Intl.NumberFormat('de-DE', { minimumFractionDigits: d, maximumFractionDigits: d });
const eur = (v) => nf(0).format(v) + ' €';
const pct = (v, d = 1) => (v > 0 ? '+' : v < 0 ? '−' : '') + nf(d).format(Math.abs(v)) + ' %';
const sgn = (v) => (v > 0 ? 'pos' : v < 0 ? 'neg' : '');

function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function walk(n, start, drift, vol, seed) {
  const r = rng(seed);
  const out = [start];
  for (let i = 1; i < n; i++) out.push(out[i - 1] * (1 + drift + (r() - 0.5) * vol));
  return out;
}

// ---------- chart helpers ----------
function scale(vals, h, pad, lo, hi) {
  const min = lo ?? Math.min(...vals);
  const max = hi ?? Math.max(...vals);
  return (v) => pad + (h - 2 * pad) * (1 - (v - min) / (max - min || 1));
}
function pathOf(vals, w, h, y, x0 = 0) {
  return vals.map((v, i) => `${i ? 'L' : 'M'}${(x0 + (i * (w - x0)) / (vals.length - 1)).toFixed(1)},${y(v).toFixed(1)}`).join('');
}
function spark(vals, w = 200, h = 34) {
  const y = scale(vals, h, 3);
  const p = pathOf(vals, w, h, y);
  return `<svg viewBox="0 0 ${w} ${h}" height="${h}" preserveAspectRatio="none"><path class="wd-area" d="${p}L${w},${h}L0,${h}Z"/><path class="wd-line" d="${p}"/></svg>`;
}
function lineChart(vals, bench, w, h, ticks) {
  const all = bench ? vals.concat(bench) : vals;
  const y = scale(all, h, 8);
  const x0 = 34;
  const p = pathOf(vals, w, h, y, x0);
  const min = Math.min(...all), max = Math.max(...all);
  let g = '';
  for (let i = 0; i <= 3; i++) {
    const v = min + ((max - min) * i) / 3;
    const yy = y(v).toFixed(1);
    g += `<line class="wd-gridl" x1="${x0}" x2="${w}" y1="${yy}" y2="${yy}"/><text class="wd-axis" x="0" y="${(+yy + 3).toFixed(1)}">${nf(0).format(v / 1000)}k</text>`;
  }
  const xs = (ticks || []).map((t, i) => `<text class="wd-axis" x="${(x0 + (i * (w - x0 - 30)) / (ticks.length - 1)).toFixed(0)}" y="${h - 1}">${t}</text>`).join('');
  const b = bench ? `<path class="wd-bench" d="${pathOf(bench, w, h, y, x0)}"/>` : '';
  return `<svg viewBox="0 0 ${w} ${h}" height="${h}">${g}<path class="wd-area" d="${p}L${w},${h - 12}L${x0},${h - 12}Z"/>${b}<path class="wd-line" d="${p}"/>${xs}</svg>`;
}
function stacked(bands, w, h, ticks) {
  const n = bands[0].length;
  const tot = Array.from({ length: n }, (_, i) => bands.reduce((s, b) => s + b[i], 0));
  const y = scale(tot, h - 12, 6, 0, Math.max(...tot) * 1.04);
  const x0 = 34;
  const xi = (i) => (x0 + (i * (w - x0)) / (n - 1)).toFixed(1);
  let base = Array(n).fill(0);
  let out = '';
  const max = Math.max(...tot) * 1.04;
  for (let k = 0; k <= 3; k++) {
    const v = (max * k) / 3;
    const yy = y(v).toFixed(1);
    out += `<line class="wd-gridl" x1="${x0}" x2="${w}" y1="${yy}" y2="${yy}"/><text class="wd-axis" x="0" y="${(+yy + 3).toFixed(1)}">${nf(0).format(v / 1000)}k</text>`;
  }
  bands.forEach((b, k) => {
    const top = base.map((v, i) => v + b[i]);
    let d = top.map((v, i) => `${i ? 'L' : 'M'}${xi(i)},${y(v).toFixed(1)}`).join('');
    for (let i = n - 1; i >= 0; i--) d += `L${xi(i)},${y(base[i]).toFixed(1)}`;
    out += `<path class="wd-band b${k + 1}" d="${d}Z"/>`;
    base = top;
  });
  out += `<path class="wd-line" style="stroke:var(--color-text);stroke-width:1.3" d="${tot.map((v, i) => `${i ? 'L' : 'M'}${xi(i)},${y(v).toFixed(1)}`).join('')}"/>`;
  out += (ticks || []).map((t, i) => `<text class="wd-axis" x="${(x0 + (i * (w - x0 - 30)) / (ticks.length - 1)).toFixed(0)}" y="${h - 1}">${t}</text>`).join('');
  return `<svg viewBox="0 0 ${w} ${h}" height="${h}">${out}</svg>`;
}
function bars(vals, w, h) {
  const max = Math.max(...vals);
  const bw = w / vals.length;
  return `<svg viewBox="0 0 ${w} ${h}" height="${h}">${vals.map((v, i) => `<rect x="${(i * bw + 2).toFixed(1)}" y="${(h - 10 - ((h - 14) * v) / max).toFixed(1)}" width="${(bw - 4).toFixed(1)}" height="${(((h - 14) * v) / max).toFixed(1)}" rx="2" style="fill:var(--color-accent);opacity:.7"/>`).join('')}${['Dez', 'Mär', 'Jun', 'Sep', 'Nov'].map((m, i) => `<text class="wd-axis" x="${(i * (w - 22)) / 4}" y="${h - 1}">${m}</text>`).join('')}</svg>`;
}
function cycleMini(w, h) {
  // Three humps on a log-like scale, halvings dashed, the next band shaded.
  const n = 160;
  const r = rng(56);
  const v = [];
  for (let i = 0; i < n; i++) {
    // Each cycle: a rise to a top about a third in, a fall to a low, a slow base.
    const c = (i % 48) / 48;
    const cyc = Math.floor(i / 48);
    const top = 1.5 * (1 - cyc * 0.2);
    const hump = top * Math.exp(-((c - 0.38) ** 2) / 0.018) - 0.35 * Math.exp(-((c - 0.62) ** 2) / 0.01);
    v.push(1 + cyc * 0.85 + hump + (r() - 0.5) * 0.1);
  }
  const y = scale(v, h - 12, 6, 0.4, 4.4);
  const xs = (i) => (i * (w - 70)) / (n - 1);
  let d = v.map((p, i) => `${i ? 'L' : 'M'}${xs(i).toFixed(1)},${y(p).toFixed(1)}`).join('');
  let out = '';
  [0, 48, 96, 144].forEach((i, k) => {
    const x = xs(i).toFixed(1);
    out += `<line x1="${x}" x2="${x}" y1="4" y2="${h - 12}" style="stroke:var(--color-warning);stroke-width:1;${k === 3 ? '' : ''}"/>`;
  });
  const xe = xs(n - 1);
  out += `<line x1="${(xe + 40).toFixed(1)}" x2="${(xe + 40).toFixed(1)}" y1="4" y2="${h - 12}" style="stroke:var(--color-warning);stroke-dasharray:4 3"/>`;
  out += `<rect x="${(xe + 6).toFixed(1)}" y="${y(4.2).toFixed(1)}" width="26" height="${(y(3.3) - y(4.2)).toFixed(1)}" rx="3" style="fill:color-mix(in oklab, var(--color-text-muted) 22%, transparent);stroke:var(--color-text-muted);stroke-dasharray:3 2"/>`;
  out += `<rect x="${(xe + 44).toFixed(1)}" y="${y(2.9).toFixed(1)}" width="22" height="${(y(2.0) - y(2.9)).toFixed(1)}" rx="3" style="fill:color-mix(in oklab, var(--color-text-muted) 22%, transparent);stroke:var(--color-text-muted);stroke-dasharray:3 2"/>`;
  out += ['2016', '2020', '2024', '2028'].map((t, i) => `<text class="wd-axis" x="${(i === 3 ? xe + 30 : xs(i * 48) + 2).toFixed(0)}" y="${h - 1}">${t}</text>`).join('');
  return `<svg viewBox="0 0 ${w} ${h}" height="${h}">${out}<path class="wd-line" d="${d}"/></svg>`;
}

// ---------- synthetic data ----------
const cats = [0.38, 0.24, 0.16, 0.12, 0.1].map((s, k) => walk(260, 210000 * s, 0.0007 + k * 0.0001, 0.02 + k * 0.004, 20 + k));
// The total is the sum of the bands, so every widget shows the same figure.
const total = cats[0].map((_, i) => cats.reduce((sum, c) => sum + c[i], 0));
const bench = walk(260, 210000, 0.0005, 0.016, 11);
const catNames = ['Aktien Welt', 'Aktien Europa', 'Anleihen', 'Krypto', 'Cash'];
const last = total[total.length - 1];
const months = ['Jan', 'Apr', 'Jul', 'Okt', 'Jan'];

// ---------- widgets ----------
const head = (t, opts = {}) =>
  `<div class="wd-h">${opts.pin ? `<span class="wd-pin">${opts.pin}</span>` : ''}<span class="wd-t">${t}</span>${opts.info === false ? '' : '<span class="wd-i">i</span>'}<span class="wd-sp"></span>${opts.chips ? `<span class="wd-chips">${opts.chips.map((c) => `<span${c === opts.on ? ' class="on"' : ''}>${c}</span>`).join('')}</span>` : ''}<span class="wd-more">⋯</span></div>`;
const foot = (l, a) => `<div class="wd-foot"><span>${l}</span>${a ? `<a>${a} →</a>` : ''}</div>`;
const wd = (size, inner, extra = '') => `<section class="wd wd--${size}"${extra}>${inner}</section>`;
const CHIPS = ['1W', '1M', '3M', 'YTD', '1J', 'Max'];

const W = {
  total: (s = 's') => wd(s, `${head('Gesamtwert')}<div class="wd-kpi">${eur(last)}</div><div class="wd-sub"><span class="pos">+1,24 % heute</span> · <span class="pos">+2.980 €</span></div><div class="wd-body" style="justify-content:flex-end">${spark(total.slice(-60), 200, 26)}</div>`),
  perfS: () => wd('s', `${head('Wertentwicklung')}<div class="wd-kpi">+4,8 %<small class="wd-muted">3M</small></div><div class="wd-sub">TTWROR · ggü. Welt-Index +3,1 %</div><div class="wd-body" style="justify-content:flex-end">${spark(total.slice(-65), 200, 26)}</div>`),
  perfM: (s = 'm', pin) => wd(s, `${head('Wertentwicklung', { chips: CHIPS, on: '3M', pin })}<div class="wd-sub" style="margin:-2px 0 4px"><b class="pos">+4,8 %</b> TTWROR · <span class="wd-muted">gestrichelt: Welt-Index +3,1 %</span></div><div class="wd-body">${lineChart(total.slice(-65), bench.slice(-65).map((v) => v * (total[195] / bench[195])), 460, 150, ['Aug', 'Sep', 'Okt', 'Nov'])}</div>${foot('Gesamt · alle Depots', 'Ganze Ansicht')}`),
  perfL: (s = 'l', pin) => wd(s, `${head('Wertentwicklung nach Kategorien', { chips: CHIPS, on: '1J', pin })}<div class="wd-sub" style="margin:-2px 0 4px">Wert · Ebene <b>Kategorien</b> · <b class="pos">+11,6 %</b> TTWROR im Jahr</div><div class="wd-body">${stacked(cats, 600, 228, months)}<div class="wd-leg">${catNames.map((c, k) => `<span><i class="b${k + 1}"></i>${c}</span>`).join('')}</div></div>${foot('Klick auf ein Band filtert, die Ebene bleibt', 'Ganze Ansicht')}`),
  movers: (s = 'm') => wd(s, `${head('Tops und Flops', { chips: ['Tag', 'Woche', 'Monat', 'YTD'], on: 'Woche' })}<div class="wd-two"><div><h4>Höchste</h4><table class="wd-tab">${[['Halbleiter AG', 6.8, 1210], ['Welt-ETF', 2.1, 980], ['Netz Versorger', 3.9, 410], ['Pharma Nord', 1.7, 220]].map(([n, p, e]) => `<tr><td>${n}</td><td class="num pos">${pct(p)}</td><td class="num pos">+${eur(e)}</td></tr>`).join('')}</table></div><div><h4>Niedrigste</h4><table class="wd-tab">${[['Krypto-Münze', -5.2, -860], ['Autobauer Süd', -3.4, -390], ['Rohstoff-ETC', -1.9, -170], ['Bank West', -0.8, -60]].map(([n, p, e]) => `<tr><td>${n}</td><td class="num neg">${pct(p)}</td><td class="num neg">−${eur(-e)}</td></tr>`).join('')}</table></div></div>${foot('Beitrag in € zum Depot · Basis im ⓘ', 'In Vermögen')}`),
  moversS: () => wd('s', `${head('Tops und Flops')}<ul class="wd-list"><li><span class="wd-sp">Halbleiter AG</span><span class="pos">+6,8 %</span></li><li><span class="wd-sp">Krypto-Münze</span><span class="neg">−5,2 %</span></li></ul><div class="wd-sub" style="margin-top:auto">diese Woche</div>`),
  drift: (s = 't', hints = true) => wd(s, `${head('Allokation und Drift')}<div class="wd-sub" style="margin:-2px 0 6px">Zielplan „Basis“ · Toleranz ±3 Punkte</div><table class="wd-tab"><tr><th>Kategorie</th><th class="num">Ist</th><th class="num">Soll</th><th>Drift</th></tr>${[['Aktien Welt', 41.2, 40, 1.2], ['Aktien Europa', 21.0, 25, -4.0], ['Anleihen', 14.9, 15, -0.1], ['Krypto', 13.6, 10, 3.6], ['Cash', 9.3, 10, -0.7]].map(([n, i, z, d]) => `<tr><td>${n}</td><td class="num">${nf(1).format(i)} %</td><td class="num">${nf(0).format(z)} %</td><td><span class="wd-drift"><b style="${d >= 0 ? `left:50%;width:${Math.min(50, d * 8)}%` : `right:50%;width:${Math.min(50, -d * 8)}%`};${Math.abs(d) > 3 ? 'background:var(--color-warning)' : ''}"></b></span> <span class="${Math.abs(d) > 3 ? '' : 'wd-muted'}" style="font-size:10.5px;${Math.abs(d) > 3 ? 'color:var(--color-warning);font-weight:700' : ''}">${d > 0 ? '+' : d < 0 ? '−' : ''}${nf(1).format(Math.abs(d))}</span></td></tr>`).join('')}</table>${hints ? `<div class="wd-sub" style="margin-top:8px;line-height:1.45"><b style="color:var(--color-text)">Rechnerisch zum Soll</b> (nur Anzeige, kein Auftrag): Aktien Europa ≈ +8.400 €, Krypto ≈ −7.560 €</div>` : ''}${foot('2 außerhalb der Toleranz', 'Ziele bearbeiten')}`),
  quality: () => wd('s', `${head('Datenqualität')}<ul class="wd-list"><li><span class="wd-dot"></span><span class="wd-sp">2 Kurse älter als 5 Tage</span></li><li><span class="wd-dot"></span><span class="wd-sp">1 Wertpapier ohne Kategorie</span></li></ul>${foot('', 'Prüfen')}`),
  due: () => wd('s', `${head('Fällig', { info: false })}<ul class="wd-list"><li><span class="wd-sp">Ausschüttung Welt-ETF</span><span class="wd-muted">28.11.</span></li><li><span class="wd-sp">Prognose prüfen</span><span class="wd-muted">02.12.</span></li></ul>`),
  risk: () => wd('s', `${head('Konzentration')}<div class="wd-kpi">0,082<small class="wd-muted">HHI</small></div><div class="wd-sub">Größte Position 9,8 % · Grenze 15 %</div>`),
  crashes: (s = 'm') => wd(s, `${head('Crashes im Vergleich', { chips: ['Im Depot', 'Katalog'], on: 'Im Depot' })}<table class="wd-tab"><tr><th>Fenster</th><th class="num">Welt-Index</th><th class="num">Depot heute</th><th class="num">Tage</th></tr>${[['Herbst-Ausverkauf', -11.4, -9.1, 23], ['Zinsschock', -26.0, -22.7, 282], ['Pandemie-Crash', -33.9, -29.5, 33], ['Zollschock', -14.8, -17.2, 9], ['Zwei-Tage-Einbruch', -6.1, -7.4, 2]].map(([n, b, d, t], i) => `<tr${i >= 3 ? ' style="background:color-mix(in oklab, var(--color-accent) 6%, transparent)"' : ''}><td>${n}</td><td class="num neg">${pct(b)}</td><td class="num neg">${pct(d)}</td><td class="num">${t}</td></tr>`).join('')}</table><div class="wd-sub" style="margin-top:6px">hinterlegt: kurze Einbrüche nach der engeren Regel (I55, Vorschlag)</div>${foot('Benchmark Welt-Index · Preis, ohne Urteil', 'Alle Fenster')}`),
  cycle: (s = 'm') => wd(s, `${head('Bitcoin-Zyklus', { chips: ['Alle', 'Aktueller'], on: 'Alle' })}<div class="wd-body">${cycleMini(460, 150)}</div><div class="wd-sub">Max, alle Zyklen · graue Felder: Analog-Band für Tief und Top des nächsten Zyklus (n = 3, beide Enden)</div>${foot('Halvings orange, das nächste geschätzt', 'Ganze Ansicht')}`),
  news: (s = 'm') => wd(s, `${head('Nachrichten, eingeordnet')}<ul class="wd-list">${[['hoch', 'Halbleiter AG hebt die Jahresprognose an', 'Umsatzplus im Kerngeschäft; trifft 6,1 % des Depots', 'Agentur · Stufe 1'], ['hoch', 'Notenbank lässt den Leitzins unverändert', 'betrifft Anleihen und Bank West', 'Agentur · Stufe 1'], ['mittel', 'Autobauer Süd senkt die Marge', 'Position seit drei Wochen schwächer', 'Fachpresse · Stufe 2']].map(([r, t, why, src]) => `<li style="display:block"><span class="wd-rate">${r}</span> <b>${t}</b><br><span class="wd-muted">${why} · ${src}</span></li>`).join('')}</ul>${foot('12 noch ohne Einordnung, ausgeblendet', 'Alle')}`),
  snapshots: (s = 'w') => wd(s, `${head('Snapshots')}<div style="display:flex;gap:14px;align-items:flex-end"><div><div class="wd-kpi" style="font-size:18px">01.11.2026</div><div class="wd-sub">letzter von 14 · seitdem <span class="pos">+2,3 %</span></div></div><div style="flex:1">${spark(total.slice(-120, -10), 240, 34)}</div></div>${foot('', 'Vergleichen')}`),
  income: (s = 'w') => wd(s, `${head('Einkommen', { chips: ['Monat', 'Jahr'], on: 'Monat' })}<div class="wd-body">${bars([120, 40, 310, 90, 60, 420, 130, 50, 290, 80, 70, 460], 420, 62)}</div>`),
  predictions: () => wd('s', `${head('Prognosen')}<div class="wd-kpi">4<small class="wd-muted">offen</small></div><div class="wd-sub">11 aufgelöst · Kalibrierung im ⓘ</div>`),
  tax: () => wd('s', `${head('Steuer')}<div class="wd-kpi" style="font-size:18px">412 €</div><div class="wd-sub">Freibetrag noch frei im Jahr</div>`),
};

// ---------- page shell ----------
function page(title, body) {
  return `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Generated by build.js. Sprint 32 planning board: static HTML and inline
     SVG from synthetic series; the colours come from app.css. No script runs. -->
<style id="board">
${CSS}
</style>
</head>
<body>
${body}
</body>
</html>
`;
}
const SYN = '<span class="mock-synth">SYNTHETISCH</span>';
const tag = (k, t) => `<span class="mock-tag mock-tag--${k}">${t}</span>`;
const editW = (html, sizes, on) => html.replace('</section>', `<span class="wd-handle"></span><span class="wd-x">×</span><span class="wd-sizes">${sizes.map((s) => `<span${s === on ? ' class="on"' : ''}>${s}</span>`).join('')}</span></section>`);
// A mini grid: items [label, col, row, w, h, cls].
const mini = (items, rows) => `<div class="sp-mini" style="grid-template-rows:repeat(${rows},26px)">${items.map(([l, c, r, w, h, cls]) => `<div class="${cls || ''}" style="grid-column:${c} / span ${w};grid-row:${r} / span ${h}">${l}</div>`).join('')}</div>`;

const totalM = (style = '') => `<section class="wd wd--m"${style}>${head('Gesamtwert', { chips: ['folgt · 1J'], on: '' })}<div class="wd-kpi">${eur(last)} <small class="pos">+11,6 % · 1J</small></div><div class="wd-body">${lineChart(total.slice(-260).filter((_, i) => i % 2 === 0), null, 330, 120, ['Dez', 'Mär', 'Jun', 'Sep', 'Nov'])}</div>${foot('Wert über den Zeitraum · Ansicht Alles', 'In Vermögen')}</section>`;

// ---------- board 01: resize and move, the others make room ----------
function board01() {
  const before = [['Gesamtwert', 1, 1, 3, 1, 'hl'], ['Datenqualität', 4, 1, 3, 1], ['Fällig', 7, 1, 3, 1], ['Abseits', 10, 1, 3, 1], ['Wertentwicklung', 1, 2, 8, 3], ['Drift', 9, 2, 4, 3], ['Tops und Flops', 1, 5, 6, 2], ['Crashes', 7, 5, 6, 2]];
  const afterA = [['Gesamtwert · M', 1, 1, 6, 2, 'hl'], ['Datenqualität', 7, 1, 3, 1, 'mv'], ['Fällig', 10, 1, 3, 1, 'mv'], ['Abseits', 7, 2, 3, 1, 'mv'], ['Wertentwicklung', 1, 3, 8, 3, 'mv'], ['Drift', 9, 3, 4, 3, 'mv'], ['Tops und Flops', 1, 6, 6, 2, 'mv'], ['Crashes', 7, 6, 6, 2, 'mv']];
  const afterB = [['Gesamtwert · M', 1, 1, 6, 2, 'hl'], ['Datenqualität', 1, 3, 3, 1, 'mv'], ['Fällig', 7, 1, 3, 1], ['Abseits', 10, 1, 3, 1], ['frei', 7, 2, 6, 1, 'gap'], ['frei', 4, 3, 9, 1, 'gap'], ['Wertentwicklung', 1, 4, 8, 3, 'mv'], ['Drift', 9, 4, 4, 3, 'mv'], ['Tops und Flops', 1, 7, 6, 2, 'mv'], ['Crashes', 7, 7, 6, 2, 'mv']];
  const today = `<div class="wd-edit"><div class="sp-flash">⚠ Gesamtwert kann Größe M nicht annehmen: es würde Datenqualität überdecken.</div><div class="mock-subbar">… sechs Widgets weiter unten …</div><div class="wd-grid" style="grid-auto-rows:96px">${editW(W.drift('t', false), ['M', 'T'], 'T')}<div style="grid-column:span 5"></div>${editW(W.crashes('m'), ['M', 'L'], 'M').replace('<section class="wd wd--m"', '<section class="wd wd--m" style="position:relative"')}</div><p class="sp-cap">Geklickt wird unten auf „L“ bei Crashes, die Meldung steht oben, außerhalb des Bildes, und sagt nicht, was zu tun ist.</p></div>`;
  return page('Sprint 32 · Board 01 — Größe ändern', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 01 — Größe ändern und verschieben: die anderen rücken nach ${SYN}</h1>
<p class="mock-note">Dein Befund vom 25.11.: „Wenn ich bei einem S auf M klicke, bekomme ich die Meldung, dass die anderen Widgets überdeckt würden … also was muss ich machen, die löschen? … wenn ich von S auf M schalte, sollen die sich einfach alle verschieben, dann muss ich die halt wieder zurecht rücken.“ Heute (ADR-0062 §2, §7) verweigert der Bearbeiten-Modus jede Überlappung und meldet das ganz oben.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Empfehlung A:</b> eine Größenänderung oder ein Verschieben gelingt immer. Was im Weg ist, rückt nach unten; danach rutscht alles nach oben, bis keine Lücke bleibt (wie bei Grafana oder Home Assistant). Die Rückmeldung steht <b>am Widget</b>, mit „Rückgängig“. <b>Umschalten:</b> „Lücken stehen lassen“ (B) oder „Überlappung verweigern“ (heute).</p></div></section>
<section class="mock-board"><h2>① Heute ${tag('before', 'vorher')}</h2>${today}</section>
<section class="mock-board"><h2>② Was passiert, wenn „Gesamtwert“ von S auf M wechselt <small>dieselbe Ausgangslage, zwei Regeln</small></h2>
<div class="sp-row"><div>${tag('rec', 'A · empfohlen')}<div class="sp-flow">${mini(before, 7)}<div class="sp-arrow">→</div>${mini(afterA, 7)}</div><p class="sp-cap"><b>Nach unten schieben, dann nach oben aufrücken.</b> Gesamtwert behält seinen Platz und wächst; Datenqualität, Fällig und Abseits rücken in die frei gebliebenen Felder rechts daneben, alles darunter rückt um eine Reihe. Orange umrandet: was sich bewegt hat. Keine Lücke, kein Widget verschwindet.</p></div>
<div>${tag('alt', 'B')}<div class="sp-flow">${mini(before, 9)}<div class="sp-arrow">→</div>${mini(afterB, 9)}</div><p class="sp-cap"><b>Nur nach unten schieben.</b> Was überdeckt würde, rutscht unter das gewachsene Widget; die Reihen darüber bleiben, wo sie sind. Es entstehen Lücken (rot gestrichelt), die du von Hand füllst. Vorhersehbarer, aber nach jeder Änderung Aufräumarbeit.</p></div></div></section>
<section class="mock-board"><h2>③ Die Rückmeldung am Widget, nicht oben ${tag('rec', 'A')}</h2>
<div class="wd-edit" style="max-width:820px"><div class="wd-grid" style="grid-auto-rows:112px;padding-bottom:40px">${editW(totalM(' style="position:relative;overflow:visible"'), ['S', 'W', 'M'], 'M').replace('</section>', '<div class="sp-toast">Gesamtwert ist jetzt M · 7 Widgets sind nachgerückt <a>Rückgängig</a></div></section>')}${editW(W.quality(), ['S', 'M'], 'S').replace('wd wd--s', 'wd wd--s sp-moved')}${editW(W.due(), ['S'], 'S').replace('wd wd--s', 'wd wd--s sp-moved')}</div></div>
<p class="mock-note" style="margin-top:8px">Die Meldung erscheint unter dem Widget, das du angeklickt hast, und wird vom Screenreader vorgelesen (heute: oben im Seitenkopf). „Rückgängig“ nimmt genau diesen Schritt zurück, Strg+Z ebenso; „Zurücksetzen“ verwirft weiter alles seit „Bearbeiten“. Eine Meldung, die etwas verweigert, gibt es nur noch an zwei Stellen: das 41. Widget (Obergrenze 40) und ein Widget, das in keine Reihe bis 200 mehr passt; beide stehen ebenfalls am Widget. Auch beim Ziehen gilt A: wohin du ein Widget ziehst, dort landet es, und die anderen weichen.</p></section>
<section class="mock-board"><h2>④ „Gesamtwert“ in seinen Größen <small>heute wirkt M unübersichtlich</small></h2>
<div class="sp-row3"><div>${tag('rec', 'S · bleibt')}<div class="wd-grid" style="grid-template-columns:1fr;grid-auto-rows:112px">${W.total('s').replace('wd--s', 'wd--s" style="grid-column:span 1')}</div><p class="sp-cap">Eine Zahl, die Veränderung im Zeitraum, eine kleine Linie.</p></div>
<div>${tag('rec', 'W · neu')}<div class="wd-grid" style="grid-template-columns:1fr;grid-auto-rows:112px"><section class="wd" style="grid-column:span 1">${head('Gesamtwert')}<div class="sp-kpis" style="flex-wrap:nowrap;gap:18px"><div style="min-width:0"><div class="l">Wert</div><div class="v">${eur(last)}</div></div><div style="min-width:0"><div class="l">1J</div><div class="v pos">+11,6 %</div></div><div style="min-width:0"><div class="l">Gewinn</div><div class="v pos">+21.480 €</div></div></div>${foot('Ansicht Alles', 'In Vermögen')}</section></div><p class="sp-cap">Breit und flach: drei Kennzahlen nebeneinander, ohne Chart. Für die oberste Reihe gedacht.</p></div>
<div>${tag('rec', 'M · neu gezeichnet')}<div class="wd-grid" style="grid-template-columns:1fr;grid-auto-rows:112px">${totalM(' style="grid-column:span 1;grid-row:span 2"')}</div><p class="sp-cap">Eine große Zahl und darunter nur der Wertverlauf über den Zeitraum. Alles Weitere (Kategorien, Hinweise) gehört in andere Widgets.</p></div></div>
<p class="mock-note">Die Regel für jede Art, nicht nur für Gesamtwert: <b>jede Größe zeigt mehr vom Gleichen, nie etwas anderes.</b> S eine Zahl, W die Zahl mit zwei, drei Begleitern, M dieselbe Zahl mit ihrem Verlauf, L die Zahl, der Verlauf und eine Aufteilung. Eine Größe, die nichts Lesbares mehr hinzufügt, wird gar nicht angeboten. Sprint 32 prüft jede vorhandene Art gegen diese Regel und streicht Größen, die sie verletzen (Datenqualität M und Abseits M bleiben, weil sie die Liste zeigen, die S nur zählt).</p></section>
`);
}

// ---------- board 03: new dashboard, templates to choose from ----------
function tplMini(items) {
  return `<div class="wd-mini">${items.map((c) => `<div class="${c}"></div>`).join('')}</div>`;
}
function board03() {
  const fromWealth = [
    ['Überblick', 'wie heute „/“', ['s', 's', 's', 's', 'l', 't', 'm', 'm'], 11],
    ['Bestände', 'Vermögen › Bestände', ['z', 'z', 'z', 'z', 'z'], 9],
    ['Allokation & Ziele', 'Vermögen › 2. Tab', ['z', 'z', 'z'], 4],
    ['Cashflow', 'Vermögen › 3. Tab', ['z', 'z', 'z', 'z'], 6],
    ['Snapshots', 'Vermögen › 4. Tab', ['z', 'z'], 2],
    ['Steuer', 'Vermögen › 5. Tab', ['z', 'z'], 3],
    ['Risiko', 'Vermögen › 6. Tab', ['z', 'z', 'z', 'z'], 5],
    ['Prognosen', 'Vermögen › 7. Tab', ['z', 'z'], 2],
  ];
  const themes = [
    ['Performance', 'Rendite in allen Zeiträumen', ['s', 's', 's', 's', 'l', 't', 'm', 'm'], 7, 'Wertentwicklung, Rendite-Heatmap, Tops und Flops, Beitrag je Position'],
    ['Krypto Lover', 'Zyklus, Halving, Krypto-Ansicht', ['l', 't', 'm', 'm'], 5, 'Bitcoin-Zyklus, Wertentwicklung und Tops/Flops der gewählten Ansicht, Abstand zum Hoch, Crashes'],
    ['Rücksetzer', 'dein Wunsch „Buy The Dip“, Name offen', ['m', 'm', 'm', 'm'], 5, 'Abstand zum 52-Wochen-Hoch, Drawdown je Wertpapier, Crashes im Vergleich, Tops und Flops 1W'],
    ['Einkommen & Steuer', 'was hereinkommt und abgeht', ['w', 'w', 'm', 'm'], 5, 'Einkommen, Handelsaktivität, Freibetrag, Gebühren und Steuern'],
  ];
  const card = ([n, sub, cells, count, list], on) => `<div class="sp-tpl${on ? ' on' : ''}">${tplMini(cells)}<b>${n}</b><div>${sub}</div><div class="meta">${count} Widgets${list ? ' · ' + list : ''}</div></div>`;
  return page('Sprint 32 · Board 03 — Neues Dashboard', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 03 — „Neues Dashboard“: Vorlagen zur Auswahl ${SYN}</h1>
<p class="mock-note">Dein Wunsch: „Wenn ich auf neues Dashboard aus Vorlage klicke, will ich lieber Vorlagen zur Auswahl haben, so wie die für Risiko, Vermögen, Allokation usw. Man könnte noch Vorlagen bauen wie Krypto Lover oder Buy The Dip.“ Heute bietet „Neues Dashboard“ nur „Leer“ und „Überblick“.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Empfehlung:</b> „Neues Dashboard“ öffnet eine Galerie. Zuerst „Leer“, dann die Vorlagen aus Vermögen (dieselben, die als Start-Dashboards mitkommen, Board 02), dann Themen-Vorlagen. Jede Karte zeigt ihr Raster im Kleinen, die Zahl der Widgets und welche. Ein Klick öffnet einen kleinen Dialog: Name (vorbelegt, änderbar) und, wo die Vorlage es braucht, die Ansicht. „Anlegen“ speichert die Kopie und öffnet sie.</p><p><b>Deine Frage (nur du kannst sie beantworten):</b> darf eine mitgelieferte Vorlage „Buy The Dip“ heißen? Der Name ist eine Handlungsanweisung („kauf“), und „keine Beratung“ gehört zu dem, was Portfolixir ist. Empfohlen: „Rücksetzer“, mit denselben Widgets; Umschalten: „Buy The Dip heißt Buy The Dip“. Ein eigenes Dashboard darfst du natürlich nennen, wie du willst.</p></div></section>
<section class="mock-board"><h2>① Die Galerie ${tag('rec', 'empfohlen')}</h2>
<div class="mock-frame"><div class="sp-gal"><div class="sp-tpl" style="display:grid;place-items:center;min-height:118px;border-style:dashed;color:var(--color-accent);font-weight:700">＋ Leer beginnen</div>
<h4>Wie die bisherigen Seiten · die Start-Dashboards</h4>${fromWealth.map((t) => card(t, t[0] === 'Risiko')).join('')}
<h4>Themen</h4>${themes.map((t) => card(t, false)).join('')}</div></div>
<p class="sp-cap">Breite Balken im Raster sind die neue Größe „Zeile“ (Board 02): ein Widget über die ganze Breite, so hoch wie sein Inhalt. Eine Vorlage, deren Widgets noch nicht alle gebaut sind, erscheint nicht (ADR-0062 §3 gilt weiter): Sprint 32 bietet Leer, Überblick, Bestände, Allokation & Ziele, Snapshots, Risiko, Krypto Lover und Rücksetzer; Cashflow, Steuer, Prognosen, Performance und Einkommen & Steuer kommen mit ihren Widgets im nächsten Widget-Sprint.</p></section>
<section class="mock-board"><h2>② Nach dem Klick</h2>
<div class="sp-row"><div class="sp-dialog"><h4>Dashboard aus „Krypto Lover“</h4><div class="sp-field"><label>Name</label><span class="sp-input">Krypto Lover</span></div><div class="sp-field"><label>Ansicht</label><span class="mock-select">Krypto ▾</span></div><p class="sp-cap" style="margin:0 0 10px">Die Ansicht gilt für alle Widgets dieses Dashboards, die eine nehmen; ein einzelnes Widget kann sie in seinem ⋯-Menü weiter überschreiben. Ohne Wahl: deine Standardansicht.</p><div style="display:flex;gap:8px;justify-content:flex-end"><span class="wd-btn">Abbrechen</span><span class="wd-btn wd-btn--acc">Anlegen</span></div></div>
<div class="sp-dialog"><h4>Dashboard aus „Risiko“</h4><div class="sp-field"><label>Name</label><span class="sp-input">Risiko</span></div><p class="sp-cap" style="margin:0 0 10px">Ohne eigene Ansicht: das Dashboard folgt der Ansicht oben in der Leiste, wie heute. Gibt es schon ein Dashboard mit dem Namen, wird „Risiko (2)“ vorgeschlagen.</p><div style="display:flex;gap:8px;justify-content:flex-end"><span class="wd-btn">Abbrechen</span><span class="wd-btn wd-btn--acc">Anlegen</span></div></div></div>
<p class="mock-note" style="margin-top:10px">Neu dafür: ein Dashboard darf eine <b>eigene Ansicht</b> speichern (ADR-0062 §2 kennt die Ansicht heute nur pro Widget). Ohne sie folgt es wie bisher der Ansicht der Adresse oder deiner Standardansicht. Die Krypto-Vorlage braucht das, weil sie sonst „alles“ zeigt.</p></section>
`);
}

// ---------- board 04: periods, one menu, own periods kept ----------
function board04() {
  const roll = ['1T', '1W', '1M', '3M', '6M', '1J', '3J', '5J', 'Max'];
  const cal = ['lfd. Monat', 'Vormonat', 'lfd. Quartal', 'Vorquartal', 'Q1 26', 'Q2 26', 'Q3 26', 'Q4 26', 'YTD', 'Vorjahr'];
  const favs = ['1W', 'lfd. Monat', 'YTD', '1J', 'Max'];
  const opt = (l) => `<span class="${l === '1J' ? 'on ' : ''}${favs.includes(l) ? 'fav' : ''}">${l}</span>`;
  const dd = `<div class="sp-dd"><h5>Rollierend · bis heute</h5><div class="sp-opts">${roll.map(opt).join('')}</div><h5>Kalender</h5><div class="sp-opts">${cal.map(opt).join('')}</div><h5>Eigene · gespeichert</h5>
<div class="sp-own hl">★ Seit Umschichtung <em>01.03.2025 – heute</em></div><div class="sp-own">☆ Sommer 2026 <em>01.06. – 31.08.2026</em></div><div class="sp-own">☆ Seit dem ersten Kauf <em>12.05.2019 – heute</em></div><div class="sp-add">＋ Eigenen Zeitraum anlegen …</div><h5>Jahr</h5><div class="sp-opts"><span>2026</span><span>2025</span><span>2024</span><span>2023</span><span>…</span></div><p class="sp-cap" style="margin:8px 0 0">★ = in der Leiste als Schnellwahl; ein Klick auf den Stern nimmt einen Zeitraum hinein oder heraus. Ein Quartal, das noch nicht begonnen hat, erscheint gestrichelt und ist nicht wählbar. „lfd. Quartal“ und „Q4 26“ sind heute dasselbe Quartal; beide stehen da, weil das eine morgen weiterläuft und das andere stehen bleibt.</p></div>`;
  return page('Sprint 32 · Board 04 — Zeiträume', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 04 — Zeiträume: ein Menü mit Standards, eigene Zeiträume gespeichert ${SYN}</h1>
<p class="mock-note">Dein Wunsch: Wochen, MTD, aktueller Monat, seit einem Monat, Quartal 1 bis 4, aktuelles Quartal … „aber so, dass es in einem Menü nicht zu überladen aussieht. Vielleicht eher ein Dropdown, wo es die Standards gibt und man eigene Daten hinzufügen kann, die einen interessieren. So dass es auch auf Dauer gespeichert wird“ und in anderen Charts oder fürs ganze Dashboard nutzbar ist. Heute: acht feste Tasten (1T bis Max) über dem Dashboard, Vermögen hat zusätzlich „Benutzerdefinierter Zeitraum“.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Empfehlung A:</b> in der Leiste nur noch <b>deine Schnellwahl</b> (bis zu sechs, von dir mit ★ gewählt, Vorgabe: 1W · lfd. Monat · YTD · 1J · Max) und ein Knopf mit dem aktuellen Zeitraum, der das Menü öffnet. Im Menü vier Gruppen: rollierend, Kalender, Jahr, <b>deine eigenen</b>. Eigene Zeiträume und die Schnellwahl werden <b>auf dem Server gespeichert</b>, gelten auf jedem Gerät, für das ganze Dashboard und für jedes festgepinnte Widget, und sind über API und MCP lesbar und anlegbar. <b>Umschalten:</b> „alle Tasten zeigen“ (B).</p></div></section>
<section class="mock-board"><h2>① Die Leiste ${tag('rec', 'A')}</h2>
<div class="mock-frame"><div class="pd-bar"><span class="mock-select">Alles ▾</span><span class="pd-chips">${favs.map((f) => `<span${f === '1J' ? ' class="on"' : ''}>${f}</span>`).join('')}</span><span class="wd-btn">Zeitraum ▾</span><span class="wd-sp" style="flex:1"></span><span class="wd-btn">Bearbeiten</span></div>
<div class="pd-bar" style="margin-top:10px"><span class="mock-select">Alles ▾</span><span class="pd-chips">${favs.map((f) => `<span>${f}</span>`).join('')}</span><span class="sp-trig">Seit Umschichtung ▾</span><span class="wd-sub">01.03.2025 – 25.11.2026</span></div>
<p class="sp-cap">Oben: ein Standard aus der Schnellwahl ist aktiv. Unten: ein eigener Zeitraum ist aktiv; der Knopf trägt seinen Namen und daneben stehen die Daten, damit nie unklar ist, was „Seit Umschichtung“ heißt.</p></div></section>
<section class="mock-board"><h2>② Das Menü und ein eigener Zeitraum</h2>
<div class="sp-row">${dd}<div class="sp-dialog"><h4>Eigener Zeitraum</h4><div class="sp-field"><label>Name</label><span class="sp-input">Seit Umschichtung</span></div><div class="sp-field"><label>Von</label><span class="sp-input">01.03.2025</span></div><div class="sp-field"><label>Bis</label><span><span class="pd-chips"><span class="on">heute</span><span>Datum</span></span></span></div><div class="sp-field"><label></label><span>☑ in der Schnellwahl zeigen</span></div><p class="sp-cap" style="margin:0 0 10px">„bis heute“ wächst jeden Tag mit; ein festes Ende bleibt stehen. Gespeichert für alle Geräte, im Audit-Journal vermerkt. Ändern und löschen im selben Menü (⋯ neben dem Namen).</p><div style="display:flex;gap:8px;justify-content:flex-end"><span class="wd-btn">Abbrechen</span><span class="wd-btn wd-btn--acc">Speichern und anwenden</span></div></div></div></section>
<section class="mock-board"><h2>③ Dasselbe Menü am Widget</h2>
<div class="sp-row"><div><div class="wd-grid" style="grid-template-columns:1fr;grid-auto-rows:112px">${W.perfM('m', '📌').replace('wd wd--m"', 'wd wd--m" style="grid-column:span 1"').replace('<span class="wd-chips">', '<span class="pd-pin">📌 eigener: lfd. Quartal</span><span class="wd-chips" style="display:none">')}</div></div>
<div><p class="mock-note">Im ⋯-Menü eines Widgets öffnet „Zeitraum festpinnen“ dasselbe Menü; ein Pin auf einen eigenen Zeitraum speichert dessen Verweis, nicht die Daten, so dass eine Änderung am Zeitraum überall gilt. Wird ein eigener Zeitraum gelöscht, liest ein Widget, das ihn gepinnt hatte, wieder den Zeitraum der Leiste und sagt es im Fuß („eigener Zeitraum gelöscht · folgt 1J“), wie heute bei einer gelöschten Ansicht.</p>
<table class="pd-var"><tr><th>Widget</th><th>kann</th><th>bei „lfd. Quartal“</th></tr><tr><td>Wertentwicklung, Gesamtwert, Beitrag je Position, Heatmap</td><td>jeden Zeitraum (Von–Bis)</td><td>genau das Quartal</td></tr><tr><td>Tops und Flops</td><td>Tag, Woche, Monat, Quartal, YTD, 1J (ADR-0061)</td><td>„lfd. Quartal → Quartal“</td></tr><tr><td>Handelsaktivität</td><td>jeden Zeitraum</td><td>genau das Quartal</td></tr><tr><td>Bitcoin-Zyklus, Crashes, Datenqualität</td><td>keinen</td><td>„ohne Zeitraum“</td></tr></table></div></div></section>
<section class="mock-board"><h2>④ Zum Vergleich: alle Tasten in der Leiste ${tag('no', 'B · nicht empfohlen')}</h2>
<div class="mock-frame"><div class="pd-bar"><span class="pd-chips">${roll.concat(cal).map((f) => `<span${f === '1J' ? ' class="on"' : ''}>${f}</span>`).join('')}</span></div><p class="sp-cap">19 Tasten, und die eigenen Zeiträume fehlen noch. Auf dem Handy wäre das ein langer Streifen zum Wischen. Genau das Überladene, das du vermeiden wolltest.</p></div></section>
`);
}

// ---------- board 05: two new widgets ----------
function heatColor(v) {
  const a = Math.min(1, Math.abs(v) / 6);
  const c = v >= 0 ? 'var(--color-positive)' : 'var(--color-danger)';
  return `background:color-mix(in oklab, ${c} ${Math.round(10 + a * 55)}%, transparent)`;
}
function board05() {
  const r = rng(77);
  const years = [2026, 2025, 2024, 2023];
  const mon = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
  const grid = years.map((y) => mon.map((_, m) => (y === 2026 && m > 10 ? null : +((r() - 0.42) * 9).toFixed(1))));
  const yearTot = grid.map((row) => +(row.filter((v) => v !== null).reduce((p, v) => p * (1 + v / 100), 1) * 100 - 100).toFixed(1));
  const heat = `<table class="sp-heat"><tr><th></th>${mon.map((m) => `<th>${m}</th>`).join('')}<th>Jahr</th></tr>${years.map((y, i) => `<tr><th>${y}</th>${grid[i].map((v) => (v === null ? '<td class="na">·</td>' : `<td style="${heatColor(v)}">${nf(1).format(v)}</td>`)).join('')}<td class="y" style="${heatColor(yearTot[i] / 3)}">${nf(1).format(yearTot[i])}</td></tr>`).join('')}</table>`;
  const buys = [3, 1, 4, 2, 0, 5, 1, 2, 3, 1, 2, 4].map((v) => v * 1300 + Math.round(r() * 900));
  const sells = [0, 2, 0, 1, 3, 0, 0, 1, 0, 2, 1, 0].map((v) => v * 1600 + (v ? Math.round(r() * 700) : 0));
  const max = Math.max(...buys, ...sells);
  const w = 560, h = 150, mid = 78, bw = w / 12;
  const act = `<svg viewBox="0 0 ${w} ${h}" height="${h}"><line class="wd-gridl" x1="0" x2="${w}" y1="${mid}" y2="${mid}"/>${buys.map((v, i) => `<rect x="${(i * bw + 5).toFixed(1)}" y="${(mid - (v / max) * 64).toFixed(1)}" width="${(bw - 10).toFixed(1)}" height="${((v / max) * 64).toFixed(1)}" rx="2" style="fill:var(--color-accent);opacity:.75"/>`).join('')}${sells.map((v, i) => `<rect x="${(i * bw + 5).toFixed(1)}" y="${mid}" width="${(bw - 10).toFixed(1)}" height="${((v / max) * 64).toFixed(1)}" rx="2" style="fill:var(--color-warning);opacity:.75"/>`).join('')}${['Dez', 'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov'].map((m, i) => `<text class="wd-axis" x="${(i * bw + 8).toFixed(0)}" y="${h - 1}">${m}</text>`).join('')}</svg>`;
  return page('Sprint 32 · Board 05 — Neue Widgets', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 05 — zwei neue Widgets: Rendite-Heatmap und Handelsaktivität ${SYN}</h1>
<p class="mock-note">Dein Wunsch: „In Portfolio Performance gibt es sowas wie Handelsaktivität, Heatmap für Rendite pro Monat oder Jahr.“ Beide zeigen eine Zahl, die die App heute noch nicht ausgibt; nach ADR-0062 §10 braucht jede neue Zahl ihre eigene Entscheidung. Darum kommen sie im nächsten Widget-Sprint, mit ihrer Entscheidung (ADR-0063) auf dessen Planungs-PR; dieses Board zeigt vorab, wie sie aussehen sollen. Beide sind Stufe (a) der Leiter: abgeleitete Kennzahlen, mit ihrer Rechengrundlage im ⓘ und in API und MCP, ohne Urteil.</p></header>
<section class="mock-board"><h2>① Rendite-Heatmap ${tag('rec', 'neu')} <small>M und L; S zeigt nur die Jahresspalte</small></h2>
<div class="sp-row"><section class="wd" style="min-height:250px">${head('Rendite je Monat', { chips: ['TTWROR', 'Wert'], on: 'TTWROR' })}<div class="wd-body">${heat}</div>${foot('Ansicht Alles · in %', 'Ganze Ansicht')}</section>
<div><p class="mock-note"><b>Was jede Zelle ist:</b> die zeitgewichtete Rendite (TTWROR) des Kalendermonats, aus derselben täglichen Kette, die „Wertentwicklung“ rechnet (ADR-0004, Performance-Lesen), Einzahlungen herausgerechnet. Die Jahresspalte ist das Produkt der Monate, nicht ihre Summe. <b>Lücken:</b> ein Monat ohne Bestand ist ein Punkt, kein 0; ein angebrochener Monat (der laufende, der erste) trägt ein Zeichen und sein Von–Bis im Tooltip. <b>Umschalter „Wert“:</b> derselbe Raster in Euro (Gewinn des Monats nach Zu- und Abflüssen).</p><p class="mock-note"><b>Zeitraum:</b> die Heatmap zeigt immer ganze Jahre; der Zeitraum der Leiste legt fest, wie viele (1J: das laufende und das letzte, Max: alle). <b>Rechengrundlage in der Antwort:</b> Reihe, Monatsgrenzen, Methode der Verkettung, Behandlung der Lücken (AGENTS.md, blockiert sonst das Review). Neue Lesung: <code>GET /api/v1/views/:id/performance/calendar</code> und das MCP-Werkzeug dazu.</p></div></div></section>
<section class="mock-board"><h2>② Handelsaktivität ${tag('rec', 'neu')} <small>W, M und L</small></h2>
<div class="sp-row"><section class="wd" style="min-height:250px">${head('Handelsaktivität', { chips: ['Volumen', 'Anzahl'], on: 'Volumen' })}<div class="wd-sub" style="margin:-2px 0 4px"><span style="color:var(--color-accent);font-weight:700">■ Käufe 38.400 €</span> · <span style="color:var(--color-warning);font-weight:700">■ Verkäufe 17.900 €</span> · 41 Buchungen in 1J</div><div class="wd-body">${act}</div>${foot('Ansicht Alles · nach Monat', 'Alle Trades')}</section>
<div><p class="mock-note"><b>Was ein Balken ist:</b> die Summe der Käufe (nach oben) und Verkäufe (nach unten) eines Monats in Euro zum Buchungskurs, Gebühren getrennt ausgewiesen; „Anzahl“ zählt die Buchungen. Ein- und Auslieferungen zählen nicht als Handel und stehen getrennt im ⓘ. <b>Zeitraum:</b> jeder, mit Monaten bei mehr als drei Monaten, Wochen darunter. <b>L</b> fügt die Liste der letzten Trades an. Es ist eine Summe von Buchungen, keine Bewertung: Stufe (a), ohne Urteil („viel gehandelt“ steht nirgends). Neue Lesung: <code>GET /api/v1/views/:id/trading_activity</code>.</p><p class="mock-note"><b>Ohne neue Zahl, für „Rücksetzer“ und „Krypto Lover“ (Board 03):</b> „Abstand zum Hoch“, die Liste der Wertpapiere einer Ansicht mit ihrem Abstand zum 52-Wochen-Hoch und ihrem größten Rückgang, aus dem schon vorhandenen <code>securities.metrics</code> (ADR-0047). Sortiert nach Abstand, ohne „günstig“ oder „Kaufchance“.</p></div></div></section>
`);
}

// ---------- board 02: Wealth's tabs become starter dashboards ----------
function sidebar(on) {
  const dash = [['Überblick'], ['Bestände', 'neu'], ['Allokation & Ziele', 'neu'], ['Snapshots', 'neu'], ['Risiko', 'neu'], ['Mein Krypto', '']];
  return `<aside class="wd-side"><div class="wd-brand">Portfolixir</div><h5>Dashboards</h5>${dash.map(([d, n]) => `<a class="${d === on ? 'on' : ''}"><span class="wd-ico">▦</span>${d}${n ? ' <span class="pd-follow" style="margin-left:auto;font-size:9.5px">' + n + '</span>' : ''}</a>`).join('')}<a class="add"><span class="wd-ico">+</span>Neues Dashboard</a><h5>Entdecken</h5><a><span class="wd-ico">◎</span>Wertpapiere</a><a><span class="wd-ico">€</span>Cashflow</a><a><span class="wd-ico">§</span>Steuer</a><a><span class="wd-ico">◇</span>Prognosen</a><a><span class="wd-ico">☰</span>Nachrichten</a><a><span class="wd-ico">⊞</span>Alle Widgets</a><h5>Pflege</h5><a class="quiet"><span class="wd-ico">⚙</span>Transaktionen …</a></aside>`;
}
const zeile = (title, inner, opts = {}) => `<section class="sp-full">${head(title, opts)}${inner}${opts.foot || ''}</section>`;
function board02() {
  const kpis = zeile('Kennzahlen', `<div class="sp-kpis"><div><div class="l">Gesamt inkl. Cash</div><div class="v">${eur(last)}</div></div><div><div class="l">TTWROR · 1J</div><div class="v pos">+11,6 %</div></div><div><div class="l">IZF / MWR</div><div class="v pos">+10,9 % p. a.</div></div><div><div class="l">Wertpapiere</div><div class="v">${eur(last * 0.907)}</div></div><div><div class="l">Cashquote</div><div class="v">9,3 %</div></div><div><div class="l">Anfangswert · Flüsse</div><div class="v" style="font-size:14px">186.200 € · +6.000 €</div></div></div>`);
  const perf = zeile('Performance', `<div class="pd-bar" style="margin:0 0 6px"><span class="pd-chips"><span class="on">% (TTWROR)</span><span>Wert (EUR)</span></span><span class="wd-sub">Ebene</span><span class="pd-chips"><span>Gesamt</span><span class="on">Kategorien</span><span>Wertpapiere</span></span><span class="pd-follow">folgt · 1J</span></div>${stacked(cats, 860, 190, months)}<div class="wd-leg">${catNames.map((c, k) => `<span><i class="b${k + 1}"></i>${c}</span>`).join('')}</div>`, { foot: foot('Benchmark… · Daten als Tabelle', 'Ganze Ansicht') });
  const contrib = zeile('Beitrag je Position', `<table class="wd-tab"><tr><th>Wertpapier</th><th class="num">Anfangswert</th><th class="num">Zu-/Abflüsse</th><th class="num">Erträge</th><th class="num">Endwert</th><th class="num">Beitrag</th></tr>${[['Halbleiter AG', 9800, 0, 0, 12210, 2410], ['Welt-ETF', 41200, 3000, 410, 46900, 2290], ['Netz Versorger', 8800, 0, 260, 9420, 880], ['Autobauer Süd', 7100, 0, 120, 6640, -340]].map(([n, a, f, e, z, b]) => `<tr><td>${n}</td><td class="num">${nf(2).format(a)}</td><td class="num">${nf(2).format(f)}</td><td class="num">${nf(2).format(e)}</td><td class="num">${nf(2).format(z)}</td><td class="num ${b > 0 ? 'pos' : 'neg'}">${b > 0 ? '+' : '−'}${nf(2).format(Math.abs(b))}</td></tr>`).join('')}</table>`, { foot: foot('31 kleinere Positionen ausgeblendet · Alle anzeigen', '') });
  const positions = zeile('Positionen', `<table class="wd-tab"><tr><th>Wertpapier</th><th class="num">Stück</th><th class="num">Kurs</th><th class="num">Wert</th><th class="num">Anteil</th></tr>${[['Welt-ETF', 412, 113.84], ['Halbleiter AG', 60, 203.5], ['Netz Versorger', 300, 31.4]].map(([n, s, k]) => `<tr><td>${n}</td><td class="num">${s}</td><td class="num">${nf(2).format(k)}</td><td class="num">${nf(2).format(s * k)}</td><td class="num">${nf(1).format((s * k * 100) / last)} %</td></tr>`).join('')}</table>`, { foot: foot('Spalten wählen', '') });
  const dash = `<div class="wd-shell" style="grid-template-columns:200px 1fr">${sidebar('Bestände')}<div class="wd-main"><div class="wd-top"><h3>Bestände</h3><span class="wd-sp"></span><span class="mock-select">Alles ▾</span><span class="pd-chips"><span>1W</span><span>lfd. Monat</span><span>YTD</span><span class="on">1J</span><span>Max</span></span><span class="wd-btn">Zeitraum ▾</span><span class="wd-btn">Bearbeiten</span></div><div class="sp-band">${kpis}${perf}${contrib}${positions}<div class="wd-sub" style="text-align:center">… Verrechnungskonten</div></div></div></div>`;
  return page('Sprint 32 · Board 02 — Start-Dashboards', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 02 — Vermögen wird zu Start-Dashboards, die genauso aussehen wie die Tabs ${SYN}</h1>
<p class="mock-note">Dein Wunsch: „die alte Ansicht von Vermögen einfach überführen in die Widget-Dashboards, … genau so wie vorher, nur dass jeder Teil ein Widget ist und anpassbar, entfernbar usw. … statt bei Vermögen die Tabs oben wäre jedes ein eigenes Dashboard, das zum Start mitkommt, das man anpassen und umbenennen kann.“ Die Bestandsaufnahme: 7 Tabs mit rund 30 Abschnitten; nur wenige haben heute ein Widget.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Empfehlung:</b> jeder Abschnitt eines Tabs wird <b>ein Widget, das genau den heutigen Abschnitt zeichnet</b>, in der neuen Größe <b>„Zeile“</b>: volle Breite, so hoch wie sein Inhalt. Untereinander gestapelt sieht das Dashboard aus wie der Tab. Weil jeder Abschnitt jetzt ein Widget ist, kannst du ihn entfernen, verschieben, umbenannte Dashboards bauen und ihn in andere Dashboards holen. Der eigene Zeitraum-Schalter eines Abschnitts weicht der Leiste oben (ADR-0062 §5).</p>
<p><b>Start-Dashboards A (empfohlen):</b> beim Update einmal gespeichert, danach ganz deine: umbenennen, ändern, löschen; über „Neues Dashboard“ jederzeit neu anlegbar. <b>B:</b> nur angezeigt, bis du sie zum ersten Mal änderst (dann gespeichert); einfacher für eine frische Installation, aber Löschen braucht ein eigenes „ausgeblendet“-Gedächtnis. Umschalten: „Start-Dashboards erst beim Ändern speichern“.</p>
<p><b>Reihenfolge:</b> Sprint 32 baut Bestände, Allokation & Ziele, Snapshots und Risiko; Cashflow, Steuer und Prognosen folgen im nächsten Widget-Sprint (dort sind die Abschnitte am größten) und bleiben bis dahin Seiten unter „Entdecken“. Umschalten: „alle sieben in Sprint 32“ (dann zwei gestapelte PRs mehr).</p></div></section>
<section class="mock-board"><h2>① Das Start-Dashboard „Bestände“ ${tag('rec', 'empfohlen')}</h2>${dash}
<p class="sp-cap">Links die Start-Dashboards an der Stelle der Tabs („neu“ nur bis zum ersten Öffnen). „Mein Krypto“ steht für ein eigenes. Jeder Kasten rechts ist ein Widget in der Größe „Zeile“: Kennzahlen, Datenhinweise (nur wenn es welche gibt), Performance, Beitrag je Position, Positionen, Verrechnungskonten, in der Reihenfolge und Gestalt des heutigen Tabs.</p></section>
<section class="mock-board"><h2>② Was zu welchem Start-Dashboard wird</h2>
<table class="pd-var"><tr><th>Start-Dashboard</th><th>Widgets (Größe „Zeile“, in dieser Reihenfolge)</th><th>vorhandene Widgets, die es schon fast gibt</th><th>Sprint</th></tr>
<tr class="rec"><td><b>Bestände</b></td><td>Kennzahlen · Datenhinweise · Performance (Chart mit Ebene, Benchmark, Tabelle) · Beitrag je Position · Positionen · Verrechnungskonten</td><td>Gesamtwert (S), Wertentwicklung (L)</td><td>32</td></tr>
<tr class="rec"><td><b>Allokation & Ziele</b></td><td>Kennzahlen-Zeile · Allokation (Baum oder Positionen, Sunburst, Drift-Tabelle, Hinweise zum Soll)</td><td>Allokation und Drift (M, T), Abseits des Ziels</td><td>32</td></tr>
<tr class="rec"><td><b>Snapshots</b></td><td>Vergleich gegen einen Snapshot · Snapshot-Liste</td><td>Snapshots (S, W)</td><td>32</td></tr>
<tr class="rec"><td><b>Risiko</b></td><td>Eigene Regeln · Kennzahlen des Portfolios · Crashes · Größte Einzelpositionen · Klumpenrisiko · Anlageklassen-Obergrenzen</td><td>Crashes im Vergleich (M, L)</td><td>32</td></tr>
<tr><td>Cashflow</td><td>Erträge (Jahresübersicht, Zahlungen, Top-Beiträge, je Position) · Trades (Realisiert, Nach dem Verkauf, je Periode) · Ein- und Auszahlungen · Gebühren und Steuern</td><td>Verkaufsrückblick (M)</td><td>danach</td></tr>
<tr><td>Steuer</td><td>Steuerfreier Verkaufsspielraum · Erfasste Abrechnungen</td><td>–</td><td>danach</td></tr>
<tr><td>Prognosen</td><td>Kalibrierung · Alle Prognosen</td><td>–</td><td>danach</td></tr></table>
<p class="mock-note" style="margin-top:8px"><b>Was sich trotzdem ändert, damit es ehrlich bleibt:</b> (1) Formulare (neuer Snapshot, Abrechnung erfassen, Regel anlegen) wandern nicht in ein Widget; das Widget zeigt einen Link „Neuer Snapshot →“ auf die bisherige Seite, die als „Ganze Ansicht“ und unter „Pflege“ erreichbar bleibt (ADR-0022, Änderung vom 21.11., Punkt 3). (2) Der Zeitraum kommt aus der Leiste; Wertentwicklung und Beitrag folgen ihr, wie andere Widgets. (3) Auf dem Handy zeichnet ein „Zeile“-Widget die schmale Form, die der Abschnitt heute schon hat (Positionen als Zeilen, Tabellen als Karten). (4) Die Seite „Vermögen“ bleibt bis zum nächsten Widget-Sprint unter „Entdecken“, dann verlässt sie das Menü und bleibt nur als „Ganze Ansicht“.</p></section>
<section class="mock-board"><h2>③ Bearbeiten: ein „Zeile“-Widget</h2>
<div class="wd-edit" style="max-width:900px"><div class="sp-band">${editW(kpis.replace('sp-full', 'sp-full wd'), ['S', 'W', 'Zeile'], 'Zeile')}${editW(zeile('Beitrag je Position', '<div class="wd-sub">Tabelle wie oben …</div>').replace('sp-full', 'sp-full wd'), ['M', 'L', 'Zeile'], 'Zeile')}</div></div>
<p class="mock-note" style="margin-top:8px">Ein Abschnitt kann außer „Zeile“ auch Rastergrößen anbieten, wo er klein lesbar ist (Kennzahlen als S ist der heutige Gesamtwert, als W die drei Hauptzahlen, Board 01 ④). Im Raster zählt „Zeile“ als 12 Spalten × 1 Reihe; gezeichnet wird sie so hoch wie ihr Inhalt, und alles darunter beginnt danach. Größe ändern und Verschieben folgen Board 01 A.</p></section>
`);
}

// ---------- write ----------
const out = { '01-resize': board01(), '02-starter-dashboards': board02(), '03-templates': board03(), '04-periods': board04(), '05-new-widgets': board05(), '06-real-app': board06(), '07-widget-look': board07(), '08-alle-widgets': board08(), '09-groessen-nach-apple': board09(), '10-abstand': board10() };
for (const [name, html] of Object.entries(out)) {
  fs.writeFileSync(path.join(__dirname, name + '.html'), html);
  console.log('wrote ' + name + '.html');
}

// ---------- board 06: the real app, rearranged ----------
function board06() {
  const img = (f, cap) => `<figure class="mock-fig"><img src="${f}" style="width:100%;border:1px solid var(--color-border-strong);border-radius:10px" alt=""><p class="sp-cap">${cap}</p></figure>`;
  return page('Sprint 32 · Board 06 — die echte App als Dashboard', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 06 — die echte App, als Dashboard angeordnet ${SYN}</h1>
<p class="mock-note">Gezeigt auf deine Frage vom 25.11. („Zeig mir mal Beispiel, wie die jetzige Vermögensübersicht und Allokation als Dashboard aussehen würden“). Keine Zeichnung: die laufende App auf dem synthetischen Review-Seed (<code>priv/demo/finding_surfaces_seed.exs</code>), deren Seiten im Browser so umgestellt wurden, wie Board 02 es vorsieht. Zahlen, Diagramme und Bedienelemente sind echt, nur die Anordnung ist der Entwurf; nichts ist gespeichert. Die Skripte liegen in <code>real-app/</code>.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Deine Wahl vom 25.11.: Kennzahlen A</b> („Ja, A sieht super aus“): der Gesamtwert mit dem Balken Wertpapiere zu Cash, drei gleich gebaute Spalten (Ergebnis, TTWROR, IRR), darunter die Wertbrücke Anfang + Nettoflüsse + Ergebnis = heute, ein ⓘ für das ganze Widget. „Ergebnis“ statt „Gewinn“, weil die Tabelle „Beitrag je Position“ dieselbe Zahl so nennt.</p></div></section>
<section class="mock-board"><h2>① Kennzahlen: heute ${tag('before', 'vorher')}, A ${tag('rec', 'gewählt')}, B ${tag('alt', 'B')}</h2>
${img('06-kpi-heute.png', 'Heute: sieben Kacheln in zwei Reihen ungleicher Größe, ein ⓘ an jeder, Unterzeilen in drei Stilen.')}
${img('06-kpi-A.png', 'A: Gesamtwert und Aufteilung, drei Renditezahlen auf einer Linie, die Wertbrücke geht auf den Cent auf (76.617,17 + 4.341,20 + 7.348,65 = 88.307,02).')}
${img('06-kpi-A-dark.png', 'A im Dunkelmodus.')}
${img('06-kpi-B.png', 'B: fünf Spalten in einer Zeile; Anfangswert, Nettoflüsse und Multiplikator hinter „weitere Kennzahlen“.')}</section>
<section class="mock-board"><h2>② Das Start-Dashboard „Bestände“ <small>mit den heutigen Kennzahlen; A ersetzt sie beim Bau</small></h2>
<div class="sp-row">${img('06-real-bestaende.png', 'Wie es mitkommt: jeder Abschnitt des Tabs ein Widget, Positionen und Verrechnungskonten zeigen die ersten Zeilen und „Alle anzeigen“.')}${img('06-real-bestaende-angepasst.png', 'Nach einer Minute „Bearbeiten“: drei Hauptzahlen, die Datenhinweise als kleines M-Widget daneben, Positionen und Konten nebeneinander; rund ein Drittel kürzer.')}</div>
<div class="sp-row">${img('06-real-bestaende-bearbeiten.png', 'Bearbeiten: Griff, Größen (S, W, Zeile), × an jedem Widget; „Widget hinzufügen“, „Zurücksetzen“, „Fertig“.')}${img('06-real-allokation.png', 'Das Start-Dashboard „Allokation & Ziele“: Kennzahlen-Zeile und die Allokation als ein Widget.')}</div></section>
`);
}

// ---------- board 07: one look for every widget ----------
function board07() {
  const F = [
    ['1', 'Kopf', '„folgt · 1J“ steht auf einer eigenen Zeile unter dem Titel und kostet jedem Widget eine Zeile.', '#0, #1, #7, #8, #9, #10, #11'],
    ['2', 'Grundlage im Inhalt', 'Erklärsätze oben im Inhalt: Tops und Flops (drei Zeilen, in S ein Viertel der Fläche), Abseits des Ziels, Allokation, Verkaufsrückblick; der Bitcoin-Zyklus endet mit einem Absatz. Die Grundlage gehört hinter ⓘ (ADR-0062 §1, I1).', '#6, #10, #11, #14, #15, #18–#20'],
    ['3', 'Warnkästen', 'Ein großer ACHTUNG-Kasten oben drückt die eigentliche Zahl nach unten (Gesamtwert M, Verkaufsrückblick); Gesamtwert S schneidet seine Warnung ab („Nicht in der Sum…“); Datenqualität M ist ein roter Fließtext voller Links.', '#0, #1, #3, #20'],
    ['4', 'Karte in der Karte', 'Gesamtwert M zeichnet eine Kachel mit Farbstreifen und eine Vierer-Leiste in seiner Karte; zwei Zahlen sind abgeschnitten („25.11.202“, „LETZTE BUCHUNG“ läuft über).', '#1'],
    ['5', 'Zahlengrößen', 'Die Hauptzahl ist mal 26, mal 30, mal 24 px, mal grün, mal schwarz, mal ein Datum; Labels mal in Großbuchstaben, mal nicht.', '#0, #1, #5, #7, #12'],
    ['6', 'Größen ohne Sinn', 'Tops und Flops S ist höher als M (593 zu 412 px) und kürzt jeden Namen; Crashes L und Bitcoin-Zyklus L zeigen dasselbe wie M mit Leerraum; Allokation T ist M, nur schmaler.', '#10, #11, #15, #17, #19'],
    ['7', 'Fußzeile', 'Neun verschiedene Linktexte, mal mit, mal ohne Ansicht links, Gesamtwert S mit zwei Fußzeilen.', 'alle'],
    ['8', 'Fließtext statt Spalte', '„Rechnerisch zum Soll“ ist ein Absatz mit fünf Beträgen hinter der Drift-Tabelle, statt einer Spalte in ihr.', '#14, #15'],
    ['9', 'Schalter im Widget', 'Kursrendite/Beitrag und Im Depot/Katalog stehen mal unter dem Erklärtext, mal als volle Leiste.', '#10, #11, #16, #17'],
    ['10', 'Balken verschwunden', 'Auf der alten Übersicht standen Kursrendite und Beitrag nebeneinander, der Beitrag mit Balken. Im Widget ist es ein Umschalter, Kursrendite vorn und ohne Balken; die Balken erscheinen nur unter „Beitrag“, und unter 560 px gar nicht.', '#10, #11'],
  ];
  const rules = [
    ['Kopf, eine Zeile', 'Titel · ⓘ · Zeitraum als kleine Marke („1J“, „📌 Max“, „ohne Zeitraum“ entfällt) · rechts der Schalter des Widgets · ⋯'],
    ['Eine Hauptzahl-Form', 'Label klein über der Zahl; Zahl S 28 px, W und M als Held 34 px, Nebenzahlen 24 px; darunter eine kurze graue Zeile. Farbe nur für Plus und Minus. Keine Karte in der Karte, kein Farbstreifen im Widget (der Rest der Farbfrage bleibt I48).'],
    ['Listen wie der Verkaufsrückblick', 'Name links (eine Zeile, voller Name im Tooltip), Zahl rechts, eine zweite graue Zeile wo nötig. Zahlen werden nie gekürzt; was nicht passt, fällt in der kleineren Größe weg.'],
    ['Balken bei vergleichbaren Zahlen', 'Eine Liste von Zahlen derselben Art (Tops und Flops, Beitrag, Drift) trägt unter jeder Zeile den Balken der Beitragstabelle: Mitte = 0, Plus nach rechts in Grün, Minus nach links in Rot, die größte Zahl der Liste füllt 45 %. In beiden Ansichten (Kursrendite und Beitrag) und auch auf dem Handy, wo die App ihn heute unter 560 px ausblendet. Dein Hinweis vom 25.11.: „das war hilfreich“.'],
    ['Grundlage hinter ⓘ', 'Im Inhalt höchstens eine kurze Zeile (Ansicht · Zeitraum); Methode, Ausschlüsse, „keine Prognose“ stehen im ⓘ.'],
    ['Warnung als Zeile', 'Im Widget nie ein Kasten: eine Zeile „⚠ 3 nicht in der Summe“ im Fuß, mit Link; der Kasten gehört in Datenhinweise und in die ganze Ansicht.'],
    ['Fuß, eine Zeile', 'links die Ansicht (wo es eine gibt), rechts ein Link, benannt nach seinem Ziel („Bestände →“, „Alle Trades →“).'],
    ['Größenregel', 'jede Größe zeigt mehr vom Gleichen (Änderung vom 25.11., 3). Eine Größe, die nichts hinzufügt, entfällt.'],
  ];
  const k = (l, v, cls = '', s = '') => `<div><div class="lab">${l}</div><div class="${cls}">${v}</div>${s ? `<div class="sub">${s}</div>` : ''}</div>`;
  const hd = (t, extra = '') => `<div class="wd-h" style="font-size:13px"><span class="wd-t">${t}</span><span class="wd-i">i</span><span class="pd-follow">1J</span><span class="wd-sp"></span>${extra}<span class="wd-more">⋯</span></div>`;
  const ft = (l, a) => `<div class="wd-foot" style="border-top:1px solid var(--color-border);padding-top:6px"><span>${l}</span><a>${a} →</a></div>`;
  const row = (n, s, v, cls) => `<li><span class="wd-sp"><b style="font-weight:600">${n}</b>${s ? `<br><span class="wd-muted">${s}</span>` : ''}</span><span class="${cls}" style="font-weight:650">${v}</span></li>`;
  const bar = (v, max) => `<span class="g7bar"><i class="${v >= 0 ? 'p' : 'n'}" style="width:${(Math.abs(v) / max * 45).toFixed(1)}%"></i></span>`;
  const rowb = (n, v, num, max) => `<li style="display:block"><span style="display:flex;gap:8px"><span class="wd-sp"><b style="font-weight:600">${n}</b></span><span class="${v >= 0 ? 'pos' : 'neg'}" style="font-weight:650">${num}</span></span>${bar(v, max)}</li>`;
  const after = `
<div class="g7">
<section class="wd" style="grid-column:span 3">${hd('Gesamtwert')}<div class="g7k"><div class="big2">88.307,02 <small>EUR</small></div><div class="sub"><span class="pos">+8,0 %</span> TTWROR · <span class="pos">+7.348,65</span> EUR</div></div><div class="wd-body" style="justify-content:flex-end">${spark(total.slice(-120), 200, 26)}</div>${ft('⚠ 3 nicht in der Summe', 'Bestände')}</section>
<section class="wd" style="grid-column:span 3">${hd('Tops und Flops')}<ul class="wd-list g7l">${rowb('Allianz SE', 31.4, '+31,4 %', 31.4)}${rowb('Apple Inc.', 25.3, '+25,3 %', 31.4)}${rowb('iShares Core MSCI World', -0.6, '−0,6 %', 31.4)}${rowb('Vanguard FTSE All-World', 0.3, '+0,3 %', 31.4)}</ul>${ft('Ansicht Alles', 'Bestände')}</section>
<section class="wd" style="grid-column:span 6">${hd('Datenqualität', '<span class="pd-na" style="border-style:solid">3 Probleme · 1 Achtung</span>').replace('<span class="pd-follow">1J</span>', '')}<ul class="wd-list g7l">${row('<span class="wd-dot" style="background:var(--color-danger);margin-right:6px"></span>3 Anleihen auf zwei Preisskalen', 'zählen hundertfach zu hoch oder zu niedrig', '3', '')}${row('<span class="wd-dot" style="background:var(--color-danger);margin-right:6px"></span>1 Kursreihe passt nicht zu ihren Buchungen', 'Tamarisk Systems Inc.', '1', '')}${row('<span class="wd-dot" style="background:var(--color-warning);margin-right:6px"></span>19 Kurse älter als 7 Tage', 'gehaltene Wertpapiere', '19', '')}${row('<span class="wd-dot" style="background:var(--color-warning);margin-right:6px"></span>1 ohne Anlageklasse', 'Ostsee Logistik 4,10 % 2028/2033', '1', '')}</ul>${ft('über alle Depots', 'Wertpapiere prüfen')}</section>
<section class="wd" style="grid-column:span 6">${hd('Tops und Flops', '<span class="wd-chips"><span class="on">Kursrendite</span><span>Beitrag</span></span>')}<div class="wd-two"><div><h4>Höchste</h4><ul class="wd-list g7l">${rowb('Allianz SE vinkulierte Namens-Aktien', 31.4, '+31,4 %', 31.4)}${rowb('Apple Inc.', 25.3, '+25,3 %', 31.4)}${rowb('NVIDIA Corporation', 19.9, '+19,9 %', 31.4)}${rowb('Microsoft Corporation', 17.1, '+17,1 %', 31.4)}</ul></div><div><h4>Niedrigste</h4><ul class="wd-list g7l">${rowb('iShares Core MSCI World', -0.6, '−0,6 %', 31.4)}${rowb('Vanguard FTSE All-World', 0.3, '+0,3 %', 31.4)}${rowb('Bitcoin', 12.3, '+12,3 %', 31.4)}</ul></div></div>${ft('Ansicht Alles · 28 ohne Kursrendite', 'Bestände')}</section>
<section class="wd" style="grid-column:span 6">${hd('Allokation und Drift').replace('<span class="pd-follow">1J</span>', '')}<table class="wd-tab"><tr><th>Kategorie</th><th class="num">Ist</th><th class="num">Soll</th><th class="num">Drift</th><th class="num">≈ zum Soll</th></tr>${[['Stability', '9,3', '15,0', '−5,7', '+4.243,67'], ['Growth', '35,1', '65,0', '−29,9', '+22.452,23'], ['Crypto', '3,4', '5,0', '−1,6', ''], ['Cash', '21,6', '20,0', '+1,6', '']].map(([n, i, s, d, z]) => `<tr><td>${n}</td><td class="num">${i} %</td><td class="num">${s} %</td><td class="num ${Math.abs(parseFloat(d.replace('−', '-').replace(',', '.'))) >= 5 ? 'neg' : 'wd-muted'}" style="min-width:110px">${d} pp${bar(parseFloat(d.replace('−', '-').replace(',', '.')), 29.9)}</td><td class="num">${z}</td></tr>`).join('')}</table><div class="sub" style="margin-top:6px">≈ zum Soll: nur Anzeige, kein Auftrag (ADR-0023)</div>${ft('Plan „Plan“ auf Strategies · Ansicht Alles', 'Ziele')}</section>
<section class="wd" style="grid-column:span 6">${hd('Verkaufsrückblick').replace('<span class="pd-follow">1J</span>', '')}<ul class="wd-list g7l">${row('Brightwater Utilities plc', 'verkauft 16.10.2026 · 460 Tage', '+30,00 EUR', 'pos')}${row('Tamarisk Mining Ltd', 'verkauft 17.08.2026 · 600 Tage', '−400,00 EUR', 'neg')}${row('Kestrel Bay Resources Inc.', 'verkauft 28.07.2026 · 80 Tage', '+151,00 EUR', 'pos')}${row('Wrenfield Gardens AG', 'verkauft 28.07.2026 · 780 Tage', '+420,00 EUR', 'pos')}</ul>${ft('⚠ 2 Verkäufe ohne vollständige Daten · alle Depots', 'Alle Trades')}</section>
</div>`;
  return page('Sprint 32 · Board 07 — ein Look für jedes Widget', `
<style>
.g7{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:14px;align-items:start}
.g7 .wd{padding:12px 16px}
.g7 .lab{font-size:10.5px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;color:var(--color-text-muted)}
.g7 .big2{font-size:28px;font-weight:760;letter-spacing:-.015em;font-variant-numeric:tabular-nums;line-height:1.1}
.g7 .big2 small{font-size:13px;font-weight:600;color:var(--color-text-muted)}
.g7 .sub{font-size:12px;color:var(--color-text-muted);margin-top:3px}
.g7l li{padding:6px 0;font-size:12.5px;align-items:baseline}
.g7 .wd-foot{font-size:11.5px}
.g7bar{display:block;position:relative;height:5px;border-radius:999px;background:var(--color-bg-muted);margin:5px 0 1px;overflow:hidden}
.g7bar::before{content:"";position:absolute;top:0;bottom:0;left:50%;width:1px;background:var(--color-border-strong)}
.g7bar i{position:absolute;top:0;bottom:0;border-radius:999px}
.g7bar i.p{left:50%;background:var(--color-positive)} .g7bar i.n{right:50%;background:var(--color-danger)}
table.f7{width:100%;border-collapse:collapse;font-size:12.5px}
table.f7 th,table.f7 td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--color-border);vertical-align:top}
table.f7 th{font-size:10px;letter-spacing:.05em;text-transform:uppercase;color:var(--color-text-muted)}
table.f7 td:first-child{font-weight:800;color:var(--color-accent);width:24px}
</style>
<header class="mock-board mock-head"><h1>Sprint 32 · Board 07 — ein Look für jedes Widget ${SYN}</h1>
<p class="mock-note">Dein Vorschlag vom 25.11.: „Vielleicht sollten wir einmal den Look von allen Widgets prüfen?“ Geprüft: alle elf Widget-Arten in allen ihren Rastergrößen (21), fotografiert in der laufenden App auf dem synthetischen Review-Seed, auf einem Wegwerf-Dashboard, das jede Art in jeder Größe hält (<code>real-app/all_sizes.exs</code>, <code>real-app/widgets.js</code>). Die Nummern unten (#0 bis #20) stehen auf den beiden Kontaktbögen; Befund 10 kam nach deiner Frage nach den Balken dazu.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Empfehlung:</b> eine Widget-Anatomie für alle, abgeleitet aus deiner Wahl A für die Kennzahlen (Board 06): ein Kopf auf einer Zeile, eine Form für Hauptzahlen, Listen wie der Verkaufsrückblick, die Grundlage hinter ⓘ, Warnungen als eine Zeile, ein Fuß auf einer Zeile, die Größenregel. Sprint 32 setzt sie als eigene Lane L auf allen elf Arten um, bevor Lane W die neuen Widgets von Vermögen baut, damit diese gleich so entstehen. <b>Umschalten:</b> „Look erst nach Vermögen“.</p></div></section>
<section class="mock-board"><h2>① Was die Prüfung findet</h2><div class="mock-frame"><table class="f7"><tr><th>#</th><th>Thema</th><th>Befund</th><th>Widgets</th></tr>${F.map(([n, t, b, w]) => `<tr><td>${n}</td><td><b>${t}</b></td><td>${b}</td><td class="wd-muted">${w}</td></tr>`).join('')}</table>
<p class="sp-cap">Nebenbei aufgefallen, kein Look-Thema: in Wertentwicklung und Gesamtwert fällt der Wertverlauf an einem einzelnen Tag tief ab (#0, #8, #9). Der Review-Seed enthält absichtlich Tage ohne Kurs und Wechselkurs; ob der Abfall genau das ist, prüft Lane W's Vergleichstest gegen die Route, bevor jemand ihn für einen Fehler hält.</p></div></section>
<section class="mock-board"><h2>② Die Anatomie ${tag('rec', 'empfohlen')}</h2><div class="mock-frame"><table class="f7">${rules.map(([t, r], i) => `<tr><td>${i + 1}</td><td style="width:200px"><b>${t}</b></td><td>${r}</td></tr>`).join('')}</table></div></section>
<section class="mock-board"><h2>③ Sechs Widgets nach der Anatomie ${tag('rec', 'nachher')} <small>dieselben synthetischen Zahlen wie auf den Kontaktbögen</small></h2>${after}
<p class="mock-note" style="margin-top:10px">Gesamtwert S: die Warnung als Zeile im Fuß. Tops und Flops S: eine Liste mit Balken, ohne Erklärtext, niedriger als M. Datenqualität M: die Liste von S mit Zählern und je einer erklärenden Zeile statt des roten Fließtexts. Tops und Flops M: der Schalter im Kopf, Balken in beiden Spalten und in beiden Ansichten. Allokation und Drift: „≈ zum Soll“ als Spalte, die Drift mit ihrem Balken. Verkaufsrückblick: der Warnkasten wird eine Fußzeile, die Liste bleibt, sie ist schon das Vorbild. Bitcoin-Zyklus L bekommt das Zyklus-Diagramm, das es als Komponente schon gibt; Crashes L und Allokation T entfallen nach der Größenregel (gespeicherte Widgets dieser Größen werden als M gelesen).</p></section>
<section class="mock-board"><h2>④ Heute ${tag('before', 'vorher')} <small>alle 21, Kontaktbögen</small></h2><img src="07-heute-1.png" style="width:100%;border:1px solid var(--color-border-strong);border-radius:10px" alt=""><img src="07-heute-2.png" style="width:100%;margin-top:12px;border:1px solid var(--color-border-strong);border-radius:10px" alt=""></section>
`);
}

// ---------- board 08: every widget in every size, light and dark ----------
function board08() {
  const sizes = JSON.parse(fs.readFileSync(path.join(__dirname, 'real-app', 'sizes.json'), 'utf8'));
  const names = { total_value: 'Gesamtwert', data_quality: 'Datenqualität', due: 'Fällig', off_target: 'Abseits des Ziels', performance: 'Wertentwicklung', movers: 'Tops und Flops', snapshots: 'Snapshots', allocation_drift: 'Allokation und Drift', crashes: 'Crashes im Vergleich', bitcoin_cycle: 'Bitcoin-Zyklus', sale_review: 'Verkaufsrückblick' };
  const grid = { S: '3 × 1', W: '6 × 1', M: '6 × 2', T: '4 × 3', L: '8 × 3' };
  const verdict = {
    total_value: ['S: brauchbar, die Warnung ist abgeschnitten.', 'M: nicht in Ordnung: Karte in der Karte, zwei Zahlen abgeschnitten (07 ① 3, 4).'],
    data_quality: ['S: in Ordnung, Zeilen gekürzt.', 'M: nicht in Ordnung: roter Fließtext statt Liste (07 ① 3).'],
    due: ['S: in Ordnung; der Kreis hinter dem Namen ist unerklärt.'],
    off_target: ['S: in Ordnung.', 'M: in Ordnung, der Erklärsatz oben gehört ins ⓘ (07 ① 2).'],
    performance: ['S, M, L: in Ordnung; M beschriftet die Achse nur an zwei Stellen.'],
    movers: ['S: nicht in Ordnung: höher als M, jeder Name gekürzt (07 ① 6).', 'M: brauchbar, ohne Balken (07 ① 10).'],
    snapshots: ['S und W: in Ordnung.'],
    allocation_drift: ['M: brauchbar, „Rechnerisch zum Soll“ als Absatz (07 ① 8).', 'T: entbehrlich, M nur schmaler (07 ① 6).'],
    crashes: ['M: in Ordnung.', 'L: nicht in Ordnung: dasselbe wie M mit Leerraum (07 ① 6).'],
    bitcoin_cycle: ['M: brauchbar, nur Text.', 'L: nicht in Ordnung: kein Diagramm, Leerraum (07 ① 6).'],
    sale_review: ['M: in Ordnung bis auf den Warnkasten oben (07 ① 3).'],
  };
  const kinds = [...new Set(sizes.map((s) => s.kind))];
  const block = (k) => {
    const its = sizes.filter((s) => s.kind === k);
    const row = (theme) => `<div class="g8row">${its.map((s) => `<figure class="g8"><img src="08-galerie/${k}-${s.size}-${theme}.png" width="${s.w}" alt=""><figcaption><b>${s.size}</b> · Raster ${grid[s.size]} · ${s.w} × ${s.h} px</figcaption></figure>`).join('')}</div>`;
    return `<section class="mock-board"><h2>${names[k]} <small>${k}</small></h2><p class="mock-note">${verdict[k].join(' ')}</p><div class="g8theme">Hell</div>${row('light')}<div class="g8theme">Dunkel</div>${row('dark')}</section>`;
  };
  return page('Sprint 32 · Board 08 — alle Widgets', `
<style>
.g8row{display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start;margin:0 0 10px}
.g8{margin:0}.g8 img{display:block;border-radius:12px;box-shadow:var(--shadow-sm)}
.g8 figcaption{margin-top:5px;font-size:11.5px;color:var(--color-text-muted)}
.g8theme{font-size:10px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;color:var(--color-text-muted);margin:6px 0 6px}
</style>
<header class="mock-board mock-head"><h1>Sprint 32 · Board 08 — jedes Widget in jeder Größe, hell und dunkel ${SYN}</h1>
<p class="mock-note">Dein Wunsch vom 25.11.: „jedes Widget einmal in seinen Größen screenshoten, in light und dark … dann zeig mir bitte alle nochmal ordentlich, damit wir sehen, ob die alle in Ordnung aussehen.“ Der Stand von heute, vor Lane L: die laufende App auf dem synthetischen Review-Seed, 1280 px breit, jedes Widget für sich fotografiert (<code>real-app/gallery.js</code>); die Einzelbilder liegen in <code>08-galerie/</code> als <code>&lt;art&gt;-&lt;größe&gt;-&lt;light|dark&gt;.png</code>. „Raster“ ist die gespeicherte Größe in Spalten × Reihen, „px“ die gezeichnete. <b>Was auffällt:</b> eine Reihe ist 112 px hoch, aber kein S-Widget ist es; die Höhe folgt dem Inhalt (bis 593 px), deshalb wirkt ein Dashboard unruhig (Board 09).</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Für die Doku:</b> diese Bilder zeigen den Stand vor dem Umbau und dienen hier nur zum Vergleich. Sprint 32 bekommt eine Geschichte, die dieselben Bilder nach Lane L neu erzeugt (jede Art, jede Größe, hell und dunkel, in 2×), als Skript im Repository, damit die Doku jede Funktion mit ihrem Widget zeigen kann und die Bilder nach jeder Änderung neu entstehen (D-13).</p></div></section>
${kinds.map(block).join('')}
`);
}

// ---------- board 09: Apple's sizes, and templates with widgets on them ----------
function board09() {
  const img = (f, cap) => `<figure class="mock-fig" style="margin:0"><img src="${f}" style="width:100%;border:1px solid var(--color-border-strong);border-radius:10px" alt=""><p class="sp-cap">${cap}</p></figure>`;
  return page('Sprint 32 · Board 09 — Größen nach Apple', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 09 — Widget-Größen nach Apples Familien, und die Vorlagen mit Widgets darauf ${SYN}</h1>
<p class="mock-note">Deine Fragen vom 25.11.: „Für Widgets hat Apple ja Empfehlungen für die Sizes. Verfolgen wir die bei allen?“ und „Sehen die Vorlagen auch gut aus, wenn die Widgets drauf sind, oder machen die Widget-Sizes die Ästhetik wieder kaputt?“ <b>Kurz: nein und ja.</b> Heute folgen wir Apple nur halb, und genau das macht die Ästhetik kaputt.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Empfehlung:</b> die Größen werden Apples Familien (WidgetKit: small, medium, large, extra large). Eine quadratische Einheit, alle Größen ein Vielfaches davon, <b>jede Größe mit fester Höhe</b>. Dazu bleiben „Zeile“ (die Abschnitte aus Vermögen, so hoch wie ihr Inhalt) und „Ganze Ansicht“. Jede Art zeichnet pro Größe ihr eigenes Layout, wie Apple es verlangt (Lane L). Auf dem Handy stehen zwei S nebeneinander, M und L über die volle Breite, wie auf dem iPhone-Homescreen; native Widgets später (I53) übernehmen die Größen 1 : 1. <b>Umschalten:</b> „Größen wie bisher“.</p></div></section>
<section class="mock-board"><h2>① Unsere Größen gegen Apples</h2><div class="mock-frame"><table class="pd-var">
<tr><th>Apple (WidgetKit)</th><th>Form</th><th>bei uns heute</th><th>Vorschlag</th></tr>
<tr><td>small</td><td>1 × 1 Einheit, quadratisch</td><td><b>S</b> 3 × 1 Raster, breit statt quadratisch, Höhe wächst mit dem Inhalt</td><td><b>S</b> 3 Spalten × 2 Reihen ≈ 240 × 236 px, fest</td></tr>
<tr><td>medium</td><td>2 × 1, so hoch wie small</td><td><b>W</b> 6 × 1</td><td><b>M</b> 6 × 2, fest</td></tr>
<tr><td>large</td><td>2 × 2</td><td><b>M</b> 6 × 2 (halb so hoch wie Apples large)</td><td><b>L</b> 6 × 4, fest</td></tr>
<tr><td>extra large (iPad)</td><td>4 × 2</td><td><b>L</b> 8 × 3, kein Vielfaches der Einheit</td><td><b>XL</b> 12 × 4, die volle Breite, fest</td></tr>
<tr><td>–</td><td>–</td><td><b>T</b> 4 × 3, kein Vielfaches der Einheit</td><td>entfällt (gelesen als L)</td></tr>
<tr><td>–</td><td>–</td><td>„Zeile“ (geplant, Board 02)</td><td>bleibt: volle Breite, so hoch wie der Inhalt, nur für Abschnitte</td></tr>
</table><p class="sp-cap"><b>Was heute folgt:</b> W ist zwei S breit und M zwei W hoch, das ist Apples Muster. <b>Was nicht folgt:</b> S ist nicht quadratisch, L und T haben Breiten (8, 4), die kein Vielfaches von S sind, und keine Größe hat eine feste Höhe. Neben einem L (8 Spalten) passt nur ein T oder eine Lücke; S neben L lässt Spalte 12 leer. Umbenennung für gespeicherte Layouts: S bleibt S, W wird M, M wird L, T wird L, L wird XL; die Reihen verdoppeln sich, die Lage ordnet E1 beim ersten Speichern neu (Board 01 A).</p></div></section>
<section class="mock-board"><h2>② Die Vorlage „Überblick“ <small>links heute, rechts dieselben Widgets auf Apples Kacheln (im Browser simuliert, nichts gespeichert)</small></h2>
<div class="sp-row">${img('09-ueberblick-heute.png', 'Heute: jede Reihe so hoch wie ihr höchstes Widget; Allokation (T) und Crashes enden in Leerraum, Datenqualität und Fällig sind kürzer als ihre Nachbarn.')}${img('09-ueberblick-apple.png', 'Apples Kacheln: gleiche Höhen je Reihe, ruhige Kanten, Wertentwicklung über die volle Breite. Aber der heutige Inhalt passt noch nicht: Crashes und Bitcoin-Zyklus sind halb leer, Tops und Flops wäre in S abgeschnitten.')}</div></section>
<section class="mock-board"><h2>③ „Krypto Lover“ und „Rücksetzer“ <small>mit den heutigen Widgets nachgestellt; „Abstand zum Hoch“ gibt es noch nicht</small></h2>
<div class="sp-row">${img('09-krypto-heute.png', 'Krypto Lover heute: L neben T geht auf, darunter zwei M und zwei S mit unterschiedlicher Höhe.')}${img('09-krypto-apple.png', 'Auf Apples Kacheln: geordnet; der Bitcoin-Zyklus als XL ohne Diagramm ist zu leer (Lane L gibt ihm das Diagramm).')}</div>
<div class="sp-row">${img('09-ruecksetzer-heute.png', 'Rücksetzer heute: neben Crashes L (8 Spalten) passen zwei S nur übereinander, Spalte 12 bleibt leer, Crashes endet in einer großen Lücke.')}${img('09-ruecksetzer-apple.png', 'Auf Apples Kacheln: keine leere Spalte; Tops und Flops in S zeigt, warum jede Größe ihr eigenes Layout braucht (abgeschnitten).')}</div>
<p class="mock-note" style="margin-top:8px"><b>Was das heißt:</b> die Vorlagen sehen erst gut aus, wenn beides kommt: Apples feste Kacheln (das Raster wird ruhig) und ein Layout je Art und Größe (der Inhalt füllt seine Kachel). Nur das eine allein reicht nicht, wie die rechten Bilder zeigen. Beides gehört in Lane L; die Vorlagen werden danach auf den neuen Größen gesetzt und vor dem Bau auf diesem Board gegengeprüft.</p></section>
`);
}

// ---------- board 10: the space between widgets ----------
function board10() {
  const img = (f, cap) => `<figure class="mock-fig" style="margin:0"><img src="${f}" style="width:100%;border:1px solid var(--color-border-strong);border-radius:10px" alt=""><p class="sp-cap">${cap}</p></figure>`;
  return page('Sprint 32 · Board 10 — Abstand zwischen Widgets', `
<header class="mock-board mock-head"><h1>Sprint 32 · Board 10 — der Abstand zwischen den Widgets ${SYN}</h1>
<p class="mock-note">Deine Frage vom 25.11.: „Mir gefällt bei den Dashboards der Widget-Abstand nicht. Kann man das nicht besser designen?“ Die Vorlage „Überblick“ in der laufenden App (Review-Seed), auf Apples festen Kacheln wie Board 09, in vier Abständen; nur CSS im Browser, nichts gespeichert (<code>real-app/spacing.js</code>). Die leeren Flächen in Wertentwicklung sind kein Abstandsthema: der Inhalt füllt seine Kachel erst nach Lane L.</p></header>
<section class="mock-board"><div class="mock-pickbar"><p><b>Was heute stört:</b> der Abstand zwischen zwei Widgets (12 px) ist kleiner als ihr Innenabstand (16 px seitlich), und die Ecken sind mit 12 px eng. Die Karten wirken dadurch aneinandergeklebt, als eine unruhige Fläche statt als einzelne Widgets. <b>Die Regel dagegen:</b> der Abstand zwischen Widgets ist mindestens so groß wie ihr Innenabstand.</p>
<p><b>Deine Wahl vom 25.11.: D „Eine Fläche“</b> („optisch find ich aktuell D am besten. Ich will da nicht so viel Platz verschwenden. Widgets als einzelnes Element auf iOS wäre was anderes für später, aber für die Web-App finde ich das so am besten“). Die Web-App zeichnet ein Dashboard als eine Fläche mit Haarlinien zwischen den Widgets; einzelne Karten mit Abstand bleiben für native Widgets (I53).</p>
<p><b>Die Empfehlung vor deiner Wahl war B „Luftig“:</b> 20 px zwischen den Widgets, 18 × 20 px innen, Ecken 16 px, eine feine Linie und ein weicher Schatten, 32 px Seitenrand. Sie trägt hell und dunkel. <b>C „Apple“</b> (24 px, Ecken 22 px, ohne Linie) ist am nächsten am iPhone, aber im Dunkelmodus verschwinden die Karten im Hintergrund (②) und auf 1280 px Breite kostet sie Platz. <b>D „Eine Fläche“</b> (Haarlinien statt Abständen) ist am dichtesten, verliert aber das Widget als Einheit. <b>Umschalten:</b> „Abstand C“, „Abstand D“, „Abstand wie bisher“.</p></div></section>
<section class="mock-board"><h2>① Vier Abstände, hell</h2>
<div class="sp-row">${img('10-heute-light.png', 'A heute: 12 px zwischen, 12 × 16 px innen, Ecken 12 px.')}${img('10-luftig-light.png', 'B Luftig (vorher empfohlen): 20 px zwischen, 18 × 20 px innen, Ecken 16 px, feine Linie, weicher Schatten.')}</div>
<div class="sp-row">${img('10-apple-light.png', 'C Apple: 24 px zwischen, 20 × 22 px innen, Ecken 22 px, ohne Linie.')}${img('10-flaeche-light.png', '<b>D Eine Fläche (gewählt):</b> 1 px Haarlinien statt Abstand, ein gemeinsamer Rahmen mit 16 px Ecken.')}</div></section>
<section class="mock-board"><h2>② D im Dunkelmodus ${tag('rec', 'gewählt')}</h2>${img('10-flaeche-dark.png', 'D dunkel: die Haarlinien bleiben sichtbar, die Fläche bleibt ruhig.')}</section>
<section class="mock-board"><h2>③ B und C im Dunkelmodus</h2>
<div class="sp-row">${img('10-luftig-dark.png', 'B: die feine Linie hält die Karten auseinander.')}${img('10-apple-dark.png', 'C: ohne Linie verschwimmen Karte und Hintergrund; C bräuchte im Dunkelmodus hellere Karten.')}</div></section>
`);
}
