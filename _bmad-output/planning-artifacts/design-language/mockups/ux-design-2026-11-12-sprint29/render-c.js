// Renders the Sprint 29 board 07 to PNG at 1x, light and dark, then reduces
// each to a 256-colour palette when python3 with Pillow is available.
// First builds once and measures every frame at the width the board gives
// it, then rebuilds with the measured heights (passed in FRAME_SIZES_C, so no
// sizes file is shared with the other boards in this folder) and renders.
// Usage: node render-c.js
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
const BOARD = '07-cycle-states';
const FRAMES = path.join(__dirname, 'frames');
const WIDTH = 1310;
const BUILD = path.join(__dirname, 'build-c.js');

(async () => {
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  execFileSync(process.execPath, [BUILD], { stdio: 'inherit' });
  const browser = await chromium.launch(launch);

  // 1. Measure every frame at the width the board gives it.
  const html = fs.readFileSync(path.join(__dirname, BOARD + '.html'), 'utf8');
  const sizes = {};
  for (const m of html.matchAll(/<iframe src="frames\/([^"]+)" width="(\d+)"/g)) {
    const page = await browser.newPage({ viewport: { width: Number(m[2]), height: 100 }, deviceScaleFactor: 1, locale: 'de-DE' });
    await page.goto('file://' + path.join(FRAMES, m[1]), { waitUntil: 'load' });
    await page.waitForTimeout(150);
    sizes[m[1]] = await page.evaluate(() => Math.ceil(Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)));
    await page.close();
  }
  execFileSync(process.execPath, [BUILD], { stdio: 'inherit', env: { ...process.env, FRAME_SIZES_C: JSON.stringify(sizes) } });

  // 2. Render the board in both themes, the theme set in every frame too.
  const page = await browser.newPage({ viewport: { width: WIDTH, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
  const written = [];
  for (const theme of ['light', 'dark']) {
    await page.setViewportSize({ width: WIDTH, height: 900 });
    await page.goto('file://' + path.join(__dirname, BOARD + '.html'), { waitUntil: 'load' });
    for (const f of page.frames()) await f.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
    const full = await page.evaluate(() => document.documentElement.scrollHeight);
    await page.setViewportSize({ width: WIDTH, height: full });
    await page.waitForTimeout(400);
    const png = path.join(__dirname, `${BOARD}--${theme}.png`);
    await page.screenshot({ path: png, fullPage: true });
    written.push(png);
    console.log('rendered ' + path.basename(png));
  }
  await browser.close();
  try {
    execFileSync('python3', ['-c', QUANTIZE, ...written]);
    console.log('reduced to 256 colours');
  } catch (e) {
    console.log('left at full colour (python3 with Pillow not found)');
  }
})();
