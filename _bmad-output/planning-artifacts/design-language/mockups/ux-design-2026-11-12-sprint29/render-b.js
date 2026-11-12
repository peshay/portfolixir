// Renders boards 03 to 06 to PNG at 1x, light and dark, then reduces each
// to a 256-colour palette when python3 with Pillow is available. First
// measures every frame at its width and writes frames/sizes-b.json, so
// build-b.js gives each <iframe> its real height; then rebuilds and renders.
// Usage: node build-b.js && node render-b.js [board ...]
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
const BOARDS = ['03-research-entry', '04-dq-held-first', '05-translucent-bands', '06-control-bar'];
const FRAMES = path.join(__dirname, 'frames');
const WIDTH = { '03-research-entry': 1310, '04-dq-held-first': 1090, '05-translucent-bands': 1090, '06-control-bar': 1150 };

(async () => {
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const browser = await chromium.launch(launch);
  const only = process.argv.slice(2);
  const boards = only.length ? BOARDS.filter((b) => only.includes(b)) : BOARDS;

  // 1. Measure every frame at the width the board gives it.
  const widths = {};
  for (const b of boards) {
    const html = fs.readFileSync(path.join(__dirname, b + '.html'), 'utf8');
    for (const m of html.matchAll(/<iframe src="frames\/([^"]+)" width="(\d+)"/g)) widths[m[1]] = Number(m[2]);
  }
  let sizes = {};
  try { sizes = JSON.parse(fs.readFileSync(path.join(FRAMES, 'sizes-b.json'), 'utf8')); } catch (e) { /* none yet */ }
  for (const [file, width] of Object.entries(widths)) {
    const page = await browser.newPage({ viewport: { width, height: 100 }, deviceScaleFactor: 1, locale: 'de-DE' });
    await page.goto('file://' + path.join(FRAMES, file), { waitUntil: 'load' });
    await page.waitForTimeout(150);
    sizes[file] = await page.evaluate(() => Math.max(document.documentElement.scrollHeight, document.body.scrollHeight));
    await page.close();
  }
  fs.writeFileSync(path.join(FRAMES, 'sizes-b.json'), JSON.stringify(sizes, null, 1) + '\n');
  execFileSync(process.execPath, [path.join(__dirname, 'build-b.js')], { stdio: 'inherit' });

  // 2. Render each board in both themes, the theme set in every frame too.
  const page = await browser.newPage({ viewport: { width: 1300, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
  const written = [];
  for (const board of boards) {
    for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width: WIDTH[board], height: 900 });
      await page.goto('file://' + path.join(__dirname, board + '.html'), { waitUntil: 'load' });
      for (const f of page.frames()) await f.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
      const full = await page.evaluate(() => document.documentElement.scrollHeight);
      await page.setViewportSize({ width: WIDTH[board], height: full });
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
