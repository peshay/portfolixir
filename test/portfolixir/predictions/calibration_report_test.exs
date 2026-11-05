defmodule Portfolixir.Predictions.CalibrationReportTest do
  # ADR-0055 §4 (Sprint 25 plan, Lane F, F3): the calibration report read.
  # Predictions.calibration_report/2 loads the predictions its filters name,
  # resolves each at read (F2) and scores them (the engine,
  # calibration_test.exs, carries the hand-summed 48-call fixture). Here a
  # small fixture runs the whole path from stored closes to the scores, with
  # each figure worked out by hand.
  #
  # Every call is made on 2026-03-04 (the test clock seam of
  # create_prediction/3), so its start close stands for 2026-03-03; the
  # report reads with today: 2026-11-05.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Predictions

  @made_at ~U[2026-03-04 15:00:00.000000Z]
  @today ~D[2026-11-05]

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp predict!(actor, security, direction, probability, resolves_on, model) do
    attrs =
      %{
        "security_id" => security.id,
        "direction" => direction,
        "probability" => probability,
        "benchmark" => "rate:0",
        "resolves_on" => resolves_on
      }
      |> then(&if(model, do: Map.put(&1, "model", model), else: &1))

    {:ok, prediction} = Predictions.create_prediction(actor, attrs, now: @made_at)
    prediction
  end

  setup do
    agent = Actor.api_token_rw("research-agent")
    operator = Actor.owner_ui()

    # 100 -> 110 by 06-01 and still 110 on 09-01: +0.1 against rate:0, so
    # an outperform call hits and an underperform call misses.
    rising = create_security!(name: "Rising Co.", ticker: nil, currency: "EUR")

    put_quotes!(rising, [
      {~D[2026-03-03], "100"},
      {~D[2026-06-01], "110"},
      {~D[2026-09-01], "110"}
    ])

    unpriced = create_security!(name: "Unpriced Co.", ticker: nil, currency: "EUR")

    predict!(agent, rising, "outperform", "0.60", "2026-06-01", "model-a")
    predict!(agent, rising, "underperform", "0.80", "2026-06-01", "model-a")
    predict!(agent, rising, "outperform", "0.60", "2026-09-01", "model-a")
    predict!(operator, rising, "outperform", "0.70", "2026-06-01", nil)
    predict!(agent, unpriced, "outperform", "0.55", "2026-06-01", "model-b")
    predict!(operator, rising, "outperform", "0.90", "2026-12-01", nil)

    :ok
  end

  defp report(filters \\ []), do: Predictions.calibration_report(filters, today: @today)

  # User story (F3, ADR-0055 §4):
  # As the operator's agent asking how its calls have scored,
  # I want the report over the stored calls, each resolved at read,
  # so that the score follows the closes as they stand today.
  #
  # Acceptance criteria:
  # - Every stored call is counted: open, resolved, unresolved by reason.
  # - The headline, the bands and the groups score the resolved ones.
  test "the report over every stored call, resolved at read" do
    report = report()

    assert report.counts == %{
             total: 6,
             open: 1,
             resolved: 4,
             unresolved: %{
               no_start_close: 1,
               no_end_close: 0,
               no_benchmark_close: 0,
               no_fx_rate: 0
             }
           }

    # Resolved: 0.60 hit (e 0.16), 0.80 underperform miss (0.64), 0.60 hit
    # (0.16, the 09-01 call), 0.70 hit (0.09). n = 4.
    # S1 = 1.05: Brier 1.05 / 4 = 0.2625.
    # S2 = 0.0256 + 0.4096 + 0.0256 + 0.0081 = 0.4689;
    # n S2 - S1^2 = 1.8756 - 1.1025 = 0.7731; n^2 (n - 1) = 48;
    # 0.7731 / 48 = 0.01610625; sqrt = 0.1269104014649705534529135418210966.
    assert_decimal(report.brier.score, "0.2625")

    assert Decimal.to_string(report.brier.standard_error) ==
             "0.1269104014649705534529135418210966"

    assert_decimal(report.brier.reference, "0.25")

    # Sharpness (0.10 + 0.30 + 0.10 + 0.20) / 4 = 0.175; mean p 0.675.
    # Hits 3 of 4: 0.75; standard error sqrt(3 x 1 / 48) = sqrt(1 / 16) = 0.25.
    assert_decimal(report.sharpness, "0.175")
    assert_decimal(report.hit_rate.mean_probability, "0.675")
    assert report.hit_rate.hits == 3
    assert_decimal(report.hit_rate.rate, "0.75")
    assert_decimal(report.hit_rate.standard_error, "0.25")

    assert Enum.map(report.bands, & &1.count) == [0, 2, 1, 1, 0]
    assert Enum.all?(report.bands, &(&1.hit_rate == :too_few))

    assert Enum.map(report.groups.author, &{&1.author, &1.counts.resolved}) ==
             [agent: 3, operator: 1]

    assert Enum.map(report.groups.model, &{&1.model, &1.counts.total}) ==
             [{"model-a", 3}, {"model-b", 1}, {nil, 2}]
  end

  # User story (F3, ADR-0055 §4 "filtered by author, model and a
  # resolves_on range"):
  # As the operator comparing the agent's calls with mine,
  # I want the report narrowed to an author, a model or the calls due in a
  # range,
  # so that each reads on its own sample.
  #
  # Acceptance criteria:
  # - author, model, resolves_from and resolves_to (inclusive) narrow every
  #   count and score; an unknown author matches nothing and mints no atom.
  # - Any other filter is refused by name.
  test "filtered by author, model and a resolves_on range" do
    operator = report(author: :operator)
    assert %{total: 2, open: 1, resolved: 1} = operator.counts
    # One 0.70 hit: e = 0.09.
    assert_decimal(operator.brier.score, "0.09")
    assert operator.brier.standard_error_reason == :one_resolved

    # model-a's three: e 0.16, 0.64, 0.16; S1 = 0.96; Brier 0.32.
    model_a = report(author: "agent", model: "model-a")
    assert %{total: 3, open: 0, resolved: 3} = model_a.counts
    assert_decimal(model_a.brier.score, "0.32")

    # Due on 06-01 only: the 09-01 and the 12-01 calls fall outside.
    # e 0.16, 0.64, 0.09; S1 = 0.89; Brier 0.89 / 3.
    june = report(resolves_from: ~D[2026-06-01], resolves_to: ~D[2026-06-01])
    assert %{total: 4, open: 0, resolved: 3} = june.counts
    assert june.counts.unresolved.no_start_close == 1
    assert Decimal.to_string(june.brier.score) == "0.2966666666666666666666666666666667"

    nobody = report(author: "nobody_author_zz")
    assert nobody.counts.total == 0
    assert nobody.brier.score == nil
    assert_raise ArgumentError, fn -> String.to_existing_atom("nobody_author_zz") end

    assert_raise ArgumentError, ~r/calibration filter :security_id/, fn ->
      report(security_id: 1)
    end
  end

  # User story (F3, ADR-0055 §4 "computation_basis"; the brief addendum,
  # "Every metric documents its computation basis"):
  # As the agent that must be able to check a score,
  # I want the report to state its basis — the resolution rule, the
  # formulas, the minimum band count, that unresolved calls are excluded
  # and counted, and that no distribution is counted —
  # so that nobody has to guess how a figure was made.
  test "the report states its computation basis" do
    basis = report().computation_basis

    assert basis.minimum_band_count == 20
    assert basis.staleness_days == 7
    assert_decimal(basis.reference, "0.25")

    for key <- [
          :resolution,
          :start_close,
          :end_close,
          :currency,
          :benchmark,
          :outcome,
          :distributions,
          :brier_score,
          :brier_standard_error,
          :sharpness,
          :hit_rate,
          :hit_rate_standard_error,
          :bands,
          :excluded,
          :small_samples,
          :groups,
          :precision
        ] do
      assert is_binary(Map.fetch!(basis, key)) and basis[key] != "", "basis.#{key}"
    end

    assert basis.start_close =~ "strictly before"
    assert basis.outcome =~ "excess = 0"
    assert basis.distributions =~ "not counted"
    assert basis.excluded =~ "unresolved"
    assert basis.bands =~ "too_few"
    assert basis.precision =~ "Decimal.sqrt"
  end
end
