defmodule Portfolixir.Catalog.MarketDataBounds do
  @moduledoc """
  The plausibility bounds on a stored market-data point, a security's close
  or an exchange rate, defined once for every writer and every latest read
  (E25 S3, F26).

  A point is plausible when its value is positive and its date is a bounded
  date (`Portfolixir.Input.BoundedDate`) no later than `latest_date/0`: the host's calendar day (`Portfolixir.Clock`) plus
  one day of zone slack, because a provider dates its points in UTC or in its
  own zone, which can already be tomorrow where the instance runs.

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

  @doc "The latest date a stored market-data point may carry."
  @spec latest_date() :: Date.t()
  def latest_date, do: Date.add(Clock.today(), 1)

  @doc """
  Whether a point with this date and value is plausible. The date is a `Date`
  or an ISO 8601 string, the value a number, a `Decimal` or a decimal string,
  as a provider row carries them before the changeset casts them; anything
  else, and anything unparseable, is not plausible.
  """
  @spec plausible?(term(), term()) :: boolean()
  def plausible?(%Date{} = date, value) do
    BoundedDate.within?(date) and Date.compare(date, latest_date()) != :gt and positive?(value)
  end

  def plausible?(date, value) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> plausible?(parsed, value)
      {:error, _} -> false
    end
  end

  def plausible?(_date, _value), do: false

  @doc """
  Adds the bounds to a changeset: `date_field` a bounded date
  (`Portfolixir.Input.BoundedDate`, E25 S4) no later than `latest_date/0`,
  `value_field` greater than zero.
  """
  @spec validate(Ecto.Changeset.t(), atom(), atom()) :: Ecto.Changeset.t()
  def validate(changeset, date_field, value_field) do
    latest = latest_date()

    changeset
    |> BoundedDate.validate([date_field])
    |> validate_change(date_field, fn ^date_field, date ->
      if Date.compare(date, latest) == :gt,
        do: [{date_field, "must not be later than #{Date.to_iso8601(latest)}"}],
        else: []
    end)
    |> validate_number(value_field, greater_than: 0)
  end

  defp positive?(%Decimal{} = value),
    do: not Decimal.nan?(value) and not Decimal.inf?(value) and Decimal.gt?(value, 0)

  defp positive?(value) when is_number(value), do: value > 0

  defp positive?(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> positive?(decimal)
      _ -> false
    end
  end

  defp positive?(_value), do: false
end
