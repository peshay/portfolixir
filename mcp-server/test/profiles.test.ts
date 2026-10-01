import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  ADMIN_TOOLS,
  BOOK_KEPT_DESTRUCTIVE,
  MCP_PROFILES,
  profileSwitch
} from "../src/profiles.js";
import { callTool, listTools } from "../src/tools.js";
import { connectCompanion, publishedTools } from "./support/companion.js";
import { createRecordingClient } from "./support/recording-client.js";

// Sprint 17, Lane A1 (#992; plan D-5): one companion, one switch with three
// levels. The admin set is the list `book` leaves out; the meta-test below is
// what forces a choice for every tool that can overwrite or remove.

const removes = (name: string) => {
  const tool = listTools().find((candidate) => candidate.name === name);
  return tool?.method === "DELETE" || name === "portfolixir.quotes.release";
};

describe("the companion's tool profiles", () => {
  // User story (A1, #992):
  // As the operator configuring the companion,
  // I want one variable with three levels, the old read-only switch still
  // honoured, and a conflicting pair refused at boot,
  // so that an upgrade changes nothing and a contradiction never runs.
  //
  // Acceptance criteria:
  // - PORTFOLIXIR_MCP_PROFILE takes read, book or full (any case, trimmed);
  //   unset or empty is full.
  // - PORTFOLIXIR_MCP_READ_ONLY=true alone is read; beside PROFILE=read it
  //   agrees; beside PROFILE=book or full it stops the companion with both
  //   variables named.
  // - READ_ONLY=false (the shipped default) only means the switch is off, so
  //   it never conflicts with a profile.
  // - An unknown profile, or an unreadable READ_ONLY, stops the companion with
  //   its variable named.
  it("reads the profile and the read-only switch together, strictly", () => {
    assert.deepEqual([...MCP_PROFILES], ["read", "book", "full"]);

    for (const readOnly of [undefined, "", "0", "false", " FALSE "]) {
      assert.equal(profileSwitch(undefined, readOnly), "full", String(readOnly));
      assert.equal(profileSwitch("", readOnly), "full", String(readOnly));
      assert.equal(profileSwitch("read", readOnly), "read", String(readOnly));
      assert.equal(profileSwitch(" Book ", readOnly), "book", String(readOnly));
      assert.equal(profileSwitch("FULL", readOnly), "full", String(readOnly));
    }

    for (const readOnly of ["1", "true", " TRUE "]) {
      assert.equal(profileSwitch(undefined, readOnly), "read", readOnly);
      assert.equal(profileSwitch("", readOnly), "read", readOnly);
      assert.equal(profileSwitch("read", readOnly), "read", readOnly);

      for (const profile of ["book", "full"]) {
        assert.throws(
          () => profileSwitch(profile, readOnly),
          (error: Error) =>
            /PORTFOLIXIR_MCP_PROFILE/.test(error.message) &&
            /PORTFOLIXIR_MCP_READ_ONLY/.test(error.message) &&
            error.message.includes(profile),
          `${profile} beside READ_ONLY=${readOnly}`
        );
      }
    }

    for (const profile of ["admin", "write", "readonly", "true", "ful"]) {
      assert.throws(
        () => profileSwitch(profile, undefined),
        /PORTFOLIXIR_MCP_PROFILE must be read, book or full/,
        profile
      );
    }

    for (const readOnly of ["yes", "on", "2"]) {
      assert.throws(() => profileSwitch("book", readOnly), /PORTFOLIXIR_MCP_READ_ONLY/, readOnly);
    }
  });

  // User story (A1, #992; D-5's principle):
  // As the operator who lets an agent book unattended,
  // I want every tool that can overwrite or remove to be placed on purpose,
  // either in the admin set the book profile leaves out or in the list of
  // overwrites it keeps, each with its reason,
  // so that a new destructive tool cannot reach a book run by default.
  //
  // Acceptance criteria:
  // - Every tool with destructiveHint sits in exactly one of the two lists.
  // - Every entry names a tool that exists, and carries a one-line reason.
  // - Every book-kept entry is destructive; every admin entry is a write.
  // - Every tool that removes, and every merge, is admin; the plan
  //   activation, which the previous plan's activation undoes, is kept.
  it("places every destructive tool in exactly one list, with its reason", () => {
    const tools = listTools();
    const byName = new Map(tools.map((tool) => [tool.name, tool]));

    for (const tool of tools.filter((candidate) => candidate.annotations.destructiveHint)) {
      const placed = [ADMIN_TOOLS.has(tool.name), BOOK_KEPT_DESTRUCTIVE.has(tool.name)];
      assert.equal(
        placed.filter(Boolean).length,
        1,
        `${tool.name} carries destructiveHint: place it in ADMIN_TOOLS or BOOK_KEPT_DESTRUCTIVE (src/profiles.ts)`
      );
    }

    for (const [list, entries] of [
      ["ADMIN_TOOLS", ADMIN_TOOLS],
      ["BOOK_KEPT_DESTRUCTIVE", BOOK_KEPT_DESTRUCTIVE]
    ] as const) {
      for (const [name, reason] of entries) {
        assert.ok(byName.has(name), `${list} names ${name}, which is no tool`);
        assert.ok(reason.trim().length > 10, `${list}: ${name} needs its reason`);
        assert.doesNotMatch(reason, /\n/, `${list}: ${name}'s reason is one line`);
      }
    }

    for (const name of BOOK_KEPT_DESTRUCTIVE.keys()) {
      assert.equal(byName.get(name)?.annotations.destructiveHint, true, name);
    }

    for (const name of ADMIN_TOOLS.keys()) {
      assert.equal(byName.get(name)?.annotations.readOnlyHint, false, name);
    }

    for (const tool of tools) {
      if (removes(tool.name) || tool.name.endsWith(".merge")) {
        assert.ok(ADMIN_TOOLS.has(tool.name), `${tool.name} removes or merges: it is admin`);
      }
    }

    for (const name of [
      "portfolixir.cash_accounts.remove_former_name",
      "portfolixir.securities_accounts.remove_former_name",
      "portfolixir.securities.delete_isin_alias",
      "portfolixir.securities.isin_change",
      "portfolixir.policy_rules.retire",
      "portfolixir.quotes.release"
    ]) {
      assert.ok(ADMIN_TOOLS.has(name), name);
    }

    assert.ok(BOOK_KEPT_DESTRUCTIVE.has("portfolixir.plans.activate"));
  });

  // User story (A1, #992):
  // As the operator choosing a profile,
  // I want each profile to list exactly its tools to the host,
  // so that the agent only sees what it may call.
  //
  // Acceptance criteria:
  // - read lists exactly the tools with readOnlyHint.
  // - book lists every tool but the admin set: the reads, every create, and
  //   the overwrites it keeps.
  // - full, and no profile at all, list every tool.
  it("lists exactly each profile's tools to the host", async () => {
    const all = listTools().map((tool) => tool.name);
    const names = async (profile?: "read" | "book" | "full") =>
      (await publishedTools(profile === undefined ? {} : { profile })).map((tool) => tool.name);

    assert.deepEqual(
      await names("read"),
      listTools()
        .filter((tool) => tool.annotations.readOnlyHint)
        .map((tool) => tool.name)
    );

    const book = await names("book");
    assert.deepEqual(
      book,
      all.filter((name) => !ADMIN_TOOLS.has(name))
    );

    for (const tool of listTools()) {
      const creates = !tool.annotations.readOnlyHint && !tool.annotations.destructiveHint;

      if (creates || tool.annotations.readOnlyHint || BOOK_KEPT_DESTRUCTIVE.has(tool.name)) {
        assert.ok(book.includes(tool.name), `book lists ${tool.name}`);
      }
    }

    assert.ok(!book.some((name) => ADMIN_TOOLS.has(name)));
    assert.deepEqual(await names("full"), all);
    assert.deepEqual(await names(), all);
    assert.deepEqual(
      listTools({ profile: "book" }).map((tool) => tool.name),
      book
    );
  });

  // User story (A1, #992; D-14's security lens):
  // As the operator whose agent may call a tool it guessed or cached,
  // I want a tool its profile leaves out refused at the call itself, before
  // any request, with the profile and the variable named,
  // so that the listing is not the only line of defence.
  //
  // Acceptance criteria:
  // - Under book, every admin tool is refused as a tool error naming the book
  //   profile and PORTFOLIXIR_MCP_PROFILE, and no API request is made.
  // - Under book, a create and a kept overwrite reach the API.
  // - Under read, the refusal names the read profile and both variables.
  it("refuses a tool its profile leaves out at the call, before any request", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });
    const companion = await connectCompanion(client, { profile: "book" });

    try {
      for (const name of [
        "portfolixir.transactions.delete",
        "portfolixir.securities.merge",
        "portfolixir.quotes.release",
        "portfolixir.cash_accounts.remove_former_name"
      ]) {
        const refused = await companion.mcp.callTool({ name, arguments: {} });
        assert.equal(refused.isError, true, name);
        const text = (refused.content as any)[0].text;
        assert.match(text, new RegExp(name.replaceAll(".", "\\.")), name);
        assert.match(text, /book profile/, name);
        assert.match(text, /PORTFOLIXIR_MCP_PROFILE=book/, name);
        assert.match(text, /full/, name);
      }

      assert.equal(requests.length, 0);

      await companion.mcp.callTool({
        name: "portfolixir.transactions.update",
        arguments: { id: 9, transaction: { notes: "corrected" } }
      });
      await companion.mcp.callTool({
        name: "portfolixir.views.create",
        arguments: { view: { name: "Everything" } }
      });
      assert.deepEqual(
        requests.map((request) => `${request.method} ${request.path}`),
        ["PATCH /api/v1/transactions/9", "POST /api/v1/views"]
      );
    } finally {
      await companion.close();
    }

    await assert.rejects(
      callTool(client, "portfolixir.views.delete", { id: 3 }, { profile: "book" }),
      /book profile.*PORTFOLIXIR_MCP_PROFILE=book/s
    );
    await assert.rejects(
      callTool(client, "portfolixir.views.create", { view: { name: "x" } }, { profile: "read" }),
      /read profile.*PORTFOLIXIR_MCP_PROFILE=read.*PORTFOLIXIR_MCP_READ_ONLY=true/s
    );
    assert.equal(requests.length, 2);
  });

  // User story (A1, #992):
  // As the agent connecting to the companion,
  // I want the server instructions to say which profile runs,
  // so that a tool I do not see is not a mystery.
  //
  // Acceptance criteria:
  // - The instructions name the active profile and the variable, in one clause.
  it("names the active profile in the server instructions", async () => {
    for (const profile of MCP_PROFILES) {
      const companion = await connectCompanion(undefined, { profile });

      try {
        const instructions = companion.mcp.getInstructions() ?? "";
        assert.match(instructions, new RegExp(`runs the ${profile} profile \\(PORTFOLIXIR_MCP_PROFILE\\)`));
      } finally {
        await companion.close();
      }
    }
  });
});
