defmodule Portfolixir.Repo.Migrations.AddNameAuthorToPolicyRules do
  @moduledoc """
  Security review 2026-10-12, H14 (decision T-16): a policy rule stores who
  last named it, its **name author**, derived from the actor of the write
  that set the name — `operator` for the Risk page, `agent` for an API or MCP
  token (`Portfolixir.Portfolios.PolicyRuleVersion.author_for/1`). A rename is
  no version, so a version's author never said who gave the name.

    1. **The column** is nullable text with a CHECK mirroring the schema's
       closed set. A new rule and every rename set it; a rule stored before
       this migration has none until step 2 gives it one. It changes with
       every rename, so no guard keeps it.
    2. **The backfill** (`Portfolixir.Portfolios.PolicyRuleNameAuthorBackfill`)
       takes the author the journal recorded for the rule's last rename, or,
       where it was never renamed, the author of its first version, written
       with the name; each write journaled under a `system_job` actor. A rule
       with neither keeps no name author and is counted in the log.
       Idempotent: a re-run writes nothing.

  `PolicyRuleNameAuthorBackfill.run/1` is referenced from this immutable
  migration — keep its signature stable. It is pinned by the seeded case in
  `test/portfolixir/seeded_upgrade/author_marks_test.exs`.
  """
  use Ecto.Migration

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios.PolicyRuleNameAuthorBackfill

  def up do
    alter table(:policy_rules) do
      add(:name_author, :string)
    end

    create(
      constraint(:policy_rules, :policy_rules_name_author_check,
        check: "name_author IS NULL OR name_author IN ('operator', 'agent')"
      )
    )

    # The backfill reads and writes the table, which needs the column
    # committed to the migration's own transaction first.
    flush()

    {:ok, report} =
      PolicyRuleNameAuthorBackfill.run(Actor.system_job("policy_name_author_backfill"))

    if report.untraced > 0 do
      Logger.warning(
        "policy-rule name author backfill (H14): #{report.untraced} rule(s) have neither a " <>
          "journaled rename nor an authored version and keep no name author"
      )
    end
  end

  def down do
    drop(constraint(:policy_rules, :policy_rules_name_author_check))

    # Dropping the column rewrites no row, so the journal needs no actor.
    alter table(:policy_rules) do
      remove(:name_author)
    end
  end
end
