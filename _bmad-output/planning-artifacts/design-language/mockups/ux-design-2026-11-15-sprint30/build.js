// Sprint 30 planning boards, drawn on 2026-11-15 before any code:
//
//   01 where the Total chart's axis starts (idea I43): the mark, the switch,
//      or both;
//   02 the polish list „Polish: Wealth“ (#1366), before and after for each
//      line whose fix changes the picture;
//   03 the app ships Inter (#1221): three surfaces in DejaVu Sans, what a
//      device without Inter draws today, and in the shipped variable font.
//   04 „Tops und Flops“ per period (idea I32, FR-59, ADR-0061): the card on
//      the Overview (A) or a block on Vermögen › Performance (B), from
//      capture-d.js's fragments.
//
// Every "today" frame is the review instance's own markup, captured by
// capture.js on the synthetic review seed (captured/*.html); every "after"
// frame is that markup edited by hand here, and what does not exist yet is
// in the frame's <style id="proposal"> or marked `mock-new`. The charts are
// the captured SVG, re-drawn by the app's own rules where a frame changes
// their axis (security_chart.ex, stacked_chart.ex). Every name and figure is
// the seed's, or invented where a frame says so; no instance data, name or
// machine detail appears.
//
// Usage:
//   node capture.js   # optional: re-captures (review instance on :4013)
//   node capture-d.js # optional: board 04's fragments (same instance)
//   node build.js     # writes frames/* and the four boards
//   node render.js    # measures the frames, rebuilds, renders the PNGs
const fs = require('fs');
const path = require('path');

const DIR = __dirname;
const FRAMES = path.join(DIR, 'frames');
fs.mkdirSync(FRAMES, { recursive: true });
const CSS_FROM_FRAME = '../../../../../../priv/static/app.css';
const CSS_FROM_BOARD = '../../../../../priv/static/app.css';
const cap = (f) => fs.readFileSync(path.join(DIR, 'captured', f), 'utf8');
const json = (f, fallback) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { return fallback; } };
const CAPTURED = json(path.join(DIR, 'captured', 'measures.json'), {});
const SIZES = json(path.join(FRAMES, 'sizes.json'), {});
const PROBES = json(path.join(FRAMES, 'probes.json'), {});
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

// One replacement that must happen exactly once, so a re-capture whose
// markup moved fails here instead of drawing a frame without its change.
function swap(s, from, to) {
  const i = typeof from === 'string' ? s.indexOf(from) : s.search(from);
  if (i < 0) throw new Error('not found: ' + String(from).slice(0, 80));
  return s.replace(from, to);
}

const nf0 = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const deNum = (t) => Number(t.trim().replace(/%$/, '').replace(/−/g, '-').replace(/\./g, '').replace(',', '.'));

// ---------------------------------------------------------------------------
// Frames and boards (Sprint 29's writer and layout)

const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.app-frame { padding-left: 0 !important; min-height: 0 !important; }
.app-shell, .app-main, .app-main--workspace, .workspace-page { min-height: 0 !important; }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: 2px; border-radius: 8px; }
.mock-crop { margin: 0; padding: 8px 12px; border: 1px dashed var(--color-border-strong); border-radius: var(--radius-md); font-size: 12px; color: var(--color-text-muted); }
`;
const BREAK_BEFORE = /><(?=\/?(?:path|g|svg|line|text|tr|td|th|thead|tbody|table|div|section|figure|nav|header|form|select|label|button|a |p |p>|h[1-6]|li|ul|ol|details|summary|span class="control-bar__group))/g;

// A frame drawn for a 1200 px window is 980 px wide (the window less the
// 220 px menu); the section's padding reads 2.4vw, so it is pinned to the
// 28 px it has at 1200 px.
const AT_1200 = '.workspace-section { padding: 28px; }';
function writeFrame(name, body, { css = '', width = 980, privacy = false } = {}) {
  if (width === 980) css = AT_1200 + css;
  const doc = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet"${privacy ? ' data-privacy="on" data-privacy-label="verborgen"' : ''}>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${name}</title>
<link rel="stylesheet" href="${CSS_FROM_FRAME}">
<style id="frame">${FRAME_CSS}</style>
<style id="proposal">${css}</style>
</head>
<body>${body.replace(BREAK_BEFORE, '>\n<')}</body>
</html>
`;
  fs.writeFileSync(path.join(FRAMES, name + '.html'), doc.replace(/[ \t]+$/gm, '').replace(/\n{3,}/g, '\n\n'));
  return { file: name + '.html', width, height: SIZES[name + '.html'] || 600 };
}
const tagged = (f, tag) => ({ ...f, tag });
const probe = (f) => PROBES[f.file] || {};

const BOARD_CSS = (cols) => `
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: ${cols}px; margin: 0 auto 28px; }
.mock-head h1 { margin: 0 0 6px; font-size: 22px; }
.mock-board > h2 { margin: 0 0 4px; font-size: 17px; font-weight: 760; }
.mock-board > h2 small { font-size: 12px; font-weight: 700; color: var(--color-accent); background: var(--color-accent-soft); padding: 2px 8px; border-radius: 999px; margin-left: 6px; vertical-align: 2px; }
p.mock-note { margin: 0 0 12px; max-width: 150ch; font-size: 13px; color: var(--color-text-muted); line-height: 1.5; }
.mock-pickbar { margin: 0 0 16px; padding: 12px 16px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 13px; line-height: 1.55; max-width: 150ch; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-pickbar ul { margin: 4px 0 6px; padding-left: 20px; }
.mock-head p { max-width: 150ch; font-size: 13px; line-height: 1.55; }
.mock-head table { width: auto; border-collapse: collapse; margin: 6px 0 10px; font-size: 12.5px; }
.mock-head th, .mock-head td { padding: 3px 16px 3px 0; text-align: left; border-bottom: 1px solid var(--color-border); }
.mock-head td.n { text-align: right; font-variant-numeric: tabular-nums; }
.mock-row { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
.mock-fig { margin: 0; }
.mock-tag { display: block; max-width: 980px; margin: 0 0 6px; font-size: 12px; font-weight: 600; color: var(--color-text-muted); }
.mock-tag b { display: inline-block; margin-right: 6px; padding: 1px 9px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; background: var(--color-bg-muted); color: var(--color-text-muted); }
.mock-frame { width: max-content; border: 1px solid var(--color-border-strong); border-radius: 10px; overflow: hidden; box-shadow: var(--shadow-panel); background: var(--color-bg); }
.mock-frame iframe { display: block; border: 0; }
`;
// A tag reads "KIND · text": the kind in a pill (Heute, A, B, C), then the line.
function tagHtml(t) {
  if (!t) return '';
  const [kind, ...rest] = t.split(' · ');
  return `<span class="mock-tag"><b>${kind}</b>${rest.join(' · ')}</span>`;
}
function board(file, title, cols, intro, sections) {
  const sec = sections.map((s) => `
<section class="mock-board">${s.lead ? `
  <div class="mock-pickbar">${s.lead}</div>` : ''}
  <h2>${s.title}${s.recommended ? ' <small>empfohlen</small>' : ''}${s.option ? ' <small>Option</small>' : ''}</h2>
  <p class="mock-note">${s.note}</p>
  <div class="mock-row">${s.frames.map((f) => `<figure class="mock-fig" style="max-width: ${f.width + 2}px">${tagHtml(f.tag)}<div class="mock-frame"><iframe src="frames/${f.file}" width="${f.width}" height="${f.height}" title="${f.file}"></iframe></div></figure>`).join('')}</div>
</section>`).join('\n');
  fs.writeFileSync(path.join(DIR, file), `<!doctype html>
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
`);
}

// ---------------------------------------------------------------------------
// The shared line chart (security_chart.ex): viewBox 960 x 320, the plot
// 56..936 x 16..292, the axis the window's min..max padded by 5 % in five
// even steps.

const PL = 56, PR = 936, PT = 16, PB = 292;
function lineChart(html) {
  const pts = html.match(/<polyline class="quote-line"[^>]*points="([^"]+)"/)[1].trim().split(/\s+/).map((p) => p.split(',').map(Number));
  const ticks = [...html.matchAll(/<text class="chart-axis-y[^"]*"[^>]*y="([\d.]+)"[^>]*>\s*([^<]+?)\s*<\/text>/g)].map((m) => ({ y: Number(m[1]), label: m[2], v: deNum(m[2]) }));
  const yMin = ticks[0].v, yMax = ticks[ticks.length - 1].v;
  const values = pts.map(([, y]) => yMin + (PB - y) / (PB - PT) * (yMax - yMin));
  const upx = Number((html.match(/--chart-upx: ([\d.]+)/) || [0, 1])[1]);
  return { pts, ticks, yMin, yMax, values, upx };
}
// The stacked chart's round step: 1, 2, 2.5 or 5 times a power of ten.
function roundStep(raw) {
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  return [1, 2, 2.5, 5, 10].find((m) => m * mag >= raw) * mag;
}
const tickLabel = (v) => (v === 0 ? '0' : nf0.format(v)).replace('-', '−');
function labelsSvg(ticks, x = PL - 6, topLimit = 12) {
  return ticks.map(({ v, y }) => `<text class="chart-axis-y ${y - PT < topLimit ? 'is-top' : ''}" x="${x}" y="${y.toFixed(2)}" text-anchor="end" dominant-baseline="central">${tickLabel(v)}</text>`).join('');
}
function gridSvg(ticks, x0 = PL) {
  return ticks.map(({ y }) => `<line x1="${x0}" y1="${y.toFixed(2)}" x2="${PR}" y2="${y.toFixed(2)}"></line>`).join('');
}

// „ab 0“ (proposal B and C): the line drawn on the stack's axis, from 0 to
// the window's highest value plus 5 %, in its round steps, so the line
// reads like the stack's top edge.
function fromZero(html) {
  const c = lineChart(html);
  const top = Math.max(...c.values);
  const hi = top * 1.05;
  const step = roundStep(hi / 5);
  const ticks = [];
  for (let k = 0; k * step <= hi + 1e-9; k++) ticks.push({ v: k * step, y: PB - (PB - PT) * (k * step) / hi });
  const y = (v) => PB - (PB - PT) * v / hi;
  const pts = c.pts.map(([x], i) => [x, y(c.values[i])]);
  const f = (n) => n.toFixed(2);
  const area = `M${f(pts[0][0])},${f(pts[0][1])} ` + pts.map(([x, yy]) => `L${f(x)},${f(yy)}`).join(' ') + ` L${f(pts[pts.length - 1][0])},${PB}.0 L${f(pts[0][0])},${PB}.0 Z`;
  let out = html;
  out = swap(out, /(<g class="chart-axes"[^>]*>)[\s\S]*?(<\/g>)/, `$1${gridSvg(ticks)}$2`);
  out = swap(out, /<path class="quote-area" d="[^"]*"/, `<path class="quote-area" d="${area}"`);
  out = swap(out, /(<polyline class="quote-line"[^>]*points=")[^"]*"/, `$1${pts.map(([x, yy]) => `${f(x)},${f(yy)}`).join(' ')}"`);
  out = swap(out, /(<g class="chart-axis-labels">)\s*(?:<text class="chart-axis-y[\s\S]*?<\/text>\s*)+/, `$1${labelsSvg(ticks)}`);
  return { html: out, step, hi, ticks, top };
}

// The axis break (proposal A and C): a small double zigzag on the bottom
// grid line where the plot begins, over a patch of the frame's colour, so
// the line reads broken at the axis' foot; sized in CSS pixels through the
// chart's own --chart-upx, 14 px wide at every width; aria-hidden, the
// chart's label says it in words. The lowest value keeps its place beside
// it. Where the values stand inside the plot (J5 A, rule ③), the gutter is
// empty and the dates touch the bottom line, so the mark moves into the
// gutter, its right edge on the plot's edge.
function breakMark(html, lowest, unit = '') {
  const c = lineChart(html);
  const mark = `<g class="chart-axis-break" transform="translate(${(PL + 8 * c.upx).toFixed(2)} ${PB}) scale(${c.upx})" aria-hidden="true"><rect x="-7.5" y="-6.5" width="15" height="13" rx="2"></rect><path d="M-6.5,-1 l3.25,-2.8 l3.25,2.8 l3.25,-2.8 l3.25,2.8 M-6.5,4.4 l3.25,-2.8 l3.25,2.8 l3.25,-2.8 l3.25,2.8"></path></g>`;
  let out = swap(html, '<g class="chart-axis-labels">', mark + '<g class="chart-axis-labels">');
  out = swap(out, /aria-label="(Wert im Zeitverlauf|Kurschart)"/, `aria-label="$1 · Achse ab ${lowest}${unit}, nicht ab 0"`);
  return out;
}
const MARK_CSS = `
/* I43 A: the axis break, the frame's colour under two zigzags in the muted ink. */
.chart-axis-break rect { fill: var(--color-bg); }
.chart-axis-break path { fill: none; stroke: var(--color-text-muted); stroke-width: 1.4; stroke-linecap: round; stroke-linejoin: round; }
.chart-frame[data-axis-inside] .chart-axis-break { transform: translate(calc(56px - 8px * var(--chart-upx, 1)), 292px) scale(var(--chart-upx, 1)); }
`;

// The switch „Achse: Ausschnitt · ab 0“ as one more group of the shared
// control bar, after „Ebene“, on Gesamt in „Wert“ only.
function axisGroup(active) {
  const opt = (key, label, href) => `<a href="${href}" class="segmented-control__option${active === key ? ' is-active' : ''}"${active === key ? ' aria-current="true"' : ''} data-axis="${key}">${label}</a>`;
  return `<span class="control-bar__group mock-new"><span class="control-bar__label" id="stack-axis-label">Achse</span><div class="segmented-control" data-role="stack-axis" role="group" aria-labelledby="stack-axis-label">${opt('window', 'Ausschnitt', '/portfolio?level=total')}${opt('zero', 'ab 0', '/portfolio?level=total&amp;axis=zero')}</div></span>`;
}
function withSwitch(html, active) {
  const i = html.indexOf('data-role="stack-bar"');
  const j = html.indexOf('</span>\n  </div>\n</div>', i);
  if (i < 0 || j < 0) throw new Error('stack bar not found');
  const k = j + '</span>'.length;
  let out = html.slice(0, k) + axisGroup(active) + html.slice(k);
  if (active === 'zero') out = out.replace(/href="\/portfolio\?level=(category|security)"/g, 'href="/portfolio?level=$1"');
  return out;
}

// ===========================================================================
// Board 01 — I43: where the Total chart's axis starts

const B1 = {};
const TOTAL = cap('perf-total-1200.html');
const CATEGORY = cap('perf-category-1200.html');
const TOTAL_390 = cap('perf-total-390.html');
const PRIVACY_390 = cap('perf-total-privacy-390.html');
const SECURITY = cap('security-chart-1200.html');
const totalLine = lineChart(TOTAL);
const zero = fromZero(TOTAL);
const lowTotal = totalLine.ticks[0].label;
const W1200 = 980;

B1.total = tagged(writeFrame('01a-gesamt-heute', TOTAL, {}), 'Heute · Gesamt, Wert (EUR), 1J: die Achse von ' + lowTotal + ' bis ' + totalLine.ticks[4].label);
B1.category = tagged(writeFrame('01b-kategorien-heute', CATEGORY, {}), 'Heute · Kategorien, dasselbe Fenster: der Stapel ab 0, Schritte zu 20.000');
B1.markA = tagged(writeFrame('01c-a-markierung', breakMark(TOTAL, lowTotal), { css: MARK_CSS }), 'A · nur die Markierung: ≈ am Fuß der Achse, der unterste Wert bleibt');
B1.switchB = tagged(writeFrame('01d-b-ausschnitt', withSwitch(TOTAL, 'window'), {}), 'B · Schalter auf „Ausschnitt“ (Standard): das Bild von heute');
B1.zeroB = tagged(writeFrame('01e-b-ab-0', withSwitch(zero.html, 'zero'), {}), 'B · Schalter auf „ab 0“ (axis=zero): die Linie liest wie die Oberkante des Stapels');
B1.windowC = tagged(writeFrame('01f-c-ausschnitt', withSwitch(breakMark(TOTAL, lowTotal), 'window'), { css: MARK_CSS }), 'C · „Ausschnitt“ mit der Markierung: Standard, das Bild von heute plus ≈');
B1.zeroC = tagged(writeFrame('01g-c-ab-0', withSwitch(zero.html, 'zero'), {}), 'C · „ab 0“: die Achse beginnt bei 0, keine Markierung');
const secLine = lineChart(SECURITY);
B1.securityC = tagged(writeFrame('01h-c-kurschart', breakMark(SECURITY, secLine.ticks[0].label), { width: 954, css: MARK_CSS }), 'C · Kurschart (Diagramm, 1J): nur die Markierung, kein Schalter');
const total390 = lineChart(TOTAL_390);
const zero390 = fromZero(TOTAL_390);
B1.window390 = tagged(writeFrame('01i-c-390-ausschnitt', withSwitch(breakMark(TOTAL_390, total390.ticks[0].label), 'window'), { width: 390, css: MARK_CSS }), 'C · 390 px, „Ausschnitt“');
B1.zero390 = tagged(writeFrame('01j-c-390-ab-0', withSwitch(zero390.html, 'zero'), { width: 390 }), 'C · 390 px, „ab 0“');
const priv = lineChart(PRIVACY_390);
B1.privacy = tagged(writeFrame('01k-c-privat-390', breakMark(PRIVACY_390, priv.ticks[0].label, ''), { width: 390, css: MARK_CSS, privacy: true }), 'C · Privatsphäre-Modus, 390 px: Prozentachse, kein Schalter');

// The figures the notes quote, computed from the captured line.
const tv = totalLine.values;
const firstV = tv[0], lastV = tv[tv.length - 1], minV = Math.min(...tv), maxV = Math.max(...tv);
const shareGesamt = (maxV - minV) / (totalLine.yMax - totalLine.yMin);
const shareStack = (maxV - minV) / zero.hi;
const pctOf = (x) => nf0.format(Math.round(x * 100)) + ' %';

const I43_LEAD = `<p><strong>Entschieden</strong> (DESIGN.md, Amendment 2026-11-07, Anatomie 1 und 2): bei „Gesamt“ ohne Filter ist der Chart unter der Leiste der heutige Wertchart, Byte für Byte, die Achse vom kleinsten bis zum größten Wert des Fensters (plus 5 %) in fünf gleichen Schritten (<code>security_chart.ex</code>); der Stapel bei „Kategorien“ und „Wertpapiere“ beginnt bei 0 und liest in runden Schritten (<code>stacked_chart.ex</code>, <code>round_ticks</code>, Sprint 28 D2); die Reihe „% (TTWROR)“ hat ihre Nulllinie. Idee I43 ist triagiert (<code>ideas.md</code>): der Stapel wird nicht über 0 abgeschnitten, sonst lesen seine Flächen nicht mehr als Anteile; offen sind Schalter oder Markierung und ob der Kurschart sie trägt.</p>
<p><strong>Was dieses Board vorschlägt (C, empfohlen):</strong> auf „Gesamt“ in „Wert“ ein Schalter <b>Achse: Ausschnitt · ab 0</b> in der Leiste nach „Ebene“ (die Regel „labelled controls start on one edge“ gilt, die Gruppe ist eine mehr auf <code>ControlBar.bar/1</code>), und die Markierung ≈ überall, wo eine Achse in einem Betrag nicht bei 0 beginnt; der Kurschart eines Wertpapiers bekommt nur die Markierung. Der Standard bleibt <b>„Ausschnitt“</b>: das Bild von heute Byte für Byte plus die Markierung. Die Wahl steht in der Adresse wie die Ebene, <code>axis=zero</code> nur wenn nicht Standard, nach <code>level</code> und vor dem Zeitraum; die Links der Leiste und der Zeitraum behalten sie. „ab 0“ zeichnet die Linie auf der Achse des Stapels: von 0 bis zum Höchstwert plus 5 %, in dessen runden Schritten, „0“ als Wert. Der Satz „byte for byte“ im Amendment 2026-11-07 wird mit der Story geändert.</p>
<p><strong>Umkehrbar per Kommentar:</strong> „I43 nur Markierung“ (A), „I43 nur Schalter“ (B), „I43 Standard ab 0“ (C, aber „ab 0“ als Standard, <code>axis=window</code> für den Ausschnitt).</p>`;

board('01-axis-start.html', 'Sprint 30 · I43 — wo die Achse des Gesamt-Charts beginnt', 2010, I43_LEAD, [
  { title: '① Heute: dasselbe Fenster bei „Gesamt“ und bei „Kategorien“', note: `Vermögen › Bestände › Performance, „Wert (EUR)“, 1J, Ansicht Alles, bei 1200 px (Abschnitt 980 px, Diagramm 924 px; die Tabelle „Beitrag je Position“, „Daten als Tabelle“ und der benutzerdefinierte Zeitraum ausgelassen). Der Wert bewegt sich im Fenster zwischen ${nf0.format(minV)} und ${nf0.format(maxV)} (Beginn ${nf0.format(firstV)}, Ende ${nf0.format(lastV)}). Links füllt diese Spanne ${pctOf(shareGesamt)} der Höhe, weil die Achse bei ${lowTotal} beginnt; rechts bewegt sich die Oberkante des Stapels um ${pctOf(shareStack)} der Höhe. Dasselbe Fenster liest links wie ein Steilhang, rechts wie eine Delle; nichts auf der linken Seite sagt, dass die Achse nicht bei 0 beginnt.`, frames: [B1.total, B1.category] },
  { title: '② A — nur die Markierung', note: 'Wo die Achse in einem Betrag nicht bei 0 beginnt, unterbricht am Fuß der Achse eine kleine doppelte Zickzacklinie ≈ die unterste Gitterlinie, wo der Plot beginnt (15 px breit bei jeder Breite, auf einem Fleck in der Farbe des Rahmens, in der gedämpften Schrift); der unterste Wert bleibt stehen, sonst ändert sich nichts. Stehen die Werte im Plot (unter 760 px, J5 A ③), ist der Rand links leer und die Daten stehen dicht unter der Linie: dort sitzt die Markierung im Rand, ihre rechte Kante auf der Kante des Plots (⑤). Das Label des Diagramms sagt es in Worten („Wert im Zeitverlauf · Achse ab 76.033, nicht ab 0“). Billig und ehrlich, aber die Frage „wie sähe es ab 0 aus“ bleibt unbeantwortet: man muss die Kategorien öffnen.', frames: [B1.markA] },
  { title: '③ B — nur der Schalter', note: `Eine Gruppe „Achse“ mit „Ausschnitt · ab 0“ in der Leiste, nach „Ebene“, nur bei „Gesamt“ ohne Filter in „Wert“. In „% (TTWROR)“ fehlt sie (die Reihe hat ihre Nulllinie, eine Rendite ist kein Betrag), ebenso im Privatsphäre-Modus, dessen Achse in Prozent des Fensterbeginns liest. „ab 0“: Achse 0 bis ${nf0.format(Math.round(zero.hi))} (Höchstwert ${nf0.format(Math.round(zero.top))} plus 5 %), Schritte zu ${nf0.format(zero.step)} wie im Stapel nebenan, die Linie damit auf Höhe seiner Oberkante. Ohne Markierung bleibt der Ausschnitt so stumm wie heute.`, frames: [B1.switchB, B1.zeroB] },
  { title: '④ C — der Schalter auf „Gesamt“ und die Markierung überall', recommended: true, note: 'B auf Vermögens „Gesamt“, dazu A, sobald eine Achse in einem Betrag nicht bei 0 beginnt: im Ausschnitt (Standard) und auf dem Kurschart eines Wertpapiers. „ab 0“ beginnt bei 0 und trägt keine Markierung. Der Kurschart bekommt keinen Schalter: ein Kurs ab 0 zeigt bei einem Wertpapier selten etwas, und seine Achse fällt seit Board 07 ⑨ nie unter 0 (<code>price_axis?</code>, <code>axis_floor/4</code>); die logarithmische Skala trägt die Markierung nicht (sie hat keine 0). Gebaut im geteilten Chart als eine Option (<code>axis_break?</code>), wahr, wenn <code>y_min</code> über 0 liegt und die Achse einen Betrag liest; der Schalter in <code>StackedChart.bar/1</code> und <code>portfolio_live.ex</code> (<code>axis=zero</code> wie <code>level</code>).', frames: [B1.windowC, B1.zeroC, B1.securityC] },
  { title: '⑤ C bei 390 px', recommended: true, note: 'Die Leiste fällt unter ihrem Boden 380 auf „Label über dem Steuerelement“ (Amendment 2026-11-08, B): „Ebene“ und „Achse“ stehen über ihren Steuerelementen, beide an der linken Kante; kein Steuerelement beginnt nach seinem Label. Die Werte stehen bei dieser Breite im Plot (J5 A, Regel ③), die Markierung sitzt dann links unten im leeren Rand, ihre rechte Kante auf der Kante des Plots. Die Leiste misst die Story in Inter und DejaVu Sans (<code>control_bar.js</code>), Falz 780 und Boden 380 bleiben, wenn die Zeile mit „Achse“ in beiden Schriften darunter bleibt.', frames: [B1.window390, B1.zero390] },
  { title: '⑥ C im Privatsphäre-Modus', recommended: true, note: 'Die Achse liest in Prozent des Werts am Fensterbeginn (Board 02 von Sprint 26); ihre 0 eines Betrags wäre −100 %. Der Schalter fehlt: im Modus liest die Achse in Prozent, „ab 0“ hieße dort −100 %. Die Markierung bleibt, weil die Achse ebenso nicht beim Betrag 0 beginnt. Ein kleiner Rahmen, 390 px.', frames: [B1.privacy] },
]);

// ===========================================================================
// Board 02 — „Polish: Wealth“ (#1366)

const B2 = {};
const POSITIONS = cap('positions-1200.html');

// ① The positions table keeps all its rows, so its columns keep the widths
// the page gives them; the board shows the six with a note (`mock-keep`),
// the others collapsed out of the picture but not out of the column widths.
const KEEP_SIX = '#holdings-positions-table tbody tr:not(.mock-keep) { visibility: collapse; }';
// A: the note's first phrase never breaks; the note stays under its figure,
// right-aligned, and may reach 9rem left past its column, into the empty
// space under its neighbour's figure (no row carries notes in two adjacent
// cells), so it adds no width to the column. The depot never breaks, an
// ellipsis past 7rem, the whole name in its title; the name column's floor
// drops from 12rem to 9.5rem to make the room.
const noteLead = (html) => html.replace(/<small class="cell-note">\s*([^<·]+?) · ([^<]+?)\s*<\/small>/g, '<small class="cell-note"><span class="cell-note__lead">$1</span> · $2</small>');
const depotCell = (html) => html.replace(/<td data-column="depot">\s*([^<]+?)\s*<\/td>/g, '<td data-column="depot"><span class="cell-depot" title="$1">$1</span></td>');
const DEPOT_CSS = `
#holdings-positions-table td[data-column="depot"] { white-space: nowrap; }
.cell-depot { display: block; max-width: 7rem; overflow: hidden; text-overflow: ellipsis; }
#holdings-positions-table th.cell-name { min-width: 9.5rem; }
`;
const POS_A_CSS = KEEP_SIX + `
.cell-note__lead { white-space: nowrap; }
#holdings-positions-table td.num .cell-note { display: block; margin-left: -9rem; }
` + DEPOT_CSS;
B2.posBefore = tagged(writeFrame('02a-positionen-heute', POSITIONS, { css: KEEP_SIX }), 'Heute · Positionen, acht Spalten, die sechs Zeilen mit Notiz');
B2.posA = tagged(writeFrame('02b-positionen-a', depotCell(noteLead(POSITIONS)), { css: POS_A_CSS }), 'A · erste Wendung ungebrochen, Notiz bis 9rem nach links; Depot einzeilig');
// B: the note behind an ⓘ at the figure, its words in the popover; the
// depot as in A.
const POS_B_CSS = KEEP_SIX + `
#holdings-positions-table td.num .metric-tooltip { margin-left: 4px; vertical-align: 1px; }
` + DEPOT_CSS;
const noteTip = (html) => {
  return html.replace(/\s*<small class="cell-note">\s*([^<]+?)\s*<\/small>/g, (_, text) => `<details class="metric-tooltip metric-tooltip--inline mock-new"><summary aria-label="Zu diesem Wert">ⓘ</summary><p role="tooltip">${text}</p></details>`);
};
B2.posB = tagged(writeFrame('02c-positionen-b', depotCell(noteTip(POSITIONS)), { css: POS_B_CSS }), 'B · die Notiz hinter einem ⓘ an der Zahl');

// ② and ③: the stacked chart (stacked_chart.ex), re-drawn from the captured
// bands: each band's daily values read back from its edges, then stacked by
// the app's rules (zero_first, the diverging stack, range, round_ticks).
function stackModel(html) {
  const svg = html.match(/<svg class="stack-chart"[\s\S]*?<\/svg>/)[0];
  const lines = [...svg.matchAll(/<line x1="56" y1="([\d.]+)"/g)].map((m) => Number(m[1]));
  const labels = [...svg.matchAll(/<text class="chart-axis-y[^"]*"[^>]*y="([\d.]+)"[^>]*>\s*([^<]+?)\s*<\/text>/g)].map((m) => ({ y: Number(m[1]), v: deNum(m[2]) }));
  const [a, b] = [labels[0], labels[1]];
  const per = (a.y - b.y) / (b.v - a.v);
  const lo = a.v - (PB - a.y) / per;
  const valueAt = (y) => lo + (PB - y) / per;
  const bands = [...svg.matchAll(/<path class="(stack-band[^"]*)" d="([^"]+)" fill="([^"]+)" data-band="([^"]+)"(?: data-part="negative")?>\s*<title>([^<]*)<\/title>\s*<\/path>/g)].map((m) => {
    const coords = m[2].replace(/[MZ]/g, '').trim().split(/\s*L\s*/).map((p) => p.split(',').map(Number));
    const n = coords.length / 2;
    const upper = coords.slice(0, n), lower = coords.slice(n).reverse();
    return { cls: m[1], fill: m[3], key: m[4], title: m[5], xs: upper.map(([x]) => x), values: upper.map(([, y], i) => valueAt(y) - valueAt(lower[i][1])) };
  });
  return { svg, bands, lines };
}
function stackSvg(model, { gutter = PL, tickBelow = false, hoverKey = null } = {}) {
  const n = model.bands[0].values.length;
  const changes = (b) => b.values.some((v) => v > 0.5) && b.values.some((v) => v < -0.5);
  const order = [...model.bands.filter(changes), ...model.bands.filter((b) => !changes(b))];
  let pos = new Array(n).fill(0), neg = new Array(n).fill(0);
  const parts = [];
  for (const b of order) {
    const up = b.values.map((v) => Math.max(v, 0)), down = b.values.map((v) => Math.min(v, 0));
    const posAfter = pos.map((p, i) => p + up[i]), negAfter = neg.map((q, i) => q + down[i]);
    const positive = { b, part: 'positive', edges: pos.map((p, i) => [p, posAfter[i]]) };
    const negative = { b, part: 'negative', edges: negAfter.map((q, i) => [q, neg[i]]) };
    if (b.values.every((v) => v >= 0)) parts.push(positive);
    else if (b.values.every((v) => v <= 0)) parts.push(negative);
    else parts.push(positive, negative);
    pos = posAfter; neg = negAfter;
  }
  const edges = parts.flatMap((p) => p.edges);
  let lo = Math.min(0, ...edges.map((e) => e[0]));
  const top = Math.max(0, ...edges.map((e) => e[1]));
  let hi = top === lo ? lo + 1 : top + (top - lo) * 0.05;
  let step = roundStep((hi - lo) / 5);
  // #1366 line 13 (proposal): one round step below zero whenever a band
  // dips under it, so the depth reads against a labelled tick.
  if (tickBelow && lo < 0) lo = step * Math.floor(lo / step + 1e-9);
  const x = (i) => gutter + (PR - gutter) * i / (n - 1);
  const y = (v) => PB - (PB - PT) * (v - lo) / (hi - lo);
  const ticks = [];
  for (let k = Math.ceil(lo / step - 1e-9); k <= Math.floor(hi / step + 1e-9); k++) ticks.push({ v: k * step, y: y(k * step) });
  const f = (v) => v.toFixed(2);
  const path = (p) => 'M' + [...p.edges.map((e, i) => [x(i), y(e[1])]), ...p.edges.map((e, i) => [x(i), y(e[0])]).reverse()].map(([xx, yy]) => `${f(xx)},${f(yy)}`).join(' L') + ' Z';
  const bandsSvg = parts.map((p) => `<path class="${p.b.cls}${p.part === 'negative' ? ' stack-band--negative' : ''}" d="${path(p)}" fill="${p.b.fill}" data-band="${p.b.key}"${p.part === 'negative' ? ' data-part="negative"' : ''}><title>${p.b.title}</title></path>`).join('');
  const zeroLine = lo < 0 ? `<line class="chart-zeroline" x1="${gutter}" y1="${f(y(0))}" x2="${PR}" y2="${f(y(0))}"></line>` : '';
  const svg = `<svg class="stack-chart" role="img" aria-label="Wert je Kategorie im Zeitverlauf" viewBox="0 0 960 320" preserveAspectRatio="xMidYMid meet" width="100%" data-points="${n}" data-plot-top="16.00"><g class="chart-axes" stroke="currentColor" stroke-opacity="0.15">${gridSvg(ticks, gutter)}</g>${bandsSvg}${zeroLine}<g class="chart-axis-labels">${labelsSvg(ticks, gutter - 6)}<text class="chart-axis-x" x="${gutter}" y="314" text-anchor="start">15.11.2025</text><text class="chart-axis-x" x="936" y="314" text-anchor="end">15.11.2026</text></g></svg>`;
  return { svg, ticks, lo, hi, step, order: order.map((b) => b.key) };
}
const stack = stackModel(CATEGORY);
const withSvg = (html, svg) => html.replace(/<svg class="stack-chart"[\s\S]*?<\/svg>/, svg);

// ② The gutter: 88 viewBox units instead of 56, the values outside the plot.
const GUTTER = 88;
const outside = (html) => swap(html, '<div class="stack-figure__chart" id="stack-figure-chart" data-axis-inside=""', '<div class="stack-figure__chart mock-new" id="stack-figure-chart"');
const gutterSvg = stackSvg(stack, { gutter: GUTTER });
B2.gutterBefore = tagged(writeFrame('02d-stapel-heute', CATEGORY, {}), 'Heute · die Werte im Plot, über einem 3-px-Rand in der Farbe der Fläche');
B2.gutterAfter = tagged(writeFrame('02e-stapel-rand', outside(withSvg(CATEGORY, gutterSvg.svg)), {}), `Neu · linker Rand ${GUTTER} statt 56 Einheiten, die Werte außerhalb`);

// ③ A negative cash day shallower than one step. The seed's window has no
// such day today; the frame sets Cash to −11.865 on two days (#1366's line:
// the UAT persona's depth on #1436), everything else is the seed's.
const DIP = -11865;
const dipModel = { ...stack, bands: stack.bands.map((b) => b.key !== 'cash' ? b : { ...b, values: b.values.map((v, i) => (i === 240 || i === 241 ? DIP : v)) }) };
const dipBefore = stackSvg(dipModel);
const dipAfter = stackSvg(dipModel, { tickBelow: true });
// The legend reads like the stack, top band first: Cash, now drawn first
// at the zero line, becomes its last row (the closing act's D1).
const cashLast = (html) => {
  const row = html.match(/<tr data-band="cash"[\s\S]*?<\/tr>/)[0];
  return html.replace(row, '').replace(/(<tbody>[\s\S]*?)(\s*<\/tbody>)/, `$1${row}$2`);
};
B2.dipBefore = tagged(writeFrame('02f-stapel-minus-heute', cashLast(withSvg(CATEGORY, dipBefore.svg)), {}), `Heute · Cash ${nf0.format(DIP).replace('-', '−')} an zwei Tagen: Nulllinie, aber kein Wert unter 0`);
B2.dipAfter = tagged(writeFrame('02g-stapel-minus-neu', cashLast(withSvg(CATEGORY, dipAfter.svg.replace('<g class="chart-axis-labels">', '<g class="chart-axis-labels">'))), {}), `Neu · ein runder Schritt unter 0: ${tickLabel(dipAfter.ticks[0].v)}`);

// ④ Allokation & Ziele: the TTWROR figure while a new window loads.
const KPIS = cap('kpis-allocation-1200.html');
const kpisLoading = (html) => swap(html, /(TTWROR 1J\s*)<strong class="is-positive">\s*\+8,0%\s*<\/strong>/, '$1<strong class="value-slot-pending mock-new" aria-busy="true" data-waits="performance"><span class="value-skeleton" aria-hidden="true"></span><span class="recomputing-cue"><span class="spinner"></span> wird berechnet</span></strong>').replace('data-role="kpi-summary"', 'data-role="kpi-summary" aria-busy="true"');
const KPI_CSS = '.kpi-summary .value-slot-pending { display: inline-flex; align-items: center; gap: 6px; vertical-align: middle; } .kpi-summary .value-slot-pending .value-skeleton { width: 3.2em; }';
B2.allocBefore = tagged(writeFrame('02h-allokation-heute', KPIS, {}), 'Heute · während ein neues Fenster lädt: „+8,0%“ des vorigen, ohne Zeichen');
B2.allocAfter = tagged(writeFrame('02i-allokation-neu', kpisLoading(KPIS), { css: KPI_CSS }), 'Neu · der Platzhalter der App, aria-busy, bis die Zahl landet');

// ⑤ The windows table at 390 px: rows (UX-DR27's phone rows) under 560 px.
// Two detected windows drawn by hand beside the seed's manual one (the seed
// chooses no crash benchmark, so it detects none); their figures invented.
const WINDOWS = [
  { key: 'd:1', name: 'Herbstdelle', start: '02.09.2026', trough: '29.09.2026', decline: '−12,4 %', rec: '27.10.2026', gap: '3', kind: 'detected' },
  { key: 'd:2', name: null, start: '14.03.2026', trough: '08.04.2026', decline: '−10,6 %', rec: '22.05.2026', gap: '2', kind: 'detected' },
];
const detectedRow = (w) => `<tr data-key="${w.key}" class=""><td class="${w.name ? '' : 'crash-unnamed'}">${w.name || 'ohne Namen'}</td><td>${w.start}</td><td>${w.trough}</td><td class="num is-negative">${w.decline}</td><td>${w.rec}</td><td class="num">${w.gap}</td><td><span class="badge badge--neutral">erkannt</span></td><td class="crash-actions"><button type="button" class="link-button" data-role="crash-name-open">${w.name ? 'Umbenennen' : 'Name'}</button>${w.name ? '<button type="button" class="link-button" data-role="crash-unname">Name löschen</button>' : ''}</td></tr>`;
const RULE_BENCH = '<p class="crash-rule" data-role="crash-rule"><span>Regel: Hoch → Tief ab 10 % im Schlusskurs des Crash-Benchmarks · Crash-Benchmark <b>Meridian Global Equity ETF</b> (EUR)</span><button type="button" class="link-button" data-role="crash-change-benchmark">Ändern</button><button type="button" class="button-secondary crash-rule__add" data-role="crash-add-window"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 5v14M5 12h14"></path></svg>Fenster anlegen</button></p>';
function withWindows(html) {
  let out = swap(html, /<p class="crash-rule" data-role="crash-rule">[\s\S]*?<\/p>/, RULE_BENCH);
  out = swap(out, /(<table class="data-table crash-windows-table" id="crash-windows-table">[\s\S]*?<tbody>)/, `$1${WINDOWS.map(detectedRow).join('')}`);
  out = out.replace(/Crash-Fenster · 1 manuell/, 'Crash-Fenster · 2 erkannt · 1 manuell');
  return out;
}
const phoneRow = (w) => `<li class="phone-row" data-key="${w.key}"><span class="phone-row__body"><span class="phone-row__name${w.name ? '' : ' crash-unnamed'}">${w.name || 'ohne Namen'}</span><span class="phone-row__ids">Hoch ${w.start} → Tief ${w.trough}</span><span class="crash-window-row__actions">${w.kind === 'manual' ? '<span class="badge crash-badge--manual">manuell</span><button type="button" class="link-button">Bearbeiten</button><button type="button" class="link-button">Löschen</button>' : `<span class="badge badge--neutral">erkannt</span><span class="muted">Lücke ${w.gap} T.</span><button type="button" class="link-button">${w.name ? 'Umbenennen' : 'Name'}</button>${w.name ? '<button type="button" class="link-button">Name löschen</button>' : ''}`}</span></span><span class="phone-row__figures"><span class="phone-row__figure ${w.decline ? 'is-negative' : 'muted'}">${w.decline || '—'}</span><span class="phone-row__figure2">${w.rec ? `erholt ${w.rec}` : '—'}</span></span></li>`;
const MANUAL = { key: 'm:1', name: 'Synthetic dip', start: '06.10.2026', trough: '26.10.2026', decline: null, rec: null, kind: 'manual' };
const CRASH_ROWS_CSS = `
/* #1366 line 17: under 560 px the windows table gives way to rows, the
   phone lists' pattern (UX-DR27): name over its dates, the decline over
   the kind, the actions on a third line. */
#crash-windows-phone-rows { display: none; }
@media (max-width: 560px) {
  .crash-windows .data-table-wrapper:has(#crash-windows-table) { display: none; }
  #crash-windows-phone-rows { display: block; }
}
#crash-windows-phone-rows .phone-row { grid-template-columns: minmax(0, 1fr) auto; }
.crash-window-row__actions { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 10px; margin-top: 4px; font-size: 12.5px; }
.crash-window-row__actions .link-button { font-size: 12.5px; }
`;
function windowsRows(html) {
  return swap(html, /(<table class="data-table crash-windows-table" id="crash-windows-table">[\s\S]*?<\/table>\s*<\/div>)/, `$1<ul id="crash-windows-phone-rows" class="phone-rows mock-new" aria-label="Crash-Fenster">${[...WINDOWS, MANUAL].map(phoneRow).join('')}</ul>`);
}
const CRASH_390 = withWindows(cap('crash-390.html'));
const cropCrash = (html) => html.replace(/(<section class="workspace-section crash-section"[^>]*>)[\s\S]*?(<details class="perf-table-disclosure crash-windows")/, '$1<p class="mock-crop">Kopf, Leiste, Fensterzeile und Liste wie heute; das Board lässt sie aus.</p>$2');
B2.crashBefore = tagged(writeFrame('02j-crash-fenster-390-heute', cropCrash(CRASH_390), { width: 390 }), 'Heute · 390 px: sieben Spalten, seitlich scrollend');
B2.crashAfter = tagged(writeFrame('02k-crash-fenster-390-neu', cropCrash(windowsRows(CRASH_390)), { width: 390, css: CRASH_ROWS_CSS }), 'Neu · 390 px: Zeilen unter 560 px');

// ⑥ Vermögen › Risiko without a portfolio.
const RISK_HEAD = cap('risk-head-1200.html');
const CATALOGUE = cap('crash-catalogue-1200.html');
const riskPage = (inner) => RISK_HEAD.replace(/(<\/nav>)(\s*<\/div><\/main>)/, `$1${inner}$2`);
const EMPTY = '<section class="workspace-section"><p class="empty-state" data-role="risk-empty">Noch kein Portfolio — Risiko wird über Bestände gemessen, und es gibt keine.</p></section>';
const catalogueOnly = (html) => {
  const s = html.match(/<section class="workspace-section crash-section"[\s\S]*<\/section>/)[0];
  let out = s.replace(/<span class="control-bar__group ">\s*<span class="control-bar__label" id="crash-universe-label">[\s\S]*?<\/div>\s*<\/span>/, '');
  out = swap(out, /<a href="[^"]*" class="crash-window__link"[\s\S]*?<\/a>/, '<span class="hint">Ganzer Katalog</span>');
  out = out.replace(/<span class="badge badge--neutral" data-role="crash-held">im Depot<\/span>/g, '');
  out = out.replace(/<details class="perf-table-disclosure crash-windows"[\s\S]*?<\/details>/, (d) => d.replace(' open=""', ''));
  return out.replace('class="workspace-section crash-section"', 'class="workspace-section crash-section mock-new"');
};
B2.riskBefore = tagged(writeFrame('02l-risiko-leer-heute', riskPage(EMPTY), {}), 'Heute · ohne Portfolio: nur die Leerzeile');
B2.riskAfter = tagged(writeFrame('02m-risiko-leer-neu', riskPage(EMPTY + catalogueOnly(CATALOGUE)), {}), 'Neu · die Leerzeile, darunter die Crashes über den ganzen Katalog');

// ⑦ „Namen ohne Fenster“: the hint says why, and the table fits its wrapper.
// Three names drawn by hand (the seed has none): one given for the current
// crash benchmark whose window the closes no longer start, two for another.
const UNMATCHED = [
  { key: 'n:1', name: 'Zinsschock', bench: 'Meridian Global Equity ETF', current: true, start: '05.02.2026' },
  { key: 'n:2', name: 'Ölpreisdelle', bench: 'Vanguard FTSE All-World UCITS ETF USD Acc', current: false, start: '11.06.2025' },
  { key: 'n:3', name: 'Sommerflaute', bench: 'Vanguard FTSE All-World UCITS ETF USD Acc', current: false, start: '21.07.2025' },
];
const unmatchedRow = (u, suffix) => `<tr data-key="${u.key}"><td>${u.name}</td><td>${u.bench}${!u.current && suffix ? '<span class="muted"> · kehrt zurück, wenn er wieder Crash-Benchmark ist</span>' : ''}</td><td>${u.start}</td><td class="crash-actions"><button type="button" class="link-button" data-role="crash-from-name-open">Als manuelles Fenster anlegen …</button><button type="button" class="link-button" data-role="crash-unname">Löschen</button></td></tr>`;
const unmatchedTable = (rows, suffix) => `<div class="data-table-wrapper"><table class="data-table crash-windows-table"><thead><tr><th>Name</th><th>Gegeben für</th><th>Hoch</th><th><span class="sr-only">Aktionen</span></th></tr></thead><tbody>${rows.map((u) => unmatchedRow(u, suffix)).join('')}</tbody></table></div>`;
const UNMATCHED_TODAY = `<div class="crash-unmatched" id="crash-unmatched"><h3>Namen ohne Fenster (3)</h3><p class="hint">Die Kurse haben sich geändert: an diesen Tagen beginnt kein erkanntes Fenster mehr. Ein Name wird nie geraten einem anderen Fenster zugeordnet.</p>${unmatchedTable(UNMATCHED, true)}</div>`;
const UNMATCHED_NEW = `<div class="crash-unmatched mock-new" id="crash-unmatched"><h3>Namen ohne Fenster (3)</h3><p class="hint" data-role="crash-unmatched-closes">1 Name: Die Kurse haben sich geändert, an diesem Tag beginnt kein erkanntes Fenster mehr. Ein Name wird nie geraten einem anderen Fenster zugeordnet.</p>${unmatchedTable(UNMATCHED.filter((u) => u.current), false)}<p class="hint" data-role="crash-unmatched-hidden">2 Namen: ausgeblendet, weil ein anderer Crash-Benchmark gewählt ist; sie kehren zurück, sobald ihr Benchmark wieder Crash-Benchmark ist.</p>${unmatchedTable(UNMATCHED.filter((u) => !u.current), false)}</div>`;
const UNMATCHED_CSS = `
/* #1366 lines 21 and 22: one table per reason, each under its own line;
   the actions may wrap inside their cell, so the table keeps to its wrapper. */
#crash-unmatched .crash-windows-table { width: 100%; }
#crash-unmatched .crash-actions { white-space: normal; }
#crash-unmatched .crash-actions .link-button { white-space: nowrap; }
#crash-unmatched .hint + .data-table-wrapper { margin-bottom: 12px; }
`;
const CRASH_1200 = withWindows(cap('crash-1200.html'));
const withUnmatched = (html, block) => swap(html, /(<\/table>\s*<\/div>)(\s*<\/div>\s*<\/details>)/, `$1${block}$2`).replace(/Crash-Fenster · 2 erkannt · 1 manuell/, 'Crash-Fenster · 2 erkannt · 1 manuell · 3 Namen ohne Fenster');
B2.namesBefore = tagged(writeFrame('02n-namen-heute', cropCrash(withUnmatched(CRASH_1200, UNMATCHED_TODAY)), {}), 'Heute · ein Satz für alle Namen; die Tabelle breiter als ihr Rahmen');
B2.namesAfter = tagged(writeFrame('02o-namen-neu', cropCrash(withUnmatched(CRASH_1200, UNMATCHED_NEW)), { css: UNMATCHED_CSS }), 'Neu · zwei Gründe, je ein Satz; die Tabellen passen in 922 px');

const pw = (f) => probe(f).tables || [];
const tableLine = (f, i = 0) => { const t = pw(f)[i]; return t ? `${t.scroll} px in ${t.client} px` : '—'; };
const rowsLine = (f) => (probe(f).rows || []).join(', ');
const posBeforeP = probe(B2.posBefore), posAP = probe(B2.posA), posBP = probe(B2.posB);
const gutterP = probe(B2.gutterAfter), gutterBeforeP = probe(B2.gutterBefore);

const POLISH_LEAD = `<p><strong>Entschieden:</strong> die Zeilen der Polish-Liste „Polish: Wealth“ (#1366) sind S3-Befunde mit ihrer Quelle; eine Story, die die Fläche berührt, behebt sie testgetrieben (ADR-0026, Amendment 2026-11-01). <strong>Was dieses Board zeigt:</strong> für jede Zeile, deren Behebung das Bild ändert, heute (vom Review-Seed erfasst) und danach (aus derselben Markup von Hand); wo eine Wahl besteht, A empfohlen. <strong>Ohne Bildänderung</strong> (kein Rahmen): der Tooltip eines angetippten Segments, der nach dem Tippen stehen bleibt (Allokation, <code>layout_view.ex</code>); <code>sync_rates</code>' Schutz auf dem Server neben <code>fx_syncing</code>; „Im Depot ansehen“ behält <code>view</code>; der Link der Notiz „kein Preis“ mit <code>holding=held</code>; das FX-Datum eines Tests, das mit dem Kalender wandert.</p><p><strong>Umkehrbar per Kommentar:</strong> „Positionen B“ (die Notiz hinter einem ⓘ statt A).</p>`;

board('02-wealth-polish.html', 'Sprint 30 · Polish: Wealth (#1366) — vorher und nachher', 2010, POLISH_LEAD, [
  { title: '① Positionen bei 1200 px: die Notiz unter der Zahl und das Depot', recommended: true, note: `Positionen mit den acht Spalten aus #1322 (Depot, Wertpapier, Stückzahl, Ø Kosten, Letzter Kurs, Marktwert, G&amp;V, G&amp;V %), die sechs Zeilen mit einer Notiz. Die übrigen 32 Zeilen sind ausgeblendet (<code>visibility: collapse</code>), die Spalten rechnen sie mit, wie auf der Seite. Heute bricht „ohne Wechselkurs · nicht in der Summe“ in der 113-px-Spalte auf vier Zeilen unter der Zahl und „Demo Depot“ in jeder Zeile auf zwei. Zeilenhöhen heute ${rowsLine(B2.posBefore)} px, Tabelle ${tableLine(B2.posBefore)}. <b>A (empfohlen):</b> die erste Wendung der Notiz bricht nie (<code>.cell-note__lead</code>: „ohne Wechselkurs“, „kein Preis“, „Handelspreis“); die Notiz steht rechtsbündig unter der Zahl und darf bis 9rem nach links über ihre Spalte reichen, in den leeren Raum unter der Zahl daneben (<code>margin-left: -9rem</code>, so macht sie die Spalte nicht breiter; keine Zeile hat Notizen in zwei benachbarten Zellen: „kein Preis“ steht im Kurs neben Ø Kosten, „ohne Wechselkurs“ im Marktwert neben einem Kurs ohne Notiz). Das Depot bleibt einzeilig, ab 7rem mit Auslassung, der ganze Name im <code>title</code>; dafür sinkt der Boden der Namensspalte von 12rem (#1322) auf 9,5rem, sonst wäre die Tabelle 956 px in 922 px. Zeilenhöhen ${rowsLine(B2.posA)} px, Tabelle ${tableLine(B2.posA)}. <b>B:</b> die Notiz hinter einem ⓘ an der Zahl (I1), das Depot wie A; Zeilenhöhen ${rowsLine(B2.posB)} px, Tabelle ${tableLine(B2.posB)}; ruhiger, aber „nicht in der Summe“ ist dann einen Klick entfernt, und ein „—“ steht ohne sichtbaren Grund.`, frames: [B2.posBefore, B2.posA, B2.posB] },
  { title: '② Der gestapelte Chart: die Werte außerhalb des Plots', note: `Bei 1200 px steht der Chart neben seiner Legende, ${gutterBeforeP.svgWidth || 560} px breit; unter 760 px setzt die geteilte Regel (J5 A, ③) die Werte in den Plot, über einen 3-px-Rand in der Farbe der Fläche, der über vollen Bändern schwer liest. Heute ist der linke Rand 56 Einheiten des viewBox, bei dieser Breite ${gutterBeforeP.gutterPx || 33} px, die Werte (${gutterBeforeP.labelWidth || 32} px für „80.000“) passen nicht davor. Neu: der linke Rand des Stapels ${GUTTER} Einheiten, bei ${gutterP.svgWidth || 560} px Breite ${gutterP.gutterPx || '—'} px; die Werte stehen außerhalb, rechtsbündig 6 Einheiten vor dem Plot (rechte Kante bei ${gutterP.labelRight || '—'} px, linke bei ${gutterP.labelLeft || '—'} px). ${GUTTER} Einheiten tragen einen Wert mit sieben Zeichen („−20.000“, „100.000“; 38 px in der Monoschrift zu 9 px) mit 4 px Luft links ab ${Math.ceil(42 * 960 / (GUTTER - 6))} px Diagrammbreite; darunter, auf dem Telefon, gilt die Regel „im Plot“ wie heute (der Hook <code>ChartScale</code> nimmt die Schwelle des Stapels aus einem Attribut). Der Gesamt-Chart behält seine 56 Einheiten: er steht nie neben einer Legende.`, frames: [B2.gutterBefore, B2.gutterAfter] },
  { title: '③ Ein Tag mit Cash unter 0, flacher als ein Schritt', note: `Der Seed hat heute keinen solchen Tag im Fenster; der Rahmen setzt Cash an zwei Tagen auf ${nf0.format(DIP).replace('-', '−')} (die Tiefe, die der UAT-Persona auf #1436 auffiel), sonst sind alle Bänder die des Seeds, nach den Regeln der App neu gestapelt: Cash wechselt das Vorzeichen, steht also an der Nulllinie und ist die letzte Zeile der Legende. Heute: Schritte zu ${nf0.format(dipBefore.step)}, der Plot reicht bis ${nf0.format(Math.round(dipBefore.lo)).replace('-', '−')}, der erste Wert ist „0“: die Tiefe steht nirgends auf dem Schirm (Legende und Tooltips lesen den letzten Tag). Neu: liegt ein Band unter 0, reicht der Plot bis zum nächsten runden Schritt darunter, „${tickLabel(dipAfter.ticks[0].v)}“ steht als Wert unter der Delle (<code>round_ticks</code> mit <code>lo</code> auf ein Vielfaches des Schritts abgerundet). Im Privatsphäre-Modus dasselbe in ganzen Prozent.`, frames: [B2.dipBefore, B2.dipAfter] },
  { title: '④ Allokation &amp; Ziele: TTWROR, während ein neues Fenster lädt', note: 'Heute behält die Zeile die Zahl des vorigen Fensters, bis das neue landet, ohne Zeichen: sie liest einen Moment lang als aktuell (der Privacy-Walk liest die Seite dann zu früh). Neu: solange die Performance neu berechnet wird, steht der Platzhalter der App an ihrer Stelle (<code>.value-slot-pending</code> mit <code>aria-busy="true"</code>, das Skelett und „wird berechnet“, wie die Kennzahl auf Bestände), und die Zeile trägt <code>aria-busy</code> (<code>busy_placeholders_test</code>).', frames: [B2.allocBefore, B2.allocAfter] },
  { title: '⑤ Crashes: die Tabelle der Fenster bei 390 px', note: `Vermögen › Risiko, „Crash-Fenster“ geöffnet. Heute scrollt die Tabelle mit sieben Spalten und den Aktionen in ihrem Rahmen seitlich (${CAPTURED.crashWindows390 ? `${CAPTURED.crashWindows390.table} px in ${CAPTURED.crashWindows390.wrapper} px` : ''}, gemessen mit dem Fenster des Seeds). Neu unter 560 px die Zeilen der Telefonlisten (UX-DR27, <code>.phone-row</code>): der Name über Hoch → Tief, darunter die Art, die längste Lücke und die Aktionen; rechts der Rückgang über „erholt …“. Zwei erkannte Fenster sind von Hand ergänzt (Zahlen erfunden), weil der Seed keinen Crash-Benchmark wählt; das manuelle ist das des Seeds.`, frames: [B2.crashBefore, B2.crashAfter] },
  { title: '⑥ Risiko ohne Portfolio', note: 'Heute steht nur „Noch kein Portfolio …“, und die Listen über den ganzen Katalog sind nicht erreichbar, obwohl sie kein Portfolio brauchen. Neu: unter der Leerzeile der Abschnitt „Crashes“ über den ganzen Katalog: die Gruppe „Wertpapiere“ entfällt (es gibt kein Depot), „Im Depot ansehen“ ebenso, die Marke „im Depot“ an keinem Namen; die Fenster und ihr Formular wie gehabt. Die Liste des Rahmens ist die des Seeds über den Katalog.', frames: [B2.riskBefore, B2.riskAfter] },
  { title: '⑦ „Namen ohne Fenster“: der richtige Grund, und die Tabelle passt', note: `Heute gilt ein Satz für alle Namen: „Die Kurse haben sich geändert …“, auch für einen Namen, der nur fehlt, weil ein anderer Crash-Benchmark gewählt ist (dessen Zelle sagt es zusätzlich, gedämpft). Die Tabelle braucht ${tableLine(B2.namesBefore, 1)} (UAT: 1.059 in 922), „Löschen“ ist nur seitlich scrollend erreichbar. Neu: eine Tabelle je Grund unter ihrem Satz, „Die Kurse haben sich geändert …“ oder „ausgeblendet, weil ein anderer Crash-Benchmark gewählt ist; sie kehren zurück, sobald ihr Benchmark wieder Crash-Benchmark ist“, mit der Zahl der Namen vorn; der gedämpfte Zusatz der Zelle entfällt, die Aktionen dürfen in ihrer Zelle umbrechen. Tabellen ${tableLine(B2.namesAfter, 1)} und ${tableLine(B2.namesAfter, 2)}. Drei Namen von Hand (der Seed hat keine).`, frames: [B2.namesBefore, B2.namesAfter] },
]);

// ===========================================================================
// Board 03 — the app ships Inter (#1221)

const B3 = {};
const DEJAVU = ':root { --font-sans: "DejaVu Sans"; }';
// The shipped face as the story would write it: the variable font's latin
// and latin-ext subsets, wght 100–900, font-display swap. The frames load
// it from frames/inter/, which is not in the repository: render.js serves
// the files of @fontsource-variable/inter@5.3.0 there (README).
const INTER = `
@font-face { font-family: "Inter"; font-style: normal; font-display: swap; font-weight: 100 900; src: url(inter/inter-latin-ext-wght-normal.woff2) format("woff2-variations"); unicode-range: U+0100-02BA, U+02BD-02C5, U+02C7-02CC, U+02CE-02D7, U+02DD-02FF, U+0304, U+0308, U+0329, U+1D00-1DBF, U+1E00-1E9F, U+1EF2-1EFF, U+2020, U+20A0-20AB, U+20AD-20C0, U+2113, U+2C60-2C7F, U+A720-A7FF; }
@font-face { font-family: "Inter"; font-style: normal; font-display: swap; font-weight: 100 900; src: url(inter/inter-latin-wght-normal.woff2) format("woff2-variations"); unicode-range: U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD; }
`;
// B: three static weights only; 500 falls to 400, 650 to 760 to 700.
const STATIC = [400, 600, 700].map((w) => `@font-face { font-family: "Inter"; font-style: normal; font-display: swap; font-weight: ${w}; src: url(inter/inter-latin-${w}-normal.woff2) format("woff2"); }`).join('\n');
const KPI_STRIP = cap('kpi-strip-1200.html');
const TX = cap('tx-filter-390.html');
// The sheet is a modal <dialog> fixed to the window's foot; the frame
// draws it in the page's flow, open, so its whole height shows.
const SHEET = 'dialog.filter-sheet[open] { position: static; max-height: none; box-shadow: none; }';
B3.kpiD = tagged(writeFrame('03a-kpi-dejavu', KPI_STRIP, { css: DEJAVU }), 'Heute ohne Inter · DejaVu Sans');
B3.kpiI = tagged(writeFrame('03b-kpi-inter', KPI_STRIP, { css: INTER }), 'A · Inter, variabel (latin + latin-ext)');
B3.kpiS = tagged(writeFrame('03c-kpi-inter-statisch', KPI_STRIP, { css: STATIC }), 'B · Inter, nur 400/600/700 statisch');
B3.posD = tagged(writeFrame('03d-positionen-dejavu', POSITIONS, { css: KEEP_SIX + DEJAVU }), 'Heute ohne Inter · DejaVu Sans');
B3.posI = tagged(writeFrame('03e-positionen-inter', POSITIONS, { css: KEEP_SIX + INTER }), 'A · Inter, variabel');
B3.txD = tagged(writeFrame('03f-transaktionen-dejavu', TX, { width: 390, css: SHEET + DEJAVU }), 'Heute ohne Inter · DejaVu Sans, 390 px');
B3.txI = tagged(writeFrame('03g-transaktionen-inter', TX, { width: 390, css: SHEET + INTER }), 'A · Inter, variabel, 390 px');

const FONT = json(path.join(DIR, 'font-sizes.json'), {});
const kib = (b) => (b ? nf1.format(b / 1024) + ' KiB' : '—');
const sizeRow = (label, files) => `<tr><td>${label}</td><td class="n">${files.map((f) => kib(FONT[f])).join(' + ')}</td><td class="n">${kib(files.reduce((a, f) => a + (FONT[f] || 0), 0))}</td></tr>`;
const fp = (f, k) => (probe(f)[k] !== undefined ? probe(f)[k] : '—');
const FONT_LEAD = `<p><strong>Entschieden:</strong> <code>--font-sans</code> nennt Inter zuerst (<code>app.css</code>, Zeile 3), die App liefert aber keine Schriftdatei (#1221): wer Inter nicht installiert hat, sieht die Seite in seiner Systemschrift; CI zeichnete in DejaVu Sans, der breitesten der üblichen, und seit Board 06 ⑮ misst jeder Rundgang beide (DESIGN.md, Amendment 2026-11-08, „Measured in every font“). <strong>Was dieses Board vorschlägt (A, empfohlen):</strong> die App liefert Inter selbst als variable woff2-Schrift (wght 100–900), die Untermengen latin und latin-ext, <code>font-display: swap</code>, aus <code>priv/static/fonts/</code> über ein <code>@font-face</code> je Untermenge mit ihrer <code>unicode-range</code>; <code>--font-sans</code> bleibt. Die Gewichte der App (400, 500, 600, 650, 680, 700, 740, 760) liegen alle im variablen Bereich. Lizenz: SIL Open Font License 1.1 (die Lizenzdatei liegt neben den Schriften). <strong>B:</strong> nur die statischen Gewichte 400, 600 und 700; 500 fällt auf 400, 650, 680, 740 und 760 fallen auf 700.</p>
<table><thead><tr><th>woff2, gemessen (@fontsource-variable/inter und @fontsource/inter 5.3.0)</th><th>Dateien</th><th>zusammen</th></tr></thead><tbody>
${sizeRow('A · variabel, latin', ['inter-latin-wght-normal.woff2'])}
${sizeRow('A · variabel, latin-ext', ['inter-latin-ext-wght-normal.woff2'])}
${sizeRow('A · variabel, beide', ['inter-latin-wght-normal.woff2', 'inter-latin-ext-wght-normal.woff2'])}
${sizeRow('B · statisch 400/600/700, latin', ['inter-latin-400-normal.woff2', 'inter-latin-600-normal.woff2', 'inter-latin-700-normal.woff2'])}
${sizeRow('B · statisch 400/600/700, latin-ext', ['inter-latin-ext-400-normal.woff2', 'inter-latin-ext-600-normal.woff2', 'inter-latin-ext-700-normal.woff2'])}
</tbody></table>
<p>B ist nicht kleiner: drei statische Gewichte wiegen in latin ${kib(['inter-latin-400-normal.woff2', 'inter-latin-600-normal.woff2', 'inter-latin-700-normal.woff2'].reduce((a, f) => a + (FONT[f] || 0), 0))} gegen ${kib(FONT['inter-latin-wght-normal.woff2'])} für alle Gewichte. Ein Browser lädt eine Untermenge nur, wenn die Seite ein Zeichen aus ihrer <code>unicode-range</code> braucht: deutscher und englischer Text kommt mit latin aus (ä, ö, ü, ß, €, „“, ›, −, …), latin-ext erst bei Namen wie „Łódź“ oder „Kőbánya“. ⓘ, ≈ und → liegen in keiner der beiden und kommen wie heute aus der nächsten Schrift der Liste.</p>
<p><strong>Umkehrbar per Kommentar:</strong> „Schrift B“ (statisch 400/600/700).</p>`;

board('03-shipped-font.html', 'Sprint 30 · #1221 — die App liefert Inter', 2010, FONT_LEAD, [
  { title: '① Übersicht: der KPI-Streifen bei 1200 px', recommended: true, note: `Zuerst, was ein Gerät ohne Inter heute zeigt (DejaVu Sans), dann A, dann B. Höhe des Streifens: DejaVu Sans ${fp(B3.kpiD, 'height')} px (die letzte Buchung bricht auf zwei Zeilen), Inter variabel ${fp(B3.kpiI, 'height')} px, statisch ${fp(B3.kpiS, 'height')} px. In B fallen die Labels der Zellen (650) auf 700, das Gewicht der Werte darunter, und sind nur noch durch Größe und Farbe getrennt; ebenso die Spaltenköpfe der Tabellen (740) und die Marke (760): jede Stufe, die DESIGN.md zwischen 600 und 700 oder über 700 setzt, fällt weg.`, frames: [B3.kpiD, B3.kpiI, B3.kpiS] },
  { title: '② Vermögen: Positionen bei 1200 px', recommended: true, note: `Dieselben sechs Zeilen wie Board 02 ①. Zeilenhöhen DejaVu Sans ${rowsLine(B3.posD)} px, Tabelle ${tableLine(B3.posD)}; Inter ${rowsLine(B3.posI)} px, Tabelle ${tableLine(B3.posI)}. In DejaVu Sans passt die Tabelle heute nicht (G&amp;V % halb außer Sicht, #1322 kehrt in der Ersatzschrift zurück), mit Inter passt sie. Die Rundgänge messen weiter in beiden Schriften: mit <code>swap</code> zeichnet die Seite die Ersatzschrift, bis die Datei geladen ist, und ein Gerät, das Webschriften sperrt, sieht sie immer.`, frames: [B3.posD, B3.posI] },
  { title: '③ Transaktionen bei 390 px, der Filter geöffnet', recommended: true, note: `Die Historie am Telefon, wo die Chips der Leiste im Filterblatt stehen (Konto, Typ, Geändert seit); das Blatt geöffnet und im Fluss der Seite gezeichnet statt am Fuß des Fensters, die Liste nach vier Zeilen ausgelassen. Höhe DejaVu Sans ${fp(B3.txD, 'height')} px, Inter ${fp(B3.txI, 'height')} px.`, frames: [B3.txD, B3.txI] },
]);

// ===========================================================================
// Board 04 — idea I32, „Tops und Flops“ per period (FR-59, ADR-0061)

const B4 = {};
const OVERVIEW = cap('d-overview-1200.html');
const OVERVIEW_PRIVACY = cap('d-overview-privacy-1200.html');
const PERF = cap('d-perf-1200.html');
const D_MEASURES = json(path.join(DIR, 'captured', 'd-measures.json'), {});

// The Overview's fragment in its parts: the wrappers and the load-error
// region, one entry per top-level section, the closing tags.
function overviewParts(html) {
  const first = html.indexOf('<section');
  const last = html.lastIndexOf('</section>') + '</section>'.length;
  const sections = html.slice(first, last).split(/(?=<section\b)/).map((s) => s.trim()).filter(Boolean)
    .map((s) => ({ id: (s.match(/^<section[^>]*\bid="([^"]+)"/) || [0, (s.match(/class="([^"]+)"/) || [0, ''])[1]])[1], html: s }));
  return { prefix: html.slice(0, first), sections, suffix: html.slice(last) };
}
// The Overview with the card after the KPI strip; `keep` limits the
// sections drawn (the rest named in a crop line).
function overviewWith(html, card, { keep = null, crop = '' } = {}) {
  const o = overviewParts(html);
  const out = [];
  for (const s of o.sections) {
    if (!keep || keep.includes(s.id)) out.push(s.html);
    if (s.id === 'dashboard-kpi-strip' && card) out.push(card);
  }
  if (crop) out.push(`<p class="mock-crop">${crop}</p>`);
  return o.prefix + out.join('\n') + o.suffix;
}
const cardOnly = (html, card) => { const o = overviewParts(html); return o.prefix + card + o.suffix; };

// The figures. YTD is the seed's own: the Kursrendite from its stored
// closes (the last on or before 31.12.2025 and the latest, all twelve in
// EUR; psql on the review database), the Beitrag the contribution table's
// rows for YTD as captured (d-measures.json), every one of the 41 opened.
const CLOSES = [
  [3, 'Allianz SE vinkulierte Namens-Aktien o.N.', 95.12, 116.86],
  [1, 'Apple Inc. Registered Shares o.N.', 161.18, 188.87],
  [2, 'Microsoft Corporation Registered Shares DL-,00000625', 200.79, 234.52],
  [7, 'NVIDIA Corporation Registered Shares DL-,001', 207.64, 240.11],
  [6, 'Bitcoin', 46233.79, 51393.52],
  [47, 'Larkspur Rail AG 4,00 % Anleihe 2031', 99.0, 100.25],
  [42, 'Birkenhain Wasser Anleihe 2029 1,50%', 0.982, 0.985],
  [43, 'Ostsee Logistik 4,10% 2028/2033', 98.8, 99.1],
  [41, 'Kestrel Anleihe 2030 2,75%', 97.1, 97.25],
  [5, 'Vanguard FTSE All-World UCITS ETF USD Acc', 87.12, 87.21],
  [8, 'Nordic Timber Holdings AB', 42.93, 42.64, 'letzter Kurs 11.10.2026'],
  [4, 'iShares Core MSCI World UCITS ETF USD (Acc)', 75.0, 72.02]
];
const pct = (r) => (r > 0 ? '+' : r < 0 ? '−' : '') + nf1.format(Math.abs(r)) + '%';
const ytdReturns = CLOSES.map(([id, name, a, b, sub]) => ({ id, name, r: (b / a - 1) * 100, sub })).sort((x, y) => y.r - x.r);
const nf2 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const amount = (v) => (v > 0 ? '+' : v < 0 ? '−' : '') + nf2.format(Math.abs(v));
const contribRows = (D_MEASURES.contribution || []).map((r) => ({ id: r.id, name: r.name, v: deNum(r.figure.replace(/^\+/, '')), sold: r.note === 'am Ende nicht mehr im Bestand' || r.note === 'weder zu Beginn noch am Ende im Bestand', mark: r.unvalued }));
const contribNonZero = contribRows.filter((r) => Math.round(r.v * 100) !== 0).sort((x, y) => y.v - x.v);
const contribZero = contribRows.length - contribNonZero.length;

// Five highest over five lowest; under ten, the list splits (the larger
// half on top), so no name stands in both halves. The lowest half reads
// from the lowest up.
function halves(rows, key) {
  const sorted = [...rows].sort((x, y) => y[key] - x[key]);
  const n = Math.min(5, Math.ceil(sorted.length / 2));
  const m = Math.min(5, sorted.length - n);
  return { top: sorted.slice(0, n), bottom: sorted.slice(sorted.length - m).reverse() };
}

const MASK = '<span class=pf-mask role=img aria-label=verborgen></span>';
const signClass = (v) => (v > 0 ? 'is-positive' : v < 0 ? 'is-negative' : '');
function returnRow(r) {
  return `<li><a href="/securities/${r.id}" class="attention-item" data-role="movers-row"><span class="attention-name">${esc(r.name)}${r.sub ? `<small class="attention-item__sub">${r.sub}</small>` : ''}</span><span class="num ${signClass(r.r)}">${pct(r.r)}</span></a></li>`;
}
function contribRow(r, largest, privacy) {
  const w = (Math.abs(r.v) / largest * 45).toFixed(1);
  const fig = privacy ? MASK : `${amount(r.v)} EUR`;
  return `<li><a href="/securities/${r.id}" class="attention-item" data-role="movers-row"><span class="attention-name">${esc(r.name)}${r.sold ? ' <span class="badge badge--neutral" data-role="movers-sold">verkauft</span>' : ''}${r.mark ? `<span class="contribution-unvalued-mark">${r.mark}</span>` : ''}${r.sub ? `<small class="attention-item__sub">${r.sub}</small>` : ''}</span><span class="num movers__figure"><span class="${signClass(r.v)}">${fig}</span><span class="drift-bar" aria-hidden="true"><span class="drift-bar__fill ${r.v < 0 ? 'is-under' : 'is-over'}" style="width: ${w}%"></span></span></span></a></li>`;
}
const PERIODS = [['day', 'Tag'], ['week', 'Woche'], ['month', 'Monat'], ['quarter', 'Quartal'], ['ytd', 'YTD'], ['1y', '1J']];
function controlBar(active, list = null) {
  const seg = (items, cur, param, id) => `<div class="segmented-control" data-role="movers-${param}" role="group" aria-labelledby="${id}">${items.map(([k, l]) => `<a href="/?movers_${param}=${k}" class="segmented-control__option${k === cur ? ' is-active' : ''}"${k === cur ? ' aria-current="true"' : ''}>${l}</a>`).join('')}</div>`;
  const listGroup = list ? `<span class="control-bar__group"><span class="control-bar__label" id="movers-list-label">Liste</span>${seg([['return', 'Kursrendite'], ['contribution', 'Beitrag']], list, 'list', 'movers-list-label')}</span>` : '';
  return `<div class="control-bar control-bar--fold-560 control-bar--floor-380" data-role="movers-bar"><div class="control-bar__controls"><span class="control-bar__group"><span class="control-bar__label" id="movers-period-label">Zeitraum</span>${seg(PERIODS, active, 'period', 'movers-period-label')}</span>${listGroup}</div></div>`;
}
const INFO_LINES = [
  'Kursrendite: letzter gespeicherter Schlusskurs im Zeitraum ÷ Schlusskurs vor dem Zeitraum − 1, beide in EUR zum gespeicherten Wechselkurs ihres Tages; Erträge und Kosten zählen nicht.',
  'Beitrag: Endwert − Anfangswert − Zu-/Abflüsse + Erträge − Kosten je Position, wie „Beitrag je Position“ in Vermögen; eine im Zeitraum verkaufte Position zählt mit.',
  'Je fünf höchste und niedrigste; unter zehn teilt sich die Liste, kein Name steht in beiden Hälften. Ein Beitrag, der 0,00 liest, steht in keiner Hälfte.',
  'Ohne Schlusskurs vor dem Zeitraum, ohne Kurs darin oder ohne Wechselkurs: keine Kursrendite. Ein Tag ohne Kurs zählt beim Beitrag null, wie in Vermögen.',
  'Tag: seit dem vorigen Schlusskurs jedes Wertpapiers; die beiden Daten stehen an der Zeile.'
];
// The card. `layout`: 'cols' (two columns, stacked by the card's own
// container query under 640 px: A1 at 390 px) or a list key for A2.
function moversCard(o) {
  const info = `<details class="metric-tooltip metric-tooltip--inline metric-tooltip--section" data-role="section-info"${o.infoOpen ? ' open data-place="below"' : ''}><summary aria-label="Über diesen Abschnitt">ⓘ</summary><p role="tooltip">${INFO_LINES.join('<br>')}</p></details>`;
  const head = `<div class="section-head"><div class="section-title"><h2 id="movers-title">Tops und Flops</h2>${info}</div><a class="kpi-summary__link" href="${o.href}" data-role="movers-wealth-link">In Vermögen ansehen →</a></div>`;
  const bar = controlBar(o.period, o.layout === 'cols' ? null : o.layout);
  // Where the view Wealth remembers is not the card's, one sentence under
  // the basis line names both (the built card, commit "fix(dashboard): the
  // movers card names Wealth's other view instead of linking it").
  const wealthView = o.wealthView ? `<p class="hint${o.wealthViewNew ? ' mock-new' : ''}" data-role="movers-wealth-view">Vermögen ist gerade auf die Ansicht „<bdi>${esc(o.wealthView)}</bdi>“ eingegrenzt; diese Karte zeigt „<bdi>${esc(o.view)}</bdi>“.</p>` : '';
  const basis = `<p class="summary-basis" data-role="movers-basis">${o.basis}</p>${wealthView}`;
  if (o.empty) return `<section id="dashboard-movers" class="workspace-section movers mock-new" aria-labelledby="movers-title">${head}${bar}<p class="empty-state" data-role="movers-empty">Keine Bestände in dieser Ansicht.</p></section>`;
  const rs = halves(o.returns, 'r');
  const cs = halves(o.contrib, 'v');
  const largest = Math.max(...[...cs.top, ...cs.bottom].map((r) => Math.abs(r.v)));
  const half = (label, rows, fn) => rows.length ? `<h4 class="movers__half">${label}</h4><ul class="attention-list">${rows.map(fn).join('')}</ul>` : '';
  const retCol = `<div class="movers__col" data-role="movers-return">${o.layout === 'cols' ? '<h3>Kursrendite</h3>' : ''}${half('Höchste', rs.top, returnRow)}${half('Niedrigste', rs.bottom, returnRow)}${o.returnCount ? `<p class="movers__count">${o.returnCount}</p>` : ''}</div>`;
  const conCol = `<div class="movers__col" data-role="movers-contribution">${o.layout === 'cols' ? '<h3>Beitrag</h3>' : ''}${half('Höchste', cs.top, (r) => contribRow(r, largest, o.privacy))}${half('Niedrigste', cs.bottom, (r) => contribRow(r, largest, o.privacy))}${o.contribCount ? `<p class="movers__count">${o.contribCount}</p>` : ''}</div>`;
  const cols = o.layout === 'cols' ? retCol + conCol : o.layout === 'return' ? retCol : conCol;
  return `<section id="dashboard-movers" class="workspace-section movers mock-new" aria-labelledby="movers-title">${head}${bar}${basis}<div class="movers__grid${o.layout === 'cols' ? '' : ' movers__grid--one'}">${cols}</div></section>`;
}
const MOVERS_CSS = `
/* I32: the card „Tops und Flops“ on the Overview. Its parts are the page's
   own: .section-head with the I1 ⓘ and the „→“ link of the trades card,
   the shared control bar, .attention-list rows, the contribution table's
   bar under its figure (contribution_table.ex) and the „ohne Bestand“
   badge's neutral look for „verkauft“. New are only the grid and the two
   small labels. */
.movers { container: movers / inline-size; }
.movers .section-head { margin-bottom: 0; }
.movers > .summary-basis { margin: 0; font-size: 12px; color: var(--color-text-muted); }
.movers__grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: var(--space-5, 20px) 48px; align-items: start; }
.movers__grid--one { grid-template-columns: minmax(0, 1fr); }
@container movers (max-width: 640px) { .movers__grid { grid-template-columns: minmax(0, 1fr); } }
.movers__col h3 { margin: 0; padding-bottom: 6px; font-size: 15px; border-bottom: 1px solid var(--color-border); }
.movers__half { margin: 12px 0 6px; font-size: 11px; font-weight: 650; letter-spacing: 0.04em; text-transform: uppercase; color: var(--color-text-muted); }
.movers__col > .movers__half:first-child { margin-top: 0; }
.movers__count { margin: 12px 0 0; font-size: 12px; color: var(--color-text-muted); }
.movers .attention-item .num { text-align: right; }
.movers .attention-name .badge { margin-left: 6px; vertical-align: 1px; }
.movers__figure .drift-bar { display: block; flex: none; width: 110px; min-width: 110px; margin: 5px 0 0 auto; }
`;

const YTD = {
  period: 'ytd', layout: 'cols', href: '/portfolio?from=2026-01-01&amp;to=2026-11-15',
  basis: 'Ansicht Alles · YTD: Schlusskurs 31.12.2025 bis 15.11.2026 · in EUR, aus gespeicherten Schlusskursen und Buchungen',
  returns: ytdReturns, contrib: contribNonZero,
  returnCount: '23 ohne Kursrendite: 17 ohne Kurs, 4 erst im Zeitraum bepreist, 2 ohne Wechselkurs',
  contribCount: `${contribZero} Positionen ohne Beitrag im Zeitraum`
};
const yRet = halves(ytdReturns, 'r'), yCon = halves(contribNonZero, 'v');

// ① today, ② A at 1200 px, the ⓘ open, ④ the privacy mode.
B4.today = tagged(writeFrame('04a-uebersicht-heute', OVERVIEW, {}), 'Heute · Übersicht bei 1200 px, Ansicht Alles: keine Karte');
B4.a = tagged(writeFrame('04b-a-karte', overviewWith(OVERVIEW, moversCard(YTD)), { css: MOVERS_CSS }), 'A · „Tops und Flops“ unter dem KPI-Streifen, YTD, die Zahlen des Seeds');
B4.info = tagged(writeFrame('04c-a-info-offen', cardOnly(OVERVIEW, moversCard({ ...YTD, infoOpen: true })), { css: MOVERS_CSS }), 'A · dieselbe Karte, das ⓘ geöffnet: die Methode');
B4.privacy = tagged(writeFrame('04d-a-privat', cardOnly(OVERVIEW_PRIVACY, moversCard({ ...YTD, privacy: true })), { css: MOVERS_CSS, privacy: true }), 'A · Privatsphäre-Modus: Kursrendite bleibt, Beitrag behält Reihenfolge und Balken, der Betrag ist der Balken der App');

// ③ 390 px: A1 stacked (recommended), A2 the switch in both states.
const KEEP_390 = ['dashboard-kpi-strip'];
const CROP_390 = 'Darunter wie heute: Abgeschlossene Trades, Ziel-Abweichungen, Fällig, Ferncoin-Zyklus, Datenqualität.';
B4.a1 = tagged(writeFrame('04e-a1-390-gestapelt', overviewWith(OVERVIEW, moversCard(YTD), { keep: KEEP_390, crop: CROP_390 }), { width: 390, css: MOVERS_CSS }), 'A1 · 390 px, gestapelt: Kursrendite, darunter Beitrag');
B4.a2r = tagged(writeFrame('04f-a2-390-kursrendite', overviewWith(OVERVIEW, moversCard({ ...YTD, layout: 'return' }), { keep: KEEP_390, crop: CROP_390 }), { width: 390, css: MOVERS_CSS }), 'A2 · 390 px, Schalter auf „Kursrendite“');
B4.a2c = tagged(writeFrame('04g-a2-390-beitrag', overviewWith(OVERVIEW, moversCard({ ...YTD, layout: 'contribution' }), { keep: KEEP_390, crop: CROP_390 }), { width: 390, css: MOVERS_CSS }), 'A2 · 390 px, Schalter auf „Beitrag“');

// ⑤ States, invented figures: „Tag“ on Sunday 15.11.2026; six securities
// in a view; a view without holdings.
const STOCK = 'Do 12.11. → Fr 13.11.', COIN = 'Sa 14.11. → So 15.11.';
const DAY = [
  [6, 'Bitcoin', 2.4, 61.68, COIN], [7, 'NVIDIA Corporation Registered Shares DL-,001', 1.8, 43.31, STOCK], [1, 'Apple Inc. Registered Shares o.N.', 0.9, 84.99, STOCK],
  [3, 'Allianz SE vinkulierte Namens-Aktien o.N.', 0.6, 42.07, STOCK], [2, 'Microsoft Corporation Registered Shares DL-,00000625', 0.4, 9.38, STOCK],
  [4, 'iShares Core MSCI World UCITS ETF USD (Acc)', -1.1, -95.07, STOCK], [5, 'Vanguard FTSE All-World UCITS ETF USD Acc', -0.7, -25.23, STOCK],
  [47, 'Larkspur Rail AG 4,00 % Anleihe 2031', -0.2, -20.05, STOCK], [41, 'Kestrel Anleihe 2030 2,75%', -0.1, -5.0, STOCK], [42, 'Birkenhain Wasser Anleihe 2029 1,50%', 0.1, 0.01, STOCK]
];
B4.day = tagged(writeFrame('04h-zustand-tag-wochenende', cardOnly(OVERVIEW, moversCard({
  period: 'day', layout: 'cols', href: '/portfolio?from=2026-11-12&amp;to=2026-11-15',
  basis: 'Ansicht Alles · Tag: seit dem vorigen Schlusskurs jedes Wertpapiers, die Daten an der Zeile · in EUR',
  returns: DAY.map(([id, name, r, , sub]) => ({ id, name, r, sub })), contrib: DAY.map(([id, name, , v, sub]) => ({ id, name, v, sub })),
  returnCount: '25 ohne Kursrendite: 17 ohne Kurs, 6 ohne zwei Schlusskurse, 2 ohne Wechselkurs', contribCount: '25 Positionen ohne Beitrag an ihrem Tag'
})), { css: MOVERS_CSS }), 'Zustand · „Tag“ am Sonntag, 15.11.2026: Aktie Fr gegen Do, Krypto So gegen Sa · Zahlen erfunden');
const SIX = [
  [11, 'Kestrel Industrial Group NV', 6.3, 312.0], [46, 'Wexmoor Instruments AG', 3.1, 96.5], [50, 'Tamarisk Systems Inc.', 1.2, 18.6],
  [12, 'Alpine Test Werke AG', -0.4, -8.9], [35, 'Brightwater Utilities plc', -1.9, -61.8], [37, 'Sable Point Energy ASA', -4.8, -233.4]
];
B4.six = tagged(writeFrame('04i-zustand-sechs', cardOnly(OVERVIEW, moversCard({
  period: 'month', layout: 'cols', href: '/portfolio?view=nur-neuzugang&amp;from=2026-11-01&amp;to=2026-11-15',
  basis: 'Ansicht Nur Neuzugang · Monat: Schlusskurs 31.10.2026 bis 15.11.2026 · in EUR, aus gespeicherten Schlusskursen und Buchungen',
  returns: SIX.map(([id, name, r]) => ({ id, name, r })),
  contrib: [...SIX.map(([id, name, , v]) => ({ id, name, v })), { id: 38, name: 'Linden Bay Bond 2029', v: 41.2, sold: true }]
})), { css: MOVERS_CSS }), 'Zustand · sechs Wertpapiere: je Hälfte drei; sieben Positionen mit einer verkauften: vier über drei · Zahlen erfunden');
// Board 06 (Sprint 30's closing act, design critic): 04i as drawn, the
// link carrying `view=`, and as built, the link without it and the
// sentence naming Wealth's other view under the basis line.
const SIX_CARD = {
  period: 'month', layout: 'cols', view: 'Nur Neuzugang',
  basis: 'Ansicht Nur Neuzugang · Monat: Schlusskurs 31.10.2026 bis 15.11.2026 · in EUR, aus gespeicherten Schlusskursen und Buchungen',
  returns: SIX.map(([id, name, r]) => ({ id, name, r })),
  contrib: [...SIX.map(([id, name, , v]) => ({ id, name, v })), { id: 38, name: 'Linden Bay Bond 2029', v: 41.2, sold: true }]
};
writeFrame('06g-bewegte-ansicht-heute', cardOnly(OVERVIEW, moversCard({ ...SIX_CARD, href: '/portfolio?view=nur-neuzugang&amp;from=2026-11-01&amp;to=2026-11-15' })), { css: MOVERS_CSS });
writeFrame('06h-bewegte-ansicht-neu', cardOnly(OVERVIEW, moversCard({ ...SIX_CARD, href: '/portfolio?from=2026-11-01&amp;to=2026-11-15', wealthView: 'Alles', wealthViewNew: true })), { css: MOVERS_CSS });
B4.empty = tagged(writeFrame('04j-zustand-leer', cardOnly(OVERVIEW, moversCard({ period: 'ytd', layout: 'cols', href: '/portfolio?from=2026-01-01&amp;to=2026-11-15', empty: true })), { css: MOVERS_CSS }), 'Zustand · eine Ansicht ohne Bestände');

// ⑥ B, not recommended: the same rankings on Vermögen › Performance, under
// „Beitrag je Position“, following that page's period (YTD/1J/3J/5J/Max).
const perfB = (() => {
  let s = PERF.replace(/(<figure id="performance-figure"[\s\S]*?<\/figure>)/, '<p class="mock-crop">Der Performance-Chart wie heute (Gesamt, TTWROR, YTD).</p>');
  s = s.replace(/<div class="control-bar[^"]*" data-role="stack-bar">[\s\S]*?<\/span>\s*<\/div>\s*<\/div>/, '');
  s = s.replace(/<form method="get" action="\/portfolio" class="period-disclosure__body benchmark-form"[\s\S]*?<\/form>/, '');
  const rs = halves(ytdReturns, 'r'), cs = halves(contribNonZero, 'v');
  const largest = Math.max(...[...cs.top, ...cs.bottom].map((r) => Math.abs(r.v)));
  const half = (label, rows, fn) => `<h4 class="movers__half">${label}</h4><ul class="attention-list">${rows.map(fn).join('')}</ul>`;
  const block = `<div id="performance-movers" class="contribution movers mock-new" data-role="movers"><div class="contribution__head"><div class="section-title"><h3 id="movers-title">Tops und Flops</h3><details class="metric-tooltip metric-tooltip--inline metric-tooltip--section"><summary aria-label="Über diesen Abschnitt">ⓘ</summary><p role="tooltip">${INFO_LINES.slice(0, 4).join('<br>')}</p></details></div><span class="contribution__scope">YTD · Ansicht Alles</span></div><div class="movers__grid"><div class="movers__col"><h3>Kursrendite</h3>${half('Höchste', rs.top, returnRow)}${half('Niedrigste', rs.bottom, returnRow)}<p class="movers__count">${YTD.returnCount}</p></div><div class="movers__col"><h3>Beitrag</h3>${half('Höchste', cs.top, (r) => contribRow(r, largest))}${half('Niedrigste', cs.bottom, (r) => contribRow(r, largest))}<p class="movers__count">${YTD.contribCount}</p></div></div></div>`;
  return swap(s, /<\/section>(\s*<\/div><\/main>)/, `${block}</section>$1`);
})();
const B_CSS = MOVERS_CSS + '#performance-movers { display: grid; gap: var(--space-3); margin-top: var(--space-5, 20px); }';
B4.b = tagged(writeFrame('04k-b-vermoegen', perfB, { css: B_CSS }), 'B · Vermögen › Performance, YTD: unter „Beitrag je Position“, dem Zeitraum der Seite folgend');

const yList = (rows, f) => rows.map(f).join(', ');
const TOPS_LEAD = `<p><strong>Entschieden</strong> (Idee I32, FR-59, ADR-0061 in Arbeit): für den Umfang der Übersicht (die Standard-Ansicht, sonst „Alles“) je Kalenderfenster zwei Ranglisten nebeneinander: <b>Kursrendite</b> (jedes heute im Umfang gehaltene Wertpapier, seine Kursrendite in EUR über das Fenster aus gespeicherten Schlusskursen) und <b>Beitrag</b> (der Geldbeitrag jeder Position in EUR über dasselbe Fenster, ADR-0051, mit den im Fenster verkauften Positionen, markiert „verkauft“). Fenster <b>Tag · Woche · Monat · Quartal · YTD · 1J</b>, jeweils bis heute; „Tag“ ist seit dem vorigen Schlusskurs jedes Wertpapiers, die Daten stehen dabei. Je fünf Höchste und Niedrigste je Rangliste. Keine Urteilswörter. Ein sichtbarer Basissatz, die Methode hinter dem ⓘ (DESIGN.md, I1). Jeder Name führt zum Wertpapier; „In Vermögen ansehen →“ öffnet Vermögen mit dem Fenster als benutzerdefiniertem Zeitraum.</p>
<p><strong>Das Board schlägt vor</strong>, und jede Zeile ist per Kommentar umkehrbar:</p>
<ul>
<li><b>A, die Karte auf der Übersicht, direkt unter dem KPI-Streifen</b> und vor „Abgeschlossene Trades“. Die Übersicht ist eine Spalte von Abschnitten; Wert-Karte und Streifen nennen die Rendite des Umfangs (+6,2% seit Jahresbeginn, TTWROR 1J), die Karte sagt gleich darunter, welche Namen sie bewegt haben, im selben Umfang. „Abgeschlossene Trades“ zählt dagegen über alle Depots, unabhängig von der Ansicht, und „Ziel-Abweichungen“, „Fällig“ und „Datenqualität“ beantworten „braucht etwas mich?“; zwischen ihnen stünde die Karte im falschen Gespräch.</li>
<li><b>Der Zeitraum in der geteilten Leiste</b> (<code>ControlBar.bar/1</code>, „Labelled controls start on one edge“): eine Gruppe „Zeitraum“, bei 1200 px eine Zeile, am Telefon das Label darüber (Boden 380). Der Link rechts im Kopf wie „Alle Trades →“.</li>
<li><b>Die Zeilen sind die der Übersicht</b> (<code>.attention-item</code>): Name links, Zahl rechts; Kursrendite als Prozent mit einer Nachkommastelle und Vorzeichen, Beitrag als Betrag in EUR mit dem Balken der Beitragstabelle darunter (<code>.drift-bar</code>, 110 px, das größte gelistete füllt 45 %). „verkauft“ als <code>badge--neutral</code> wie „ohne Bestand“ unter „Fällig“; eine Position, die an Tagen null zählte, trägt die Markierung der Beitragstabelle („171 Tage mit 0 bewertet“). Keine Rangnummern: die Beitrags-Lesung trägt keine.</li>
<li><b>Unter jeder Liste die Zahl ohne Antwort</b>: bei der Kursrendite nach Grund („17 ohne Kurs, 4 erst im Zeitraum bepreist, 2 ohne Wechselkurs“), beim Beitrag die Positionen, deren Beitrag 0,00 liest; ein Beitrag 0,00 steht in keiner Hälfte, sonst füllen ungepreiste Fonds die Niedrigsten.</li>
<li><b>Am Telefon A1, gestapelt</b>: Kursrendite, darunter Beitrag; der Balken fällt dort wie in der Beitragstabelle weg (<code>.drift-bar</code> unter 560 px).</li>
</ul>
<p><strong>Die Zahlen:</strong> ② bis ④ und ⑥ sind die des Seeds, YTD bis 15.11.2026. Kursrendite aus den gespeicherten Schlusskursen der zwölf Wertpapiere, die einen am 31.12.2025 und einen danach haben (Höchste ${yList(yRet.top, (r) => `${r.name.split(' ')[0]} ${pct(r.r)}`)}; Niedrigste ${yList(yRet.bottom, (r) => `${r.name.split(' ')[0]} ${pct(r.r)}`)}); Beitrag aus der Tabelle „Beitrag je Position“ für YTD, alle ${contribRows.length} Zeilen (${contribNonZero.length} mit Beitrag, ${contribZero} mit 0,00). ⑤'s Tag- und Monatszahlen sind erfunden und so markiert.</p>
<p><strong>Umkehrbar per Kommentar:</strong> „Tops/Flops auf Vermögen“ (B), „Tops/Flops umschaltbar am Handy“ (A2), „Tops/Flops nur Kursrendite“, „Tops/Flops nur Beitrag“.</p>`;

board('04-tops-flops.html', 'Sprint 30 · I32 — Tops und Flops je Zeitraum', 2010, TOPS_LEAD, [
  { title: '① Heute und ② A: die Karte auf der Übersicht, 1200 px', recommended: true, note: 'Links die Übersicht, wie die Review-Instanz sie heute zeigt (Ansicht Alles). Rechts dieselbe Seite mit der Karte unter dem KPI-Streifen: Kopf mit ⓘ und „In Vermögen ansehen →“, die Leiste „Zeitraum“, der Basissatz, zwei Spalten „Kursrendite“ | „Beitrag“, je „Höchste“ (5) über „Niedrigste“ (5). Wrenfield Gardens AG und Tamarisk Mining Ltd wurden im Jahr verkauft und stehen nur beim Beitrag; Larkspur Robotics Inc hat keinen Wechselkurs und daher keine Kursrendite, beim Beitrag steht es mit seinen 171 Tagen zu null. Nordic Timber trägt das Datum seines letzten Kurses, weil es vor dem Fensterende liegt.', frames: [B4.today, B4.a] },
  { title: '② A mit offenem ⓘ und ④ A im Privatsphäre-Modus', recommended: true, note: 'Das ⓘ hält die Methode (I1): die zwei Formeln, die Teilung unter zehn, was keine Antwort hat, und was „Tag“ heißt; sichtbar bleibt der eine Basissatz. Im Privatsphäre-Modus folgt die Karte der Regel der App (PrivacyMode, DESIGN.md Amendment 2026-11-06): jeder Betrag in einer Währung ist der Balken <code>pf-mask</code>, Prozente bleiben. Die Kursrendite bleibt also unverändert; der Beitrag behält Reihenfolge, Vorzeichenfarbe und den Balken unter der Zahl, wie die Beitragstabelle im Modus ihre <code>drift-bar</code>-Breiten behält (gemessen: 45,0 %, 42,0 %, 16,9 % …) und die Erträge-Balken ihre Höhen („ratios“). Die Zählzeile nennt keine Beträge („ohne Beitrag“ statt „0,00“), so bleibt sie im Modus gleich.', frames: [B4.info, B4.privacy] },
  { title: '③ A bei 390 px: A1 gestapelt (empfohlen) und A2 mit Schalter', recommended: true, note: 'Ein Container-Query auf der Karte (unter 640 px) stapelt die Spalten: A1 zeigt Kursrendite, darunter Beitrag, ohne Bedienschritt; die Seite wird länger, liest aber beide Fragen. A2 setzt eine zweite Gruppe „Liste: Kursrendite · Beitrag“ in die Leiste und zeigt eine Liste. Die Leiste folgt der geteilten Regel: unter ihrem Boden stehen die Labels über ihren Steuerungen, alle an einer Kante. Die Balken fallen unter 560 px weg, wie in der Beitragstabelle. Darunter folgt die Übersicht wie heute (abgeschnitten).', frames: [B4.a1, B4.a2r, B4.a2c] },
  { title: '⑤ Zustände: „Tag“ am Wochenende, sechs Wertpapiere, leerer Umfang', note: '„Tag“ am Sonntag, 15.11.2026: jede Zeile misst seit dem vorigen Schlusskurs ihres Wertpapiers, die Aktie Fr 13.11. gegen Do 12.11., Bitcoin So 15.11. gegen Sa 14.11. Die beiden Daten stehen als kleine Zeile unter dem Namen, nicht im Tooltip: am Telefon gibt es kein Hover, und genau sie unterscheiden die Zeilen. Mit sechs Wertpapieren zeigt jede Hälfte drei, kein Name in beiden; beim Beitrag sind es sieben Positionen mit einer verkauften, also vier über drei (die größere Hälfte oben). Ohne Bestände bleibt die Leiste, die Listen weichen dem Satz „Keine Bestände in dieser Ansicht.“; ein Beitrag einer im Fenster verkauften Position fiele dann noch an, das Board lässt diesen Fall der Story. Tag- und Monatszahlen erfunden.', frames: [B4.day, B4.six, B4.empty] },
  { title: '⑥ B — nicht empfohlen: auf Vermögen › Performance', option: true, note: 'Dieselben Ranglisten als Block unter „Beitrag je Position“, dem Zeitraum der Seite folgend (YTD, 1J, 3J, 5J, Max, benutzerdefiniert). Nicht empfohlen: die Seite hat kein Tag, keine Woche, keinen Monat und kein Quartal, also genau die kurzen Fenster nicht, nach denen „Tops und Flops“ gefragt wird (nur über „Benutzerdefinierter Zeitraum …“); und die Tabelle darüber ordnet den Geldbeitrag schon, größter zuerst, so dass die Spalte „Beitrag“ hier zum zweiten Mal dasselbe sagt. Der Chart ist abgeschnitten, die Leiste „Ebene“ ausgelassen.', frames: [B4.b] }
]);

console.log('wrote frames and boards 01 to 04');
