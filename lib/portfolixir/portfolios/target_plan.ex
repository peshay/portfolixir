defmodule Portfolixir.Portfolios.TargetPlan do
  @moduledoc """
  A view-bound SOLL target plan (ADR-0020).

  A plan is the unit a maintainer steers: it belongs to a `(portfolio, view,
  classification)` and owns its per-category target weights
  (`Portfolixir.Portfolios.Target` rows hanging off `plan_id`) plus the plan's
  cash target.

  `view_id = nil` is the **Gesamt** (total) plan — the portfolio-wide plan that
  reproduces the behaviour before views existed. `classification_id = nil` marks
  the portfolio-wide **cash-only** plan that carries the legacy global cash
  target (which was never classification-scoped); per-classification cash targets
  live on the plan for their own `classification_id`.

  Since ADR-0027 a plan is a **named version** with a lifecycle `status`
  (`active` / `draft` / `archived`). Uniqueness is enforced by the partial
  NULLS-NOT-DISTINCT index `portfolio_target_plans_active_unique_index`: at most
  one **active** plan per `(portfolio_id, view_id, classification_id)`; drafts
  and archived plans coexist freely in the same scope (duplicate-to-edit).

  Plan and target writes are journaled and guard-armed (ADR-0017): every write
  goes through `Portfolixir.Portfolios.Targets` with an actor.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolixir.Buckets.View
  alias Portfolixir.Classifications.Classification
  alias Portfolixir.Portfolios.Portfolio
  alias Portfolixir.Portfolios.Target

  @type t :: %__MODULE__{}

  @statuses ~w(active draft archived)

  schema "portfolio_target_plans" do
    field(:cash_target_weight, :decimal)
    field(:name, :string, default: "Plan")
    field(:status, :string, default: "active")

    belongs_to(:portfolio, Portfolio)
    belongs_to(:view, View)
    belongs_to(:classification, Classification)

    has_many(:targets, Target, foreign_key: :plan_id)

    timestamps()
  end

  @doc "The allowed plan lifecycle statuses (ADR-0027)."
  def statuses, do: @statuses

  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [
      :portfolio_id,
      :view_id,
      :classification_id,
      :cash_target_weight,
      :name,
      :status
    ])
    |> validate_required([:portfolio_id, :name, :status])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:status, @statuses)
    |> validate_cash_target_weight()
    |> assoc_constraint(:portfolio)
    |> assoc_constraint(:view)
    |> assoc_constraint(:classification)
    |> unique_constraint([:portfolio_id, :view_id, :classification_id],
      name: :portfolio_target_plans_active_unique_index
    )
  end

  # The cash target is a fraction in `[0, 1]` (e.g. `0.05` for 5%), or `nil` when
  # the plan does not steer a cash quote — mirroring the per-category weights.
  defp validate_cash_target_weight(changeset) do
    validate_number(changeset, :cash_target_weight,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1
    )
  end
end
