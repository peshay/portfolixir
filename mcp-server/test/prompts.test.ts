import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { MCP_PROFILES } from "../src/profiles.js";
import { PP_CSV_V1_EXAMPLE, PP_JSON_V1_EXAMPLE } from "../src/prompts.js";
import { listTools } from "../src/tools.js";
import { connectCompanion } from "./support/companion.js";

// Sprint 17, Lane A4 (#983): two prompts, MCP only. A prompt is an
// instruction to the user's own agent; the API has nothing to serve it to.

const NO_ADVICE = [
  /The system prepares decisions and the operator executes them/,
  /nothing here places, proposes or sizes a trade/
];

async function promptText(
  name: string,
  args: Record<string, string> = {},
  profile: (typeof MCP_PROFILES)[number] = "full"
): Promise<string> {
  const companion = await connectCompanion(undefined, { profile });

  try {
    const prompt = await companion.mcp.getPrompt({ name, arguments: args });
    assert.ok(prompt.messages.length > 0, name);

    return prompt.messages
      .map((message) => {
        assert.equal(message.role, "user", name);
        assert.equal(message.content.type, "text", name);
        return (message.content as { text: string }).text;
      })
      .join("\n");
  } finally {
    await companion.close();
  }
}

// Every tool a prompt names exists, so a prompt never sends an agent to a tool
// that is gone.
function assertNamesOnlyRealTools(name: string, text: string): void {
  const tools = new Set(listTools().map((tool) => tool.name));

  // A family written as portfolixir.views.* names no single tool and is skipped.
  for (const [mention] of text.matchAll(/portfolixir\.[a-z_]+\.[a-z_.]*[a-z_]/g)) {
    assert.ok(tools.has(mention), `${name} names ${mention}, which is no tool`);
  }
}

describe("the companion's prompts", () => {
  // User story (A4, #983):
  // As the operator connecting an agent for the first time,
  // I want the companion to offer two prompts, a first setup and an import
  // converter, under every profile,
  // so that my agent starts from the product's own instructions.
  //
  // Acceptance criteria:
  // - The server advertises the prompts capability.
  // - prompts/list answers exactly first_setup and import_converter, each with
  //   a title and a description; import_converter takes one optional argument,
  //   export_file.
  // - An unknown prompt is an error.
  it("lists the two prompts under every profile", async () => {
    for (const profile of MCP_PROFILES) {
      const companion = await connectCompanion(undefined, { profile });

      try {
        assert.ok(companion.mcp.getServerCapabilities()?.prompts, profile);

        const { prompts } = await companion.mcp.listPrompts();
        assert.deepEqual(
          prompts.map((prompt) => prompt.name),
          ["first_setup", "import_converter"],
          profile
        );

        for (const prompt of prompts) {
          assert.ok((prompt.title ?? "").length > 0, prompt.name);
          assert.ok((prompt.description ?? "").length > 40, prompt.name);
        }

        assert.deepEqual(prompts[0].arguments ?? [], []);
        assert.deepEqual(
          (prompts[1].arguments ?? []).map((argument) => [argument.name, argument.required ?? false]),
          [["export_file", false]]
        );

        await assert.rejects(companion.mcp.getPrompt({ name: "nope", arguments: {} }), /nope/);
      } finally {
        await companion.close();
      }
    }
  });

  // User story (A4, #983):
  // As the operator setting up an instance with my agent,
  // I want the first-setup prompt to check the instance and the profile, read
  // what exists, propose a structure and explain how data gets in, writing
  // nothing I have not confirmed,
  // so that the setup is mine and nothing lands by surprise.
  //
  // Acceptance criteria:
  // - The text embeds the active profile and what it admits.
  // - It checks the instance first, reads before it proposes, writes nothing
  //   without the operator's confirmation, and groups with buckets and views,
  //   not portfolios.
  // - The total across everything is a read with no view (#1007, Sprint 18
  //   plan D-5): it proposes no catch-all view to get it.
  // - It names the intake paths: a Portfolio Performance file on the Imports
  //   page, the import_converter prompt, manual booking; and no broker sync.
  // - It carries the no-advice framing, and names only tools that exist.
  it("first_setup checks, reads, proposes and writes nothing unconfirmed", async () => {
    for (const profile of MCP_PROFILES) {
      const text = await promptText("first_setup", {}, profile);

      assert.match(text, new RegExp(`runs the ${profile} profile \\(PORTFOLIXIR_MCP_PROFILE\\)`));
      assertNamesOnlyRealTools(`first_setup/${profile}`, text);
    }

    const text = await promptText("first_setup", {}, "book");

    assert.match(text, /Write nothing without the operator's confirmation/);
    assert.match(text, /portfolixir\.contract\.get/);
    assert.match(text, /portfolixir\.cash_accounts\.list/);
    assert.match(text, /portfolixir\.securities_accounts\.list/);
    assert.match(text, /portfolixir\.views\.list/);
    assert.match(text, /portfolixir\.buckets\.create/);
    assert.match(text, /portfolixir\.views\.valuation without an id/);
    assert.match(text, /needs no view/);
    assert.doesNotMatch(text, /one view that includes everything/);
    assert.doesNotMatch(text, /views\.create with only a name/);
    assert.match(text, /portfolixir\.portfolios\.create is deprecated/);
    assert.match(text, /Imports page of the instance \(Transactions → Import in the UI, \/imports\)/);
    assert.match(text, /import_converter prompt/);
    assert.match(text, /portfolixir\.transactions\.create, one booking per call/);
    assert.match(text, /There is no broker or bank connection/);

    for (const framing of NO_ADVICE) {
      assert.match(text, framing);
    }

    const readSetup = await promptText("first_setup", {}, "read");
    assert.match(readSetup, /propose but not create/);
    // Note 7: PROFILE=book beside READ_ONLY=true stops the companion.
    assert.match(readSetup, /PORTFOLIXIR_MCP_PROFILE=book and PORTFOLIXIR_MCP_READ_ONLY unset or false/);
    assert.doesNotMatch(text, /another book write can undo/);
    assert.match(await promptText("first_setup", {}, "full"), /needs none of them/);
  });

  // User story (#1173):
  // As the user's agent setting up an instance that holds no portfolio record
  // yet,
  // I want first_setup to say which record an import or an account binds to
  // and that the first one creates it,
  // so that an empty portfolixir.portfolios.list does not leave me guessing
  // where the import books.
  //
  // Acceptance criteria:
  // - The text no longer promises "the first portfolio": accounts and
  //   imports bind to the earliest portfolio record, which the first import
  //   or account creates as "Default" (EUR), so an instance has none before.
  // - The sentence stays within the bytes of the one it replaces (Sprint 20
  //   plan D-10: first_setup's text changes inside its own bytes).
  it("first_setup says the first import or account creates the portfolio record", async () => {
    const text = await promptText("first_setup", {}, "book");

    assert.doesNotMatch(text, /lands in the first portfolio/);
    assert.doesNotMatch(text, /books into that first portfolio/);

    const [sentence] =
      /Group with buckets and views, not with portfolios: [^\n]*/.exec(text) ?? [""];

    assert.equal(
      sentence,
      "Group with buckets and views, not with portfolios: a portfolio is an internal compatibility " +
        "record (ADR-0024), portfolixir.portfolios.create is deprecated, and accounts and imports " +
        'bind to the earliest one, which the first import or account creates as "Default" (EUR).'
    );
    assert.ok(Buffer.byteLength(sentence, "utf8") <= 276, `${Buffer.byteLength(sentence, "utf8")} bytes`);
  });

  // User story (A4, #983):
  // As the operator whose bank exports a format Portfolixir does not read,
  // I want my agent told the exact file format the Imports page takes and how
  // to write a converter for it on my machine,
  // so that the file previews without an error and imports without a
  // broker connection, a network call or a booking the preview never showed.
  //
  // Acceptance criteria:
  // - The text states the header verbatim, the delimiter, the date and number
  //   formats, every type label, what Betrag is per type and which account
  //   Konto and Gegenkonto name, the EUR-only rule and the JSON v1 variant.
  // - It carries the binding constraints: no broker sync, no network or model
  //   call, synthetic examples, a file for the Imports page, and that booking
  //   the rows one by one through portfolixir.transactions.create is not a
  //   substitute (preview, content-hash idempotency).
  // - It shows the example blocks verbatim and the no-advice framing.
  // - A given export_file is named in the text.
  it("import_converter states the target format and its constraints", async () => {
    const text = await promptText("import_converter");

    assert.ok(
      text.includes("Datum;Typ;Wertpapier;Stück;Kurs;Betrag;Gebühren;Steuern;Gesamtpreis;Konto;Gegenkonto;Notiz;Quelle")
    );

    for (const label of [
      "Kauf",
      "Verkauf",
      "Dividende",
      "Zinsen",
      "Einlage",
      "Entnahme",
      "Gebühren",
      "Steuern",
      "Steuerrückerstattung",
      "Umbuchung (Ausgang)",
      "Einlieferung",
      "Auslieferung",
      "Umbuchung (Wertpapier)"
    ]) {
      assert.ok(text.includes(`${label} (`), label);
    }

    assert.match(text, /`;` between fields/);
    assert.match(text, /YYYY-MM-DD HH:MM:SS/);
    assert.match(text, /A dot is ALWAYS read as a thousands separator/);
    assert.match(text, /INCLUDING Gebühren and Steuern/);
    assert.match(text, /AFTER Gebühren and Steuern/);
    assert.match(text, /NET amount credited/);
    assert.match(text, /Konto is the depot, Gegenkonto the cash account/);
    assert.match(text, /The CSV books every row in EUR/);
    // ADR-0053 §1: the importer reads a filled Gesamtpreis as PP writes it,
    // so the prompt no longer says it is ignored, and says why it stays empty.
    assert.doesNotMatch(text, /ignores Gesamtpreis/);
    assert.match(text, /leave Gesamtpreis and Quelle empty/);
    assert.match(
      text,
      /Gesamtpreis stays empty because a filled one is read as Portfolio Performance writes it, Betrag as the gross value before Gebühren and Steuern and Gesamtpreis as the cash, checked against both to the cent, while an empty one makes Betrag the cash effect described below/
    );
    // #1094: the summary counts rows per cash account and per depot, never
    // per Konto, which names a depot on a trade and a cash account elsewhere.
    assert.doesNotMatch(text, /rows per Konto/);
    assert.match(
      text,
      /rows per cash account and rows per depot, each row counted under every cash account and every depot it names \(a Kauf or Verkauf under its depot and its Gegenkonto, a transfer under both sides\), so the two lists may add up to more than the rows/
    );
    assert.match(text, /JSON v1 variant/);

    assert.match(text, /No broker or bank connection/);
    assert.match(text, /no network call and no model call/);
    assert.match(text, /synthetic/);
    assert.match(text, /Imports page/);
    // #1093: the page's place in the UI, beside its address.
    assert.match(text, /Imports page of their instance \(Transactions → Import in the UI, \/imports\)/);
    assert.match(text, /opens the Imports page \(Transactions → Import in the UI, \/imports\)/);
    assert.match(
      text,
      /Booking the converted rows one by one with portfolixir\.transactions\.create is not a substitute/
    );
    assert.match(text, /skips the preview/);
    assert.match(text, /content-hash idempotency/);

    // PR β closing act, note 3: the content hash leaves Notiz out.
    assert.match(
      text,
      /agree in Datum \(with its time\), Typ, Wertpapier, Stück, Kurs, Betrag, Gebühren, Steuern, Konto and Gegenkonto are one booking to the importer, whatever their Notiz/
    );
    assert.match(text, /never keep them apart through Notiz/);
    // Note 4: the preview renders no per-row CSV note.
    assert.doesNotMatch(text, /csv-without-isin/);
    // The launch test's run: an export may state no closing balance.
    assert.match(text, /When the export states no closing balance/);
    assert.match(
      text,
      /ask the operator to compare it with the balance their bank shows before they drop the file/
    );
    // Note 10: a PDF is not an export this prompt converts.
    assert.match(text, /A PDF statement is not an export this prompt converts/);
    assert.match(text, /machine_generated/);

    assert.ok(text.includes(PP_CSV_V1_EXAMPLE), "the CSV example, verbatim");
    assert.ok(text.includes(PP_JSON_V1_EXAMPLE), "the JSON example, verbatim");

    for (const framing of NO_ADVICE) {
      assert.match(text, framing);
    }

    assertNamesOnlyRealTools("import_converter", text);

    assert.match(
      await promptText("import_converter", { export_file: "bank-export-2025.csv" }),
      /bank-export-2025\.csv/
    );
  });

  // User story (the launch test's second run, #1037):
  // As the user's agent converting an export whose dividends name a depot,
  // I want the import_converter prompt to say which depot the importer books a
  // dividend to, and what to write when one security sits in two depots,
  // so that I do not guess at where a dividend lands.
  //
  // Acceptance criteria:
  // - The Konto rules say a Dividende from the CSV is booked to its cash
  //   account and its security with no depot: the row names none, and the
  //   importer reads no Gegenkonto on it (csv_parser.ex, map_accounts/3).
  // - The JSON v1 variant's portfolio field names a DIVIDEND's depot
  //   (json_parser.ex), and the prompt says to write that variant when the
  //   same security sits in two depots and each dividend should name its own.
  it("import_converter says which depot a dividend is booked to", async () => {
    const text = await promptText("import_converter");

    assert.match(
      text,
      /a Dividende from the CSV is booked to its cash account and its security with no depot/
    );
    assert.match(text, /The importer reads no Gegenkonto on these rows, so the CSV gives them no depot/);
    assert.match(text, /on a DIVIDEND, the depot the dividend is booked to/);
    assert.match(
      text,
      /When the same security sits in two depots and each dividend should name the depot that held the shares, write the JSON v1 variant below/
    );
  });

  // User story (#1044, #948; Sprint 19 B4b):
  // As the user's agent converting an export,
  // I want the import_converter prompt to name every row the preview refuses
  // for its accounts or its currency,
  // so that I write a file whose rows all book instead of meeting the refusals
  // in the operator's preview.
  //
  // Acceptance criteria:
  // - A transfer row names both sides, filled: in the CSV (Umbuchung
  //   (Ausgang) and Umbuchung (Wertpapier)) and in JSON v1 (otherAccount,
  //   otherPortfolio). A Kauf or Verkauf names its Gegenkonto.
  // - The prompt never calls one account on both sides a refusal: the
  //   preview takes such a transfer and the apply skips it as an internal
  //   transfer (ADR-0050 §5).
  // - A JSON v1 row's currency, and its security's, is one Portfolixir
  //   supports (the currencies its security dialog offers); any other code is
  //   refused, as an ISIN without a valid check digit is.
  it("import_converter names the account and currency refusals", async () => {
    const text = await promptText("import_converter");

    assert.match(
      text,
      /a transfer row needs both Konto and Gegenkonto filled, or the preview refuses the row/
    );
    assert.doesNotMatch(text, /never the same account/);
    assert.match(text, /a Kauf or Verkauf without a Gegenkonto is refused/);
    assert.match(
      text,
      /otherAccount \(where a CASH_TRANSFER's money arrives\), otherPortfolio \(where a SECURITY_TRANSFER's shares arrive\); a transfer without its other side is refused/
    );
    assert.match(
      text,
      /currency: the cash account's currency, one currency per account, and one Portfolixir supports: the currencies its security dialog offers/
    );
    assert.match(
      text,
      /a row whose currency, or whose security's currency, is any other code is refused/
    );
  });

  // User story (ADR-0053 A7, the amendment of 2026-10-07; #1098):
  // As the user's agent converting an export that records a tax refund,
  // I want the import_converter prompt to say where a refund of tax goes,
  // so that I write it as its own row and never as a negative Steuern beside
  // a Betrag that already holds it.
  //
  // Acceptance criteria:
  // - The text says that a refund of tax is its own Steuerrückerstattung row
  //   and that Steuern is never negative in a converter file.
  // - It still says to write every amount as a positive magnitude.
  it("import_converter says a refund of tax is its own row", async () => {
    const text = await promptText("import_converter");

    assert.match(text, /Write every amount as a positive magnitude; the type gives the direction/);
    assert.match(
      text,
      /A refund of tax is its own Steuerrückerstattung row, and Steuern is never negative in a converter file/
    );
  });
});
