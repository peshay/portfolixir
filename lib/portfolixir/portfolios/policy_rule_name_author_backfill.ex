defmodule Portfolixir.Portfolios.PolicyRuleNameAuthorBackfill do
  @moduledoc """
  The one-time backfill of a policy rule's `name_author` (security review
  2026-10-12, H14, T-16), run by the migration
  `add_name_author_to_policy_rules`.

  A rule stored before name authors existed has none. Both policy tables were
  journal-armed from their first migration, and a rule row is updated only
  by a rename, so the rule's last update entry (`resource_type`
  `policy_rule`, operation `update`, a real write — never a scenario) names
  the actor that gave the current name, and the name author is the one
  `Portfolixir.Portfolios.PolicyRuleVersion.author_for/1` derives for that
  actor type. A rule never renamed carries the name it was created with,
  written with its first version, so it takes that version's stored author.

  A rule with neither keeps no name author and is counted as untraced; the
  migration logs the count. Each row written is journaled under the caller's
  actor with its before and after, and its `updated_at` moves, so a `since=`
  reader sees the new field. The journal hands the schemaless row to the
  invalidation seam, which cannot resolve its portfolio and so bumps every
  portfolio basis: a finding memoised before the backfill is never served
  again. The backfill only fills an empty name author, so a second run
  writes nothing.

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
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias Portfolixir.Repo

  @columns ~w(id portfolio_id view_id name name_author inserted_at updated_at)a

  @type report :: %{
          operator: non_neg_integer(),
          agent: non_neg_integer(),
          untraced: non_neg_integer()
        }

  @doc """
  Fills the name author of every rule that has none from its last journaled
  rename, or from its first version's author, journaled under `actor`.
  Returns how many rows became `operator` and `agent`, and how many have
  neither.
  """
  @spec run(Actor.t()) :: {:ok, report()}
  def run(%Actor{} = actor) do
    pending =
      from(r in "policy_rules", where: is_nil(r.name_author), order_by: r.id, select: r.id)
      |> Repo.all()

    renamers = renamers(pending)
    first_authors = first_version_authors(pending)

    report =
      Enum.reduce(pending, %{operator: 0, agent: 0, untraced: 0}, fn id, acc ->
        case name_author(id, renamers, first_authors) do
          nil ->
            Map.update!(acc, :untraced, &(&1 + 1))

          author ->
            :ok = write_row(actor, id, author)
            Map.update!(acc, author, &(&1 + 1))
        end
      end)

    {:ok, report}
  end

  defp name_author(id, renamers, first_authors) do
    case Map.fetch(renamers, Integer.to_string(id)) do
      {:ok, actor_type} -> PolicyRuleVersion.author_for(%Actor{type: actor_type})
      :error -> Map.get(first_authors, id)
    end
  end

  # The actor type of each rule's last update entry — its last rename — by
  # the rule's id as the journal files it (a string).
  defp renamers([]), do: %{}

  defp renamers(ids) do
    wanted = MapSet.new(ids, &Integer.to_string/1)

    [resource_type: "policy_rule", operation: :update]
    |> Journal.list_entries()
    |> Enum.filter(&MapSet.member?(wanted, &1.resource_id))
    |> Enum.sort_by(& &1.id, :desc)
    |> Enum.reduce(%{}, fn entry, acc -> Map.put_new(acc, entry.resource_id, entry.actor_type) end)
  end

  # The stored author of each rule's first version (earliest start, then
  # id), the one written with the rule and its name.
  defp first_version_authors([]), do: %{}

  defp first_version_authors(ids) do
    from(v in "policy_rule_versions",
      where: v.policy_rule_id in ^ids and not is_nil(v.author),
      order_by: [asc: v.policy_rule_id, asc: v.valid_from, asc: v.id],
      select: {v.policy_rule_id, v.author}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {rule_id, author}, acc ->
      Map.put_new(acc, rule_id, stored_author(author))
    end)
  end

  # The closed set the column's CHECK allows, read without making atoms.
  defp stored_author("operator"), do: :operator
  defp stored_author("agent"), do: :agent

  defp write_row(actor, id, author) do
    row = from(r in "policy_rules", where: r.id == ^id, select: map(r, ^@columns))
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Multi.new()
    |> Multi.run(:before, fn repo, _changes ->
      {:ok, row |> lock("FOR UPDATE") |> repo.one!()}
    end)
    |> Multi.run(:rule, fn repo, _changes ->
      {1, [written]} =
        repo.update_all(
          where(row, [r], is_nil(r.name_author)),
          set: [name_author: Atom.to_string(author), updated_at: now]
        )

      {:ok, written}
    end)
    |> Journal.record(actor,
      resource_type: "policy_rule",
      operation: :update,
      source: :rule,
      before_step: :before
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
    end
  end
end
