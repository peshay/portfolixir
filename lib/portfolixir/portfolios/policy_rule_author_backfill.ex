defmodule Portfolixir.Portfolios.PolicyRuleAuthorBackfill do
  @moduledoc """
  The one-time backfill of a policy-rule version's `author` (E25 S7, G30),
  run by the migration `add_author_to_policy_rule_versions`.

  A version stored before authors existed has none. Both policy tables were
  journal-armed from their first migration, so the version's creation entry
  (`resource_type` `policy_rule_version`, operation `create`, a real write —
  never a scenario) names the actor that wrote it, and the author is the one
  `Portfolixir.Portfolios.PolicyRuleVersion.author_for/1` derives for that
  actor type: `agent` for an API token, `operator` otherwise.

  A version without a creation entry keeps no author and is counted as
  untraced; the migration logs the count. Each row written is journaled under
  the caller's actor with its before and after, and its `updated_at` moves,
  so a `since=` reader sees the new field. The journal hands the schemaless
  row to the invalidation seam, which cannot resolve its portfolio and so
  bumps every portfolio basis: a finding memoised before the backfill, keyed
  under that basis, is never served again. The backfill only fills an empty
  author, so a second run writes nothing.

  It reads and writes the table schemaless, naming only the columns it has at
  this migration, so the immutable migration keeps running when a later one
  adds a column the schema then knows.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias Portfolixir.Repo

  @columns ~w(id policy_rule_id subject_type security_id classification_id category_id
              subject_view_id measure kind threshold lower upper metric_window severity note
              valid_from valid_until author inserted_at updated_at)a

  @type report :: %{
          operator: non_neg_integer(),
          agent: non_neg_integer(),
          untraced: non_neg_integer()
        }

  @doc """
  Fills the author of every version that has none from its journaled
  creation, journaled under `actor`. Returns how many rows became `operator`
  and `agent`, and how many have no creation entry.
  """
  @spec run(Actor.t()) :: {:ok, report()}
  def run(%Actor{} = actor) do
    pending =
      from(v in "policy_rule_versions", where: is_nil(v.author), order_by: v.id, select: v.id)
      |> Repo.all()

    creators = creators(pending)

    report =
      Enum.reduce(pending, %{operator: 0, agent: 0, untraced: 0}, fn id, acc ->
        case Map.fetch(creators, Integer.to_string(id)) do
          {:ok, actor_type} ->
            author = PolicyRuleVersion.author_for(%Actor{type: actor_type})
            :ok = write_row(actor, id, author)
            Map.update!(acc, author, &(&1 + 1))

          :error ->
            Map.update!(acc, :untraced, &(&1 + 1))
        end
      end)

    {:ok, report}
  end

  # The actor type of each version's first creation entry — a real write, as
  # `Journal.list_entries/1` reads by default, never a scenario — by the
  # version's id as the journal files it (a string). A one-time read: rules
  # are few, and every creation entry is read once.
  defp creators([]), do: %{}

  defp creators(ids) do
    wanted = MapSet.new(ids, &Integer.to_string/1)

    [resource_type: "policy_rule_version", operation: :create]
    |> Journal.list_entries()
    |> Enum.filter(&MapSet.member?(wanted, &1.resource_id))
    |> Enum.sort_by(& &1.id)
    |> Enum.reduce(%{}, fn entry, acc -> Map.put_new(acc, entry.resource_id, entry.actor_type) end)
  end

  defp write_row(actor, id, author) do
    row = from(v in "policy_rule_versions", where: v.id == ^id, select: map(v, ^@columns))
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Multi.new()
    |> Multi.run(:before, fn repo, _changes ->
      {:ok, row |> lock("FOR UPDATE") |> repo.one!()}
    end)
    |> Multi.run(:version, fn repo, _changes ->
      {1, [written]} =
        repo.update_all(
          where(row, [v], is_nil(v.author)),
          set: [author: Atom.to_string(author), updated_at: now]
        )

      {:ok, written}
    end)
    |> Journal.record(actor,
      resource_type: "policy_rule_version",
      operation: :update,
      source: :version,
      before_step: :before
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
    end
  end
end
