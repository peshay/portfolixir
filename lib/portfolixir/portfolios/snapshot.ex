defmodule Portfolixir.Portfolios.Snapshot do
  @moduledoc """
  A depot snapshot (ADR-0027): a named ledger **marker** — view scope plus
  as-of date — freezing "the holdings I had on day X" without copying any
  financial data. Quantities and cost basis are derived on demand by
  projecting the transaction ledger up to `as_of` (ADR-0004), so a snapshot
  can never drift from the ledger.

  `view_id = nil` marks the "everything" scope (ADR-0024). Names are unique
  per scope (partial-NULL-aware unique index, NULLS NOT DISTINCT).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Buckets.View

  @type t :: %__MODULE__{}

  schema "depot_snapshots" do
    field(:name, :string)
    field(:as_of, :date)

    belongs_to(:view, View)

    timestamps()
  end

  @doc """
  Builds a snapshot changeset. `today` is injected by the context shell (the
  clock stays out of schemas and engines, AR-2): an as-of date after `today`
  is rejected — a snapshot marks a state that exists, never a future one.
  """
  def changeset(snapshot, attrs, today) do
    snapshot
    |> cast(attrs, [:name, :as_of, :view_id])
    |> validate_required([:name, :as_of])
    |> validate_length(:name, max: 120)
    |> validate_not_future(today)
    |> assoc_constraint(:view)
    |> unique_constraint([:name, :view_id], name: :depot_snapshots_name_per_scope_index)
  end

  defp validate_not_future(changeset, today) do
    validate_change(changeset, :as_of, fn :as_of, as_of ->
      case Date.compare(as_of, today) do
        :gt -> [as_of: "must not lie in the future"]
        _ -> []
      end
    end)
  end
end
