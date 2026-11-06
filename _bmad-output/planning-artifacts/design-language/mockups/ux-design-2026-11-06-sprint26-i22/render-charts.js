// Renders board 02 (I22, the charts) to PNG at 1200 px, then reduces it to
// a 256-colour palette when python3 with Pillow is available. Board 01 keeps
// its own render.js.
// Usage: node render-charts.js (after node build-charts.js)
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const path = require('path');
const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
(async () => {
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
  await page.goto('file://' + path.join(__dirname, '02-privacy-charts.html'), { waitUntil: 'load' });
  // Every iframe is painted only inside the viewport: make the viewport the
  // whole board, then give the frames time to load and paint.
  const h = await page.evaluate(() => document.documentElement.scrollHeight);
  await page.setViewportSize({ width: 1200, height: h });
  await page.waitForLoadState('load');
  await page.waitForTimeout(1500);
  const png = path.join(__dirname, '02-privacy-charts--1200.png');
  await page.screenshot({ path: png, fullPage: true });
  await browser.close();
  console.log('rendered 02-privacy-charts--1200.png');
  try {
    execFileSync('python3', ['-c', QUANTIZE, png]);
    console.log('reduced to 256 colours');
  } catch (e) {
    console.log('left at full colour (python3 with Pillow not found)');
  }
})();
