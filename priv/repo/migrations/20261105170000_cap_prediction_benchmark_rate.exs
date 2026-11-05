defmodule Portfolixir.Repo.Migrations.CapPredictionBenchmarkRate do
  @moduledoc """
  ADR-0055, amendment of 2026-11-05, §3 (the Sprint 25 closing act's UAT
  persona): a fixed-rate benchmark of a prediction is a fraction from
  -0.999999 to 1, so `rate:0.02` is 2 % a year and `rate:5`, meant as 5 %,
  is refused rather than stored as 500 % a year on a record nobody can
  correct.

  The cap is a CHECK of its own, `predictions_benchmark_rate_cap_check`,
  beside `predictions_benchmark_rate_check` (the engine's bound, -0.999999
  to 10, which `create_predictions` added and which stays as it is: an
  applied migration is never edited). It is added **NOT VALID**: it refuses
  every new row, and no stored row is checked. A prediction is permanent
  (§2: the table refuses UPDATE and DELETE), so a call an instance stored
  against a rate above 1 before this release cannot be corrected and must
  not stop the upgrade; it stays as made, resolved by its own rate.
  `Portfolixir.Predictions.Prediction` refuses the same bound first, with
  the message naming the fraction form.
  """
  use Ecto.Migration

  def change do
    create(
      constraint(:predictions, :predictions_benchmark_rate_cap_check,
        check: "benchmark_rate IS NULL OR benchmark_rate <= 1",
        validate: false
      )
    )
  end
end
