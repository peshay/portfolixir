// Renders the Sprint 28 boards to PNG at 1x, light and dark, then reduces
// each to a 256-colour palette when python3 with Pillow is available.
// First measures every frame at its width and writes frames/sizes.json, so
// build.js gives each <iframe> its real height; then rebuilds and renders.
// Usage: node build.js && node render.js
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
const BOARDS = ['01-news-view', '02-stack-filter', '03-ttwror-levels', '04-version', '05-currency-mismatch', '06-privacy-stack', '07-basis-and-bar'];
const FRAMES = path.join(__dirname, 'frames');
const WIDTH = { '01-news-view': 1310, '02-stack-filter': 1090, '03-ttwror-levels': 1090, '04-version': 1960, '05-currency-mismatch': 1090, '06-privacy-stack': 1090, '07-basis-and-bar': 1300 };

(async () => {
  const launch = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {};
  const browser = await chromium.launch(launch);

  // 1. Measure every frame at the width the board gives it.
  const widths = {};
  for (const b of BOARDS) {
    const html = fs.readFileSync(path.join(__dirname, b + '.html'), 'utf8');
    for (const m of html.matchAll(/<iframe src="frames\/([^"]+)" width="(\d+)"/g)) widths[m[1]] = Number(m[2]);
  }
  const sizes = {};
  for (const [file, width] of Object.entries(widths)) {
    if (file.startsWith('04-')) continue; // fixed heights: the sidebar is 100vh
    const page = await browser.newPage({ viewport: { width, height: 100 }, deviceScaleFactor: 1, locale: 'de-DE' });
    await page.goto('file://' + path.join(FRAMES, file), { waitUntil: 'load' });
    await page.waitForTimeout(150);
    sizes[file] = await page.evaluate(() => Math.max(document.documentElement.scrollHeight, document.body.scrollHeight));
    await page.close();
  }
  fs.writeFileSync(path.join(FRAMES, 'sizes.json'), JSON.stringify(sizes, null, 1) + '\n');
  execFileSync(process.execPath, [path.join(__dirname, 'build.js')], { stdio: 'inherit' });

  // 2. Render each board in both themes, the theme set in every frame too.
  const page = await browser.newPage({ viewport: { width: 1960, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
  const written = [];
  for (const board of BOARDS) {
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
