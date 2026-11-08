// Captures the app's shell (sidebar, top bar, the main element emptied) from
// the review instance on the synthetic review seed, GET requests only, and
// writes shell.html, which build.js wraps around every frame.
// Usage: BASE=http://localhost:4011 node capture.js
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 }, locale: 'de-DE' });
  await p.goto((process.env.BASE || 'http://localhost:4011') + '/securities/1', { waitUntil: 'networkidle' });
  const out = await p.evaluate(() => {
    const body = document.body.cloneNode(true);
    body.querySelectorAll('script').forEach(s => s.remove());
    const main = body.querySelector('main');
    const mainHtml = main.outerHTML;
    main.innerHTML = '%%MAIN%%';
    const pane = document.querySelector('.detail-pane, [class*=detail-pane]');
    return { shell: body.innerHTML, mainClass: main.className, pane: pane ? pane.outerHTML.slice(0, 4000) : 'none', paneClass: pane ? pane.className : '' };
  });
  const strip = s => s.replace(/ data-phx-[a-z-]+="[^"]*"/g, '').replace(/ phx-[a-z-]+="[^"]*"/g, '').replace(/ id="phx-[^"]*"/g,'');
  out.shell = strip(out.shell); out.pane = strip(out.pane);
  fs.writeFileSync(require('path').join(__dirname, 'shell.html'), out.shell.replace(/[ \t]+\n/g, '\n').trim() + '\n');
  console.log(out.shell.length, out.mainClass, out.paneClass);

  await b.close();
})();
