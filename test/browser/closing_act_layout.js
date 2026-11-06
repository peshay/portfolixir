// Layout checks from Sprint 26's closing act (the design critic's and the
// UAT persona's findings), driven in a real Chromium by
// test/browser/closing_act_layout_test.exs, which boots the endpoint, seeds
// a synthetic world and passes the base URL, the case to run and the ids it
// seeded as JSON in the only argument. LiveViewTest applies no CSS, so where
// a box lands on the screen is measured here.
//
// Prints one JSON object on stdout: {"ok": true} or {"ok": false, "errors":
// ["..."]}; the exit status is 0 either way unless the browser itself fails.
"use strict";

const { launchChromium } = require("./launch");

const args = JSON.parse(process.argv[2]);
const base = args.base_url;

function check(condition, message) {
  if (!condition) throw new Error(message);
}

async function ready(page, path) {
  await page.goto(base + path);
  await page.waitForSelector("[data-phx-main].phx-connected");
}

async function nextFrame(page) {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => resolve())));
}

// V4: the delete dialog opens centred, not pinned to the page's left gutter.
async function dialogCentred(page, label) {
  await page.waitForSelector("#delete-preview-dialog[open]");
  await nextFrame(page);
  const box = await page.evaluate(() => {
    const r = document.querySelector("#delete-preview-dialog").getBoundingClientRect();
    return { left: r.left, right: document.documentElement.clientWidth - r.right };
  });
  check(
    Math.abs(box.left - box.right) <= 1,
    label + ": the dialog is not centred " + JSON.stringify(box)
  );
  await page.keyboard.press("Escape");
  await page.waitForSelector("#delete-preview-dialog", { state: "detached" });
}

async function deleteDialogs(browser) {
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  await ready(page, "/classifications/" + args.classification_id);

  await page.click("header.detail-head button.button-danger");
  await dialogCentred(page, "the classification's delete dialog at 1200");

  await page.click(
    "button[phx-click='ask_delete_category'][phx-value-id='" + args.category_id + "']"
  );
  await dialogCentred(page, "the category's delete dialog at 1200");
  await page.close();
}

const CASES = {
  delete_dialogs: deleteDialogs
};

(async () => {
  const browser = await launchChromium();
  const errors = [];
  try {
    await CASES[args.case](browser);
  } catch (error) {
    errors.push(String(error && error.message));
  } finally {
    await browser.close();
  }
  const result = errors.length === 0 ? { ok: true } : { ok: false, errors };
  process.stdout.write(JSON.stringify(result) + "\n");
})().catch((error) => {
  process.stderr.write(String(error && error.stack) + "\n");
  process.exit(2);
});
