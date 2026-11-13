import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ADMIN_TOOLS, BOOK_KEPT_DESTRUCTIVE, profileRefusal } from "../src/profiles.js";
import { callTool, listTools } from "../src/tools.js";
import { connectCompanion } from "./support/companion.js";
import { createRecordingClient } from "./support/recording-client.js";

// Sprint 29, D3 (#1413): the three logo writes the API has served since
// LogoController landed, reached through the companion, calling the API only
// (ADR-0002). They add no endpoint and no semantics.
const PUT = "portfolixir.securities.logo_put";
const DELETE = "portfolixir.securities.logo_delete";
const DISCOVER = "portfolixir.securities.logo_discover";

const tool = (name: string) => listTools().find((entry) => entry.name === name);

const STATUS = {
  security_id: 7,
  path: "/security_logos/7.png",
  source: "manual",
  has_logo: true,
  locked: true,
  file_missing: false
};

describe("the security logo tools", () => {
  // User story (#1413, S2):
  // As the operator's agent connected through the companion,
  // I want to set, remove and search again for a security's logo, as the
  // operator can on the security's page and the API can over HTTP,
  // so that a logo write is a flow the agent can complete.
  //
  // Acceptance criteria:
  // - logo_put sends PUT /api/v1/securities/:security_id/logo with
  //   {logo: {url}}; logo_delete sends DELETE on the same path;
  //   logo_discover sends POST .../logo/discover with no body. Each answers
  //   the API's logo status as it came.
  // - logo_put takes an https URL only: a plain-http one, an empty one, a
  //   missing one, a field it does not take and a security_id that is not a
  //   positive integer are refused before any request; the other two take
  //   security_id and nothing else.
  it("routes each write to the existing logo endpoints and refuses what it does not take", async () => {
    const { client, requests } = createRecordingClient({ data: STATUS });

    const put = await callTool(client, PUT, { security_id: 7, url: "https://example.test/logo.png" });
    await callTool(client, DELETE, { security_id: 7 });
    await callTool(client, DISCOVER, { security_id: 7 });

    assert.deepEqual(
      requests.map((request) => [request.method, request.path, request.body]),
      [
        ["PUT", "/api/v1/securities/7/logo", { logo: { url: "https://example.test/logo.png" } }],
        ["DELETE", "/api/v1/securities/7/logo", undefined],
        ["POST", "/api/v1/securities/7/logo/discover", undefined]
      ]
    );
    assert.deepEqual(put.structuredContent, { data: STATUS });

    for (const args of [
      { security_id: 7, url: "http://example.test/logo.png" },
      { security_id: 7, url: "HTTP://example.test/logo.png" },
      { security_id: 7, url: "ftp://example.test/logo.png" },
      { security_id: 7, url: "" },
      { security_id: 7 },
      { url: "https://example.test/logo.png" },
      { security_id: 0, url: "https://example.test/logo.png" },
      { security_id: "7", url: "https://example.test/logo.png" },
      { security_id: 7, url: "https://example.test/logo.png", source: "manual" }
    ]) {
      const before = requests.length;
      await assert.rejects(callTool(client, PUT, { ...args }), JSON.stringify(args));
      assert.equal(requests.length, before, JSON.stringify(args));
    }

    for (const name of [DELETE, DISCOVER]) {
      for (const args of [{}, { security_id: 0 }, { security_id: 1.5 }, { security_id: 7, url: "https://x.test/a.png" }]) {
        const before = requests.length;
        await assert.rejects(callTool(client, name, { ...args }), `${name} ${JSON.stringify(args)}`);
        assert.equal(requests.length, before, `${name} ${JSON.stringify(args)}`);
      }
    }

    assert.equal(tool(PUT)?.inputSchema.properties.url.pattern, "^https://");
    assert.deepEqual(tool(PUT)?.inputSchema.required, ["security_id", "url"]);
    assert.equal(tool(PUT)?.inputSchema.additionalProperties, false);

    for (const name of [DELETE, DISCOVER]) {
      assert.deepEqual(tool(name)?.inputSchema.required, ["security_id"], name);
      assert.deepEqual(Object.keys(tool(name)?.inputSchema.properties ?? {}), ["security_id"], name);
    }
  });

  // User story (#1413; Sprint 17 A1's profiles, D-5's principle):
  // As the operator who lets an agent book unattended,
  // I want the two writes that set a logo in the book profile and the one
  // that deletes the stored image held with the other removals, and the two
  // that make the server fetch marked as reaching outside the instance,
  // so that a host asks before each and a book run thins out nothing.
  //
  // Acceptance criteria:
  // - logo_put: destructive and idempotent (a PUT), openWorldHint, kept in
  //   book with its reason.
  // - logo_discover: hinted as a PUT is (it replaces a discovered logo, and
  //   a repeat adds nothing), openWorldHint, kept in book with its reason; no
  //   outcome-unknown note, which promises a duplicate a retry cannot store.
  // - logo_delete: destructive and idempotent, not open-world, admin (a
  //   DELETE removes the stored file), listed in full and refused under
  //   book before any request.
  // - None is listed under read or label.
  it("hints the three, keeps put and discover in book, and holds the delete as admin", async () => {
    assert.deepEqual(tool(PUT)?.annotations, {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true
    });
    assert.deepEqual(tool(DISCOVER)?.annotations, {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: true
    });
    assert.deepEqual(tool(DELETE)?.annotations, {
      readOnlyHint: false,
      destructiveHint: true,
      idempotentHint: true,
      openWorldHint: false
    });

    assert.ok(BOOK_KEPT_DESTRUCTIVE.has(PUT));
    assert.ok(BOOK_KEPT_DESTRUCTIVE.has(DISCOVER));
    assert.ok(ADMIN_TOOLS.has(DELETE));
    assert.doesNotMatch(tool(DISCOVER)?.description ?? "", /ApiOutcomeUnknownError/);

    const listed = (profile: "read" | "book" | "full" | "label") =>
      listTools({ profile }).map((entry) => entry.name);

    for (const name of [PUT, DISCOVER]) {
      assert.ok(listed("book").includes(name), `book lists ${name}`);
    }

    assert.ok(!listed("book").includes(DELETE));

    for (const name of [PUT, DELETE, DISCOVER]) {
      assert.ok(listed("full").includes(name), `full lists ${name}`);
      assert.ok(!listed("read").includes(name), `read leaves out ${name}`);
      assert.ok(!listed("label").includes(name), `label leaves out ${name}`);
    }

    const { client, requests } = createRecordingClient({ data: STATUS });
    const companion = await connectCompanion(client, { profile: "book" });

    try {
      const refused = await companion.mcp.callTool({ name: DELETE, arguments: { security_id: 7 } });
      assert.equal(refused.isError, true);
      assert.match(JSON.stringify(refused.content), /book profile/);
      assert.equal(requests.length, 0);

      await companion.mcp.callTool({
        name: PUT,
        arguments: { security_id: 7, url: "https://example.test/logo.png" }
      });
      await companion.mcp.callTool({ name: DISCOVER, arguments: { security_id: 7 } });
      assert.deepEqual(
        requests.map((request) => [request.method, request.path]),
        [
          ["PUT", "/api/v1/securities/7/logo"],
          ["POST", "/api/v1/securities/7/logo/discover"]
        ]
      );
    } finally {
      await companion.close();
    }

    assert.match(profileRefusal("book", DELETE), /this one: Deletes the stored image/);
  });

  // User story (#1413):
  // As the agent choosing among the three,
  // I want each description to say what the server does, what it refuses
  // and what it answers,
  // so that I need not read the API reference to call them.
  //
  // Acceptance criteria:
  // - logo_put says https and a public address only, else 422, the image
  //   types and size, that the logo is locked against discovery, and that
  //   it is journaled under the token.
  // - logo_delete says the stored image is deleted and the logo locked as
  //   "no logo", that logo_put sets one again, journaled under the token.
  // - logo_discover says a locked logo, or a security no discovery source
  //   covers (a bond, a fund), answers no_source and names the other
  //   results, journaled under the token (PR 2 closing act).
  // - Each says what it returns: the logo status.
  it("says what each write does, refuses and answers", () => {
    const put = tool(PUT)?.description ?? "";
    assert.match(put, /https and a public address only, else 422/);
    assert.match(put, /png, jpeg or webp, at most 256 KiB/);
    assert.match(put, /locks it against discovery/);

    const remove = tool(DELETE)?.description ?? "";
    assert.match(remove, /deletes the stored image/);
    assert.match(remove, /"no logo"/);
    assert.match(remove, /logo_put sets one again/);

    const discover = tool(DISCOVER)?.description ?? "";
    assert.match(discover, /locked logo .* answers result no_source/);
    assert.match(discover, /, or a security no discovery source covers, answers result no_source/);
    assert.match(discover, /updated or failed/);

    for (const description of [put, remove, discover]) {
      assert.match(description, /Journaled under your token/);
      assert.match(description, /Returns the logo status/);
    }
  });
});
