defmodule PortfolixirWeb.DashboardDomIdsTest do
  # Sprint 32 closing act (PR 2, the correctness lens): a dashboard that
  # held Wealth's „Kennzahlen“ (`wealth_key_figures`) beside Risk's
  # „Kennzahlen“ (`key_figures`) drew two elements with the id
  # `dashboard-key-figures`, and the page could not be patched. Every
  # registered kind in every grid size it takes now stands on dashboards,
  # and no id repeats on a page, nor is one id drawn by two kinds. The kinds
  # and sizes are the registry's, so a kind registered later is checked
  # with no change here. Synthetic data only.
  #
  # group: :dashboards -- a create takes the count lock (LockTable row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Dashboards.Layout
  alias Portfolixir.Dashboards.Widgets

  # A portfolio with cash and a security bought, so the widgets draw their
  # figures and not only their empty states, and a dollar account without
  # a rate, so „Datenhinweise“, drawn only when a note exists, draws too.
  defp seed do
    today = Clock.today()
    home = base_world(name: "Home", cash_name: "Home Cash", depot_name: "Home Depot")
    deposit!(home, "12000.25", Date.add(today, -400))
    security = create_security!(name: "Alpha Werke")
    put_quotes!(security, [{Date.add(today, -390), "100"}, {today, "112.5"}])
    buy!(home, security, quantity: "40", price: "100", date: Date.add(today, -390))

    dollars =
      add_depot(home.portfolio,
        cash_currency: "USD",
        cash_name: "Dollar Cash",
        depot_name: "Dollar Depot"
      )

    deposit!(%{portfolio: home.portfolio, cash: dollars.cash}, "250", Date.add(today, -10),
      currency: "USD"
    )
  end

  # Every kind in every grid size it takes, in the registry's order.
  defp grid_items do
    for kind <- Widgets.kinds(),
        size <- kind.sizes,
        match?({:ok, _}, Widgets.dimensions(size)),
        do: {kind.key, size}
  end

  # The items one under the other, on as many dashboards as the layout's
  # item and row caps need.
  defp layouts(items) do
    Enum.chunk_while(
      items,
      {[], 1},
      fn {kind, size}, {acc, row} ->
        {:ok, {_w, h}} = Widgets.dimensions(size)
        item = %{"kind" => kind, "size" => size, "col" => 1, "row" => row}

        if length(acc) < Layout.max_items() and row + h - 1 <= Layout.max_row() do
          {:cont, {[item | acc], row + h}}
        else
          {:cont, Enum.reverse(acc), {[%{item | "row" => 1}], 1 + h}}
        end
      end,
      fn {acc, _row} -> {:cont, Enum.reverse(acc), {[], 1}} end
    )
  end

  defp dashboard!(name, layout) do
    {:ok, dashboard} =
      Dashboards.create_dashboard(Actor.owner_ui(), %{"name" => name, "layout" => layout})

    dashboard
  end

  defp page(conn, dashboard) do
    {:ok, view, _html} = live(conn, "/dashboards/#{dashboard.id}")
    render_async(view)
    view |> render() |> Floki.parse_document!()
  end

  defp ids(nodes), do: nodes |> Floki.attribute("id")

  defp repeated(ids),
    do:
      ids |> Enum.frequencies() |> Enum.filter(fn {_id, n} -> n > 1 end) |> Enum.map(&elem(&1, 0))

  # Each id inside a widget, with the kind whose frame draws it.
  defp ids_by_kind(doc) do
    for widget <- Floki.find(doc, "section[data-widget-kind]"),
        [kind] = Floki.attribute(widget, "data-widget-kind"),
        id <- ids(Floki.find(widget, "[id]")) ++ ids([widget]),
        do: {id, kind}
  end

  # User story:
  # As the operator who composes a dashboard from any kinds,
  # I want every widget's ids to stay its own,
  # so that a dashboard holding Wealth's and Risk's „Kennzahlen“ side by
  # side draws and updates like any other.
  #
  # Acceptance criteria:
  # - A dashboard holding wealth_key_figures and key_figures draws each
  #   widget under an id of its own.
  # - Every registered kind in every grid size it takes, on dashboards of
  #   at most the layout's item cap, draws no id twice on a page, and no id
  #   is drawn by two kinds on any of the pages.
  test "Wealth's and Risk's „Kennzahlen“ stand on one dashboard under ids of their own",
       %{conn: conn} do
    seed()

    board =
      dashboard!("Beide Kennzahlen", [
        %{"kind" => "wealth_key_figures", "size" => "row", "col" => 1, "row" => 1},
        %{"kind" => "key_figures", "size" => "row", "col" => 1, "row" => 2}
      ])

    doc = page(conn, board)
    assert repeated(ids(Floki.find(doc, "[id]"))) == []

    frames = Floki.find(doc, "section[data-widget-kind]")
    assert length(frames) == 2
    assert frames |> ids() |> Enum.uniq() |> length() == 2
  end

  test "every kind in every size draws ids that never repeat on a page or across kinds",
       %{conn: conn} do
    seed()

    pages =
      grid_items()
      |> layouts()
      |> Enum.with_index(1)
      |> Enum.map(fn {layout, n} ->
        assert length(layout) <= Layout.max_items()
        {n, page(conn, dashboard!("Alle #{n}", layout))}
      end)

    drawn =
      pages
      |> Enum.flat_map(fn {_n, doc} -> Floki.find(doc, "section[data-widget-kind]") end)
      |> length()

    assert drawn == length(grid_items())

    for {n, doc} <- pages do
      assert repeated(ids(Floki.find(doc, "[id]"))) == [],
             "page #{n} draws an id twice: #{inspect(repeated(ids(Floki.find(doc, "[id]"))))}"
    end

    shared =
      pages
      |> Enum.flat_map(fn {_n, doc} -> ids_by_kind(doc) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {id, kinds} -> {id, Enum.uniq(kinds)} end)
      |> Enum.filter(fn {_id, kinds} -> length(kinds) > 1 end)

    assert shared == [], "an id drawn by two kinds: #{inspect(shared)}"
  end
end
