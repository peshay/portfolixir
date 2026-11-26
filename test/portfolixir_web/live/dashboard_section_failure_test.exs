defmodule PortfolixirWeb.DashboardSectionFailureTest do
  # Sprint 32 closing act, PR 2 (coverage of the section widgets' failure
  # state, W1–W4): a section widget whose background read fails says so in
  # its own words and the page stays up. The reads fail here because
  # columns they read are renamed inside the test's own transaction (rolled
  # back with it), after the data is seeded and before the page mounts, as
  # `dashboard_trades_card_failure_test.exs` does for the trades card: the
  # page's own mount still reads, each widget's read fails. Synchronous: the
  # renames lock the tables for the test, so it cannot share a file with
  # the async widget tests. Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Dashboards
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Repo

  # Each kind with the size it is drawn at and the line its failure reads.
  @failures [
    {"wealth_key_figures", "row", "key-figures-failed", "Couldn't load the key figures."},
    {"summary_line", "row", "summary-line-failed", "Couldn't load the key figures."},
    {"contribution", "L", "contribution-widget-failed", "Couldn't load the contributions."},
    {"positions", "row", "positions-failed", "Couldn't load the positions."},
    {"cash_accounts", "row", "cash-failed", "Couldn't load the cash accounts."},
    {"allocation", "row", "allocation-failed", "Couldn't load the allocation."},
    {"snapshot_comparison", "row", "snapshot-comparison-failed", "Could not load the comparison"},
    {"snapshot_list", "row", "snapshot-list-failed", "Couldn't load the snapshots."},
    {"own_rules", "row", "own-rules-failed", "Couldn't load the rules."},
    {"key_figures", "row", "key_figures-failed", "Couldn't load the risk figures."},
    {"top_holdings", "row", "top_holdings-failed", "Couldn't load the risk figures."},
    {"concentration", "row", "concentration-failed", "Couldn't load the risk figures."},
    {"asset_class_limits", "row", "asset_class_limits-failed", "Couldn't load the risk figures."}
  ]

  # User story:
  # As the operator whose dashboard holds Wealth's and Risk's sections,
  # I want a section whose read fails to say so in its widget,
  # so that a failed read is never mistaken for an empty one or for one
  # still loading, and the rest of the page stays usable.
  #
  # Acceptance criteria:
  # - With the valuation's, the snapshots', the rules' and the categories'
  #   reads failing, each section widget lands its failure and draws its
  #   own failure line: „Couldn't load the key figures.“ (in „Kennzahlen“
  #   and, since the S32 closing act's coverage pass, „Kennzahlen-Zeile“),
  #   „… the
  #   contributions.“, „… the positions.“, „… the cash accounts.“, „… the
  #   allocation.“, „Could not load the comparison“, „Couldn't load the
  #   snapshots.“, „… the rules.“, and „Couldn't load the risk figures.“
  #   in each of the four lens widgets.
  # - No widget is left waiting on its skeleton, and the page stays up.
  test "a section whose read fails says so in its widget", %{conn: conn} do
    today = Clock.today()
    world = base_world(name: "Fehler", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", Date.add(today, -100))
    security = create_security!(name: "Quickturn Test Retail")
    buy!(world, security, quantity: "2", price: "100", date: Date.add(today, -90))
    put_quotes!(security, [{Date.add(today, -90), "100"}, {today, "110"}])
    owner = Actor.owner_ui()
    {:ok, _} = Snapshots.create_snapshot(owner, %{name: "Vorher", as_of: Date.add(today, -50)})
    {:ok, _} = Classifications.create_classification(owner, %{name: "Strategy"})

    layout =
      @failures
      |> Enum.with_index()
      |> Enum.map(fn {{kind, size, _role, _line}, index} ->
        %{"kind" => kind, "size" => size, "col" => 1, "row" => 1 + index * 4}
      end)

    {:ok, dashboard} =
      Dashboards.create_dashboard(owner, %{"name" => "Fehler", "layout" => layout})

    for sql <- [
          "ALTER TABLE cash_accounts RENAME COLUMN liquidity_role TO liquidity_role_unreadable",
          "ALTER TABLE depot_snapshots RENAME COLUMN view_id TO view_id_unreadable",
          "ALTER TABLE policy_rules RENAME COLUMN name_author TO name_author_unreadable",
          "ALTER TABLE classification_categories RENAME COLUMN color TO color_unreadable"
        ],
        do: Repo.query!(sql)

    capture_log(fn ->
      {:ok, view, _html} = live(conn, "/dashboards/#{dashboard.id}")
      render_async(view)
      doc = view |> render() |> Floki.parse_document!()

      for {kind, _size, role, line} <- @failures do
        [widget] = Floki.find(doc, "section.dashboard-widget[data-widget-kind='#{kind}']")

        assert widget
               |> Floki.find("[data-role='#{role}']")
               |> Floki.text()
               |> String.trim() == line,
               kind

        assert Floki.find(widget, "[aria-busy='true']") == [], kind
      end

      assert Process.alive?(view.pid)
    end)
  end
end
