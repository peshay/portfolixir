defmodule Portfolixir.Portfolios.QuotePlausibility do
  @moduledoc """
  The `implausible_quote` finding (#1101, Sprint 20 plan D-7): the **shell**
  half of `Portfolixir.Engines.QuotePlausibility`.

  For a set of securities it loads each buy, sell and priced inbound
  delivery together with the latest stored quote of its window (the
  booking's date and the `window_days/0` days before it), puts the booked
  price per unit in the security's currency, and hands both to the engine
  with the security's split events and each quote's storage basis.

  **In the security's currency.** A booking in the security's own currency
  is read at its booked price; one booked in another currency at its
  security-currency leg, `security_amount ÷ quantity` — the native price
  the ledger's cost basis reads (ADR-0033) — and without that leg it is not
  compared.

  **Overlap** (D-7): a security the two-scales guard
  (`Portfolixir.Portfolios.Bonds.two_scales_among/1`) names is left out,
  since `two_scales` names the cause more precisely; this finding is its
  general case.

  Who reads it: Wealth, over the positions its scope values, and the
  catalog-wide `implausible_quote` predicate over the held securities
  (`Portfolixir.Catalog.DataQuality`), which the Overview counts and the
  securities list and `GET /api/v1/securities?data_quality=` serve. It names
  and converts nothing.
  """

  import Ecto.Query

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.QuoteAdjustment
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Engines.QuotePlausibility, as: Engine
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Bonds
  alias Portfolixir.Repo

  # The bookings that state a price per unit the market set: a buy, a sell,
  # and since #779 a priced inbound delivery, which opens its lot at its
  # price as a buy does (the two-scales guard reads the same two inbound
  # kinds).
  @kinds ~w(buy sell inbound_delivery)

  @doc "The booking kinds the guard compares."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc """
  The findings among `security_ids`, sorted by name: each the engine's
  finding with the security's `security_id`, `name` and `currency_code`.
  """
  @spec findings([integer()]) :: [map()]
  def findings(security_ids) when is_list(security_ids) do
    Security
    |> where([s], s.id in ^Enum.uniq(security_ids))
    |> Repo.all()
    |> findings_among()
  end

  @doc "`findings/1` over securities a caller has already loaded."
  @spec findings_among([Security.t()]) :: [map()]
  def findings_among(securities) when is_list(securities) do
    securities = Enum.uniq_by(securities, & &1.id)
    ids = Enum.map(securities, & &1.id)
    bookings = bookings_by_security(ids)
    events = Quotes.split_events_by_security(ids)

    named =
      for security <- Enum.sort_by(securities, &{&1.name, &1.id}),
          finding =
            security
            |> engine_bookings(Map.get(bookings, security.id, []))
            |> Engine.finding(Map.get(events, security.id, [])),
          finding != nil do
        {security,
         Map.merge(finding, %{
           security_id: security.id,
           name: security.name,
           currency_code: security.currency_code
         })}
      end

    on_two_scales =
      named
      |> Enum.map(&elem(&1, 0))
      |> Bonds.two_scales_among()
      |> MapSet.new(& &1.security_id)

    for {security, finding} <- named, not MapSet.member?(on_two_scales, security.id), do: finding
  end

  # Each booking of the kinds above with a price above 0, and the latest
  # stored quote dated on it or within the window before it; a booking with
  # no quote there is not loaded, as it is not compared.
  defp bookings_by_security([]), do: %{}

  defp bookings_by_security(ids) do
    window = Engine.window_days()

    latest_in_window =
      from(q in SecurityQuote,
        where:
          q.security_id == parent_as(:booking).security_id and
            q.date <= parent_as(:booking).date and
            q.date >= date_add(parent_as(:booking).date, ^(-window), "day"),
        order_by: [desc: q.date],
        limit: 1,
        select: %{date: q.date, close: q.close, source: q.source}
      )

    from(t in Transaction,
      as: :booking,
      where: t.security_id in ^ids and t.type in ^@kinds and not is_nil(t.price) and t.price > 0,
      inner_lateral_join: q in subquery(latest_in_window),
      on: true,
      order_by: [asc: t.date, asc: t.id],
      select: %{
        security_id: t.security_id,
        type: t.type,
        date: t.date,
        price: t.price,
        currency_code: t.currency_code,
        security_amount: t.security_amount,
        quantity: t.quantity,
        quote: q
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.security_id)
  end

  defp engine_bookings(%Security{} = security, rows) do
    for row <- rows do
      %{
        kind: row.type,
        date: row.date,
        price: unit_price(row, security.currency_code),
        quote: %{
          date: row.quote.date,
          close: row.quote.close,
          basis: QuoteAdjustment.basis(row.quote.source, security)
        }
      }
    end
  end

  # The price per unit in the security's currency (ADR-0033's native leg).
  defp unit_price(%{currency_code: currency} = row, currency), do: row.price
  defp unit_price(row, nil), do: row.price

  defp unit_price(%{security_amount: %Decimal{} = amount, quantity: %Decimal{} = quantity}, _) do
    if Decimal.compare(quantity, 0) == :gt, do: Decimal.div(amount, quantity)
  end

  defp unit_price(_row, _currency), do: nil

  @doc """
  The finding's computation basis, as the payload carries it (the
  `AGENTS.md` metric rule; D-7): the input series, the reference, the
  window, the gaps and the threshold, and what it assumes.
  """
  @spec computation_basis() :: map()
  def computation_basis do
    window = Engine.window_days()
    k = Engine.threshold()

    %{
      input_series:
        "the stored quotes of each security, each read on its booking's own split basis " <>
          "(ADR-0028 §2): a provider's back-adjusted close is multiplied back by the splits " <>
          "recorded after its date, and divided by those effective up to the booking's date",
      reference:
        "each booking's price per unit — a buy, a sell or a priced inbound delivery — in the " <>
          "security's currency: the booked price, or for a booking in another currency its " <>
          "security_amount ÷ quantity; a booking at a price of 0 has no ratio and is skipped",
      window:
        "the quote on the booking date, or the latest within #{window} days before the " <>
          "booking date",
      gaps:
        "a booking with no quote in the window is not compared, nor one with no price in the " <>
          "security's currency; a security with no compared booking is not named",
      threshold:
        "#{k}: a security is named when close ÷ price is below 1/#{k} or above #{k} for at " <>
          "least one booking, both ends of the band included; the finding shows the latest " <>
          "such booking, its quote and close on the booking's basis, ratio rounded half up " <>
          "at scale 6, and bookings_outside counts them",
      assumptions:
        "a security the two-scales guard names (data_quality two_scales) is not counted " <>
          "again; held means a non-zero quantity summed across every depot of every " <>
          "portfolio; nothing is converted or stored"
    }
  end
end
