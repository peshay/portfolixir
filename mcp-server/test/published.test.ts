import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";

import { z } from "zod";

import { ApiOutcomeUnknownError, ApiReadTimeoutError, createApiClient } from "../src/api-client.js";
import { readOnlySwitch } from "../src/server.js";
import { allTools, callTool, listTools, type ToolDefinition } from "../src/tools.js";
import { connectCompanion, publishedTools } from "./support/companion.js";
import { createRecordingClient } from "./support/recording-client.js";

// The properties a structural comparison keeps: what a schema lets through
// (types, enums, properties, required, array items, and what an object does
// with a key it does not name), not how it words it.
function structure(schema: any): any {
  if (schema === null || typeof schema !== "object") {
    return schema;
  }

  if (Array.isArray(schema.anyOf)) {
    const present = schema.anyOf.filter((branch: any) => branch.type !== "null");

    if (present.length === 1 && present.length < schema.anyOf.length) {
      const inner = structure(present[0]);
      return { ...inner, type: [inner.type, "null"].flat().sort() };
    }

    return { anyOf: schema.anyOf.map(structure) };
  }

  const out: Record<string, unknown> = {};

  if (schema.type !== undefined) {
    out.type = Array.isArray(schema.type) ? [...schema.type].sort() : schema.type;
  }

  if (Array.isArray(schema.enum)) {
    out.enum = schema.enum.filter((value: unknown) => value !== null).sort();
  }

  if (schema.properties !== undefined) {
    out.properties = Object.fromEntries(
      Object.keys(schema.properties)
        .sort()
        .map((key) => [key, structure(schema.properties[key])])
    );
    out.required = [...(schema.required ?? [])].sort();
  }

  if (schema.properties !== undefined || [schema.type].flat().includes("object")) {
    out.additionalProperties = unnamedKeys(schema.additionalProperties);
  }

  if (schema.items !== undefined) {
    out.items = structure(schema.items);
  }

  return out;
}

// What an object does with a key it does not name (R-098): false refuses it;
// true takes it whatever its value, which is also what a schema says that
// leaves the keyword out; a schema takes it when its value fits. A schema that
// fits everything (`{}`, as the validator's free map reads) is true.
function unnamedKeys(additionalProperties: any): any {
  if (additionalProperties === undefined || additionalProperties === true) {
    return true;
  }

  if (additionalProperties === false) {
    return false;
  }

  const value = structure(additionalProperties);
  return Object.keys(value).length === 0 ? true : value;
}

// Every object of a published schema, the input itself first, with the path
// that reaches it.
function* objectsOf(schema: any, path: string): Generator<[string, any]> {
  if (schema === null || typeof schema !== "object") {
    return;
  }

  if (schema.properties !== undefined || [schema.type].flat().includes("object")) {
    yield [path, schema];
  }

  for (const [key, value] of Object.entries<any>(schema.properties ?? {})) {
    yield* objectsOf(value, `${path}.${key}`);
  }

  if (schema.items !== undefined) {
    yield* objectsOf(schema.items, `${path}[]`);
  }

  for (const branch of schema.anyOf ?? []) {
    yield* objectsOf(branch, path);
  }
}

// The create and update bodies whose published schema names its properties
// and leaves additionalProperties out. The validator closes them like every
// other object (N-08): a key such a body does not name is refused. Stating
// the keyword costs 29 bytes of the schema budget a body, which the budget
// does not hold today, so these are compared as the closed objects they are
// enforced as. The list only ever shrinks: a body that states the keyword
// leaves it, and a new object states the keyword.
const BODIES_WITHOUT_THE_KEYWORD = [
  "portfolixir.securities.create.security",
  "portfolixir.securities.update.security",
  "portfolixir.portfolios.create.portfolio",
  "portfolixir.cash_accounts.create.cash_account",
  "portfolixir.cash_accounts.update.cash_account",
  "portfolixir.securities_accounts.create.securities_account",
  "portfolixir.securities_accounts.update.securities_account",
  "portfolixir.transactions.create.transaction",
  "portfolixir.transactions.update.transaction",
  "portfolixir.classifications.create.classification",
  "portfolixir.classifications.update.classification",
  "portfolixir.classifications.categories.create.category",
  "portfolixir.classifications.categories.update.category",
  "portfolixir.buckets.create.bucket",
  "portfolixir.buckets.update.bucket",
  "portfolixir.views.create.view",
  "portfolixir.views.update.view"
];

// The free maps: objects whose keys are data, so their schema names none.
const FREE_MAPS = [
  "portfolixir.portfolios.risk.asset_class_caps",
  "portfolixir.securities.create.security.attributes",
  "portfolixir.securities.update.security.attributes"
];

// A tool's published input schema as the validator is held to it: the schema
// itself, with the keyword put on the bodies that leave it out.
function publishedAsEnforced(definition: ToolDefinition): any {
  const published = structuredClone(definition.inputSchema);

  for (const [path, object] of objectsOf(published, definition.name)) {
    if (BODIES_WITHOUT_THE_KEYWORD.includes(path) && object.additionalProperties === undefined) {
      object.additionalProperties = false;
    }
  }

  return published;
}

// Every property of a published schema, with the path that reaches it.
function* propertiesOf(schema: any, path: string): Generator<[string, string, any]> {
  if (schema === null || typeof schema !== "object") {
    return;
  }

  for (const [key, value] of Object.entries<any>(schema.properties ?? {})) {
    yield [`${path}.${key}`, key, value];
    yield* propertiesOf(value, `${path}.${key}`);
  }

  if (schema.items !== undefined) {
    yield* propertiesOf(schema.items, `${path}[]`);
  }

  for (const branch of schema.anyOf ?? []) {
    yield* propertiesOf(branch, path);
  }
}

// The Decimal-valued inputs the API takes (money, quantities, prices, rates,
// weights, thresholds, the recorded tax figures): each one is a string on the
// wire, never a JSON number.
const DECIMAL_NAMES = new Set([
  "quantity",
  "price",
  "gross_amount",
  "fees",
  "taxes",
  "security_amount",
  "settlement_amount",
  "settlement_fx_rate",
  "amount",
  "close",
  "target_weight",
  "cash_target_weight",
  "threshold",
  "lower",
  "upper",
  "warn",
  "hard",
  "low",
  "high",
  "min_drift",
  "risk_free_rate",
  "amount_granted",
  "allowance_granted",
  "allowance_used",
  "saver_allowance_single",
  "saver_allowance_joint",
  "capital_gains_tax_rate",
  "solidarity_surcharge_rate",
  "church_tax_rate",
  "capital_gains_tax_withheld",
  "solidarity_surcharge_withheld",
  "church_tax_withheld",
  "taxable_income",
  "loss_pot_equities",
  "loss_pot_other",
  "loss_carryforward_prior_years",
  "withholding_tax_pot",
  "withholding_tax_credited"
]);

// The HTTP method each tool routes to, read from the router's source rather
// than from the companion's own derivation, so the two are independent.
function routedMethodsFromSource(): Map<string, string> {
  const source = readFileSync(new URL("../src/tools.ts", import.meta.url), "utf8");
  const routes = new Map<string, string>();

  for (const [, name, method] of source.matchAll(
    /case "(portfolixir\.[a-z0-9_.]+)":\s*return client\.request\(\s*"([A-Z]+)"/g
  )) {
    routes.set(name, method);
  }

  // --- S29 C5 begin ---
  // One tool routes two ways by whether a key is given (ADR-0058 §9:
  // crashes.put names or edits with a key, draws without one). Its route is
  // the keyed branch's, the one the companion's own derivation reads with
  // every argument set; REPLACING_POSTS below names its hints.
  for (const [, name, method] of source.matchAll(
    /case "(portfolixir\.[a-z0-9_.]+)":\s*return args\.key === undefined\s*\?\s*client\.request\(\s*"POST"[^\n]*\n\s*:\s*client\.request\(\s*"([A-Z]+)"/g
  )) {
    routes.set(name, method);
  }
  // --- S29 C5 end ---

  // --- S31 D2 begin ---
  // dashboards.put routes three ways (ADR-0062 §8): POST without an id, and
  // with one PUT when a layout is sent, else PATCH. Its route is the keyed
  // branch's with every argument set as the companion's derivation reads
  // it (a dashboard argument with no layout: PATCH); REPLACING_POSTS below
  // names its hints.
  for (const [, name, method] of source.matchAll(
    /case "(portfolixir\.[a-z0-9_.]+)":\s*return args\.id === undefined\s*\?\s*client\.request\(\s*"POST"[^\n]*\n\s*:\s*args\.dashboard\?\.layout === undefined\s*\?\s*client\.request\(\s*"([A-Z]+)"/g
  )) {
    routes.set(name, method);
  }
  // --- S31 D2 end ---

  // --- S32 T2 begin ---
  // periods.put routes three ways: DELETE with delete: true, else POST
  // without an id and PUT with one. Its route is the delete's, the one the
  // companion's own derivation reads with every argument set; it is admin,
  // and REPLACING_POSTS below names its hints.
  for (const [, name, method] of source.matchAll(
    /case "(portfolixir\.[a-z0-9_.]+)":\s*return args\.delete\s*\?\s*client\.request\(\s*"([A-Z]+)"/g
  )) {
    routes.set(name, method);
  }
  // --- S32 T2 end ---

  return routes;
}

// The named exceptions to "the method decides", each with its reason.
const READ_ONLY_POSTS = [
  "portfolixir.splits.preview", // computes the split's effect, stores nothing
  "portfolixir.holdings.reconcile" // compares a pasted list with the ledger, stores nothing
];

// Routed through POST but remove what is stored, so they are hinted as a
// DELETE is: destructive, and idempotent, since a repeat finds nothing left.
const REMOVING_POSTS = [
  "portfolixir.quotes.release" // removes the manual quotes in a range (E25 S6, T-9)
];

// Routed through POST but change or remove stored rows, so they are hinted
// as a PUT is: destructive, and idempotent, since a repeat changes nothing
// more (a second retirement answers 409, a second activation is a no-op, a
// second ISIN change a named conflict). E25 S7 review round, R1.
const MODIFYING_POSTS = [
  "portfolixir.policy_rules.retire", // closes the version in force, drops scheduled ones
  "portfolixir.plans.activate", // archives the plan that was active
  "portfolixir.securities.isin_change", // writes the new ISIN onto the security
  // ADR-0050 §7, §10: moves every booking, deletes the source; a retry of a
  // completed merge answers the original record, so it is idempotent.
  "portfolixir.cash_accounts.merge",
  "portfolixir.securities_accounts.merge",
  // ADR-0050 §9, §10: the security merge, idempotent the same way.
  "portfolixir.securities.merge",
  // --- S29 D3 begin ---
  // #1413: replaces a discovered logo; a repeat stores no second record.
  "portfolixir.securities.logo_discover"
  // --- S29 D3 end ---
];

// Routed through POST and add a row, but close the version in force and
// replace the scheduled versions from their date (security review
// 2026-10-12, H13): destructive, and not idempotent, since a repeat adds
// another version.
const REPLACING_POSTS = [
  "portfolixir.policy_rules.add_version", // closes the version in force, replaces scheduled ones
  // --- S29 C5 begin ---
  // PUT with a key (overwrites a name or a manual window's fields), POST
  // without one (adds a manual window): destructive, and not idempotent.
  "portfolixir.crashes.put",
  // --- S29 C5 end ---
  // --- S31 D2 begin ---
  // PUT or PATCH with an id (overwrites a layout, a name or a place), POST
  // without one (adds a dashboard): destructive, and not idempotent.
  "portfolixir.dashboards.put",
  // --- S31 D2 end ---
  // --- S32 T2 begin ---
  // DELETE with delete: true, PUT with an id (overwrites a period), POST
  // without one (adds a period): destructive, and not idempotent.
  "portfolixir.periods.put"
  // --- S32 T2 end ---
];

const OPEN_WORLD = [
  "portfolixir.securities.search_online", // sends its query to the configured provider
  "portfolixir.securities.create", // queues a provider backfill and a logo lookup (R6)
  "portfolixir.quotes.sync", // the quote provider
  "portfolixir.exchange_rates.sync", // the rate feed
  // --- S29 D3 begin ---
  "portfolixir.securities.logo_put", // downloads the image its URL names (#1413)
  "portfolixir.securities.logo_discover", // asks the discovery sources (#1413)
  // --- S29 D3 end ---
  // --- S29 H6 begin ---
  "portfolixir.chains.refresh" // Bitcoin's Esplora host (ADR-0059 §3, §11)
  // --- S29 H6 end ---
];

// Writes that only ever add, and whose additions are permanent.
const APPEND_ONLY = [
  "portfolixir.notes.append",
  "portfolixir.policy_rules.create",
  "portfolixir.predictions.create"
];

describe("the companion's published tool surface", () => {
  // User story (E25 S7, F21):
  // As the operator relying on the companion's schema tests,
  // I want the schema those tests pin to be the one an MCP host receives,
  // so that a pinned property (a decimal typed as a string, a field left out)
  // is a property of what ships and not of a definition nobody publishes.
  //
  // Acceptance criteria:
  // - tools/list over a real transport publishes, for every tool, exactly the
  //   inputSchema of its definition, descriptions and closed objects included.
  // - The validator the companion enforces before any API request accepts the
  //   same properties, types, enums and required fields the published schema names.
  it("publishes every tool's input schema exactly as its definition", async () => {
    const published = await publishedTools();
    const definitions = listTools();

    assert.deepEqual(
      published.map((tool) => tool.name),
      definitions.map((tool) => tool.name)
    );

    for (const definition of definitions) {
      const tool = published.find((candidate) => candidate.name === definition.name);
      assert.deepEqual(tool?.inputSchema, definition.inputSchema, definition.name);
      assert.equal(tool?.title, definition.title, definition.name);
      assert.equal(tool?.description, definition.description, definition.name);
    }
  });

  it("enforces the properties its published schema names", async () => {
    for (const definition of allTools()) {
      const enforced = z.toJSONSchema(definition.zodSchema, { io: "input" });
      assert.deepEqual(
        structure(enforced),
        structure(publishedAsEnforced(definition)),
        `${definition.name}: the validator and the published schema disagree`
      );
    }
  });

  // User story (architecture review 2026-11, R-098, its closure half; N-08):
  // As a developer adding or changing a tool,
  // I want the test that holds a tool's published schema and its validator
  // together to compare which objects are closed as well,
  // so that a tool cannot publish a closed object and enforce an open one,
  // and a new tool cannot ship an object that takes a key it does not name.
  //
  // Acceptance criteria:
  // - The comparison above keeps, for every object of every declared tool,
  //   what the object does with a key it does not name, so the published
  //   schema and the validator agree on it (the labeller's two tools too).
  // - Every published object that names its properties states
  //   additionalProperties: false, the input itself and every object below
  //   it; the only exceptions are the bodies listed above, which leave the
  //   keyword out and are enforced closed.
  // - An object that names no property is a free map; it states what its
  //   values are, and there are exactly the three listed above.
  it("closes every object that names its properties, and names the free maps", () => {
    const withoutTheKeyword: string[] = [];
    const freeMaps: string[] = [];

    for (const definition of allTools()) {
      assert.equal(
        definition.inputSchema.additionalProperties,
        false,
        `${definition.name}: the input takes an argument it does not name`
      );

      for (const [path, object] of objectsOf(definition.inputSchema, definition.name)) {
        if (object.properties === undefined) {
          freeMaps.push(path);
          assert.ok(
            object.additionalProperties === true ||
              (typeof object.additionalProperties === "object" && object.additionalProperties !== null),
            `${path} names no property and does not say what its values are`
          );
        } else if (object.additionalProperties === undefined) {
          withoutTheKeyword.push(path);
        } else {
          assert.equal(object.additionalProperties, false, `${path} names its properties and is not closed`);
        }
      }
    }

    assert.deepEqual(withoutTheKeyword.sort(), [...BODIES_WITHOUT_THE_KEYWORD].sort());
    assert.deepEqual(freeMaps.sort(), [...FREE_MAPS].sort());
  });

  it("types every published decimal as a string and no property as a JSON number", async () => {
    let decimals = 0;

    for (const tool of await publishedTools()) {
      for (const [path, key, property] of propertiesOf(tool.inputSchema, tool.name)) {
        const types = [property.type ?? []].flat();
        assert.ok(!types.includes("number"), `${path} is published as a JSON number`);

        if (DECIMAL_NAMES.has(key) && property.type !== undefined) {
          decimals += 1;
          assert.ok(types.includes("string"), `${path} is a decimal not published as a string`);
        }
      }
    }

    assert.ok(decimals >= 60, `the scan found too few decimal properties: ${decimals}`);
  });

  // User story (E25 S7, F21, with #766):
  // As the operator reading the research log,
  // I want the append tool to publish no author and no provenance field,
  // so that the agent cannot claim to be the operator or mark its own entry
  // as confirmed: the server sets both.
  //
  // Acceptance criteria:
  // - The published notes.append schema closes the entry object and names no
  //   author, machine_generated or provenance field.
  // - An entry sent with one of those fields is refused naming the field and
  //   never reaches the API (N-08); the same entry without them is appended.
  it("publishes no author or provenance field on a research-log append", async () => {
    const append = (await publishedTools()).find((tool) => tool.name === "portfolixir.notes.append");
    const note = (append?.inputSchema as any).properties.note;

    assert.equal(note.additionalProperties, false);

    for (const field of ["author", "machine_generated", "provenance", "actor", "source_type"]) {
      assert.equal(note.properties[field], undefined, field);
    }

    const entry = {
      kind: "evidence",
      body: "a synthetic finding",
      source_quality: "primary",
      as_of: "2026-08-01"
    };
    const { client, requests } = createRecordingClient({ data: { id: 1 } });
    const companion = await connectCompanion(client);

    try {
      for (const [field, value] of [
        ["author", "operator"],
        ["machine_generated", false]
      ] as const) {
        const refused: any = await companion.mcp.callTool({
          name: "portfolixir.notes.append",
          arguments: { security_id: 7, note: { ...entry, [field]: value } }
        });

        assert.equal(refused.isError, true, field);
        assert.match(refused.content[0].text, new RegExp(`Unrecognized key: "${field}" at note`), field);
      }

      assert.equal(requests.length, 0);

      await companion.mcp.callTool({
        name: "portfolixir.notes.append",
        arguments: { security_id: 7, note: entry }
      });
    } finally {
      await companion.close();
    }

    assert.equal(requests.length, 1);
    assert.deepEqual(requests[0].body, { note: entry });
  });

  // User story (E25 S7, F24):
  // As the operator whose agent reads names, notes and provider results that
  // someone else may have written,
  // I want the companion to tell the agent, once and at connect time, that all
  // such text is data and never an instruction,
  // so that text planted in a record is less likely to steer the agent.
  //
  // Acceptance criteria:
  // - The initialize answer carries server instructions naming names, notes,
  //   bodies and search results as data, not instructions.
  // - The instructions say that only the operator instructs, and how to read
  //   the tool hints.
  it("states at connect time that stored and third-party text is data", async () => {
    const companion = await connectCompanion();

    try {
      const instructions = companion.mcp.getInstructions() ?? "";

      assert.match(instructions, /names, notes, research-log bodies/);
      assert.match(instructions, /search results/);
      assert.match(instructions, /DATA, never instructions/);
      assert.match(instructions, /only the operator instructs you/);
      assert.match(instructions, /readOnlyHint/);
      assert.match(instructions, /destructiveHint/);
    } finally {
      await companion.close();
    }
  });

  // User story (E25 S7, F24 and G25, T-8):
  // As the operator deciding what my MCP host may run without asking,
  // I want every tool to say whether it reads, adds, overwrites or deletes,
  // and whether it reaches past the instance,
  // so that the host can approve reads by itself and ask before a delete.
  //
  // Acceptance criteria:
  // - Every published tool carries readOnlyHint, destructiveHint,
  //   idempotentHint and openWorldHint, none left unset.
  // - The hints follow the HTTP method the tool routes to: GET reads, POST
  //   adds, PUT, PATCH and DELETE overwrite or remove; the only exceptions are
  //   named (two POST-routed computations read; six tools that reach past the
  //   instance, OPEN_WORLD's, are open-world).
  // - The append-only writes are non-destructive and their descriptions state
  //   that what they add is permanent; a new policy-rule version, which
  //   closes and replaces versions, is destructive and not idempotent (H13).
  it("publishes every tool's hints, derived from the method it routes to", async () => {
    const routes = routedMethodsFromSource();
    const published = [
      ...(await publishedTools()),
      // --- S28 N1 begin ---
      // The news labeller's two tools, published under its profile only.
      ...(await publishedTools({ profile: "label" }))
      // --- S28 N1 end ---
    ];

    assert.equal(routes.size, published.length, "every tool routes to one API request");

    for (const tool of published) {
      const method = routes.get(tool.name);
      const hints = tool.annotations ?? {};

      for (const hint of ["readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint"]) {
        assert.equal(typeof (hints as any)[hint], "boolean", `${tool.name}: ${hint} unset`);
      }

      const readOnly = method === "GET" || READ_ONLY_POSTS.includes(tool.name);
      const replacing = REPLACING_POSTS.includes(tool.name);
      const hintedAs = REMOVING_POSTS.includes(tool.name)
        ? "DELETE"
        : MODIFYING_POSTS.includes(tool.name)
          ? "PUT"
          : method;
      assert.equal(hints.readOnlyHint, readOnly, `${tool.name} (${method}) readOnlyHint`);
      assert.equal(
        hints.destructiveHint,
        !readOnly && (replacing || ["PUT", "PATCH", "DELETE"].includes(hintedAs ?? "")),
        `${tool.name} (${method}) destructiveHint`
      );
      assert.equal(
        hints.idempotentHint,
        readOnly || (!replacing && hintedAs !== "POST"),
        `${tool.name} idempotentHint`
      );
      assert.equal(hints.openWorldHint, OPEN_WORLD.includes(tool.name), `${tool.name} openWorldHint`);

      if (method === "GET") {
        assert.equal(hints.readOnlyHint, true, `${tool.name} is GET-routed`);
      }

      if (method === "DELETE") {
        assert.equal(hints.destructiveHint, true, `${tool.name} is DELETE-routed`);
      }
    }

    for (const name of APPEND_ONLY) {
      const tool = published.find((candidate) => candidate.name === name);
      assert.equal(tool?.annotations?.destructiveHint, false, name);
      assert.match(tool?.description ?? "", /PERMANENT/, `${name} states its permanence`);
    }
  });

  // User story (E25 S7, F24 and G25, with E25 S6, T-9):
  // As the operator whose host asks before a write that removes what is stored,
  // I want the quote release, a POST that removes manual quotes, hinted as the
  // delete it is,
  // so that the host never approves it as an additive write.
  //
  // Acceptance criteria:
  // - portfolixir.quotes.release is routed through POST and carries
  //   destructiveHint true and idempotentHint true, readOnlyHint false.
  // - It is not listed in read-only mode.
  // User story (E25 S7 review round, R1):
  // As the operator whose host asks before every destructive write,
  // I want the POST-routed writes that change or remove stored rows hinted
  // destructive by name,
  // so that a retirement, a plan activation or an ISIN change never runs as
  // if it only added a record.
  //
  // Acceptance criteria:
  // - policy_rules.retire, plans.activate and securities.isin_change are
  //   destructive and idempotent, and carry no "a retry can duplicate it"
  //   note.
  // - Every POST-routed tool is either read-only, one of the named removing
  //   or modifying writes, or a write that only adds.
  it("hints the POST-routed writes that change stored rows as destructive, by name", async () => {
    const published = await publishedTools();

    for (const name of MODIFYING_POSTS) {
      const tool = published.find((candidate) => candidate.name === name);
      assert.equal(tool?.annotations?.readOnlyHint, false, name);
      assert.equal(tool?.annotations?.destructiveHint, true, name);
      assert.equal(tool?.annotations?.idempotentHint, true, name);
      assert.doesNotMatch(tool?.description ?? "", /outcome unknown/, name);
    }

    const routes = routedMethodsFromSource();
    const additive = published.filter(
      (tool) =>
        routes.get(tool.name) === "POST" &&
        tool.annotations?.readOnlyHint === false &&
        tool.annotations?.destructiveHint === false
    );

    for (const tool of additive) {
      assert.doesNotMatch(
        tool.description ?? "",
        /\b(is archived|are dropped|is dropped|written onto|is closed|is replaced)\b/,
        `${tool.name} says it changes stored rows but is hinted as only adding`
      );
    }
  });

  // User story (Sprint 24 J1, #1378; ADR-0017, amendment of 2026-11-04):
  // As the agent reading the audit journal,
  // I want the journal tool to say what a delete's after holds,
  // so that I read a deleted record from before and know the older shapes.
  //
  // Acceptance criteria:
  // - portfolixir.journal.list's description says a delete's after is null.
  // - It names the last release whose deletes kept the older shapes.
  it("states that a delete's after is null in the journal tool", async () => {
    const journal = (await publishedTools()).find(
      (tool) => tool.name === "portfolixir.journal.list"
    );

    assert.match(journal?.description ?? "", /A delete's after is null/);
    assert.match(journal?.description ?? "", /2026\.11\.8 or earlier/);
  });

  // User story (E25 S7 review round, R6):
  // As the operator deciding which tools may reach beyond the instance,
  // I want the security create hinted open-world,
  // so that the provider backfill and logo lookup it queues are in view.
  //
  // Acceptance criteria:
  // - portfolixir.securities.create carries openWorldHint: true.
  it("hints the security create as reaching a provider", async () => {
    const create = (await publishedTools()).find(
      (tool) => tool.name === "portfolixir.securities.create"
    );

    assert.equal(create?.annotations?.openWorldHint, true);
    assert.match(create?.description ?? "", /provider/);
  });

  // User story (E25 S7 review round, R3):
  // As the agent whose read-only call timed out,
  // I want to be told the call changed nothing,
  // so that I retry it instead of re-reading for a write that never was.
  //
  // Acceptance criteria:
  // - A read-only tool routed through POST that times out answers a read
  //   timeout, never outcome unknown; a write routed the same way still
  //   answers outcome unknown.
  it("answers a read-only POST that timed out as a read, not an unknown outcome", async () => {
    const companion = await connectCompanion({
      request: async (method: string, path: string, _body?: unknown, options?: { readOnly?: boolean }) => {
        if (options?.readOnly) {
          throw new ApiReadTimeoutError(method, path, 30_000);
        }

        throw new ApiOutcomeUnknownError(method, path, 30_000);
      }
    } as any);

    try {
      const read = await companion.mcp.callTool({
        name: "portfolixir.holdings.reconcile",
        arguments: { rows: [{ identifier: "DE0001234565", quantity: "1" }] }
      });

      assert.equal(read.isError, true);
      assert.doesNotMatch((read.content as any)[0].text, /outcome unknown/);
      assert.match((read.content as any)[0].text, /changes nothing/);

      const write = await companion.mcp.callTool({
        name: "portfolixir.notes.append",
        arguments: {
          security_id: 7,
          note: { kind: "evidence", body: "x", source_quality: "primary", as_of: "2026-08-01" }
        }
      });

      assert.match((write.content as any)[0].text, /outcome unknown/);
    } finally {
      await companion.close();
    }
  });

  // User story (#1045):
  // As the agent whose companion reaches the API through a reverse proxy,
  // I want a gateway's 502 on a read-only tool to tell me a retry is safe,
  // and on a write to tell me the outcome is unknown,
  // so that I retry the one and re-read before the other.
  //
  // Acceptance criteria:
  // - Through the MCP layer and the real API client, a read-only tool routed
  //   through POST answered 502 with an HTML page is a tool error naming 502
  //   and the retry, never outcome unknown; a write answered the same way is
  //   a tool error saying outcome unknown and the re-read.
  it("answers a gateway's 502 on a read-only POST as retry-safe and on a write as outcome unknown", async () => {
    const page = "<html><head><title>502 Bad Gateway</title></head><body>nginx</body></html>";
    const companion = await connectCompanion(
      createApiClient({
        baseUrl: "http://portfolixir.test",
        token: "api-token",
        fetch: async () => new Response(page, { status: 502, headers: { "content-type": "text/html" } })
      })
    );

    try {
      const read = await companion.mcp.callTool({
        name: "portfolixir.holdings.reconcile",
        arguments: { rows: [{ identifier: "DE0001234565", quantity: "1" }] }
      });
      const readText = (read.content as any)[0].text as string;

      assert.equal(read.isError, true);
      assert.match(readText, /POST \/api\/v1\/holdings\/reconcile answered 502/);
      assert.match(readText, /the call changes nothing, so it can be retried/);
      assert.doesNotMatch(readText, /outcome unknown|SyntaxError/);

      const write = await companion.mcp.callTool({
        name: "portfolixir.notes.append",
        arguments: {
          security_id: 7,
          note: { kind: "evidence", body: "x", source_quality: "primary", as_of: "2026-08-01" }
        }
      });
      const writeText = (write.content as any)[0].text as string;

      assert.equal(write.isError, true);
      assert.match(writeText, /outcome unknown/);
      assert.match(writeText, /the gateway answered 502 instead/);
      assert.match(writeText, /Re-read the records it would have changed before retrying/);
    } finally {
      await companion.close();
    }
  });

  it("hints the quote release as the delete it is", async () => {
    const routes = routedMethodsFromSource();
    const release = (await publishedTools()).find((tool) => tool.name === "portfolixir.quotes.release");

    assert.equal(routes.get("portfolixir.quotes.release"), "POST");
    assert.equal(release?.annotations?.readOnlyHint, false);
    assert.equal(release?.annotations?.destructiveHint, true);
    assert.equal(release?.annotations?.idempotentHint, true);

    const readOnly = await publishedTools({ profile: "read" });
    assert.equal(readOnly.some((tool) => tool.name === "portfolixir.quotes.release"), false);
  });

  // User story (E25 S7, G31):
  // As the agent about to retry a write that timed out,
  // I want every write whose retry can add a second record to say, where I
  // read it, that a timeout means the outcome is unknown,
  // so that I re-read before I retry instead of storing a duplicate.
  //
  // Acceptance criteria:
  // - Every tool that writes and is not idempotent (each POST-routed write)
  //   states the outcome-unknown rule and the re-read in its description.
  // - The server instructions state it once for every write.
  // - A timed-out write reaches the host as a tool error carrying that rule.
  it("states the outcome-unknown rule on every write a retry could duplicate", async () => {
    const published = await publishedTools();
    const irreversible = published.filter(
      (tool) => tool.annotations?.readOnlyHint === false && tool.annotations?.idempotentHint === false
    );

    assert.ok(irreversible.length > 20, `too few irreversible writes: ${irreversible.length}`);

    for (const tool of irreversible) {
      assert.match(tool.description ?? "", /outcome unknown/, tool.name);
      assert.match(tool.description ?? "", /re-read before retrying/, tool.name);
    }

    for (const name of ["portfolixir.notes.append", "portfolixir.transactions.create", "portfolixir.splits.create"]) {
      assert.ok(irreversible.some((tool) => tool.name === name), name);
    }

    const companion = await connectCompanion({
      request: async (method, path) => {
        throw new ApiOutcomeUnknownError(method, path, 30_000);
      }
    });

    try {
      assert.match(companion.mcp.getInstructions() ?? "", /outcome unknown/);

      const timedOut = await companion.mcp.callTool({
        name: "portfolixir.notes.append",
        arguments: {
          security_id: 7,
          note: { kind: "evidence", body: "x", source_quality: "primary", as_of: "2026-08-01" }
        }
      });
      assert.equal(timedOut.isError, true);
      assert.match((timedOut.content as any)[0].text, /outcome unknown/);
      assert.match((timedOut.content as any)[0].text, /POST \/api\/v1\/securities\/7\/notes/);
    } finally {
      await companion.close();
    }
  });

  // User story (E25 S7, G28):
  // As the agent about to delete a tree, a category or a view, or to store a
  // policy rule,
  // I want the description to name everything one call removes or makes
  // permanent, and what the journal keeps of it,
  // so that I do not take a one-row delete for what is a cascade.
  //
  // Acceptance criteria:
  // - The classification, category and view deletes name each kind of row the
  //   delete removes with them, and say that the journal keeps each removed
  //   row as its own delete.
  // - The policy-rule create and add_version state that a version is permanent
  //   once in force, and create names retire as the only way to end it.
  it("names what a cascading delete removes and what a rule makes permanent", async () => {
    const published = await publishedTools();
    const description = (name: string) =>
      published.find((tool) => tool.name === name)?.description ?? "";

    const classification = description("portfolixir.classifications.delete");
    assert.match(classification, /every category of the tree, at every depth/);
    assert.match(classification, /every security's assignment in it/);
    assert.match(classification, /every target weight on its categories/);
    assert.match(classification, /every target plan of the tree/);
    assert.match(classification, /journaled as its own delete before the classification's/);

    const category = description("portfolixir.classifications.categories.delete");
    assert.match(category, /its sub-categories at every depth/);
    assert.match(category, /assignments to any of them/);
    assert.match(category, /target weights on any of them/);
    assert.match(category, /journaled as its own delete, the lowest categories first/);

    const view = description("portfolixir.views.delete");
    assert.match(view, /include and exclude bucket sets/);
    assert.match(view, /every target plan scoped to the view/);
    assert.match(view, /every depot snapshot taken in its scope/);
    assert.match(view, /journaled one delete each before the view's/);

    for (const name of [
      "portfolixir.classifications.delete",
      "portfolixir.classifications.categories.delete",
      "portfolixir.views.delete"
    ]) {
      assert.match(description(name), /ONE CALL REMOVES/, name);
    }

    const create = description("portfolixir.policy_rules.create");
    assert.match(create, /PERMANENT once in force/);
    assert.match(create, /can only be retired/);
    assert.match(description("portfolixir.policy_rules.add_version"), /PERMANENT once in force/);
  });

  // User story (E25 S7, G30, the wording half; T-8):
  // As the operator whose agent's own token can store policy rules,
  // I want the rule tools to call a rule a stored rule and to point to the
  // audit journal for who wrote it,
  // so that a rule the agent wrote is not presented to it as my standard.
  //
  // Acceptance criteria:
  // - No policy-rule tool and not the findings read calls a rule the
  //   operator's, in its title, its description or its schema.
  // - The list, show, create and add_version descriptions point to the audit
  //   journal for who wrote a rule or a version.
  it("words the policy-rule tools neutrally and points to the journal for the author", async () => {
    const published = await publishedTools();
    const ruleTools = published.filter(
      (tool) =>
        tool.name.startsWith("portfolixir.policy_rules.") ||
        tool.name === "portfolixir.portfolios.policy_findings"
    );

    assert.equal(ruleTools.length, 8);

    for (const tool of ruleTools) {
      const words = `${tool.title} ${tool.description} ${JSON.stringify(tool.inputSchema)}`;
      assert.doesNotMatch(words, /operator's/i, tool.name);
    }

    for (const name of ["list", "get", "create", "add_version"]) {
      const tool = ruleTools.find((candidate) => candidate.name === `portfolixir.policy_rules.${name}`);
      assert.match(tool?.description ?? "", /a stored rule/, name);
      assert.match(tool?.description ?? "", /audit journal \(portfolixir\.journal\.list/, name);
    }
  });

  // User story (E25 S7, G26, T-8):
  // As the operator who wants an agent to read the instance but never write it,
  // I want one opt-in switch that makes the companion read-only,
  // so that a prompt-injected agent in that session cannot change anything
  // through the companion, even with a tool it guessed or cached.
  //
  // Acceptance criteria:
  // - Read-only, tools/list lists exactly the tools with readOnlyHint, and no
  //   write tool.
  // - A call to a write tool is refused again at call time, as a tool error
  //   naming the switch, with no API request, whether or not it was listed.
  // - Read tools work as before; without the switch every tool is listed.
  it("in read-only mode lists and calls no write tool", async () => {
    const reads = listTools().filter((tool) => tool.annotations.readOnlyHint);
    const listed = await publishedTools({ profile: "read" });

    assert.deepEqual(
      listed.map((tool) => tool.name),
      reads.map((tool) => tool.name)
    );
    assert.ok(listed.every((tool) => tool.annotations?.readOnlyHint === true));
    assert.ok(listed.some((tool) => tool.name === "portfolixir.securities.search_online"));
    assert.equal((await publishedTools()).length, listTools().length);

    const { client, requests } = createRecordingClient({ data: { id: 1 } });
    const companion = await connectCompanion(client, { profile: "read" });

    try {
      for (const [name, args] of [
        ["portfolixir.transactions.delete", { id: 1 }],
        ["portfolixir.notes.append", {
          security_id: 7,
          note: { kind: "evidence", body: "x", source_quality: "primary", as_of: "2026-08-01" }
        }],
        ["portfolixir.quotes.sync", { security_id: 7 }]
      ] as const) {
        const refused = await companion.mcp.callTool({ name, arguments: args });
        assert.equal(refused.isError, true, name);
        assert.match((refused.content as any)[0].text, /read-only/, name);
        assert.match((refused.content as any)[0].text, /PORTFOLIXIR_MCP_READ_ONLY/, name);
      }

      assert.equal(requests.length, 0);

      const read = await companion.mcp.callTool({
        name: "portfolixir.securities.get",
        arguments: { id: 7 }
      });
      assert.equal(read.isError, undefined);
      assert.deepEqual(
        requests.map((request) => `${request.method} ${request.path}`),
        ["GET /api/v1/securities/7"]
      );
    } finally {
      await companion.close();
    }
  });

  it("refuses a write in read-only mode at the call itself", async () => {
    const { client, requests } = createRecordingClient({ data: {} });

    await assert.rejects(
      callTool(client, "portfolixir.transactions.delete", { id: 1 }, { profile: "read" }),
      /read-only.*PORTFOLIXIR_MCP_READ_ONLY/
    );
    assert.equal(requests.length, 0);

    await callTool(client, "portfolixir.splits.preview", {
      security_id: 7,
      date: "2026-08-01",
      ratio_numerator: 2,
      ratio_denominator: 1
    }, { profile: "read" });
    assert.deepEqual(
      requests.map((request) => `${request.method} ${request.path}`),
      ["POST /api/v1/splits/preview"]
    );
  });

  it("reads the read-only switch strictly, off by default", () => {
    for (const value of [undefined, "", "0", "false", "FALSE", " false "]) {
      assert.equal(readOnlySwitch(value), false, String(value));
    }

    for (const value of ["1", "true", "TRUE", " true "]) {
      assert.equal(readOnlySwitch(value), true, value);
    }

    for (const value of ["yes", "on", "readonly", "2"]) {
      assert.throws(() => readOnlySwitch(value), /PORTFOLIXIR_MCP_READ_ONLY/, value);
    }
  });

  // User story (E25 S7, F21):
  // As the agent calling a tool through an MCP host,
  // I want every answer the companion gives to reach me as a tool result,
  // so that a delete the API answered without a body does not read as a
  // failure I would retry, and a refused argument names what was wrong.
  //
  // Acceptance criteria:
  // - A call the API answers with no body reaches the host as a result, not
  //   as a protocol error.
  // - An argument the validator refuses reaches the host as a tool error
  //   naming the tool and the field, and no API request is made.
  // - An unknown tool reaches the host as a tool error naming it.
  it("answers every call as a tool result the host accepts", async () => {
    const requests: string[] = [];
    const companion = await connectCompanion({
      request: async (method, path) => {
        requests.push(`${method} ${path}`);
        return null;
      }
    });

    try {
      const deleted = await companion.mcp.callTool({
        name: "portfolixir.views.delete",
        arguments: { id: 3 }
      });
      assert.equal(deleted.isError, undefined);
      assert.deepEqual(deleted.content, [{ type: "text", text: "null" }]);
      assert.deepEqual(requests, ["DELETE /api/v1/views/3"]);

      const refused = await companion.mcp.callTool({
        name: "portfolixir.views.delete",
        arguments: { id: "three" }
      });
      assert.equal(refused.isError, true);
      assert.match((refused.content as any)[0].text, /portfolixir\.views\.delete/);
      assert.match((refused.content as any)[0].text, /\bid\b/);
      assert.equal(requests.length, 1);

      const unknown = await companion.mcp.callTool({ name: "portfolixir.nope", arguments: {} });
      assert.equal(unknown.isError, true);
      assert.match((unknown.content as any)[0].text, /portfolixir\.nope/);
    } finally {
      await companion.close();
    }
  });
});
