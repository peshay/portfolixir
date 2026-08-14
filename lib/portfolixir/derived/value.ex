defmodule Portfolixir.Derived.Value do
  @moduledoc """
  One durable derived value (ADR-0039 §1, the `:durable` lifetime): a row
  carrying `as_of` and the `(data_version, computation_version)` pair it was
  computed at. One row per `(analytic_id, basis, entry_key)`, replaced on
  recompute — the not-yet-replaced row of a superseded version *is* the §6
  stale render source, and it survives restarts.

  The payload is the computed term serialized with `:erlang.term_to_binary/1`
  (exact `Decimal` round-trip, no JSON coercion) and read back through
  `Plug.Crypto.non_executable_binary_to_term/2` with `[:safe]` — the table is
  written only by this application, but decoding defensively costs nothing.

  This table class is **not journaled** (a materialization write is not a
  financial write) and must never be read by a write path (I7). Both are
  enforced by name: `write_actor_test.exs` lists the derived tables
  explicitly, and `derived_never_a_write_source_test.exs` walks the write
  paths' ASTs.
  """

  use Ecto.Schema

  schema "derived_values" do
    field(:analytic_id, :string)
    field(:basis, :string)
    field(:entry_key, :string)
    field(:data_version, :integer)
    field(:computation_version, :integer)
    field(:as_of, :utc_datetime)
    field(:payload, :binary)

    timestamps(type: :utc_datetime)
  end

  @doc "Serializes a computed term into the payload column."
  @spec encode(term()) :: binary()
  def encode(value), do: :erlang.term_to_binary(value)

  @doc "Deserializes a payload column, refusing executable or atom-creating terms."
  @spec decode(binary()) :: term()
  def decode(payload) when is_binary(payload),
    do: Plug.Crypto.non_executable_binary_to_term(payload, [:safe])
end
