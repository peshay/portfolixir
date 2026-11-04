// Launches the Chromium every browser script drives (Sprint 24 M1, plan
// D-5). CI installs the Chromium of the Playwright version this directory's
// lockfile pins (`npx --prefix test/browser playwright install --with-deps
// chromium`), and `launch()` finds it with no option. A machine that brings
// its own Chromium, such as a cloud container with a browser preinstalled
// for another Playwright release, names it in
// PLAYWRIGHT_CHROMIUM_EXECUTABLE and runs the scripts unchanged.
"use strict";

const { chromium } = require("playwright");

function launchChromium() {
  const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE;
  return chromium.launch(executablePath ? { executablePath } : {});
}

module.exports = { launchChromium };
