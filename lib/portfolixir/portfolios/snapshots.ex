defmodule Portfolixir.Portfolios.Snapshots do
  @moduledoc """
  Depot snapshots (ADR-0027): create, list and delete the ledger markers that
  freeze "the holdings of a view scope as of day X" — by reference, never by
  copy. The comparison itself ("would I have done better keeping these
  holdings?") is computed by `Portfolixir.Portfolios.SnapshotComparison` from
  the ledger and the stored quote history.

  Writes are actor-first and journaled (FR-28): a snapshot is user data whose
  creation and deletion should be attributable, even though the marker itself
  carries no financial values.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Portfolixir.Actor
  alias Portfolixir.Buckets.View
  alias Portfolixir.Journal
  alias Portfolixir.Portfolios.Snapshot
  alias Portfolixir.Repo

  @doc """
  Creates a snapshot marker on behalf of `actor`.

  `attrs`: `name` (unique per scope), `as_of` (date, not in the future),
  `view_id` (optional; `nil` = the "everything" scope). Returns
  `{:ok, %Snapshot{}}` or `{:error, %Ecto.Changeset{}}`.
  """
  def create_snapshot(%Actor{} = actor, attrs, opts \\ []) when is_map(attrs) do
    today = Keyword.get(opts, :today, Date.utc_today())

    Multi.new()
    |> Multi.insert(:snapshot, Snapshot.changeset(%Snapshot{}, attrs, today))
    |> Journal.record(actor, resource_type: "snapshot", operation: :create, source: :snapshot)
    |> Repo.transaction()
    |> normalize()
  end

  @doc """
  Lists snapshots, newest as-of first. Pass `view:` (a `%View{}`, view id, or
  `nil` for the "everything" scope) to filter — omitting the key lists all.
  """
  def list_snapshots(opts \\ []) do
    from(s in Snapshot)
    |> filter_view(opts)
    |> order_by([s], desc: s.as_of, desc: s.id)
    |> Repo.all()
  end

  @doc "Fetches one snapshot, or `{:error, :not_found}`."
  def fetch_snapshot(%Snapshot{} = snapshot), do: {:ok, snapshot}

  def fetch_snapshot(id) when is_integer(id) do
    case Repo.get(Snapshot, id) do
      nil -> {:error, :not_found}
      snapshot -> {:ok, snapshot}
    end
  end

  @doc """
  Deletes a snapshot marker on behalf of `actor`. Returns `{:ok, %Snapshot{}}`,
  `{:error, :not_found}`, or `{:error, %Ecto.Changeset{}}`.
  """
  def delete_snapshot(%Actor{} = actor, snapshot_or_id) do
    with {:ok, snapshot} <- fetch_snapshot(snapshot_or_id) do
      Multi.new()
      |> Multi.delete(:snapshot, snapshot)
      |> Journal.record(actor,
        resource_type: "snapshot",
        operation: :delete,
        source: :snapshot,
        before: snapshot
      )
      |> Repo.transaction()
      |> normalize()
    end
  end

  defp normalize({:ok, %{snapshot: snapshot}}), do: {:ok, snapshot}
  defp normalize({:error, :snapshot, changeset, _changes}), do: {:error, changeset}

  defp filter_view(query, opts) do
    case Keyword.fetch(opts, :view) do
      :error -> query
      {:ok, nil} -> where(query, [s], is_nil(s.view_id))
      {:ok, %View{id: id}} -> where(query, [s], s.view_id == ^id)
      {:ok, id} when is_integer(id) -> where(query, [s], s.view_id == ^id)
    end
  end
end
