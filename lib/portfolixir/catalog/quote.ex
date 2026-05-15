defmodule Portfolixir.Catalog.Quote do
  @moduledoc """
  A single end-of-day close for a security.

  Quotes are an append/upsert log keyed by `(security_id, date)`. The
  `source` field documents the provenance of the value so manual entries,
  background syncs, and provider-specific captures stay distinguishable.

  Decimals are used everywhere — never floats — so the data round-trips
  losslessly between the database, charts, and downstream calculations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(auto manual coingecko portfolio_performance)

  schema "security_quotes" do
    field(:security_id, :integer)
    field(:date, :date)
    field(:close, :decimal)
    field(:source, :string)

    timestamps()
  end

  def sources, do: @sources

  def changeset(quote_, attrs) do
    quote_
    |> cast(attrs, [:security_id, :date, :close, :source])
    |> validate_required([:security_id, :date, :close, :source])
    |> validate_inclusion(:source, @sources, message: "is invalid")
    |> unique_constraint([:security_id, :date],
      name: :security_quotes_security_id_date_index
    )
  end
end
