defmodule Portfolixir.Fx.NonPositiveRateTest do
  # A release before 2026.10.1 judged a rate before the column rounded it,
  # so a positive rate finer than the column's 15 decimal places could be
  # stored as 0. Such a row, planted here past today's changeset (the
  # legacy-row idiom of test/portfolixir/catalog/provider_data_bounds_test.exs),
  # is no rate to any read: the excluded-and-named and missing-rate paths
  # apply, the row itself is left as it is, and the boot reports it.
  # Synthetic data only.
  use PortfolixirWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Fx.ExchangeRate
  alias Portfolixir.Fx.HistoryGaps
  alias Portfolixir.Fx.RateSync
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.ExternalFlows
  alias Portfolixir.Portfolios.Income
  alias Portfolixir.Repo
  alias Portfolixir.WorldFixtures

  # A positive rate finer than the column's 15 decimal places.
  @sub_scale "0.0000000000000001"

  setup do
    on_exit(fn -> RateSync.Fake.clear_response() end)
    :ok
  end

  # The rule every pre-2026.10.1 release applied to a rate: the cast value,
  # judged before the column rounds it.
  defp pre_2026_10_1_rule_accepts?(rate) do
    {%{}, %{rate: :decimal}}
    |> Ecto.Changeset.cast(%{rate: rate}, [:rate])
    |> Ecto.Changeset.validate_number(:rate, greater_than: 0)
    |> Map.fetch!(:valid?)
  end

  # Writes the sub-scale rate as that rule let it through, past today's
  # changeset, and proves the column keeps it as 0.
  defp plant_legacy_rate!(date) do
    assert pre_2026_10_1_rule_accepts?(@sub_scale)
    refute ExchangeRate.changeset(%ExchangeRate{}, rate_attrs(date, @sub_scale)).valid?

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    row =
      date
      |> rate_attrs(Decimal.new(@sub_scale))
      |> Map.merge(%{inserted_at: now, updated_at: now})

    {1, _} = Repo.insert_all(ExchangeRate, [row])

    stored = stored_rate!(date)
    assert Decimal.equal?(stored.rate, 0), "numeric(30,15) stores #{@sub_scale} as 0"
    stored
  end

  defp stored_rate!(date),
    do: Repo.get_by!(ExchangeRate, base_currency: "EUR", quote_currency: "USD", date: date)

  defp rate_attrs(date, rate),
    do: %{base_currency: "EUR", quote_currency: "USD", date: date, rate: rate, source: "ecb"}

  defp usd_world!, do: WorldFixtures.base_world(currency: "EUR", cash_currency: "USD")

  defp book!(world, type, amount, date) do
    {:ok, _tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "USD"
      })

    :ok
  end

  defp api(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  # The status a read answers, or the exception it raised (Phoenix.ConnTest
  # re-raises a controller's or a mount's exception in the test process).
  defp outcome(path, api? \\ true) do
    {result, _log} =
      with_log(fn ->
        try do
          conn = if api?, do: api(build_conn()), else: build_conn()
          get(conn, path).status
        rescue
          error in Plug.Conn.WrapperError -> {:raised, error.reason.__struct__}
          error -> {:raised, error.__struct__}
        end
      end)

    result
  end

  # The weekend day (a Saturday) at least two weeks back: a date the ECB
  # never publishes, so no history backfill ever rewrites a row on it.
  defp saturday_before(date) do
    Date.add(date, -rem(Date.day_of_week(date) - 6 + 7, 7))
  end

  # User story (security review 2026-10-12, K06):
  # As the operator of an instance upgraded from a release before 2026.10.1,
  # I want a stored rate of zero to count as no rate wherever a rate is
  # looked up,
  # so that the valuation reads answer instead of failing.
  #
  # Acceptance criteria:
  # - With the zero row as the latest rate, the portfolio valuation and the
  #   total valuation answer 200.
  test "a legacy zero rate as the latest rate: the valuation reads answer instead of raising" do
    world = usd_world!()
    day = Date.add(Clock.today(), -10)
    :ok = book!(world, "deposit", "100", day)
    plant_legacy_rate!(day)

    outcomes = %{
      portfolio_valuation: outcome("/api/v1/portfolios/#{world.portfolio.id}/valuation"),
      total_valuation: outcome("/api/v1/valuation")
    }

    assert outcomes == %{portfolio_valuation: 200, total_valuation: 200}
  end

  # User story (security review 2026-10-12, K06):
  # As the operator whose rate history holds such a row,
  # I want every read whose history crosses its date to answer,
  # so that one bad day never takes the Cash-flow page or the performance
  # family down for good.
  #
  # Acceptance criteria:
  # - After a plausible rate the next day, the external flows, the income,
  #   the performance and the /cashflow page answer 200.
  test "a newer plausible rate heals the latest read, and the history reads crossing the zero row answer" do
    world = usd_world!()
    pid = world.portfolio.id
    day = Date.add(Clock.today(), -10)
    :ok = book!(world, "deposit", "100", day)
    :ok = book!(world, "interest", "1", day)
    plant_legacy_rate!(day)

    assert {:ok, 1} = Fx.upsert_many([rate_attrs(Date.add(day, 1), "1.1")])

    assert outcome("/api/v1/portfolios/#{pid}/valuation") == 200

    outcomes = %{
      external_flows: outcome("/api/v1/external_flows"),
      income: outcome("/api/v1/portfolios/#{pid}/income"),
      performance: outcome("/api/v1/portfolios/#{pid}/performance"),
      cashflow_page: outcome("/cashflow", false)
    }

    assert outcomes == %{external_flows: 200, income: 200, performance: 200, cashflow_page: 200}
  end

  # User story (security review 2026-10-12, K06):
  # As the operator whose zero row sits on a day the provider never
  # publishes,
  # I want the reads to answer although no backfill can overwrite it,
  # so that the repair does not depend on a hand edit of the database.
  #
  # Acceptance criteria:
  # - After a backfill of the business days around it, the zero row is
  #   still stored, and the valuation and the performance answer 200.
  test "a zero row on a date the provider does not publish stays, and the reads answer" do
    world = usd_world!()
    pid = world.portfolio.id
    saturday = Clock.today() |> Date.add(-14) |> saturday_before()
    friday = Date.add(saturday, -1)
    monday = Date.add(saturday, 2)
    :ok = book!(world, "deposit", "100", friday)
    plant_legacy_rate!(saturday)

    RateSync.Fake.put_history_response(
      {:ok, [rate_attrs(friday, "1.1"), rate_attrs(monday, "1.1")]}
    )

    assert {:ok, %{status: :ok, upserted: 2}} = RateSync.backfill()
    assert Decimal.equal?(stored_rate!(saturday).rate, 0)

    outcomes = %{
      portfolio_valuation: outcome("/api/v1/portfolios/#{pid}/valuation"),
      performance: outcome("/api/v1/portfolios/#{pid}/performance")
    }

    assert outcomes == %{portfolio_valuation: 200, performance: 200}
  end

  # User story (security review 2026-10-12, K06):
  # As the agent reading a converted figure,
  # I want a zero rate to give the same answer as a missing one in every
  # lookup,
  # so that the excluded-and-named and missing-rate paths apply, and no
  # stored row is deleted or changed by a read.
  #
  # Acceptance criteria:
  # - convert/4 (on or before a date and latest), convert_on/4, hub_rates/1,
  #   latest/2, at_or_before/3 and series/2 treat the zero row as no rate.
  # - The income report excludes and names a payment on that day; the
  #   external flows exclude and name a deposit on it.
  # - The row is unchanged afterwards.
  test "every rate lookup treats a stored zero rate as no rate, and changes nothing" do
    world = usd_world!()
    day = Date.add(Clock.today(), -10)
    :ok = book!(world, "deposit", "100", day)
    :ok = book!(world, "interest", "1", day)
    planted = plant_legacy_rate!(day)
    one = Decimal.new("1")

    assert Fx.convert(one, "USD", "EUR", day) == {:error, :no_rate}
    assert Fx.convert(one, "EUR", "USD", day) == {:error, :no_rate}
    assert Fx.convert(one, "USD", "EUR") == {:error, :no_rate}
    assert Fx.convert_on(one, "USD", "EUR", day) == {:error, :no_rate}
    assert Fx.rate("USD", "EUR", day) == {:error, :no_rate}
    assert Fx.hub_rates(["USD", "EUR"]) == %{"EUR" => Decimal.new(1)}
    assert Fx.latest("EUR", "USD") == nil
    assert Fx.at_or_before("EUR", "USD", day) == nil
    assert Fx.hub_rate_before("USD", day) == nil
    assert Fx.series("USD", Date.add(day, -1)) == []

    income = Income.for_portfolio(world.portfolio.id)
    assert income.excluded.count == 1
    assert [%{currency_code: "USD"}] = income.excluded.currencies

    flows = ExternalFlows.report()
    assert flows.excluded.count == 1

    after_reads = stored_rate!(day)
    assert after_reads.id == planted.id
    assert Decimal.equal?(after_reads.rate, 0)
    assert after_reads.updated_at == planted.updated_at
  end

  # User story (security review 2026-10-12, K06):
  # As the operator of an upgraded instance,
  # I want the boot to report any stored rate that is not positive,
  # so that I know such a row exists, which no read uses, and can repair it.
  #
  # Acceptance criteria:
  # - report_non_positive_rates/0 logs one warning naming the count and
  #   each pair and date; it deletes and changes nothing and answers :ok.
  # - With no such row it logs nothing.
  test "the boot reports a stored non-positive rate and leaves it" do
    assert capture_log([level: :warning], fn -> assert Fx.report_non_positive_rates() == :ok end) ==
             ""

    day = Date.add(Clock.today(), -10)
    planted = plant_legacy_rate!(day)

    log =
      capture_log([level: :warning], fn -> assert Fx.report_non_positive_rates() == :ok end)

    assert log =~ "1 stored exchange rate is not positive"
    assert log =~ "EUR/USD on #{Date.to_iso8601(day)}"

    after_report = stored_rate!(day)
    assert after_report.id == planted.id
    assert Decimal.equal?(after_report.rate, 0)

    # The boot step runs the same report unless its config turns it off.
    previous = Application.fetch_env(:portfolixir, :report_non_positive_rates_on_boot)

    on_exit(fn ->
      case previous do
        {:ok, value} ->
          Application.put_env(:portfolixir, :report_non_positive_rates_on_boot, value)

        :error ->
          Application.delete_env(:portfolixir, :report_non_positive_rates_on_boot)
      end
    end)

    Application.put_env(:portfolixir, :report_non_positive_rates_on_boot, true)

    assert capture_log([level: :warning], fn ->
             assert Fx.report_non_positive_rates_on_boot() == :ok
           end) =~ "EUR/USD on #{Date.to_iso8601(day)}"

    Application.put_env(:portfolixir, :report_non_positive_rates_on_boot, false)

    assert capture_log([level: :warning], fn ->
             assert Fx.report_non_positive_rates_on_boot() == :ok
           end) == ""
  end

  # User story (security review 2026-10-12, K06):
  # As the operator whose earliest stored rate for a currency is such a row,
  # I want the history-gap read not to count it as coverage,
  # so that the automatic backfill fetches that currency's history while
  # every conversion treats the day as missing.
  #
  # Acceptance criteria:
  # - A currency whose only stored rate is 0 is open from its earliest
  #   booking date, and due for the backfill.
  test "a non-positive earliest rate does not count as history coverage" do
    world = usd_world!()
    day = Date.add(Clock.today(), -10)
    :ok = book!(world, "deposit", "100", day)
    plant_legacy_rate!(day)

    assert HistoryGaps.open() == %{"USD" => day}
    assert Map.has_key?(HistoryGaps.due(), "USD")
  end
end
