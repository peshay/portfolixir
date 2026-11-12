// Renders the Sprint 29 boards 01 and 02 to PNG at 1x, light and dark, then
// reduces each to a 256-colour palette when python3 with Pillow is available.
// First builds once and measures every frame at the width its board gives it,
// then rebuilds with the measured heights (passed in FRAME_SIZES, so no sizes
// file is shared with the other boards in this folder) and renders.
// Usage: node render-a.js [board ...]
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
const BOARDS = ['01-crash-section', '02-benchmark-picker'];
const FRAMES = path.join(__dirname, 'frames');
const WIDTH = { '01-crash-section': 1310, '02-benchmark-picker': 1310 };
const BUILD = path.join(__dirname, 'build-a.js');

(async () => {
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const only = process.argv.slice(2);
  const boards = only.length ? BOARDS.filter((b) => only.includes(b)) : BOARDS;
  execFileSync(process.execPath, [BUILD], { stdio: 'inherit' });
  const browser = await chromium.launch(launch);

  // 1. Measure every frame of both boards at the width its board gives it.
  const widths = {};
  for (const b of BOARDS) {
    const html = fs.readFileSync(path.join(__dirname, b + '.html'), 'utf8');
    for (const m of html.matchAll(/<iframe src="frames\/([^"]+)" width="(\d+)"/g)) widths[m[1]] = Number(m[2]);
  }
  const sizes = {};
  for (const [file, width] of Object.entries(widths)) {
    const page = await browser.newPage({ viewport: { width, height: 100 }, deviceScaleFactor: 1, locale: 'de-DE' });
    await page.goto('file://' + path.join(FRAMES, file), { waitUntil: 'load' });
    await page.waitForTimeout(150);
    // A frame with the shell is as tall as its content, not the viewport.
    sizes[file] = await page.evaluate(() => {
      const shell = document.querySelector('.app-frame');
      const h = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
      if (!shell) return h;
      const main = document.querySelector('main');
      // The sidebar's foot (the version) sits at 100vh: give the sidebar's
      // own entries and its foot room, else it is cut.
      const nav = document.querySelector('.primary-nav');
      const navBottom = nav && nav.offsetParent ? nav.getBoundingClientRect().bottom + 90 : 0;
      return Math.ceil(Math.max(main.getBoundingClientRect().bottom + 24, navBottom, 360));
    });
    await page.close();
  }
  execFileSync(process.execPath, [BUILD], { stdio: 'inherit', env: { ...process.env, FRAME_SIZES: JSON.stringify(sizes) } });

  // 2. Render each board in both themes, the theme set in every frame too.
  const page = await browser.newPage({ viewport: { width: 1310, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
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
