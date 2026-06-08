defmodule Portfolixir.Portfolios.TargetsTest do
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Targets

  # User story:
  # As a local portfolio maintainer (and the LLM I connect over MCP),
  # I want to store my target weights per strategy category in Portfolixir,
  # so that the single source of truth carries my SOLL allocation instead of an
  # external document I have to keep in sync by hand.
  #
  # Acceptance criteria:
  # - Targets can be set, listed (optionally scoped to one classification), and
  #   deleted per portfolio and category.
  # - Setting a target again upserts the weight rather than duplicating it.
  # - A weight outside [0, 1] is rejected.
  # - A category from another classification cannot be targeted.

  defp setup_world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(%{name: "Local Portfolio", base_currency_code: "EUR"})

    {:ok, classification} = Classifications.create_classification(%{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(%{classification_id: classification.id, name: "Core"})

    {:ok, satellite} =
      Classifications.create_category(%{classification_id: classification.id, name: "Satellite"})

    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite}
  end

  test "sets, lists, and scopes target weights per portfolio" do
    %{portfolio: portfolio, classification: classification, core: core, satellite: satellite} =
      setup_world()

    {:ok, targets} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"},
        %{"category_id" => satellite.id, "target_weight" => "0.4"}
      ])

    assert length(targets) == 2

    listed = Targets.list_targets(portfolio.id)
    assert length(listed) == 2

    scoped = Targets.list_targets(portfolio.id, classification_id: classification.id)
    assert length(scoped) == 2

    assert Targets.list_targets(portfolio.id, classification_id: classification.id + 999) == []
  end

  test "upserts an existing target instead of duplicating it" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.5"}
      ])

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.7"}
      ])

    [target] = Targets.list_targets(portfolio.id)
    assert Decimal.equal?(target.target_weight, Decimal.new("0.7"))
  end

  test "rejects a weight outside the unit interval" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert {:error, %Ecto.Changeset{} = changeset} =
             Targets.set_targets(portfolio.id, classification.id, [
               %{"category_id" => core.id, "target_weight" => "1.5"}
             ])

    assert %{target_weight: [_ | _]} = errors_on(changeset)
    assert Targets.list_targets(portfolio.id) == []
  end

  test "rejects a category from a different classification" do
    %{portfolio: portfolio, classification: classification} = setup_world()

    {:ok, other} = Classifications.create_classification(%{name: "Regions"})

    {:ok, foreign} =
      Classifications.create_category(%{classification_id: other.id, name: "Europe"})

    assert {:error, :category_mismatch} =
             Targets.set_targets(portfolio.id, classification.id, [
               %{"category_id" => foreign.id, "target_weight" => "0.5"}
             ])
  end

  test "deletes a target for one category" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.5"}
      ])

    assert {:ok, 1} = Targets.delete_target(portfolio.id, core.id)
    assert Targets.list_targets(portfolio.id) == []
    assert {:ok, 0} = Targets.delete_target(portfolio.id, core.id)
  end
end
