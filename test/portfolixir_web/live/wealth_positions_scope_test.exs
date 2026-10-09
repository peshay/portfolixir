defmodule PortfolixirWeb.WealthPositionsScopeTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications

  # Two portfolios, the second with base USD (#1124's review seed in small):
  # the first holds Alpha Works in its EUR depot, the second Bravo Freight in
  # its USD depot. One bucket tags the second depot, and the view "Overseas"
  # includes that bucket only, so it holds Bravo Freight and nothing else.
  setup do
    Classifications.ensure_builtins()

    home = base_world(name: "Home", cash_name: "Home Cash", depot_name: "Home Depot")

    overseas =
      base_world(
        name: "Overseas",
        currency: "USD",
        cash_name: "Overseas Cash",
        depot_name: "Overseas Depot"
      )

    alpha = create_security!(name: "Alpha Works", ticker: "ALPW")
    bravo = create_security!(name: "Bravo Freight", ticker: "BRVF", currency: "USD")

    buy!(home, alpha, quantity: "10", price: "100", date: ~D[2026-01-05])
    buy!(overseas, bravo, quantity: "4", price: "50", date: ~D[2026-01-05], currency: "USD")
    put_quote!(alpha, ~D[2026-01-06], "110")
    put_quote!(bravo, ~D[2026-01-06], "55")

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Overseas tag"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), overseas.depot, [bucket.id])

    {:ok, view} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Overseas view", include_all: false})

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), view, [bucket.id], [])

    %{alpha: alpha, bravo: bravo, view: view}
  end

  defp position?(lv, security) do
    has_element?(
      lv,
      ~s(#holdings-positions-table [data-role="holdings-position"][data-security-id="#{security.id}"])
    )
  end

  # User story (#1124; Sprint 20 plan D-8; ADR-0024):
  # As a local portfolio maintainer with a second portfolio,
  # I want Wealth's positions table to read the scope the rest of the page
  # reads,
  # so that a holding the page's notes and totals count is a row I can find,
  # and the table and the notes never disagree on one page.
  #
  # Acceptance criteria:
  # - Under Everything the table lists every portfolio's holdings, the second
  #   portfolio's included.
  # - Under a view it lists the positions the view holds, and no others.
  # - The anatomy does not change: the page's scope line names the scope, and
  #   the table keeps its heading and basis line.
  test "under Everything the positions table lists every portfolio's holdings",
       %{conn: conn, alpha: alpha, bravo: bravo} do
    conn = get(conn, "/portfolio?view=total")
    {:ok, lv, _html} = live(conn, "/portfolio?view=total")
    render_async(lv)

    assert position?(lv, alpha)
    assert position?(lv, bravo)
  end

  test "under a view the positions table lists the positions the view holds",
       %{conn: conn, alpha: alpha, bravo: bravo, view: view} do
    conn = get(conn, "/portfolio?view=#{view.id}")
    {:ok, lv, _html} = live(conn, "/portfolio?view=#{view.id}")
    html = render_async(lv)

    assert html =~ "Scoped to view: Overseas view"
    assert position?(lv, bravo)
    refute position?(lv, alpha)

    assert lv |> element(~s([data-role="positions-basis"])) |> render() =~
             "One row per depot and security, valued at the latest stored price."
  end

  # User story (#1124; the page's view-gone fallback):
  # As a local portfolio maintainer whose view was deleted in another tab,
  # I want the positions table to follow the page when it falls back to
  # Everything,
  # so that the rows match the scope the notice says the page now shows.
  #
  # Acceptance criteria:
  # - After the page degrades to Everything, the table lists every
  #   portfolio's holdings again.
  test "when the view is deleted the table follows the page back to Everything",
       %{conn: conn, alpha: alpha, bravo: bravo, view: view} do
    conn = get(conn, "/portfolio?view=#{view.id}")
    {:ok, lv, _html} = live(conn, "/portfolio?view=#{view.id}")
    render_async(lv)
    refute position?(lv, alpha)

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), view)

    # The period switch reloads the scoped performance under the stale id,
    # which degrades the page to Everything.
    lv |> element(~s(button[phx-value-period="ytd"])) |> render_click()
    html = render_async(lv)

    assert html =~ "The selected view no longer exists"
    assert position?(lv, alpha)
    assert position?(lv, bravo)
  end
end
