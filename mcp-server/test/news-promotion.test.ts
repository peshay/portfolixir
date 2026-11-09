import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { callTool, listTools } from "../src/tools.js";
import { createRecordingClient } from "./support/recording-client.js";

// ADR-0056 §8 and ADR-0044's amendment of 2026-11-06 (Sprint 28, N5): a
// story becomes a research note through notes.append with its cluster_id,
// and events.create takes a news item as its source.
const APPEND = "portfolixir.notes.append";
const EVENT = "portfolixir.events.create";

const tool = (name: string) => listTools().find((entry) => entry.name === name);

describe("from story to knowledge", () => {
  // User story (ADR-0056 §8):
  // As the operating agent that judged a story worth keeping,
  // I want notes.append to take its cluster_id with my body, and the
  // headline, event type and tone I may change,
  // so that one call keeps it, and the companion refuses before any
  // request what the server would refuse.
  //
  // Acceptance criteria:
  // - With cluster_id and body the call reaches POST
  //   /api/v1/securities/:id/notes with the note as sent, headline, event
  //   type and tone included (null as null).
  // - as_of, source_url or source_quality beside cluster_id, and a note
  //   without cluster_id missing kind, source_quality or as_of, are refused
  //   before any request; an event type outside the eight and a tone of 2
  //   are refused.
  // - The description names cluster_id, the fields the server sets and
  //   that the story is promoted; the schema lists headline, event_type and
  //   tone.
  it("notes.append takes cluster_id and refuses the story's own fields beside it", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });
    const note = { cluster_id: 9, body: "Kept.", headline: null, event_type: "guidance", tone: -1 };

    await callTool(client, APPEND, { security_id: 7, note });
    assert.deepEqual(requests, [
      { method: "POST", path: "/api/v1/securities/7/notes", body: { note }, token: "Bearer api-token" }
    ]);

    for (const extra of [{ as_of: "2026-11-01" }, { source_url: "https://x.example.org" }, { source_quality: "primary" }]) {
      await assert.rejects(callTool(client, APPEND, { security_id: 7, note: { ...note, ...extra } }), /send none beside it/);
    }

    await assert.rejects(
      callTool(client, APPEND, { security_id: 7, note: { kind: "evidence", body: "x", as_of: "2026-11-01" } }),
      /required without cluster_id/
    );

    for (const bad of [{ event_type: "noise" }, { tone: 2 }]) {
      await assert.rejects(callTool(client, APPEND, { security_id: 7, note: { ...note, ...bad } }));
    }

    assert.equal(requests.length, 1);

    const description = tool(APPEND)?.description ?? "";
    assert.match(description, /A news story: cluster_id and body/);
    assert.match(description, /as_of, source_url, source_quality \(send none\)/);
    assert.match(description, /and promotes it/);
    assert.match(description, /evidence and event_result only/);

    const properties = (tool(APPEND)?.inputSchema as any).properties.note.properties;
    for (const field of ["cluster_id", "headline", "event_type", "tone"]) {
      assert.ok(properties[field], field);
    }
    assert.deepEqual((tool(APPEND)?.inputSchema as any).properties.note.required, ["body"]);
  });

  // User story (ADR-0056 §8; ADR-0048):
  // As the operating agent recording a date a news item announced,
  // I want events.create to take the item's news_id as its source,
  // so that I do not copy its link and source quality.
  //
  // Acceptance criteria:
  // - With news_id and no source_quality the call reaches the API with the
  //   event as sent.
  // - source_url or source_quality beside news_id, and neither news_id nor
  //   source_quality, are refused before any request.
  it("events.create takes news_id in place of source_url and source_quality", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });
    const event = { kind: "earnings", date: "2026-12-01", timing: "exact", news_id: 5 };

    await callTool(client, EVENT, { security_id: 7, event });
    assert.deepEqual(requests[0].body, { event });

    await assert.rejects(callTool(client, EVENT, { security_id: 7, event: { ...event, source_quality: "primary" } }), /send neither/);
    await assert.rejects(callTool(client, EVENT, { security_id: 7, event: { ...event, source_url: "https://x.example.org" } }), /send neither/);

    const { news_id: _dropped, ...unsourced } = event;
    await assert.rejects(callTool(client, EVENT, { security_id: 7, event: unsourced }), /required without news_id/);

    assert.equal(requests.length, 1);
    assert.ok((tool(EVENT)?.inputSchema as any).properties.event.properties.news_id);
  });
});
