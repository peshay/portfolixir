// Renders every *.html in this directory to a PNG next to it. Widths come from
// <body data-widths="1200,390">; default 1200. Usage: node render.mjs [file...]
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || '/opt/node22/lib/node_modules/playwright/index.mjs');
import fs from 'node:fs'; import path from 'node:path'; import url from 'node:url';
const dir = path.dirname(url.fileURLToPath(import.meta.url));
const files = process.argv.slice(2).length ? process.argv.slice(2) : fs.readdirSync(dir).filter(f => f.endsWith('.html'));
const browser = await chromium.launch();
for (const f of files) {
  const html = fs.readFileSync(path.join(dir, f), 'utf8');
  const widths = (html.match(/data-widths="([^"]+)"/)?.[1] || '1200').split(',').map(Number);
  for (const w of widths) {
    const page = await browser.newPage({ viewport: { width: w, height: 800 }, deviceScaleFactor: 1 });
    await page.goto('file://' + path.join(dir, f)); await page.waitForTimeout(300);
    const out = path.join(dir, f.replace(/\.html$/, widths.length > 1 ? `--${w}.png` : '.png'));
    await page.screenshot({ path: out, fullPage: true }); await page.close(); console.log('rendered', path.basename(out));
  }
}
await browser.close();
