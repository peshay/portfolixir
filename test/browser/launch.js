// Launches the Chromium every browser script drives (Sprint 24 M1, plan
// D-5; Sprint 31 M2). By default it is the chromium-headless-shell of the
// Playwright version this directory's lockfile pins, the browser CI's
// `browser` job installs (`npx --prefix test/browser playwright install
// --with-deps chromium`) and runs every walk in. *Why:* a full Chrome lays
// the shipped Inter out differently; a walk measured 3 px of margin there
// and failed in CI (Sprint 30 retrospective, carry-forward 1). The channel
// is named, not left to Playwright's default, so a later release or
// PWDEBUG cannot switch the walks to another browser unnoticed.
//
// A machine that brings its own browser, such as a cloud container with a
// Chromium preinstalled for another Playwright release, names it in
// PLAYWRIGHT_CHROMIUM_EXECUTABLE and runs the scripts unchanged; it then
// measures in that browser, not in CI's. Either way the first launch in a
// process logs one line on stderr naming what it launched and the
// browser's version, so a run says which browser its figures come from.
// launch_check_test.exs pins the choice.
"use strict";

const { chromium } = require("playwright");
const { version: playwrightVersion } = require("playwright/package.json");

const SHELL = "chromium-headless-shell";

// The options `launchChromium` hands Playwright for an environment, and
// the name of the browser they launch.
function launchChoice(env) {
  const executablePath = env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  if (executablePath) {
    return {
      options: { headless: true, executablePath },
      browser: `PLAYWRIGHT_CHROMIUM_EXECUTABLE=${executablePath}`,
    };
  }
  return {
    options: { headless: true, channel: SHELL },
    browser: `${SHELL} of Playwright ${playwrightVersion}`,
  };
}

let announced = false;

async function launchChromium() {
  const { options, browser: name } = launchChoice(process.env);
  const browser = await chromium.launch(options);
  if (!announced) {
    announced = true;
    console.error(`launch.js: launched ${name}, Chromium ${browser.version()}`);
  }
  return browser;
}

module.exports = { launchChromium, launchChoice };
