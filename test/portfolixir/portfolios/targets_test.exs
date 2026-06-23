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
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Local Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, classification} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Strategy"})

    {:ok, core} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, satellite} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Satellite"
      })

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

    {:ok, other} =
      Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{name: "Regions"})

    {:ok, foreign} =
      Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
        classification_id: other.id,
        name: "Europe"
      })

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

  test "rejects a non-map target entry instead of crashing" do
    %{portfolio: portfolio, classification: classification} = setup_world()

    assert {:error, :invalid_entry} =
             Targets.set_targets(portfolio.id, classification.id, [1])

    assert Targets.list_targets(portfolio.id) == []
  end

  # User story:
  # As a maintainer (or the MCP client) reading and editing one target,
  # I want to fetch a single portfolio/category target and to get clear errors
  # for unknown trees or malformed entries,
  # so that the SOLL editor never silently mis-files a weight.
  #
  # Acceptance criteria:
  # - get_target/2 returns the stored target, or nil when none exists.
  # - set_targets/3 against an unknown classification returns {:error, :not_found}.
  # - An entry whose category_id is a numeric string is matched to its category;
  #   a non-numeric id is treated as "no id" and left to the changeset.
  test "get_target/2 returns the stored target or nil" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert Targets.get_target(portfolio.id, core.id) == nil

    {:ok, _} =
      Targets.set_targets(portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.6"}
      ])

    target = Targets.get_target(portfolio.id, core.id)
    assert target.category_id == core.id
    assert Decimal.equal?(target.target_weight, Decimal.new("0.6"))
  end

  test "set_targets/3 reports an unknown classification as :not_found" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    assert {:error, :not_found} =
             Targets.set_targets(portfolio.id, classification.id + 999, [
               %{"category_id" => core.id, "target_weight" => "0.5"}
             ])
  end

  test "set_targets/3 accepts a numeric-string category id" do
    %{portfolio: portfolio, classification: classification, core: core} = setup_world()

    # The string id matches the in-tree category (normalize_id parses it), so
    # the foreign-category guard passes and the weight is upserted.
    assert {:ok, [target]} =
             Targets.set_targets(portfolio.id, classification.id, [
               %{"category_id" => Integer.to_string(core.id), "target_weight" => "0.5"}
             ])

    assert target.category_id == core.id
  end

  test "set_targets/3 leaves a missing category id to the changeset" do
    %{portfolio: portfolio, classification: classification} = setup_world()

    # No category_id: the foreign-category guard treats it as "no id" and the
    # changeset rejects the row for the missing required category.
    assert {:error, %Ecto.Changeset{} = changeset} =
             Targets.set_targets(portfolio.id, classification.id, [
               %{"target_weight" => "0.5"}
             ])

    assert %{category_id: [_ | _]} = errors_on(changeset)
    assert Targets.list_targets(portfolio.id) == []
  end
end
