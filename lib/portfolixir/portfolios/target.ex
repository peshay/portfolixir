defmodule Portfolixir.Portfolios.Target do
  @moduledoc """
  A portfolio's target weight for one classification category.

  Target weights are the SOLL side of the weekly SOLL/IST check: they live in
  Portfolixir (the single source of truth) rather than in an external document,
  so the actual allocation (`Portfolixir.Portfolios.Allocation`) can report drift
  without the caller carrying the targets along.

  The weight is a fraction in `[0, 1]` (e.g. `0.25` for 25%), matching how
  `Portfolixir.Portfolios.Valuation` reports actual position weights. Targets are
  not required to sum to 1: a portfolio may define only the categories it tracks.

  Since ADR-0020 a target hangs off a **plan** (`plan_id` →
  `Portfolixir.Portfolios.TargetPlan`), which fixes the `(portfolio, view,
  classification)` it belongs to. `view_id NULL` on the plan is the Gesamt plan,
  today's portfolio-wide behaviour. The denormalised `portfolio_id` and
  `classification_id` columns are kept on the target for query convenience and
  match the plan they belong to. A category is unique **within a plan**.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Classifications.Category
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.TargetPlan

  schema "portfolio_targets" do
    field(:target_weight, :decimal)

    belongs_to(:plan, TargetPlan)
    belongs_to(:portfolio, Portfolio)
    belongs_to(:classification, Classification)
    belongs_to(:category, Category)

    timestamps()
  end

  def changeset(target, attrs) do
    target
    |> cast(attrs, [:plan_id, :portfolio_id, :classification_id, :category_id, :target_weight])
    |> validate_required([
      :plan_id,
      :portfolio_id,
      :classification_id,
      :category_id,
      :target_weight
    ])
    |> validate_number(:target_weight,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
    |> assoc_constraint(:plan)
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:classification)
    |> assoc_constraint(:category)
    |> unique_constraint([:plan_id, :category_id],
      name: :portfolio_targets_plan_id_category_id_index
    )
  end
end
