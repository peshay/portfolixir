defmodule Portfolixir.Catalog.QuotesNonPositiveCloseTest do
  # #1473, ADR-0051's amendment of 2026-11-21, item 1: "One rule for every
  # price read in the app." The securities list's change tiles and a
  # security's price change read closes; a stored close of 0 or below is no
  # price there either. Figures (Python's decimal, getcontext().prec = 34):
  #   11 - 10 = 1;  11 / 10 - 1 = 0.1;  12 / 10 - 1 = 0.2
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures

  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Clock

  defp legacy_close!(security, date, close) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {1, _rows} =
      Repo.insert_all(SecurityQuote, [
        %{
          security_id: security.id,
          date: date,
          close: Decimal.new(close),
          source: "manual",
          inserted_at: now,
          updated_at: now
        }
      ])

    :ok
  end

  defp days_ago(n), do: Date.add(Clock.today(), -n)

  # User story (#1473):
  # As the operator scanning the securities list,
  # I want a legacy close of 0 skipped by the latest close, the day change
  # and the 1M and 1Y changes,
  # so that a feed's placeholder never reads as -100 %.
  #
  # Acceptance criteria:
  # - 10 forty days ago, 11 two days ago and a legacy 0 yesterday: the
  #   latest price is 11 of two days ago, the day change +1 (+10 %) against
  #   the 10, and the 1M change +10 %.
  # - A legacy 0 on the 1M baseline's day is no baseline: the 10 before it
  #   is.
  test "the change tiles skip a close of 0 or below" do
    fund = create_security!(name: "Tile Fund", ticker: nil)
    put_quotes!(fund, [{days_ago(40), "10"}, {days_ago(2), "11"}])
    legacy_close!(fund, days_ago(1), "0")
    legacy_close!(fund, days_ago(30), "-1")

    [%{metrics: metrics}] = Quotes.attach_metrics([fund])
    assert Decimal.equal?(metrics.latest_price, Decimal.new("11"))
    assert metrics.latest_price_date == days_ago(2)
    assert Decimal.equal?(metrics.day_change_abs, Decimal.new("1"))
    assert Decimal.equal?(metrics.day_change_pct, Decimal.new("0.1"))
    assert Decimal.equal?(metrics.performance_1m, Decimal.new("0.1"))
  end

  # Acceptance criteria:
  # - 10 forty days ago, a legacy 0 on the baseline's day thirty days ago,
  #   12 yesterday: the 30-day change is 12 / 10 - 1 = 0.2, never nil.
  test "a security's price change reads its baseline from a positive close" do
    fund = create_security!(name: "Change Fund", ticker: nil)
    put_quotes!(fund, [{days_ago(40), "10"}, {days_ago(1), "12"}])
    legacy_close!(fund, days_ago(30), "0")

    assert Decimal.equal?(Quotes.performance(fund.id, 30), Decimal.new("0.2"))
  end
end
