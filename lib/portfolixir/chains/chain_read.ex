defmodule Portfolixir.Chains.ChainRead do
  @moduledoc """
  The state row of one chain with a source (ADR-0059 §8, §9): the host that
  last answered, when a run was last tried and last succeeded, the last
  error (a short code and its reason per source), and the inputs of the
  next halving's estimate (§6): the tip's height, its block's timestamp and
  the timestamp of the block 2,016 below it. Plus the day and host of the
  last genesis check (§7, once a day per source).

  One row per chain, overwritten by each run of `Portfolixir.Chains.Reader`:
  state, not history, and not journaled (§9).

  The reader writes it through `changeset/2`, which holds the row to the
  writers' rules as every stored row is (the input sweeps): `chain` is one
  of the registry's names, the hosts and the error are one-line text within
  their columns, and the genesis check's day is a bounded date.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Portfolixir.Chains.Registry
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.Text

  @type t :: %__MODULE__{}

  schema "chain_reads" do
    field(:chain, :string)
    field(:source_host, :string)
    field(:last_tried_at, :utc_datetime)
    field(:last_ok_at, :utc_datetime)
    field(:last_error, :string)
    field(:tip_height, :integer)
    field(:tip_at, :utc_datetime)
    field(:tip_2016_at, :utc_datetime)
    field(:genesis_checked_on, :date)
    field(:genesis_checked_host, :string)

    timestamps(type: :utc_datetime)
  end

  @fields [
    :chain,
    :source_host,
    :last_tried_at,
    :last_ok_at,
    :last_error,
    :tip_height,
    :tip_at,
    :tip_2016_at,
    :genesis_checked_on,
    :genesis_checked_host
  ]

  # The columns' sizes (the migration 20261112210000).
  @host_max 255
  @error_max 512

  @doc "The state row's changeset: the writers' rules on what a run stores."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(row, attrs) do
    row
    |> cast(attrs, @fields)
    |> validate_required([:chain])
    |> validate_inclusion(:chain, Registry.names())
    |> Text.validate([:source_host, :genesis_checked_host], max: @host_max)
    |> Text.validate(:last_error, max: @error_max)
    |> BoundedDate.validate([:genesis_checked_on])
  end
end
