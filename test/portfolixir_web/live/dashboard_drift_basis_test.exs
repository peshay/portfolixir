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

  defp off_target(doc),
    do: Floki.find(doc, "#dashboard-attention [data-form='wide'] [data-role='drift-alert']")

  defp arithmetic(doc),
    do: Floki.find(doc, "#dashboard-allocation-drift [data-role='drift-arithmetic']")

  defp foot(doc), do: text(Floki.find(doc, "#dashboard-allocation-drift .widget__foot"))

  # User story:
  # As the operator reading the template's two drift widgets side by side,
  # I want „Abseits des Ziels“ and „Allokation und Drift“ to count the
  # same rows as off target, by the rule the API's min_drift= applies,
  # so that the two widgets of one dashboard never disagree.
  #
  # Acceptance criteria (money lens MO4):
  # - One predicate, `Allocation.drift_at_least?/2` at 5 pp, inclusive as
  #   the API is, over every level of the tree and cash in both widgets:
  #   a subcategory beyond its target is counted by both, and a drift of
  #   exactly 5.0 pp too (Python decimal: 1000 / 2000 − 0.45 = 0.05).
  # - Both say the rule: „±5 pp or more“, every level of the tree.
  test "both drift widgets count the same rows: every level, inclusive at 5 pp",
       %{conn: conn} do
    world = two_thirds_invested()
    equity = category!(world.tree, "Equity")
    core = category!(world.tree, "Core", equity)
    satellite = category!(world.tree, "Satellite", equity)

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
        %{"category_id" => core.id, "target_weight" => "0.5"},
        %{"category_id" => satellite.id, "target_weight" => "0.1"}
      ])

    {:ok, _} =
      Portfolixir.Portfolios.set_cash_target(
        Actor.owner_ui(),
        world.portfolio,
        Decimal.new("0.4")
      )

    doc = loaded(conn)
    names = fn nodes -> nodes |> Enum.map(&text/1) |> Enum.map(&hd(String.split(&1))) end

    assert Enum.sort(names.(off_target(doc))) == Enum.sort(names.(arithmetic(doc)))
    assert length(arithmetic(doc)) == 3
    assert foot(doc) =~ "3 at ±5 pp or more"

    assert text(Floki.find(doc, "#dashboard-attention [data-role='attention-explainer']")) =~
             "±5 pp or more from their target weight, at every level of the tree"
  end

  test "a drift of exactly 5 pp is off target in both widgets, as min_drift=0.05 reads it",
       %{conn: conn} do
    world = base_world()
    today = Clock.today()
    alpha = create_security!(name: "Alpha Works", ticker: "ALW")
    deposit!(world, "2000", Date.add(today, -40))
    buy!(world, alpha, quantity: "10", price: "100", date: Date.add(today, -30))
    put_quotes!(alpha, [{today, "100"}])
    {:ok, tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Steering"})
    core = category!(tree, "Core")
    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), alpha.id, tree.id, core.id)

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), world.portfolio.id, tree.id, [
        %{"category_id" => core.id, "target_weight" => "0.45"}
      ])

    {:ok, _} =
      Portfolixir.Portfolios.set_cash_target(
        Actor.owner_ui(),
        world.portfolio,
        Decimal.new("0.55")
      )

    api =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")
      |> get(
        "/api/v1/portfolios/#{world.portfolio.id}/allocation" <>
          "?classification_id=#{tree.id}&min_drift=0.05"
      )
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(api["categories"], & &1["name"]) == ["Core"]

    doc = loaded(conn)
    assert length(off_target(doc)) == 2
    assert length(arithmetic(doc)) == 2
  end

  # User story:
  # As the operator with two portfolios,
  # I want each drift widget to say which portfolios it reads,
  # so that two counts of two scopes are read as two scopes.
  #
  # Acceptance criteria (money lens MO4):
  # - „Allokation und Drift“ names the portfolio whose allocation it
  #   draws; „Abseits des Ziels“ says it reads every portfolio.
  # - With one portfolio neither names it.
  test "with two portfolios each drift widget says which it reads", %{conn: conn} do
    first = base_world(name: "First Synthetic")

    _second =
      base_world(name: "Second Synthetic", cash_name: "Second Cash", depot_name: "Second Depot")

    deposit!(first, "1000", Date.add(Clock.today(), -40))
    {:ok, _tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Steering"})
    doc = loaded(conn)

    assert text(
             Floki.find(doc, "#dashboard-allocation-drift [data-role='allocation-drift-basis']")
           ) =~
             "Portfolio First Synthetic"

    assert text(Floki.find(doc, "#dashboard-attention [data-role='attention-explainer']")) =~
             "in every portfolio"
  end
end
