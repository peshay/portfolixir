defmodule PortfolixirWeb.CashflowFacetsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.WorldFixtures

  # User story (#787, the review's D5 and A3; EXPERIENCE.md → Amendment
  # 2026-09-12 → UX-DR21 extended, IA sharpened):
  # As a local portfolio maintainer opening a Cash-flow facet,
  # I want the page subtitle to name the facet and the facet to open with
  # one basis line — currency · what is aggregated · scope — plus one ⓘ for
  # exclusions and method,
  # so that no facet opens with a paragraph and none stands under another
  # facet's subtitle.
  #
  # Acceptance criteria:
  # - Each facet's page subtitle names the facet.
  # - Each facet carries one basis line and one focusable ⓘ, and no
  #   free-standing paragraph above its first table.
  @facets [
    {"/cashflow", "Received dividends and interest", "dividends and interest · this portfolio"},
    {"/cashflow?tab=realized", "Realized gains and losses from sales",
     "FIFO-matched sales · all portfolios"},
    {"/cashflow?tab=flows", "Deposits and withdrawals",
     "external deposits and withdrawals · all portfolios"},
    {"/cashflow?tab=costs", "Fees and taxes", "fees and taxes at overview level · all portfolios"}
  ]

  test "every facet names itself in the subtitle and opens with one basis line and its ⓘ",
       %{conn: conn} do
    world = WorldFixtures.base_world()
    share = WorldFixtures.create_security!(name: "Share Co", ticker: "SHR")
    WorldFixtures.deposit!(world, "1000", ~D[2026-02-01])
    WorldFixtures.buy!(world, share, quantity: "2", price: "100", date: ~D[2026-02-10])

    for {path, subtitle, basis} <- @facets do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, ".topbar-page p", subtitle), path
      assert has_element?(view, "[data-role='facet-basis']", "Amounts in EUR"), path
      assert has_element?(view, "[data-role='facet-basis']", basis), path
      assert has_element?(view, "[data-role='facet-basis'] details.metric-tooltip summary"), path
      refute has_element?(view, "section.workspace-section > p.muted"), path
    end
  end
end
