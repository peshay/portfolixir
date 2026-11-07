defmodule Portfolixir.News.UniverseTest do
  # ADR-0056 §2 (Sprint 27, N4): the universe an aggregator item is matched
  # against — every security a view holds, that carries a target weight
  # above zero, or that carries `news_watch` — and the exchange-traded funds
  # left out of aggregator matching. Synthetic names only.
  use Portfolixir.DataCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, sell!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.News.Matcher
  alias Portfolixir.News.Universe
  alias Portfolixir.Portfolios.Targets

  defp owner, do: Actor.owner_ui()

  defp equity!(name), do: create_security!(name: name, ticker: nil, asset_class: "equity")

  defp ids(members), do: Enum.map(members, & &1.id)

  # A plan on the world's portfolio with a position target per
  # `{security, weight}`, each security filed under one category.
  defp position_targets!(world, weighted, opts \\ []) do
    {:ok, classification} =
      Classifications.create_classification(owner(), %{
        name: "Strategy #{System.unique_integer([:positive])}"
      })

    {:ok, category} =
      Classifications.create_category(owner(), %{
        classification_id: classification.id,
        name: "Core"
      })

    entries =
      for {security, weight} <- weighted do
        {:ok, _} =
          Classifications.assign_security(owner(), security.id, classification.id, category.id)

        %{category_id: category.id, security_id: security.id, target_weight: Decimal.new(weight)}
      end

    {:ok, _targets} =
      Targets.set_targets(owner(), world.portfolio.id, classification.id, entries, opts)

    classification
  end

  # User story:
  # As the operator's agent,
  # I want aggregator news matched only against the securities I hold, aim
  # to hold, or watch,
  # so that an alias of a security I have no stake in does not pull items
  # onto it, and a candidate I am researching can still collect news.
  #
  # Acceptance criteria:
  # - A held security is in the universe; one sold to zero is not.
  # - A security with a position target above zero in an active plan is in;
  #   a zero target, or one only in a draft plan, is not.
  # - A security with `news_watch` is in; one with none of the three is not.
  # - Each member carries its id, kind, aliases, CIK, ISIN and WKN.
  describe "members/0" do
    test "held, targeted above zero, or watched; nothing else" do
      world = base_world(name: "Universe Portfolio")
      held = equity!("Northwind Harbour Logistics AG")
      sold = equity!("Larkspur Robotics Inc")
      targeted = equity!("Quillfeather Paper SE")
      zero = equity!("Saltmarsh Water plc")
      drafted = equity!("Tidewater Rail AG")
      outside = equity!("Ironbark Timber Ltd")

      buy!(world, held, quantity: "3")
      buy!(world, sold, quantity: "2")
      sell!(world, sold, quantity: "2", date: ~D[2026-02-02])

      classification = position_targets!(world, [{targeted, "0.25"}, {zero, "0"}])
      [active] = Targets.list_plans(world.portfolio.id, classification_id: classification.id)
      {:ok, draft} = Targets.duplicate_plan(owner(), active)

      {:ok, _} =
        Classifications.assign_security(
          owner(),
          drafted.id,
          classification.id,
          hd(Classifications.list_categories(classification.id)).id
        )

      {:ok, _} =
        Targets.set_targets(
          owner(),
          world.portfolio.id,
          classification.id,
          [
            %{
              category_id: hd(Classifications.list_categories(classification.id)).id,
              security_id: drafted.id,
              target_weight: Decimal.new("0.4")
            }
          ],
          plan: draft
        )

      {:ok, watched} =
        Catalog.update_security(owner(), equity!("Fernhill Optics AG"), %{
          news_watch: true,
          news_cik: "320193",
          isin: "DE000FHO0000",
          wkn: "FHO000",
          news_aliases: [%{token: "Fernhill", context: ["optics"], case: "insensitive"}]
        })

      members = Universe.members()

      assert ids(members) == Enum.sort([held.id, targeted.id, watched.id])
      refute Enum.any?([sold, zero, drafted, outside], &(&1.id in ids(members)))

      member = Enum.find(members, &(&1.id == watched.id))
      assert member.kind == "equity"
      assert member.cik == "0000320193"
      assert member.isin == "DE000FHO0000"
      assert member.wkn == "FHO000"
      assert [%{token: "Fernhill", context: ["optics"], case: :insensitive}] = member.aliases
    end
  end

  # User story:
  # As the operator who holds an index fund,
  # I want its name and aliases kept out of aggregator matching,
  # so that market and index news is not filed under the fund.
  #
  # Acceptance criteria:
  # - A held ETF is a member of the universe, and is not among the
  #   securities aggregator items are matched against.
  # - An ETF by the name's inference (no class stored) is left out too.
  describe "aggregator/0" do
    test "an exchange-traded fund is left out of aggregator matching" do
      world = base_world(name: "Fund Portfolio")
      stock = equity!("Northwind Harbour Logistics AG")
      fund = create_security!(name: "Synthetic World Index ETF", ticker: nil, asset_class: "etf")

      buy!(world, stock, quantity: "1")
      buy!(world, fund, quantity: "1")

      assert Enum.sort(ids(Universe.members())) == Enum.sort([stock.id, fund.id])
      assert ids(Universe.aggregator()) == [stock.id]
      assert Universe.etf?(Enum.find(Universe.members(), &(&1.id == fund.id)))
    end

    test "aggregator_index/0 compiles the aggregator members for the matcher" do
      {:ok, watched} =
        Catalog.update_security(owner(), equity!("Northwind Harbour Logistics AG"), %{
          news_watch: true,
          news_aliases: [%{token: "Northwind Harbour", case: "insensitive"}]
        })

      {:ok, _fund} =
        Catalog.update_security(
          owner(),
          create_security!(name: "Northwind Harbour Index ETF", ticker: nil, asset_class: "etf"),
          %{news_watch: true, news_aliases: [%{token: "Northwind Harbour", case: "insensitive"}]}
        )

      index = Universe.aggregator_index()

      assert Matcher.match("Northwind Harbour wins a contract", index) ==
               {:assigned, watched.id}
    end
  end
end
