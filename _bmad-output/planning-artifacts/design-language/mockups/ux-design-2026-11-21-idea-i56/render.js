// Renders the idea boards to PNG at 1x (board 06 at 1460 px, so three phones fit side by side at 1 : 1), in the light and the dark
// theme, then reduces each to a 256-colour palette when python3 with Pillow
// is available.
// Usage: node render.js (after node build.js)
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const path = require('path');

const QUANTIZE = 'import sys\nfrom PIL import Image\nfor f in sys.argv[1:]:\n    Image.open(f).convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(f, optimize=True)\n';
const BOARDS = ['01-widget', '02-navigation', '03-dashboard', '04-devices', '05-period', '06-screens'];

(async () => {
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, deviceScaleFactor: 1, locale: 'de-DE' });
  const written = [];
  for (const board of BOARDS) {
    for (const theme of ['light', 'dark']) {
      await page.setViewportSize({ width: board === '06-screens' ? 1460 : 1200, height: 900 });
      await page.goto('file://' + path.join(__dirname, board + '.html'), { waitUntil: 'load' });
      await page.evaluate((t) => document.documentElement.setAttribute('data-theme', t), theme);
      await page.waitForTimeout(300);
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
