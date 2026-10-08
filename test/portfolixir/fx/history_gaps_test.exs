defmodule Portfolixir.Fx.HistoryGapsTest do
  # #1120 (Sprint 20 PR α, A4; the plan's D-5). The one-shot history
  # backfill runs by itself, once, when needed: when a booking or a cash
  # account in a non-EUR currency predates that currency's earliest stored
  # rate. This module pins that condition, and the guard that keeps it from
  # firing again for a currency a completed run already sought (a currency
  # the ECB does not publish, a booking before 1999). Invented names,
  # figures and dates only.
  #
  # async: false -- the guard's record is one settings row, which another
  # async module's uncommitted write would make this one wait for.
  use Portfolixir.DataCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, cross_trade!: 3, deposit!: 4]

  alias Portfolixir.Fx
  alias Portfolixir.Fx.HistoryGaps

  # The rows' days are this module's own: rates are unique per (base,
  # quote, date), and another async module storing the same day would make
  # this one wait on its uncommitted row (#1018).
  defp rate!(quote_currency, date, rate) do
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: quote_currency,
          date: date,
          rate: rate,
          source: "ecb"
        }
      ])
  end

  # User story (#1120, D-5):
  # As an operator who imported years of history in a foreign currency,
  # I want the instance to know which currency's stored rates do not reach
  # back to its first booking, and from which day,
  # so that the historical rates can be fetched by themselves, only when a
  # booking needs them.
  #
  # Acceptance criteria:
  # - A booking in a non-EUR currency dated before that currency's earliest
  #   stored rate names the currency with its earliest booking date.
  # - A booking on or after the earliest stored rate names nothing.
  # - EUR is never named: it is the hub and needs no rate.
  # - A currency with no stored rate at all is named.
  # - The currency of the cash account a booking settles through counts
  #   even when the booking is priced in another currency (a cross-currency
  #   trade, ADR-0015), and so does the portfolio's base currency; a GBX
  #   price is read as GBP, the stored currency it derives from.
  describe "open/0, the condition" do
    test "a USD booking before USD's earliest stored rate names USD with its earliest date" do
      world = base_world(cash_currency: "USD", cash_name: "Broker USD")
      deposit!(world, "500", ~D[2021-03-15], currency: "USD")
      deposit!(world, "700", ~D[2021-06-01], currency: "USD")
      rate!("USD", ~D[2021-05-17], "1.25")

      assert HistoryGaps.open() == %{"USD" => ~D[2021-03-15]}
    end

    test "a booking on or after the earliest stored rate names nothing" do
      world = base_world(cash_currency: "USD", cash_name: "Broker USD")
      rate!("USD", ~D[2021-05-17], "1.25")
      deposit!(world, "500", ~D[2021-05-17], currency: "USD")
      deposit!(world, "700", ~D[2021-06-01], currency: "USD")

      assert HistoryGaps.open() == %{}
    end

    test "EUR is never named, with or without a stored rate" do
      world = base_world(cash_name: "Giro")
      deposit!(world, "500", ~D[2021-03-15], currency: "EUR")

      assert HistoryGaps.open() == %{}

      rate!("USD", ~D[2021-05-17], "1.25")
      assert HistoryGaps.open() == %{}
    end

    test "a currency with no stored rate at all is named" do
      world = base_world(cash_currency: "TWD", cash_name: "Konto TWD")
      deposit!(world, "9000", ~D[2021-04-01], currency: "TWD")
      rate!("USD", ~D[2021-01-04], "1.25")

      assert HistoryGaps.open() == %{"TWD" => ~D[2021-04-01]}
    end

    test "the settling account's currency, the base currency and GBX as GBP count" do
      # A EUR-priced fund bought through a CHF account: the booking's own
      # currency is EUR, its cash leg is in francs.
      franc = base_world(name: "Franken", cash_currency: "CHF", cash_name: "Konto CHF")
      fund = create_security!(name: "Examplia Fonds", ticker: "EXFD", currency: "EUR")

      cross_trade!(franc, fund,
        quantity: "10",
        price: "100",
        settled: "1250",
        gross: "1250",
        date: ~D[2021-02-08]
      )

      # A GBX-priced share bought through a EUR account.
      pound = base_world(name: "Pfund", cash_name: "Giro")
      share = create_security!(name: "Examplia plc", ticker: "EXPL", currency: "GBX")

      cross_trade!(pound, share,
        quantity: "100",
        price: "250",
        settled: "300",
        gross: "300",
        date: ~D[2021-02-09]
      )

      # A portfolio in dollars holding euros.
      dollar = base_world(name: "Dollar", currency: "USD", cash_currency: "EUR")
      deposit!(dollar, "100", ~D[2021-02-10], currency: "EUR")

      rate!("CHF", ~D[2021-05-17], "0.8")
      rate!("GBP", ~D[2021-05-17], "0.8")
      rate!("USD", ~D[2021-05-17], "1.25")

      assert HistoryGaps.open() == %{
               "CHF" => ~D[2021-02-08],
               "GBP" => ~D[2021-02-09],
               "USD" => ~D[2021-02-10]
             }
    end
  end

  # User story (#1120, D-5, "once"):
  # As an operator whose history holds a currency the ECB does not publish,
  # or a booking before 1999,
  # I want a completed backfill to settle that currency for good,
  # so that the instance does not fetch the whole series again on every
  # start and every import for a gap no fetch can close.
  #
  # Acceptance criteria:
  # - due/0 is open/0 less the currencies a completed run already sought.
  # - A sought currency stays open: the gap is still there, and still named
  #   by the walk; it is only no longer due.
  # - A currency not yet sought is due beside a sought one.
  # - Recording is cumulative and idempotent.
  describe "due/0, the guard" do
    test "a currency a completed run already sought is open but no longer due" do
      world = base_world(cash_currency: "TWD", cash_name: "Konto TWD")
      deposit!(world, "9000", ~D[2021-04-01], currency: "TWD")

      assert HistoryGaps.due() == %{"TWD" => ~D[2021-04-01]}

      assert :ok = HistoryGaps.record_sought(["TWD"])

      assert HistoryGaps.open() == %{"TWD" => ~D[2021-04-01]}
      assert HistoryGaps.due() == %{}

      dollar = base_world(name: "Dollar", cash_currency: "USD", cash_name: "Broker USD")
      deposit!(dollar, "500", ~D[2021-03-15], currency: "USD")

      assert HistoryGaps.due() == %{"USD" => ~D[2021-03-15]}

      assert :ok = HistoryGaps.record_sought(["USD"])
      assert :ok = HistoryGaps.record_sought(["USD"])

      assert HistoryGaps.sought() == ["TWD", "USD"]
      assert HistoryGaps.due() == %{}
    end
  end
end
