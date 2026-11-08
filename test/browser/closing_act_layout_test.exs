defmodule PortfolixirWeb.Browser.ClosingActLayoutTest do
  # Where Sprint 26's closing act found a box in the wrong place (the design
  # critic's and the UAT persona's findings), in a real browser. LiveViewTest
  # renders the server's markup and applies no CSS, so this test boots the
  # endpoint on a free loopback port and drives Chromium through
  # `closing_act_layout.js` with Playwright, as
  # `PortfolixirWeb.Browser.InfoTipsPlacementTest` does.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias PortfolixirWeb.PreferenceCookieHelpers

  @moduletag :browser
  @moduletag timeout: 120_000

  @script Path.expand("closing_act_layout.js", __DIR__)

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: PortfolixirWeb.Endpoint,
         scheme: :http,
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    # "localhost", the endpoint's configured host, so the LiveView socket's
    # origin check passes.
    %{base_url: "http://localhost:#{port}"}
  end

  defp run!(case_name, base_url, ids) do
    argument = Jason.encode!(Map.merge(ids, %{base_url: base_url, case: case_name}))
    {output, status} = System.cmd("node", [@script, argument], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    output
    |> String.split("\n", trim: true)
    |> List.last()
    |> Jason.decode!()
  end

  # User story (Sprint 26 closing act, design critic V4):
  # As the operator deleting a classification or one of its categories,
  # I want the delete dialog to open in the middle of the screen,
  # so that it reads as the app's modal and not as a box stuck to the page's
  # left edge.
  #
  # Acceptance criteria:
  # - At 1200 px the classification's and the category's delete dialogs on
  #   /classifications/:id lie centred: their left and right distances to
  #   the viewport differ by at most 1 px.
  test "the classification page's delete dialogs open centred", %{base_url: base_url} do
    _world = base_world(name: "Dialog Portfolio")
    owner = Actor.owner_ui()
    {:ok, classification} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(owner, %{
        classification_id: classification.id,
        name: "Growth"
      })

    security = create_security!(name: "Northwind Harbour Logistics AG", ticker: "NHL")
    {:ok, _} = Classifications.assign_security(owner, security.id, classification.id, category.id)

    result =
      run!("delete_dialogs", base_url, %{
        classification_id: classification.id,
        category_id: category.id
      })

    assert result == %{"ok" => true}
  end

  # User story (Sprint 26 closing act, design critic V3 and V1):
  # As the operator reading a security's Trades tab and its Predictions tab,
  # I want "After the sale" to end where its table ends and an ⓘ to open
  # whole in fullscreen,
  # so that no blank band pushes the legend away, no table scrolls inside
  # the page, and no line of the computation basis is cut off.
  #
  # Acceptance criteria:
  # - On /securities/:id?tab=trades at 1200 px, "After the sale"'s table
  #   wrapper is as tall as its table (2 px of borders allowed), the legend
  #   follows it within 16 px, and the wrapper does not scroll on its own;
  #   the same in fullscreen.
  # - In fullscreen, the Predictions tab's ⓘ opens with no box between it
  #   and the scrolling pane cutting its panel.
  test "After the sale ends with its table, and a fullscreen tab's ⓘ opens whole",
       %{base_url: base_url} do
    world = base_world(name: "Trades Portfolio")
    security = create_security!(name: "Synthetic Sold Fund", ticker: "SSF")

    put_quotes!(security, [
      {~D[2025-01-02], "60"},
      {~D[2025-07-09], "71"},
      {~D[2025-08-08], "72"},
      {~D[2025-10-09], "73"}
    ])

    buy!(world, security, quantity: "20", price: "60", date: ~D[2025-01-02])
    sell!(world, security, quantity: "20", price: "71", date: ~D[2025-07-09])

    assert run!("trades_tab", base_url, %{security_id: security.id}) == %{"ok" => true}
  end

  # User story (Sprint 26 closing act, design critic on P1):
  # As the operator on a phone with the privacy switch in the top bar,
  # I want the page's title to show whole,
  # so that "Konten & Depots" does not read "Konten & D…".
  #
  # Acceptance criteria:
  # - At 390 px, in German with the privacy mode on, the top bar's title on
  #   /securities, /transactions, /portfolios and /journal is not cut
  #   (`#app-topbar-title` scrollWidth ≤ clientWidth), and the page does not
  #   scroll sideways.
  test "the top bar's longest titles fit at 390 px beside the privacy switch",
       %{base_url: base_url} do
    _world = base_world(name: "Phone Portfolio")

    cookies =
      for {name, value} <- [{"portfolixir_locale", "de"}, {"portfolixir_privacy", "on"}] do
        [
          name,
          name
          |> PreferenceCookieHelpers.cookie_pair(value)
          |> String.split("=", parts: 2)
          |> List.last()
        ]
      end

    result =
      run!("topbar_titles", base_url, %{
        cookies: cookies,
        paths: ["/securities", "/transactions", "/portfolios", "/journal"]
      })

    assert result == %{"ok" => true}
  end

  # User story (I23; Sprint 27's closing act, design critic D1, D2 and D5):
  # As the operator reading the stacked chart on a phone,
  # I want each legend row's figures beside its name and the axis readable,
  # so that the value, share and change do not scroll out of the legend.
  #
  # Acceptance criteria:
  # - At 390 px, on /portfolio?level=category and on a drilled category
  #   (/portfolio?level=security&category=…) whose securities carry long
  #   names, the legend does not scroll on its own, every figure cell lies
  #   inside the legend's box and the viewport, and the page does not scroll
  #   sideways.
  # - The stack's axis labels are 9 CSS px.
  # - A drill from the legend by keyboard leaves the focus on the
  #   breadcrumb's current item (D5).
  test "the stacked chart's legend keeps its figures in view at 390 px", %{base_url: base_url} do
    world = base_world(name: "Phone Stack", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "100000", ~D[2025-01-02])
    owner = Actor.owner_ui()
    {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Growth"})

    for {name, price} <- [
          {"Northwind Harbour Logistics International Holdings AG", "1234.56"},
          {"Synthetic Global Infrastructure Opportunities Fund", "987.65"}
        ] do
      security = create_security!(name: name)
      buy!(world, security, quantity: "12", price: price, date: ~D[2025-01-02])
      put_quotes!(security, [{~D[2025-01-02], price}])
      {:ok, _} = Classifications.assign_security(owner, security.id, tree.id, category.id)
    end

    result =
      run!("stack_phone", base_url, %{
        paths: [
          "/portfolio?level=category&tree=#{tree.id}",
          "/portfolio?level=security&tree=#{tree.id}&category=#{category.id}"
        ]
      })

    assert result == %{"ok" => true}
  end
end
