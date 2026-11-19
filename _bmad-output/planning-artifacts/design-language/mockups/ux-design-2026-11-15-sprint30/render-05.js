// Board 05, drawn in Sprint 30's closing act after CI: the window's select
// on Vermögen › Risiko › Crashes, before and after it takes the room it is
// given instead of a fixed 20.5rem cap (board 05's head says why).
//
// Writes frames/05*.html and 05-crash-select-width.html, then serves this
// repository on a loopback port (the frames link the real
// priv/static/app.css, whose @font-face rules load the app's own Inter from
// /fonts/, served from priv/static/fonts/), measures each frame's select
// (frames/05-probes.json), and renders the board at 1x in both themes,
// reduced to 256 colours when python3 with Pillow is available.
//
// Render it in the Chromium CI's browser job runs, Playwright 1.65.0's
// headless shell (revision 1254): it lays the app's Inter out in
// whole-pixel advances, where the full browser does not, and the "before"
// frame is cut there only.
//
// Usage: node render-05.js
// (PLAYWRIGHT_CHROMIUM_EXECUTABLE names a Chromium of the machine's own.)
// Synthetic data only: the windows are the crash walk's
// (test/browser/crash_section_layout_test.exs).
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');

const DIR = __dirname;
const FRAMES = path.join(DIR, 'frames');
const ROOT = path.resolve(DIR, '../../../../..');
const BOARD = '05-crash-select-width';
const WIDTH = 2060;

const WINDOWS = [
  'Synthetic war leg drawn by hand over a long stretch of the bear market · 23.02.2022–07.03.2022 · manuell',
  'Synthetic dip · 15.08.2022–29.08.2022 · manuell',
  'Ohne Namen · 03.01.2022–12.10.2022'
];
const SELECTED = 1;

// The bar as `PortfolixirWeb.ControlBar.bar/1` and crash_section.ex draw
// it (the German page), its window select on the short manual window.
const bar = () => `<div class="control-bar control-bar--fold-900 control-bar--floor-330 crash-bar" data-role="crash-bar">
<div class="control-bar__controls">
<form class="control-bar__group" id="crash-window-form">
<label class="control-bar__label" for="crash-window">Fenster</label>
<select id="crash-window" name="crash">
${WINDOWS.map((w, i) => `<option${i === SELECTED ? ' selected' : ''}>${w}</option>`).join('\n')}
</select>
</form>
<span class="control-bar__group">
<span class="control-bar__label" id="crash-list-label">Liste</span>
<div class="segmented-control" data-role="crash-list" role="group" aria-labelledby="crash-list-label">
<a class="segmented-control__option is-active" href="#">Verlierer</a>
<a class="segmented-control__option" href="#">Gewinner</a>
<a class="segmented-control__option" href="#">Erholer</a>
</div></span>
<span class="control-bar__group">
<span class="control-bar__label" id="crash-universe-label">Wertpapiere</span>
<div class="segmented-control" data-role="crash-universe" role="group" aria-labelledby="crash-universe-label">
<a class="segmented-control__option" href="#">Im Depot</a>
<a class="segmented-control__option is-active" href="#">Ganzer Katalog</a>
</div></span>
</div>
</div>`;

// Each frame states its rule in its own <style id="rule">, so the board
// draws the same before and after the fix lands in app.css: "before" the
// fixed cap, "after" the room the select is given.
const BEFORE = '.crash-bar select { max-width: 20.5rem; }';
const AFTER = '.crash-bar select { max-width: 100%; }';
const DEJAVU = ':root, :root[data-theme] { --font-sans: "DejaVu Sans" !important; }';

// A frame for a W px window is W less the 220 px menu wide, the section's
// padding pinned to the 2.4vw it has there.
const FRAME_LIST = [
  { file: '05a-1200-heute.html', window: 1200, css: BEFORE },
  { file: '05b-1200-neu.html', window: 1200, css: AFTER },
  { file: '05c-1100-heute.html', window: 1100, css: BEFORE },
  { file: '05d-1100-neu.html', window: 1100, css: AFTER },
  { file: '05e-1200-dejavu-heute.html', window: 1200, css: BEFORE + DEJAVU },
  { file: '05f-1200-dejavu-neu.html', window: 1200, css: AFTER + DEJAVU }
];

function writeFrame({ file, window, css }) {
  const width = window - 220;
  const pad = Math.round(window * 0.024 * 10) / 10;
  const doc = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${file.replace(/\.html$/, '')}</title>
<link rel="stylesheet" href="../../../../../../priv/static/app.css">
<style id="frame">
body { margin: 0; background: var(--color-bg); }
.workspace-section { padding: ${pad}px; }
</style>
<style id="rule">${css}</style>
</head>
<body><div style="width: ${width}px">
<section class="crash-section workspace-section" id="risk-crashes">
${bar()}
</section>
</div></body>
</html>
`;
  fs.writeFileSync(path.join(FRAMES, file), doc);
}

// The board: the head, then one row per comparison.
const fig = (tag, label, file, width, height) =>
  `<figure class="mock-fig"><span class="mock-tag"><b>${tag}</b>${label}</span><div class="mock-frame"><iframe src="frames/${file}" width="${width}" height="${height}" title="${file}"></iframe></div></figure>`;

function writeBoard(p) {
  const w = (f) => p[f] && p[f].select;
  const n = (v) => String(v).replace('.', ',');
  const h = (f) => (p[f] ? p[f].height : 120);
  const doc = `<!doctype html>
<html lang="de" data-theme="light" data-accent="violet">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Sprint 30 · Crashes — die Auswahl des Fensters</title>
<link rel="stylesheet" href="../../../../../priv/static/app.css">
<!-- Written by render-05.js. Each frame under frames/ is a static page that
     links app.css; the block below is artboard chrome only. No script runs
     here. Synthetic data only. -->
<style id="board">
body { margin: 0; padding: 24px; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); }
.mock-board { max-width: 2010px; margin: 0 auto 28px; }
.mock-head h1 { margin: 0 0 6px; font-size: 22px; }
.mock-head p { max-width: 150ch; font-size: 13px; line-height: 1.55; }
.mock-board > h2 { margin: 0 0 4px; font-size: 17px; font-weight: 760; }
.mock-board > h2 small { font-size: 12px; font-weight: 700; color: var(--color-accent); background: var(--color-accent-soft); padding: 2px 8px; border-radius: 999px; margin-left: 6px; vertical-align: 2px; }
p.mock-note { margin: 0 0 12px; max-width: 150ch; font-size: 13px; color: var(--color-text-muted); line-height: 1.5; }
.mock-row { display: flex; gap: 24px; align-items: flex-start; flex-wrap: wrap; }
.mock-fig { margin: 0; }
.mock-tag { display: block; max-width: 980px; margin: 0 0 6px; font-size: 12px; font-weight: 600; color: var(--color-text-muted); }
.mock-tag b { display: inline-block; margin-right: 6px; padding: 1px 9px; border-radius: 999px; font-size: 11px; font-weight: 700; letter-spacing: .05em; text-transform: uppercase; background: var(--color-bg-muted); color: var(--color-text-muted); }
.mock-frame { width: max-content; border: 1px solid var(--color-border-strong); border-radius: 10px; overflow: hidden; box-shadow: var(--shadow-panel); background: var(--color-bg); }
.mock-frame iframe { display: block; border: 0; }
</style>
</head>
<body>
<div class="mock-board mock-head"><h1>Sprint 30 · Vermögen › Risiko, Crashes: die Auswahl des Fensters</h1>
<p><strong>Anlass:</strong> der Browser-Job von CI nach F1 (die App liefert Inter) und M1 (Playwright 1.65.0). Der Rundgang <code>crash_section_layout.js</code> verlangt, dass ein manuelles Fenster mit kurzem Namen bei 1200 px ganz in der Auswahl steht (Board 06 ⑫ von Sprint 29). Die Auswahl war auf 20,5rem (328 px) begrenzt; „Synthetic dip · 15.08.2022–29.08.2022 · manuell“ brauchte 325 px, 3 px Luft. Die Headless-Shell von Playwright 1.65 (Chromium-Revision 1254, die CI startet) setzt die ausgelieferte variable Inter in ganzen Pixeln je Zeichen: dort braucht derselbe Text 332 px und wird gekürzt. Der Rundgang bleibt, wie er ist.</p>
<p><strong>Neu:</strong> keine feste Obergrenze; die Auswahl ist so breit wie ihre längste Option, höchstens so breit wie der Platz, den sie bekommt. Auf der einen Zeile ist das der Rest der Zeile, den die Gruppe „Fenster“ seit Board 06 ⑮ schon nimmt (von 16rem bis zu ihrer eigenen Breite), in der Labelspalte und unter 560 px die Spalte. Die Zeile bricht weiter an den 16rem der Gruppe um, nie an der Auswahl; Falz 900 und Boden 330 bleiben. Gemessen in diesem Chromium: bei 1200 px ${n(w('05a-1200-heute.html'))} → ${n(w('05b-1200-neu.html'))} px Auswahl, der kurze Name braucht ${n(p.needed)} px (${n(Math.round((w('05b-1200-neu.html') - p.needed) * 10) / 10)} px Luft statt ${n(Math.round((w('05a-1200-heute.html') - p.needed) * 10) / 10)}). Im Rundgang: 332 in 357 px (Revision 1254, Headless-Shell), 325 in 356,7 px (Revision 1243).</p>
<p><strong>Umkehrbar per Kommentar:</strong> „Crashes-Auswahl in der Labelspalte bis 20,5rem“ (② wie heute; der kurze Name bleibt dort in Revision 1254 gekürzt).</p></div>

<section class="mock-board">
  <h2>① 1200 px, Inter: eine Zeile, 924 px Leiste <small>empfohlen</small></h2>
  <p class="mock-note">Heute endet die Zeile ${n(p['05a-1200-heute.html'] && p['05a-1200-heute.html'].lineEnd)} px vor der Leiste, und die Auswahl kürzt den kurzen Namen an ihrer Obergrenze. Neu nimmt sie den Rest der Zeile; die längste Option, das lange manuelle Fenster, ist breiter als der Rest, also endet die Zeile an der Leiste. Ein Name, der auch dort nicht passt, wird gekürzt; die geöffnete Liste zeigt ihn ganz.</p>
  <div class="mock-row">${fig('Heute', 'Auswahl bis 20,5rem: „… · manuel“', '05a-1200-heute.html', 980, h('05a-1200-heute.html'))}${fig('Neu', 'Auswahl bis zum Rest der Zeile: „… · manuell“', '05b-1200-neu.html', 980, h('05b-1200-neu.html'))}</div>
</section>

<section class="mock-board">
  <h2>② 1100 px, Inter: die Labelspalte (A), 828 px Leiste <small>empfohlen</small></h2>
  <p class="mock-note">Unter dem Falz 900 steht jedes Feld in der Spalte nach den Labels, in seiner eigenen Breite. Heute schneidet die Obergrenze auch hier bei 328 px ab, obwohl die Spalte Platz hat; neu ist die Auswahl so breit wie ihre längste Option (${n(w('05d-1100-neu.html'))} px), wie sie es unter 560 px schon war.</p>
  <div class="mock-row">${fig('Heute', 'bis 20,5rem', '05c-1100-heute.html', 880, h('05c-1100-heute.html'))}${fig('Neu', 'bis zur Spalte', '05d-1100-neu.html', 880, h('05d-1100-neu.html'))}</div>
</section>

<section class="mock-board">
  <h2>③ 1200 px, DejaVu Sans, die Ersatzschrift: unverändert</h2>
  <p class="mock-note">In DejaVu Sans ist die Zeile schon heute voll (Board 06 ⑮): die Gruppe „Fenster“ bekommt nur den Rest, die Auswahl ${n(w('05e-1200-dejavu-heute.html'))} px; neu ${n(w('05f-1200-dejavu-neu.html'))} px. Der kurze Name bleibt dort gekürzt, solange die Zeile voll ist, wie der Rundgang es erlaubt.</p>
  <div class="mock-row">${fig('Heute', 'DejaVu Sans', '05e-1200-dejavu-heute.html', 980, h('05e-1200-dejavu-heute.html'))}${fig('Neu', 'DejaVu Sans', '05f-1200-dejavu-neu.html', 980, h('05f-1200-dejavu-neu.html'))}</div>
</section>
</body>
</html>
`;
  fs.writeFileSync(path.join(DIR, BOARD + '.html'), doc);
}

// This repository over HTTP: /fonts/* from priv/static/fonts, the rest
// from the root, so app.css's `url("/fonts/…")` loads the app's Inter.
function serve() {
  const types = { '.html': 'text/html', '.css': 'text/css', '.woff2': 'font/woff2', '.png': 'image/png', '.svg': 'image/svg+xml' };
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    p = p.startsWith('/fonts/') ? path.join(ROOT, 'priv/static', p) : path.join(ROOT, p);
    if (!p.startsWith(ROOT) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, { 'content-type': types[path.extname(p)] || 'application/octet-stream' });
    fs.createReadStream(p).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

(async () => {
  fs.mkdirSync(FRAMES, { recursive: true });
  FRAME_LIST.forEach(writeFrame);
  writeBoard({});
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}/` + path.relative(ROOT, DIR).split(path.sep).join('/') + '/';
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const browser = await chromium.launch(launch);
  const ctx = await browser.newContext({ deviceScaleFactor: 1, locale: 'de-DE' });

  // 1. Each frame: its height, the select's width, where the line ends,
  //    and what the short window needs (a copy of the select holding it
  //    alone, uncapped, as the walk measures it).
  const probes = {};
  for (const f of FRAME_LIST) {
    const page = await ctx.newPage();
    await page.setViewportSize({ width: f.window - 220, height: 40 });
    await page.goto(base + 'frames/' + f.file, { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    probes[f.file] = await page.evaluate((selected) => {
      const round = (v) => Math.round(v * 10) / 10;
      const select = document.getElementById('crash-window');
      const probe = select.cloneNode(false);
      probe.removeAttribute('id');
      probe.style.cssText = 'max-width: none; width: auto; position: absolute; visibility: hidden;';
      probe.appendChild(new Option(select.options[selected].text));
      select.parentElement.appendChild(probe);
      const needed = probe.getBoundingClientRect().width;
      probe.remove();
      const bar = document.querySelector('.crash-bar').getBoundingClientRect();
      const last = document.querySelector('[data-role=crash-universe]').getBoundingClientRect();
      return {
        height: Math.ceil(document.documentElement.scrollHeight),
        select: round(select.getBoundingClientRect().width),
        needed: round(needed),
        lineEnd: round(bar.right - last.right),
        inter: document.fonts.check('12.5px Inter') && [...document.fonts].some((x) => x.family.replace(/"/g, '') === 'Inter' && x.status === 'loaded')
      };
    }, SELECTED);
    await page.close();
  }
  probes.needed = probes['05b-1200-neu.html'].needed;
  probes.browser = browser.version();
  fs.writeFileSync(path.join(FRAMES, '05-probes.json'), JSON.stringify(probes, null, 1) + '\n');
  writeBoard(probes);

  // 2. The board in both themes, the theme set in every frame too.
  const page = await ctx.newPage();
  const written = [];
  for (const theme of ['light', 'dark']) {
    await page.setViewportSize({ width: WIDTH, height: 900 });
    await page.goto(base + BOARD + '.html', { waitUntil: 'load' });
    for (const f of page.frames()) await f.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
    for (const f of page.frames()) await f.evaluate(() => document.fonts.ready);
    const full = await page.evaluate(() => document.documentElement.scrollHeight);
    await page.setViewportSize({ width: WIDTH, height: full });
    await page.waitForTimeout(300);
    const png = path.join(DIR, `${BOARD}--${theme}.png`);
    await page.screenshot({ path: png, fullPage: true });
    written.push(png);
    console.log('rendered ' + path.basename(png));
  }
  await browser.close();
  server.close();
  try {
    const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
    execFileSync('python3', ['-c', QUANTIZE, ...written]);
    console.log('reduced to 256 colours');
  } catch (e) {
    console.log('left at full colour (python3 with Pillow not found)');
  }
})();
