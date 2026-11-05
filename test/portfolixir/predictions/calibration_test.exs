defmodule Portfolixir.Predictions.CalibrationTest do
  # ADR-0055 §4 (Sprint 25 plan, Lane F, F3; risk tier: money math, here
  # the scores). The calibration report's engine: pure, over predictions
  # already resolved (F2), so every figure is pinned on an in-memory
  # fixture whose sums are worked out by hand below. Every figure is an
  # exact Decimal at Decimal's default context (34 significant digits,
  # half-up); a quotient that does not terminate is written out to its 34
  # digits, and each was checked against an independent decimal calculator
  # at the same precision.
  use ExUnit.Case, async: true

  alias Portfolixir.Predictions.Calibration
  alias Portfolixir.Predictions.Prediction
  alias Portfolixir.Predictions.Resolution

  defp d(value), do: Decimal.new(value)

  defp assert_decimal(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.equal?(actual, d(expected)), "expected #{expected}, got #{inspect(actual)}"
  end

  defp assert_digits(actual, expected) do
    assert %Decimal{} = actual
    assert Decimal.to_string(actual) == expected
  end

  # One entry as Predictions.list_with_resolution/2 answers it. `state` is
  # :hit, :miss, :open or an unresolved reason.
  defp entry(author, model, probability, state) do
    prediction = %Prediction{author: author, model: model, probability: d(probability)}

    resolution =
      case state do
        outcome when outcome in [:hit, :miss] ->
          %Resolution{status: :resolved, outcome: outcome, start_on: nil, end_on: nil}

        :open ->
          %Resolution{status: :open, start_on: nil, end_on: nil}

        reason ->
          %Resolution{status: :unresolved, reason: reason, start_on: nil, end_on: nil}
      end

    %{prediction: prediction, resolution: resolution}
  end

  defp times(n, author, model, probability, state),
    do: List.duplicate(entry(author, model, probability, state), n)

  # The fixture: 43 resolved predictions, 4 unresolved and 1 open.
  #
  #   agent, model-a:  13 x 0.60 hit, 7 x 0.60 miss, 1 x 0.69 hit;
  #                    1 x 0.80 no_end_close; 1 x 0.75 open
  #   operator:        12 x 0.70 hit, 6 x 0.70 miss, 1 x 0.79 miss,
  #                    1 x 0.50 hit; 1 x 0.65 no_fx_rate,
  #                    1 x 0.90 no_benchmark_close
  #   agent, model-b:  1 x 0.90 hit, 1 x 0.99 miss; 1 x 0.55 no_start_close
  #
  # So the band 0.60-0.69 holds 21 resolved (shown: at least 20) and the
  # band 0.70-0.79 holds 19 (too_few); the band 0.80-0.89 holds none,
  # because its one call is unresolved and excluded.
  defp fixture do
    times(13, :agent, "model-a", "0.60", :hit) ++
      times(7, :agent, "model-a", "0.60", :miss) ++
      times(1, :agent, "model-a", "0.69", :hit) ++
      times(1, :agent, "model-a", "0.80", :no_end_close) ++
      times(1, :agent, "model-a", "0.75", :open) ++
      times(12, :operator, nil, "0.70", :hit) ++
      times(6, :operator, nil, "0.70", :miss) ++
      times(1, :operator, nil, "0.79", :miss) ++
      times(1, :operator, nil, "0.50", :hit) ++
      times(1, :operator, nil, "0.65", :no_fx_rate) ++
      times(1, :operator, nil, "0.90", :no_benchmark_close) ++
      times(1, :agent, "model-b", "0.90", :hit) ++
      times(1, :agent, "model-b", "0.99", :miss) ++
      times(1, :agent, "model-b", "0.55", :no_start_close)
  end

  # User story (F3, ADR-0055 §4 "the headline"; D-10 condition 1):
  # As the operator weighing the agent's calls,
  # I want one score over every resolved call, with its uncertainty, beside
  # the score of saying 50 % to everything,
  # so that I read how much weight the calls deserve from the first
  # resolutions on.
  #
  # Acceptance criteria:
  # - Brier = mean((p - o)^2), o = 1 for a hit and 0 for a miss; its
  #   standard error the sample standard deviation of the squared errors
  #   over sqrt(n); the reference 0.25.
  # - Sharpness = mean(p - 0.50); the hit rate with its standard error (the
  #   sample standard deviation of the 0/1 outcomes over sqrt(n)) beside
  #   the mean stated probability.
  # - Open and unresolved calls are counted, unresolved by reason, and
  #   enter no score.
  test "the headline over every resolved prediction" do
    report = Calibration.report(fixture())

    assert report.counts == %{
             total: 48,
             open: 1,
             resolved: 43,
             unresolved: %{
               no_start_close: 1,
               no_end_close: 1,
               no_benchmark_close: 1,
               no_fx_rate: 1
             }
           }

    # Squared errors e = (p - o)^2, by hand:
    #   0.60 hit (0.40)^2 = 0.16 x 13 = 2.08     e^2 0.0256 x 13 = 0.3328
    #   0.60 miss 0.36 x 7           = 2.52      0.1296 x 7      = 0.9072
    #   0.69 hit (0.31)^2            = 0.0961    0.00923521
    #   0.70 hit 0.09 x 12           = 1.08      0.0081 x 12     = 0.0972
    #   0.70 miss 0.49 x 6           = 2.94      0.2401 x 6      = 1.4406
    #   0.79 miss                    = 0.6241    0.38950081
    #   0.50 hit                     = 0.25      0.0625
    #   0.90 hit                     = 0.01      0.0001
    #   0.99 miss                    = 0.9801    0.96059601
    #   n = 43; S1 = sum e = 10.5803; S2 = sum e^2 = 4.19973203.
    #
    # Brier = S1 / n = 10.5803 / 43 = 0.2460534883720930232558139534883721.
    # Its standard error s / sqrt(n), with s^2 = (n S2 - S1^2) / (n (n - 1)),
    # is sqrt((n S2 - S1^2) / (n^2 (n - 1))):
    #   n S2 = 180.58847729; S1^2 = 111.94274809; difference 68.64572920;
    #   n^2 (n - 1) = 1849 x 42 = 77658;
    #   68.64572920 / 77658 = 0.0008839595405495860310077519379844...
    #   sqrt = 0.02973128367005524316366463331071660.
    assert_digits(report.brier.score, "0.2460534883720930232558139534883721")
    assert_digits(report.brier.standard_error, "0.02973128367005524316366463331071660")
    assert report.brier.standard_error_reason == nil
    assert_decimal(report.brier.reference, "0.25")

    # Sum p = 20 x 0.60 + 0.69 + 18 x 0.70 + 0.79 + 0.50 + 0.90 + 0.99
    #       = 12 + 0.69 + 12.6 + 0.79 + 0.50 + 0.90 + 0.99 = 28.47.
    # Sharpness = sum (p - 0.50) / n = (28.47 - 21.5) / 43 = 6.97 / 43
    #           = 0.1620930232558139534883720930232558.
    # Mean stated probability = 28.47 / 43 = 0.6620930232558139534883720930232558.
    assert_digits(report.sharpness, "0.1620930232558139534883720930232558")
    assert_digits(report.hit_rate.mean_probability, "0.6620930232558139534883720930232558")

    # Hits h = 13 + 1 + 12 + 1 + 1 = 28; hit rate 28 / 43
    #   = 0.6511627906976744186046511627906977.
    # Its standard error, the same estimator over the 0/1 outcomes
    # (sum o = sum o^2 = h): sqrt((n h - h^2) / (n^2 (n - 1)))
    #   = sqrt(h (n - h) / (n^2 (n - 1))) = sqrt(28 x 15 / 77658)
    #   = sqrt(420 / 77658) = sqrt(10 / 1849) = sqrt(10) / 43
    #   = 0.07354134093414835655811380335890043.
    assert report.hit_rate.hits == 28
    assert_digits(report.hit_rate.rate, "0.6511627906976744186046511627906977")
    assert_digits(report.hit_rate.standard_error, "0.07354134093414835655811380335890043")
    assert report.hit_rate.standard_error_reason == nil
  end

  # User story (F3, ADR-0055 §4 "five bands"; D-10 condition 1):
  # As the operator reading calibration by stated probability,
  # I want a band's hit rate only once it holds 20 resolved calls,
  # so that two calls in a band are never read as a calibration.
  #
  # Acceptance criteria:
  # - Five bands, 0.50-0.59 to 0.90-0.99, each with its count and mean
  #   stated probability; 0.69 falls in 0.60-0.69, 0.79 in 0.70-0.79.
  # - From 20 resolved predictions a band shows its hit rate; below, its
  #   hit_rate is :too_few. The mean stated probability is shown either
  #   way (nil for an empty band): it is what was said, not an estimate.
  test "five bands, a hit rate only from 20 resolved predictions" do
    report = Calibration.report(fixture())

    assert Enum.map(report.bands, &{Decimal.to_string(&1.from), Decimal.to_string(&1.to)}) ==
             [
               {"0.50", "0.59"},
               {"0.60", "0.69"},
               {"0.70", "0.79"},
               {"0.80", "0.89"},
               {"0.90", "0.99"}
             ]

    [b50, b60, b70, b80, b90] = report.bands

    assert b50.count == 1
    assert_decimal(b50.mean_probability, "0.50")
    assert b50.hit_rate == :too_few

    # 20 x 0.60 + 0.69 = 12.69; 12.69 / 21 = 0.6042857142857142857142857142857143.
    # 14 hits of 21: 2 / 3 = 0.6666666666666666666666666666666667.
    assert b60.count == 21
    assert_digits(b60.mean_probability, "0.6042857142857142857142857142857143")
    assert_digits(b60.hit_rate, "0.6666666666666666666666666666666667")

    # 18 x 0.70 + 0.79 = 13.39; 13.39 / 19 = 0.7047368421052631578947368421052632.
    # 12 hits of 19, but 19 < 20: too_few.
    assert b70.count == 19
    assert_digits(b70.mean_probability, "0.7047368421052631578947368421052632")
    assert b70.hit_rate == :too_few

    # Its one call (0.80) is unresolved: nothing resolved in the band.
    assert b80.count == 0
    assert b80.mean_probability == nil
    assert b80.hit_rate == :too_few

    # (0.90 + 0.99) / 2 = 0.945.
    assert b90.count == 2
    assert_decimal(b90.mean_probability, "0.945")
    assert b90.hit_rate == :too_few
  end

  # User story (F3, ADR-0055 §4 "groups"; D-10 condition 2):
  # As the operator whose agent changes models under one token,
  # I want the same block per author and per model,
  # so that a new model's calls are scored apart from the old one's and
  # the operator's own calls stand beside the agent's.
  #
  # Acceptance criteria:
  # - One group per author present (agent, operator) and per model present
  #   (in order, the operator's calls, which carry no model, last as nil),
  #   each with the counts, the scores and the bands of the headline.
  test "the same block per author and per model" do
    report = Calibration.report(fixture())

    assert Enum.map(report.groups.author, & &1.author) == [:agent, :operator]
    assert Enum.map(report.groups.model, & &1.model) == ["model-a", "model-b", nil]

    [agent, operator] = report.groups.author

    # Agent: 21 (model-a) + 2 (model-b) = 23 resolved; hits 14 + 1 = 15;
    # S1 = 2.08 + 2.52 + 0.0961 + 0.01 + 0.9801 = 5.6862;
    # Brier 5.6862 / 23 = 0.2472260869565217391304347826086957;
    # hit rate 15 / 23 = 0.6521739130434782608695652173913043.
    assert agent.counts == %{
             total: 26,
             open: 1,
             resolved: 23,
             unresolved: %{
               no_start_close: 1,
               no_end_close: 1,
               no_benchmark_close: 0,
               no_fx_rate: 0
             }
           }

    assert_digits(agent.brier.score, "0.2472260869565217391304347826086957")
    assert_digits(agent.hit_rate.rate, "0.6521739130434782608695652173913043")
    assert Enum.map(agent.bands, & &1.count) == [0, 21, 0, 0, 2]

    # Operator: 20 resolved, hits 12 + 1 = 13;
    # S1 = 1.08 + 2.94 + 0.6241 + 0.25 = 4.8941; Brier 4.8941 / 20 = 0.244705;
    # hit rate 13 / 20 = 0.65; sum p = 12.6 + 0.79 + 0.50 = 13.89, so
    # sharpness (13.89 - 10) / 20 = 0.1945 and mean probability 0.6945.
    # S2 = 0.0972 + 1.4406 + 0.38950081 + 0.0625 = 1.98980081;
    # n S2 - S1^2 = 39.7960162 - 23.95221481 = 15.84380139;
    # n^2 (n - 1) = 400 x 19 = 7600; 15.84380139 / 7600 = 0.002084710709210526...;
    # sqrt = 0.04565863236246270129611268087637318.
    assert operator.counts.resolved == 20
    assert operator.counts.unresolved.no_fx_rate == 1
    assert operator.counts.unresolved.no_benchmark_close == 1
    assert_decimal(operator.brier.score, "0.244705")
    assert_digits(operator.brier.standard_error, "0.04565863236246270129611268087637318")
    assert_decimal(operator.hit_rate.rate, "0.65")
    assert_decimal(operator.sharpness, "0.1945")
    assert_decimal(operator.hit_rate.mean_probability, "0.6945")
    assert Enum.map(operator.bands, & &1.count) == [1, 0, 19, 0, 0]
    assert Enum.all?(operator.bands, &(&1.hit_rate == :too_few))

    [model_a, model_b, no_model] = report.groups.model

    # model-a: 21 resolved, the band 0.60-0.69 shown at 2 / 3;
    # S1 = 2.08 + 2.52 + 0.0961 = 4.6961; Brier 4.6961 / 21
    # = 0.2236238095238095238095238095238095.
    assert model_a.counts.resolved == 21
    assert model_a.counts.open == 1
    assert_digits(model_a.brier.score, "0.2236238095238095238095238095238095")
    assert_digits(Enum.at(model_a.bands, 1).hit_rate, "0.6666666666666666666666666666666667")

    # model-b: 2 resolved, 0.90 hit and 0.99 miss; e = 0.01 and 0.9801;
    # S1 = 0.9901, Brier 0.49505; S2 = 0.0001 + 0.96059601 = 0.96069601;
    # n S2 - S1^2 = 1.92139202 - 0.98029801 = 0.94109401; n^2 (n - 1) = 4;
    # 0.94109401 / 4 = 0.2352735025; sqrt = 0.48505 (0.48505^2 = 0.2352735025).
    # Hit rate 1 / 2 = 0.5; its standard error sqrt(1 x 1 / 4) = 0.5.
    # Sharpness (0.40 + 0.49) / 2 = 0.445.
    assert_decimal(model_b.brier.score, "0.49505")
    assert_decimal(model_b.brier.standard_error, "0.48505")
    assert_decimal(model_b.hit_rate.rate, "0.5")
    assert_decimal(model_b.hit_rate.standard_error, "0.5")
    assert_decimal(model_b.sharpness, "0.445")

    # The operator's calls carry no model: the nil group is the operator's.
    assert no_model.counts == operator.counts
    assert no_model.brier == operator.brier
  end

  # User story (F3, ADR-0055 §4, the small sample):
  # As the operator reading the report in its first weeks,
  # I want a figure that cannot be computed named null with its reason,
  # so that nothing divides by zero and nothing reads as a certainty one
  # call cannot carry.
  #
  # Acceptance criteria:
  # - n = 0: every score, the sharpness, the hit rate and the mean stated
  #   probability are nil; both standard errors are nil with reason
  #   :no_resolved; every band reads count 0 and too_few.
  # - n = 1: the scores are the call's own; both standard errors are nil
  #   with reason :one_resolved (a sample standard deviation needs n - 1 of
  #   at least 1).
  test "no resolved prediction, and one" do
    empty = Calibration.report([entry(:agent, "model-a", "0.70", :open)])

    assert empty.counts.resolved == 0
    assert empty.counts.open == 1
    assert empty.brier.score == nil
    assert empty.brier.standard_error == nil
    assert empty.brier.standard_error_reason == :no_resolved
    assert_decimal(empty.brier.reference, "0.25")
    assert empty.sharpness == nil
    assert empty.hit_rate.rate == nil
    assert empty.hit_rate.hits == 0
    assert empty.hit_rate.mean_probability == nil
    assert empty.hit_rate.standard_error == nil
    assert empty.hit_rate.standard_error_reason == :no_resolved
    assert Enum.all?(empty.bands, &(&1.count == 0 and &1.hit_rate == :too_few))

    nothing = Calibration.report([])
    assert nothing.counts.total == 0
    assert nothing.groups == %{author: [], model: []}

    # One 0.80 miss: e = 0.64; Brier 0.64; sharpness 0.30; hit rate 0.
    one = Calibration.report([entry(:operator, nil, "0.80", :miss)])

    assert_decimal(one.brier.score, "0.64")
    assert one.brier.standard_error == nil
    assert one.brier.standard_error_reason == :one_resolved
    assert_decimal(one.sharpness, "0.30")
    assert_decimal(one.hit_rate.rate, "0")
    assert_decimal(one.hit_rate.mean_probability, "0.80")
    assert one.hit_rate.standard_error == nil
    assert one.hit_rate.standard_error_reason == :one_resolved
  end

  # User story (F3, ADR-0055 §4): every call stated alike scores a
  # standard error of exactly 0, never a negative under the root.
  test "equal squared errors give a standard error of exactly 0" do
    report = Calibration.report(times(3, :agent, "model-a", "0.60", :hit))

    # e = 0.16 three times: n S2 - S1^2 = 3 x 0.0768 - 0.48^2 = 0.2304 - 0.2304 = 0.
    assert_decimal(report.brier.score, "0.16")
    assert_decimal(report.brier.standard_error, "0")
    assert_decimal(report.hit_rate.standard_error, "0")
  end
end
