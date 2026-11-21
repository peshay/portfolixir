// Builds the I56 idea boards: every function a widget, dashboards composed
// from widgets. All figures are synthetic: seeded random walks and invented
// names, no portfolio figure, name or machine detail.
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
  drift: (s = 't', hints = true) => wd(s, `${head('Allokation und Drift')}<div class="wd-sub" style="margin:-2px 0 6px">Ziel­plan „Basis“ · Toleranz ±3 Punkte</div><table class="wd-tab"><tr><th>Kategorie</th><th class="num">Ist</th><th class="num">Soll</th><th>Drift</th></tr>${[['Aktien Welt', 41.2, 40, 1.2], ['Aktien Europa', 21.0, 25, -4.0], ['Anleihen', 14.9, 15, -0.1], ['Krypto', 13.6, 10, 3.6], ['Cash', 9.3, 10, -0.7]].map(([n, i, z, d]) => `<tr><td>${n}</td><td class="num">${nf(1).format(i)} %</td><td class="num">${nf(0).format(z)} %</td><td><span class="wd-drift"><b style="${d >= 0 ? `left:50%;width:${Math.min(50, d * 8)}%` : `right:50%;width:${Math.min(50, -d * 8)}%`};${Math.abs(d) > 3 ? 'background:var(--color-warning)' : ''}"></b></span> <span class="${Math.abs(d) > 3 ? '' : 'wd-muted'}" style="font-size:10.5px;${Math.abs(d) > 3 ? 'color:var(--color-warning);font-weight:700' : ''}">${d > 0 ? '+' : d < 0 ? '−' : ''}${nf(1).format(Math.abs(d))}</span></td></tr>`).join('')}</table>${hints ? `<div class="wd-sub" style="margin-top:8px;line-height:1.45"><b style="color:var(--color-text)">Rechnerisch zum Soll</b> (nur Anzeige, kein Auftrag): Aktien Europa ≈ +8.400 €, Krypto ≈ −7.560 €</div>` : ''}${foot('2 außerhalb der Toleranz', 'Ziele bearbeiten')}`),
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
<!-- Generated by build.js. Idea board for I56: the widgets are static HTML
     and inline SVG from synthetic series; the colours come from app.css.
     No script runs here. -->
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

function sidebarA(on = 'Mein Überblick') {
  const dash = ['Mein Überblick', 'Performance', 'Allokation & Drift', 'Risiko & Crashes', 'Einkommen & Steuer', 'Bitcoin-Zyklus'];
  return `<aside class="wd-side"><div class="wd-brand">Portfolixir</div><h5>Dashboards</h5>${dash.map((d) => `<a class="${d === on ? 'on' : ''}"><span class="wd-ico">▦</span>${d}</a>`).join('')}<a class="add"><span class="wd-ico">+</span>Neues Dashboard</a><h5>Entdecken</h5><a><span class="wd-ico">◎</span>Wertpapiere</a><a><span class="wd-ico">☰</span>Nachrichten</a><a><span class="wd-ico">⊞</span>Alle Widgets</a><h5>Pflege</h5><a class="quiet"><span class="wd-ico">⚙</span>Daten pflegen</a><a class="quiet"><span class="wd-ico">⇪</span>Import</a></aside>`;
}

// ---------- board 01: the widget ----------
function board01() {
  const catalog = [
    ['Überblick', [['Gesamtwert', 'S M', 'Übersicht'], ['Datenqualität', 'S M', 'Übersicht; Vermögen › Bestände'], ['Fällig', 'S M', 'Übersicht'], ['Abseits des Ziels', 'S', 'Übersicht']]],
    ['Performance', [['Wertentwicklung (Gesamt, Kategorien, Wertpapiere)', 'S M L Voll', 'Vermögen › Bestände, 1. Abschnitt'], ['Beiträge je Position', 'M L', 'Vermögen › Bestände, unter dem Chart'], ['Tops und Flops', 'S M', 'Übersicht'], ['Snapshots', 'S W', 'Vermögen › 4. Tab', 1]]],
    ['Allokation', [['Allokation', 'M', 'Vermögen › Bestände'], ['Ziele und Drift, mit Rechenhinweis', 'M T', 'Vermögen › Allokation & Ziele, 2. Tab', 1]]],
    ['Positionen', [['Positionen', 'M L Voll', 'Vermögen › Bestände'], ['Cash-Konten', 'S M', 'Vermögen › Bestände'], ['Verkaufsrückblick', 'M', 'Übersicht; Wertpapierseite'], ['Wertpapier-Dossier', 'Voll', 'Wertpapiere › Seite']]],
    ['Einkommen und Kosten', [['Einkommen', 'W M', 'Vermögen › Cashflow, 3. Tab'], ['Ein- und Auszahlungen', 'M', 'ebd.'], ['Gebühren und Steuern', 'M', 'ebd.'], ['Realisiert', 'M', 'ebd.']]],
    ['Risiko', [['Kennzahlen', 'S M', 'Vermögen › Risiko, 6. Tab'], ['Konzentration (HHI)', 'S', 'ebd.'], ['Anlageklassen-Grenzen', 'M', 'ebd.'], ['Crashes im Vergleich', 'M L', 'ebd., unten', 1]]],
    ['Steuer', [['Freibetrag', 'S', 'Vermögen › Steuer, 5. Tab'], ['Bescheinigungen', 'M', 'ebd.']]],
    ['Analysen', [['Bitcoin-Zyklus', 'M L Voll', 'Übersicht-Karte; Wertpapierseite'], ['Prognosen und Kalibrierung', 'S M', 'Vermögen › Prognosen, 7. Tab']]],
    ['Nachrichten', [['Eingeordnete Nachrichten', 'M L', 'News (heute ungefiltert)']]],
  ];
  const rows = catalog.map(([g, ws]) => ws.map(([n, sz, today, hot], i) => `<tr${hot ? ' class="hot"' : ''}>${i === 0 ? `<td class="grp" rowspan="${ws.length}">${g}</td>` : ''}<td>${n}${hot ? ' <span class="mock-tag mock-tag--alt" style="margin:0 0 0 4px;padding:0 6px;font-size:9.5px">von dir: versteckt</span>' : ''}</td><td>${sz.split(' ').map((z) => `<span class="wd-sz">${z}</span>`).join('')}</td><td class="wd-muted">${today}</td></tr>`).join('')).join('');
  return page('Idee I56 — das Widget', `
<header class="mock-board mock-head"><h1>Idee I56 · 1 von 6 — das Widget als Baustein ${SYN}</h1>
<p class="mock-note">Ideen-Board vom 21.11.2026, kein Sprint-Board. Jede Funktion wird ein Widget: <b>eine Abfrage der bestehenden JSON-API plus ihre Darstellung</b>. Browser, Handy und später native Widgets lesen dieselbe Antwort. Alle Namen und Zahlen sind erfunden. Farben und Karten bleiben wie heute; die Farbfrage ist I48 mit eigenem Board.</p></header>

<section class="mock-board"><h2>Anatomie <small>jedes Widget hat dieselben fünf Teile</small></h2>
<div class="wd-anat"><div class="wd-grid" style="grid-auto-rows:118px">${W.perfM('m').replace('class="wd wd--m"', 'class="wd wd--m" style="grid-column:span 12"')}</div>
<ol class="wd-call">
<li><b>Titel und ⓘ</b>: das ⓘ zeigt die Rechenbasis aus der API-Antwort (Reihe, Fenster, Benchmark, Lücken), wie heute bei jeder Kennzahl.</li>
<li><b>Eigene Steuerung</b>: der Zeitraum sitzt im Widget, nicht oben auf der Seite. Dein häufigster Griff (kurzer Zeitraum, dann 1J, YTD, Max) ist ein Klick.</li>
<li><b>⋯-Menü</b>: Größe, Ansicht (Gesamt, ein Depot, eine Ansicht), entfernen, „Ganze Ansicht“.</li>
<li><b>Inhalt</b> in der gewählten Größe; die Zahlen sind dieselben wie in der API.</li>
<li><b>Fußzeile</b>: Bezug (welches Depot oder welche Ansicht) und der Weg in die volle Ansicht.</li>
</ol></div></section>

<section class="mock-board"><h2>Größen statt freier Pixel <small>S · M · L · Voll, wie Apples Widget-Größen</small></h2>
<p class="mock-note">Ein Widget kennt feste Größen. So lässt es sich auf dem Desktop im Raster anordnen, auf dem Handy untereinander stapeln und später als natives Widget in einer Größe auf den Home-Bildschirm legen. <b>Voll</b> ist die heutige Seite (etwa das große Chart mit Ebenen, Filter und Tabelle) und bleibt über „Ganze Ansicht“ erreichbar. Nicht jedes Widget braucht jede Größe.</p>
<div class="wd-sizes-row">
<div><span class="mock-tag mock-tag--alt">S · eine Zahl</span><div class="wd-grid" style="grid-template-columns:1fr">${W.perfS().replace('wd--s', 'wd--s" style="grid-column:span 1')}</div></div>
<div><span class="mock-tag mock-tag--alt">M · eine Aussage</span><div class="wd-grid" style="grid-template-columns:1fr;grid-auto-rows:118px">${W.perfM('m').replace('wd--m', 'wd--m" style="grid-column:span 1')}</div></div>
<div><span class="mock-tag mock-tag--alt">L · mit Ebenen</span><div class="wd-grid" style="grid-template-columns:1fr;grid-auto-rows:112px">${W.perfL('l').replace('wd--l', 'wd--l" style="grid-column:span 1')}</div></div>
</div></section>

<section class="mock-board"><h2>Der Katalog <small>die heutigen Funktionen als Widgets, nach Thema gruppiert</small></h2>
<p class="mock-note">Die Bestandsaufnahme aus I35 in ihrer neuen Form. Rechts steht, wo die Funktion heute liegt. <b>Hervorgehoben</b> sind die drei, die du versteckt genannt hast. Die Pflege (Import, Transaktionen, Konten und Depots, Ansichten, Klassifizierungen, Feeds, Audit-Journal) wird <b>kein Widget</b>: sie zieht an einen eigenen, ruhigen Ort (I47), weil dein Agent die Daten pflegt.</p>
<div class="mock-frame"><table class="wd-cat"><tr><th>Gruppe</th><th>Widget</th><th>Größen</th><th>Heute zu finden</th></tr>${rows}</table></div></section>`);
}

// ---------- board 02: navigation ----------
function board02() {
  const miniA = `<div class="wd-mini"><div class="s">Gesamtwert</div><div class="s">Datenqualität</div><div class="s">Fällig</div><div class="s">Konzentration</div><div class="l">Wertentwicklung nach Kategorien</div><div class="t">Allokation und Drift</div><div class="m">Tops und Flops</div><div class="m">Crashes im Vergleich</div></div>`;
  const shellA = `<div class="wd-shell" style="min-height:430px">${sidebarA()}<div class="wd-main"><div class="wd-top"><h3>Mein Überblick</h3><span class="mock-select">Gesamt ▾</span><span class="wd-sp"></span><span class="wd-btn">Vorlagen</span><span class="wd-btn wd-btn--acc">Bearbeiten</span></div>${miniA}</div></div>`;
  const shellB = `<div class="wd-shell" style="min-height:430px"><aside class="wd-side"><div class="wd-brand">Portfolixir</div><a><span class="wd-ico">⌂</span>Übersicht</a><a class="on"><span class="wd-ico">◔</span>Vermögen</a><a><span class="wd-ico">◎</span>Wertpapiere</a><a><span class="wd-ico">☰</span>News</a><h5>Daten</h5><a class="quiet">Transaktionen</a><a class="quiet">Konten &amp; Depots</a><a class="quiet">Ansichten</a><a class="quiet">Klassifizierungen</a><a class="quiet">Audit-Journal</a><h5>Meine Dashboards</h5><a>▦ Kurzfristig</a><a class="add">+ Neues Dashboard</a></aside><div class="wd-main"><div class="wd-top"><h3>Vermögen</h3><span class="wd-sp"></span><span class="wd-btn">Bearbeiten</span></div><div class="wd-tabs"><span class="on">Bestände</span><span>Allokation &amp; Ziele</span><span>Cashflow</span><span>Snapshots</span><span>Steuer</span><span>Risiko</span><span>Prognosen</span></div><div class="wd-mini"><div class="l">Wertentwicklung nach Kategorien</div><div class="t">Allokation</div><div class="m">Positionen</div><div class="m">Cash-Konten</div></div></div></div>`;
  return page('Idee I56 — Navigation', `
<header class="mock-board mock-head"><h1>Idee I56 · 2 von 6 — wohin das Menü führt ${SYN}</h1>
<p class="mock-note">Deine offene Frage: Wird das Menü zur Liste der Dashboards, oder bleiben die heutigen Bereiche und Dashboards kommen dazu? Beide Varianten in derselben Breite, mit denselben Widgets.</p>
<div class="mock-pickbar"><p><b>Zur Wahl:</b> A oder B. Empfohlen ist <b>A</b>: Mit B bleiben die sieben Tabs und mit ihnen das Verstecken. Drift, Snapshots und Crashes lägen weiter im 2., 4. und 6. Tab. A stellt dieselben Widgets auf Dashboards nach Thema zusammen, und jedes Dashboard ist veränderbar.</p><p><b>Umdrehen mit:</b> „Bereiche behalten“ (B).</p></div></header>

<section class="mock-board"><span class="mock-tag mock-tag--rec">A · empfohlen</span><h2>Das Menü ist die Liste deiner Dashboards</h2>
<p class="mock-note">Oben die Dashboards: fünf kuratierte Vorlagen und deine eigenen, beliebig viele (hier ein eigenes: Bitcoin-Zyklus). Darunter <b>Entdecken</b>: Wertpapiere (die Liste und jede Wertpapierseite, selbst aus Widgets gebaut), Nachrichten und der Katalog <b>Alle Widgets</b>, damit nichts unauffindbar wird. Ganz unten, ruhig: <b>Pflege</b>, wo die Formulare hinziehen (I47). Die Auswahl „Gesamt ▾“ setzt die Ansicht für das ganze Dashboard; ein Widget kann sie für sich überschreiben.</p>
${shellA}</section>

<section class="mock-board"><span class="mock-tag mock-tag--alt">B · Alternative</span><h2>Die Bereiche bleiben, Dashboards kommen dazu</h2>
<p class="mock-note">Jeder Tab wird intern zu einem festen Widget-Dashboard und ist damit auch umstellbar. Daneben stehen eigene Dashboards. Der Umbau ist kleiner, aber die Struktur mit sieben Tabs bleibt. Die Pflegebereiche stehen weiter mitten im Menü.</p>
${shellB}</section>`);
}

// ---------- board 03: the dashboard ----------
function board03() {
  const grid = [W.total(), W.quality(), W.due(), W.risk(), W.perfL(), W.drift(), W.movers(), W.crashes(), W.cycle(), W.news(), W.snapshots(), W.income()].join('');
  const editGrid = [
    W.total().replace('<section class="wd wd--s">', '<section class="wd wd--s"><span class="wd-handle"></span><span class="wd-x">×</span>'),
    W.quality().replace('<section class="wd wd--s">', '<section class="wd wd--s"><span class="wd-handle"></span><span class="wd-x">×</span>'),
    W.moversS().replace('<section class="wd wd--s">', '<section class="wd wd--s"><span class="wd-handle"></span><span class="wd-x">×</span><span class="wd-sizes"><span class="on">S</span><span>M</span></span>'),
    '<div class="wd-drop">Snapshots hier ablegen</div>',
    W.perfL('l').replace('<section class="wd wd--l">', '<section class="wd wd--l"><span class="wd-handle"></span><span class="wd-x">×</span><span class="wd-sizes"><span>S</span><span>M</span><span class="on">L</span></span>'),
    W.drift('t', false).replace('<section class="wd wd--t">', '<section class="wd wd--t"><span class="wd-handle"></span><span class="wd-x">×</span><span class="wd-sizes"><span>M</span><span class="on">T</span></span>'),
  ].join('');
  const panel = `<div class="wd-panel"><b>Widget hinzufügen</b><div class="wd-search" style="margin:8px 0 2px">Suchen …</div>
<h4>Performance</h4><div class="wd-item">Wertentwicklung <em>S M L</em></div><div class="wd-item">Beiträge je Position <em>M L</em></div><div class="wd-item hl">Snapshots <em>S W</em></div>
<h4>Allokation</h4><div class="wd-item">Allokation <em>M</em></div>
<h4>Risiko</h4><div class="wd-item">Crashes im Vergleich <em>M L</em></div><div class="wd-item">Anlageklassen-Grenzen <em>M</em></div>
<h4>Einkommen</h4><div class="wd-item">Einkommen <em>W M</em></div><div class="wd-item">Gebühren und Steuern <em>M</em></div>
<h4>Analysen</h4><div class="wd-item">Bitcoin-Zyklus <em>M L</em></div><div class="wd-item">Prognosen <em>S M</em></div>
<div class="wd-sub" style="margin-top:8px">Ziehen oder antippen. Dein Agent kann dasselbe über API und MCP.</div></div>`;
  const tpl = (name, desc, cells) => `<div class="wd-tpl"><div class="wd-mini">${cells.map((c) => `<div class="${c}"></div>`).join('')}</div><b>${name}</b><span class="wd-muted">${desc}</span></div>`;
  return page('Idee I56 — ein Dashboard', `
<header class="mock-board mock-head"><h1>Idee I56 · 3 von 6 — ein Dashboard, bearbeitet und als Vorlage ${SYN}</h1>
<p class="mock-note">„Mein Überblick“, gebaut aus dem, was du am meisten liest. Oben: Hauptchart mit Kategorien und Zeitraum im Widget. Daneben: die Drift-Tabelle, heute im 2. Tab. Dazu Tops und Flops, Crashes (heute im 6. Tab), Zyklus, eingeordnete Nachrichten und Snapshots (heute im 4. Tab). Ein 12-Spalten-Raster: S = 3 Spalten, M = 6, L = 8 × 3 Zeilen, T = 4 × 3 (hoch), W = 6 × 1 (breit).</p></header>

<section class="mock-board"><span class="mock-tag mock-tag--rec">Ansehen</span><h2>Mein Überblick <small>Desktop, 1120 px</small></h2>
<div class="wd-shell">${sidebarA()}<div class="wd-main"><div class="wd-top"><h3>Mein Überblick</h3><span class="mock-select">Gesamt ▾</span><span class="wd-sp"></span><span class="wd-btn">Vorlagen</span><span class="wd-btn wd-btn--acc">Bearbeiten</span></div><div class="wd-grid">${grid}</div></div></div></section>

<section class="mock-board wd-edit"><span class="mock-tag mock-tag--alt">Bearbeiten</span><h2>Derselbe Screen im Bearbeitungsmodus</h2>
<p class="mock-note">Ein Schalter oben. Widgets ziehen sich am Griff, die Größe wechselt unten rechts, × entfernt. Rechts der Katalog zum Hinzufügen. Gespeichert wird <b>auf dem Server</b> und im Journal: Das Dashboard sieht auf jedem Gerät gleich aus, und dein Agent kann eines für dich bauen („stell mir ein Dashboard für kurzfristige Bewegungen zusammen“). Damit beantwortet der Bearbeitungsmodus auch die offene Frage aus I47: Bearbeiten ist ein Modus.</p>
<div class="wd-shell" style="grid-template-columns:196px 1fr 230px">${sidebarA()}<div class="wd-main"><div class="wd-top"><h3>Mein Überblick</h3><span class="wd-sub">bearbeiten</span><span class="wd-sp"></span><span class="wd-btn">Zurücksetzen</span><span class="wd-btn wd-btn--acc">Fertig</span></div><div class="wd-grid">${editGrid}</div></div><div style="padding:12px 12px 12px 0">${panel}</div></div></section>

<section class="mock-board"><span class="mock-tag mock-tag--alt">Vorlagen</span><h2>Kuratierte Dashboards <small>mitgeliefert, schreibgeschützt; kopieren und anpassen</small></h2>
<p class="mock-note">Ein neuer Nutzer startet mit diesen fünf und findet so jede Funktion. Ändern kann man nur eine Kopie, damit die Vorlage für alle gleich bleibt und mit neuen Versionen besser werden kann.</p>
<div class="wd-templates">
${tpl('Überblick', 'Hat sich etwas geändert, braucht etwas mich?', ['s', 's', 's', 's', 'l', 't'])}
${tpl('Performance', 'Wertentwicklung, Beiträge, Tops und Flops, Snapshots', ['l', 't', 'm', 'm'])}
${tpl('Allokation &amp; Drift', 'Ist gegen Soll, Rechenhinweis, Allokation', ['t', 'l', 'm', 'm'])}
${tpl('Risiko &amp; Crashes', 'Kennzahlen, Konzentration, Grenzen, Crashes', ['s', 's', 's', 's', 'm', 'm'])}
${tpl('Einkommen &amp; Steuer', 'Einkommen, Kosten, Realisiert, Freibetrag', ['w', 'w', 'm', 'm'])}
</div></section>`);
}

// ---------- board 04: devices ----------
function board04() {
  const phone = [W.total(), W.quality(), W.perfM('m'), W.movers('m'), W.drift('m', false)].join('').replace(/<span class="wd-chips">(<span[^>]*>1W<\/span>)/, '<span class="wd-chips">');
  return page('Idee I56 — Geräte', `
<header class="mock-board mock-head"><h1>Idee I56 · 4 von 6 — dasselbe Widget auf jedem Gerät ${SYN}</h1>
<p class="mock-note">Weil ein Widget nur eine API-Antwort in fester Größe ist, trägt das Prinzip über den Browser hinaus. Hier steht, was <b>später</b> kommt: native Widgets in einem eigenen Repository (I53, Schritt 3, eine eigene Planentscheidung). Die App im Handy-Browser und als Home-Bildschirm-App zeigt Board 6 in jeder Größe; die erste Fassung dieses Boards zeichnete dort zu gequetscht.</p></header>

<section class="mock-board"><h2>iPhone-Home-Bildschirm <small>später; die Handy-Ansicht der App selbst zeigt Board 6</small></h2>
<div class="wd-dev"><div><div class="wd-home"><div class="ios"><div class="nw s2"><div class="t">Gesamtwert</div><div class="k">${eur(last)}</div><div style="color:#0f766e;font-weight:700">+1,24 % heute</div></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="nw m4"><div class="t">Tops und Flops · Woche</div><div style="display:flex;justify-content:space-between;margin-top:4px"><span>Halbleiter AG</span><b style="color:#0f766e">+6,8 %</b></div><div style="display:flex;justify-content:space-between"><span>Welt-ETF</span><b style="color:#0f766e">+2,1 %</b></div><div style="display:flex;justify-content:space-between"><span>Krypto-Münze</span><b style="color:#ce1b42">−5,2 %</b></div></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div></div></div><p class="wd-cap"><span class="mock-tag mock-tag--before" style="margin:0">später</span> iOS-Home-Bildschirm: S als kleines, M als mittleres natives Widget, aus demselben Katalog gewählt.</p></div></div></section>

<section class="mock-board"><h2>Schreibtisch und Wand <small>später, eigenes Repository</small></h2>
<div class="wd-dev">
<div><div class="wd-mac"><div class="bar"></div><div class="nw" style="left:20px;top:34px;width:150px"><div style="opacity:.75;font-size:10px;font-weight:700;text-transform:uppercase">Gesamtwert</div><div style="font-size:18px;font-weight:760">${eur(last)}</div><div style="color:#5eead4">+1,24 % heute</div></div><div class="nw" style="left:20px;top:126px;width:300px;height:120px"><div style="opacity:.75;font-size:10px;font-weight:700;text-transform:uppercase">Wertentwicklung · 3M</div><svg viewBox="0 0 300 90" style="width:100%;height:90px"><path d="${pathOf(total.slice(-65), 300, 90, scale(total.slice(-65), 90, 6))}" style="fill:none;stroke:#c4b5fd;stroke-width:1.8"/></svg></div></div><p class="wd-cap">macOS-Schreibtisch: dieselben S- und M-Widgets.</p></div>
<div><div class="wd-vision"><div class="win"><div style="font-size:10px;font-weight:700;text-transform:uppercase;color:#5a6577">Allokation und Drift</div>${['Aktien Welt +1,2', 'Aktien Europa −4,0', 'Anleihen −0,1', 'Krypto +3,6', 'Cash −0,7'].map((r) => `<div style="display:flex;justify-content:space-between;border-bottom:1px solid rgb(0 0 0 / .08);padding:3px 0"><span>${r.split(/ [+−]/)[0]}</span><b style="color:#0e141b">${r.match(/[+−].*/)[0]}</b></div>`).join('')}</div></div><p class="wd-cap">visionOS: ein Widget als Fenster an der Wand, etwa die Drift-Tabelle.</p></div>
</div>
<p class="mock-note" style="margin-top:14px"><b>Was das technisch heißt:</b> Ein natives Widget holt sich bei jeder Aktualisierung seine API-Antwort mit eigenem Token, ganz wie ein Agent. Push-Nachrichten an externe Geräte sind gesperrt (B3.7), werden dafür aber nicht gebraucht. Erreichbar ist die Instanz, wo sie heute erreichbar ist (Heimnetz, VPN, eigener Proxy). Die Apps lägen in einem eigenen Repository und lesen nur die API.</p></section>`);
}

// ---------- board 05: the period ----------
const PERIODS = ['1T', '1W', '1M', '3M', 'YTD', '1J', '3J', 'Max'];
const pchips = (on) => `<span class="pd-chips">${PERIODS.map((p) => `<span${p === on ? ' class="on"' : ''}>${p}</span>`).join('')}</span>`;
const phead = (t, badge) => `<div class="wd-h"><span class="wd-t">${t}</span><span class="wd-i">i</span><span class="wd-sp"></span>${badge}<span class="wd-more">⋯</span></div>`;
function board05() {
  const perf = (badge, vals, sub, extra = '') => `<section class="wd wd--m" style="position:relative">${phead('Wertentwicklung', badge)}<div class="wd-sub" style="margin:-2px 0 4px">${sub}</div><div class="wd-body">${lineChart(vals, null, 460, 150, null)}</div>${foot('Gesamt · alle Depots', 'Ganze Ansicht')}${extra}</section>`;
  const menu = `<div class="pd-menu"><div class="hl">● Folgt dem Dashboard (3M)</div><div>Eigener Zeitraum …</div><hr><div>Größe</div><div>Ansicht: Gesamt</div><div>Entfernen</div></div>`;
  const grid = [
    perf('<span class="pd-follow">folgt · 3M</span>', total.slice(-65), '<b class="pos">+4,8 %</b> TTWROR in 3 Monaten'),
    perf('<span class="pd-pin">📌 eigener: Max</span>', total.map((v, i) => v * (0.55 + (0.45 * i) / total.length)), '<b class="pos">+86,0 %</b> TTWROR seit Beginn · bleibt bei Max, egal was oben gewählt ist'),
    `<section class="wd wd--m">${phead('Tops und Flops', '<span class="pd-follow">folgt · 3M → Quartal</span>')}<div class="wd-sub" style="margin:-2px 0 6px">Das Widget kennt Tag, Woche, Monat, Quartal, YTD und 1 Jahr; 3M wird zum laufenden Quartal, und das steht hier.</div><div class="wd-two"><div><h4>Höchste</h4><table class="wd-tab"><tr><td>Halbleiter AG</td><td class="num pos">+14,2 %</td></tr><tr><td>Welt-ETF</td><td class="num pos">+5,0 %</td></tr></table></div><div><h4>Niedrigste</h4><table class="wd-tab"><tr><td>Krypto-Münze</td><td class="num neg">−9,8 %</td></tr><tr><td>Autobauer Süd</td><td class="num neg">−6,1 %</td></tr></table></div></div>${foot('', 'In Vermögen')}</section>`,
    `<section class="wd wd--m">${phead('Bitcoin-Zyklus', '<span class="pd-na">ohne Zeitraum</span>')}<div class="wd-body">${cycleMini(460, 140)}</div><div class="wd-sub">Zeigt immer alle Zyklen plus Prognose; der Zeitraum oben gilt hier nicht, und das Etikett sagt es.</div></section>`,
  ].join('');
  const mini = (name, cells) => `<div class="mock-frame" style="padding:10px 12px"><div class="pd-bar" style="margin:0 0 8px"><b style="font-size:13px">${name}</b><span class="wd-sp" style="flex:1"></span>${pchips('3M')}</div><div class="wd-mini">${cells}</div></div>`;
  return page('Idee I56 — der Zeitraum', `
<header class="mock-board mock-head"><h1>Idee I56 · 5 von 6 — ein Zeitraum für alles, Ausnahmen festgepinnt ${SYN}</h1>
<p class="mock-note">Deine zwei Wünsche widersprechen sich nur scheinbar: meistens sollen <b>alle Dashboards denselben Zeitraum</b> zeigen, manchmal soll <b>dasselbe Widget mit zwei Zeiträumen nebeneinander</b> stehen. Der Vorschlag: Der Zeitraum ist eine Auswahl oben, die für alle Dashboards gilt und beim Wechsel bleibt. Ein Widget folgt ihr, bis man ihm im ⋯-Menü einen eigenen gibt; dann trägt es eine Marke.</p>
<div class="mock-pickbar"><p><b>Zur Wahl:</b> A, B oder C (Tabelle unten). Empfohlen ist <b>A</b>.</p><p><b>Umdrehen mit:</b> „Zeitraum je Widget“ (B) oder „Zeitraum je Dashboard“ (C).</p></div></header>

<section class="mock-board"><span class="mock-tag mock-tag--rec">A · empfohlen</span><h2>Ein Zeitraum oben, ein Widget darf abweichen</h2>
<p class="mock-note">Oben 3M. Das erste Chart folgt und sagt es leise („folgt · 3M“). Das zweite ist auf Max festgepinnt und zeigt das in Akzentfarbe, damit niemand eine Max-Zahl für eine 3M-Zahl hält. Tops und Flops übersetzt 3M in seinen nächsten eigenen Zeitraum und sagt auch das. Der Zyklus hat keinen Zeitraum. Rechts oben das ⋯-Menü des ersten Charts.</p>
<div class="mock-frame"><div class="pd-bar" style="margin:0 0 12px"><h3 style="margin:0;font-size:16px">Mein Überblick</h3><span class="mock-select">Gesamt ▾</span><span style="flex:1"></span>${pchips('3M')}</div>
<div class="wd-grid">${grid.replace('<section class="wd wd--m" style="position:relative">', '<section class="wd wd--m" style="position:relative;overflow:visible">').replace(foot('Gesamt · alle Depots', 'Ganze Ansicht') + '</section>', foot('Gesamt · alle Depots', 'Ganze Ansicht') + menu + '</section>')}</div></div></section>

<section class="mock-board"><h2>Der Zeitraum bleibt beim Wechsel <small>von „Mein Überblick“ zu „Risiko &amp; Crashes“</small></h2>
<p class="mock-note">Der gewählte Zeitraum hängt an dir, nicht am Dashboard: Er wird gemerkt (wie heute Thema und Sprache) und gilt auf jedem Dashboard, bis du ihn änderst. Ein Link auf ein Dashboard darf ihn mitgeben, etwa „Performance auf YTD“.</p>
<div style="display:grid;grid-template-columns:1fr 40px 1fr;gap:8px;align-items:center">${mini('Mein Überblick', '<div class="s">Gesamtwert</div><div class="s">Datenqualität</div><div class="s">Fällig</div><div class="s">Konzentration</div><div class="l">Wertentwicklung · folgt 3M</div><div class="t">Allokation und Drift</div>')}<div style="text-align:center;font-size:22px;color:var(--color-accent)">→</div>${mini('Risiko &amp; Crashes', '<div class="s">Volatilität · folgt 3M</div><div class="s">Max. Drawdown · folgt 3M</div><div class="s">Konzentration</div><div class="s">Grenzen</div><div class="l">Crashes im Vergleich · ohne Zeitraum</div><div class="t">Kennzahlen · folgt 3M</div>')}</div></section>

<section class="mock-board"><h2>Die drei Möglichkeiten</h2>
<div class="mock-frame"><table class="pd-var"><tr><th></th><th>Wo der Zeitraum sitzt</th><th>Alle Dashboards gleich</th><th>Zwei Zeiträume nebeneinander</th><th>Preis</th></tr>
<tr class="rec"><td><b>A</b> · empfohlen</td><td>oben, für alle; ein Widget kann sich festpinnen</td><td>ja, von selbst</td><td>ja, ein Widget festpinnen</td><td>eine Marke am Widget und eine Regel, wie ein Widget einen Zeitraum übersetzt, den es nicht kennt</td></tr>
<tr><td><b>B</b></td><td>in jedem Widget (Board 1 bis 3)</td><td>nein: jedes Widget einzeln umstellen</td><td>ja</td><td>ein Zeitraum-Wechsel sind viele Klicks</td></tr>
<tr><td><b>C</b></td><td>oben, je Dashboard</td><td>nein: jedes Dashboard merkt sich seinen</td><td>nein, nur über ein zweites Dashboard</td><td>beim Wechsel springt der Zeitraum</td></tr></table></div></section>`);
}

// ---------- board 06: screen formats ----------
function compactScreen(opts) {
  const { w, h, cls = '', two = false, tab = true, more = false } = opts;
  const vals = total.slice(-65);
  const cTotal = `<div class="cp"><div class="cp-h">Gesamtwert</div><div class="cp-k">${eur(last)}</div><div class="cp-s"><span class="pos" style="font-weight:700">+1,24 %</span> heute · <span class="pos">+2.980 €</span></div><div style="margin-top:8px">${spark(total.slice(-60), 300, 40)}</div></div>`;
  const cQual = `<div class="cp"><div class="cp-line"><span class="wd-dot" style="margin:0"></span><span><b>Datenqualität</b> · 2 Hinweise</span><span class="chev">›</span></div></div>`;
  const cPerf = `<div class="cp"><div class="cp-h">Wertentwicklung <small>folgt · 3M</small></div><div class="cp-k2 pos">+4,8 %</div><div class="cp-s" style="margin-bottom:6px">TTWROR · Welt-Index +3,1 %</div>${lineChart(vals, null, 340, 170, ['Aug', 'Okt', 'Nov'])}</div>`;
  const cMov = `<div class="cp"><div class="cp-h">Tops und Flops <small>Quartal</small></div><div class="cp-seg"><span class="on">Höchste</span><span>Niedrigste</span></div>${[['Halbleiter AG', 14.2, 2420], ['Welt-ETF', 5.0, 1980], ['Netz Versorger', 3.9, 410]].map(([n, p, e]) => `<div class="cp-r"><div class="n">${n}<small>+${eur(e)} Beitrag</small></div><div class="v pos">${pct(p)}</div></div>`).join('')}</div>`;
  const cDrift = `<div class="cp"><div class="cp-h">Drift <small>±3 Punkte</small></div>${[['Aktien Europa', 21.0, 25, -4.0], ['Krypto', 13.6, 10, 3.6], ['Aktien Welt', 41.2, 40, 1.2]].map(([n, i, z, d]) => `<div class="cp-r"><div class="n">${n}<small>${nf(1).format(i)} % · Soll ${z} %</small></div><div class="v" style="${Math.abs(d) > 3 ? 'color:var(--color-warning)' : 'color:var(--color-text-muted);font-weight:600'}">${d > 0 ? '+' : '−'}${nf(1).format(Math.abs(d))} Pkt.</div></div>`).join('')}</div>`;
  const cSnap = `<div class="cp"><div class="cp-h">Snapshots <small>14</small></div><div class="cp-r"><div class="n">01.11.2026<small>letzter Snapshot</small></div><div class="v pos">+2,3 %</div></div></div>`;
  const cNews = `<div class="cp"><div class="cp-h">Nachrichten <small>eingeordnet</small></div>${[['Halbleiter AG hebt die Jahresprognose an', 'hoch · Agentur'], ['Notenbank lässt den Leitzins unverändert', 'hoch · Agentur']].map(([t, m]) => `<div class="cp-r"><div class="n">${t}<small>${m}</small></div></div>`).join('')}</div>`;
  const body = two
    ? `<div class="cp-col two"><div class="cp-stack">${cPerf}${cDrift}${more ? cNews : ''}</div><div class="cp-stack">${cTotal}${cQual}${cMov}${more ? cSnap : ''}</div></div>`
    : `<div class="cp-col">${cTotal}${cQual}${cPerf}${cMov}${cDrift}</div>`;
  const tabbar = tab ? `<div class="cp-tabbar"><span class="on"><b>▦</b>Dashboards</span><span><b>◎</b>Wertpapiere</span><span><b>☰</b>Nachrichten</span><span><b>⋯</b>Mehr</span></div>` : '';
  return `<div class="cp-dev ${cls}" style="width:${w}px;height:${h}px"><div class="cp-status">9:41</div><div class="cp-appbar"><h3>Mein Überblick ▾</h3><span class="cp-sel">Gesamt</span></div><div class="cp-period">${PERIODS.map((p) => `<span${p === '3M' ? ' class="on"' : ''}>${p}</span>`).join('')}</div>${body}${tabbar}</div>`;
}
function board06() {
  const cap = (t) => `<p class="cp-cap">${t}</p>`;
  return page('Idee I56 — Bildschirmformate', `
<header class="mock-board mock-head" style="max-width:1400px"><h1>Idee I56 · 6 von 6 — Bildschirmformate, lesbar auf jedem ${SYN}</h1>
<p class="mock-note" style="max-width:150ch">Das Handy von Board 4 war gequetscht: Es waren die Desktop-Widgets, nur schmaler. Hier hat jedes Widget eine eigene <b>kompakte Form</b> mit Handy-Schrift (Text 15 bis 17 pt, Zahlen 22 bis 30 pt, nichts unter 12 pt) und Zeilen mit mindestens 44 pt Höhe zum Antippen. In einer Zeile steht höchstens ein Name und eine Zahl, die zweite Zahl steht darunter. Alle Geräte sind <b>1 : 1 in Punkten</b> gezeichnet, bis auf das iPad.</p></header>

<section class="mock-board" style="max-width:1400px"><h2>Die Regel: die Breite entscheidet, nicht das Gerät</h2>
<div class="mock-frame" style="max-width:900px"><table class="cp-classes"><tr><th>Klasse</th><th>Verfügbare Breite</th><th>Aufbau</th><th>Beispiele</th></tr>
<tr><td><b>kompakt</b></td><td>unter 600 pt</td><td>eine Spalte, jedes Widget in seiner kompakten Form, Tab-Leiste unten, Zeitraum als wischbare Leiste</td><td>jedes iPhone hochkant, das Faltgerät zugeklappt, ein schmales Fenster auf dem iPad oder Mac</td></tr>
<tr><td><b>mittel</b></td><td>600 bis 1000 pt</td><td>zwei Spalten aus kompakten Widgets, die Reihenfolge des Desktop-Rasters spaltenweise</td><td>das Faltgerät aufgeklappt, iPad hochkant, iPhone quer</td></tr>
<tr><td><b>breit</b></td><td>ab 1000 pt</td><td>das 12-Spalten-Raster von Board 3 mit Seitenleiste</td><td>iPad quer, Mac, Desktop-Browser</td></tr></table></div>
<p class="mock-note" style="margin-top:8px">So muss kein Gerätemodell im Code stehen. Ein neues Format, etwa ein Faltgerät oder ein geteilter Bildschirm, fällt von selbst in eine Klasse.</p></section>

<section class="mock-board" style="max-width:1400px"><h2>iPhone, drei Größen <small>der erste Bildschirm ohne Scrollen, 1 : 1</small></h2>
<div class="cp-row">
<div>${compactScreen({ w: 375, h: 667 })}${cap('<b>Klein</b>, 375 × 667 pt (SE-Klasse): gleiche Schrift, nur weniger auf einmal. Darunter wird gescrollt.')}</div>
<div>${compactScreen({ w: 402, h: 874 })}${cap('<b>Standard</b>, um 400 × 870 pt: Gesamtwert, Datenqualität und das Chart passen auf den ersten Blick.')}</div>
<div>${compactScreen({ w: 440, h: 956 })}${cap('<b>Max/Plus</b>, 440 × 956 pt: dieselbe Spalte, breiter, und Tops und Flops kommen dazu.')}</div>
</div></section>

<section class="mock-board" style="max-width:1400px"><h2>Das faltbare iPhone <small>zugeklappt kompakt, aufgeklappt mittel</small></h2>
<p class="mock-note" style="max-width:150ch"><b>Die Maße sind angenommen</b>: rund 360 × 640 pt außen und ein fast quadratisches, querliegendes Innen-Display von rund 760 × 580 pt. Vor dem Bau gilt das echte Maß. Für die Regel oben spielt das keine Rolle. Zugeklappt ist das Gerät kompakt, aufgeklappt mittel, und beim Aufklappen bleibt die Stelle, an der man gerade liest.</p>
<div class="cp-row">
<div>${compactScreen({ w: 360, h: 640, cls: 'fold' })}${cap('<b>Zugeklappt</b>, angenommen 360 × 640 pt: kompakt, eine Spalte.')}</div>
<div>${compactScreen({ w: 760, h: 580, cls: 'fold', two: true, tab: false })}${cap('<b>Aufgeklappt</b>, angenommen 760 × 580 pt: mittel, zwei Spalten. Das Chart steht links und ist so hoch wie zwei Karten. Die Tab-Leiste wird zur Seitenleiste, sobald die Höhe knapp ist (hier weggelassen).')}</div>
</div></section>

<section class="mock-board" style="max-width:1400px"><h2>iPad hochkant <small>mittel, auf 60 % verkleinert</small></h2>
<div style="width:${Math.round(834 * 0.6) + 20}px;height:${Math.round(1194 * 0.6) + 20}px"><div class="cp-scaled" style="transform:scale(.6)">${compactScreen({ w: 834, h: 1194, cls: 'pad', two: true, more: true })}</div></div>
${cap('<b>834 × 1194 pt</b>: zwei Spalten wie beim aufgeklappten Faltgerät. Quer (1194 pt) wird es breit, mit dem Raster von Board 3.')}</section>`);
}

const boards = { '01-widget': board01, '02-navigation': board02, '03-dashboard': board03, '04-devices': board04, '05-period': board05, '06-screens': board06 };
for (const [name, fn] of Object.entries(boards)) {
  fs.writeFileSync(path.join(__dirname, name + '.html'), fn());
  console.log('wrote ' + name + '.html');
}
