defmodule Portfolixir.Repo.Migrations.AddAuthorsToTaxStatementsAndAllowanceOrders do
  @moduledoc """
  Security review 2026-10-12, K12 (decision T-16): a recorded tax statement
  and an allowance order store who recorded them (`author`) and who last
  corrected them (`corrected_by`), each derived from the actor of the write
  — `operator` for the Tax page, `agent` for an API or MCP token
  (`Portfolixir.Actor.author/1`) — so a statement the agent recorded or
  corrected is told apart from the operator's own transcription without the
  journal.

    1. **The columns** are nullable text with a CHECK mirroring the schemas'
       closed set, on both tables. A create sets `author`, every update
       `corrected_by`; a row stored before this migration has neither until
       step 2 gives it what the journal names.
    2. **The backfill** (`Portfolixir.Tax.AuthorBackfill`) takes `author`
       from each row's journaled creation and `corrected_by` from its last
       journaled update not made by the instance's own jobs, each write
       journaled under a `system_job` actor. A row with neither entry keeps
       none and is counted in the log. Idempotent: a re-run writes nothing.

  `Portfolixir.Tax.AuthorBackfill.run/1` is referenced from this immutable
  migration — keep its signature stable. It is pinned by the seeded case in
  `test/portfolixir/seeded_upgrade/author_marks_test.exs`.
  """
  use Ecto.Migration

  require Logger

  alias Portfolixir.Actor
  alias Portfolixir.Tax.AuthorBackfill

  @tables [:tax_statement_snapshots, :allowance_orders]

  def up do
    for table <- @tables do
      alter table(table) do
        add(:author, :string)
        add(:corrected_by, :string)
      end

      create(
        constraint(table, :"#{table}_author_check",
          check: "author IS NULL OR author IN ('operator', 'agent')"
        )
      )

      create(
        constraint(table, :"#{table}_corrected_by_check",
          check: "corrected_by IS NULL OR corrected_by IN ('operator', 'agent')"
        )
      )
    end

    # The backfill reads and writes the tables, which needs the columns
    # committed to the migration's own transaction first.
    flush()

    {:ok, report} = AuthorBackfill.run(Actor.system_job("tax_author_backfill"))

    if report.untraced > 0 do
      Logger.warning(
        "tax author backfill (K12): #{report.untraced} statement(s) or allowance order(s) " <>
          "have no journaled creation or correction and keep no author"
      )
    end
  end

  def down do
    for table <- @tables do
      drop(constraint(table, :"#{table}_corrected_by_check"))
      drop(constraint(table, :"#{table}_author_check"))

      # Dropping the columns rewrites no row, so the journal needs no actor.
      alter table(table) do
        remove(:corrected_by)
        remove(:author)
      end
    end
  end
end
