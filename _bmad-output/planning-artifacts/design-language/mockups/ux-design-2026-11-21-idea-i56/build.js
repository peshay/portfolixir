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
<header class="mock-board mock-head"><h1>Idee I56 · 1 von 4 — das Widget als Baustein ${SYN}</h1>
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
<header class="mock-board mock-head"><h1>Idee I56 · 2 von 4 — wohin das Menü führt ${SYN}</h1>
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
<header class="mock-board mock-head"><h1>Idee I56 · 3 von 4 — ein Dashboard, bearbeitet und als Vorlage ${SYN}</h1>
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
<header class="mock-board mock-head"><h1>Idee I56 · 4 von 4 — dasselbe Widget auf jedem Gerät ${SYN}</h1>
<p class="mock-note">Weil ein Widget nur eine API-Antwort in fester Größe ist, trägt das Prinzip über den Browser hinaus. Links das, was im Rahmen der Idee gebaut würde: das Handy im Browser und als Home-Bildschirm-App (I53, Schritt 1). Rechts das, was <b>später</b> kommt: native Widgets in einem eigenen Repository (I53, Schritt 3, eine eigene Planentscheidung).</p></header>

<section class="mock-board"><h2>Handy <small>dasselbe Dashboard, gestapelt; S teilt sich eine Zeile</small></h2>
<div class="wd-dev"><div><div class="wd-phone"><div class="wd-top" style="margin:0 2px 8px"><h3 style="font-size:15px">Mein Überblick</h3><span class="wd-sp"></span><span class="wd-btn" style="padding:2px 8px">☰</span></div><div class="wd-grid">${phone}</div></div><p class="wd-cap">Die Reihenfolge ist die des Desktop-Rasters, von links oben nach rechts unten. L und T werden auf dem Handy zu M, Voll bleibt eine eigene Seite.</p></div>

<div><div class="wd-home"><div class="ios"><div class="nw s2"><div class="t">Gesamtwert</div><div class="k">${eur(last)}</div><div style="color:#0f766e;font-weight:700">+1,24 % heute</div></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="nw m4"><div class="t">Tops und Flops · Woche</div><div style="display:flex;justify-content:space-between;margin-top:4px"><span>Halbleiter AG</span><b style="color:#0f766e">+6,8 %</b></div><div style="display:flex;justify-content:space-between"><span>Welt-ETF</span><b style="color:#0f766e">+2,1 %</b></div><div style="display:flex;justify-content:space-between"><span>Krypto-Münze</span><b style="color:#ce1b42">−5,2 %</b></div></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div><div class="app"></div></div></div><p class="wd-cap"><span class="mock-tag mock-tag--before" style="margin:0">später</span> iOS-Home-Bildschirm: S als kleines, M als mittleres natives Widget, aus demselben Katalog gewählt.</p></div></div></section>

<section class="mock-board"><h2>Schreibtisch und Wand <small>später, eigenes Repository</small></h2>
<div class="wd-dev">
<div><div class="wd-mac"><div class="bar"></div><div class="nw" style="left:20px;top:34px;width:150px"><div style="opacity:.75;font-size:10px;font-weight:700;text-transform:uppercase">Gesamtwert</div><div style="font-size:18px;font-weight:760">${eur(last)}</div><div style="color:#5eead4">+1,24 % heute</div></div><div class="nw" style="left:20px;top:126px;width:300px;height:120px"><div style="opacity:.75;font-size:10px;font-weight:700;text-transform:uppercase">Wertentwicklung · 3M</div><svg viewBox="0 0 300 90" style="width:100%;height:90px"><path d="${pathOf(total.slice(-65), 300, 90, scale(total.slice(-65), 90, 6))}" style="fill:none;stroke:#c4b5fd;stroke-width:1.8"/></svg></div></div><p class="wd-cap">macOS-Schreibtisch: dieselben S- und M-Widgets.</p></div>
<div><div class="wd-vision"><div class="win"><div style="font-size:10px;font-weight:700;text-transform:uppercase;color:#5a6577">Allokation und Drift</div>${['Aktien Welt +1,2', 'Aktien Europa −4,0', 'Anleihen −0,1', 'Krypto +3,6', 'Cash −0,7'].map((r) => `<div style="display:flex;justify-content:space-between;border-bottom:1px solid rgb(0 0 0 / .08);padding:3px 0"><span>${r.split(/ [+−]/)[0]}</span><b style="color:#0e141b">${r.match(/[+−].*/)[0]}</b></div>`).join('')}</div></div><p class="wd-cap">visionOS: ein Widget als Fenster an der Wand, etwa die Drift-Tabelle.</p></div>
</div>
<p class="mock-note" style="margin-top:14px"><b>Was das technisch heißt:</b> Ein natives Widget holt sich bei jeder Aktualisierung seine API-Antwort mit eigenem Token, ganz wie ein Agent. Push-Nachrichten an externe Geräte sind gesperrt (B3.7), werden dafür aber nicht gebraucht. Erreichbar ist die Instanz, wo sie heute erreichbar ist (Heimnetz, VPN, eigener Proxy). Die Apps lägen in einem eigenen Repository und lesen nur die API.</p></section>`);
}

const boards = { '01-widget': board01, '02-navigation': board02, '03-dashboard': board03, '04-devices': board04 };
for (const [name, fn] of Object.entries(boards)) {
  fs.writeFileSync(path.join(__dirname, name + '.html'), fn());
  console.log('wrote ' + name + '.html');
}
