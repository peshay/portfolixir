// Renders the Sprint 30 boards to PNG at 1x, light and dark, then reduces
// each to a 256-colour palette when python3 with Pillow is available.
//
// First it measures every frame at the width its board gives it and writes
// frames/sizes.json (each <iframe>'s height) and frames/probes.json (the
// figures the boards quote: table widths, row heights, the stacked chart's
// gutter), then rebuilds the boards with them and renders.
//
// Board 03's Inter frames load the shipped face from frames/inter/, which
// is not in the repository: this script serves it there from the npm
// packages @fontsource-variable/inter and @fontsource/inter 5.3.0 (SIL Open
// Font License 1.1), unpacked into INTER_DIR, by default a directory under
// the system's temporary directory, fetched with `npm pack` when missing.
// It writes the measured file sizes to font-sizes.json.
//
// Usage: node build.js && node render.js [board ...]
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
const BOARDS = ['01-axis-start', '02-wealth-polish', '03-shipped-font'];
const WIDTH = 2060;
const FRAMES = path.join(__dirname, 'frames');

// The two font packages, unpacked once.
const INTER_DIR = process.env.INTER_DIR || path.join(os.tmpdir(), 'portfolixir-board-inter-5.3.0');
function fontFiles() {
  const dirs = { variable: '@fontsource-variable/inter@5.3.0', static: '@fontsource/inter@5.3.0' };
  const out = {};
  for (const [k, pkg] of Object.entries(dirs)) {
    const dir = path.join(INTER_DIR, k);
    if (!fs.existsSync(path.join(dir, 'package', 'files'))) {
      fs.mkdirSync(dir, { recursive: true });
      const tgz = execFileSync('npm', ['pack', pkg, '--silent'], { cwd: dir }).toString().trim().split('\n').pop();
      execFileSync('tar', ['-xzf', tgz], { cwd: dir });
    }
    out[k] = path.join(dir, 'package', 'files');
  }
  return out;
}
const FONT_FILES = ['inter-latin-wght-normal.woff2', 'inter-latin-ext-wght-normal.woff2',
  ...[400, 600, 700].flatMap((w) => [`inter-latin-${w}-normal.woff2`, `inter-latin-ext-${w}-normal.woff2`])];

// In a frame: the figures the boards quote.
function probeFrame() {
  const r = { height: Math.max(document.documentElement.scrollHeight, document.body.scrollHeight) };
  r.tables = [...document.querySelectorAll('.data-table-wrapper')].filter((w) => w.offsetParent).map((w) => ({ scroll: w.scrollWidth, client: w.clientWidth }));
  const rows = document.querySelectorAll('#holdings-positions-table tbody tr.mock-keep');
  if (rows.length) r.rows = [...rows].map((tr) => Math.round(tr.getBoundingClientRect().height));
  const svg = document.querySelector('.stack-chart');
  if (svg) {
    const box = svg.getBoundingClientRect();
    const k = box.width / 960;
    const x1 = Number(svg.querySelector('.chart-axes line').getAttribute('x1'));
    const labels = [...svg.querySelectorAll('.chart-axis-y')].map((t) => t.getBoundingClientRect());
    r.svgWidth = Math.round(box.width);
    r.gutterPx = Math.round(x1 * k);
    r.labelWidth = Math.round(Math.max(...labels.map((b) => b.width)));
    r.labelLeft = Math.round(Math.min(...labels.map((b) => b.left - box.left)));
    r.labelRight = Math.round(Math.max(...labels.map((b) => b.right - box.left)));
  }
  return r;
}

(async () => {
  const files = fontFiles();
  const sizes = {};
  for (const f of FONT_FILES) {
    const p = [files.variable, files.static].map((d) => path.join(d, f)).find((q) => fs.existsSync(q));
    if (p) sizes[f] = fs.statSync(p).size;
  }
  fs.writeFileSync(path.join(__dirname, 'font-sizes.json'), JSON.stringify(sizes, null, 1) + '\n');

  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const browser = await chromium.launch(launch);
  const ctx = await browser.newContext({ deviceScaleFactor: 1, locale: 'de-DE' });
  await ctx.route('**/frames/inter/*.woff2', (route) => {
    const name = path.basename(new URL(route.request().url()).pathname);
    const p = [files.variable, files.static].map((d) => path.join(d, name)).find((q) => fs.existsSync(q));
    return p ? route.fulfill({ path: p, contentType: 'font/woff2' }) : route.abort();
  });
  const only = process.argv.slice(2);
  const boards = only.length ? BOARDS.filter((b) => only.includes(b)) : BOARDS;

  // 1. Measure every frame at the width its board gives it.
  const widths = {};
  for (const b of BOARDS) {
    const html = fs.readFileSync(path.join(__dirname, b + '.html'), 'utf8');
    for (const m of html.matchAll(/<iframe src="frames\/([^"]+)" width="(\d+)"/g)) widths[m[1]] = Number(m[2]);
  }
  const frameSizes = {}, probes = {};
  for (const [file, width] of Object.entries(widths)) {
    const page = await ctx.newPage();
    await page.setViewportSize({ width, height: 40 });
    await page.goto('file://' + path.join(FRAMES, file), { waitUntil: 'load' });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    probes[file] = await page.evaluate(probeFrame);
    frameSizes[file] = probes[file].height;
    await page.close();
  }
  fs.writeFileSync(path.join(FRAMES, 'sizes.json'), JSON.stringify(frameSizes, null, 1) + '\n');
  fs.writeFileSync(path.join(FRAMES, 'probes.json'), JSON.stringify(probes, null, 1) + '\n');
  execFileSync(process.execPath, [path.join(__dirname, 'build.js')], { stdio: 'inherit' });

  // 2. Render each board in both themes, the theme set in every frame too.
  const page = await ctx.newPage();
  const written = [];
  for (const board of boards) {
    for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width: WIDTH, height: 900 });
      await page.goto('file://' + path.join(__dirname, board + '.html'), { waitUntil: 'load' });
      for (const f of page.frames()) await f.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
      for (const f of page.frames()) await f.evaluate(() => document.fonts.ready);
      const full = await page.evaluate(() => document.documentElement.scrollHeight);
      await page.setViewportSize({ width: WIDTH, height: full });
      await page.waitForTimeout(400);
      const png = path.join(__dirname, `${board}--${theme}.png`);
      await page.screenshot({ path: png, fullPage: true });
      written.push(png);
      console.log('rendered ' + path.basename(png));
    }
  }
  await browser.close();
  try {
    execFileSync('python3', ['-c', QUANTIZE, ...written]);
    console.log('reduced to 256 colours');
  } catch (e) {
    console.log('left at full colour (python3 with Pillow not found)');
  }
})();
