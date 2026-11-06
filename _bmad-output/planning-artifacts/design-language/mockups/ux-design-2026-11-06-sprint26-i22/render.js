// Renders board 01 to PNG: the whole board at 1x into this folder; with
// DETAIL_DIR set, also each variant's pair (light and dark) at 2x into that
// folder, the size a reader looks at (kept out of the repository for size).
// Usage: node render.js (after node build.js); DETAIL_DIR=/some/dir node render.js
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const browser = await chromium.launch(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {});
  for (const scale of process.env.DETAIL_DIR ? [1, 2] : [1]) {
    const page = await browser.newPage({ viewport: { width: 2120, height: 1000 }, deviceScaleFactor: scale, locale: 'de-DE' });
    await page.goto('file://' + path.join(__dirname, '01-privacy-mode.html'), { waitUntil: 'load' });
    await page.waitForTimeout(800);
    if (scale === 1) {
      await page.screenshot({ path: path.join(__dirname, '01-privacy-mode--board.png'), fullPage: true });
      console.log('rendered the board');
    } else {
      for (const id of ['wealth-today', 'wealth-a', 'wealth-b', 'wealth-c', 'overview-today', 'overview-a', 'overview-b', 'overview-c']) {
        await page.locator('#' + id).screenshot({ path: path.join(process.env.DETAIL_DIR, `01-${id}.png`) });
        console.log('rendered', id);
      }
      await page.locator('.mock-head').screenshot({ path: path.join(process.env.DETAIL_DIR, '01-head.png') });
    }
    await page.close();
  }
  await browser.close();
})();
