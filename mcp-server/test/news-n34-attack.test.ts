import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// Sprint 28 plan D-8 (carry-forwards 1 and 5): the security lens's attack
// on the companion's side of N3 (news.digest's consumer) and N4
// (news.assign): what each profile lists and what it calls.
const ASSIGN = "portfolixir.news.assign";
const DIGEST = "portfolixir.news.digest";

describe("news.assign and the digest's consumer across the profiles (N3/N4 attack)", () => {
  // User story (ADR-0054 §1, ADR-0056 §7 and §9):
  // As the operator who gives a read-only agent the read profile and the
  // labeller the label profile,
  // I want neither to list news.assign nor to call it by name, and the read
  // profile to read the digest under a consumer,
  // so that a profile narrows the tools both ways and a reader keeps its
  // bookmark.
  //
  // Acceptance criteria:
  // - The read and label profiles refuse news.assign called by name before
  //   any request; book and full send it.
  // - The read profile sends news.digest with consumer and ack_cursor as a
  //   GET; the label profile lists and calls no digest.
  // - A consumer name with + / @ : reaches the API encoded, never as a
  //   space.
  it("refuses news.assign by name in read and label, and reads the digest under a consumer in read", async () => {
    const { client, requests } = createRecordingClient({ data: { rows: [] } });

    for (const profile of ["read", "label"] as const) {
      const before = requests.length;
      await assert.rejects(
        callTool(client, ASSIGN, { news_id: 9, security_id: 12 }, { profile }),
        profile
      );
      assert.equal(requests.length, before, profile);
    }

    for (const profile of ["book", "full"] as const) {
      await callTool(client, ASSIGN, { news_id: 9, security_id: null }, { profile });
    }

    await callTool(
      client,
      DIGEST,
      { consumer: "agent+1@host:run/a", ack_cursor: "1762592400~AAAA" },
      { profile: "read" }
    );

    assert.ok(listTools({ profile: "read" }).some((entry) => entry.name === DIGEST));
    assert.ok(!listTools({ profile: "label" }).some((entry) => entry.name === DIGEST));

    const before = requests.length;
    await assert.rejects(callTool(client, DIGEST, { consumer: "label-run" }, { profile: "label" }));
    assert.equal(requests.length, before);

    assert.deepEqual(
      requests.map((request) => [request.method, request.path]),
      [
        ["PUT", "/api/v1/news/items/9/assignment"],
        ["PUT", "/api/v1/news/items/9/assignment"],
        [
          "GET",
          "/api/v1/news/digest?consumer=agent%2B1%40host%3Arun%2Fa&ack_cursor=1762592400%7EAAAA"
        ]
      ]
    );
  });
});
