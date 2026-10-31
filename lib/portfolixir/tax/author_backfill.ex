defmodule Portfolixir.Tax.AuthorBackfill do
  @moduledoc """
  The one-time backfill of `author` and `corrected_by` on recorded tax
  statements and allowance orders (security review 2026-10-12, K12, T-16),
  run by the migration `add_authors_to_tax_statements_and_allowance_orders`.

  A row stored before authors existed has neither. Both tables are
  journal-armed, so a row's creation entry (operation `create`, a real write
  — never a scenario) names the actor that recorded it, and its last update
  entry the actor that corrected it last; each becomes the author
  `Portfolixir.Actor.author/1` derives for that actor type. An update the
  instance's own jobs journaled (a `system_job`, such as the identity
  normalisation or this backfill) corrects nothing the operator or the agent
  wrote, so it is passed over. A row recorded before the table was armed has
  no creation entry and keeps no author.

  A row with neither entry is counted as untraced; the migration logs the
  count. Each row written is journaled under the caller's actor with its
  before and after, and its `updated_at` moves, so a `since=` reader sees the
  new fields. The backfill only fills a row that has neither field, so a
  second run writes nothing.

  It reads and writes the tables schemaless, naming only the columns they
  have at this migration, so the immutable migration keeps running when a
  later one adds a column the schema then knows. Pinned, not frozen (#1015):
  the seeded case in `test/portfolixir/seeded_upgrade/author_marks_test.exs`
  turns red when a later change makes this code, or the journal write it
  calls, touch a column the migration's version lacks.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Repo

  @tables [
    {"tax_statement_snapshots", "tax_statement_snapshot",
     ~w(id institution holder tax_year as_of source church_tax_rate note taxable_income
        allowance_granted allowance_used loss_pot_equities loss_pot_other
        loss_carryforward_prior_years withholding_tax_pot withholding_tax_credited
        capital_gains_tax_withheld solidarity_surcharge_withheld church_tax_withheld
        author corrected_by inserted_at updated_at)a},
    {"allowance_orders", "allowance_order",
     ~w(id holder institution tax_year amount_granted note author corrected_by inserted_at
        updated_at)a}
  ]

  @type report :: %{written: non_neg_integer(), untraced: non_neg_integer()}

  @doc """
  Fills `author` and `corrected_by` of every statement and allowance order
  that has neither, from its journal, journaled under `actor`. Returns how
  many rows were written and how many have no entry to read.
  """
  @spec run(Actor.t()) :: {:ok, report()}
  def run(%Actor{} = actor) do
    report =
      Enum.reduce(@tables, %{written: 0, untraced: 0}, fn table, acc ->
        {written, untraced} = backfill(actor, table)
        %{written: acc.written + written, untraced: acc.untraced + untraced}
      end)

    {:ok, report}
  end

  defp backfill(actor, {table, resource_type, columns}) do
    pending =
      from(r in table,
        where: is_nil(r.author) and is_nil(r.corrected_by),
        order_by: r.id,
        select: r.id
      )
      |> Repo.all()

    creators = actor_types(pending, resource_type, :create, :first)
    correctors = actor_types(pending, resource_type, :update, :last)

    Enum.reduce(pending, {0, 0}, fn id, {written, untraced} ->
      key = Integer.to_string(id)
      author = author(Map.get(creators, key))
      corrected_by = author(Map.get(correctors, key))

      if is_nil(author) and is_nil(corrected_by) do
        {written, untraced + 1}
      else
        :ok = write_row(actor, {table, resource_type, columns}, id, author, corrected_by)
        {written + 1, untraced}
      end
    end)
  end

  # The actor type of each row's first (`:first`) or last (`:last`) entry of
  # `operation`, by the row's id as the journal files it (a string). Entries
  # the instance's own jobs wrote are passed over.
  defp actor_types([], _resource_type, _operation, _which), do: %{}

  defp actor_types(ids, resource_type, operation, which) do
    wanted = MapSet.new(ids, &Integer.to_string/1)
    order = if which == :first, do: :asc, else: :desc

    [resource_type: resource_type, operation: operation]
    |> Journal.list_entries()
    |> Enum.filter(&(MapSet.member?(wanted, &1.resource_id) and &1.actor_type != :system_job))
    |> Enum.sort_by(& &1.id, order)
    |> Enum.reduce(%{}, fn entry, acc -> Map.put_new(acc, entry.resource_id, entry.actor_type) end)
  end

  defp author(nil), do: nil
  defp author(actor_type), do: Actor.author(%Actor{type: actor_type})

  defp write_row(actor, {table, resource_type, columns}, id, author, corrected_by) do
    row = from(r in table, where: r.id == ^id, select: map(r, ^columns))
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Multi.new()
    |> Multi.run(:before, fn repo, _changes ->
      {:ok, row |> lock("FOR UPDATE") |> repo.one!()}
    end)
    |> Multi.run(:row, fn repo, _changes ->
      {1, [written]} =
        repo.update_all(
          where(row, [r], is_nil(r.author) and is_nil(r.corrected_by)),
          set: [author: stored(author), corrected_by: stored(corrected_by), updated_at: now]
        )

      {:ok, written}
    end)
    |> Journal.record(actor,
      resource_type: resource_type,
      operation: :update,
      source: :row,
      before_step: :before
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
    end
  end

  defp stored(nil), do: nil
  defp stored(author), do: Atom.to_string(author)
end
