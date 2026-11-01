// Renders the board to PNG: 01-i1.html at 1200 px, 01-i1-390.html at 390 px,
// then reduces each PNG to a 256-colour palette when python3 with Pillow is
// available (about a third of the size; the board stays legible).
// Usage: node render.js
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const path = require('path');
const JOBS = [['01-i1.html', 1200, '01-i1--1200.png'], ['01-i1-390.html', 390, '01-i1--390.png']];
const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
(async () => {
  const browser = await chromium.launch();
  for (const [html, w, png] of JOBS) {
    const page = await browser.newPage({ viewport: { width: w, height: 900 }, deviceScaleFactor: 1 });
    await page.goto('file://' + path.join(__dirname, html));
    await page.waitForTimeout(300);
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
