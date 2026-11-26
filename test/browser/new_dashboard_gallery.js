// „Neues Dashboard“'s gallery and its dialog (Sprint 32 S4; board
// ux-design-2026-11-25-sprint32/03 ① and ②), driven in a real Chromium by
// test/browser/new_dashboard_gallery_test.exs, which boots the endpoint
// and passes the base URL as JSON in the only argument. LiveViewTest
// applies no CSS, so this is where the S32 closing act's two style
// findings are measured, at 1200 and at 393 px: the groups' headings are
// the board's small muted labels, not the section headings an older rule
// (`.workspace-section h2`) drew at 20 px, and the dialog's buttons keep
// the dialog's padding, which `.modal > .modal-footer` never gave a
// footer inside the form.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "error":
// "..."}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");
const { settle, visit, leave } = require("./settle");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;
const SIZES = [
  { width: 1200, height: 900 },
  { width: 393, height: 852 }
];

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function walk(browser, viewport) {
  const at = String(viewport.width);
  const ctx = await browser.newContext({ viewport });
  const page = await ctx.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error && error.message)));
  await visit(page, base + "/dashboards/new?locale=de");
  const state = await settle(page);
  check(state.connected && state.settled, at + ": the gallery did not settle: " + JSON.stringify(state));

  const heads = await page.evaluate(() => {
    const body = getComputedStyle(document.body).color;
    return [...document.querySelectorAll(".gallery-group")].map((h) => {
      const style = getComputedStyle(h);
      return { text: h.textContent.trim(), size: parseFloat(style.fontSize), muted: style.color !== body };
    });
  });
  console.error(at + " headings: " + JSON.stringify(heads));
  check(heads.length === 2, at + ": the gallery shows no two groups: " + JSON.stringify(heads));
  const loud = heads.filter((h) => h.size > 12.5 || !h.muted);
  check(loud.length === 0, at + ": a group heading is not a small muted label: " + JSON.stringify(loud));

  await page.click("[data-template='krypto_lover']");
  try {
    await page.waitForFunction(() => {
      const d = document.getElementById("new-dashboard-dialog");
      return d !== null && d.open;
    }, null, { timeout: 10000 });
  } catch (_timeout) {
    throw new Error(at + ": the dialog did not open");
  }
  const footer = await page.evaluate(() => {
    const dialog = document.getElementById("new-dashboard-dialog").getBoundingClientRect();
    const create = document.querySelector("#new-dashboard-form button[type='submit']").getBoundingClientRect();
    const cancel = document.querySelector("#new-dashboard-form [data-role='new-dashboard-cancel']").getBoundingClientRect();
    return { right: dialog.right - create.right, bottom: dialog.bottom - create.bottom, left: cancel.left - dialog.left };
  });
  console.error(at + " footer: " + JSON.stringify(footer));
  check(
    footer.right >= 16 && footer.bottom >= 16 && footer.left >= 16,
    at + ": the dialog's buttons touch its edges: " + JSON.stringify(footer)
  );

  check(errors.length === 0, at + ": the page raised a script error: " + errors.join(" | "));
  await leave(ctx);
}

(async () => {
  const browser = await launchChromium();
  try {
    for (const viewport of SIZES) await walk(browser, viewport);
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
