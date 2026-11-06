// Renders board 03 to PNG: each desktop board at 1200 px, each phone
// board at 390 px, then reduces each PNG to a 256-colour palette when
// python3 with Pillow is available (the board stays legible).
// Usage: node render.js
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const path = require('path');
const JOBS = [
  ['03-sale-hindsight.html', 1200, '03-sale-hindsight--1200.png'],
  ['03-sale-hindsight-390.html', 390, '03-sale-hindsight--390.png']
];
const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
(async () => {
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
  for (const [html, w, png] of JOBS) {
    const page = await browser.newPage({ viewport: { width: w, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
    await page.goto('file://' + path.join(__dirname, html), { waitUntil: 'load' });
    // Every iframe is painted only inside the viewport: make the viewport
    // the whole board, then give the frames time to load and paint.
    const h = await page.evaluate(() => document.documentElement.scrollHeight);
    await page.setViewportSize({ width: w, height: h });
    await page.waitForLoadState('load');
    await page.waitForTimeout(1500);
    await page.screenshot({ path: path.join(__dirname, png), fullPage: true });
    await page.close();
    console.log('rendered', png);
  }
  await browser.close();
  try {
    execFileSync('python3', ['-c', QUANTIZE, ...JOBS.map(j => path.join(__dirname, j[2]))]);
    console.log('reduced to 256 colours');
  } catch (e) {
    console.log('left at full colour (python3 with Pillow not found)');
  }
})();
