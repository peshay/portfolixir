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
    |> Map.new(fn row ->
      percent = row.target_weight |> Decimal.mult(100) |> Decimal.normalize()
      {row.security_id, percent |> Decimal.to_string(:normal) |> Decimal.new()}
    end)
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

  # Acceptance criteria (closing act, correctness and edge-case hunters):
  # - A stale position row (its security re-filed elsewhere) no longer
  #   blocks saving the plan: sent back unchanged, it is left as it is.
  # - Changing a stale row is refused with a message that says why — and a
  #   refused save changes nothing: a position cleared in the same save is
  #   still there (the clears used to commit before the save failed).
  test "a stale position row neither blocks the plan nor half-saves it", %{conn: conn} = ctx do
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), ctx.portfolio.id, ctx.tree.id, [
        %{category_id: ctx.equity.id, security_id: ctx.timber.id, target_weight: "0.08"},
        %{category_id: ctx.equity.id, security_id: ctx.solar.id, target_weight: "0.20"}
      ])

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), ctx.timber.id, ctx.tree.id, ctx.bonds.id)

    view = open(conn, ctx.tree)

    html =
      view
      |> form("#soll-plan-form")
      |> render_submit(%{
        "positions" => %{
          "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "8", "#{ctx.solar.id}" => "20"}
        },
        "cash_target" => "10"
      })

    assert html =~ "Plan saved"
    assert Decimal.equal?(Targets.get_cash_target(ctx.portfolio.id), Decimal.new("0.1"))

    html =
      view
      |> form("#soll-plan-form")
      |> render_submit(%{
        "positions" => %{
          "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "9", "#{ctx.solar.id}" => ""}
        },
        "cash_target" => "10"
      })

    assert html =~ "no longer sits under"

    assert position_rows(ctx.portfolio.id, ctx.tree.id) == %{
             ctx.timber.id => Decimal.new("8"),
             ctx.solar.id => Decimal.new("20")
           }
  end

  # Acceptance criteria (closing act, both hunters): clearing a category's
  # last position target hands the steering back to the category — the row
  # that only followed their sum goes with them, so the category has no
  # target (what the editor shows), never a 0 % or the old sum the operator
  # did not type. A category weight typed in the same save is kept.
  test "clearing the last position target clears the followed category row",
       %{conn: conn} = ctx do
    view = open(conn, ctx.tree)

    positions = fn timber, solar ->
      %{"#{ctx.equity.id}" => %{"#{ctx.timber.id}" => timber, "#{ctx.solar.id}" => solar}}
    end

    view
    |> form("#soll-plan-form")
    |> render_submit(%{"positions" => positions.("8", "52"), "cash_target" => ""})

    assert category_row(ctx) == Decimal.new("0.6")

    view
    |> form("#soll-plan-form")
    |> render_submit(%{"positions" => positions.("", ""), "cash_target" => ""})

    assert position_rows(ctx.portfolio.id, ctx.tree.id) == %{}
    assert category_row(ctx) == nil
    assert has_element?(view, ~s(input[name="weights[#{ctx.equity.id}]"][value=""]))

    # Typed in the same save, the category weight stays.
    view
    |> form("#soll-plan-form")
    |> render_submit(%{"positions" => positions.("8", ""), "cash_target" => ""})

    view
    |> form("#soll-plan-form")
    |> render_submit(%{
      "positions" => positions.("", ""),
      "weights" => %{"#{ctx.equity.id}" => "35"},
      "cash_target" => ""
    })

    assert category_row(ctx) == Decimal.new("0.35")
  end

  # Acceptance criteria (closing act, edge-case hunter): positions summing
  # above 100 % are refused in the operator's words — no raw placeholder —
  # and the refused save leaves every stored row, including one cleared in it.
  test "a plan over 100 % is refused whole and in words", %{conn: conn} = ctx do
    view = open(conn, ctx.tree)

    view
    |> form("#soll-plan-form")
    |> render_submit(%{
      "positions" => %{
        "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "8", "#{ctx.solar.id}" => "20"}
      },
      "cash_target" => ""
    })

    html =
      view
      |> form("#soll-plan-form")
      |> render_submit(%{
        "positions" => %{
          "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "", "#{ctx.solar.id}" => "120"}
        },
        "cash_target" => ""
      })

    assert html =~ "between 0 and 100"
    refute html =~ "%{"

    assert position_rows(ctx.portfolio.id, ctx.tree.id) == %{
             ctx.timber.id => Decimal.new("8"),
             ctx.solar.id => Decimal.new("20")
           }
  end

  # Acceptance criteria (closing act, UAT persona): copying another view's plan
  # copies its position targets too — the rows show open with the source's
  # values, and saving writes them into this view's plan.
  test "copying a plan from another view carries its position targets", %{conn: conn} = ctx do
    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), ctx.portfolio.id, ctx.tree.id, [
        %{category_id: ctx.equity.id, target_weight: "0.3"},
        %{category_id: ctx.equity.id, security_id: ctx.timber.id, target_weight: "0.1"},
        %{category_id: ctx.equity.id, security_id: ctx.solar.id, target_weight: "0.2"}
      ])

    {:ok, named} = Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Stocks"})
    view = open(conn, ctx.tree)

    view
    |> element("form[phx-change='select_soll_view']")
    |> render_change(%{"soll_view" => "#{named.id}"})

    view
    |> element("form[phx-change='copy_soll_plan']")
    |> render_change(%{"copy_from" => "total"})

    timber_input = ~s(input[name="positions[#{ctx.equity.id}][#{ctx.timber.id}]"][value="10"])
    assert has_element?(view, timber_input)
    refute has_element?(view, ~s(tr.soll-row--position[data-category="#{ctx.equity.id}"][hidden]))

    view |> form("#soll-plan-form") |> render_submit(%{"cash_target" => ""})

    copied =
      ctx.portfolio.id
      |> Targets.list_position_targets(classification_id: ctx.tree.id, view: named.id)
      |> Map.new(&{&1.security_id, &1.target_weight})

    assert Decimal.equal?(copied[ctx.timber.id], Decimal.new("0.1"))
    assert Decimal.equal?(copied[ctx.solar.id], Decimal.new("0.2"))
  end

  # Acceptance criteria (closing act): a security filed under a sub-category
  # shows a row there and under the parent that carries its stored target —
  # typing into both is refused by name, and the refused save changes nothing.
  test "a second position target for one security is refused by name", %{conn: conn} = ctx do
    {:ok, nordic} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: ctx.tree.id,
        parent_id: ctx.equity.id,
        name: "Nordics"
      })

    {:ok, _} =
      Targets.set_targets(Actor.owner_ui(), ctx.portfolio.id, ctx.tree.id, [
        %{category_id: ctx.equity.id, security_id: ctx.timber.id, target_weight: "0.08"}
      ])

    {:ok, _} =
      Classifications.assign_security(Actor.owner_ui(), ctx.timber.id, ctx.tree.id, nordic.id)

    view = open(conn, ctx.tree)
    assert has_element?(view, ~s(input[name="positions[#{nordic.id}][#{ctx.timber.id}]"]))

    html =
      view
      |> form("#soll-plan-form")
      |> render_submit(%{
        "positions" => %{
          "#{ctx.equity.id}" => %{"#{ctx.timber.id}" => "8", "#{ctx.solar.id}" => ""},
          "#{nordic.id}" => %{"#{ctx.timber.id}" => "5"}
        },
        "cash_target" => ""
      })

    assert html =~
             "Nordic Timber Test AB already carries a position target under another category"

    assert position_rows(ctx.portfolio.id, ctx.tree.id) == %{ctx.timber.id => Decimal.new("8")}
  end

  # Acceptance criteria (closing act, edge-case hunter): the page's other
  # refusals read in its language too — a blank tree name on a German page.
  test "a refused tree name reads in German", %{conn: conn} do
    conn = Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")
    {:ok, view, _html} = live(conn, "/classifications/new")

    html =
      view
      |> form("#classification-form")
      |> render_submit(%{"classification" => %{"name" => ""}})

    assert html =~ "Name darf nicht leer sein"
    refute html =~ "can&#39;t be blank"
  end

  defp category_row(ctx) do
    case Targets.get_target(ctx.portfolio.id, ctx.equity.id) do
      nil -> nil
      row -> Decimal.normalize(row.target_weight)
    end
  end

  # User story (#874; board ux-design-2026-09-24/08-classification-detail,
  # "#874"; DESIGN.md → the plan editor, #467's per-parent hint):
  # As the operator editing a nested plan,
  # I want each parent's "children Σ" to stay on screen and follow my typing,
  # so that Growth at 65 % over children adding up to 60 % is flagged while I
  # type, not only after "Save plan".
  #
  # Acceptance criteria:
  # - On load and on every change the hint is computed the same way, with the
  #   weight each child steers by: a child that follows its position targets
  #   counts with their sum (ADR-0030 §2).
  # - Changing a parent's own weight keeps its hint and flags the mismatch; a
  #   parent nobody touched keeps its hint too.
  # - Changing a position target under a child moves the parent's hint.
  test "the children Σ hint stays live while the plan is edited", %{conn: conn} = ctx do
    owner = Actor.owner_ui()

    category =
      &Classifications.create_category(owner, Map.put(&1, :classification_id, ctx.tree.id))

    {:ok, growth} = category.(%{name: "Growth"})
    {:ok, core} = category.(%{name: "Core market", parent_id: growth.id})
    {:ok, platforms} = category.(%{name: "Platforms", parent_id: growth.id})
    {:ok, stability} = category.(%{name: "Stability"})
    {:ok, govies} = category.(%{name: "Govies", parent_id: stability.id})
    {:ok, gold} = category.(%{name: "Gold", parent_id: stability.id})

    kestrel = create_security!(name: "Kestrel Industrial Test NV", ticker: "KIT")
    meridian = create_security!(name: "Meridian Global Test ETF", ticker: "MGT")

    for security <- [kestrel, meridian] do
      {:ok, _} = Classifications.assign_security(owner, security.id, ctx.tree.id, core.id)
    end

    {:ok, _} =
      Targets.set_targets(owner, ctx.portfolio.id, ctx.tree.id, [
        %{category_id: growth.id, target_weight: "0.60"},
        %{category_id: platforms.id, target_weight: "0.35"},
        %{category_id: core.id, security_id: meridian.id, target_weight: "0.15"},
        %{category_id: core.id, security_id: kestrel.id, target_weight: "0.10"},
        %{category_id: stability.id, target_weight: "0.30"},
        %{category_id: govies.id, target_weight: "0.20"},
        %{category_id: gold.id, target_weight: "0.10"}
      ])

    view = open(conn, ctx.tree)

    # Loaded: Core counts with its positions (15 + 10), Platforms with 35.
    assert child_hint(view, "Growth") == {"children Σ 60%", false}
    assert child_hint(view, "Stability") == {"children Σ 30%", false}

    edit = fn weights, positions ->
      view
      |> form("#soll-plan-form")
      |> render_change(%{
        "weights" =>
          Map.merge(
            %{
              "#{platforms.id}" => "35",
              "#{stability.id}" => "30",
              "#{govies.id}" => "20",
              "#{gold.id}" => "10"
            },
            weights
          ),
        "positions" => %{
          "#{core.id}" =>
            Map.merge(%{"#{meridian.id}" => "15", "#{kestrel.id}" => "10"}, positions)
        },
        "cash_target" => ""
      })
    end

    edit.(%{"#{growth.id}" => "65"}, %{})
    assert child_hint(view, "Growth") == {"children Σ 60%", true}
    assert child_hint(view, "Stability") == {"children Σ 30%", false}

    edit.(%{"#{growth.id}" => "60"}, %{"#{kestrel.id}" => "15"})
    assert child_hint(view, "Growth") == {"children Σ 65%", true}
  end

  # The hint text of the category row named `name`, and whether it is flagged.
  defp child_hint(view, name) do
    row =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#soll-plan-form tr.soll-row")
      |> Enum.find(fn row ->
        row |> Floki.find("th.soll-row__name") |> Floki.text() |> String.contains?(name)
      end)

    case Floki.find(row, ~s([data-role="soll-child-hint"])) do
      [] ->
        nil

      [hint] ->
        text = hint |> Floki.text() |> String.split() |> Enum.join(" ")
        {text, hint |> Floki.attribute("class") |> hd() |> String.contains?("is-target-mismatch")}
    end
  end
end
