// Which browser the walks launch, on its own (Sprint 31 M2, the Sprint 30
// retrospective's carry-forward 1): CI's browser job runs the walks in the
// chromium-headless-shell of the Playwright release test/browser pins, and
// a machine that launched a full Chrome instead laid the shipped Inter out
// 3 px wider and passed where CI failed. `launchChoice` in launch.js
// decides what `launchChromium` launches; this script asks it for an empty
// environment and for one that names a browser, then launches twice with
// the machine's own environment and counts the lines the launcher logged.
// Driven by launch_check_test.exs.
//
// Prints one JSON object on stdout: both choices, the choice for this
// machine's environment and the browser version each launch reported. The
// launcher's own lines go to stderr, which the test reads too.
"use strict";

const { launchChromium, launchChoice } = require("./launch");
const { leave } = require("./settle");

(async () => {
  const out = {
    bare: launchChoice({}),
    named: launchChoice({ PLAYWRIGHT_CHROMIUM_EXECUTABLE: "/opt/another/chrome" }),
    here: launchChoice(process.env),
    versions: [],
  };
  try {
    for (let i = 0; i < 2; i++) {
      const browser = await launchChromium();
      out.versions.push(browser.version());
      await leave(browser);
    }
  } catch (error) {
    out.error = String(error && error.message);
  }
  console.log(JSON.stringify(out));
})();
