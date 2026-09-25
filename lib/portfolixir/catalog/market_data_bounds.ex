defmodule Portfolixir.Catalog.MarketDataBounds do
  @moduledoc """
  The plausibility bounds on a stored market-data point, a security's close
  or an exchange rate, defined once for every writer and every latest read
  (E25 S3, F26).

  A point is plausible when its value, as its column keeps it, is positive and
  fits the column, and its date is a bounded date
  (`Portfolixir.Input.BoundedDate`) no later than `latest_date/0`: the host's
  calendar day (`Portfolixir.Clock`) plus one day of zone slack, because a
  provider dates its points in UTC or in its own zone, which can already be
  tomorrow where the instance runs.

  "As its column keeps it" is the S3/S4 review round's correction: the
  database rounds a value to its column's scale (`close_column/0`,
  `rate_column/0`), so the value is rounded first (ADR-0016 §2) and the
  positive check judges what is stored. A positive value finer than the scale
  would otherwise pass and be stored as zero, a zero close priced and a zero
  rate divided by.

  Three places apply the same rule, so a point the sync would refuse is also
  one no other writer can store and no read can serve:

    * the `Portfolixir.Catalog.Quote` and `Portfolixir.Fx.ExchangeRate`
      changesets (`validate/3`), so the API, the sync and every other writer
      refuse it;
    * the quote and rate sync writers and the adapters, which drop an
      implausible point (`plausible?/2`) instead of failing the whole batch;
    * the latest-quote and latest-rate reads, capped at `latest_date/0`, so a
      row stored before the bound existed never becomes the valuation price
      and never makes a stale quote look fresh.
  """

  import Ecto.Changeset

  alias Portfolixir.Clock
  alias Portfolixir.Input.BoundedDate
  alias Portfolixir.Input.BoundedDecimal

  @close_column {20, 6}
  @rate_column {30, 15}

  @doc "The `numeric(precision, scale)` of a stored close."
  @spec close_column() :: {pos_integer(), non_neg_integer()}
  def close_column, do: @close_column

  @doc "The `numeric(precision, scale)` of a stored exchange rate."
  @spec rate_column() :: {pos_integer(), non_neg_integer()}
  def rate_column, do: @rate_column

  @doc "The latest date a stored market-data point may carry."
  @spec latest_date() :: Date.t()
  def latest_date, do: Date.add(Clock.today(), 1)

  @doc """
  Whether a point with this date and value is plausible, for a value stored
  in a `numeric(precision, scale)` `column` (`close_column/0`,
  `rate_column/0`). The date is a `Date` or an ISO 8601 string, the value a
  number, a `Decimal` or a decimal string, as a provider row carries them
  before the changeset casts them; anything else, and anything unparseable,
  is not plausible.
  """
  @spec plausible?(term(), term(), {pos_integer(), non_neg_integer()}) :: boolean()
  def plausible?(%Date{} = date, value, column) do
    BoundedDate.within?(date) and Date.compare(date, latest_date()) != :gt and
      storable_positive?(value, column)
  end

  def plausible?(date, value, column) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> plausible?(parsed, value, column)
      {:error, _} -> false
    end
  end

  def plausible?(_date, _value, _column), do: false

  @doc """
  Adds the bounds to a changeset: `date_field` a bounded date
  (`Portfolixir.Input.BoundedDate`, E25 S4) no later than `latest_date/0`;
  `value_field` rounded to its `column`'s scale, within its precision
  (`Portfolixir.Input.BoundedDecimal.bound_to_column/3`) and then greater
  than zero.
  """
  @spec validate(Ecto.Changeset.t(), atom(), atom(), {pos_integer(), non_neg_integer()}) ::
          Ecto.Changeset.t()
  def validate(changeset, date_field, value_field, column) do
    latest = latest_date()

    changeset
    |> BoundedDate.validate([date_field])
    |> validate_change(date_field, fn ^date_field, date ->
      if Date.compare(date, latest) == :gt,
        do: [{date_field, "must not be later than #{Date.to_iso8601(latest)}"}],
        else: []
    end)
    |> BoundedDecimal.bound_to_column(value_field, column)
    |> validate_number(value_field, greater_than: 0)
  end

  # The value as its column keeps it, judged the way the changeset judges it.
  defp storable_positive?(value, {_precision, scale} = column) do
    case to_decimal(value) do
      {:ok, decimal} ->
        stored = BoundedDecimal.round_to_scale(decimal, scale)
        BoundedDecimal.fits_column?(stored, column) and Decimal.gt?(stored, 0)

      :error ->
        false
    end
  end

  # The conversions Ecto's `:decimal` cast applies to a provider's value.
  defp to_decimal(%Decimal{} = value),
    do: if(BoundedDecimal.finite?(value), do: {:ok, value}, else: :error)

  defp to_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  defp to_decimal(value) when is_float(value), do: {:ok, Decimal.from_float(value)}
  defp to_decimal(value) when is_binary(value), do: BoundedDecimal.parse(value)
  defp to_decimal(_value), do: :error
end
