import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { allTools, type ToolDefinition } from "../src/tools.js";
import { connectCompanion } from "./support/companion.js";
import { createRecordingClient } from "./support/recording-client.js";

// A name no tool takes, at any depth.
const STRAY = "zz_not_an_argument";

// A step into a tool's input: a property's name, or 0 for an array's item.
type Step = string | 0;

interface InputObject {
  path: Step[];
  /** A free map: its keys are data, so the schema names no property. */
  freeMap: boolean;
}

// Every object a tool's published input holds, the input itself first, with
// the path that reaches it.
function* inputObjects(schema: any, path: Step[] = []): Generator<InputObject> {
  if (schema === null || typeof schema !== "object") {
    return;
  }

  if (schema.properties !== undefined) {
    yield { path, freeMap: false };
  } else if ([schema.type].flat().includes("object")) {
    yield { path, freeMap: true };
  }

  for (const [key, value] of Object.entries<any>(schema.properties ?? {})) {
    yield* inputObjects(value, [...path, key]);
  }

  if (schema.items !== undefined) {
    yield* inputObjects(schema.items, [...path, 0]);
  }

  // An object offered as one of several shapes stands where its property
  // stands, so it is asked the same question at the same path.
  for (const branch of schema.anyOf ?? []) {
    yield* inputObjects(branch, path);
  }
}

// Arguments that reach the object at `path` and put `value` there.
function reaching(path: Step[], value: unknown): unknown {
  return path.reduceRight<unknown>((inner, step) => (step === 0 ? [inner] : { [step]: inner }), value);
}

// Whether the validator refuses STRAY inside the object at `path`, as an
// argument the object does not take.
function refusesStray(tool: ToolDefinition, path: Step[]): boolean {
  const result = tool.zodSchema.safeParse(reaching(path, { [STRAY]: "1" }));

  return (
    !result.success &&
    result.error.issues.some(
      (issue: any) =>
        issue.code === "unrecognized_keys" &&
        issue.keys.includes(STRAY) &&
        JSON.stringify(issue.path) === JSON.stringify(path)
    )
  );
}

const where = (tool: ToolDefinition, path: Step[]) =>
  [tool.name, ...path.map((step) => (step === 0 ? "[]" : step))].join(" > ");

async function call(name: string, args: Record<string, unknown>, profile: "full" | "label" = "full") {
  const { client, requests } = createRecordingClient({ data: {} });
  const companion = await connectCompanion(client, { profile });

  try {
    const result: any = await companion.mcp.callTool({ name, arguments: args });
    return { isError: result.isError === true, text: String(result.content?.[0]?.text ?? ""), requests };
  } finally {
    await companion.close();
  }
}

describe("an argument a tool does not take", () => {
  // User story (security review 2026-11, N-08; decision D-4):
  // As the operating LLM agent calling a tool,
  // I want an argument the tool does not take refused with its name, before
  // any request,
  // so that a question the tool cannot answer, or a filter or scope it does
  // not know, is never answered by running the call without it.
  //
  // Acceptance criteria:
  // - Every tool the companion declares, under any profile, refuses an
  //   unknown argument at the top of its input.
  // - Every object inside a tool's input that names its properties (a
  //   resource's body, a row of a list, a nested setting) refuses an unknown
  //   key the same way.
  // - The free maps, whose keys are data, are the only objects that take a
  //   key their schema does not name, and they are the three named here.
  it("is refused by every tool, at every depth of its input", () => {
    const tools = allTools();
    const freeMaps: string[] = [];
    let objects = 0;

    assert.ok(tools.length >= 182, `the walk found too few tools: ${tools.length}`);

    for (const tool of tools) {
      for (const { path, freeMap } of inputObjects(tool.inputSchema)) {
        objects += 1;

        if (freeMap) {
          freeMaps.push(where(tool, path));
          assert.ok(!refusesStray(tool, path), `${where(tool, path)} is a free map and refuses a key`);
        } else {
          assert.ok(refusesStray(tool, path), `${where(tool, path)} takes an argument it does not name`);
        }
      }
    }

    assert.ok(objects >= 220, `the walk found too few objects: ${objects}`);
    assert.deepEqual(freeMaps.sort(), [
      "portfolixir.portfolios.risk > asset_class_caps",
      "portfolixir.securities.create > security > attributes",
      "portfolixir.securities.update > security > attributes"
    ]);
  });

  // Acceptance criteria:
  // - Through the server an MCP host talks to, the refusal is a tool error
  //   that names the tool and the argument, and no request reaches the API;
  //   this holds for a tool without any required argument too, under the
  //   agent's profiles and the news labeller's.
  it("answers a tool error naming the tool and the argument, and sends nothing", async () => {
    const calls: Array<[string, "full" | "label"]> = [
      ...allTools()
        .filter((tool) => (tool.inputSchema.required ?? []).length === 0)
        .map((tool): [string, "full" | "label"] => [tool.name, "full"]),
      ["portfolixir.news.unlabeled", "label"]
    ];

    assert.ok(calls.length >= 30, `too few tools without a required argument: ${calls.length}`);

    for (const [name, profile] of calls) {
      const { isError, text, requests } = await call(name, { [STRAY]: true }, profile);

      assert.equal(isError, true, name);
      assert.ok(text.includes(name), `${name}: the refusal names the tool`);
      assert.ok(text.includes(`"${STRAY}"`), `${name}: the refusal names the argument`);
      assert.deepEqual(requests, [], `${name}: no request is sent`);
    }
  });

  // User story (security review 2026-11, N-08; decision D-4):
  // As the operating LLM agent that learned dry_run on the three cascading
  // deletes and a view named view_id on the rule and snapshot tools,
  // I want a tool that takes neither to say so,
  // so that I never read a delete's or a plan write's answer as the answer
  // to the question I asked.
  //
  // Acceptance criteria:
  // - dry_run on a delete or a release that does not offer it is refused
  //   naming dry_run; nothing is sent.
  // - view_id on the target tools, which name the view `view`, is refused
  //   naming view_id; nothing is sent.
  // - The same call without the stray argument is sent as before.
  const strays: Array<[string, Record<string, unknown>, string, [string, string]]> = [
    ["portfolixir.buckets.delete", { id: 3 }, "dry_run", ["DELETE", "/api/v1/buckets/3"]],
    ["portfolixir.policy_rules.delete", { id: 3 }, "dry_run", ["DELETE", "/api/v1/policy_rules/3"]],
    ["portfolixir.transactions.delete", { id: 3 }, "dry_run", ["DELETE", "/api/v1/transactions/3"]],
    ["portfolixir.securities.delete", { id: 3 }, "dry_run", ["DELETE", "/api/v1/securities/3"]],
    ["portfolixir.splits.delete", { transaction_id: 3 }, "dry_run", ["DELETE", "/api/v1/splits/3"]],
    [
      "portfolixir.quotes.release",
      { security_id: 3, from: "2026-01-01", to: "2026-01-31" },
      "dry_run",
      ["POST", "/api/v1/securities/3/quotes/release"]
    ],
    [
      "portfolixir.targets.delete",
      { portfolio_id: 1, category_id: 2 },
      "view_id",
      ["DELETE", "/api/v1/portfolios/1/targets/2"]
    ],
    [
      "portfolixir.targets.set",
      { portfolio_id: 1, classification_id: 2, targets: [{ category_id: 5, target_weight: "0.5" }] },
      "view_id",
      ["PUT", "/api/v1/portfolios/1/targets"]
    ],
    [
      "portfolixir.portfolios.set_cash_target",
      { portfolio_id: 1, cash_target_weight: "0.1" },
      "view_id",
      ["PUT", "/api/v1/portfolios/1/cash_target"]
    ]
  ];

  it("refuses dry_run and view_id where a tool does not take them, before any request", async () => {
    for (const [name, args, stray, route] of strays) {
      const refused = await call(name, { ...args, [stray]: stray === "dry_run" ? true : 4 });

      assert.equal(refused.isError, true, name);
      assert.match(
        refused.text,
        new RegExp(`Invalid arguments for tool ${name.replaceAll(".", "\\.")}: Unrecognized key: "${stray}"`),
        name
      );
      assert.deepEqual(refused.requests, [], `${name}: no request is sent`);

      const taken = await call(name, args);

      assert.equal(taken.isError, false, name);
      assert.deepEqual(
        taken.requests.map((request) => [request.method, request.path]),
        [route],
        name
      );
    }
  });

  // Acceptance criteria:
  // - A key a resource's body does not take is refused naming the key and
  //   the object it stands in, on a create, an update and a row of a list;
  //   nothing is sent, so a misspelled amount never books without it.
  it("names the object an unknown key stands in", async () => {
    const transaction = {
      portfolio_id: 1,
      type: "deposit",
      date: "2026-03-02",
      currency_code: "EUR",
      cash_account_id: 2,
      gross_amount: "100"
    };
    const nested: Array<[string, Record<string, unknown>, RegExp]> = [
      [
        "portfolixir.transactions.create",
        { transaction: { ...transaction, fee: "1.50" } },
        /Unrecognized key: "fee" at transaction/
      ],
      [
        "portfolixir.transactions.update",
        { id: 9, transaction: { note: "a synthetic note" } },
        /Unrecognized key: "note" at transaction/
      ],
      [
        "portfolixir.buckets.update",
        { id: 2, bucket: { dimension: "scope" } },
        /Unrecognized key: "dimension" at bucket/
      ],
      [
        "portfolixir.quotes.upsert",
        { security_id: 3, quotes: [{ date: "2026-03-02", close: "10", currency: "EUR" }] },
        /Unrecognized key: "currency" at quotes\.0/
      ],
      [
        "portfolixir.portfolios.risk",
        { portfolio_id: 1, hhi_bands: { low: "1500", medium: "2000" } },
        /Unrecognized key: "medium" at hhi_bands/
      ]
    ];

    for (const [name, args, refusal] of nested) {
      const { isError, text, requests } = await call(name, args);

      assert.equal(isError, true, name);
      assert.match(text, refusal, name);
      assert.ok(text.includes(name), `${name}: the refusal names the tool`);
      assert.deepEqual(requests, [], `${name}: no request is sent`);
    }
  });

  // Acceptance criteria:
  // - A free map keeps taking keys its schema does not name: a security's
  //   attributes reach the API as they were sent.
  it("leaves a free map's keys to the caller", async () => {
    const { isError, requests } = await call("portfolixir.securities.update", {
      id: 7,
      security: { attributes: { region: "synthetic", [STRAY]: "kept" } }
    });

    assert.equal(isError, false);
    assert.deepEqual(requests.map((request) => request.body), [
      { security: { attributes: { region: "synthetic", [STRAY]: "kept" } } }
    ]);
  });
});
