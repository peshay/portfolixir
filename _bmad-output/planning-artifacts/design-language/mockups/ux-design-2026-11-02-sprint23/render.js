// Renders the boards to PNG: each desktop board at 1200 px, each phone
// board at 390 px, then reduces each PNG to a 256-colour palette when
// python3 with Pillow is available (the board stays legible).
// Usage: node render.js
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const path = require('path');
const JOBS = [
  ['01-coverage.html', 1200, '01-coverage--1200.png'],
  ['01-coverage-390.html', 390, '01-coverage--390.png'],
  ['02-money.html', 1200, '02-money--1200.png'],
  ['02-money-390.html', 390, '02-money--390.png'],
  ['03-journal.html', 1200, '03-journal--1200.png'],
  ['03-journal-390.html', 390, '03-journal--390.png'],
  ['04-number-colours.html', 1200, '04-number-colours--1200.png'],
  ['04-number-colours-390.html', 390, '04-number-colours--390.png']
];
const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
(async () => {
  const browser = await chromium.launch();
  for (const [html, w, png] of JOBS) {
    const page = await browser.newPage({ viewport: { width: w, height: 900 }, deviceScaleFactor: 1 });
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
