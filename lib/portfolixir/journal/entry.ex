defmodule Portfolixir.Journal.Entry do
  @moduledoc """
  One append-only audit-journal row (ADR-0017, FR-28).

  An entry records a single committed financial write: who (`actor_type` /
  `actor_label`), what (`operation` on `resource_type`/`resource_id`), and the
  serialized `before`/`after` snapshots. Rows are never updated or deleted —
  the schema carries `inserted_at` only, and the database enforces append-only
  with triggers (see the `create_audit_journal` migration).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Actor

  @operations [:create, :update, :delete, :upsert]

  @type t :: %__MODULE__{}

  @primary_key {:id, :id, autogenerate: true}
  schema "audit_journal" do
    field(:actor_type, Ecto.Enum, values: Actor.types())
    field(:actor_label, :string)
    field(:operation, Ecto.Enum, values: @operations)
    field(:resource_type, :string)
    field(:resource_id, :string)
    field(:before, :map)
    field(:after, :map)
    field(:scenario_id, :integer)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc "The closed operation taxonomy."
  @spec operations() :: [atom()]
  def operations, do: @operations

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :actor_type,
      :actor_label,
      :operation,
      :resource_type,
      :resource_id,
      :before,
      :after,
      :scenario_id
    ])
    |> validate_required([:actor_type, :operation, :resource_type])
  end
end
