// The privacy walk's wait, on its own (the Sprint 28 closing act, browser
// job): `settle` in privacy_leak.js decides when a page's loads have landed,
// and the walk reads the page and leaves it only then. A walk that reads
// a page before its loads land checks less than it says, and one that
// leaves while a load's task is mid-query kills the task, which takes the
// test's one shared database connection with it (CI, Sprint 28: every
// later page answered 500).
//
// Three pages drawn in the browser itself, no server: one that never
// settles, one whose second load starts a moment after the first has
// landed (as Wealth's remembered period asks for one once the page is
// connected), and one that never connects. Driven by
// privacy_leak_settle_test.exs.
//
// Prints one JSON object on stdout: each case's answer, the time it took
// and, for the second load, whether it had landed when the wait returned.
"use strict";

const { launchChromium } = require("./launch");
const { settle } = require("./privacy_leak");

const CONNECTED = '<div data-phx-main class="phx-connected">';

(async () => {
  const browser = await launchChromium();
  const out = {};
  try {
    const page = await browser.newPage();

    // A load that never lands.
    await page.setContent(CONNECTED + '<div data-role="stuck-load" aria-busy="true"></div></div>');
    let started = Date.now();
    out.stuck = { answer: await settle(page, { settleMs: 1500 }), ms: Date.now() - started };

    // The first load lands after 300 ms; a second one starts 100 ms later
    // and lands after another 1.5 s.
    await page.setContent(
      CONNECTED +
        '<div id="first" aria-busy="true"></div></div>' +
        "<script>" +
        "window.__secondLanded = false;" +
        'setTimeout(() => document.getElementById("first").removeAttribute("aria-busy"), 300);' +
        "setTimeout(() => {" +
        '  const second = document.createElement("div");' +
        '  second.setAttribute("aria-busy", "true");' +
        "  document.querySelector('[data-phx-main]').appendChild(second);" +
        "  setTimeout(() => { second.removeAttribute('aria-busy'); window.__secondLanded = true; }, 1500);" +
        "}, 400);" +
        "</script>"
    );
    out.second = { answer: await settle(page, { settleMs: 10000 }) };
    out.second.landed = await page.evaluate(() => window.__secondLanded);

    // A page that never connects (an error page): not waited on.
    await page.setContent('<div data-phx-main><p aria-busy="true"></p></div>');
    started = Date.now();
    out.unconnected = { answer: await settle(page, { connectMs: 500, settleMs: 1500 }), ms: Date.now() - started };
  } catch (error) {
    out.error = String(error && error.message);
  } finally {
    await browser.close();
  }
  process.stdout.write(JSON.stringify(out) + "\n");
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
