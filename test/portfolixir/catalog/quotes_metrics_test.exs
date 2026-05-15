defmodule Portfolixir.Catalog.QuotesMetricsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.SecurityWithMetrics

  # User story:
  # As a local portfolio maintainer,
  # I want the securities list to surface last price, day-change and 1M/1Y
  # performance derived from quote history,
  # so that the table matches the columns Portfolio Performance shows.
  #
  # Acceptance criteria:
  # - `Quotes.attach_metrics/1` decorates each security with `:metrics`
  #   containing latest_price, latest_price_date, day_change_abs / _pct,
  #   performance_1m and performance_1y.
  # - Securities without quote history get a `%SecurityWithMetrics{}` whose
  #   metric fields are all nil.
  # - Computation handles gaps: 1M/1Y baselines fall back to the closest
  #   prior available date (PP behaviour).

  defp security_fixture(name, currency \\ "USD") do
    {:ok, sec} = Catalog.create_security(%{name: name, currency_code: currency})
    sec
  end

  defp insert_quote(security, date, close) do
    %SecurityQuote{}
    |> SecurityQuote.changeset(%{
      security_id: security.id,
      date: date,
      close: close,
      source: "manual"
    })
    |> Repo.insert!()
  end

  test "attaches latest price, date and day-change for two recent quotes" do
    sec = security_fixture("Apple")
    insert_quote(sec, ~D[2026-05-14], "120.00")
    insert_quote(sec, ~D[2026-05-15], "126.00")

    [%SecurityWithMetrics{} = wrapped] = Quotes.attach_metrics([sec])

    assert wrapped.security.id == sec.id
    assert wrapped.metrics.latest_price_date == ~D[2026-05-15]
    assert Decimal.equal?(wrapped.metrics.latest_price, Decimal.new("126.00"))
    assert Decimal.equal?(wrapped.metrics.day_change_abs, Decimal.new("6.00"))
    assert Decimal.equal?(Decimal.round(wrapped.metrics.day_change_pct, 4), Decimal.new("0.0500"))
  end

  test "computes 1M and 1Y performance with closest-prior-date fallback" do
    sec = security_fixture("Test")
    today = Date.utc_today()
    # 1Y baseline (use a date that lies before today - 365 days to test fallback)
    insert_quote(sec, Date.add(today, -400), "50.00")
    # 1M baseline (use a date before today - 30 days to test fallback)
    insert_quote(sec, Date.add(today, -45), "90.00")
    insert_quote(sec, today, "99.00")

    [wrapped] = Quotes.attach_metrics([sec])

    # 1M: (99 - 90) / 90 = 0.1
    assert Decimal.equal?(Decimal.round(wrapped.metrics.performance_1m, 4), Decimal.new("0.1000"))
    # 1Y: (99 - 50) / 50 = 0.98
    assert Decimal.equal?(Decimal.round(wrapped.metrics.performance_1y, 4), Decimal.new("0.9800"))
  end

  test "returns nil metrics for securities with no quotes" do
    sec = security_fixture("Empty")
    [wrapped] = Quotes.attach_metrics([sec])

    assert wrapped.metrics.latest_price == nil
    assert wrapped.metrics.latest_price_date == nil
    assert wrapped.metrics.day_change_abs == nil
    assert wrapped.metrics.day_change_pct == nil
    assert wrapped.metrics.performance_1m == nil
    assert wrapped.metrics.performance_1y == nil
  end

  test "preserves input order" do
    a = security_fixture("Aaa")
    b = security_fixture("Bbb")
    c = security_fixture("Ccc")

    assert [%{security: %{id: id_a}}, %{security: %{id: id_b}}, %{security: %{id: id_c}}] =
             Quotes.attach_metrics([a, b, c])

    assert {id_a, id_b, id_c} == {a.id, b.id, c.id}
  end
end
