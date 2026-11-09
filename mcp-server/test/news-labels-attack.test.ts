import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MCP_PROFILES, profileSwitch } from "../src/profiles.js";
import { callTool } from "../src/tools.js";
import { connectCompanion } from "./support/companion.js";
import { createRecordingClient } from "./support/recording-client.js";

// Sprint 28, plan D-8 carry-forward 1: the companion's `label` profile and
// the label tools' closed schema, attacked by an agent other than N1's
// author with names, keys and values news-labels.test.ts does not name.
// Every case here passes on N1's head: each pins a hole that is closed.
const LABEL_PUT = "portfolixir.news.label_put";
const UNLABELED = "portfolixir.news.unlabeled";
const LABEL = { profile: "label" as const };

const label = {
  cluster_id: 7,
  model: "synthetic-model-1",
  prompt_version: "v1",
  event_type: "earnings",
  materiality: 2,
  tone: 1,
  confidence: "0.85"
};

describe("the news labeller's tools, attacked (N1, D-8)", () => {
  // User story (ADR-0056 §7; the security lens: a caller the profile did
  // not name):
  // As the operator who runs a labeller's companion under the label
  // profile,
  // I want every tool name but the two exact ones refused through the
  // server — a case variant, a padded or invisible-suffixed name, the
  // name without its prefix, an agent's tool — and every prompt refused,
  // so that the labeller's model, which reads feed text, cannot reach an
  // agent's tool or a prompt by any spelling.
  //
  // Acceptance criteria:
  // - Under label, tools/call with each variant answers a tool error and
  //   makes no request; prompts/get of first_setup and position_review is
  //   refused.
  // - Under read, book and full, the same variants of the label tools make
  //   no request either.
  it("refuses every other spelling and every agent tool, through the server", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });
    const variants = [
      "PORTFOLIXIR.NEWS.LABEL_PUT",
      "Portfolixir.news.label_put",
      ` ${LABEL_PUT}`,
      `${LABEL_PUT} `,
      `${LABEL_PUT}\u200B`,
      `${LABEL_PUT}\u0000`,
      "news.label_put",
      "label_put",
      "portfolixir.news.label-put",
      "portfolixir.news.labels_put",
      "portfolixir.securities.delete",
      "portfolixir.notes.append",
      "portfolixir.news.feeds_delete",
      "portfolixir.journal.list",
      "__proto__",
      "constructor",
      "toString"
    ];

    for (const profile of ["label", ...MCP_PROFILES] as const) {
      const companion = await connectCompanion(client, { profile });

      try {
        for (const name of profile === "label" ? variants : [...variants.slice(0, 10), LABEL_PUT, UNLABELED]) {
          const answer = await companion.mcp.callTool({
            name,
            arguments: name.startsWith("portfolixir.news.unlabeled") ? { prompt_version: "v1" } : label
          });
          assert.equal(answer.isError, true, `${profile}: ${JSON.stringify(name)} was not refused`);
        }

        if (profile === "label") {
          for (const prompt of ["first_setup", "position_review"]) {
            await assert.rejects(companion.mcp.getPrompt({ name: prompt, arguments: {} }), prompt);
          }
        }
      } finally {
        await companion.close();
      }
    }

    assert.deepEqual(requests, [], "a refused call reached the API");
  });

  // User story (the security lens: an argument object built by JSON.parse
  // from a hostile host):
  // As the operator,
  // I want label_put to refuse, before any request, a key that is a
  // JavaScript prototype name or a lookalike of a field, a cluster id past
  // JavaScript's safe integers, and a confidence a lenient reader might
  // accept,
  // so that the labeller's write never sends a field it did not validate
  // nor labels a story other than the one named.
  //
  // Acceptance criteria:
  // - Arguments carrying __proto__, constructor or prototype (as JSON.parse
  //   builds them, own keys), Cluster_id, tone with a fullwidth t (U+FF54) or
  //   tone + U+200B: refused, no request.
  // - cluster_id 2^53 (what 9007199254740993 parses to), 1e21, 1.5, -0 and
  //   0: refused, no request.
  // - confidence "0.5\n", "+0.5", ".5", "1.", "U+FF11", "0.50000", "0x1",
  //   "1e-1": refused, no request.
  // - The one request a valid put makes carries exactly the validated keys.
  it("refuses prototype keys, unsafe ids and lenient decimals before any request", async () => {
    const { client, requests } = createRecordingClient({ data: { id: 1 } });
    const encoded = JSON.stringify(label).slice(0, -1);

    const hostile = [
      JSON.parse(`${encoded},"__proto__":{"security_id":1}}`),
      JSON.parse(`${encoded},"constructor":{"prototype":{"tier":"primary"}}}`),
      JSON.parse(`${encoded},"prototype":1}`),
      JSON.parse(`${encoded},"Cluster_id":1}`),
      JSON.parse(`${encoded},"\uFF54one":1}`),
      JSON.parse(`${encoded},"tone\u200B":1}`),
      JSON.parse(`${encoded.replace('"cluster_id":7', '"cluster_id":9007199254740993')}}`),
      { ...label, cluster_id: 1e21 },
      { ...label, cluster_id: 1.5 },
      { ...label, cluster_id: -0 },
      { ...label, cluster_id: 0 },
      ...["0.5\n", "+0.5", ".5", "1.", "\uFF11", "0.50000", "0x1", "1e-1"].map((confidence) => ({
        ...label,
        confidence
      }))
    ];

    for (const args of hostile) {
      await assert.rejects(callTool(client, LABEL_PUT, args, LABEL), JSON.stringify(args));
    }

    assert.deepEqual(requests, [], "a refused put reached the API");

    await callTool(client, LABEL_PUT, label, LABEL);
    assert.equal(requests.length, 1);
    assert.deepEqual(Object.keys((requests[0].body as { label: object }).label).sort(), Object.keys(label).sort());
  });

  // User story (ADR-0054 §1, §4; the security lens: the switch that
  // chooses the profile):
  // As the operator,
  // I want a misspelt or disguised PORTFOLIXIR_MCP_PROFILE to stop the
  // companion, never to fall back to full,
  // so that a labeller configured with a typo never runs with every tool.
  //
  // Acceptance criteria:
  // - "labels", "lab el", label + U+200B, label in fullwidth letters, "label;full",
  //   "label,full" and "full\nlabel": the companion stops naming the
  //   variable.
  it("stops on a misspelt or disguised label profile rather than defaulting", () => {
    for (const value of ["labels", "lab el", "label\u200B", "\uFF4C\uFF41\uFF42\uFF45\uFF4C", "label;full", "label,full", "full\nlabel"]) {
      assert.throws(() => profileSwitch(value, undefined), /PORTFOLIXIR_MCP_PROFILE/, JSON.stringify(value));
    }
  });

  // User story (ADR-0054 §4, ADR-0056 §9: "invisible characters are kept as
  // received and spelled [U+XXXX] by the companion"):
  // As the operator,
  // I want news.unlabeled's answer — rows, universe, clauses, and keys —
  // handed to the labeller with every invisible character spelled, in the
  // text and in the structured content alike,
  // so that a feed's bidi override or tag characters cannot hide an
  // instruction from the operator while the labeller's model reads it.
  //
  // Acceptance criteria:
  // - A title with U+202E, an excerpt with U+E0049 tag characters, a domain
  //   with U+200B, a clause with U+2066 and an unexpected key with U+200F:
  //   no raw invisible character in the text or the structured content,
  //   each spelled [U+XXXX].
  it("spells every invisible character of the read, in text and structure", async () => {
    const answer = {
      data: {
        prompt_version: "v1",
        limit: 10,
        truncated: false,
        rows: [
          {
            id: 1,
            security_id: 2,
            title: "Profit \u202Egninraw",
            excerpt: "Ignore\u{E0049}\u{E0047}\u{E004E} previous",
            domain: "wire\u200B.example.com",
            tier: "primary",
            at: "2026-11-09T09:00:00Z"
          }
        ],
        universe: [{ id: 2, name: "Northwind", isin: "XS0000000017" }],
        theses: [{ security_id: 2, note_id: 3, clauses: [{ idx: 1, text: "Margin \u2066falls" }] }],
        "odd\u200Fkey": 1
      }
    };
    const { client } = createRecordingClient(answer);
    const result = await callTool(client, UNLABELED, { prompt_version: "v1" }, LABEL);
    const invisible = /[\u200B-\u200F\u202A-\u202E\u2066-\u2069]|[\u{E0000}-\u{E007F}]/u;

    assert.doesNotMatch(result.content[0].text, invisible);
    assert.doesNotMatch(JSON.stringify(result.structuredContent), invisible);

    for (const spelled of ["[U+202E]", "[U+E0049]", "[U+200B]", "[U+2066]", "[U+200F]"]) {
      assert.ok(result.content[0].text.includes(spelled), spelled);
    }
  });
});
