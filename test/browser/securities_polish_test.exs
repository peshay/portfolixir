defmodule PortfolixirWeb.Browser.SecuritiesPolishTest do
  # The polish pass on "Securities and the security page" (#1365, Sprint 26
  # V1 under the plan's D-10: a story that touches a screen fixes its
  # lines). Four lines: where a dialog opened from a row menu gives the
  # focus back (#1340, on Securities, Accounts and Buckets), how the thesis
  # card breaks its longest label, and the Termine entry's meta line. Focus,
  # computed styles and the painted text need a browser: LiveViewTest runs
  # no client script and lays nothing out. This test boots the endpoint on a
  # free loopback port and drives Chromium through `securities_polish.js`
  # with Playwright, as `PortfolixirWeb.Browser.InfoTipsClickAwayTest` does.
  #
  # Excluded from the test job (test/test_helper.exs): it needs Node, the
  # Playwright test/browser/package-lock.json pins and its Chromium, which
  # CI's `browser` job installs. Run it with
  #
  #     mix test test/browser --only browser
  #
  # async: false -- the sandbox is shared, so the LiveView processes the
  # browser's requests start read the world this test seeds. Synthetic data
  # only, no external network: the browser talks to 127.0.0.1, and the
  # event's source link is never followed.
  use PortfolixirWeb.ConnCase, async: false

  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.Events

  @moduletag :browser
  @moduletag timeout: 180_000

  @script Path.expand("securities_polish.js", __DIR__)

  setup do
    server =
      PortfolixirWeb.TestListener.start!(
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

  # A booked security (its delete is refused, so "Cannot delete" opens) with
  # a thesis and a dated event; the booking's depot (refused the same way on
  # Accounts); and a view on Buckets.
  defp polish_world do
    world = base_world()
    security = create_security!(name: "Harbor Polish AG", ticker: "HPAG")
    buy!(world, security, quantity: "5", price: "100", date: ~D[2026-10-01])

    {:ok, _thesis} =
      Knowledge.append_note(Actor.owner_ui(), %{
        security_id: security.id,
        author: "agent",
        kind: "thesis",
        body: "Order intake holds through 2027.",
        source_quality: "primary",
        conviction: "high",
        invalidation_condition: "order intake below plan for two quarters",
        time_stop: ~D[2027-06-30],
        as_of: ~D[2026-10-01]
      })

    {:ok, _event} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: security.id,
        kind: "earnings",
        date: ~D[2026-11-20],
        timing: "estimated",
        source_quality: "primary",
        source_url: "https://ir.example.org/calendar",
        checked_at: ~D[2026-11-04]
      })

    {:ok, view} = Buckets.create_view(Actor.owner_ui(), %{name: "Core view"})

    %{security: security, depot: world.depot, view: view}
  end

  # User story (#1365, the polish pass on Securities and the security page):
  # As the operator working the securities list and a security's page by
  # keyboard and by eye,
  # I want a dialog opened from a row menu to give the focus back to that
  # row's menu button, the thesis card's longest label to break where a
  # word may break, and a Termine entry's meta line to end the entry and
  # read as two facts,
  # so that closing a dialog does not send me back to the top of the page,
  # and the research tabs read as the rest of the app does.
  #
  # Acceptance criteria:
  # - #1340: Escape, the × and Cancel on "Cannot delete" (Securities and
  #   Accounts), Escape on "Manage logo" and on Buckets' "Edit buckets",
  #   each opened from a row menu, return the focus to that row's kebab,
  #   at 1200 px and at 390 px — never to <body>.
  # - Thesis card at 1200 px: the label „Invalidierungsbedingung“ is set to
  #   break at a syllable (`hyphens: auto` under the page's `lang="de"`).
  # - Termine: the entry's meta paragraph has no margins of its own.
  # - Termine: the meta line reads „Quelle · Zuletzt geprüft 04.11.2026“.
  test "row-menu dialogs return the focus to the kebab, and the research tabs read cleanly",
       %{base_url: base_url} do
    %{security: security, depot: depot, view: view} = polish_world()

    args =
      Jason.encode!(%{
        base_url: base_url,
        security_id: security.id,
        depot_id: depot.id,
        view_id: view.id
      })

    {output, status} = System.cmd("node", [@script, args], stderr_to_stdout: true)

    assert status == 0, "the browser run failed:\n" <> output

    result =
      output
      |> String.split("\n", trim: true)
      |> List.last()
      |> Jason.decode!()

    assert result == %{"ok" => true}, "the browser found:\n" <> output
  end
end
