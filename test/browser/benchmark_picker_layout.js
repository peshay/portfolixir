// Holdings' benchmark picker at 1200 and 390 px (Sprint 29, the closing act
// of #1416; board ux-design-2026-11-12-sprint29/02 ① and ⑥), driven in a
// real Chromium by test/browser/benchmark_picker_layout_test.exs, which
// boots the endpoint and passes the page's URL as one JSON argument. It
// opens „Benchmark…“ and measures the labelled groups: at 1200 px each
// label in one column, beside its options; at 390 px each label above its
// options, and a larger gap before every label after the first than
// between a label and its own options, so a label starts its group instead
// of reading as the last line of the group before it.
//
// The picker is opened while the page's loads are still in flight, by a
// click on its summary that lands the moment the first load arrives, in
// the same task, just before LiveView applies it: the walk holds the
// LiveView's messages after its join at the socket, arms the click, then
// lets them land. LiveView removes every attribute the server did not
// render, `open` included. CI's browser job caught it on 651850e as a
// timeout, when the walk's own open raced the loads on a slow runner: a
// picker without a hook folded shut when they landed, and one whose hook
// learnt the open state only from the `toggle` event (dispatched later, in
// a task of its own) folded shut when a load landed between the click and
// that event. Holding the loads and placing the click makes the case
// happen on every run instead of on a slow one. The custom range's popover
// beside the picker ("Custom range…", the PopoverDisclosure hook) is
// opened under the same race once, at 1200 px.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "...", "seen": {...}}; the exit status is 0 either way unless the browser
// itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);

async function measure(page) {
  return page.evaluate(() => {
    const round = (value) => Math.round(value * 10) / 10;
    const box = (node) => {
      if (!node) return null;
      const b = node.getBoundingClientRect();
      return { top: round(b.top), bottom: round(b.bottom), left: round(b.left), right: round(b.right) };
    };
    const groups = document.querySelector("[data-role=benchmark-groups]");
    if (!groups) return null;
    const labels = Array.from(groups.querySelectorAll(".bm-groups__label"));
    return {
      viewport: window.innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      groups: labels.map((label) => ({
        label: box(label),
        options: box(groups.querySelector(`[aria-labelledby="${label.id}"]`))
      }))
    };
  });
}

function check(seen, width) {
  const errors = [];
  if (!seen) return [width + " px: no labelled groups"];
  if (seen.scrollWidth > seen.viewport) errors.push(width + " px: the page scrolls sideways: " + seen.scrollWidth);
  if (seen.groups.length < 2) return errors.concat([width + " px: fewer than two groups, so the case is not measured"]);

  const lefts = seen.groups.map((g) => g.label.left);
  if (Math.max(...lefts) - Math.min(...lefts) > 1) errors.push(width + " px: the labels start on " + lefts.join(", "));

  for (const [index, g] of seen.groups.entries()) {
    if (width >= 1000) {
      if (g.options.left < g.label.right) errors.push("1200 px: group " + (index + 1) + "'s options are not beside its label");
      if (g.label.top < g.options.top - 4 || g.label.top > g.options.bottom)
        errors.push("1200 px: group " + (index + 1) + "'s label is not on its options' first line");
    } else {
      const within = g.options.top - g.label.bottom;
      if (within < 0) errors.push(width + " px: group " + (index + 1) + "'s options are not under its label");
      if (index > 0) {
        const before = g.label.top - seen.groups[index - 1].options.bottom;
        if (before < 12 || before < within + 6)
          errors.push(
            width + " px: the gap before group " + (index + 1) + "'s label is " + before +
              " px against " + within + " px to its own options"
          );
      }
    }
  }
  return errors;
}

// Holds every message the page's LiveView gets after its join reply until
// `release()`, in order, so the walk acts on a connected page whose loads
// have not landed. The Phoenix heartbeat ("phoenix" topic) passes; a load
// that reaches the socket after `release()` passes at once.
async function holdLoads(page) {
  const held = [];
  let joined = false;
  let holding = true;
  let toPage = null;
  await page.routeWebSocket(/\/live\/websocket/, (ws) => {
    toPage = ws;
    const server = ws.connectToServer();
    server.onMessage((message) => {
      let topic = null;
      let event = null;
      if (typeof message === "string") [, , topic, event] = JSON.parse(message);
      if (holding && joined && topic !== "phoenix") return held.push(message);
      if (event === "phx_reply" && typeof topic === "string" && topic.startsWith("lv:")) joined = true;
      ws.send(message);
    });
  });
  return {
    release() {
      holding = false;
      for (const message of held.splice(0)) toPage.send(message);
    }
  };
}

// Runs in the page: the next LiveView message that carries a load (a
// `diff`) first clicks the summary of the disclosure `selector` names,
// then reaches LiveView, so the disclosure opens and the load's patch
// lands in one task, before the click's `toggle` event. Phoenix's
// transport hands each message to `socket.onConnMessage`, looked up at
// each call.
function clickBeforeNextLoad(selector) {
  const socket = window.liveSocket.socket;
  const receive = socket.onConnMessage;
  socket.onConnMessage = function (event) {
    const [, , topic, kind] = typeof event.data === "string" ? JSON.parse(event.data) : [];
    if (typeof topic === "string" && topic.startsWith("lv:") && kind === "diff") {
      socket.onConnMessage = receive;
      document.querySelector(selector + " > summary").click();
      window.__disclosureClicked = true;
    }
    return receive.call(this, event);
  };
}

// Opens Holdings at `width` with the disclosure `selector` names clicked
// as the first load lands, waits until the page settles, and answers the
// page, its context and the errors so far; `open` says whether the
// disclosure is still open.
async function openWhileLoading(browser, width, selector, name) {
  const phone = width < 600;
  const context = await browser.newContext({
    viewport: { width, height: phone ? 844 : 900 },
    hasTouch: phone,
    isMobile: phone,
    locale: "de-DE"
  });
  const page = await context.newPage();
  const loads = await holdLoads(page);
  await visit(page, args.url);
  await page.waitForSelector("[data-phx-main].phx-connected");
  await page.evaluate(clickBeforeNextLoad, selector);
  loads.release();
  const settled = await settle(page);
  const { open, clicked } = await page.$eval(selector, (disclosure) => ({
    open: disclosure.open,
    clicked: window.__disclosureClicked === true
  }));
  const errors = [];
  if (!clicked) errors.push(width + " px: no load landed as " + name + " opened, so the case is not measured");
  if (!settled.settled) errors.push(width + " px: the page did not settle (" + settled.pending.join(", ") + ")");
  if (!open) errors.push(width + " px: " + name + " closed when the page's loads landed");
  return { context, page, open, errors };
}

async function run(browser) {
  const errors = [];
  const seenAll = {};
  for (const width of [1200, 390]) {
    const opened = await openWhileLoading(browser, width, "[data-role=benchmark-picker]", "the picker");
    errors.push(...opened.errors);
    if (opened.open) {
      const seen = await measure(opened.page);
      seenAll[width] = seen;
      errors.push(...check(seen, width));
    }
    await leave(opened.context);
  }
  // The custom range's popover beside it (PopoverDisclosure) under the
  // same race; one width, since only the hook is checked.
  const range = await openWhileLoading(browser, 1200, "#period-custom", "the custom range's popover");
  errors.push(...range.errors);
  await leave(range.context);
  return { errors, seen: seenAll };
}

(async () => {
  const browser = await launchChromium();
  try {
    const { errors, seen } = await run(browser);
    process.stdout.write(
      JSON.stringify(errors.length === 0 ? { ok: true } : { ok: false, error: errors.join("; "), seen }) + "\n"
    );
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
