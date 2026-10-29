// A policy rule's new version, hinted and placed as the write it is
// (security review 2026-10-12, H13): portfolixir.policy_rules.add_version
// closes the version in force and replaces the scheduled versions from its
// date, the effects for which portfolixir.policy_rules.retire is hinted
// destructive and held in ADMIN_TOOLS. Fetch is faked (recording client); no
// network.
import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ADMIN_TOOLS } from "../src/profiles.js";
import { callTool } from "../src/tools.js";
import { publishedTools } from "./support/companion.js";
import { createRecordingClient } from "./support/recording-client.js";

const ADD = "portfolixir.policy_rules.add_version";
const RETIRE = "portfolixir.policy_rules.retire";

// A synthetic loosened line: the operator's 10 % single-name cap as 60 %.
const LOOSENED = {
  id: 1,
  version: {
    subject_type: "security",
    security_id: 7,
    measure: "weight",
    kind: "cap",
    threshold: "60",
    severity: "hard",
    valid_from: "2026-10-19"
  }
};

describe("a policy rule's new version is hinted and placed as the write it is", () => {
  // User story (security review 2026-10-12, H13):
  // As the operator whose host asks before a destructive call, and who runs
  // the agent under the book profile,
  // I want the new-version write, which closes the version in force and
  // replaces scheduled ones, hinted destructive and held with the admin
  // tools, as the retirement is,
  // so that neither a host keyed on hints nor a book run changes my standard
  // unconfirmed.
  //
  // Acceptance criteria:
  // - retire stays destructive and admin (the control).
  // - add_version's description names both changes, and it carries
  //   destructiveHint true.
  // - The book profile neither lists add_version nor sends its request.
  it("control: retire (closes the version in force, drops scheduled ones) is destructive and admin", async () => {
    const retire = (await publishedTools()).find((tool) => tool.name === RETIRE);
    assert.equal(retire?.annotations?.destructiveHint, true);
    assert.ok(ADMIN_TOOLS.has(RETIRE));
    assert.ok(!(await publishedTools({ profile: "book" })).some((tool) => tool.name === RETIRE));
  });

  it("tools/list hints add_version destructive, as its own description reads", async () => {
    const add = (await publishedTools()).find((tool) => tool.name === ADD);
    assert.ok(add, `${ADD} is published`);

    // The tool's own text names the two changes to stored rows ...
    assert.match(add.description ?? "", /the previous version is closed the day before/);
    assert.match(add.description ?? "", /only scheduled .* is replaced by adding a version/);

    // ... so a host that confirms destructive calls must be told.
    assert.equal(
      add.annotations?.destructiveHint,
      true,
      `${ADD} is published with ${JSON.stringify(add.annotations)}`
    );
  });

  it("the book profile neither lists add_version nor sends its request", async () => {
    const listed = (await publishedTools({ profile: "book" })).some((tool) => tool.name === ADD);
    const { client, requests } = createRecordingClient({ data: { id: 2, threshold: "60" } });
    let refusal = "";

    try {
      await callTool(client, ADD, LOOSENED, { profile: "book" });
    } catch (error) {
      refusal = String(error);
    }

    assert.deepEqual(
      {
        listed_under_book: listed,
        refused_under_book: /book profile/.test(refusal),
        requests_sent: requests.map((request) => `${request.method} ${request.path}`)
      },
      { listed_under_book: false, refused_under_book: true, requests_sent: [] }
    );
  });
});
