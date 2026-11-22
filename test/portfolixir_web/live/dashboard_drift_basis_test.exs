defmodule PortfolixirWeb.DashboardDriftBasisTest do
  # Sprint 31 closing act, money lens: what „Allokation und Drift“ says
  # its drift is measured against (MO2) and which rows the dashboard's two
  # drift widgets count as off target (MO4). Synthetic data only.
  #
  # group: :dashboards -- a create takes the advisory lock that counts the
  # dashboards (`Portfolixir.LockTable` row 30).
  use PortfolixirWeb.ConnCase, async: true, group: :dashboards

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.Targets

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp loaded(conn, path \\ "/") do
    {:ok, view, _html} = live(conn, path)
    render_async(view)
    view |> render() |> Floki.parse_document!()
  end

  defp category!(tree, name, parent \\ nil) do
    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        parent_id: parent && parent.id,
        name: name
      })

    category
  end

  # 3,000 deposited, 1,000 each in Alpha and Beta: a third each, a third
  # cash.
  defp two_thirds_invested do
    world = base_world()
    today = Clock.today()
    alpha = create_security!(name: "Alpha Works", ticker: "ALW")
    beta = create_security!(name: "Beta Lines", ticker: "BTL")
    deposit!(world, "3000", Date.add(today, -40))
    buy!(world, alpha, quantity: "10", price: "100", date: Date.add(today, -30))
    buy!(world, beta, quantity: "10", price: "100", date: Date.add(today, -30))
    put_quotes!(alpha, [{today, "100"}])
    put_quotes!(beta, [{today, "100"}])
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Steering"})
    Map.merge(world, %{alpha: alpha, beta: beta, tree: tree})
  end

  # User story:
  # As the operator whose plan allocates less than 100 % at the top level,
  # I want „Allokation und Drift“ to show the target its drift is measured
  # against, and to say so,
  # so that a row's Ist, Soll and Drift add up and its arithmetic does not
  # read as the opposite of the row.
  #
  # Acceptance criteria (ADR-0040 §2; money lens MO2):
  # - Core 30 %, Satellite 10 %, no cash target (Σ 40 %): each row's Soll
  #   is the target ÷ 40 %, so Ist − Soll is the drift the row shows.
  #   Python decimal, prec 34: Core 1000 / 3000 = 0.3333…, Soll 0.3 / 0.4
  #   = 0.75, drift −0.41666…; Satellite Soll 0.1 / 0.4 = 0.25, drift
  #   +0.08333…; Core's arithmetic −(−0.41666… × 3000) = +1,250.00.
  # - The basis line names Σ 40.0 % and that target and drift are against
  #   the allocated portion; the ⓘ says how the divided target is made.
  # - A full plan (Σ 100 %) shows its targets as entered: the D4 test.
  test "a plan under 100 % shows the target its drift is measured against", %{conn: conn} do
    world = two_thirds_invested()
    core = category!(world.tree, "Core")
    satellite = category!(world.tree, "Satellite")

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), world.alpha.id, world.tree.id, core.id)

    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        world.beta.id,
        world.tree.id,
        satellite.id
      )

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, world.tree.id, [
        %{"category_id" => core.id, "target_weight" => "0.3"},
        %{"category_id" => satellite.id, "target_weight" => "0.1"}
      ])

    doc = loaded(conn)
    widget = "#dashboard-allocation-drift"
    row = fn name -> Floki.find(doc, "#{widget} [data-form='wide'] [data-name='#{name}']") end

    assert text(Floki.find(row.("Core"), "[data-role='drift-actual']")) == "33.3%"
    assert text(Floki.find(row.("Core"), "[data-role='drift-target']")) == "75.0%"
    assert text(Floki.find(row.("Core"), "[data-role='drift-points']")) == "−41.7 pp"
    assert text(Floki.find(row.("Satellite"), "[data-role='drift-target']")) == "25.0%"
    assert text(Floki.find(row.("Satellite"), "[data-role='drift-points']")) == "+8.3 pp"

    assert text(Floki.find(doc, "#{widget} [data-role='drift-arithmetic'][data-name='Core']")) ==
             "Core ≈ +1,250.00 EUR"

    compact =
      Floki.find(doc, "#{widget} [data-compact-role='allocation-drift-row'][data-name='Core']")

    assert text(Floki.find(compact, ".widget-row__sub")) =~ "target 75.0%"

    basis = text(Floki.find(doc, "#{widget} [data-role='allocation-drift-basis']"))
    assert basis =~ "Σ target top level 40.0%"
    assert basis =~ "against the allocated portion"

    assert text(Floki.find(doc, "#{widget} [data-role='section-info']")) =~
             "divided by that sum"
  end
end
