defmodule Portfolixir.Lifecycle.MergeRecord do
  @moduledoc """
  One append-only record of a lifecycle merge (ADR-0050 §12).

  It names what was merged into what (`kind`, `source_id`, `target_id`, and
  the `portfolio_id` of an account merge), a `source_snapshot` of the source
  row, the `manifest` of every row the merge moved, restated, deleted,
  collapsed, re-pointed or dropped, the `plan_digest` the operator approved,
  and the actor. `source_id` and `target_id` carry no foreign key: the merge
  deletes its source, and a target can later be merged away itself.

  Rows are never updated or deleted: the schema carries `inserted_at` only,
  and the database refuses UPDATE, DELETE and TRUNCATE. `UNIQUE (kind,
  source_id)` makes a source mergeable once per kind.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Actor

  @kinds [:cash_account, :securities_account, :security]

  @type t :: %__MODULE__{}

  schema "merge_records" do
    field(:kind, Ecto.Enum, values: @kinds)
    field(:source_id, :integer)
    field(:target_id, :integer)
    field(:portfolio_id, :integer)
    field(:source_snapshot, :map)
    field(:manifest, :map)
    field(:plan_digest, :string)
    field(:actor_type, Ecto.Enum, values: Actor.types())
    field(:actor_label, :string)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc "The closed set of entities a merge exists for."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc """
  The changeset for a new record. The actor comes from the writer's `Actor`,
  never from the attributes.
  """
  def create_changeset(attrs, %Actor{} = actor) do
    {_type, actor_label} = Actor.to_columns(actor)

    %__MODULE__{}
    |> cast(attrs, [
      :kind,
      :source_id,
      :target_id,
      :portfolio_id,
      :source_snapshot,
      :manifest,
      :plan_digest
    ])
    |> put_change(:actor_type, actor.type)
    |> put_change(:actor_label, actor_label)
    |> validate_required([
      :kind,
      :source_id,
      :target_id,
      :source_snapshot,
      :manifest,
      :plan_digest,
      :actor_type
    ])
    |> validate_distinct_rows()
    |> validate_portfolio()
    |> unique_constraint(:source_id,
      name: :merge_records_kind_source_id_index,
      message: "has already been merged"
    )
    |> foreign_key_constraint(:portfolio_id)
    |> check_constraint(:kind, name: :merge_records_kind_check)
    |> check_constraint(:target_id,
      name: :merge_records_distinct_rows_check,
      message: "must differ from the source"
    )
    |> check_constraint(:portfolio_id, name: :merge_records_portfolio_check)
  end

  defp validate_distinct_rows(changeset) do
    source = get_field(changeset, :source_id)

    if source != nil and source == get_field(changeset, :target_id) do
      add_error(changeset, :target_id, "must differ from the source")
    else
      changeset
    end
  end

  # The composite foreign keys pin an account to one portfolio, so an account
  # merge names it; a security belongs to none.
  defp validate_portfolio(changeset) do
    case get_field(changeset, :kind) do
      :security ->
        if get_field(changeset, :portfolio_id) == nil,
          do: changeset,
          else: add_error(changeset, :portfolio_id, "must be empty for a security merge")

      kind when kind in [:cash_account, :securities_account] ->
        validate_required(changeset, [:portfolio_id])

      _unknown ->
        changeset
    end
  end
end
