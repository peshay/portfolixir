// The one wait every browser walk uses before it leaves a page (Sprint 29
// M2, the Sprint 28 retrospective's carry-forward 1). A walk that leaves a
// page while one of its loads runs stops the page's LiveView and kills the
// load's task mid-query, which takes the test's one shared database
// connection with it: every later request answers 500, or the sandbox logs
// a dropped connection and the log noise rule fails the run. CI's browser
// job failed for it three times (the privacy walk, `PeriodMemoryTest`, the
// level switch walk), each time in a walk that had not learned the wait.
// test/invariants/browser_walks_settle_test.exs asserts that every walk
// leaves a page only through this module.
//
// - `settle(page)` waits until the page is connected and nothing on it is
//   busy, and answers {connected, settled, pending}; the privacy walk reads
//   a page only once it has settled.
// - `visit(page, url)` leaves the page's current document once it has
//   settled, then goes to `url` (Playwright's `goto`).
// - `draw(page, html)` the same, then writes `html` as the page's document
//   (Playwright's `setContent`).
// - `follow(page, action)` waits the same way, then runs `action`, a click
//   or a tap on a link that loads another page.
// - `leave(target)` waits for each page of a page, a context or the
//   browser, then closes it: the end of a walk.
//
// A page whose loads have not landed after the wait's time fails the walk
// that leaves it, naming what it still waits for.
"use strict";

// What marks a load still running: every placeholder a page shows while a
// load runs carries `aria-busy` (test/invariants/busy_placeholders_test.exs),
// and LiveView's own loading class.
const BUSY = "[aria-busy='true'], .phx-loading, .value-slot-pending";

// Waits until the page is connected and every load it started has landed:
// no element is busy, and none is again a moment later (a load asked for
// once the page is connected, such as Wealth's remembered period, starts
// after the first ones land). Answers {connected, settled, pending}. A page
// that never connects (a crash, an error page) is not waited on. One still
// busy after `settleMs` is not settled, and `pending` names what it waits
// for (the Sprint 28 closing act: on CI's slower runner a wait that gave up
// after 8 s, silently, let the privacy walk leave mid-load).
//
// Once settled, the page is watched: the first change to its document
// after that ends the quiet, and a later leave that finds the page still
// quiet and nothing busy need not wait again (a load that starts shows its
// busy marker, a change). A page this wait gave up on and that is still
// busy fails the walk that leaves it at once: a second full wait would
// only stretch a failing run.
async function settle(page, { connectMs = 15000, settleMs = 45000 } = {}) {
  const connected = await page
    .waitForFunction(() => document.querySelector("[data-phx-main].phx-connected") !== null, null, { timeout: connectMs })
    .then(() => true)
    .catch(() => false);
  if (!connected) return { connected, settled: false, pending: [] };
  const deadline = Date.now() + settleMs;
  const idle = () => page.evaluate((busy) => document.querySelector(busy) === null, BUSY).catch(() => false);
  for (;;) {
    const left = deadline - Date.now();
    const landed =
      left > 0 &&
      (await page
        .waitForFunction((busy) => document.querySelector(busy) === null, BUSY, { timeout: left, polling: 100 })
        .then(() => true)
        .catch(() => false));
    if (!landed) {
      await page.evaluate(() => (window.__settleGaveUp = true)).catch(() => {});
      return { connected, settled: false, pending: await busyNow(page) };
    }
    await page.waitForTimeout(250);
    if (await idle()) {
      await watchQuiet(page);
      return { connected, settled: true, pending: [] };
    }
  }
}

// Marks the page quiet until its document next changes.
function watchQuiet(page) {
  return page
    .evaluate(() => {
      if (window.__settleObserver) window.__settleObserver.disconnect();
      window.__settleQuiet = true;
      window.__settleGaveUp = false;
      window.__settleObserver = new MutationObserver(() => {
        window.__settleQuiet = false;
        window.__settleObserver.disconnect();
      });
      window.__settleObserver.observe(document.documentElement, {
        subtree: true,
        childList: true,
        attributes: true,
        characterData: true
      });
    })
    .catch(() => {});
}

// The busy elements on the page, each by its tag and its data-role, id or
// class.
function busyNow(page) {
  return page
    .$$eval(BUSY, (els) =>
      els.slice(0, 5).map((el) => {
        const name = el.getAttribute("data-role") || el.id || [...el.classList].join(".");
        return el.tagName.toLowerCase() + (name ? " " + name : "");
      })
    )
    .catch(() => ["(the page is gone)"]);
}

// Waits before the page's current document is left. A document without
// the LiveView client (a blank page, an error page, a page the walk drew
// itself) has no server process to stop and is left at once; so is one
// still quiet since the walk's last settle. A page that does not settle in
// time fails the walk, naming what it waits for; one an earlier wait gave
// up on and still busy fails it at once.
async function beforeLeaving(page, options) {
  if (page.isClosed()) return;
  const state = await page
    .evaluate(
      (busy) => ({
        live: typeof window.liveSocket === "object" && window.liveSocket !== null,
        busy: document.querySelector(busy) !== null,
        quiet: window.__settleQuiet === true,
        gaveUp: window.__settleGaveUp === true
      }),
      BUSY
    )
    .catch(() => ({ live: false, busy: false, quiet: false, gaveUp: false }));
  if (!state.live || (state.quiet && !state.busy)) return;
  const answer =
    state.gaveUp && state.busy ? { connected: true, settled: false, pending: await busyNow(page) } : await settle(page, options);
  if (answer.connected && !answer.settled) {
    throw new Error("left " + page.url() + " before its loads landed (" + answer.pending.join(", ") + ")");
  }
}

// Goes to `url` once the current page has settled; answers what
// Playwright's `goto` answers.
async function visit(page, url, options) {
  await beforeLeaving(page);
  return page.goto(url, options);
}

// Writes `html` as the page's document once the current one has settled.
// The window stays, so the wait's marks on it are cleared.
async function draw(page, html, options) {
  await beforeLeaving(page);
  await page.setContent(html, options);
  await page.evaluate(() => {
    window.__settleQuiet = false;
    window.__settleGaveUp = false;
  });
}

// Runs `action` (a click or a tap on a link to another page) once the page
// has settled; answers what `action` answers. `waitOptions` are settle's.
async function follow(page, action, waitOptions) {
  await beforeLeaving(page, waitOptions);
  return action();
}

// Closes a page, a context or the browser once each of its pages has
// settled. Every one is waited for and the target is closed either way;
// a page that did not settle fails the walk afterwards.
async function leave(target, waitOptions) {
  const pages =
    typeof target.contexts === "function"
      ? target.contexts().flatMap((context) => context.pages())
      : typeof target.pages === "function"
        ? target.pages()
        : [target];
  const errors = [];
  for (const page of pages) {
    try {
      await beforeLeaving(page, waitOptions);
    } catch (error) {
      errors.push(String(error && error.message));
    }
  }
  await target.close();
  if (errors.length) throw new Error(errors.join("; "));
}

module.exports = { BUSY, settle, visit, draw, follow, leave };
