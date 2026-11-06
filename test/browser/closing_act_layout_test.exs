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

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications

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
end
