// Captures the Overview's data-quality block and the Wertpapiere filter
// chips from the review instance (GET only) into dq-line.html and
// dq-chips.html, for board 05.
// Usage: BASE=http://localhost:4011 node capture-dq.js
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, locale: 'de-DE' });
  const strip = s => s.replace(/ data-phx-[a-z-]+="[^"]*"/g, '').replace(/ phx-[a-z-]+="[^"]*"/g, '');
  await p.goto((process.env.BASE || 'http://localhost:4011') + '/', { waitUntil: 'networkidle' });
  const dq = await p.$eval('#dashboard-data-quality', e => e.outerHTML);
  await p.goto((process.env.BASE || 'http://localhost:4011') + '/securities', { waitUntil: 'networkidle' });
  const chips = await p.evaluate(() => { const a = [...document.querySelectorAll('a,button')].find(e => e.textContent.trim() === 'Kein Wechselkurs'); let n = a; for (let k = 0; k < 6 && n; k++) { n = n.parentElement; if (n.textContent.includes('WÄHRUNG') || n.textContent.includes('Währung')) break; } return n.outerHTML; });
  const tidy = (s) => s.replace(/[ \t]+\n/g, '\n').trim() + '\n';
  fs.writeFileSync(require('path').join(__dirname, 'dq-line.html'), tidy(strip(dq)));
  fs.writeFileSync(require('path').join(__dirname, 'dq-chips.html'), tidy(strip(chips)));
  await b.close();
})();
