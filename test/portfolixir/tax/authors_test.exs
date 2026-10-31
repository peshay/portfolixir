defmodule Portfolixir.Tax.AuthorsTest do
  # Security review 2026-10-12, K12 (decision T-16): a recorded tax statement
  # and an allowance order store who recorded them and who corrected them
  # last, derived from the actor of the write and never from input, and the
  # trim budget says which institutions rest on the agent's statement.
  use Portfolixir.DataCase, async: true

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Tax
  alias Portfolixir.Tax.AllowanceOrder
  alias Portfolixir.Tax.AuthorBackfill
  alias Portfolixir.Tax.StatementSnapshot

  @today ~D[2026-01-15]

  defp statement!(actor, institution, overrides \\ %{}) do
    {:ok, snapshot} =
      Tax.create_snapshot(
        actor,
        Map.merge(
          %{
            institution: institution,
            holder: "Owner",
            tax_year: 2025,
            as_of: ~D[2025-12-31],
            allowance_granted: "1000",
            allowance_used: "0",
            loss_pot_equities: "0"
          },
          overrides
        ),
        today: @today
      )

    snapshot
  end

  defp order!(actor, institution, amount, overrides \\ %{}) do
    {:ok, order} =
      Tax.put_allowance_order(
        actor,
        Map.merge(
          %{holder: "Owner", institution: institution, tax_year: 2025, amount_granted: amount},
          overrides
        )
      )

    order
  end

  # User story (security review 2026-10-12, K12, T-16):
  # As the operator whose agent records tax statements with its token,
  # I want every statement to store who recorded it and who corrected it
  # last, from the actor of the write,
  # so that the agent's figures are told apart from my own transcription.
  #
  # Acceptance criteria:
  # - A create stores author operator for the Tax page and agent for an API
  #   token, read-write or read-only; corrected_by stays empty.
  # - An update stores corrected_by from its actor and keeps the author; an
  #   update that changes nothing keeps corrected_by.
  # - An author or corrected_by in the input is never read; the source stays
  #   manual.
  test "a statement's author and corrector are the actors of its create and its last update" do
    mine = statement!(Actor.owner_ui(), "Bank A", %{author: "agent", corrected_by: "agent"})
    assert {mine.author, mine.corrected_by, mine.source} == {:operator, nil, "manual"}

    agents = statement!(Actor.api_token_rw("mcp"), "Bank B")
    assert {agents.author, agents.corrected_by} == {:agent, nil}
    assert statement!(Actor.api_token_ro(), "Bank C").author == :agent

    {:ok, corrected} =
      Tax.update_snapshot(
        Actor.api_token_rw("mcp"),
        mine,
        %{loss_pot_equities: "25000", corrected_by: "operator"},
        today: @today
      )

    assert {corrected.author, corrected.corrected_by} == {:operator, :agent}
    assert StatementSnapshot.agent_written?(corrected)

    {:ok, unchanged} =
      Tax.update_snapshot(Actor.owner_ui(), corrected, %{loss_pot_equities: "25000"},
        today: @today
      )

    assert unchanged.corrected_by == :agent

    {:ok, back} =
      Tax.update_snapshot(Actor.owner_ui(), corrected, %{loss_pot_equities: "0"}, today: @today)

    assert {back.author, back.corrected_by} == {:operator, :operator}
    refute StatementSnapshot.agent_written?(back)

    {:ok, theirs} =
      Tax.update_snapshot(Actor.owner_ui(), agents, %{allowance_used: "10"}, today: @today)

    assert {theirs.author, theirs.corrected_by} == {:agent, :operator}
    assert StatementSnapshot.agent_written?(theirs)
  end

  # User story (security review 2026-10-12, K12, T-16):
  # As the operator whose agent can put allowance orders with its token,
  # I want every order to store who put it and who replaced it last,
  # so that an order the agent put is marked where I compare it.
  #
  # Acceptance criteria:
  # - The first put stores its author; a later put that changes the order
  #   stores corrected_by and keeps the author; one that changes nothing
  #   keeps both. Neither is read from input.
  test "an allowance order's author and corrector are the actors of its puts" do
    order = order!(Actor.api_token_rw("mcp"), "Bank B", "400", %{author: "operator"})
    assert {order.author, order.corrected_by} == {:agent, nil}
    assert AllowanceOrder.agent_written?(order)

    same = order!(Actor.owner_ui(), "Bank B", "400")
    assert {same.id, same.author, same.corrected_by} == {order.id, :agent, nil}

    replaced = order!(Actor.owner_ui(), "bank b", "500")
    assert {replaced.id, replaced.author, replaced.corrected_by} == {order.id, :agent, :operator}

    mine = order!(Actor.owner_ui(), "Bank A", "600")
    refute AllowanceOrder.agent_written?(mine)
  end

  # User story (security review 2026-10-12, K12, T-16; board 03, Q3 = A):
  # As the operator reading the trim budget,
  # I want the roll-up to name the institutions whose counted statement the
  # agent recorded or corrected last,
  # so that the basis line can mark them.
  #
  # Acceptance criteria:
  # - agent_institutions lists exactly those institutions, sorted; a
  #   statement the latest one superseded does not count.
  test "the trim budget names the institutions that rest on the agent's statement" do
    statement!(Actor.owner_ui(), "Bank A")
    statement!(Actor.api_token_rw("mcp"), "Bank B")
    corrected = statement!(Actor.owner_ui(), "Bank C")

    {:ok, _} =
      Tax.update_snapshot(Actor.api_token_rw("mcp"), corrected, %{allowance_used: "5"},
        today: @today
      )

    statement!(Actor.api_token_rw("mcp"), "Bank D", %{as_of: ~D[2025-06-30]})
    statement!(Actor.owner_ui(), "Bank D")

    summary = Tax.holder_summary("Owner", 2025)
    assert summary.institutions == ["Bank A", "Bank B", "Bank C", "Bank D"]
    assert summary.agent_institutions == ["Bank B", "Bank C"]
  end

  # User story (security review 2026-10-12, K12, T-16):
  # As the operator upgrading an instance whose agent already recorded and
  # corrected tax statements,
  # I want the rows stored before authors existed to take what the journal
  # recorded for their creation and their last correction,
  # so that the agent's figures are marked from the first day.
  #
  # Acceptance criteria:
  # - author comes from the creation entry, corrected_by from the last
  #   update entry that no system job wrote; a row with neither keeps none
  #   and is counted as untraced.
  # - Each backfilled row is journaled under the system job it runs as; a
  #   second run writes and journals nothing.
  test "the backfill takes a stored row's authors from its journal" do
    by_agent = statement!(Actor.api_token_rw("mcp"), "Bank A")
    corrected = statement!(Actor.owner_ui(), "Bank B")

    {:ok, corrected} =
      Tax.update_snapshot(Actor.api_token_rw("mcp"), corrected, %{allowance_used: "5"},
        today: @today
      )

    normalised = journaled_update!(corrected, Actor.system_job("tax_identity_backfill"))
    order = order!(Actor.api_token_rw("mcp"), "Bank A", "400")
    untraced = untraced_statement!("Bank C")

    for {table, id} <- [
          {"tax_statement_snapshots", by_agent.id},
          {"tax_statement_snapshots", normalised.id},
          {"allowance_orders", order.id}
        ] do
      clear_authors!(table, id)
    end

    backfill_entries = fn ->
      [actor_type: :system_job, operation: :update, limit: 1000]
      |> Journal.list_entries()
      |> Enum.count(&(&1.actor_label == "tax_author_backfill"))
    end

    actor = Actor.system_job("tax_author_backfill")
    assert {:ok, %{written: 3, untraced: 1}} = AuthorBackfill.run(actor)

    assert authors(StatementSnapshot, by_agent.id) == {:agent, nil}
    assert authors(StatementSnapshot, normalised.id) == {:operator, :agent}
    assert authors(AllowanceOrder, order.id) == {:agent, nil}
    assert authors(StatementSnapshot, untraced.id) == {nil, nil}
    assert backfill_entries.() == 3

    assert {:ok, %{written: 0, untraced: 1}} = AuthorBackfill.run(actor)
    assert backfill_entries.() == 3
  end

  defp authors(schema, id) do
    row = Repo.get!(schema, id)
    {row.author, row.corrected_by}
  end

  # An update journaled under `actor` that changes the note only, as the
  # instance's own jobs write one.
  defp journaled_update!(snapshot, actor) do
    {:ok, %{record: record}} =
      Multi.new()
      |> Multi.update(:record, Ecto.Changeset.change(snapshot, note: "normalised"))
      |> Journal.record(actor,
        resource_type: "tax_statement_snapshot",
        operation: :update,
        source: :record,
        before: snapshot
      )
      |> Repo.transaction()

    record
  end

  # A statement stored before the table was journal-armed: no entry at all.
  defp untraced_statement!(institution) do
    raw!(fn ->
      Repo.insert!(%StatementSnapshot{
        institution: institution,
        holder: "Owner",
        tax_year: 2025,
        as_of: ~D[2025-12-31]
      })
    end)
  end

  defp clear_authors!(table, id) do
    raw!(fn ->
      Repo.query!("UPDATE #{table} SET author = NULL, corrected_by = NULL WHERE id = $1", [id])
    end)
  end

  defp raw!(fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job', true)")
        fun.()
      end)

    result
  end
end
