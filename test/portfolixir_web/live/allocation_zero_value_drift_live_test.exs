defmodule PortfolixirWeb.AllocationZeroValueDriftLiveTest do
  # E25 S4, G14 (#889), board 12 of the Sprint 16 design pass ("zero-value
  # drift", before/after): a position valued at 0 received a category-share
  # drift of a signed zero, shown as "-0.00 EUR" and sorted among the rows
  # that drift; and the plan editor turned every weight error into "must lie
  # between 0 and 100 %", so a weight refused for its precision named the
  # wrong reason.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets

  setup do
    world = base_world(name: "Zero value", cash_name: "Giro", depot_name: "Depot")
    owner = Actor.owner_ui()

    {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategie"})

    {:ok, growth} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Wachstum"})

    {:ok, income} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Ertrag"})

    helios = create_security!(name: "Helios Solar Systems SE", ticker: "HSS")
    larkspur = create_security!(name: "Larkspur Minerals SE", ticker: "LMS")
    harbor = create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")

    for {security, category} <- [{helios, growth}, {larkspur, growth}, {harbor, income}] do
      {:ok, _} = Classifications.assign_security(owner, security.id, tree.id, category.id)
    end

    buy!(world, helios, quantity: "10", price: "10")
    # A free allotment booked at price 0 and never quoted: valued at 0.
    buy!(world, larkspur, quantity: "10", price: "0")
    buy!(world, harbor, quantity: "10", price: "30")

    {:ok, _} =
      Targets.set_targets(owner, world.portfolio.id, tree.id, [
        %{"category_id" => growth.id, "target_weight" => "0.5"},
        %{"category_id" => income.id, "target_weight" => "0.5"}
      ])

    Map.merge(world, %{tree: tree, growth: growth, income: income})
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  # User story (board 12, "zero-value drift"):
  # As the operator reading the flat positions worklist,
  # I want a position valued at 0 to show no drift share,
  # so that the worklist ranks what I can act on and no "-0.00" reads as a
  # sell or a buy.
  #
  # Acceptance criteria:
  # - The zero-value row's drift cell reads "—", as an unassigned position's
  #   does, with no negative tone and no hint.
  # - Sorted by drift, the row sits after every row that has a drift.
  # - Value "0.00", the category and the hint "—" stay.
  test "a zero-value position's drift cell reads — and the row sorts last", %{conn: conn} = ctx do
    {:ok, view, _html} =
      live(conn, "/portfolio?tab=allocation&classification=#{ctx.tree.id}&alloc=positions")

    render_async(view)

    rows =
      view
      |> element(~s([data-role="flat-positions"]))
      |> render()
      |> Floki.parse_document!()
      |> Floki.find(~s(tr[data-role="flat-position"]))

    names = Enum.map(rows, &text(Floki.find(&1, "td:first-child")))
    larkspur_index = Enum.find_index(names, &(&1 =~ "Larkspur Minerals SE"))
    helios_index = Enum.find_index(names, &(&1 =~ "Helios Solar Systems SE"))
    harbor_index = Enum.find_index(names, &(&1 =~ "Harbor Light Utilities SE"))

    assert larkspur_index > helios_index
    assert larkspur_index > harbor_index

    larkspur = Enum.at(rows, larkspur_index)
    [drift_cell] = Floki.find(larkspur, "td.col-subject")

    assert text(drift_cell) == "—"
    refute Floki.attribute(drift_cell, "class") |> Enum.join(" ") =~ "is-negative"
    refute text(larkspur) =~ "-0.00"
    assert text(larkspur) =~ "0.00"
    assert Floki.find(larkspur, ~s([data-role="rebalance-hint"])) == []
  end

  # User story (board 12, the plan editor's note):
  # As the operator entering a plan in percent,
  # I want a weight with more places than the plan keeps refused with its own
  # sentence,
  # so that the message names the precision, not the 0-100 % range.
  #
  # Acceptance criteria:
  # - A category weight or a cash target with more than four decimal places in
  #   percent is refused with "A target carries at most four decimal places in
  #   percent"; nothing is written.
  test "the plan editor names the precision of a refused weight", %{conn: conn} = ctx do
    {:ok, view, _html} = live(conn, "/classifications/#{ctx.tree.id}")
    render_async(view)

    html =
      view
      |> form("#soll-plan-form")
      |> render_submit(%{
        "weights" => %{"#{ctx.growth.id}" => "12.34567", "#{ctx.income.id}" => "50"},
        "cash_target" => ""
      })

    assert html =~ "A target carries at most four decimal places in percent"
    refute html =~ "A target must lie between 0 and 100 %"

    html =
      view
      |> form("#soll-plan-form")
      |> render_submit(%{
        "weights" => %{"#{ctx.growth.id}" => "40", "#{ctx.income.id}" => "50"},
        "cash_target" => "10.00001"
      })

    assert html =~ "A target carries at most four decimal places in percent"

    [growth_target] =
      ctx.portfolio.id
      |> Targets.list_targets(classification_id: ctx.tree.id)
      |> Enum.filter(&(&1.category_id == ctx.growth.id))

    assert Decimal.equal?(growth_target.target_weight, Decimal.new("0.5"))
  end
end
