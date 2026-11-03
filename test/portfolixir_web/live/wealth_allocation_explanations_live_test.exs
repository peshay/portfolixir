defmodule PortfolixirWeb.WealthAllocationExplanationsLiveTest do
  # Board `ux-design-2026-11-03-sprint23-i1` on Wealth → Allokation (Sprint
  # 23 Lane I; idea I1, variant R): the section has no method sentence to
  # move, so its repair is the findings block. The problem leads, every
  # finding clamps, and each remedy link leaves its sentence for the note's
  # actions as a command of its own (③ ⑤; found while drawing 6). The
  # „Daten als Tabelle“ disclosure keeps its open state across a patch
  # (⑦, #1339), and the twin accounts' portfolio tags load in the
  # background read, not in the page process (#1366). async: false: the
  # tag test traces every process the page spawns. Every name is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets
  alias Portfolixir.WorldFixtures
  alias PortfolixirWeb.AccountNames

  # World ETF filed in Core, then moved to Edge: its position target stays
  # filed in Core (stale) and steers Core against Core's own weight
  # (conflict), so Core counts its 50 % and Edge its 60 %: 110 %
  # (overshoot).
  defp seed_world do
    world =
      WorldFixtures.base_world(name: "Demo Portfolio", cash_name: "Giro", depot_name: "Depot")

    security = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
    start = Date.add(Date.utc_today(), -10)

    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, security, quantity: "8", price: "100", date: start)
    WorldFixtures.put_quotes!(security, [{start, "100"}, {Date.utc_today(), "110"}])

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    [core, edge] =
      for {name, color} <- [{"Core", "#2563eb"}, {"Edge", "#dc2626"}] do
        {:ok, category} =
          Classifications.create_category(Actor.owner_ui(), %{
            classification_id: classification.id,
            name: name,
            color: color
          })

        category
      end

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, core.id)

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, classification.id, [
        %{"category_id" => core.id, "target_weight" => "0.7"},
        %{"category_id" => edge.id, "target_weight" => "0.6"},
        %{"category_id" => core.id, "security_id" => security.id, "target_weight" => "0.5"}
      ])

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), security.id, classification.id, edge.id)

    world
  end

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> squish()
  end

  defp roles(view, selector) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.attribute("data-role") |> List.first()))
  end

  # User story (board `ux-design-2026-11-03-sprint23-i1`, Allokation ③ ⑤;
  # found while drawing 6):
  # As the operator reading a plan's findings above the drift table,
  # I want the problem first, each finding cut to its first lines, and each
  # remedy as a link of its own under the text,
  # so that the remedy stays one press away when the text is clamped, and
  # no sentence ends in half a link.
  #
  # Acceptance criteria:
  # - The findings region holds, in order, the target conflict (problem),
  #   the overshoot and the stale target (attention); each clamps
  #   (`data-note--clamped`, its own id).
  # - The overshoot's text reads "The plan's top-level targets sum to
  #   110.0 % — more than 100 %. Drift keeps steering against the stored
  #   weights." and its actions hold "Trim the plan on the Classifications
  #   page" (/classifications); no link sits in the text.
  # - The conflict's actions hold "Align the position targets and the
  #   category weight on the Classifications page"; the stale target's text
  #   ends "It keeps counting there until it is re-filed." and its actions
  #   hold "Re-file it on the Classifications page".
  # - In German: „… Die Drift steuert weiter gegen die gespeicherten
  #   Gewichte.“ and „Plan auf der Klassifizierungsseite kürzen“.
  test "the plan's findings: the problem leads, each clamps, its remedy in the actions",
       %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    region = "#portfolio-allocation [role='status'].allocation-findings"

    assert roles(view, region <> " > *") == [
             "target-conflict-note",
             "plan-overshoot-note",
             "stale-target-note"
           ]

    for role <- ["target-conflict-note", "plan-overshoot-note", "stale-target-note"] do
      note = region <> " > .data-note--clamped[data-role='#{role}'][id]"
      assert has_element?(view, note)
      refute has_element?(view, note <> " .data-note__text a")
    end

    overshoot = region <> " > [data-role='plan-overshoot-note']"

    assert text(view, overshoot <> " .data-note__text") ==
             "The plan's top-level targets sum to 110.0 % — more than 100 %. Drift keeps steering against the stored weights."

    assert text(view, overshoot <> " .data-note__actions a[href='/classifications']") ==
             "Trim the plan on the Classifications page"

    conflict = region <> " > [data-role='target-conflict-note']"

    assert text(view, conflict <> " .data-note__text") ==
             "The position targets steer in Core: their sum overrides the stored category weight."

    assert text(view, conflict <> " .data-note__actions a[href='/classifications']") ==
             "Align the position targets and the category weight on the Classifications page"

    stale = region <> " > [data-role='stale-target-note']"

    assert text(view, stale <> " .data-note__text") ==
             "A position target filed in Core is stale: its security was moved or unassigned. It keeps counting there until it is re-filed."

    assert text(view, stale <> " .data-note__actions a[href='/classifications']") ==
             "Re-file it on the Classifications page"

    {:ok, de_view, _html} = live(conn, "/portfolio?tab=allocation&locale=de")
    render_async(de_view)

    assert text(de_view, overshoot <> " .data-note__text") ==
             "Die Top-Level-Ziele des Plans summieren sich auf 110,0 % — mehr als 100 %. Die Drift steuert weiter gegen die gespeicherten Gewichte."

    assert text(de_view, overshoot <> " .data-note__actions a") ==
             "Plan auf der Klassifizierungsseite kürzen"

    assert text(de_view, stale <> " .data-note__text") =~
             ~r/Es zählt dort weiter, bis es neu hinterlegt wird\.$/

    assert text(de_view, stale <> " .data-note__actions a") ==
             "Auf der Klassifizierungsseite neu hinterlegen"

    assert text(de_view, conflict <> " .data-note__actions a") ==
             "Positionsziele und Kategoriegewicht auf der Klassifizierungsseite angleichen"
  end

  # User story (#1339, board ⑦):
  # As the operator working in the allocation's table,
  # I want „Daten als Tabelle“ to stay open when I expand a category in it,
  # so that the rows I am reading do not fold shut under me.
  #
  # Acceptance criteria:
  # - The disclosure carries an id and the shell's `DisclosureState` hook,
  #   which puts back the `open` a LiveView patch strips (the hook is the
  #   shell's, pinned by its own tests); it still holds the drift table.
  test "„Daten als Tabelle“ keeps its open state across a patch (#1339)", %{conn: conn} do
    seed_world()

    {:ok, view, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(view)

    disclosure =
      "details#allocation-disclosure[data-role='allocation-disclosure'][phx-hook='DisclosureState']"

    assert has_element?(view, disclosure <> " table.drift-table")

    view |> element("[data-role='toggle-all-categories']") |> render_click()
    assert has_element?(view, disclosure)
  end

  # User story (#1366's third line; Sprint 22 U2 on #1333):
  # As the operator whose Wealth page lands its valuation,
  # I want the twin accounts' portfolio tags read inside the background
  # load, beside the valuation they qualify,
  # so that the page process answers my clicks instead of reading three
  # account lists each time the valuation lands.
  #
  # Acceptance criteria:
  # - `AccountNames.load_portfolio_tags/0` runs while the page loads, but
  #   never in the LiveView's own process.
  test "the twin accounts' portfolio tags load in the background read", %{conn: conn} do
    seed_world()

    collector = spawn_link(fn -> collect([]) end)
    mfa = {AccountNames, :load_portfolio_tags, 0}
    Code.ensure_loaded!(AccountNames)
    :erlang.trace_pattern(mfa, true, [:global])
    :erlang.trace(:new_processes, true, [:call, {:tracer, collector}])

    view =
      try do
        {:ok, view, _html} = live(conn, "/portfolio")
        render_async(view)
        view
      after
        :erlang.trace(:new_processes, false, [:call])
        :erlang.trace_pattern(mfa, false, [:global])
      end

    send(collector, {:callers, self()})
    callers = receive do: ({:callers, callers} -> callers)

    assert callers != [], "the portfolio tags were never loaded"
    refute view.pid in callers
  end

  defp collect(callers) do
    receive do
      {:trace, pid, :call, {AccountNames, :load_portfolio_tags, []}} -> collect([pid | callers])
      {:callers, to} -> send(to, {:callers, callers})
    end
  end
end
