defmodule PortfolixirWeb.ClassificationsViewScopeTest do
  @moduledoc """
  The classification screen's view scope (#1091's screen half; Sprint 19
  PR γ U7, board `ux-design-2026-10-04/10-category-results`, pick J10 A).

  The Wealth page's view switcher is the screen's one scope: every figure of
  a category row, the plan editor and the basis line read the chosen view,
  and the category result is the read the API serves for the same scope.
  Every name, amount and view here is invented.
  """
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios.Targets
  alias PortfolixirWeb.Format

  @auth {"authorization", "Bearer test-api-token"}

  defp live_drained(conn, path) do
    {:ok, view, _html} = live(conn, path)
    html = render_async(view)
    {view, html}
  end

  # A EUR portfolio with a depot in the view "Langfrist" and a second depot
  # outside it, and a USD portfolio whose depot is in the view. The tree is
  # board 10's: "Wachstum" over "Kern global" and "Plattformen".
  #
  # - Kestrel Systems AG (EUR, in the view): 10 at 580, now 750, Plattformen.
  # - Harborline Freight Inc (USD, in the view): 10 at 150 USD, now 180,
  #   Plattformen; its cost was not paid in EUR.
  # - Lumen Basis ETF (EUR): 8 at 550 in the view and 2 at 550 outside it,
  #   now 600, Kern global -- one security on both sides of the view.
  # - Corvid Index Fund (EUR, outside the view): 20 at 200, now 240, Kern
  #   global.
  # - Pellucid Holdings (EUR, in the view's depot, sold): Kern global.
  defp scope_world do
    euro = base_world()

    outside =
      euro.portfolio
      |> add_depot(depot_name: "Untagged Depot", cash_name: "Untagged Cash")
      |> Map.put(:portfolio, euro.portfolio)

    dollar =
      base_world(
        name: "Dollar",
        currency: "USD",
        cash_name: "Dollar Cash",
        depot_name: "Dollar Depot"
      )

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

    category = fn name, parent ->
      {:ok, category} =
        Classifications.create_category(Actor.owner_ui(), %{
          classification_id: classification.id,
          name: name,
          parent_id: parent && parent.id
        })

      category
    end

    growth = category.("Wachstum", nil)
    core = category.("Kern global", growth)
    platforms = category.("Plattformen", growth)

    file = fn security, target ->
      {:ok, _} =
        Classifications.assign_security(
          Actor.owner_ui(),
          security.id,
          classification.id,
          target.id
        )

      security
    end

    kestrel = file.(create_security!(name: "Kestrel Systems AG", ticker: "KST"), platforms)

    harborline =
      file.(
        create_security!(name: "Harborline Freight Inc", ticker: "HBF", currency: "USD"),
        platforms
      )

    lumen = file.(create_security!(name: "Lumen Basis ETF", ticker: "LBE"), core)
    corvid = file.(create_security!(name: "Corvid Index Fund", ticker: "CIF"), core)
    pellucid = file.(create_security!(name: "Pellucid Holdings", ticker: "PEL"), core)

    deposit!(euro, "30000", ~D[2026-01-01])
    deposit!(outside, "30000", ~D[2026-01-01])
    deposit!(dollar, "20000", ~D[2026-01-01], currency: "USD")

    buy!(euro, kestrel, quantity: "10", price: "580")
    buy!(euro, lumen, quantity: "8", price: "550")
    buy!(euro, pellucid, quantity: "5", price: "40", date: ~D[2026-01-02])
    sell!(euro, pellucid, quantity: "5", price: "45", date: ~D[2026-01-03])
    buy!(outside, corvid, quantity: "20", price: "200")
    buy!(outside, lumen, quantity: "2", price: "550")
    buy!(dollar, harborline, quantity: "10", price: "150", currency: "USD")

    put_quote!(kestrel, Date.utc_today(), "750")
    put_quote!(harborline, Date.utc_today(), "180")
    put_quote!(lumen, Date.utc_today(), "600")
    put_quote!(corvid, Date.utc_today(), "240")

    {:ok, _} =
      Portfolixir.Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: Date.add(Date.utc_today(), -10),
          rate: Decimal.new("1.1"),
          source: "manual"
        }
      ])

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Langfrist"})

    {:ok, long_term} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Langfrist", include_all: false})

    :ok = Buckets.set_view_buckets(Actor.owner_ui(), long_term, [bucket.id], [])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), euro.depot, [bucket.id])
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), dollar.depot, [bucket.id])

    %{
      euro: euro,
      outside: outside,
      dollar: dollar,
      classification: classification,
      growth: growth,
      core: core,
      platforms: platforms,
      view: long_term
    }
  end

  defp path(world, query), do: "/classifications/#{world.classification.id}?" <> query

  # A category row's cells as a reader gets them, whitespace collapsed.
  defp row(html, name) do
    summary =
      html
      |> Floki.parse_document!()
      |> Floki.find("section.tree summary.cat-summary")
      |> Enum.find(&(text(Floki.find(&1, ".cat-name__text")) == name))

    # The result cell stacks its amount, percentage and count as elements;
    # they read with a space between them.
    cell = fn role ->
      summary
      |> Floki.find(~s([data-role="#{role}"]))
      |> Floki.text(sep: " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
    end

    %{
      positions: cell.("category-positions"),
      value: cell.("category-value"),
      cost: cell.("category-invested"),
      result: cell.("category-result"),
      hidden: cell.("without-holdings")
    }
  end

  # A category row's summary element.
  defp summary(html, name) do
    html
    |> Floki.parse_document!()
    |> Floki.find("section.tree summary.cat-summary")
    |> Enum.find(&(text(Floki.find(&1, ".cat-name__text")) == name))
  end

  # The result cell's three figures, each as printed.
  defp result_cells(html, name) do
    summary =
      html
      |> Floki.parse_document!()
      |> Floki.find("section.tree summary.cat-summary")
      |> Enum.find(&(text(Floki.find(&1, ".cat-name__text")) == name))

    %{
      cost: text(Floki.find(summary, ~s([data-role="category-invested"]))),
      amount: text(Floki.find(summary, ~s([data-role="category-result"] > b))),
      pct: text(Floki.find(summary, ~s([data-role="category-result"] > small)))
    }
  end

  # The security rows of the tree (or of `scope`), as {name, quantity, value}.
  defp security_rows(html, scope \\ "section.tree") do
    html
    |> find(~s(#{scope} [data-role="security-row"]))
    |> Enum.map(fn row ->
      {text(Floki.find(row, ".row-name")),
       text(Floki.find(row, ~s([data-role="security-quantity"]))),
       text(Floki.find(row, ~s([data-role="security-value"])))}
    end)
    |> Enum.sort()
  end

  defp basis(html), do: html |> find(~s([data-role="category-result-basis"])) |> first_line()

  # The basis sentence as the browser gets it, no-break spaces kept.
  defp raw_basis(html),
    do: html |> find(~s([data-role="category-result-basis"] > span)) |> Floki.text()

  defp find(html, selector), do: html |> Floki.parse_document!() |> Floki.find(selector)

  # The basis line's own sentence, without the ⓘ's tooltip text.
  defp first_line(nodes) do
    nodes
    |> Floki.filter_out("details")
    |> text()
  end

  defp note(html),
    do: html |> find(~s([data-role="category-result-excluded"] .data-note__body)) |> text()

  # The page's refusal, as the operator reads it.
  defp refusal(html), do: html |> find(".alert-error") |> text()

  defp text(nodes), do: nodes |> Floki.text() |> String.replace(~r/\s+/u, " ") |> String.trim()

  # User story (#1091, the screen half; pick J10 A):
  # As a local portfolio maintainer steering a narrower slice of my holdings,
  # I want the classification screen to read the view I picked, with the view
  # switcher I know from Wealth,
  # so that a category's positions, value, cost and result are all about the
  # same scope, and the screen says which scope that is.
  #
  # Acceptance criteria:
  # - The Wealth page's view switcher stands in a controls row under the
  #   detail head, before the plan editor; the chosen view's chip is active.
  # - Under a view, "Positions" and "Value" read the view's positions, and
  #   "Cost" and "Result" the view's category result, in EUR.
  # - Members the view holds none of are hidden under "current positions
  #   only" and counted as "+N not in the view".
  # - The basis line names the view, then the currency.
  # - The excluded note follows the view's result.
  # - Under "Everything" the row reads every portfolio, as before, and the
  #   hidden members are "+N without holdings".
  test "the view switcher scopes every figure in the row and names the view (#1091, J10 A)",
       %{conn: conn} do
    world = scope_world()

    {lv, html} = live_drained(conn, path(world, "view=#{world.view.id}"))

    # The switcher, unchanged, in a controls row between the head and the
    # plan editor; the editor's own select is gone.
    assert html =~
             ~r/class="detail-head".*class="workspace-section workspace-section--controls".*class="view-switcher".*id="soll-editor"/s

    assert has_element?(lv, "#view-switch-#{world.view.id}.is-active[aria-current]")
    refute has_element?(lv, "#view-switch-total.is-active")
    refute has_element?(lv, "select[name='soll_view']")

    # Kern global: Lumen alone is in the view; Corvid is held outside it and
    # Pellucid nowhere -- both "not in the view", hidden.
    assert row(html, "Kern global") == %{
             positions: "1",
             value: "4,800.00",
             cost: "4,400.00",
             result: "+400.00 +9.1%",
             hidden: "+2 not in the view"
           }

    # Plattformen: Kestrel and Harborline are both in the view; Harborline's
    # cost was not paid in EUR (J10.2), so cost and result are Kestrel's.
    assert row(html, "Plattformen") == %{
             positions: "2",
             value: "9,136.36",
             cost: "5,800.00",
             result: "+1,700.00 +29.3% 1/2",
             hidden: ""
           }

    assert row(html, "Wachstum") == %{
             positions: "3",
             value: "13,936.36",
             cost: "10,200.00",
             result: "+2,100.00 +20.6% 2/3",
             hidden: "+2 not in the view"
           }

    assert basis(html) ==
             "View Langfrist · in EUR · Result: today's composition, not a period return"

    # A "·" never starts a line: a no-break space holds it to the word before
    # it (review round, a long view name at 390 px).
    assert raw_basis(html) =~ "Langfrist\u00A0· in EUR\u00A0· Result:"

    assert note(html) ==
             "1 position is not included in “Cost” and “Result” because its cost was not " <>
               "paid in EUR: Harborline Freight Inc (Plattformen), cost 1,500.00 USD. " <>
               "It is included in “Value”."

    # Everything: every portfolio, as the screen read before this story.
    {lv, html} = live_drained(conn, path(world, "view=total"))

    assert has_element?(lv, "#view-switch-total.is-active[aria-current]")

    # Lumen's two units outside the view count here: 10 at 600, cost 5,500.
    assert row(html, "Kern global") == %{
             positions: "2",
             value: "10,800.00",
             cost: "9,500.00",
             result: "+1,300.00 +13.7%",
             hidden: "+1 without holdings"
           }

    assert row(html, "Wachstum").positions == "4"
    assert row(html, "Wachstum").value == "19,936.36"
    assert row(html, "Wachstum").cost == "15,300.00"

    assert basis(html) ==
             "View Everything · in EUR · Result: today's composition, not a period return"
  end

  # Acceptance criteria (#1091; J10 A):
  # - Opened, a category lists only the positions the view holds, with the
  #   view's quantity and value -- for a security held inside and outside
  #   the view, the inside part only; Everything shows both parts.
  # - Turning "current positions only" off shows the members the view holds
  #   none of as an unheld row: quantity 0, no value.
  test "a category's rows hold the view's positions, and the toggle reveals the rest",
       %{conn: conn} do
    world = scope_world()

    {lv, html} = live_drained(conn, path(world, "view=#{world.view.id}"))

    # The rows are in the closed <details>, but rendered: the view's three,
    # Lumen with its 8 units in the view, not its 2 outside it.
    assert security_rows(html) == [
             {"Harborline Freight Inc", "10.00", "1,636.36"},
             {"Kestrel Systems AG", "10.00", "7,500.00"},
             {"Lumen Basis ETF", "8.00", "4,800.00"}
           ]

    shown =
      lv
      |> element("form[phx-change='toggle_current_only']")
      |> render_change(%{"current_only" => "false"})

    assert {"Corvid Index Fund", "0.00", "—"} in security_rows(shown)
    assert {"Pellucid Holdings", "0.00", "—"} in security_rows(shown)
    assert row(shown, "Kern global").hidden == ""
    assert row(shown, "Kern global").positions == "3"

    {_lv, everything} = live_drained(conn, path(world, "view=total"))

    assert {"Lumen Basis ETF", "10.00", "6,000.00"} in security_rows(everything)
    assert {"Corvid Index Fund", "20.00", "4,800.00"} in security_rows(everything)
  end

  # User story (#1091; pick J10 A):
  # As a local portfolio maintainer editing a view's target plan,
  # I want the plan editor to edit the plan of the view the screen reads,
  # with its head saying which view that is,
  # so that the plan's weights and the result beside them are about the
  # same scope, without a second picker that disagrees with the first.
  #
  # Acceptance criteria:
  # - Under a view the editor shows and saves that view's plan; the
  #   no-view plan is untouched.
  # - The head reads "Target plan" and "for view <name>" ("for view
  #   Everything" with no view).
  # - "Copy from another view…" lists the no-view plan as "Everything".
  test "the plan editor edits the chosen view's plan and names the view", %{conn: conn} do
    world = scope_world()
    portfolio = world.euro.portfolio

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.4"}],
        view: world.view.id
      )

    {lv, html} = live_drained(conn, path(world, "view=#{world.view.id}"))

    assert text(find(html, "#soll-editor .soll-editor__head h2")) == "Target plan"

    assert text(find(html, ~s(#soll-editor [data-role="soll-editor-scope"]))) ==
             "for view Langfrist"

    assert has_element?(lv, "input[name='weights[#{world.core.id}]'][value='40']")

    assert has_element?(lv, "#soll-copy-form option[value='total']", "Everything")

    lv
    |> form("#soll-plan-form", %{"weights" => %{"#{world.core.id}" => "45"}, "cash_target" => ""})
    |> render_submit()

    weight = fn view_id ->
      portfolio.id
      |> Targets.list_targets(classification_id: world.classification.id, view: view_id)
      |> Map.new(&{&1.category_id, &1.target_weight})
      |> Map.fetch!(world.core.id)
    end

    assert Decimal.equal?(weight.(world.view.id), Decimal.new("0.45"))
    assert Decimal.equal?(weight.(nil), Decimal.new("0.8"))

    {lv, html} = live_drained(conn, path(world, "view=total"))

    assert text(find(html, ~s(#soll-editor [data-role="soll-editor-scope"]))) ==
             "for view Everything"

    assert has_element?(lv, "input[name='weights[#{world.core.id}]'][value='80']")
  end

  # User story (#1091, both directions):
  # As the operator who also asks the agent,
  # I want the classification screen to show what the API answers for the
  # same scope,
  # so that the agent and I never read two different results for one view.
  #
  # Acceptance criteria:
  # - Under a view, each category's cost, result and percentage on the
  #   screen are exactly the invested, result_abs and result_pct of GET
  #   /api/v1/views/:view_id/category-results, for every category it
  #   reports a cost for, and the note names exactly its excluded_members.
  # - Under "Everything", the same holds against GET /api/v1/category-results.
  test "the screen shows what the API's category-result read answers for the same scope",
       %{conn: conn} do
    world = scope_world()
    classification = "classification_id=#{world.classification.id}"

    for {screen_query, api_path} <- [
          {"view=#{world.view.id}", "/api/v1/views/#{world.view.id}/category-results"},
          {"view=total", "/api/v1/category-results"}
        ] do
      data =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header(elem(@auth, 0), elem(@auth, 1))
        |> get(api_path <> "?" <> classification)
        |> json_response(200)
        |> Map.fetch!("data")

      {_lv, html} = live_drained(conn, path(world, screen_query))

      assert data["base_currency"] == "EUR"
      assert basis(html) =~ "in EUR"

      costed = Enum.filter(data["categories"], &Decimal.gt?(Decimal.new(&1["invested"]), 0))

      # Wachstum, Kern global and Plattformen: never a vacuous pass.
      assert length(costed) == 3

      for category <- costed do
        # The house percent, the sign and "%" glued on (the closing act of
        # PR γ).
        assert result_cells(html, category["name"]) == %{
                 cost: Format.money(Decimal.new(category["invested"])),
                 amount: Format.signed_decimal(Decimal.new(category["result_abs"]), 2),
                 pct: Format.signed_percent(Decimal.new(category["result_pct"])) <> "%"
               },
               "#{screen_query}: #{category["name"]}"
      end

      named =
        html
        |> find(~s([data-role="category-result-excluded"] bdi))
        |> Enum.map(&text/1)

      assert named == Enum.map(data["excluded_members"], & &1["security_name"])
      assert named == ["Harborline Freight Inc"]
    end
  end

  # User story (#1091; pick J10 A, "its side effect"):
  # As a local portfolio maintainer,
  # I want a view chosen on the classification screen to be the active view
  # on Wealth too, and the chips to mark the views that carry a plan for
  # this tree,
  # so that there is one answer to "which view is active" across the app.
  #
  # Acceptance criteria:
  # - Each chip is a link to this tree with `?view=`; following it stores the
  #   choice the way Wealth's chips do (ViewScope's cookie), and Wealth then
  #   opens on that view.
  # - A view with a plan for this tree carries the plan dot; one without
  #   does not.
  test "a chip is a navigation through ViewScope, and the chips mark the planned views",
       %{conn: conn} do
    world = scope_world()
    {:ok, plain} = Buckets.create_view(Actor.owner_ui(), %{name: "Sparplan"})

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        world.euro.portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.5"}],
        view: world.view.id
      )

    {lv, _html} = live_drained(conn, path(world, "view=total"))

    chip = "#view-switch-#{world.view.id}"
    assert has_element?(lv, ~s(#{chip}[href="#{path(world, "view=#{world.view.id}")}"]))
    assert has_element?(lv, ~s(#view-switch-total[href="#{path(world, "view=total")}"]))
    assert has_element?(lv, "#{chip}[data-has-plan]")
    refute has_element?(lv, "#view-switch-#{plain.id}[data-has-plan]")
    refute has_element?(lv, "#view-switch-total[data-has-plan]")

    followed = get(conn, path(world, "view=#{world.view.id}"))
    assert followed.resp_cookies["portfolixir_view"].value == "#{world.view.id}"

    {:ok, wealth, _html} = live(recycle(followed), "/portfolio")
    assert has_element?(wealth, "#view-switch-#{world.view.id}.is-active")
    render_async(wealth)
  end

  # Acceptance criteria (#1091; the I/O matrix's last rows):
  # - A view deleted while the page reads it degrades the screen to
  #   "Everything" with Wealth's notice, never a crash.
  test "a view deleted while the page reads it degrades to Everything", %{conn: conn} do
    world = scope_world()

    {lv, _html} = live_drained(conn, path(world, "view=#{world.view.id}"))

    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), world.view)
    render_patch(lv, "/classifications/#{world.classification.id}")
    # The first answer degrades the page and starts both reads again.
    render_async(lv)
    html = render_async(lv)

    assert Process.alive?(lv.pid)

    assert text(find(html, ~s([data-role="view-gone-notice"]))) ==
             "The selected view no longer exists — showing Everything."

    assert has_element?(lv, "#view-switch-total.is-active")
    refute has_element?(lv, "#view-switch-#{world.view.id}")
    assert basis(html) =~ "View Everything"
    assert row(html, "Kern global").positions == "2"
  end

  # Acceptance criteria (#1091): the scoped reads start with the tree they
  # read, so a tree that is gone says so and starts none.
  test "a tree that is gone says so and reads nothing", %{conn: conn} do
    world = scope_world()
    {:ok, _} = Classifications.delete_classification(Actor.owner_ui(), world.classification)

    {:ok, lv, html} = live(conn, path(world, "view=#{world.view.id}"))

    assert html =~ "Classification not found"
    assert render_async(lv) =~ "Classification not found"
    assert Process.alive?(lv.pid)
  end

  # Acceptance criteria (#1091, review round):
  # - Under a view, "Unsorted" counts and values the unsorted positions the
  #   view holds, and puts the rest in the "+N not in the view" slot, as a
  #   category does.
  # - Under "Everything", "Unsorted" is what it was: every unsorted
  #   security, with no slot.
  test "Unsorted follows the view as a category does", %{conn: conn} do
    world = scope_world()

    inside = create_security!(name: "Quillon Bond Fund", ticker: "QBF")
    outside = create_security!(name: "Rookery Shares", ticker: "ROO")
    buy!(world.euro, inside, quantity: "3", price: "90")
    buy!(world.outside, outside, quantity: "4", price: "70")
    put_quote!(inside, Date.utc_today(), "100")
    put_quote!(outside, Date.utc_today(), "75")

    {_lv, html} = live_drained(conn, path(world, "view=#{world.view.id}"))

    assert text(find(html, ~s([data-role="unsorted-positions"]))) == "1"
    assert text(find(html, ~s([data-role="unsorted-value"]))) == "300.00"
    assert text(find(html, ~s(#unsorted [data-role="without-holdings"]))) == "+1 not in the view"
    assert security_rows(html, "#unsorted") == [{"Quillon Bond Fund", "3.00", "300.00"}]

    {_lv, html} = live_drained(conn, path(world, "view=total"))

    assert text(find(html, ~s([data-role="unsorted-positions"]))) == "2"
    assert text(find(html, ~s([data-role="unsorted-value"]))) == "600.00"
    assert find(html, ~s(#unsorted [data-role="without-holdings"])) == []

    assert security_rows(html, "#unsorted") == [
             {"Quillon Bond Fund", "3.00", "300.00"},
             {"Rookery Shares", "4.00", "300.00"}
           ]
  end

  # Acceptance criteria (the closing act of PR γ, the edge-case hunter's #7;
  # the coordinator's decision):
  # - "Unsorted" honours "current positions only" in every scope, as the
  #   categories do: under "Everything" with the toggle on, an unsorted
  #   security no longer held drops into the same slot the categories use,
  #   "+N without holdings", and the count and the value are the held ones.
  # - Under a view that includes every account the same data reads the same
  #   figures, its slot named "+N not in the view".
  # - With the toggle off both scopes list every unsorted security and show
  #   no slot.
  # - The slot's title is Unsorted's own (cascade layer 2): its securities
  #   are unassigned, and some were never held, so the categories' "Assigned
  #   securities no longer held" was wrong twice.
  # - The assignment nudge counts every unsorted security, which is what the
  #   row it links to shows: the visible ones plus the slot's count.
  test "Unsorted honours the toggle in every scope", %{conn: conn} do
    world = scope_world()
    {:ok, everyone} = Buckets.create_view(Actor.owner_ui(), %{name: "Alle Konten"})

    held = create_security!(name: "Quillon Bond Fund", ticker: "QBF")
    sold = create_security!(name: "Sable Watch Co", ticker: "SWC")
    buy!(world.euro, held, quantity: "3", price: "90")
    buy!(world.euro, sold, quantity: "2", price: "50", date: ~D[2026-01-02])
    sell!(world.euro, sold, quantity: "2", price: "55", date: ~D[2026-01-03])
    put_quote!(held, Date.utc_today(), "100")

    unsorted = fn html ->
      %{
        positions: text(find(html, ~s([data-role="unsorted-positions"]))),
        value: text(find(html, ~s([data-role="unsorted-value"]))),
        hidden: text(find(html, ~s(#unsorted [data-role="without-holdings"]))),
        rows: security_rows(html, "#unsorted")
      }
    end

    title = fn html ->
      html
      |> find(~s(#unsorted [data-role="without-holdings"]))
      |> Floki.attribute("title")
    end

    {lv, html} = live_drained(conn, path(world, "view=total"))

    assert unsorted.(html) == %{
             positions: "1",
             value: "300.00",
             hidden: "+1 without holdings",
             rows: [{"Quillon Bond Fund", "3.00", "300.00"}]
           }

    assert title.(html) == ["Unassigned securities without holdings, hidden by the filter"]

    # The nudge's two: the row's one visible security and its "+1".
    assert text(find(html, ~s([data-role="assignment-nudge"] .data-note__body))) =~
             "2 securities are in no category yet"

    off =
      lv
      |> element("form[phx-change='toggle_current_only']")
      |> render_change(%{"current_only" => "false"})

    assert unsorted.(off) == %{
             positions: "2",
             value: "—",
             hidden: "",
             rows: [{"Quillon Bond Fund", "3.00", "300.00"}, {"Sable Watch Co", "0.00", "—"}]
           }

    {lv, html} = live_drained(conn, path(world, "view=#{everyone.id}"))

    assert unsorted.(html) == %{
             positions: "1",
             value: "300.00",
             hidden: "+1 not in the view",
             rows: [{"Quillon Bond Fund", "3.00", "300.00"}]
           }

    assert title.(html) == [
             "Unassigned securities with no position in this view, hidden by the filter"
           ]

    off =
      lv
      |> element("form[phx-change='toggle_current_only']")
      |> render_change(%{"current_only" => "false"})

    assert unsorted.(off) == %{
             positions: "2",
             value: "—",
             hidden: "",
             rows: [{"Quillon Bond Fund", "3.00", "300.00"}, {"Sable Watch Co", "0.00", "—"}]
           }

    {_lv, html} = live_drained(conn, path(world, "view=total&locale=de"))

    assert title.(html) == [
             "Nicht zugeordnete Wertpapiere ohne Bestand, vom Filter ausgeblendet"
           ]
  end

  # Acceptance criteria (the closing act of PR γ, the design critic's #5):
  # - A category the view holds none of counts "0" positions, not "—": a
  #   count is always computable.
  # - Its "Value", "Cost" and "Result" are not computable and print the
  #   value slot's dash (`.cat-na`): muted, at weight 400, never at the
  #   figures' weight. Unsorted's "Cost" and "Result" are the same dash.
  # - A figure that is there carries no such dash.
  test "a category the view holds none of counts 0 and dashes its figures quietly",
       %{conn: conn} do
    world = scope_world()

    {:ok, bonds} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: world.classification.id,
        name: "Anleihen"
      })

    tern = create_security!(name: "Tern Anleihe 2031", ticker: "TRN")

    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        tern.id,
        world.classification.id,
        bonds.id
      )

    buy!(world.outside, tern, quantity: "5", price: "98")
    put_quote!(tern, Date.utc_today(), "99")

    {_lv, html} = live_drained(conn, path(world, "view=#{world.view.id}"))

    assert row(html, "Anleihen") == %{
             positions: "0",
             value: "—",
             cost: "—",
             result: "—",
             hidden: "+1 not in the view"
           }

    summary = summary(html, "Anleihen")

    for role <- ~w(category-value category-invested category-result) do
      assert [_] = Floki.find(summary, ~s([data-role="#{role}"] .cat-na)),
             "#{role} is not the quiet dash"
    end

    assert Floki.find(summary, ~s([data-role="category-positions"] .cat-na)) == []
    assert Floki.find(summary(html, "Plattformen"), ".cat-na") == []

    for role <- ~w(unsorted-invested unsorted-result) do
      assert [_] = find(html, ~s(#unsorted [data-role="#{role}"] .cat-na))
    end

    # Everything holds the bond: its figures are there.
    {_lv, html} = live_drained(conn, path(world, "view=total"))

    assert row(html, "Anleihen") == %{
             positions: "1",
             value: "495.00",
             cost: "490.00",
             result: "+5.00 +1.0%",
             hidden: ""
           }

    assert File.read!("priv/static/app.css") =~
             ~r/\n\.cat-summary \.cat-na \{\n  color: var\(--color-text-muted\);\n  font-weight: 400;\n\}/
  end

  # Acceptance criteria (the closing act of PR γ, the edge-case hunter's #8):
  # - The result cell takes its sign colour from the figure as displayed
  #   (`Format.displayed_sign/2`, U2's rule): a result that reads 0.00 is
  #   unsigned and `is-flat`, never in the gain colour.
  # - Its percent is the house form, the sign and "%" glued on ("+9.1%"),
  #   as U2 and U3 made it on the Trades surfaces.
  test "a result that reads zero is flat, and the percent is glued", %{conn: conn} do
    world = base_world(name: "Flach")

    {:ok, tree} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Flachbaum"})

    {:ok, flat} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Eben"
      })

    level = create_security!(name: "Levelstone Fund", ticker: "LVL")
    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), level.id, tree.id, flat.id)
    deposit!(world, "5000", ~D[2026-01-01])
    buy!(world, level, quantity: "10", price: "100")
    put_quote!(level, Date.utc_today(), "100.0004")

    {_lv, html} = live_drained(conn, "/classifications/#{tree.id}?view=total")

    assert row(html, "Eben").result == "0.00 0.0%"
    [cell] = Floki.find(summary(html, "Eben"), ~s([data-role="category-result"]))
    classes = cell |> Floki.attribute("class") |> hd() |> String.split()
    assert "is-flat" in classes
    refute "is-positive" in classes
  end

  # User story (#1091, review round; the coordinator's decision):
  # As a local portfolio maintainer,
  # I want a dot on a chip of the classification screen to mean that this
  # tree has a plan for that view -- the plan the editor below would show,
  # active or draft,
  # so that the dot and the editor never contradict each other.
  #
  # Acceptance criteria:
  # - A view whose only plan for this tree is a draft carries the dot, and
  #   its editor shows the draft.
  # - A view with a cash target but no plan for this tree carries none.
  # - "Everything" carries the dot when this tree has a no-view plan.
  test "a dot marks the views in which this tree has a plan the editor shows", %{conn: conn} do
    world = scope_world()
    portfolio_id = world.euro.portfolio.id
    {:ok, drafted} = Buckets.create_view(Actor.owner_ui(), %{name: "Sparplan"})
    {:ok, other} = Classifications.create_classification(Actor.owner_ui(), %{name: "Anders"})

    {:ok, other_category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: other.id,
        name: "Anders 1"
      })

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio_id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.7"}],
        view: nil
      )

    # Sparplan: an active plan, duplicated into a draft, then the active
    # version deleted -- the draft is the plan the editor shows.
    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio_id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.3"}],
        view: drafted.id
      )

    [active] =
      Targets.list_plans(portfolio_id,
        classification_id: world.classification.id,
        view: drafted.id
      )

    {:ok, _draft} = Targets.duplicate_plan(Actor.owner_ui(), active.id)
    {:ok, _} = Targets.delete_plan_version(Actor.owner_ui(), active.id)

    # Langfrist: a cash target, and another tree's plan, but none of this
    # tree's.
    :ok = Targets.set_cash_target(Actor.owner_ui(), portfolio_id, "0.1", view: world.view.id)

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio_id,
        other.id,
        [%{category_id: other_category.id, target_weight: "1"}],
        view: world.view.id
      )

    {lv, _html} = live_drained(conn, path(world, "view=total"))

    assert has_element?(lv, "#view-switch-total[data-has-plan]")
    assert has_element?(lv, "#view-switch-#{drafted.id}[data-has-plan]")
    refute has_element?(lv, "#view-switch-#{world.view.id}[data-has-plan]")

    {lv, _html} = live_drained(conn, path(world, "view=#{drafted.id}"))
    assert has_element?(lv, "input[name='weights[#{world.core.id}]'][value='30']")

    # Deleting it, under its live view, deletes that version and loses the dot.
    html = lv |> element("button[phx-click='delete_soll_plan']") |> render_click()
    assert html =~ "Plan deleted"

    assert Targets.list_plans(portfolio_id,
             classification_id: world.classification.id,
             view: drafted.id
           ) == []

    refute has_element?(lv, "#view-switch-#{drafted.id}[data-has-plan]")

    {lv, html} = live_drained(conn, path(world, "view=#{world.view.id}"))
    refute has_element?(lv, "#soll-plan-form")
    assert text(find(html, ~s([data-role="soll-empty"] p))) == "No plan for this view."
  end

  # Acceptance criteria (#1091, review round):
  # - A view deleted after the page loaded is noticed before a plan write:
  #   "Save plan" and "Create plan" degrade the screen to "Everything" with
  #   Wealth's notice, and write nothing -- neither to the gone view nor to
  #   the Everything plan.
  # - The write answers with a refusal that names the view and says nothing
  #   was written, beside the notice (the closing act of PR γ, the edge-case
  #   hunter's #4): the typed weights gave way to Everything's plan, and a
  #   muted hint alone did not say they were lost.
  test "a plan write under a view deleted meanwhile writes nothing and says so",
       %{conn: conn} do
    world = scope_world()
    portfolio_id = world.euro.portfolio.id

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio_id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.8"}],
        view: nil
      )

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio_id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.4"}],
        view: world.view.id
      )

    {lv, _html} = live_drained(conn, path(world, "view=#{world.view.id}"))
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), world.view)

    html =
      lv
      |> form("#soll-plan-form", %{
        "weights" => %{"#{world.core.id}" => "45"},
        "cash_target" => ""
      })
      |> render_submit()

    assert text(find(html, ~s([data-role="view-gone-notice"]))) ==
             "The selected view no longer exists — showing Everything."

    assert refusal(html) =~
             "The view “Langfrist” was deleted meanwhile; nothing was saved."

    assert has_element?(lv, "#view-switch-total.is-active")

    assert [everything] =
             Targets.list_plans(portfolio_id, classification_id: world.classification.id)

    assert everything.view_id == nil

    assert [%{target_weight: weight}] =
             Targets.list_targets(portfolio_id,
               classification_id: world.classification.id,
               view: nil
             )

    assert Decimal.equal?(weight, Decimal.new("0.8"))

    # Create, on a view with no plan, deleted meanwhile.
    {:ok, empty} = Buckets.create_view(Actor.owner_ui(), %{name: "Sparplan"})
    {lv, _html} = live_drained(conn, path(world, "view=#{empty.id}"))
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), empty)

    html = lv |> element("button[phx-click='create_soll_plan']") |> render_click()

    assert text(find(html, ~s([data-role="view-gone-notice"]))) ==
             "The selected view no longer exists — showing Everything."

    assert refusal(html) =~
             "The view “Sparplan” was deleted meanwhile; no plan was created."

    # Delete, on a view with a plan, deleted meanwhile.
    {:ok, planned} = Buckets.create_view(Actor.owner_ui(), %{name: "Ruhestand"})

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        portfolio_id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.2"}],
        view: planned.id
      )

    {lv, _html} = live_drained(conn, path(world, "view=#{planned.id}"))
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), planned)

    html = lv |> element("button[phx-click='delete_soll_plan']") |> render_click()

    assert refusal(html) =~
             "The view “Ruhestand” was deleted meanwhile; nothing was deleted."

    assert [_everything] =
             Targets.list_plans(portfolio_id, classification_id: world.classification.id)

    # In German.
    {:ok, reserve} = Buckets.create_view(Actor.owner_ui(), %{name: "Notgroschen"})
    {lv, _html} = live_drained(conn, path(world, "view=#{reserve.id}&locale=de"))
    {:ok, _} = Buckets.delete_view(Actor.owner_ui(), reserve)

    html = lv |> element("button[phx-click='create_soll_plan']") |> render_click()

    assert refusal(html) =~
             "Die Ansicht „Notgroschen“ wurde inzwischen gelöscht; es wurde kein Plan angelegt."
  end

  # Acceptance criteria (#1091, review round): a view that matches no
  # accounts says so, in Wealth's words, instead of leaving every row "—"
  # without a reason.
  test "a view that matches no accounts says so", %{conn: conn} do
    world = scope_world()
    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Leer"})
    {:ok, nothing} = Buckets.create_view(Actor.owner_ui(), %{name: "Nichts", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), nothing, [bucket.id], [])

    {_lv, html} = live_drained(conn, path(world, "view=#{nothing.id}"))

    assert text(find(html, ~s([data-role="view-matches-nothing"]))) ==
             "This view matches no accounts — its included buckets are empty or no longer " <>
               "assigned. Edit the view under Views or tag accounts into its buckets."

    {_lv, html} = live_drained(conn, path(world, "view=#{world.view.id}"))
    assert find(html, ~s([data-role="view-matches-nothing"])) == []
  end

  # Acceptance criteria (#1091; G2 of the review round): a built-in tree,
  # which has no editor, gets the switcher and reads the view as a custom
  # tree does.
  test "a built-in tree reads the view too, with no editor", %{conn: conn} do
    world = scope_world()
    :ok = Classifications.ensure_builtins()

    currency =
      Enum.find(Classifications.list_classifications(), &(&1.built_in and &1.key == "currency"))

    euro_name =
      currency.id
      |> Classifications.list_categories()
      |> Enum.find(&(&1.key == "EUR"))
      |> Map.fetch!(:name)

    {lv, html} =
      live_drained(conn, "/classifications/#{currency.id}?view=#{world.view.id}")

    assert has_element?(lv, ".workspace-section--controls .view-switcher")
    assert has_element?(lv, "#view-switch-#{world.view.id}.is-active")
    refute has_element?(lv, "#soll-editor")

    # In the view: Kestrel and Lumen's 8 units; Corvid and Pellucid are not.
    assert %{positions: "2", value: "12,300.00", cost: "10,200.00", hidden: "+2 not in the view"} =
             row(html, euro_name)

    {_lv, html} = live_drained(conn, "/classifications/#{currency.id}?view=total")

    assert %{positions: "3", value: "18,300.00", hidden: "+1 without holdings"} =
             row(html, euro_name)
  end

  # Acceptance criteria (#1091; G3 of the review round): an old
  # `?soll_view=` link opens the screen on the active view and is otherwise
  # ignored.
  test "an old soll_view link opens on the active view", %{conn: conn} do
    world = scope_world()

    for {view_id, weight} <- [{nil, "0.8"}, {world.view.id, "0.4"}] do
      {:ok, _} =
        Targets.set_targets(
          Actor.owner_ui(),
          world.euro.portfolio.id,
          world.classification.id,
          [%{category_id: world.core.id, target_weight: weight}],
          view: view_id
        )
    end

    {lv, html} = live_drained(conn, path(world, "soll_view=#{world.view.id}"))

    assert has_element?(lv, "#view-switch-total.is-active")
    assert text(find(html, ~s([data-role="soll-editor-scope"]))) == "for view Everything"
    assert has_element?(lv, "input[name='weights[#{world.core.id}]'][value='80']")
  end

  # Board 10 (review round, design): the "+N not in the view" suffix sits
  # beside the name and drops under it; it never cuts the name to an
  # ellipsis. The name cell wraps at every width, not only on the phone,
  # and the swatch keeps its size.
  test "the name cell wraps its suffix at every width, and the swatch keeps its size" do
    top_level =
      "priv/static/app.css"
      |> File.read!()
      |> then(&Regex.replace(~r/@media[^{]*(\{(?:[^{}]++|(?1))*\})/, &1, ""))

    assert top_level =~
             ~r/\.cat-summary \.cat-name\s*\{[^}]*flex-wrap:\s*wrap;[^}]*row-gap:\s*0;/s

    assert top_level =~ ~r/\.cat-summary \.cat-swatch\s*\{[^}]*flex:\s*none;/s
  end

  # User story (#1091, found while drawing; pick J10 A):
  # As a German-speaking maintainer,
  # I want the classification screen to name the scope in the words every
  # other screen uses,
  # so that "Ansicht" and "Alles" mean one thing across the app.
  #
  # Acceptance criteria:
  # - The editor's head reads "für Ansicht Langfrist", the basis line
  #   "Ansicht Langfrist · in EUR · …", the hidden count "+2 nicht in der
  #   Ansicht".
  # - Nothing on the classification screen says "Sicht" or "Gesamt".
  test "the German screen says Ansicht and Alles, never Sicht or Gesamt", %{conn: conn} do
    world = scope_world()

    {:ok, _} =
      Targets.set_targets(
        Actor.owner_ui(),
        world.euro.portfolio.id,
        world.classification.id,
        [%{category_id: world.core.id, target_weight: "0.6"}],
        view: nil
      )

    {_lv, html} = live_drained(conn, path(world, "view=#{world.view.id}&locale=de"))

    assert text(find(html, ~s(#soll-editor [data-role="soll-editor-scope"]))) ==
             "für Ansicht Langfrist"

    assert basis(html) ==
             "Ansicht Langfrist · in EUR · Ergebnis: heutige Zusammensetzung, keine Periodenrendite"

    assert row(html, "Kern global").hidden == "+2 nicht in der Ansicht"

    detail = html |> find(".classifications-detail") |> Floki.raw_html()

    assert detail =~ "Aus anderer Ansicht übernehmen…"
    assert detail =~ "— Ansicht wählen —"
    assert detail =~ ~r/<option value="total">\s*Alles\s*<\/option>/
    refute detail =~ ~r/\bSicht\b/u
    refute detail =~ ~r/\bGesamt\b/u
  end
end
