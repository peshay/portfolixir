defmodule PortfolixirWeb.ClassificationsPositionTargetsTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 0, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets

  setup do
    world = base_world()
    owner = Actor.owner_ui()

    {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategy"})

    {:ok, equity} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Equity"})

    {:ok, bonds} =
      Classifications.create_category(owner, %{classification_id: tree.id, name: "Bonds"})

    timber = create_security!(name: "Nordic Timber Test AB", ticker: "NTT")
    solar = create_security!(name: "Helios Solar Test SE", ticker: "HST")
    bond = create_security!(name: "Placeholder Bond 2031", ticker: "PB31")

    for {security, category} <- [{timber, equity}, {solar, equity}, {bond, bonds}] do
      {:ok, _} = Classifications.assign_security(owner, security.id, tree.id, category.id)
    end

    {:ok, _plan} = Targets.ensure_plan(owner, world.portfolio.id, tree.id, view: nil)

    Map.merge(world, %{
      tree: tree,
      equity: equity,
      bonds: bonds,
      timber: timber,
      solar: solar,
      bond: bond
    })
  end

  defp open(conn, tree) do
    {:ok, view, _html} = live(conn, "/classifications/#{tree.id}")
    render_async(view)
    view
  end

  defp position_rows(portfolio_id, tree_id) do
    portfolio_id
    |> Targets.list_position_targets(classification_id: tree_id)
    |> Map.new(&{&1.security_id, Decimal.mult(&1.target_weight, 100) |> Decimal.normalize()})
  end

  # User story (#481 rescoped, pick F2-A of board 02-position-soll-entry):
  # As the operator steering single positions,
  # I want to enter a position's target in the same plan form as the
  # categories,
  # so that the Wealth page's hint to "align the position targets on the
  # Classifications page" points at a field that exists.
  #
  # Acceptance criteria:
  # - Each category with assigned securities offers "Positions (n)"; the
  #   position rows are inputs in the same form — one save, one live Σ.
  # - Once a position under a category carries a target, the category's input
  #   becomes the read-only "Σ positions" (ADR-0030 §2), and the Σ counts the
  #   position sum in its place.
  # - Saving writes the position rows through the Targets context, and the
  #   category row follows their sum ("the category follows it"), so a stored
  #   category weight that disagreed no longer conflicts — the Wealth page's
  #   "align the position targets and the category weight" is done by saving.
  test "position targets are entered inline and the category follows them",
       %{conn: conn} = ctx do
    # A category weight stored before any position target, now superseded.
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), ctx.portfolio.id, ctx.tree.id, [
        %{category_id: ctx.equity.id, target_weight: "0.5"}
      ])

    view = open(conn, ctx.tree)

    assert has_element?(view, "#soll-positions-toggle-#{ctx.equity.id}", "Positions (2)")
    assert has_element?(view, ~s(input[name="positions[#{ctx.equity.id}][#{ctx.timber.id}]"]))

    view |> element("#soll-positions-toggle-#{ctx.equity.id}") |> render_click()

    html =
      view
      |> form("#soll-plan-form")
      |> render_change(%{
        "weights" => %{"#{ctx.bonds.id}" => "30"},
        "positions" => %{
          "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "8", "#{ctx.solar.id}" => "52"},
          "#{ctx.bonds.id}" => %{"#{ctx.bond.id}" => ""}
        },
        "cash_target" => "10"
      })

    # The category is the sum of its positions now, shown and not editable.
    refute has_element?(view, ~s(input[name="weights[#{ctx.equity.id}]"]))
    assert has_element?(view, "#soll-position-sum-#{ctx.equity.id}", "60")
    assert html =~ ~r/data-role="soll-sum"[^>]*>\s*100/

    view
    |> form("#soll-plan-form")
    |> render_submit(%{
      "weights" => %{"#{ctx.bonds.id}" => "30"},
      "positions" => %{
        "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "8", "#{ctx.solar.id}" => "52"},
        "#{ctx.bonds.id}" => %{"#{ctx.bond.id}" => ""}
      },
      "cash_target" => "10"
    })

    assert position_rows(ctx.portfolio.id, ctx.tree.id) == %{
             ctx.timber.id => Decimal.new("8"),
             ctx.solar.id => Decimal.new("52")
           }

    [equity] = Targets.effective_targets(ctx.portfolio.id, classification_id: ctx.tree.id)
    assert Decimal.equal?(equity.effective, Decimal.new("0.6"))
    assert Decimal.equal?(equity.explicit, Decimal.new("0.6"))
    refute equity.conflict
  end

  # User story (#481, the distinction the plan pins):
  # As the operator clearing a position's target,
  # I want an empty field to mean "no position target", never zero,
  # so that clearing a field returns the steering to the category instead of
  # pinning the position at 0 %, which would change the roll-up.
  #
  # Acceptance criteria:
  # - An empty position input stores no row; a stored row whose input is
  #   cleared is deleted, not set to zero.
  # - "0" is a target of zero and is stored as one.
  # - With no position target left, the category input returns.
  test "an empty position input means no position target, and 0 means zero",
       %{conn: conn} = ctx do
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), ctx.portfolio.id, ctx.tree.id, [
        %{category_id: ctx.equity.id, security_id: ctx.timber.id, target_weight: "0.08"},
        %{category_id: ctx.equity.id, security_id: ctx.solar.id, target_weight: "0.52"}
      ])

    view = open(conn, ctx.tree)

    # Rows that carry a target open by default.
    assert has_element?(view, ~s(#soll-positions-toggle-#{ctx.equity.id}[aria-expanded="true"]))

    view
    |> form("#soll-plan-form")
    |> render_submit(%{
      "positions" => %{
        "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "", "#{ctx.solar.id}" => "0"}
      },
      "cash_target" => ""
    })

    assert position_rows(ctx.portfolio.id, ctx.tree.id) == %{ctx.solar.id => Decimal.new("0")}

    view
    |> form("#soll-plan-form")
    |> render_submit(%{
      "positions" => %{"#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "", "#{ctx.solar.id}" => ""}},
      "cash_target" => ""
    })

    assert position_rows(ctx.portfolio.id, ctx.tree.id) == %{}
    assert has_element?(view, ~s(input[name="weights[#{ctx.equity.id}]"]))
  end

  test "collapsing a category keeps its position inputs in the form", %{conn: conn} = ctx do
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), ctx.portfolio.id, ctx.tree.id, [
        %{category_id: ctx.equity.id, security_id: ctx.timber.id, target_weight: "0.08"}
      ])

    view = open(conn, ctx.tree)
    view |> element("#soll-positions-toggle-#{ctx.equity.id}") |> render_click()

    assert has_element?(view, ~s(#soll-positions-toggle-#{ctx.equity.id}[aria-expanded="false"]))

    # Hidden, not removed: a collapsed row still submits its value, so
    # collapsing can never read as clearing.
    assert has_element?(
             view,
             ~s(tr[hidden] input[name="positions[#{ctx.equity.id}][#{ctx.timber.id}]"][value="8"])
           )
  end
end
