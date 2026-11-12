// The walks' wait, on its own (the Sprint 28 closing act, browser job;
// one helper for every walk since Sprint 29 M2): `settle` in settle.js
// decides when a page's loads have landed, and a walk reads the page and
// leaves it only then. A walk that reads
// a page before its loads land checks less than it says, and one that
// leaves while a load's task is mid-query kills the task, which takes the
// test's one shared database connection with it (CI, Sprint 28: every
// later page answered 500).
//
// Pages drawn in the browser itself, no server: one that never settles,
// one whose second load starts a moment after the first has landed (as
// Wealth's remembered period asks for one once the page is connected), and
// one that never connects; then the way out of a page (Sprint 29 M2): a
// live page (one with the LiveView client) is left only once its load has
// landed, one whose load never lands fails the walk that leaves it, and a
// page without the client is left at once. Driven by settle_check_test.exs.
//
// Prints one JSON object on stdout: each case's answer, the time it took
// and, for a load, whether it had landed when the wait returned.
"use strict";

const { launchChromium } = require("./launch");
const { settle, draw, follow, leave } = require("./settle");

const CONNECTED = '<div data-phx-main class="phx-connected">';
// The LiveView client's mark on a live page (window.liveSocket).
const CLIENT = "<script>window.liveSocket = {};</script>";

(async () => {
  const browser = await launchChromium();
  const out = {};
  try {
    const page = await browser.newPage();

    // A load that never lands.
    await draw(page, CONNECTED + '<div data-role="stuck-load" aria-busy="true"></div></div>');
    let started = Date.now();
    out.stuck = { answer: await settle(page, { settleMs: 1500 }), ms: Date.now() - started };

    // The first load lands after 300 ms; a second one starts 100 ms later
    // and lands after another 1.5 s.
    await draw(
      page,
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
    await draw(page, '<div data-phx-main><p aria-busy="true"></p></div>');
    started = Date.now();
    out.unconnected = { answer: await settle(page, { connectMs: 500, settleMs: 1500 }), ms: Date.now() - started };

    // A live page whose load lands after 1 s: a click on a link waits for
    // it. Each kind of page has a page of its own: `draw` keeps the window,
    // and the LiveView client's mark with it.
    const live = await browser.newPage();
    await draw(
      live,
      CLIENT +
        CONNECTED +
        '<div id="load" aria-busy="true"></div></div>' +
        "<script>" +
        "window.__landed = false;" +
        'setTimeout(() => { document.getElementById("load").removeAttribute("aria-busy"); window.__landed = true; }, 1000);' +
        "</script>"
    );
    out.leaving = { landed: await follow(live, () => live.evaluate(() => window.__landed === true)) };

    // A live page whose load never lands: the way out fails, naming it,
    // and the click is not made.
    await draw(live, CLIENT + CONNECTED + '<div data-role="stuck-load" aria-busy="true"></div></div>');
    let clicked = false;
    started = Date.now();
    try {
      await follow(live, () => (clicked = true), { settleMs: 1000 });
      out.stuckLeave = { failed: false, clicked };
    } catch (error) {
      out.stuckLeave = { failed: true, clicked, message: String(error && error.message), ms: Date.now() - started };
    }

    // Left again while still busy: it fails at once, without a second wait.
    started = Date.now();
    out.stuckAgain = await follow(live, () => null).then(
      () => ({ failed: false }),
      (error) => ({ failed: true, message: String(error && error.message), ms: Date.now() - started })
    );

    // The load lands at last: the page is left after all.
    await live.evaluate(() => document.querySelector("[aria-busy]").removeAttribute("aria-busy"));
    out.landedLate = await follow(live, () => true).catch((error) => String(error && error.message));

    // A page without the client, busy as it may look: left at once.
    const plain = await browser.newPage();
    await draw(plain, CONNECTED + '<div aria-busy="true"></div></div>');
    started = Date.now();
    await follow(plain, () => null);
    out.withoutClient = { ms: Date.now() - started };
  } catch (error) {
    out.error = String(error && error.message);
  } finally {
    // Its pages carry no LiveView client, so they are left at once.
    await leave(browser);
  }
  process.stdout.write(JSON.stringify(out) + "\n");
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
