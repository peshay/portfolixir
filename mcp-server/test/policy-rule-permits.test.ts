// A policy rule's status and permits are named in the companion's text
// (ADR-0059 §4): the agent reads which writes a rule accepts today off the
// list read, not from a 409. No network: the published tool list only.
import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { publishedTools } from "./support/companion.js";

const LIST = "portfolixir.policy_rules.list";
const GET = "portfolixir.policy_rules.get";

describe("a policy rule's status and permits are named in the companion's text", () => {
  // User story (ADR-0059 §4):
  // As the agent that decides whether to retire or delete a stored rule,
  // I want the list read's text to name the statuses, the permits and what
  // each permit does,
  // so that I act on the payload's `permits` instead of trying a write and
  // reading its refusal.
  //
  // Acceptance criteria:
  // - The list tool names the three statuses and the four permits, says
  //   that retire on a rule scheduled to restart cancels the restart, and
  //   that delete is permitted only while no version has been in force.
  // - The get tool points at the same keys.
  it("the list read names status, permits and what each permit does", async () => {
    const list = (await publishedTools()).find((tool) => tool.name === LIST);
    assert.ok(list, `${LIST} is published`);
    const text = list.description ?? "";

    assert.match(text, /status \(in_force \| scheduled \| retired/);
    assert.match(text, /permits/);
    for (const permit of ["add_version", "rename", "retire", "delete"]) {
      assert.match(text, new RegExp(permit), permit);
    }
    assert.match(text, /cancels the restart/);
    assert.match(text, /delete only while no version has been in force/);
  });

  it("the get read carries the same status and permits", async () => {
    const get = (await publishedTools()).find((tool) => tool.name === GET);
    assert.ok(get, `${GET} is published`);
    assert.match(get.description ?? "", /status and permits as the list read/);
  });
});
