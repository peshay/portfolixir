defmodule Portfolixir.Portfolios.TargetPlansMigrationTest do
  @moduledoc """
  Pins the ADR-0020 loss-free data migration (issue #464) without re-running the
  schema migrator.

  The migrator cannot be driven cleanly under the Ecto SQL sandbox (it opens its
  own transaction on a separate connection), and switching the Repo to :auto mode
  would break the concurrently running async suite. So instead this DataCase test
  **reconstructs the pre-migration ("legacy") shape inside the sandbox
  transaction** — re-adding `portfolios.cash_target_weight`, detaching
  `portfolio_targets` from a plan — seeds legacy data, then runs the migration's
  exact data-carry statements and asserts the loss-free outcome. Everything rolls
  back at the end of the test, so the suite's schema is untouched.

  Schema **reversibility** (the DDL round trip) is exercised separately by the
  standard `mix ecto.rollback` / `mix ecto.migrate` cycle in CI and locally; this
  test pins the part with the silent-corruption risk: the data carry-over.
  """
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Repo

  # User story:
  # As the maintainer rolling out view-bound SOLL plans (ADR-0020),
  # I want the migration to carry my existing global targets and cash target into
  # the Gesamt plan with no loss,
  # so that my current setup simply appears under "Gesamt" and nothing is dropped.
  #
  # Acceptance criteria:
  # - Every legacy portfolio_targets row lands on a Gesamt plan (view_id NULL) for
  #   its own (portfolio, classification); the row keeps its weight.
  # - The legacy portfolios.cash_target_weight lands on a Gesamt, classification-
  #   less plan (view_id NULL, classification_id NULL); the value is exact.
  # - Distinct (portfolio, classification) pairs each get exactly one Gesamt plan.

  test "the data migration carries legacy targets and cash target into the Gesamt plan" do
    reconstruct_legacy_shape!()

    # Two portfolios, two classifications: enough to prove "one Gesamt plan per
    # distinct (portfolio, classification)" and an independent cash carry-over.
    p1 = insert_portfolio!("Legacy One", "0.05")
    p2 = insert_portfolio!("Legacy Two", nil)

    c_strategy = insert_classification!("Strategy")
    c_region = insert_classification!("Region")

    core = insert_category!(c_strategy, "Core")
    sat = insert_category!(c_strategy, "Satellite")
    europe = insert_category!(c_region, "Europe")

    # Legacy targets (no plan_id yet): p1 across both classifications, p2 in one.
    insert_legacy_target!(p1, c_strategy, core, "0.60")
    insert_legacy_target!(p1, c_strategy, sat, "0.40")
    insert_legacy_target!(p1, c_region, europe, "1.00")
    insert_legacy_target!(p2, c_strategy, core, "1.00")

    run_data_carry!()

    # Every legacy target now points at a Gesamt plan for its own
    # (portfolio, classification), and the weight is unchanged.
    for {portfolio_id, classification_id, category_id, weight} <- [
          {p1, c_strategy, core, "0.60"},
          {p1, c_strategy, sat, "0.40"},
          {p1, c_region, europe, "1.00"},
          {p2, c_strategy, core, "1.00"}
        ] do
      assert %{rows: [[plan_pid, plan_vid, plan_cid, target_weight]]} =
               Repo.query!(
                 """
                 SELECT pl.portfolio_id, pl.view_id, pl.classification_id, t.target_weight
                 FROM portfolio_targets t
                 JOIN portfolio_target_plans pl ON pl.id = t.plan_id
                 WHERE t.portfolio_id = $1 AND t.category_id = $2
                 """,
                 [portfolio_id, category_id]
               )

      assert plan_pid == portfolio_id
      assert is_nil(plan_vid), "the carried plan must be the Gesamt plan (view_id NULL)"
      assert plan_cid == classification_id
      assert Decimal.equal?(target_weight, Decimal.new(weight))
    end

    # Exactly one Gesamt plan per distinct (portfolio, classification): p1 has two
    # (Strategy, Region), p2 has one (Strategy) — plus p1's classification-less
    # cash plan (asserted below). No duplicate target plans.
    assert gesamt_target_plan_count(p1) == 2
    assert gesamt_target_plan_count(p2) == 1

    # The legacy cash target landed on p1's Gesamt, classification-less plan.
    assert %{rows: [[cash_weight]]} =
             Repo.query!(
               """
               SELECT cash_target_weight FROM portfolio_target_plans
               WHERE portfolio_id = $1 AND view_id IS NULL AND classification_id IS NULL
               """,
               [p1]
             )

    assert Decimal.equal?(cash_weight, Decimal.new("0.05"))

    # p2 had no cash target, so it gets no classification-less cash plan.
    assert %{rows: []} =
             Repo.query!(
               """
               SELECT id FROM portfolio_target_plans
               WHERE portfolio_id = $1 AND view_id IS NULL AND classification_id IS NULL
               """,
               [p2]
             )
  end

  # -- legacy-shape reconstruction (inside the sandbox transaction) ------------

  # Rewinds just enough of the ADR-0020 migration to recreate the pre-migration
  # write shape: the legacy `portfolios.cash_target_weight` column and a
  # `portfolio_targets` table with no required plan link. Rolls back with the test.
  defp reconstruct_legacy_shape! do
    Repo.query!("ALTER TABLE portfolios ADD COLUMN cash_target_weight numeric")
    Repo.query!("ALTER TABLE portfolio_targets ALTER COLUMN plan_id DROP NOT NULL")
  end

  # The migration's exact forward data-carry (ADR-0020), replayed here as the
  # contract under test.
  defp run_data_carry! do
    Repo.query!("""
    INSERT INTO portfolio_target_plans
      (portfolio_id, view_id, classification_id, cash_target_weight, inserted_at, updated_at)
    SELECT DISTINCT
      t.portfolio_id, NULL::bigint, t.classification_id, NULL::numeric, NOW(), NOW()
    FROM portfolio_targets t
    """)

    Repo.query!("""
    UPDATE portfolio_targets t
    SET plan_id = p.id
    FROM portfolio_target_plans p
    WHERE p.portfolio_id = t.portfolio_id
      AND p.classification_id = t.classification_id
      AND p.view_id IS NULL
    """)

    Repo.query!("""
    INSERT INTO portfolio_target_plans
      (portfolio_id, view_id, classification_id, cash_target_weight, inserted_at, updated_at)
    SELECT pf.id, NULL::bigint, NULL::bigint, pf.cash_target_weight, NOW(), NOW()
    FROM portfolios pf
    WHERE pf.cash_target_weight IS NOT NULL
    """)
  end

  defp gesamt_target_plan_count(portfolio_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT count(*) FROM portfolio_target_plans
        WHERE portfolio_id = $1 AND view_id IS NULL AND classification_id IS NOT NULL
        """,
        [portfolio_id]
      )

    count
  end

  # -- legacy seed helpers (raw SQL) ------------------------------------------

  defp insert_portfolio!(name, cash_target) do
    # This raw seed mimics legacy (pre-ADR-0020) rows. Since the `portfolios`
    # table is now guard-armed (ADR-0017), satisfy the actor guard the same way
    # Portfolixir.Journal does — set the transaction-local actor GUC — so the
    # seed insert is permitted.
    Repo.query!("SELECT set_config('portfolixir.journal_actor', 'migration_seed', true)")

    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO portfolios (name, base_currency_code, cash_target_weight, inserted_at, updated_at) " <>
          "VALUES ($1, 'EUR', $2, now(), now()) RETURNING id",
        [name, cash_target && Decimal.new(cash_target)]
      )

    id
  end

  defp insert_classification!(name) do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO classifications (name, inserted_at, updated_at) " <>
          "VALUES ($1, now(), now()) RETURNING id",
        [name]
      )

    id
  end

  defp insert_category!(classification_id, name) do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO classification_categories (classification_id, name, inserted_at, updated_at) " <>
          "VALUES ($1, $2, now(), now()) RETURNING id",
        [classification_id, name]
      )

    id
  end

  defp insert_legacy_target!(portfolio_id, classification_id, category_id, weight) do
    Repo.query!(
      "INSERT INTO portfolio_targets " <>
        "(portfolio_id, classification_id, category_id, target_weight, inserted_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, now(), now())",
      [portfolio_id, classification_id, category_id, Decimal.new(weight)]
    )
  end
end
