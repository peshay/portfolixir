// Sprint 29 planning boards 01 and 02, drawn on 2026-11-12 before any code:
//
//   01 the Crashes section on Wealth's Risk tab (FR-54, #1421, ADR-0058 §9),
//      drawn from idea board 03 (ux-design-2026-11-06-ideas-i23-i24) with the
//      states the record adds: no crash benchmark, provisional, unmatched name;
//   02 the benchmark picker, flagged first and held after (#1416, ADR-0046's
//      amendment of 2026-11-07 point 3), and where the operator chooses the
//      crash benchmark (ADR-0058 §1); its frame ⑤ (frames/02i* to 02l*) is
//      the third group „Weitere“ the B2 build added, drawn after the build,
//      and ⑥ (frames/02m*, 02n*) the groups at 390 px before and after the
//      closing act's larger gap before each label.
//
// The chrome (sidebar, top bar, area tabs, sections, segmented controls,
// tables, data notes, disclosures, the ⓘ) is the app's own markup: the shell
// (shell-a.html) is the Sprint 28 boards' capture from the review instance on
// the synthetic review seed, with the two entries Sprint 28 shipped since
// („Nachrichten“ after Wertpapiere, the version at the sidebar's foot), and
// the rest uses the classes the shipped templates use, so app.css draws it.
// What is new is drawn with the CSS in each frame's <style id="proposal">.
// Every security name is generic and every figure is invented; no instance
// data, name or machine detail appears.
//
// Usage:
//   node build-a.js    # writes frames/01*.html, frames/02*.html and both boards
//   node render-a.js   # measures the frames, rebuilds, renders the PNGs
//
// render-a.js passes the measured frame heights in FRAME_SIZES (JSON), so no
// sizes file is shared with the other boards in this folder.
const fs = require('fs');
const path = require('path');

const FRAMES = path.join(__dirname, 'frames');
fs.mkdirSync(FRAMES, { recursive: true });
const CSS_FROM_FRAME = '../../../../../../priv/static/app.css';
const STATIC_FROM_FRAME = '../../../../../../priv/static/';
const CSS_FROM_BOARD = '../../../../../priv/static/app.css';

let SIZES = {};
try { SIZES = JSON.parse(process.env.FRAME_SIZES || '{}'); } catch (e) { /* first run */ }

// ---------------------------------------------------------------------------
// Formatting (German, as the app shows it)

const nf1 = new Intl.NumberFormat('de-DE', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const sign = (x) => (x > 0 ? '+' : x < 0 ? '−' : '±');
const pct = (x) => `${sign(x)}${nf1.format(Math.abs(x))}&nbsp;%`;
const pp = (x) => `${sign(x)}${nf1.format(Math.abs(x))}&nbsp;Pp.`;
const cls = (x) => (x < 0 ? 'is-negative' : x > 0 ? 'is-positive' : '');

// ---------------------------------------------------------------------------
// Icons (the app's icon_paths/1)

const ICON = {
  chart_line: '<path d="M3 17 9 11l4 4 8-8"></path>',
  pie: '<path d="M21 12A9 9 0 1 1 12 3v9Z"></path><path d="M21 12a9 9 0 0 0-9-9v9h9Z"></path>',
  chart_bar: '<path d="M3 20V8M9 20V4M15 20v-8M21 20v-5"></path>',
  camera: '<path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2Z"></path><circle cx="12" cy="13" r="4"></circle>',
  calc: '<rect x="5" y="3" width="14" height="18" rx="2"></rect><path d="M9 7h6"></path><circle cx="9" cy="11" r=".6"></circle><circle cx="12" cy="11" r=".6"></circle><circle cx="15" cy="11" r=".6"></circle><circle cx="9" cy="14" r=".6"></circle><circle cx="12" cy="14" r=".6"></circle><circle cx="15" cy="14" r=".6"></circle><path d="M9 17h6"></path>',
  shield: '<path d="M12 21s7-3.5 7-9V5.5L12 3 5 5.5V12c0 5.5 7 9 7 9Z"></path>',
  target: '<circle cx="12" cy="12" r="9"></circle><circle cx="12" cy="12" r="4.5"></circle><circle cx="12" cy="12" r=".6"></circle>',
  chevron_right: '<path d="m9 6 6 6-6 6"></path>',
  asterisk: '<path d="M12 5v14M5.94 8.5l12.12 7M18.06 8.5l-12.12 7"></path>',
  plus: '<path d="M12 5v14M5 12h14"></path>',
  search: '<circle cx="11" cy="11" r="7"></circle><path d="m20 20-3.5-3.5"></path>',
  settings: '<circle cx="12" cy="12" r="3"></circle><circle cx="12" cy="12" r="9"></circle>',
  eye_off: '<path d="M3 3l18 18"></path><path d="M10.6 5.1A9.8 9.8 0 0 1 12 5c5 0 9 4.5 10 7-0.4 1-1.3 2.4-2.6 3.7M6.6 6.6C4.4 8 2.8 10.2 2 12c1 2.5 5 7 10 7 1.9 0 3.6-.6 5.1-1.5"></path><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"></path>',
};
const icon = (name, size = 14, klass = '') => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"${klass ? ` class="${klass}"` : ''} aria-hidden="true">${ICON[name]}</svg>`;

// ---------------------------------------------------------------------------
// Frames: one static page each, linking app.css

const SHELL = fs.readFileSync(path.join(__dirname, 'shell-a.html'), 'utf8')
  .replace(/src="\/images\//g, `src="${STATIC_FROM_FRAME}images/`);

const FRAME_CSS = `
body { margin: 0; background: var(--color-bg); }
.mock-new { outline: 2px dashed var(--color-accent); outline-offset: -4px; border-radius: 8px; }
.mock-pad { padding: 0; }
.mock-elided { margin: 0; padding: 10px clamp(16px, 2.4vw, 28px); border-bottom: 1px solid var(--color-border); font-size: 12.5px; color: var(--color-text-subtle); font-style: italic; }
`;

// One element per line, so a frame stays a readable multiline file.
const BREAK_BEFORE = /><(?=\/?(?:path|g|svg|line|circle|rect|tr|td|th|thead|tbody|tfoot|table|div|section|figure|nav|aside|header|form|select|option|optgroup|label|button|a|p|h[1-6]|details|summary|ul|li|input|span class="(?:crash-|stack-bar__|segmented-control__option|badge|area-tab)))/g;
const multiline = (s) => s.replace(BREAK_BEFORE, '>\n<');

function writeFrame(name, rawBody, { css = '', width = 960, shell = false, title = 'Risiko', subtitle = 'Konzentration und Schwankung · Ansicht: Alles', active = 'nav-portfolio', privacy = false, extraNav = null } = {}) {
  const body = multiline(rawBody);
  let html = `<div class="mock-pad">${body}</div>`;
  if (shell) {
    let s = SHELL.replace('%%MAIN%%', body)
      .replace(/<h1 id="app-topbar-title">[^<]*<\/h1>/, `<h1 id="app-topbar-title">${title}</h1>`)
      .replace(/<p id="app-topbar-subtitle">[^<]*<\/p>/, `<p id="app-topbar-subtitle">${subtitle}</p>`)
      .replace(/class="nav-link is-active"/g, 'class="nav-link "');
    if (active) s = s.replace(`id="${active}" class="nav-link "`, `id="${active}" class="nav-link is-active"`);
    if (privacy) {
      s = s.replace(/class="privacy-toggle " href="[^"]*" role="button" aria-pressed="false" title="Beträge verbergen" data-privacy-mode="off">\s*<svg[\s\S]*?<\/svg>/,
        `class="privacy-toggle is-active mock-new" href="/risk?privacy=off" role="button" aria-pressed="true" title="Beträge zeigen" data-privacy-mode="on">${icon('eye_off', 16, 'theme-svg-icon')}`);
    }
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
.mock-board > h2 small.is-decided { color: var(--color-text-muted); background: var(--color-bg-muted); }
p.mock-note { margin: 0 0 12px; max-width: 130ch; font-size: 13px; color: var(--color-text-muted); line-height: 1.5; }
p.mock-note b { color: var(--color-text); }
.mock-pickbar { margin: 0 0 16px; padding: 12px 16px; border: 1px solid var(--color-accent); border-left-width: 4px; border-radius: var(--radius-md); background: var(--color-accent-soft); font-size: 13px; line-height: 1.55; }
.mock-pickbar p { margin: 0 0 6px; } .mock-pickbar p:last-child { margin: 0; }
.mock-pickbar code { font-size: 12px; }
.mock-row { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
.mock-fig { margin: 0; }
.mock-tag { display: inline-block; margin: 0 0 6px; padding: 2px 10px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; color: var(--color-text-muted); background: var(--color-bg-muted); }
.mock-tag.is-rec { color: var(--color-accent); background: var(--color-accent-soft); }
.mock-frame { width: max-content; border: 1px solid var(--color-border-strong); border-radius: 10px; overflow: hidden; box-shadow: var(--shadow-panel); background: var(--color-bg); }
.mock-frame iframe { display: block; border: 0; }
`;

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');

function board(file, title, cols, intro, sections) {
  const sec = sections.map((s) => `
<section class="mock-board">
  <h2>${s.title}${s.recommended ? ' <small>recommended</small>' : ''}${s.decided ? ' <small class="is-decided">decided</small>' : ''}</h2>
  <p class="mock-note">${s.note}</p>
  <div class="mock-row">${s.frames.map((f) => `<figure class="mock-fig">${f.tag ? `<span class="mock-tag${f.rec ? ' is-rec' : ''}">${f.tag}</span>` : ''}<div class="mock-frame"><iframe src="frames/${f.file}" width="${f.width}" height="${f.height}" title="${f.file}"></iframe></div></figure>`).join('\n')}</div>
</section>`).join('\n');
  const html = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<link rel="stylesheet" href="${CSS_FROM_BOARD}">
<!-- Generated by build-a.js. Each frame under frames/ is a static page that
     links app.css; the block below is artboard chrome only. No script runs
     here. Synthetic data only. -->
<style id="board">${BOARD_CSS(cols)}</style>
</head>
<body>
<div class="mock-board mock-head"><h1>${esc(title)}</h1>
${intro}</div>
${sec}
</body>
</html>
`;
  fs.writeFileSync(path.join(__dirname, file), html);
}

const sized = (f, tag, rec = false) => ({ ...f, tag, rec, height: SIZES[f.file] || 700 });

// ===========================================================================
// Shared pieces of the Risk page

const WEALTH_TABS = [
  ['Bestände', 'chart_line'], ['Allokation &amp; Ziele', 'pie'], ['Cashflow', 'chart_bar'],
  ['Snapshots', 'camera'], ['Steuern', 'calc'], ['Risiko', 'shield'], ['Prognosen', 'target'],
];
const areaTabs = (active = 'Risiko') => `<nav class="area-tabs" data-role="area-tabs" data-tab-level="1" aria-label="Bereichs-Tabs">${WEALTH_TABS.map(([l, i]) => `<a class="area-tab${l === active ? ' is-active' : ''}" href="#"${l === active ? ' aria-current="page"' : ''}><span class="area-tab__icon" aria-hidden="true">${icon(i)}</span><span class="area-tab__label" data-label="${l}">${l}</span></a>`).join('')}</nav>`;

const sectionInfo = (lines, { open = false, below = false } = {}) => `<details class="metric-tooltip metric-tooltip--inline metric-tooltip--section" data-role="section-info"${open ? ' open' : ''}${below ? ' data-place="below"' : ''}><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">${lines.join('<br>')}</p></details>`;

const metricsSection = `<section class="workspace-section kpi-band" id="risk-metrics" aria-labelledby="risk-metrics-title"><header class="section-head"><div class="section-title"><h2 id="risk-metrics-title">Kennzahlen des Portfolios</h2>${sectionInfo(['Ein Tag ohne Renditebasis ergibt keine Beobachtung, nie eine Null.'])}</div></header><div class="kpi-band__support"><article class="stat stat--compact"><span>Volatilität, annualisiert</span><strong>14,2<small class="value-suffix">%</small></strong><small class="stat__sub">1 Jahr · 251 Beobachtungen · min. 60</small></article><article class="stat stat--compact"><span>Max. Rückgang</span><strong><span class="is-negative">−12,6</span><small class="value-suffix">%</small></strong><small class="stat__sub">02.06.2026 → 21.08.2026 · erholt 30.09.2026</small></article><article class="stat stat--compact"><span>Risikoadjustierte Rendite</span><strong>0,71</strong><small class="stat__sub">risikofreier Satz 2,00 % · Rendite je Risikoeinheit</small></article><article class="stat stat--compact"><span>Korrelationen</span><strong>0,88</strong><small class="stat__sub">höchste von 10 Paaren · 1 Jahr</small></article></div><p class="summary-basis" data-role="risk-basis">Grundlage: die um Zahlungen bereinigten täglichen Renditefaktoren der TTWROR-Kette, in EUR, annualisiert mit √365 — eine Einzahlung ist keine Rendite.</p></section>`;

// ===========================================================================
// Board 01 — the Crashes section

const BM = 'Weltindex ETF';

// The windows (ADR-0058 §2 and §4), newest first. Dates and falls invented.
const WINDOWS = {
  ongoing: { name: null, start: '23.10.2026', trough: '10.11.2026', fall: -11.8, bmEur: -10.9, recovered: null, kind: 'erkannt', provisional: true, gap: 3 },
  s2026: { name: 'Sommer 2026', start: '02.06.2026', trough: '21.08.2026', fall: -13.2, bmEur: -12.4, recovered: '02.10.2026', kind: 'erkannt', gap: 3, spanEnd: '21.11.2026' },
  y2025: { name: null, start: '18.02.2025', trough: '08.04.2025', fall: -16.7, recovered: '26.06.2025', kind: 'erkannt', gap: 4 },
  y2022: { name: 'Bärenmarkt 2022', start: '03.01.2022', trough: '12.10.2022', fall: -25.4, recovered: '18.01.2024', kind: 'erkannt', gap: 4 },
  war: { name: 'Kriegsbeginn 2022', start: '16.02.2022', trough: '07.03.2022', fall: -9.6, recovered: null, kind: 'manuell', gap: 3 },
  y2020: { name: 'Frühjahr 2020', start: '19.02.2020', trough: '23.03.2020', fall: -33.9, bmEur: -31.2, bmRise: 36.4, recovered: '16.11.2020', kind: 'erkannt', gap: 3, spanEnd: '23.06.2020' },
  y2018: { name: null, start: '03.10.2018', trough: '24.12.2018', fall: -19.8, recovered: '23.04.2019', kind: 'erkannt', gap: 4 },
};
const short = (d) => d.slice(0, 6); // "19.02."
const span = (w) => (w.start.slice(6) === w.trough.slice(6) ? `${short(w.start)}–${w.trough}` : `${w.start}–${w.trough}`);
const optionLabel = (w) => {
  const n = w.name || 'Ohne Namen';
  if (w.provisional) return `${n} · seit ${w.start} · läuft`;
  return `${n} · ${span(w)}${w.kind === 'manuell' ? ' · manuell' : ''}`;
};

// The held securities' moves in Frühjahr 2020, EUR price return start → trough.
const LOSERS_2020 = [
  ['Reise-Einzelwert D', -58.4], ['Bitcoin', -44.7], ['Industrie-Einzelwert B', -40.9], ['Tech-Einzelwert A', -37.2],
  ['Schwellenländer ETF', -33.0], ['Europa-Aktien ETF', -32.1], ['USA-Aktien ETF', -29.8], ['Dividenden-Fonds K', -26.5],
];
// Rebounders, Frühjahr 2020: rise from the own low to trough + 3 months; days back.
const REB_2020 = [
  ['Bitcoin', 112.4, 49], ['Tech-Einzelwert A', 71.0, 58], ['Reise-Einzelwert D', 52.3, null], ['Industrie-Einzelwert B', 47.6, 214],
  ['USA-Aktien ETF', 41.8, 139], ['Schwellenländer ETF', 39.9, 252], ['Europa-Aktien ETF', 33.5, 301], ['Dividenden-Fonds K', 24.1, 412],
];
// Rebounders, Sommer 2026: the span ends 21.11.2026, measured to the last close.
const REB_2026 = [
  ['Tech-Einzelwert A', 24.8, 19], ['Bitcoin', 21.5, 33], ['USA-Aktien ETF', 15.2, 27], ['Industrie-Einzelwert B', 13.9, null],
  ['Europa-Aktien ETF', 11.7, 41], ['Schwellenländer ETF', 10.4, null], ['Dividenden-Fonds K', 6.2, 48], ['Versorger AG', 3.1, 12],
];
// The ongoing window, its trough provisional.
const LOSERS_ONGOING = [
  ['Bitcoin', -27.3], ['Tech-Einzelwert A', -19.6], ['Industrie-Einzelwert B', -16.2], ['Reise-Einzelwert D', -15.0],
  ['USA-Aktien ETF', -12.4], ['Schwellenländer ETF', -11.1], ['Europa-Aktien ETF', -9.8], ['Dividenden-Fonds K', -7.5],
];
// The manual window without a crash benchmark: no reference line.
const LOSERS_WAR = [
  ['Europa-Aktien ETF', -14.6], ['Industrie-Einzelwert B', -13.9], ['Reise-Einzelwert D', -12.8], ['Tech-Einzelwert A', -11.2],
  ['Schwellenländer ETF', -9.7], ['Dividenden-Fonds K', -7.4], ['USA-Aktien ETF', -5.9], ['Versorger AG', -2.2],
];
// The catalogue universe adds securities the depot does not hold.
const LOSERS_2020_CAT = [
  ['Reise-Einzelwert D', -58.4, true], ['Kreuzfahrt-Einzelwert M', -55.1, false], ['Bitcoin', -44.7, true], ['Luftfahrt-Einzelwert N', -43.8, false],
  ['Industrie-Einzelwert B', -40.9, true], ['Halbleiter ETF', -38.0, false], ['Tech-Einzelwert A', -37.2, true], ['Schwellenländer ETF', -33.0, true],
];

const CRASH_CSS = `
.crash-section { position: relative; }
.crash-bar select { min-height: 30px; width: auto; max-width: min(19.5rem, 100%); font-size: 12.5px; }
.crash-window { display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px 14px; margin: 0; font-size: 13px; color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.crash-window b { color: var(--color-text); font-weight: 600; }
.crash-window .badge { align-self: center; }
.crash-window__link { margin-left: auto; color: var(--color-accent); font-weight: 600; text-decoration: none; white-space: nowrap; }
.crash-window__nolink { margin-left: auto; font-size: 12.5px; color: var(--color-text-muted); }
.crash-table { width: 100%; }
.crash-table thead th { white-space: nowrap; }
.crash-table td { padding-top: 6px; padding-bottom: 6px; }
.crash-table td.crash-rank { width: 1.5rem; color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.crash-table td.crash-name { white-space: nowrap; }
.crash-table td.crash-name .badge { margin-left: 6px; }
.crash-table td.crash-plot, .crash-table th.crash-plot { width: 44%; padding-left: 16px; padding-right: 16px; }
.crash-table.is-rebound td.crash-plot, .crash-table.is-rebound th.crash-plot { width: 34%; }
.crash-table th.crash-days { white-space: normal; width: 6.5rem; }
.crash-table td.num, .crash-table th.num { white-space: nowrap; }
.crash-table td.crash-pp { color: var(--color-text-muted); }
.crash-table td.crash-notyet { color: var(--color-danger); font-weight: 600; }
.crash-table tbody tr:hover td { background: inherit; }
.crash-track { position: relative; height: 14px; }
.crash-track__bar { position: absolute; top: 2px; height: 10px; border-radius: 2px; background: var(--color-danger); }
.crash-track__bar.is-up { background: var(--color-positive); }
.crash-track__zero { position: absolute; top: -8px; bottom: -8px; width: 1px; background: var(--color-border-strong); }
.crash-track__ref { position: absolute; top: -8px; bottom: -8px; width: 0; border-left: 1.5px dashed var(--color-text-muted); }
.crash-axis { position: relative; height: 16px; font-size: 11px; color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.crash-axis span { position: absolute; top: 0; transform: translateX(-50%); white-space: nowrap; }
.crash-table tfoot td { border: 0; padding-top: 2px; background: transparent; }
.crash-legend { display: flex; flex-wrap: wrap; gap: 4px 16px; margin: 0; font-size: 12.5px; color: var(--color-text-muted); }
.crash-legend__ref { display: inline-block; width: 0; height: 12px; margin-right: 6px; border-left: 1.5px dashed var(--color-text-muted); vertical-align: -1px; }
.crash-unanswered { margin: 0; font-size: 12.5px; color: var(--color-text-muted); }
.crash-unanswered button { margin-left: 4px; }
.crash-provisional { margin: 0; }
.crash-windows > summary { margin-bottom: 0; }
.crash-windows__body { display: grid; gap: 12px; margin-top: 8px; }
.crash-rule { display: flex; flex-wrap: wrap; align-items: center; gap: 6px 12px; margin: 0; font-size: 13px; color: var(--color-text-muted); }
.crash-rule b { color: var(--color-text); }
.crash-rule .button-secondary { margin-left: auto; display: inline-flex; align-items: center; gap: 4px; }
.crash-windows-table td, .crash-windows-table th { white-space: nowrap; }
.crash-windows-table td.crash-unnamed { font-style: italic; color: var(--color-text-muted); }
.crash-windows-table td.crash-actions { text-align: right; }
.crash-windows-table td.crash-actions .link-button + .link-button { margin-left: 12px; }
.crash-windows-table tr.is-ongoing td { background: var(--color-warning-soft); }
.crash-unmatched h3 { margin: 4px 0 4px; font-size: 13px !important; font-weight: 700 !important; }
.crash-unmatched p.hint { margin: 0 0 6px; }
.crash-unmatched-form { display: flex; flex-wrap: wrap; align-items: end; gap: 8px 12px; padding: 10px 12px; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg-elevated); }
.crash-unmatched-form label { display: grid; gap: 4px; font-size: 12px; font-weight: 600; color: var(--color-text-muted); }
.crash-unmatched-form input { min-height: 30px; font-size: 13px; }
.crash-unmatched-form input[aria-invalid] { border-color: var(--color-danger); }
.crash-unmatched-form .hint { flex-basis: 100%; margin: 0; }
.crash-chips { display: flex; flex-wrap: wrap; gap: 6px; }
.crash-chips .filter-chip .badge { margin-left: 6px; }
.crash-bar .stack-bar__label { min-width: 0; }
`;

// A ranked list as a table: rank, name, the bar against the benchmark's
// dashed line, the figure, the difference in percentage points.
function rankTable(rows, { min, max, ref, refLabel, figureHead, plotHead, ppHead, rebound = false, ticks, badges = false }) {
  const x = (v) => ((v - min) / (max - min)) * 100;
  const z = x(0);
  const body = rows.map(([n, v, extra], i) => {
    const left = Math.min(x(v), z), width = Math.abs(x(v) - z);
    const badge = badges && extra === true ? '<span class="badge badge--neutral">im Depot</span>' : '';
    const days = rebound ? (extra == null ? '<td class="num crash-notyet">noch nicht</td>' : `<td class="num">${extra}</td>`) : '';
    return `<tr><td class="crash-rank">${i + 1}</td><td class="crash-name">${n}${badge}</td><td class="crash-plot"><div class="crash-track"><span class="crash-track__zero" style="left:${z.toFixed(2)}%"></span><span class="crash-track__bar${v > 0 ? ' is-up' : ''}" style="left:${left.toFixed(2)}%;width:${width.toFixed(2)}%"></span>${ref == null ? '' : `<span class="crash-track__ref" style="left:${x(ref).toFixed(2)}%"></span>`}</div></td><td class="num ${cls(v)}">${pct(v)}</td>${ref == null ? '' : `<td class="num crash-pp">${pp(v - ref)}</td>`}${days}</tr>`;
  }).join('');
  const axis = `<div class="crash-axis">${ticks.map((t) => `<span style="left:${x(t).toFixed(2)}%">${t === 0 ? '0' : sign(t) + Math.abs(t)}&nbsp;%</span>`).join('')}</div>`;
  const cols = 4 + (ref == null ? 0 : 1) + (rebound ? 1 : 0);
  return `<div class="data-table-wrapper"><table class="data-table crash-table${rebound ? ' is-rebound' : ''}"><thead><tr><th>#</th><th>Wertpapier</th><th class="crash-plot">${plotHead}</th><th class="num">${figureHead}</th>${ref == null ? '' : `<th class="num">${ppHead}</th>`}${rebound ? '<th class="num crash-days">Tage bis Vorkrisenkurs</th>' : ''}</tr></thead><tbody>${body}</tbody><tfoot><tr><td></td><td></td><td class="crash-plot">${axis}</td>${'<td></td>'.repeat(cols - 3)}</tr></tfoot></table></div>`;
}

const seg = (labelId, label, options, active) => `<span class="stack-bar__group"><span class="stack-bar__label" id="${labelId}">${label}</span><div class="segmented-control" role="group" aria-labelledby="${labelId}">${options.map((o) => `<a class="segmented-control__option${o === active ? ' is-active' : ''}" href="#"${o === active ? ' aria-current="true"' : ''}>${o}</a>`).join('')}</div></span>`;

function crashBar({ window, list = 'Verlierer', universe = 'Im Depot', options, chips = false }) {
  const winSelect = `<form class="stack-bar__tree"><label for="crash-window">Fenster</label><select id="crash-window" name="crash">${options.map((w) => `<option${w === window ? ' selected' : ''}>${optionLabel(w)}</option>`).join('')}</select></form>`;
  return `<div class="stack-bar crash-bar" data-role="crash-bar"><div class="stack-bar__controls">${chips ? '' : winSelect}${seg('crash-list-label', 'Liste', ['Verlierer', 'Gewinner', 'Erholer'], list)}${seg('crash-universe-label', 'Wertpapiere', ['Im Depot', 'Ganzer Katalog'], universe)}</div></div>`;
}

const kindBadge = (w) => (w.kind === 'manuell' ? '<span class="badge">manuell</span>' : '<span class="badge badge--neutral">erkannt</span>');

function windowLine(w, { link = true, rebound = false, measuredTo = null, viewStart = null } = {}) {
  const name = w.name ? `<b>${w.name}</b>` : '<b><i>Ohne Namen</i></b>';
  const trough = w.provisional ? `Tief bisher <b>${w.trough}</b> <span class="badge badge-warning">vorläufig</span>` : `Tief <b>${w.trough}</b>`;
  const fall = w.kind === 'manuell' && !w.fallKnown ? '' : `<span>${BM} <b class="${cls(w.fall)}">${pct(w.fall)}</b> in USD</span>`;
  const rec = w.provisional ? '<span>läuft</span>' : w.recovered ? `<span>erholt am ${w.recovered}</span>` : '';
  let measure = '';
  if (rebound) {
    measure = measuredTo
      ? `<span>Erholung gemessen bis <b>${measuredTo}</b> <span class="badge badge-warning">vorläufig</span> · vollständig am ${w.spanEnd}</span>`
      : `<span>Erholung gemessen bis <b>${w.spanEnd}</b> (Tief + 3 Monate)</span>`;
  }
  const tail = viewStart
    ? `<span class="crash-window__nolink">Die Ansicht beginnt am ${viewStart}: in diesem Fenster gab es kein Depot.</span>`
    : link ? `<a class="crash-window__link" href="/portfolio?from=…&amp;to=…">Im Depot ansehen →</a>` : '';
  return `<p class="crash-window" data-role="crash-window">${name}${kindBadge(w)}<span>Hoch <b>${w.start}</b> → ${trough}</span>${fall}${rec}${measure}${tail}</p>`;
}

const INFO_LINES = [
  'Ein Fenster öffnet, sobald der Crash-Benchmark 10 % oder mehr unter seinem Höchststand schließt; es beginnt am letzten Tag auf dem Hoch und endet im tiefsten Schluss vor der Erholung, bei gleichen Tiefs am frühesten.',
  'Erkannt in der Währung des Benchmarks, gelistet in EUR zum Wechselkurs jedes Schlusstags; Splits bereinigt.',
  'Kurs an einem Tag: der letzte Schluss am oder vor ihm, höchstens 7 Tage alt. Ohne Kurs oder Wechselkurs keine Antwort, nie eine Null.',
  'Erholer: vom eigenen Tief zwischen Hoch und Tief bis drei Kalendermonate nach dem Tief; Tage bis Vorkrisenkurs in Kalendertagen.',
  'Gleichstand nach Wert, dann Name, dann ISIN. Benchmarks stehen in keiner Liste.',
  'Kein Urteil: die Listen vergleichen Kurse, sie sagen nicht, was zu kaufen ist.',
];

const header = (info = {}) => `<header class="section-head"><div class="section-title"><h2 id="risk-crashes-title">Crashes</h2>${sectionInfo(INFO_LINES, info)}</div></header>`;

const basisLosers = (w) => `<p class="summary-basis crash-basis">Grundlage: Kursrendite in EUR von Hoch bis Tief des Fensters · gestrichelt ${BM} über dieselben Tage (${pct(w.bmEur)}) · nur Wertpapiere, die der Katalog heute führt.</p>`;
const basisReb = (w) => `<p class="summary-basis crash-basis">Grundlage: Anstieg in EUR vom eigenen Tief bis zum Ende der Erholungsspanne · gestrichelt ${BM} (${pct(w.bmRise)}) · nur Wertpapiere, die der Katalog heute führt.</p>`;

const disclosureClosed = '<details class="perf-table-disclosure crash-windows" id="crash-windows"><summary class="disclosure-summary">' + icon('chevron_right', 12, 'disclosure-chevron') + 'Crash-Fenster · 6 erkannt · 1 manuell · 2 Namen ohne Fenster</summary></details>';

function crashSection(inner, { mark = true, info = {} } = {}) {
  return `<section class="workspace-section crash-section${mark ? ' mock-new' : ''}" id="risk-crashes" aria-labelledby="risk-crashes-title">${header(info)}${inner}</section>`;
}

const ALL_OPTIONS = [WINDOWS.ongoing, WINDOWS.s2026, WINDOWS.y2025, WINDOWS.y2022, WINDOWS.war, WINDOWS.y2020, WINDOWS.y2018];

const losersBody = (w, rows, extra = {}) => rankTable(rows, {
  min: extra.min ?? -70, max: extra.max ?? 0, ref: w.bmEur, ticks: extra.ticks ?? [-60, -40, -20, 0],
  plotHead: 'Kursrendite Hoch → Tief, EUR', figureHead: '%', ppHead: `ggü. ${BM}`, badges: extra.badges,
});

// (a) the default state, in the page, at 1200 px.
const sectionA = crashSection(
  crashBar({ window: WINDOWS.y2020, options: ALL_OPTIONS })
  + windowLine(WINDOWS.y2020)
  + losersBody(WINDOWS.y2020, LOSERS_2020)
  + basisLosers(WINDOWS.y2020)
  + '<p class="crash-unanswered">8 von 10 Wertpapieren mit Antwort gezeigt · 1 ohne Antwort: kein Kurs am Fensterbeginn <button type="button" class="link-button">anzeigen</button></p>'
  + disclosureClosed,
);
const f01a = writeFrame('01a-crashes-1200', `<div class="workspace-page">${areaTabs()}<p class="mock-elided">Eigene Regeln — unverändert</p>${metricsSection}${sectionA}<p class="mock-elided">Größte Einzelpositionen · Klumpenrisiko (HHI) · Anlageklassen-Obergrenzen — unverändert</p></div>`, { shell: true, width: 1200, css: CRASH_CSS });

// (a2) the catalogue universe: held ones carry „im Depot“.
const f01a2 = writeFrame('01a2-katalog', `<div class="workspace-page">${crashSection(
  crashBar({ window: WINDOWS.y2020, universe: 'Ganzer Katalog', options: ALL_OPTIONS })
  + windowLine(WINDOWS.y2020)
  + losersBody(WINDOWS.y2020, LOSERS_2020_CAT, { badges: true })
  + basisLosers(WINDOWS.y2020)
  + '<p class="crash-unanswered">8 von 214 Wertpapieren mit Antwort gezeigt · 31 ohne Antwort: 27 ohne Kurs am Fensterbeginn, 4 ohne Wechselkurs <button type="button" class="link-button">anzeigen</button></p>'
  + disclosureClosed,
)}</div>`, { width: 960, css: CRASH_CSS });

// (a-B) the window as a chip row instead of a select.
const chipRow = `<div class="crash-chips" role="group" aria-label="Fenster">${ALL_OPTIONS.map((w) => `<button type="button" class="filter-chip${w === WINDOWS.y2020 ? ' is-active' : ''}" aria-pressed="${w === WINDOWS.y2020}">${w.name || (w.provisional ? 'Ohne Namen · seit ' + w.start : 'Ohne Namen · ' + w.start.slice(3))}${w.kind === 'manuell' ? '<span class="badge">manuell</span>' : ''}${w.provisional ? '<span class="badge badge-warning">läuft</span>' : ''}</button>`).join('')}</div>`;
const f01aB = writeFrame('01a3-fenster-chips', `<div class="workspace-page">${crashSection(
  chipRow + crashBar({ window: WINDOWS.y2020, options: ALL_OPTIONS, chips: true }) + windowLine(WINDOWS.y2020)
  + losersBody(WINDOWS.y2020, LOSERS_2020.slice(0, 3)) + '<p class="mock-elided" style="border:0;padding:0">… die übrigen Zeilen wie in (a)</p>',
)}</div>`, { width: 960, css: CRASH_CSS });

// (b) Erholer, Frühjahr 2020: complete span, „noch nicht“.
const rebBody = (w, rows, ref, max = 125, ticks = [0, 25, 50, 75, 100, 125]) => rankTable(rows, {
  min: 0, max, ref, ticks, rebound: true,
  plotHead: 'Anstieg vom eigenen Tief, EUR', figureHead: '%', ppHead: `ggü. ${BM}`,
});
const f01b = writeFrame('01b-erholer', `<div class="workspace-page">${crashSection(
  crashBar({ window: WINDOWS.y2020, list: 'Erholer', options: ALL_OPTIONS })
  + windowLine(WINDOWS.y2020, { rebound: true })
  + rebBody(WINDOWS.y2020, REB_2020, WINDOWS.y2020.bmRise)
  + basisReb(WINDOWS.y2020)
  + disclosureClosed,
)}</div>`, { width: 960, css: CRASH_CSS });

// (b2) Erholer, Sommer 2026: the span ends 21.11.2026, so the list is provisional.
const s26 = { ...WINDOWS.s2026, bmRise: 12.9 };
const f01b2 = writeFrame('01b2-erholer-vorlaeufig', `<div class="workspace-page">${crashSection(
  crashBar({ window: WINDOWS.s2026, list: 'Erholer', options: ALL_OPTIONS })
  + windowLine(s26, { rebound: true, measuredTo: '11.11.2026' })
  + rebBody(s26, REB_2026, s26.bmRise, 30, [0, 10, 20, 30])
  + `<p class="summary-basis crash-basis">Grundlage: Anstieg in EUR vom eigenen Tief bis zum letzten Schluss (11.11.2026), nicht bis zum Ende der Spanne · gestrichelt ${BM} (${pct(s26.bmRise)}) · nur Wertpapiere, die der Katalog heute führt.</p>`
  + disclosureClosed,
)}</div>`, { width: 960, css: CRASH_CSS });

// (c) the windows behind the disclosure.
const wRow = (w, actions) => {
  const name = w.name ? `<td>${w.name}</td>` : '<td class="crash-unnamed">ohne Namen</td>';
  const trough = w.provisional ? `${w.trough} <span class="badge badge-warning">vorläufig</span>` : w.trough;
  const rec = w.provisional ? 'läuft' : (w.recovered || '—');
  return `<tr${w.provisional ? ' class="is-ongoing"' : ''}>${name}<td>${w.start}</td><td>${trough}</td><td class="num ${cls(w.fall)}">${pct(w.fall)}</td><td>${rec}</td><td class="num">${w.gap}</td><td>${kindBadge(w)}</td><td class="crash-actions">${actions}</td></tr>`;
};
const lb = (t) => `<button type="button" class="link-button">${t}</button>`;
const windowsTable = `<div class="data-table-wrapper"><table class="data-table crash-windows-table"><thead><tr><th>Name</th><th>Hoch</th><th>Tief</th><th class="num">Rückgang</th><th>Erholt</th><th class="num">Lücke, Tage</th><th>Art</th><th></th></tr></thead><tbody>${[
  wRow(WINDOWS.ongoing, lb('Benennen')),
  wRow(WINDOWS.s2026, lb('Umbenennen') + lb('Name löschen')),
  wRow(WINDOWS.y2025, lb('Benennen')),
  wRow(WINDOWS.y2022, lb('Umbenennen') + lb('Name löschen')),
  wRow(WINDOWS.war, lb('Bearbeiten') + lb('Löschen')),
  wRow(WINDOWS.y2020, lb('Umbenennen') + lb('Name löschen')),
  wRow(WINDOWS.y2018, lb('Benennen')),
].join('')}</tbody></table></div>`;
const ruleLine = (changeOpen = false) => `<p class="crash-rule">Regel: Hoch → Tief ab 10&nbsp;% im Schlusskurs des Crash-Benchmarks · Crash-Benchmark <b>${BM}</b> (USD) ${changeOpen ? '' : lb('Ändern')}<button type="button" class="button-secondary">${icon('plus', 12)}Fenster anlegen</button></p>`;
const unmatched = (form = false) => `<div class="crash-unmatched"><h3>Namen ohne Fenster (2)</h3><p class="hint">Die Kurse haben sich geändert: an diesen Tagen beginnt kein erkanntes Fenster mehr. Ein Name wird nie geraten einem anderen Fenster zugeordnet.</p><div class="data-table-wrapper"><table class="data-table crash-windows-table"><thead><tr><th>Name</th><th>Gegeben für</th><th>Hoch</th><th></th></tr></thead><tbody><tr><td>Korrektur 2023</td><td>${BM}</td><td>31.07.2023</td><td class="crash-actions">${lb('Als manuelles Fenster anlegen …')}${lb('Löschen')}</td></tr><tr><td>Finanzkrise 2008</td><td>Europa-Index ETF <span class="muted">· kehrt zurück, wenn er wieder Crash-Benchmark ist</span></td><td>09.10.2007</td><td class="crash-actions">${lb('Als manuelles Fenster anlegen …')}${lb('Löschen')}</td></tr></tbody></table></div>${form ? `<form class="crash-unmatched-form" data-role="crash-unmatched-form"><label>Name<input type="text" value="Korrektur 2023"></label><label>Hoch<input type="text" value="31.07.2023"></label><label>Tief<input type="text" value="" placeholder="TT.MM.JJJJ" aria-invalid="true"></label><button type="submit" class="button-primary">Anlegen</button><button type="button" class="button-ghost">Abbrechen</button><p class="hint">Zum Namen gehört nur der Tag des Hochs: das Tief trägst du ein. Das Fenster ist danach „manuell“, der Name ohne Fenster entfällt.</p></form>` : ''}</div>`;
const disclosureOpen = (form = false) => `<details class="perf-table-disclosure crash-windows" id="crash-windows" open><summary class="disclosure-summary">${icon('chevron_right', 12, 'disclosure-chevron')}Crash-Fenster · 6 erkannt · 1 manuell · 2 Namen ohne Fenster</summary><div class="crash-windows__body">${ruleLine()}${windowsTable}${unmatched(form)}</div></details>`;
const f01c = writeFrame('01c-fenster', `<div class="workspace-page">${crashSection(
  crashBar({ window: WINDOWS.y2020, options: ALL_OPTIONS }) + '<p class="mock-elided" style="border:0;padding:0">… Fensterzeile, Liste und Grundlage wie in (a)</p>' + disclosureOpen(false),
)}</div>`, { width: 1000, css: CRASH_CSS });
const f01c2 = writeFrame('01c2-name-ohne-fenster', `<div class="workspace-page">${crashSection(
  '<p class="mock-elided" style="border:0;padding:0">… der Aufklapper geöffnet, die Fenstertabelle wie oben</p>' + `<div class="crash-windows__body">${unmatched(true)}</div>`,
)}</div>`, { width: 1000, css: CRASH_CSS });

// (d) no crash benchmark chosen: one line, manual windows still listed.
const noteLine = `<div class="data-note data-note--note" data-role="crash-no-benchmark"><span class="data-note__icon" aria-hidden="true">${icon('asterisk')}</span><span class="data-note__word">Hinweis</span><div class="data-note__body">Kein Crash-Benchmark gewählt: die Regel erkennt keine Fenster, manuelle gelten weiter. <a href="#crash-benchmark">Crash-Benchmark wählen</a></div></div>`;
const warW = { ...WINDOWS.war, fall: null };
const f01d = writeFrame('01d-kein-benchmark', `<div class="workspace-page">${crashSection(
  noteLine
  + crashBar({ window: warW, options: [warW] })
  + windowLine(warW)
  + rankTable(LOSERS_WAR, { min: -20, max: 0, ref: null, ticks: [-20, -15, -10, -5, 0], plotHead: 'Kursrendite Hoch → Tief, EUR', figureHead: '%' })
  + '<p class="summary-basis crash-basis">Grundlage: Kursrendite in EUR von Hoch bis Tief des Fensters · kein Vergleich: kein Crash-Benchmark gewählt · nur Wertpapiere, die der Katalog heute führt.</p>'
  + '<details class="perf-table-disclosure crash-windows"><summary class="disclosure-summary">' + icon('chevron_right', 12, 'disclosure-chevron') + 'Crash-Fenster · 1 manuell</summary></details>',
)}</div>`, { width: 960, css: CRASH_CSS });
const f01d2 = writeFrame('01d2-kein-benchmark-leer', `<div class="workspace-page">${crashSection(
  noteLine + '<p class="empty-state">Noch kein Fenster. <button type="button" class="link-button">Fenster anlegen</button></p>',
)}</div>`, { width: 960, css: CRASH_CSS });

// (e) an ongoing window, its trough provisional.
const f01e = writeFrame('01e-laufend', `<div class="workspace-page">${crashSection(
  crashBar({ window: WINDOWS.ongoing, options: ALL_OPTIONS })
  + windowLine(WINDOWS.ongoing)
  + `<p class="hint crash-provisional">Das Fenster läuft: solange ${BM} tiefer schließt, wandern das Tief und mit ihm die Listen.</p>`
  + losersBody(WINDOWS.ongoing, LOSERS_ONGOING, { min: -30, ticks: [-30, -20, -10, 0] })
  + basisLosers(WINDOWS.ongoing)
  + disclosureClosed,
)}</div>`, { width: 960, css: CRASH_CSS });

// (i) a window before the view's first day: no link, one line why.
const f01i = writeFrame('01i-vor-der-ansicht', `<div class="workspace-page">${crashSection(
  crashBar({ window: WINDOWS.y2018, options: ALL_OPTIONS }) + windowLine(WINDOWS.y2018, { viewStart: '04.05.2021' }),
)}</div>`, { width: 960, css: CRASH_CSS });

// (h) the ⓘ open: the method sentences.
const f01h = writeFrame('01h-info', `<div class="workspace-page" style="min-height:400px">${crashSection(
  crashBar({ window: WINDOWS.y2020, options: ALL_OPTIONS }) + windowLine(WINDOWS.y2020), { info: { open: true, below: true } },
)}</div>`, { width: 960, css: CRASH_CSS });

// (f) the phone: A keeps the bars, two lines per entry; B rows without bars.
const PHONE_CSS = CRASH_CSS + `
.crash-plist { list-style: none; margin: 0; padding: 0; display: grid; }
.crash-plist li { display: grid; grid-template-columns: 1.4rem minmax(0, 1fr) auto; gap: 2px 8px; padding: 8px 0; border-bottom: 1px solid var(--color-border); font-size: 13px; align-items: baseline; }
.crash-plist .crash-rank { color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.crash-plist .crash-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.crash-plist .crash-fig { text-align: right; font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
.crash-plist .crash-track { grid-column: 2; margin: 4px 0 2px; }
.crash-plist .crash-pp { grid-column: 3; text-align: right; font-size: 12px; color: var(--color-text-muted); font-variant-numeric: tabular-nums; white-space: nowrap; }
.crash-plist .crash-track__zero, .crash-plist .crash-track__ref { top: -4px; bottom: -4px; }
.crash-ptable td, .crash-ptable th { white-space: nowrap; }
.crash-window__link { margin-left: 0; }
`;
function phoneList(rows, { min, max, ref }) {
  const x = (v) => ((v - min) / (max - min)) * 100;
  const z = x(0);
  return `<ol class="crash-plist">${rows.map(([n, v], i) => {
    const left = Math.min(x(v), z), width = Math.abs(x(v) - z);
    return `<li><span class="crash-rank">${i + 1}</span><span class="crash-name">${n}</span><span class="crash-fig ${cls(v)}">${pct(v)}</span><div class="crash-track"><span class="crash-track__zero" style="left:${z.toFixed(2)}%"></span><span class="crash-track__bar" style="left:${left.toFixed(2)}%;width:${width.toFixed(2)}%"></span><span class="crash-track__ref" style="left:${x(ref).toFixed(2)}%"></span></div><span class="crash-pp">${pp(v - ref)}</span></li>`;
  }).join('')}</ol>`;
}
const phoneTable = (rows, ref) => `<div class="data-table-wrapper"><table class="data-table crash-ptable"><thead><tr><th>#</th><th>Wertpapier</th><th class="num">%</th><th class="num">ggü. BM</th></tr></thead><tbody>${rows.map(([n, v], i) => `<tr><td class="crash-rank">${i + 1}</td><td>${n}</td><td class="num ${cls(v)}">${pct(v)}</td><td class="num crash-pp">${pp(v - ref)}</td></tr>`).join('')}</tbody></table></div>`;
const phoneSection = (list, privacy = false) => crashSection(
  crashBar({ window: WINDOWS.y2020, options: ALL_OPTIONS })
  + windowLine(WINDOWS.y2020)
  + list
  + `<p class="crash-legend"><span><span class="crash-legend__ref"></span>${BM} ${pct(WINDOWS.y2020.bmEur)} in EUR</span></p>`
  + basisLosers(WINDOWS.y2020)
  + disclosureClosed,
);
const f01f = writeFrame('01f-phone-balken', `<div class="workspace-page">${areaTabs()}${phoneSection(phoneList(LOSERS_2020, { min: -70, max: 0, ref: WINDOWS.y2020.bmEur }))}</div>`, { shell: true, width: 390, css: PHONE_CSS });
const f01f2 = writeFrame('01f2-phone-zeilen', `<div class="workspace-page">${areaTabs()}${phoneSection(phoneTable(LOSERS_2020, WINDOWS.y2020.bmEur))}</div>`, { shell: true, width: 390, css: PHONE_CSS });
const f01g = writeFrame('01g-phone-privat', `<div class="workspace-page">${areaTabs()}${phoneSection(phoneList(LOSERS_2020, { min: -70, max: 0, ref: WINDOWS.y2020.bmEur }))}</div>`, { shell: true, width: 390, css: PHONE_CSS, privacy: true });

// (p) where the section sits on the page: after the metrics (A) or last (B).
const OUTLINE_CSS = `
.mock-outline { display: grid; gap: 6px; padding: 14px; width: 290px; box-sizing: border-box; }
.mock-outline div { padding: 8px 10px; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg-elevated); font-size: 13px; font-weight: 600; }
.mock-outline div small { display: block; font-weight: 400; color: var(--color-text-muted); font-size: 11.5px; }
.mock-outline div.mock-new { outline-offset: 1px; }
`;
const outline = (order) => `<div class="mock-outline">${order.map(([t, s, isNew]) => `<div${isNew ? ' class="mock-new"' : ''}>${t}<small>${s}</small></div>`).join('')}</div>`;
const SECTIONS = {
  rules: ['Eigene Regeln', 'die Ansicht, deine Schwellen'],
  metrics: ['Kennzahlen des Portfolios', 'die Ansicht, ein Jahr; Max. Rückgang'],
  crashes: ['Crashes', 'der Markt, seine Fenster; die Ansicht oder der Katalog', true],
  top: ['Größte Einzelpositionen', 'die Ansicht, heute'],
  hhi: ['Klumpenrisiko (HHI)', 'die Ansicht, heute'],
  caps: ['Anlageklassen-Obergrenzen', 'per Anfrage; Korrelationen dahinter'],
};
const f01pA = writeFrame('01p-ort-a', outline([SECTIONS.rules, SECTIONS.metrics, SECTIONS.crashes, SECTIONS.top, SECTIONS.hhi, SECTIONS.caps]), { width: 290, css: OUTLINE_CSS });
const f01pB = writeFrame('01p-ort-b', outline([SECTIONS.rules, SECTIONS.metrics, SECTIONS.top, SECTIONS.hhi, SECTIONS.caps, SECTIONS.crashes]), { width: 290, css: OUTLINE_CSS });

board('01-crash-section.html', 'Sprint 29 — Board 01: the Crashes section on Wealth › Risiko (FR-54, #1421, ADR-0058)', 1260, `<div class="mock-pickbar">
<p><b>Decided (ADR-0058, signed by the merge of the Sprint 28 planning PR):</b> a section „Crashes“ on Wealth's Risk tab, as idea board 03 drew it: the window, the list (Verlierer · Gewinner · Erholer), the securities (im Depot · ganzer Katalog), eight per list against the crash benchmark's line, „Im Depot ansehen“ opening Bestände with the window as a custom range, and the windows behind a disclosure with their kind, names and names without a window (§9). Losers and winners rank the EUR price return from the window's high to its low, not to each security's own low as board 03 had it (§5). Detection reads the benchmark in its own currency, the lists are in EUR (§7.9). The states the record adds: no crash benchmark (§1), provisional (§2.5, §5), a name without a window (§3).</p>
<p><b>Proposed here, each recommended option the default unless you comment:</b> P1 the section sits after „Kennzahlen des Portfolios“ (A; flip „Crashes ans Ende“); P2 the window is a select, the first labelled control of one bar built as DESIGN.md's „Labelled controls start on one edge“ component (A; „Crash-Fenster als Chips“); P3 the screen opens on „Im Depot“, the page's view, while the API's default stays the catalogue („Crashes ganzer Katalog zuerst“); P4 it opens on the newest window, the choice kept in the address („Crash-Start tiefstes Fenster“); P5 on a phone the bars stay, two lines per entry (A; „Crashes am Handy als Tabelle“); P6 „Tage bis Vorkrisenkurs“ counts calendar days („Erholer-Tage als Handelstage“); P7 a window before the view's first day shows no „Im Depot ansehen“ and one line why („Depot-Link immer“); P8 without a crash benchmark, a manual window's lists carry no reference line and no Pp. column („Ohne Crash-Benchmark keine Listen“); P9 „Als manuelles Fenster anlegen …“ asks for the low, which a name does not store. Dashed outline: new.</p>
</div>`, [
  { title: '① The default state, in the page (1200 px)', recommended: true, note: 'P1 A, P2 A, P3, P4: the Risk page with the new section after the portfolio metrics; the window „Frühjahr 2020“ (detected, named), the list Verlierer, the securities „Im Depot“. Each bar is the EUR price return from the high to the low; the dashed line is the crash benchmark over the same days in EUR (−31,2 %), the fall that detected the window is its own currency\'s (−33,9 % in USD). Beside each: the difference in percentage points. One sentence of basis stays visible; the method is behind the heading\'s ⓘ (I1). Names without an answer are counted, never zero.', frames: [sized(f01a, 'A · 1200 px', true)] },
  { title: '② „Ganzer Katalog“, and the ⓘ open', note: 'In the catalogue, a held security carries „im Depot“, so the two universes read as one list with a marker (proposal; flip „Katalog ohne Depot-Marke“). The ⓘ holds the method: the rule, the currencies, the close lookup, the recovery span, ties, no verdict.', frames: [sized(f01a2, 'Ganzer Katalog'), sized(f01h, 'ⓘ offen')] },
  { title: '③ Where the window is chosen: a select (A) or chips (B)', recommended: true, note: '<b>A (recommended):</b> one bar, „Fenster“ the first labelled control, so window, list and securities start on one edge at every width; it scales to any number of windows and its option says name, dates and fall. <b>B:</b> one chip per window above the bar: every window visible, one click, but 10–15 chips over twenty years wrap into a block that pushes the list down, and an unnamed window needs a date to tell it apart. Flip: „Crash-Fenster als Chips“.', frames: [sized(f01aB, 'B · Chips')] },
  { title: '④ Erholer: complete, and provisional', note: '„Frühjahr 2020“: the rise from each security\'s own low to the end of the span (the low plus three calendar months, 23.06.2020), the benchmark\'s rise dashed, and the calendar days until the security first closed at or above its close at the high, or „noch nicht“ (P6; flip „Erholer-Tage als Handelstage“). „Sommer 2026“: the span ends on 21.11.2026, so the list is measured to the last close and says „vorläufig · vollständig am 21.11.2026“.', frames: [sized(f01b, 'Erholer · vollständig'), sized(f01b2, 'Erholer · vorläufig')] },
  { title: '⑤ An ongoing window', note: 'The rule\'s last window has not recovered: „seit 23.10.2026 · läuft“ in the select, „Tief bisher … vorläufig“ in the window line, and one hint that the low and the lists move while the benchmark falls. „Im Depot ansehen“ works: the range ends today.', frames: [sized(f01e, 'laufend')] },
  { title: '⑥ The windows behind the disclosure', note: 'Newest first, the ongoing one marked; „erkannt“ muted, „manuell“ in the accent because its dates were chosen by a person; the longest gap in the benchmark\'s closes per window (§7.8). The rule line names the crash benchmark with „Ändern“ (board 02 ④) and „Fenster anlegen“. Below, the names without a window: one given for the current benchmark whose high moved, one given for a former benchmark that returns when it is chosen again (§3). P9: a name stores only the high\'s date, so „Als manuelles Fenster anlegen …“ opens a form with the low empty and required.', frames: [sized(f01c, 'Aufklapper offen'), sized(f01c2, 'Name ohne Fenster → manuell')] },
  { title: '⑦ No crash benchmark chosen', note: 'One data note (UX-DR17, „Hinweis“) with the link to choose one (board 02 ④). Manual windows still work; P8: their lists carry no reference line and no Pp. column, and the basis says so. With no manual window either, the section is the note and an empty state.', frames: [sized(f01d, 'nur manuelle Fenster'), sized(f01d2, 'gar kein Fenster')] },
  { title: '⑧ A window before the view\'s first day', note: 'P7: Bestände answers a range before its history with 1 year and the line „Der angefragte Zeitraum passt nicht zu den Daten“ (#1432), so the link would land on the wrong period. The section shows no link and says why; the lists still answer, because „Im Depot“ is today\'s holdings.', frames: [sized(f01i, 'vor der Ansicht')] },
  { title: '⑨ The phone (390 px), and the privacy mode', recommended: true, note: '<b>A (recommended, P5):</b> the bars stay; each entry is two lines, name and figure over the bar and the Pp. difference; the bar falls into its label column (DESIGN.md rule A). <b>B:</b> table rows without bars, denser, but the comparison with the benchmark is only a number. Flip: „Crashes am Handy als Tabelle“. <b>Privacy mode (FR-51):</b> nothing in the section changes. It hides amounts and quantities on the server; these lists hold percentages, dates and day counts only, which stay (<code>PortfolixirWeb.PrivacyMode</code>). „Im Depot ansehen“ opens Bestände, which hides its amounts there.', frames: [sized(f01f, 'A · Balken', true), sized(f01f2, 'B · Zeilen'), sized(f01g, 'A · Privatmodus an')] },
  { title: '⑩ Where the section sits', recommended: true, note: '<b>A (recommended, P1):</b> after „Kennzahlen des Portfolios“, whose „Max. Rückgang“ is the same notion on the view; the page then reads movement before concentration. <b>B:</b> last, after the caps: the existing sections keep their places, but the section that answers „what did the market\'s falls do“ sits under three that answer „how concentrated“. Flip: „Crashes ans Ende“.', frames: [sized(f01pA, 'A · nach den Kennzahlen', true), sized(f01pB, 'B · am Ende')] },
]);

// ===========================================================================
// Board 02 — the benchmark picker and the crash benchmark setting

const FLAGGED = ['Europa-Index ETF', 'Weltindex ETF'];
const HELD = ['Bitcoin', 'Dividenden-Fonds K', 'Europa-Aktien ETF', 'Gold ETC', 'Industrie-Einzelwert B', 'Reise-Einzelwert D', 'Schwellenländer ETF', 'Staatsanleihen ETF', 'Tech-Einzelwert A', 'USA-Aktien ETF', 'Versorger AG'];

const PICK_CSS = `
.bm-groups { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 12px; align-items: baseline; flex-basis: 100%; box-sizing: border-box; padding: 10px 12px; }
.bm-groups__label { font-size: 12.5px; font-weight: 600; color: var(--color-text-muted); }
.bm-groups__options { display: flex; flex-wrap: wrap; gap: 6px 14px; }
.bm-groups__options label { font-size: 13px; color: var(--color-text); }
.bm-search { display: flex; flex-direction: column; gap: 4px; position: relative; flex-basis: 100%; padding: 6px 0; }
.bm-search input { min-height: 30px; width: 20rem; font-size: 13px; padding-left: 28px; }
.bm-search > svg { position: absolute; left: 9px; top: 14px; color: var(--color-text-muted); }
.bm-search ul { position: absolute; top: 42px; left: 0; z-index: 5; list-style: none; margin: 0; padding: 4px; width: 20rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg-elevated); box-shadow: var(--shadow-md); font-size: 13px; }
.bm-search li { padding: 6px 8px; border-radius: 6px; }
.bm-search li:first-child { background: var(--color-hover); }
.bm-search li small { display: block; color: var(--color-text-muted); font-size: 11.5px; }
.bm-listbox { position: absolute; top: calc(100% + 4px); left: 0; z-index: 5; margin: 0; padding: 4px 0; width: 17rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg-elevated); box-shadow: var(--shadow-md); font-size: 13px; list-style: none; }
.bm-listbox li { padding: 4px 12px 4px 22px; }
.bm-listbox li.is-group { padding-left: 10px; font-weight: 700; color: var(--color-text-muted); font-size: 12px; }
.bm-listbox li.is-selected { background: var(--color-accent); color: var(--color-on-accent); }
.bm-stack { position: relative; }
.bm-listbox li { line-height: 1.35; }
.crash-benchmark-form { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 12px; align-items: center; padding: 12px 14px; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-bg-elevated); }
.crash-benchmark-form label { font-size: 12.5px; font-weight: 600; color: var(--color-text-muted); }
.crash-benchmark-form select { min-height: 30px; max-width: 18rem; font-size: 13px; justify-self: start; }
.crash-benchmark-form__actions { grid-column: 2; display: flex; gap: 8px; }
.crash-benchmark-form .hint { grid-column: 2; margin: 0; }
.settings-page .workspace-section { max-width: 760px; }
`;

const perfHead = (pickerBody, { activeChips = ['Weltindex ETF'] } = {}) => `<section class="workspace-section" id="portfolio-performance"><header class="section-head"><h2>Performance</h2><div class="section-head-controls"><div class="segmented-control" role="group" aria-label="Chartreihe"><button type="button" class="segmented-control__option is-active" aria-pressed="true">% (TTWROR)</button><button type="button" class="segmented-control__option" aria-pressed="false">Wert (EUR)</button></div><div class="segmented-control" role="group" aria-label="Zeitraum">${['YTD', '1J', '3J', '5J', 'Max'].map((p) => `<button type="button" class="segmented-control__option${p === '1J' ? ' is-active' : ''}">${p}</button>`).join('')}</div><details class="period-disclosure"><summary class="disclosure-summary">${icon('chevron_right', 12, 'disclosure-chevron')}Benutzerdefinierter Zeitraum …</summary></details><details class="period-disclosure" data-role="benchmark-picker" open><summary class="disclosure-summary">${icon('chevron_right', 12, 'disclosure-chevron')}Benchmark…<span class="benchmark-picker__active">${activeChips.map((c, i) => `<span class="benchmark-chip"><span class="chart-legend__swatch chart-benchmark-${i + 1}" aria-hidden="true"></span>${c}</span>`).join('')}</span></summary><form method="get" action="/portfolio" class="period-disclosure__body benchmark-form">${pickerBody}<label class="benchmark-form__rate" for="benchmark-rate">Fester Zins % p. a.</label><input type="number" id="benchmark-rate" name="benchmark_rate" step="0.01"><button type="submit">Anwenden</button><span class="hint">Bis zu zwei Benchmarks — die ersten beiden angekreuzten gelten.</span></form></details></div></header><p class="mock-elided" style="border:0;padding:0">… der Chart wie heute</p></section>`;

const checkbox = (n, checked = false) => `<label class="benchmark-form__option"><input type="checkbox" name="benchmark[]"${checked ? ' checked' : ''}>${n}</label>`;
const pickerBefore = FLAGGED.map((n) => checkbox(n, n === 'Weltindex ETF')).join('');
const groups = (held = HELD, checkedHeld = 'Europa-Aktien ETF') => `<div class="bm-groups mock-new"><span class="bm-groups__label">Benchmarks</span><span class="bm-groups__options">${FLAGGED.map((n) => checkbox(n, n === 'Weltindex ETF')).join('')}</span><span class="bm-groups__label">Im Bestand</span><span class="bm-groups__options">${held.map((n) => checkbox(n, n === checkedHeld)).join('')}</span></div>`;
const searchBox = `<div class="bm-search mock-new">${icon('search', 14)}<input type="search" value="Rohstoff" placeholder="Weiteres Wertpapier mit Kursen suchen …" aria-label="Weiteres Wertpapier mit Kursen suchen"><ul role="listbox"><li>Rohstoff-Index ETC<small>nicht im Bestand · Kurse seit 2015</small></li><li>Rohstoff-Aktien Fonds<small>nicht im Bestand · Kurse seit 2019</small></li></ul></div>`;

const f02a = writeFrame('02a-bestaende-heute', `<div class="workspace-page">${perfHead(pickerBefore)}</div>`, { width: 1000, css: PICK_CSS });
const f02b = writeFrame('02b-bestaende-neu', `<div class="workspace-page">${perfHead(groups(), { activeChips: ['Weltindex ETF', 'Europa-Aktien ETF'] })}</div>`, { width: 1000, css: PICK_CSS });
const f02c = writeFrame('02c-bestaende-suche', `<div class="workspace-page">${perfHead(groups() + searchBox, { activeChips: ['Weltindex ETF', 'Europa-Aktien ETF'] })}</div>`, { width: 1000, css: PICK_CSS });

// Sale hindsight: „Vergleich“ with a select of flagged securities only, and
// with optgroups (the native list drawn open beside it).
const hsControls = (listbox) => `<section class="workspace-section hs-section"><h2>Nach dem Verkauf</h2><div class="hs-controls" data-role="hindsight-compare"><span class="hs-controls__label" id="hs-compare-label">Vergleich</span><nav class="segmented-control" aria-labelledby="hs-compare-label">${['Ohne', 'Fester Zins', 'Wertpapier', 'Anschlusskauf'].map((m) => `<a class="segmented-control__option${m === 'Wertpapier' ? ' is-active' : ''}" href="#">${m}</a>`).join('')}</nav><div class="bm-stack"><form class="hs-controls__field"><label for="hs-benchmark" class="visually-hidden">Benchmark</label><select id="hs-benchmark" name="benchmark"><option selected>Weltindex ETF</option></select></form>${listbox}</div></div><p class="mock-elided" style="border:0;padding:0">… die Tabelle wie heute</p></section>`;
const listboxBefore = `<ul class="bm-listbox" aria-hidden="true">${FLAGGED.map((n) => `<li${n === 'Weltindex ETF' ? ' class="is-selected"' : ''}>${n}</li>`).join('')}</ul>`;
const listboxAfter = `<ul class="bm-listbox mock-new" aria-hidden="true"><li class="is-group">Benchmarks</li>${FLAGGED.map((n) => `<li${n === 'Weltindex ETF' ? ' class="is-selected"' : ''}>${n}</li>`).join('')}<li class="is-group">Im Bestand</li>${HELD.map((n) => `<li>${n}</li>`).join('')}</ul>`;
const f02d = writeFrame('02d-verkauf-heute', `<div class="workspace-page" style="min-height:250px">${hsControls(listboxBefore)}</div>`, { width: 720, css: PICK_CSS });
const f02e = writeFrame('02e-verkauf-neu', `<div class="workspace-page" style="min-height:520px">${hsControls(listboxAfter)}</div>`, { width: 720, css: PICK_CSS });

// The crash benchmark: A inline in the Crashes section's disclosure.
const cbSelect = (selected) => `<select id="crash-benchmark" name="crash_benchmark">${selected ? '' : '<option selected>— wählen —</option>'}<optgroup label="Benchmarks">${FLAGGED.map((n) => `<option${n === selected ? ' selected' : ''}>${n}</option>`).join('')}</optgroup><optgroup label="Im Bestand">${HELD.map((n) => `<option>${n}</option>`).join('')}</optgroup></select>`;
const cbForm = (selected, unset) => `<form class="crash-benchmark-form mock-new" id="crash-benchmark" data-role="crash-benchmark-form"><label for="crash-benchmark">Crash-Benchmark</label>${cbSelect(selected)}<div class="crash-benchmark-form__actions"><button type="submit" class="button-primary">Speichern</button><button type="button" class="button-ghost">Abbrechen</button></div><p class="hint">Gilt für diese Seite und jeden Agenten: alle lesen dieselben Fenster. Die Änderung steht im Audit-Journal.</p>${unset ? '' : '<p class="hint">Namen bleiben beim bisherigen Benchmark und kehren zurück, wenn du ihn wieder wählst.</p>'}</form>`;
const f02f = writeFrame('02f-crash-unset', `<div class="workspace-page">${crashSection(
  noteLine + `<details class="perf-table-disclosure crash-windows" open><summary class="disclosure-summary">${icon('chevron_right', 12, 'disclosure-chevron')}Crash-Fenster · 1 manuell</summary><div class="crash-windows__body">${cbForm(null, true)}<p class="mock-elided" style="border:0;padding:0">… die Fenstertabelle wie auf Board 01 ⑥</p></div></details>`,
  { mark: false },
)}</div>`, { width: 960, css: CRASH_CSS + PICK_CSS });
const f02g = writeFrame('02g-crash-aendern', `<div class="workspace-page">${crashSection(
  `<details class="perf-table-disclosure crash-windows" open><summary class="disclosure-summary">${icon('chevron_right', 12, 'disclosure-chevron')}Crash-Fenster · 6 erkannt · 1 manuell · 2 Namen ohne Fenster</summary><div class="crash-windows__body">${ruleLine(true)}${cbForm('Weltindex ETF', false)}<p class="mock-elided" style="border:0;padding:0">… die Fenstertabelle wie auf Board 01 ⑥</p></div></details>`,
  { mark: false },
)}</div>`, { width: 960, css: CRASH_CSS + PICK_CSS });

// B: a page „Einstellungen“ under Verwaltung.
const SETTINGS_NAV = (s) => s.replace(/(\n\s*<\/div>\s*\n\s*<\/nav>)/, `
            <a id="nav-settings" class="nav-link is-active mock-new" href="/settings" aria-current="page">
              <span class="nav-marker" aria-hidden="true"></span>
              <span class="nav-ico" aria-hidden="true">${icon('settings')}</span>
              <span class="nav-label">Einstellungen</span>
            </a>$1`);
const settingsPage = `<div class="workspace-page settings-page"><section class="workspace-section mock-new"><header class="section-head"><div class="section-title"><h2>Crashes</h2></div></header><form class="crash-benchmark-form" style="border:0;padding:0;background:none"><label for="crash-benchmark">Crash-Benchmark</label>${cbSelect('Weltindex ETF')}<div class="crash-benchmark-form__actions"><button type="submit" class="button-primary">Speichern</button></div><p class="hint">Die Regel erkennt Crash-Fenster in seinen Schlusskursen; sie stehen auf Vermögen › Risiko.</p></form></section><section class="workspace-section"><header class="section-head"><h2>Standardansicht</h2></header><p class="hint" style="margin:0">Alles · wird heute im Ansichtswähler gesetzt</p></section></div>`;
const f02h = writeFrame('02h-einstellungen', settingsPage, { shell: true, width: 1200, css: CRASH_CSS + PICK_CSS, title: 'Einstellungen', subtitle: 'Einstellungen dieser Instanz', active: null, extraNav: SETTINGS_NAV });

// ⑤ Added by the B2 build (#1416), drawn after it: the third group
// „Weitere“, as the built markup renders it. It appears only while the
// address names a quoted security that is neither flagged nor held (the API
// accepts it; an agent's link may carry one), so the picker shows what is
// compared (`PortfolixirWeb.BenchmarkChoices.with_chosen/2`). The markup is
// that of `portfolio_live.ex` (`bm-groups`) and `sale_hindsight_section.ex`
// (optgroups); the groups are drawn by the shipped app.css alone, so no
// `.bm-groups` rule from PICK_CSS enters these frames. Only the native
// select's open list (`.bm-listbox`, as ③ draws it) and the dashed mark on
// the new group are board CSS.
const OTHER = 'Rohstoff-Index ETC';
const ID = (n) => 101 + [...FLAGGED, ...HELD, OTHER].indexOf(n);
const BUILT_CSS = PICK_CSS.split('\n').filter((l) => /^\.bm-(listbox|stack)/.test(l)).join('\n') + `
.bm-groups #benchmark-group-other, .bm-groups [data-group="other"] { outline: 2px dashed var(--color-accent); outline-offset: 1px; border-radius: 4px; }
.bm-listbox li.mock-new { outline-offset: -2px; border-radius: 0; }
.mock-room { height: 560px; } /* room for the open list drawn below the select */
`;
const builtOption = (n, checked) => `<label class="benchmark-form__option"><input type="checkbox" name="benchmark[]" value="security:${ID(n)}"${checked ? ' checked' : ''}>${n}</label>`;
const builtGroups = (checked) => `<input type="hidden" name="benchmark[]" value=""><div class="bm-groups" data-role="benchmark-groups">${[
  ['flagged', 'Benchmarks', FLAGGED], ['held', 'Im Bestand', HELD], ['other', 'Weitere', [OTHER]],
].map(([key, label, names]) => `<span class="bm-groups__label" id="benchmark-group-${key}">${label}</span><span class="bm-groups__options" role="group" aria-labelledby="benchmark-group-${key}" data-group="${key}">${names.map((n) => builtOption(n, checked.includes(n))).join('')}</span>`).join('')}</div>`;
const holdingsWeitere = `<div class="workspace-page">${areaTabs('Bestände')}${perfHead(builtGroups(['Weltindex ETF', OTHER]), { activeChips: ['Weltindex ETF', OTHER] })}</div>`;
const HOLDINGS_SHELL = { shell: true, css: BUILT_CSS, title: 'Vermögen', subtitle: 'Wert, Performance und Allokation' };
const f02i = writeFrame('02i-weitere-bestaende-1200', holdingsWeitere, { ...HOLDINGS_SHELL, width: 1200 });
const f02j = writeFrame('02j-weitere-bestaende-390', holdingsWeitere, { ...HOLDINGS_SHELL, width: 390 });

// „Nach dem Verkauf“ on Cashflow › Trades, the address naming the same
// unheld security: the select shows it, in a third optgroup.
const builtSelect = `<select id="sale-hindsight-benchmark" name="benchmark">${[
  ['flagged', 'Benchmarks', FLAGGED], ['held', 'Im Bestand', HELD], ['other', 'Weitere', [OTHER]],
].map(([key, label, names]) => `<optgroup label="${label}" data-group="${key}">${names.map((n) => `<option value="${ID(n)}"${n === OTHER ? ' selected' : ''}>${n}</option>`).join('')}</optgroup>`).join('')}</select>`;
const listboxWeitere = `<ul class="bm-listbox" aria-hidden="true"><li class="is-group">Benchmarks</li>${FLAGGED.map((n) => `<li>${n}</li>`).join('')}<li class="is-group">Im Bestand</li>${HELD.map((n) => `<li>${n}</li>`).join('')}<li class="is-group mock-new">Weitere</li><li class="is-selected mock-new">${OTHER}</li></ul>`;
const facets = `<div class="workspace-section workspace-section--controls"><nav class="segmented-control" data-role="cashflow-facets" aria-label="Cashflow-Facette">${['Erträge', 'Trades', 'Ein- &amp; Auszahlungen', 'Kosten'].map((f) => `<a class="segmented-control__option${f === 'Trades' ? ' is-active' : ''}" href="#"${f === 'Trades' ? ' aria-current="true"' : ''}>${f}</a>`).join('')}</nav></div>`;
const saleWeitere = `<div class="workspace-page">${areaTabs('Cashflow')}${facets}<p class="mock-elided">Trades — unverändert</p><section id="sale-hindsight" class="hs-section workspace-section" data-role="sale-hindsight"><h2>Nach dem Verkauf</h2><div class="summary-basis hs-basis">Kursentwicklung je Verkauf in EUR · ab dem Verkaufstag · eine Zeile je Verkaufsbuchung <details class="metric-tooltip metric-tooltip--inline" data-role="hindsight-info"><summary aria-label="Zu diesem Abschnitt">ⓘ</summary><p role="tooltip">Wie sich das verkaufte Wertpapier nach dem Verkauf bewegt hat.</p></details></div><div class="hs-controls" data-role="hindsight-compare"><span class="hs-controls__label" id="sale-hindsight-compare-label">Vergleich</span><nav class="segmented-control" aria-labelledby="sale-hindsight-compare-label">${[['none', 'Ohne'], ['rate', 'Fester Zins'], ['security', 'Wertpapier'], ['reinvestment', 'Anschlusskauf']].map(([k, m]) => `<a class="segmented-control__option${k === 'security' ? ' is-active' : ''}" href="#"${k === 'security' ? ' aria-current="true"' : ''} data-mode="${k}">${m}</a>`).join('')}</nav><div class="bm-stack"><form id="sale-hindsight-benchmark-form" class="hs-controls__field" data-role="hindsight-benchmark-form"><label for="sale-hindsight-benchmark" class="visually-hidden">Benchmark</label>${builtSelect}</form>${listboxWeitere}</div></div><p class="mock-elided" style="border:0;padding:0">… die Tabelle wie heute, gegen ${OTHER}</p></section><div class="mock-room" aria-hidden="true"></div></div>`;
const SALE_SHELL = { shell: true, css: BUILT_CSS, title: 'Trades', subtitle: 'Abgeschlossene Trades und ihr realisiertes Ergebnis' };
const f02k = writeFrame('02k-weitere-verkauf-1200', saleWeitere, { ...SALE_SHELL, width: 1200 });
const f02l = writeFrame('02l-weitere-verkauf-390', saleWeitere, { ...SALE_SHELL, width: 390 });

// ⑥ The closing act (#1416, B2): at a phone's width (≤ 560 px) the label
// stands above its options with the grid's one gap of 4 px, so a group's
// label sits as close to the options of the group before it as to its own,
// and the three groups read as one list. After: a larger gap (--space-3)
// before every group label after the first. The markup is the built one
// (`portfolio_live.ex`); „vorher“ holds the gap as built, whatever app.css
// ships later, so the frame stays a before.
const GAP_BEFORE_CSS = BUILT_CSS + `
@media (max-width: 560px) { .bm-groups .bm-groups__label:not(:first-child) { margin-top: 0; } }
`;
const GAP_AFTER_CSS = BUILT_CSS + `
@media (max-width: 560px) { .bm-groups .bm-groups__label:not(:first-child) { margin-top: var(--space-3); outline: 2px dashed var(--color-accent); outline-offset: 2px; border-radius: 4px; } }
`;
const phonePicker = `<div class="workspace-page">${areaTabs('Bestände')}${perfHead(builtGroups(['Weltindex ETF', OTHER]), { activeChips: ['Weltindex ETF', OTHER] })}</div>`;
const f02m = writeFrame('02m-gruppen-390-vorher', phonePicker, { ...HOLDINGS_SHELL, css: GAP_BEFORE_CSS, width: 390 });
const f02n = writeFrame('02n-gruppen-390-nachher', phonePicker, { ...HOLDINGS_SHELL, css: GAP_AFTER_CSS, width: 390 });

board('02-benchmark-picker.html', 'Sprint 29 — Board 02: the benchmark picker and the crash benchmark (#1416, ADR-0046 amendment 2026-11-07, ADR-0058 §1)', 1260, `<div class="mock-pickbar">
<p><b>Decided:</b> every read that takes <code>benchmark=security:&lt;id&gt;</code> accepts any security with at least one stored quote, flagged or not; <code>is_benchmark</code> keeps its meaning (reference-only: not bookable, out of the data-quality sets) and is the picker's default content; the picker offers the flagged securities first and the held ones after them, and is built only after its board (ADR-0046, amendment of 2026-11-07, point 3; #1416). The crash benchmark is one instance setting, set through the API, its MCP tool and the screen, journaled, with no default; the Crashes section's „no benchmark“ line links to it (ADR-0058 §1).</p>
<p><b>Today the screen has two pickers</b>, both flagged-only (<code>Catalog.list_securities(is_benchmark: true)</code>): Bestände's „Benchmark…“ disclosure (<code>portfolio_live.ex</code>) and „Nach dem Verkauf“'s select, on Cashflow and on a security's Trades tab (<code>sale_hindsight_section.ex</code>). Predictions take their benchmark over the API only. Both screens also resolve a chosen id against the flag (<code>resolve_benchmark_security/1</code> in <code>portfolio_live.ex</code>, the flagged list in <code>sale_hindsight_section.ex</code>), so a held security ticked in the new picker would fall back to „not selected“ unless the story changes those resolvers with the picker. No settings page exists; the one instance setting with a screen, the default view, is set where it acts (the view switcher).</p>
<p><b>Proposed here:</b> Q1 both pickers show two labelled groups, „Benchmarks“ then „Im Bestand“ (held today in any depot, with a stored quote, by name), no search (A); Q2 the crash benchmark is chosen inline, in the Crashes section's window disclosure, with the same two groups (A). Dashed outline: new.</p>
</div>`, [
  { title: '① Bestände: „Benchmark…“ today and as proposed', recommended: true, note: '<b>Today:</b> the flagged securities only. <b>A (recommended, Q1):</b> two groups, each label in one column and its options from one edge (DESIGN.md, „Labelled controls start on one edge“): the flagged ones first, then every security held today with a stored quote, by name. A held security used as the benchmark stays bookable and stays in every check, because it is not flagged. A held security without a stored quote is not offered: the API would refuse it with 422.', frames: [sized(f02a, 'heute'), sized(f02b, 'A · Benchmarks, dann Im Bestand', true)] },
  { title: '② Variant B: plus a search over every security with quotes', note: '<b>B:</b> A and a search for any catalogue security with stored quotes, held or not, which the API accepts since the amendment. Not recommended: the amendment names flagged and held; an unheld reference series is what the flag is for (flag it on Wertpapiere and it appears under „Benchmarks“), and a search turns a short choice into the catalogue. Flip: „Benchmark-Suche“.', frames: [sized(f02c, 'B · mit Suche')] },
  { title: '③ „Nach dem Verkauf“: the select today and as proposed', recommended: true, note: 'The same two groups as <code>&lt;optgroup&gt;</code>s of the native select (drawn open beside it, as a browser shows it). Its default stays the first flagged security, as today.', frames: [sized(f02d, 'heute'), sized(f02e, 'A · zwei Gruppen', true)] },
  { title: '④ Where the crash benchmark is chosen: inline (A) or a settings page (B)', recommended: true, note: '<b>A (recommended, Q2):</b> in the Crashes section. Unset, the data note\'s „Crash-Benchmark wählen“ opens the windows disclosure with the form; set, the rule line\'s „Ändern“ opens it. The select carries the same two groups; „Speichern“ writes the setting through the API\'s path, journaled under the operator. The hints say what the setting means for agents and what happens to names (§3). <b>B:</b> a new page „Einstellungen“ under Verwaltung, where later instance settings could gather (the news clustering\'s two values are API-only today). Not recommended now: one setting does not make a page, the operator meets the question where the crashes are, and the default view set in place is the precedent. Flip: „Einstellungsseite“.', frames: [sized(f02f, 'A · noch kein Crash-Benchmark', true), sized(f02g, 'A · ändern', true), sized(f02h, 'B · Einstellungen')] },
  { title: '⑤ B2 — die Gruppe „Weitere“ (added by the build)', note: '<b>Found while building Q1 A, drawn before the sprint PR lands:</b> a link may name a quoted security that is neither flagged nor held (the API accepts it since the amendment; an agent\'s link may carry one). The built pickers compare it, and show it in a third group, „Weitere“, after „Benchmarks“ and „Im Bestand“, so the picker never shows one security while comparing another, and applying the form again keeps it (<code>PortfolixirWeb.BenchmarkChoices.with_chosen/2</code>). The group is there only while such a security is chosen: untick it and apply, or pick another in the select, and it is gone; it is never a way to find one (variant B\'s search stays off). Drawn as the build renders it, with the shipped app.css: the label column at 1200 px, the label above its options on a phone (≤ 560 px). The select\'s open list is drawn beside it, as in ③. Dashed: the new group. Flip: „Ohne Gruppe Weitere“ — the picker then drops a security it does not offer, as before.', frames: [sized(f02i, 'Bestände · 1200 px'), sized(f02j, 'Bestände · 390 px'), sized(f02k, 'Nach dem Verkauf · 1200 px'), sized(f02l, 'Nach dem Verkauf · 390 px')] },
  { title: '⑥ The groups at 390 px (the closing act)', recommended: true, note: '<b>Found by the closing act:</b> on a phone (≤ 560 px) each label stands above its options, and the grid\'s one gap of 4 px also separates a group from the next label, so „Im Bestand“ and „Weitere“ read as the last lines of the group before them. <b>After (recommended):</b> a larger gap (<code>--space-3</code>) before every group label after the first, so each label starts its group; at 1200 px the label column is unchanged. Dashed: the labels that move. The order the boxes are applied in is unchanged by this frame: „Anwenden“ keeps the address\'s order for boxes already chosen and appends the newly ticked ones, so the chips keep their colours.', frames: [sized(f02m, 'vorher · 390 px'), sized(f02n, 'nachher · 390 px', true)] },
]);

console.log('wrote frames/01*.html, frames/02*.html, 01-crash-section.html and 02-benchmark-picker.html');
