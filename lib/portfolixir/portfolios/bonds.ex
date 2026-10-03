defmodule Portfolixir.Portfolios.Bonds do
  @moduledoc """
  The bond reading of
  [ADR-0052](../../docs/decisions/0052-bond-master-data-in-dedicated-columns.md)
  (#330): the **shell** half of `Portfolixir.Engines.BondMetrics`.

  For a security whose effective asset class is `bond` or `government_bond`
  it loads what the engine needs — the master data, the units held, the
  price the valuation uses and the booked buys — and wraps every figure in
  its computation basis, as the `AGENTS.md` metric rule requires in the
  payload. Any other security has no reading, whatever master data it
  carries. Nothing is stored; the reading is computed when it is read.

  The price is `Portfolixir.Portfolios.Valuation.security_status/3`'s: the
  latest stored quote, or the last own trade price while there is none — so
  the yields and the value beside them on the Overview use one price.

  `two_scales_findings/1` is the guard over a set of securities, for the
  place a total is read (Wealth → Holdings → data quality).
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Engines.BondMetrics
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Valuation
  alias Portfolixir.Repo

  @classes ~w(bond government_bond)

  @hundredth "one unit of the holding is a hundredth of the face amount (the convention a " <>
               "Portfolio Performance export books a percent-quoted bond in), so a quote is " <>
               "both percent of face and the price per unit"

  @doc "The asset classes a reading is computed for."
  @spec classes() :: [String.t()]
  def classes, do: @classes

  @doc "Whether `security`'s effective asset class is one of the two bond classes."
  @spec bond?(term()) :: boolean()
  def bond?(%Security{} = security), do: Security.effective_asset_class(security) in @classes
  def bond?(_other), do: false

  @doc """
  The reading of one bond, or `nil` for any other security.

  Options: `:as_of` (default `Portfolixir.Clock.today/0`), and the inputs a
  caller already holds, so it does not load them twice — `:transactions`
  (`Ledger.list_transactions_for_security/1`) and `:status`
  (`Valuation.security_status/3`).
  """
  @spec reading(Security.t(), keyword()) :: map() | nil
  def reading(%Security{} = security, opts \\ []) do
    if bond?(security), do: build(security, opts)
  end

  defp build(%Security{} = security, opts) do
    as_of = Keyword.get_lazy(opts, :as_of, &Clock.today/0)

    transactions =
      Keyword.get_lazy(opts, :transactions, fn ->
        Ledger.list_transactions_for_security(security.id)
      end)

    status = Keyword.get_lazy(opts, :status, fn -> Valuation.security_status(security.id) end)

    quantity = held_quantity(transactions)
    price = %{value: status.latest_price, date: status.price_date, source: status.price_source}
    terms = %{coupon_rate: security.coupon_rate, maturity_date: security.maturity_date}
    metrics = BondMetrics.compute(terms, price, quantity, as_of)
    currency = face_currency(security)

    %{
      as_of: as_of,
      quantity: quantity,
      nominal_held: %{
        amount: metrics.nominal_held,
        currency_code: currency,
        computation_basis: nominal_basis(currency)
      },
      remaining_term: Map.put(metrics.remaining_term, :computation_basis, term_basis(as_of)),
      current_yield: Map.put(metrics.current_yield, :computation_basis, current_yield_basis()),
      yield_to_maturity:
        Map.put(metrics.yield_to_maturity, :computation_basis, yield_to_maturity_basis(as_of)),
      two_scales: two_scales(latest_quote(status), buys(transactions))
    }
  end

  @doc """
  The bonds among `security_ids` that are priced on two scales, sorted by
  name, each the engine's finding with its `security_id` and `name`.
  """
  @spec two_scales_findings([integer()]) :: [map()]
  def two_scales_findings(security_ids) when is_list(security_ids) do
    bonds =
      Security
      |> where([s], s.id in ^Enum.uniq(security_ids))
      |> Repo.all()
      |> Enum.filter(&bond?/1)

    ids = Enum.map(bonds, & &1.id)
    quotes = Quotes.latest_by_security_ids(ids)
    buys = buys_by_security(ids)

    for security <- Enum.sort_by(bonds, &{&1.name, &1.id}),
        finding = two_scales(quote_point(quotes[security.id]), Map.get(buys, security.id, [])),
        finding != nil do
      Map.merge(finding, %{security_id: security.id, name: security.name})
    end
  end

  defp two_scales(latest_quote, buys) do
    case BondMetrics.two_scales(latest_quote, buys) do
      nil -> nil
      finding -> Map.put(finding, :rule, two_scales_rule())
    end
  end

  defp two_scales_rule do
    {low, high} = BondMetrics.two_scales_band()

    "named when the latest stored quote is between #{low} and #{high} times a booked buy " <>
      "price per unit (both included): quotes near 100 beside bookings near 1 mean the " <>
      "export booked the nominal as the quantity, so value, gain and weight are a hundred " <>
      "times too high while the TTWROR shows nothing; the figures are shown as stored, " <>
      "nothing is converted"
  end

  defp held_quantity(transactions) do
    transactions
    |> Positions.calculate()
    |> Map.values()
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
  end

  defp buys(transactions) do
    for %Transaction{type: "buy", price: %Decimal{} = price, date: date} <- transactions,
        do: %{price: price, date: date}
  end

  defp buys_by_security([]), do: %{}

  defp buys_by_security(ids) do
    Transaction
    |> where([t], t.security_id in ^ids and t.type == "buy" and not is_nil(t.price))
    |> select([t], {t.security_id, %{price: t.price, date: t.date}})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp latest_quote(%{price_source: :quote, latest_price: %Decimal{} = close, price_date: date}),
    do: %{close: close, date: date}

  defp latest_quote(_status), do: nil

  defp quote_point(%{close: %Decimal{} = close, date: date}), do: %{close: close, date: date}
  defp quote_point(_none), do: nil

  defp face_currency(%Security{face_value_currency_code: code}) when is_binary(code), do: code
  defp face_currency(%Security{currency_code: code}), do: code

  # -- the computation basis of each figure (AGENTS.md metric rule) ----------

  defp nominal_basis(currency) do
    %{
      input_series:
        "the units held in every depot of every portfolio, summed from the security's bookings",
      window: "the holding on the read day (as_of)",
      reference: "the face value's currency, #{currency} (the security's while none is set)",
      gaps: "no holding is a nominal of 0; nothing is estimated",
      assumptions:
        "#{@hundredth}; the nominal is therefore quantity × 100, and the denomination " <>
          "(face_value) does not enter it"
    }
  end

  defp term_basis(as_of) do
    %{
      input_series: "the security's maturity_date and the read day",
      window: "from #{Date.to_iso8601(as_of)} (as_of) to the maturity_date",
      reference: "none: a span of calendar days, not a comparison",
      gaps:
        "without a maturity_date the term is null with insufficient_data and missing " <>
          "naming it; on and after the maturity date it is matured",
      assumptions:
        "calendar days, years = days ÷ #{BondMetrics.days_per_year()} rounded half up at " <>
          "scale 6; whole_years and whole_months count a month once its day of the month is " <>
          "reached; reported, not evaluated"
    }
  end

  defp current_yield_basis do
    %{
      input_series:
        "the coupon_rate (percent of face per year) and the price the valuation uses: the " <>
          "latest stored quote, or the last own trade price while there is none " <>
          "(price.source says which, price.date when)",
      window: "the price on price.date; the coupon as stored",
      reference: "percent of face: #{@hundredth}",
      gaps:
        "without a coupon_rate or a price above 0 it is null with insufficient_data and " <>
          "missing naming the input; a matured bond has none (matured)",
      assumptions:
        "coupon_rate ÷ price, a ratio (0.025707 is 2.5707 %) rounded half up at scale 6; " <>
          "no accrued interest, fees or taxes; reported, not evaluated"
    }
  end

  defp yield_to_maturity_basis(as_of) do
    %{
      input_series:
        "the coupon_rate, the maturity_date and the price the valuation uses (as for " <>
          "current_yield)",
      window:
        "from #{Date.to_iso8601(as_of)} (as_of) to the maturity_date, the price on price.date",
      reference: "percent of face, redeemed at 100",
      gaps:
        "without a coupon_rate, a price above 0 or a maturity_date it is null with " <>
          "insufficient_data and missing naming each; a matured bond has none (matured)",
      assumptions:
        "the linear approximation (coupon + (100 − price) ÷ remaining years) ÷ price, the " <>
          "remaining years being calendar days ÷ #{BondMetrics.days_per_year()} at full " <>
          "precision; no compounding, no accrued interest, fees or taxes; a ratio rounded " <>
          "half up at scale 6; reported, not evaluated"
    }
  end
end
