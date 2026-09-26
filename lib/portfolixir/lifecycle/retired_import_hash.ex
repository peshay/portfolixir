defmodule Portfolixir.Lifecycle.RetiredImportHash do
  @moduledoc """
  The content hash of a row a merge removed, kept so that no re-import books
  that row again (ADR-0050 §3, obligation O1).

  A merge removes a row for one of two reasons, and says which: an
  `internal_transfer` (§5: both legs became one account, the row is void) or
  a `collapsed_duplicate` (§8: the operator chose to collapse a key-equal
  pair, and `superseded_by_transaction_id` names the target row that stays).
  `former_transaction_id` is the removed row's id; `merge_record_id` the
  record of the merge that removed it.

  Rows are never updated or deleted, and a hash is retired at most once; the
  database enforces both, and refuses a retired hash on `transactions`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @reasons [:internal_transfer, :collapsed_duplicate]

  @type t :: %__MODULE__{}

  schema "retired_import_hashes" do
    field(:import_hash, :string)
    field(:former_transaction_id, :integer)
    field(:merge_record_id, :integer)
    field(:reason, Ecto.Enum, values: @reasons)
    field(:superseded_by_transaction_id, :integer)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc "The closed set of reasons a merge removes a row for."
  @spec reasons() :: [atom()]
  def reasons, do: @reasons

  @doc false
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :import_hash,
      :former_transaction_id,
      :merge_record_id,
      :reason,
      :superseded_by_transaction_id
    ])
    |> validate_required([:import_hash, :former_transaction_id, :merge_record_id, :reason])
    |> validate_superseded_by()
    |> unique_constraint(:import_hash,
      name: :retired_import_hashes_import_hash_index,
      message: "has already been retired"
    )
    |> foreign_key_constraint(:merge_record_id,
      name: :retired_import_hashes_merge_record_id_fkey
    )
    |> check_constraint(:reason, name: :retired_import_hashes_reason_check)
  end

  # A collapse names the row that superseded the removed one; a void transfer
  # is superseded by nothing.
  defp validate_superseded_by(changeset) do
    case get_field(changeset, :reason) do
      :collapsed_duplicate ->
        validate_required(changeset, [:superseded_by_transaction_id])

      :internal_transfer ->
        if get_field(changeset, :superseded_by_transaction_id) == nil,
          do: changeset,
          else:
            add_error(
              changeset,
              :superseded_by_transaction_id,
              "must be empty for an internal transfer"
            )

      _unknown ->
        changeset
    end
  end
end
