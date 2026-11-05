// The sidebar's collapsed rail survives a live redirect and a full page load
// (Sprint 24 P2, #1357's rail line: on a phone, a collapsed rail opened
// again at every menu item), driven in a real Chromium by
// test/browser/rail_persists_test.exs, which boots the endpoint and passes
// its base URL as the only argument. LiveViewTest runs no client script and
// applies no CSS, so this is where the rail itself is measured.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");

const base = process.argv[2];
// A phone held sideways: wider than the 900 px breakpoint, so the sidebar
// is the desktop one with its rail, as on the owner's phone.
const PHONE_LANDSCAPE = { width: 915, height: 412 };
const PHONE_PORTRAIT = { width: 390, height: 844 };
const DESKTOP = { width: 1200, height: 800 };
// --sidebar-rail in app.css.
const RAIL = 72;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

// Recorded from the document's start, before the page's own scripts: the
// sidebar's width at DOMContentLoaded (the server's render, before the
// LiveView socket has joined and any hook has run) and the widest it has
// been on any frame since, so an expanded frame between two collapsed ones
// cannot pass unseen.
function recorder() {
  window.__rail = { firstRender: null, firstRight: null, firstAttr: null, widest: 0 };
  const width = () => {
    const sidebar = document.getElementById("app-sidebar");
    return sidebar ? sidebar.getBoundingClientRect().width : null;
  };
  document.addEventListener("DOMContentLoaded", () => {
    window.__rail.firstRender = width();
    const sidebar = document.getElementById("app-sidebar");
    window.__rail.firstRight = sidebar ? sidebar.getBoundingClientRect().right : null;
    window.__rail.firstAttr = document.documentElement.getAttribute("data-rail");
  });
  const frame = () => {
    const w = width();
    if (w !== null && w > window.__rail.widest) window.__rail.widest = w;
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

async function sidebarWidth(page) {
  return page.evaluate(() => document.getElementById("app-sidebar").getBoundingClientRect().width);
}

// Waits until the sidebar is the rail (`collapsed` true) or wider, after its
// 180 ms width transition; polled, never slept for.
async function expectRail(page, collapsed, message, timeout = 5000) {
  try {
    await page.waitForFunction(
      ([rail, want]) => {
        const w = document.getElementById("app-sidebar").getBoundingClientRect().width;
        return want ? Math.abs(w - rail) < 1 : w > rail + 40;
      },
      [RAIL, collapsed],
      { timeout, polling: "raf" }
    );
  } catch (_) {
    throw new Error(message + ": the sidebar is " + (await sidebarWidth(page)) + " px wide");
  }
}

// Waits until the page at `path` is connected and its sidebar marks
// `section` (the link of the section it belongs to) as the current one.
async function connected(page, path, section = path) {
  try {
    await page.waitForFunction(
      ([p, s]) =>
        location.pathname === p &&
        document.querySelector("[data-phx-main].phx-connected") !== null &&
        document.querySelector(".nav-link.is-active[href='" + s + "']") !== null,
      [path, section],
      { timeout: 10000 }
    );
  } catch (_) {
    throw new Error(path + " did not connect: at " + (await page.evaluate(() => location.pathname)));
  }
}

// Taps the rail's toggle and waits for the server to answer the request
// that remembers the new state, so the next full load can carry it.
async function toggle(page, collapsed) {
  const want = "/preferences/rail?rail=" + (collapsed ? "collapsed" : "expanded");
  const remembered = page.waitForResponse(
    (response) => response.url().endsWith(want) && response.status() === 204,
    { timeout: 5000 }
  );
  await page.tap("label.sidebar-toggle");
  await remembered;
  await expectRail(page, collapsed, collapsed ? "the toggle did not collapse the rail" : "the toggle did not expand the rail");
}

// Waits until the off-canvas sidebar is closed (its right edge at or left
// of the viewport's) after its transition, its checkbox unchecked and the
// remembered rail kept on <html>; polled, never slept for.
async function expectDrawerClosed(page, message, timeout = 5000) {
  try {
    await page.waitForFunction(
      () =>
        document.getElementById("app-sidebar").getBoundingClientRect().right <= 0 &&
        document.getElementById("app-sidebar-toggle").checked === false &&
        document.documentElement.getAttribute("data-rail") === "collapsed",
      null,
      { timeout, polling: "raf" }
    );
  } catch (_) {
    const state = await page.evaluate(() => ({
      right: document.getElementById("app-sidebar").getBoundingClientRect().right,
      checked: document.getElementById("app-sidebar-toggle").checked,
      attr: document.documentElement.getAttribute("data-rail")
    }));
    throw new Error(message + ": " + JSON.stringify(state));
  }
}

async function checked(page) {
  return page.evaluate(() => document.getElementById("app-sidebar-toggle").checked);
}

async function resetWidest(page) {
  await page.evaluate(() => {
    window.__rail.widest = 0;
  });
}

async function rail(page) {
  return page.evaluate(() => window.__rail);
}

(async () => {
  const browser = await launchChromium();
  try {
    const context = await browser.newContext({
      viewport: PHONE_LANDSCAPE,
      hasTouch: true,
      isMobile: true
    });
    await context.addInitScript(recorder);
    const page = await context.newPage();

    // An empty instance: Cash flow's empty state links to Accounts & depots
    // with a live redirect (data-phx-link="redirect").
    await page.goto(base + "/cashflow");
    await connected(page, "/cashflow", "/portfolio");
    await expectRail(page, false, "a first visit did not open the sidebar expanded");

    await toggle(page, true);
    check(await checked(page), "the collapsed rail's checkbox is not checked");

    // A live redirect: the same document, a new LiveView.
    await page.evaluate(() => {
      window.__sameDocument = true;
    });
    await resetWidest(page);
    await page.tap("a[data-phx-link='redirect'][href='/portfolios']");
    await connected(page, "/portfolios");
    check(await page.evaluate(() => window.__sameDocument === true), "the link was not a live redirect");
    await expectRail(page, true, "a live redirect opened the rail");
    check((await rail(page)).widest < RAIL + 1, "a live redirect showed the sidebar expanded on a frame");
    check(await checked(page), "after a live redirect the checkbox is not checked");

    // A sidebar link: a full page load.
    await page.tap("#nav-securities");
    await connected(page, "/securities");
    check(await page.evaluate(() => window.__sameDocument === undefined), "the sidebar link was not a full load");
    let seen = await rail(page);
    check(seen.firstAttr === "collapsed", "the page was not rendered with the remembered rail: " + JSON.stringify(seen));
    check(Math.abs(seen.firstRender - RAIL) < 1, "the first render showed the sidebar " + seen.firstRender + " px wide");
    await expectRail(page, true, "a full page load opened the rail");
    check((await rail(page)).widest < RAIL + 1, "a full page load showed the sidebar expanded on a frame");
    check(await checked(page), "after a full load the checkbox is not checked");

    // Expanded again, a full load opens expanded.
    await toggle(page, false);
    await page.tap("#nav-dashboard");
    await connected(page, "/");
    seen = await rail(page);
    check(seen.firstAttr === null, "an expanded rail was rendered remembered: " + JSON.stringify(seen));
    check(seen.firstRender > RAIL + 40, "the first render after expanding showed the rail");
    await expectRail(page, false, "the rail stayed collapsed after expanding");

    // Collapsed in landscape, the phone turned upright: the off-canvas
    // sidebar stays closed, on the first render and once connected.
    await toggle(page, true);
    await page.setViewportSize(PHONE_PORTRAIT);
    await page.goto(base + "/securities");
    await connected(page, "/securities");
    seen = await rail(page);
    check(seen.firstRight <= 0, "upright, the first render opened the off-canvas sidebar: " + JSON.stringify(seen));
    const drawer = await page.evaluate(() => ({
      right: document.getElementById("app-sidebar").getBoundingClientRect().right,
      checked: document.getElementById("app-sidebar-toggle").checked,
      attr: document.documentElement.getAttribute("data-rail")
    }));
    check(drawer.right <= 0, "upright, the remembered rail opened the off-canvas sidebar: " + JSON.stringify(drawer));
    check(drawer.checked === false, "upright, the checkbox is checked with the sidebar closed");
    check(drawer.attr === "collapsed", "upright, the remembered rail was dropped");

    // A mounted page narrowed across the breakpoint (closing act, P2): the
    // phone turned upright, or a desktop window dragged narrow, with the
    // rail collapsed. Below 900 px a checked box opens the off-canvas
    // sidebar, so the drawer must stay closed; widened again, the rail is
    // still collapsed.
    for (const wide of [PHONE_LANDSCAPE, DESKTOP]) {
      const at = wide.width + " px";
      await page.setViewportSize(wide);
      await page.goto(base + "/securities");
      await connected(page, "/securities");
      await expectRail(page, true, "at " + at + " the remembered rail was not collapsed");
      check(await checked(page), "at " + at + " the collapsed rail's checkbox is not checked");

      await page.setViewportSize(PHONE_PORTRAIT);
      await expectDrawerClosed(page, "narrowed from " + at + ", the off-canvas sidebar opened");

      await page.setViewportSize(wide);
      await expectRail(page, true, "widened back to " + at + ", the rail was not collapsed");
      check(await checked(page), "widened back to " + at + ", the checkbox is not checked");
      check(
        (await page.evaluate(() => document.documentElement.getAttribute("data-rail"))) === null,
        "widened back to " + at + ", the remembered rail stayed on <html>"
      );
    }

    await context.close();
    process.stdout.write(JSON.stringify({ ok: true }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
