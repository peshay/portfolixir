// The page with the browser's site storage blocked (Sprint 29 M4, #1439),
// driven in a real Chromium by test/browser/storage_blocked_test.exs, which
// boots the endpoint and passes its base URL as the only argument. A
// browser that blocks site data throws a SecurityError as soon as a script
// reads `window.localStorage` or `window.sessionStorage`; the init script
// below makes both getters throw the same way before any of the page's own
// scripts run. The page must still connect, come up in the system theme and
// the default accent, follow the system's colour scheme, and let the theme
// and accent controls change the page.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { visit, leave } = require("./settle");

const base = process.argv[2];
// --color-bg in app.css: the light :root and the dark media block.
const LIGHT_BG = "#f6f7fa";
const DARK_BG = "#0b0f14";

function check(condition, message) {
  if (!condition) throw new Error(message);
}

// Runs in the page before its own scripts: what a browser that blocks site
// data does on a storage read.
function blockStorage() {
  for (const name of ["localStorage", "sessionStorage"]) {
    Object.defineProperty(window, name, {
      configurable: true,
      get() {
        throw new DOMException("Access is denied for this document.", "SecurityError");
      }
    });
  }
}

async function shown(page) {
  return page.evaluate(() => {
    const root = document.documentElement;
    const pressed = (selector) =>
      [...document.querySelectorAll(selector)]
        .filter((el) => el.getAttribute("aria-pressed") === "true")
        .map((el) => el.dataset.themeChoice || el.dataset.accentChoice);
    return {
      theme: root.dataset.theme || null,
      accent: root.dataset.accent || null,
      bg: getComputedStyle(root).getPropertyValue("--color-bg").trim(),
      themePressed: pressed("[data-theme-control] [data-theme-choice]"),
      accentPressed: pressed("[data-accent-control] [data-accent-choice]")
    };
  });
}

async function waitFor(page, predicate, arg, message) {
  try {
    await page.waitForFunction(predicate, arg, { timeout: 5000, polling: "raf" });
  } catch (_) {
    throw new Error(message + ": " + JSON.stringify(await shown(page)));
  }
}

(async () => {
  const browser = await launchChromium();
  try {
    const context = await browser.newContext({ colorScheme: "dark", viewport: { width: 1200, height: 800 } });
    await context.addInitScript(blockStorage);
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(String(error && error.message)));

    await visit(page, base + "/");
    check(
      await page.evaluate(() => {
        try {
          return window.localStorage && false;
        } catch (error) {
          return error.name === "SecurityError";
        }
      }),
      "the storage block is not in place"
    );

    try {
      await page.waitForFunction(() => document.querySelector("[data-phx-main].phx-connected") !== null, null, {
        timeout: 15000
      });
    } catch (_) {
      throw new Error("with storage blocked the page did not connect; page errors: " + JSON.stringify(errors));
    }

    let seen = await shown(page);
    check(seen.theme === "system", "with storage blocked the theme is not the system one: " + JSON.stringify(seen));
    check(seen.accent === "violet", "with storage blocked the accent is not the default: " + JSON.stringify(seen));
    check(seen.bg === DARK_BG, "a dark system did not give the dark page: " + JSON.stringify(seen));
    check(
      JSON.stringify(seen.themePressed) === '["system"]' && JSON.stringify(seen.accentPressed) === '["violet"]',
      "the controls do not mark the system theme and the default accent: " + JSON.stringify(seen)
    );

    // The system turns light: the page follows it.
    await page.emulateMedia({ colorScheme: "light" });
    await waitFor(
      page,
      (bg) => getComputedStyle(document.documentElement).getPropertyValue("--color-bg").trim() === bg,
      LIGHT_BG,
      "a light system did not give the light page"
    );

    // The controls still change the page, for this page, with nothing kept.
    await page.click("[data-theme-control] summary");
    await page.click("[data-theme-control] [data-theme-choice='dark']");
    await waitFor(page, () => document.documentElement.dataset.theme === "dark", null, "the theme control did not apply dark");
    await page.click("[data-accent-control] summary");
    await page.click("[data-accent-control] [data-accent-choice='teal']");
    await waitFor(page, () => document.documentElement.dataset.accent === "teal", null, "the accent control did not apply teal");

    // A LiveView update re-syncs the controls: they keep showing the choice
    // the page shows, not the default an unreadable storage would give.
    await page.evaluate(() => document.dispatchEvent(new Event("phx:update")));
    seen = await shown(page);
    check(
      JSON.stringify(seen.themePressed) === '["dark"]' && JSON.stringify(seen.accentPressed) === '["teal"]',
      "after an update the controls do not mark the shown theme and accent: " + JSON.stringify(seen)
    );
    check(seen.bg === DARK_BG, "the dark choice did not give the dark page: " + JSON.stringify(seen));

    check(errors.length === 0, "the page threw: " + JSON.stringify(errors));

    await leave(context);
    process.stdout.write(JSON.stringify({ ok: true }) + "\n");
  } catch (error) {
    process.stdout.write(JSON.stringify({ ok: false, error: String(error && error.message) }) + "\n");
  } finally {
    await leave(browser);
  }
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
