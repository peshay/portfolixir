defmodule Portfolixir.Catalog.QuoteWrite do
  @moduledoc """
  The journal image of one authored write to a security's quotes (E25 S6,
  G27 under decision T-9).

  Quotes are one row per `(security_id, date)` and an authored write touches
  many of them at once, so the journal records the write as one aggregate
  under `resource_type: "security_quotes"` and the security's id: the
  `before` image holds the stored rows the write replaced or released, the
  `after` image the rows it wrote (none for a release). Each row is
  `%{date, close, source}`.

  A plain struct rather than a schema: it is never stored as a row, only
  serialized into the append-only journal and matched by
  `Portfolixir.Derived.BlastRadius`, which answers it with the security's own
  radius.
  """

  @enforce_keys [:security_id, :quotes]
  defstruct [:security_id, :quotes]

  @type row :: %{date: Date.t(), close: Decimal.t(), source: String.t()}
  @type t :: %__MODULE__{security_id: integer(), quotes: [row()]}

  @doc "The image of `rows` (quote structs or maps) of one security, ascending by date."
  @spec new(integer(), [map()]) :: t()
  def new(security_id, rows) when is_integer(security_id) and is_list(rows) do
    quotes =
      rows
      |> Enum.map(&%{date: &1.date, close: &1.close, source: &1.source})
      |> Enum.sort_by(& &1.date, Date)

    %__MODULE__{security_id: security_id, quotes: quotes}
  end
end
