defmodule Portfolixir.Catalog.SecurityMetricsTest do
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.SecurityMetrics
  alias Portfolixir.Ledger.Splits

  @as_of ~D[2026-09-19]

  defp seed_series!(security_id, closes, last \\ @as_of) do
    first = Date.add(last, -(length(closes) - 1))

    rows =
      closes
      |> Enum.with_index()
      |> Enum.map(fn {close, index} ->
        %{date: Date.add(first, index), close: Decimal.new(close), source: "manual"}
      end)

    {:ok, _count} = Quotes.upsert_many(security_id, rows)
    :ok
  end

  defp assert_decimal(actual, expected) do
    assert Decimal.equal?(actual, Decimal.new(expected)),
           "expected #{expected}, got #{inspect(actual)}"
  end

  # User story (FR-39, ADR-0047 §1, §6, §9):
  # As the operator's agent researching one security,
  # I want its derived metrics over the API in one read, each naming the span
  # it was measured over,
  # so that I can describe the instrument without walking the quote history
  # myself.
  #
  # Acceptance criteria:
  # - The read answers the §3 metrics with a payload-level computation basis
  #   (input series, reference, gaps, assumptions) and a per-metric window.
  # - The figures are in the security's own currency and the basis says so
  #   (identity I7).
  test "reads the §3 metrics over the security's own close series and names the basis" do
    security = create_security!(name: "Metric Co", ticker: "MTC", currency: "USD")
    seed_series!(security.id, List.duplicate("100", 400))

    {:ok, payload} = SecurityMetrics.for_security(security.id, as_of: @as_of)

    assert payload.security_id == security.id
    assert payload.currency_code == "USD"
    assert payload.as_of == @as_of
    assert_decimal(payload.latest_close.close, "100")
    assert payload.latest_close.date == @as_of

    basis = payload.computation_basis
    assert basis.input_series =~ "USD"
    assert basis.input_series =~ "split-adjusted"
    assert basis.reference == nil
    assert basis.gaps =~ "no return observation"
    assert basis.assumptions =~ "252"

    assert_decimal(payload.metrics.sma_50.value, "100")
    assert_decimal(payload.metrics.volatility["30d"].value, "0")
    assert payload.metrics.momentum["12m"].observations == 2
    assert payload.metrics.distance_to_extremes.high.date
  end

  # User story (ADR-0047 §1, ADR-0028 §2):
  # As the operator whose security split during the window,
  # I want the metrics computed over the split-adjusted close series,
  # so that a split never reads as a crash.
  #
  # Acceptance criteria:
  # - A 2:1 split halving the stored closes leaves the drawdown at exactly 0
  #   and the volatility at exactly 0 — the series is continuous once adjusted.
  test "the metrics read the split-adjusted series, so a split is not a price move" do
    world = base_world(name: "Split World", cash_name: "SW Cash", depot_name: "SW Depot")
    security = create_security!(name: "Split Co", ticker: "SPC", asset_class: "equity")
    buy!(world, security, quantity: "10", price: "100", date: Date.add(@as_of, -60))

    effective = Date.add(@as_of, -20)

    {:ok, _txs} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: effective,
        ratio_numerator: 2,
        ratio_denominator: 1
      })

    # Stored raw closes: 100 before the split, 50 from the effective date on.
    seed_series!(
      security.id,
      List.duplicate("100", 20) ++ List.duplicate("50", 21),
      @as_of
    )

    {:ok, payload} = SecurityMetrics.for_security(security.id, as_of: @as_of)

    assert_decimal(payload.metrics.max_drawdown["30d"].value, "0")
    assert_decimal(payload.metrics.volatility["30d"].value, "0")
    assert_decimal(payload.latest_close.close, "50")
  end

  # Acceptance criteria (ADR-0047 §5, identity I5):
  # - A security with no stored quotes answers every metric as a refusal, with
  #   its observation count, rather than an error.
  test "a security with no quote history answers gap markers, not an error" do
    security = create_security!(name: "Empty Co", ticker: "EMP")

    {:ok, payload} = SecurityMetrics.for_security(security.id, as_of: @as_of)

    assert payload.latest_close == nil
    assert payload.metrics.sma_200.insufficient_data
    assert payload.metrics.sma_200.observations == 0
    assert payload.metrics.volatility["365d"].insufficient_data
  end

  # Acceptance criteria:
  # - An unknown security is `{:error, :not_found}`, never a crash.
  test "an unknown security is not found" do
    assert SecurityMetrics.for_security(-1, as_of: @as_of) == {:error, :not_found}
  end

  # Acceptance criteria (ADR-0047 §3):
  # - Closes dated after as_of are not read, so a frozen as_of gives a frozen
  #   answer.
  test "as_of bounds the series the metrics read" do
    security = create_security!(name: "Bound Co", ticker: "BND")
    seed_series!(security.id, List.duplicate("100", 30) ++ ["999"], @as_of)

    {:ok, payload} = SecurityMetrics.for_security(security.id, as_of: Date.add(@as_of, -1))

    assert payload.latest_close.date == Date.add(@as_of, -1)
    assert_decimal(payload.latest_close.close, "100")
  end
end
