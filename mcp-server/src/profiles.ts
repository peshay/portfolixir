/**
 * The companion's tool profiles (Sprint 17, A1, #992; plan D-5): one server,
 * one switch, three levels.
 *
 * - `read` lists and calls only the tools that change nothing (readOnlyHint).
 * - `book` lists and calls every tool except the admin set below: the reads,
 *   every create, and the replace-shaped writes, which the same write sent
 *   the former value undoes (two leave a residue, named below).
 * - `full` (the default) lists and calls every tool.
 *
 * A profile narrows the companion, not the API token: whoever holds
 * PORTFOLIXIR_API_TOKEN can still call every route directly. It keeps an
 * unattended agent run from deleting or merging through the companion; it is
 * not a security boundary.
 */
export type McpProfile = "read" | "book" | "full";

export const MCP_PROFILES: readonly McpProfile[] = ["read", "book", "full"];

/**
 * The opt-in read-only switch, `PORTFOLIXIR_MCP_READ_ONLY` (E25 S7, G26,
 * T-8): off unless set to `true` or `1`. Any value other than those and
 * `false`, `0` or empty stops the companion with the variable named, so a
 * mistyped switch never runs the companion with every write open. Since A1 it
 * is a synonym for `PORTFOLIXIR_MCP_PROFILE=read`.
 */
export function readOnlySwitch(value: string | undefined): boolean {
  const normalized = (value ?? "").trim().toLowerCase();

  if (["", "0", "false"].includes(normalized)) {
    return false;
  }

  if (["1", "true"].includes(normalized)) {
    return true;
  }

  throw new Error("PORTFOLIXIR_MCP_READ_ONLY must be true or false (1 or 0), or unset");
}

/**
 * The profile the companion runs, from `PORTFOLIXIR_MCP_PROFILE` and the
 * older `PORTFOLIXIR_MCP_READ_ONLY`, read together:
 *
 * - the profile is `read`, `book` or `full`, in any case and trimmed; unset
 *   or empty is `full`, or `read` when the read-only switch is on;
 * - the read-only switch on (`true`, `1`) is `read`, and beside an explicit
 *   `book` or `full` the pair contradicts itself, so the companion stops with
 *   both variables named rather than guess which one was meant;
 * - the switch off (`false`, `0`, empty, unset) only means it is off, as it
 *   always did, so it never conflicts: Compose and `.env.example` ship it as
 *   `false`, and a `PROFILE=read` beside that default is simply `read`.
 *
 * Any other value of either variable stops the companion with that variable
 * named, as the read-only switch always has.
 */
export function profileSwitch(
  profile: string | undefined,
  readOnly: string | undefined
): McpProfile {
  const readOnlyOn = readOnlySwitch(readOnly);
  const normalized = (profile ?? "").trim().toLowerCase();

  if (normalized === "") {
    return readOnlyOn ? "read" : "full";
  }

  if (!(MCP_PROFILES as readonly string[]).includes(normalized)) {
    throw new Error("PORTFOLIXIR_MCP_PROFILE must be read, book or full, or unset (full)");
  }

  if (readOnlyOn && normalized !== "read") {
    throw new Error(
      `PORTFOLIXIR_MCP_PROFILE=${normalized} contradicts PORTFOLIXIR_MCP_READ_ONLY=true; ` +
        "unset one of them (PORTFOLIXIR_MCP_READ_ONLY=true means PORTFOLIXIR_MCP_PROFILE=read)"
    );
  }

  return normalized as McpProfile;
}

// THE ADMIN SET — the tools the `book` profile leaves out.
//
// The principle (D-5), as implemented: removal-shaped tools are admin, and
// replace-shaped writes stay in `book`.
//
// A tool that removes a stored row is admin (a delete, a former-name or
// ISIN-alias removal, an unassignment, a cleared position override, the
// release of manual quotes), even where a later write could put an equal row
// back: what comes back is a new row, and drawing the line at removal keeps
// a book run from thinning out what it may not have read. The three merges,
// the ISIN change and a rule's retirement are admin too: no book write
// reverses them.
//
// A write that replaces a value stays in `book` (BOOK_KEPT_DESTRUCTIVE
// below), because the same write sent the former value undoes it, also where
// the replacement empties something: views.set_buckets,
// securities_accounts.set_buckets and cash_accounts.set_buckets sent a
// narrower set, and securities_accounts.set_position_buckets sent [] (the
// explicit-empty override), stay in `book`, while
// securities_accounts.clear_position_buckets, which removes the override, is
// admin. A plan activation stays: activating the previous plan undoes it.
// Two kept writes leave a residue their inverse does not clear, named in
// their reasons: a rename back keeps the in-between name as a former name,
// and an upsert over a provider date leaves that date manual.
//
// A test (test/profiles.test.ts) fails any tool that carries destructiveHint
// and sits in neither list, any entry that names no tool, and any tool that
// removes or merges outside this one, so a new tool forces the choice.
export const ADMIN_TOOLS: ReadonlyMap<string, string> = new Map([
  ["portfolixir.securities.delete", "Removes the security; a create makes a new one under a new id."],
  [
    "portfolixir.securities.isin_change",
    "Rewrites the security's identity and records the old ISIN as an alias; no book write reverses both."
  ],
  [
    "portfolixir.securities.delete_isin_alias",
    "Forgets a former ISIN imports match by; only an ISIN change records one, and that is admin."
  ],
  [
    "portfolixir.securities.merge",
    "Moves the duplicate's history onto the survivor and deletes it; nothing splits them again."
  ],
  ["portfolixir.events.delete", "Removes the calendar event; a create makes a new one."],
  [
    "portfolixir.quotes.release",
    "Removes every manual close in a range in one call, often the only copy of those values."
  ],
  ["portfolixir.cash_accounts.delete", "Removes the cash account; a create makes a new one."],
  [
    "portfolixir.cash_accounts.remove_former_name",
    "Forgets a name the next import resolves to this account; a rename records only the previous live name, so restoring it takes renaming through it and back, not one inverse write."
  ],
  [
    "portfolixir.cash_accounts.merge",
    "Moves every booking onto the target and deletes the source; nothing splits them again."
  ],
  ["portfolixir.securities_accounts.delete", "Removes the depot; a create makes a new one."],
  [
    "portfolixir.securities_accounts.remove_former_name",
    "Forgets a name the next import resolves to this depot; a rename records only the previous live name, so restoring it takes renaming through it and back, not one inverse write."
  ],
  [
    "portfolixir.securities_accounts.merge",
    "Moves every booking onto the target depot and deletes the source; nothing splits them again."
  ],
  [
    "portfolixir.securities_accounts.clear_position_buckets",
    "Removes a position's bucket override; a removal, held with the others."
  ],
  [
    "portfolixir.transactions.delete",
    "Removes a booking; one booked again by hand has no import hash, so a re-import books it twice."
  ],
  [
    "portfolixir.classifications.delete",
    "Removes the tree with every category, assignment and target weight on it in one call."
  ],
  [
    "portfolixir.classifications.categories.delete",
    "Removes the category with its sub-categories, assignments and target weights."
  ],
  [
    "portfolixir.classifications.unassign",
    "Removes a security's assignment; a removal, held with the others (a reassignment stays in book)."
  ],
  ["portfolixir.targets.delete", "Removes a category's target weight; a removal, held with the others."],
  [
    "portfolixir.targets.delete_position",
    "Removes a position-level target; a removal, held with the others."
  ],
  [
    "portfolixir.policy_rules.retire",
    "Ends the version in force and drops every scheduled one; a retired rule is never in force again."
  ],
  ["portfolixir.policy_rules.delete", "Removes a rule with every version it has."],
  [
    "portfolixir.buckets.delete",
    "Removes the bucket and rewrites every view, account set and override that named it."
  ],
  [
    "portfolixir.views.delete",
    "Removes the view with its bucket sets, its plans and its depot snapshots."
  ],
  ["portfolixir.plans.delete", "Removes a plan version with its target weights."],
  ["portfolixir.snapshots.delete", "Removes a dated snapshot marker; a removal, held with the others."],
  ["portfolixir.tax_profiles.delete", "Removes a taxpayer profile; a removal, held with the others."],
  [
    "portfolixir.allowance_orders.delete",
    "Removes a recorded allowance order; a removal, held with the others."
  ],
  [
    "portfolixir.tax_snapshots.delete",
    "Removes a recorded tax statement; a removal, held with the others."
  ]
]);

// THE OVERWRITES `book` KEEPS — the replace-shaped tools that carry
// destructiveHint (they overwrite what is stored): the same tool sent the
// value it replaced undoes each, with the two residues its reason names. The audit
// journal keeps every before-image (portfolixir.journal.list), so the value
// to send back can be read even when the agent did not read it first.
export const BOOK_KEPT_DESTRUCTIVE: ReadonlyMap<string, string> = new Map([
  ["portfolixir.securities.update", "Master data; an update with the previous values restores it."],
  ["portfolixir.events.update", "An event is mutable by design; an update sets it back."],
  [
    "portfolixir.quotes.upsert",
    "An upsert of the replaced closes restores the series; a date it took from provider data stays manual until portfolixir.quotes.release (admin)."
  ],
  [
    "portfolixir.cash_accounts.update",
    "A rename back restores the name but keeps the in-between name as a former name, which no new account may take and a later import books here; only cash_accounts.remove_former_name (admin) clears it."
  ],
  [
    "portfolixir.securities_accounts.update",
    "A rename back restores the name but keeps the in-between name as a former name, which no new depot may take and a later import books here; only securities_accounts.remove_former_name (admin) clears it."
  ],
  ["portfolixir.transactions.update", "An update with the previous fields restores the booking."],
  [
    "portfolixir.classifications.update",
    "Name, description and position; an update sets them back."
  ],
  [
    "portfolixir.classifications.categories.update",
    "Name, description and parent; an update sets them back."
  ],
  [
    "portfolixir.classifications.assign",
    "Moves a security to a category; assigning the previous category moves it back."
  ],
  [
    "portfolixir.classifications.assign_bulk",
    "Moves securities to a category; assigning their previous categories moves them back."
  ],
  ["portfolixir.targets.set", "Upserts target weights; setting the previous weights restores them."],
  ["portfolixir.policy_rules.rename", "A label outside the versioning; a rename back restores it."],
  [
    "portfolixir.portfolios.set_cash_target",
    "Sets or clears the cash target; setting the previous value restores it."
  ],
  ["portfolixir.buckets.update", "Name and colour; an update sets them back."],
  ["portfolixir.views.update", "Name and include_all; an update sets them back."],
  ["portfolixir.views.set_buckets", "Replaces the view's bucket sets; sending the previous sets restores them."],
  [
    "portfolixir.securities_accounts.set_buckets",
    "Replaces the depot's default buckets; sending the previous set restores it."
  ],
  [
    "portfolixir.cash_accounts.set_buckets",
    "Replaces the cash account's buckets; sending the previous set restores it."
  ],
  [
    "portfolixir.securities_accounts.set_position_buckets",
    "Replaces a position's override; sending the previous override restores it."
  ],
  [
    "portfolixir.settings.set_default_view",
    "A preference; setting the previous view restores it."
  ],
  [
    "portfolixir.plans.activate",
    "Archives the active plan; activating that plan again undoes it (D-5's own example)."
  ],
  ["portfolixir.plans.rename", "A plan's name; a rename back restores it."],
  [
    "portfolixir.tax_parameters.upsert",
    "Replaces a year's statutory parameters; an upsert of the previous ones restores them."
  ],
  ["portfolixir.tax_profiles.update", "A taxpayer profile's fields; an update sets them back."],
  [
    "portfolixir.allowance_orders.put",
    "Records or replaces an allowance order; putting the previous amount restores it."
  ],
  ["portfolixir.tax_snapshots.update", "A recorded statement's fields; an update sets them back."]
]);

interface ProfiledTool {
  name: string;
  annotations: { readOnlyHint: boolean };
}

/** Whether `profile` lists and calls `tool`. */
export function profileAdmits(profile: McpProfile, tool: ProfiledTool): boolean {
  switch (profile) {
    case "read":
      return tool.annotations.readOnlyHint;
    case "book":
      return !ADMIN_TOOLS.has(tool.name);
    case "full":
      return true;
  }
}

/**
 * The tool error a call outside the profile answers, naming the profile and
 * the variable that chose it, before any request is made.
 */
export function profileRefusal(profile: McpProfile, name: string): string {
  if (profile === "read") {
    return (
      `${name} is not available: this companion runs the read profile, read-only ` +
      "(PORTFOLIXIR_MCP_PROFILE=read, or PORTFOLIXIR_MCP_READ_ONLY=true), and calls only " +
      "the tools that change nothing."
    );
  }

  const reason = ADMIN_TOOLS.get(name);

  return (
    `${name} is not available: this companion runs the book profile ` +
    "(PORTFOLIXIR_MCP_PROFILE=book), which leaves out the admin tools: every removal, and the " +
    `writes no book write reverses${reason === undefined ? "" : ` (this one: ${reason})`}. Ask the operator ` +
    "to run it, under the full profile or on the instance's own pages."
  );
}

/**
 * The clause the server instructions carry for the active profile (A1): the
 * agent learns at connect time why a tool it expects is not listed.
 */
export function profileClause(profile: McpProfile): string {
  const scope = {
    read: "it lists only the tools that change nothing",
    book:
      "it lists the reads, the creates and the replace-shaped writes (updates, upserts, " +
      "sets), and leaves out the admin tools (every removal, the merges, the ISIN change, a " +
      "rule's retirement, the release of manual quotes)",
    full: "it lists every tool"
  }[profile];

  return (
    `This companion runs the ${profile} profile (PORTFOLIXIR_MCP_PROFILE): ${scope}; a tool ` +
    "it does not list is refused at the call, and only the operator can change the profile."
  );
}
