defmodule PortfolixirWeb.SecurityDetailOverviewTest do
  # Review C7 / A8 of 2026-09-12, variant A (owner's pick 2026-09-14): the
  # detail pane's first tab is a reading surface, not the master-data form.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Knowledge
  alias Portfolixir.WorldFixtures

  defp world do
    world = WorldFixtures.base_world()

    security =
      WorldFixtures.create_security!(
        name: "Helios Solar Systems SE",
        ticker: "HLSO",
        isin: "DE000HLSO0001",
        asset_class: "equity"
      )

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{feed: "PORTFOLIO_PERFORMANCE"})

    WorldFixtures.deposit!(world, "5000", ~D[2026-01-02])
    WorldFixtures.buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-02])

    WorldFixtures.put_quotes!(security, [
      {~D[2026-01-02], "100.00"},
      {Date.add(Portfolixir.Clock.today(), -1), "108.00"},
      {Portfolixir.Clock.today(), "110.00"}
    ])

    %{world: world, security: security}
  end

  defp panel(view), do: view |> element("#detail-tab-panel-overview") |> render()

  # User story:
  # As a local portfolio maintainer opening a security,
  # I want its first tab to answer "what is this, how does it stand, what do I
  # think about it" instead of presenting an edit form,
  # so that reading a position does not start with eight input fields.
  #
  # Acceptance criteria:
  # - The overview renders no input, select or textarea until an edit
  #   affordance is used (the spine's progressive-disclosure rule).
  # - It carries the six figures — latest price, day change, 1Y, holding,
  #   value, unrealised — the price chart, the thesis state and the note.
  # - The feed is a translated word, never the stored constant (issue 785).
  describe "the overview as a reading surface" do
    test "opens with figures, chart, thesis and note, and no input element", %{conn: conn} do
      %{security: security} = world()

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      html = panel(view)

      refute html =~ "<input"
      refute html =~ "<select"
      refute html =~ "<textarea"

      for label <- ["Latest price", "Day change", "1Y", "Holding", "Value", "Unrealised"] do
        assert html =~ label, "the overview is missing the #{label} figure"
      end

      # The tab's own chart, the thesis card, the note card and the basis line.
      assert has_element?(view, "#detail-tab-panel-overview svg")
      assert has_element?(view, ~s([data-role="overview-thesis"]))
      assert has_element?(view, ~s([data-role="overview-note"]))
      assert has_element?(view, ~s([data-role="overview-basis"]))

      # #785: the feed reads as words, never as the stored constant, and the
      # asset class as its label.
      basis = view |> element(~s([data-role="overview-basis"])) |> render()
      assert basis =~ "Portfolio Performance"
      refute basis =~ "PORTFOLIO_PERFORMANCE"
      assert basis =~ "Equity"

      # The identifiers stay on the pane's header, where they always were.
      assert view |> element(".detail-pane-sub") |> render() =~ "DE000HLSO0001"
    end

    test "the figures read the position: quantity, depot, value and unrealised with its basis",
         %{conn: conn} do
      %{security: security} = world()

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      html = panel(view)

      # 10 shares bought at 100, priced at 110: 1,100.00 value, +100.00 (+10 %).
      # #1201 (Sprint 21 γ2, board 02 ⑦) flips the percent on purpose to
      # DESIGN.md's form: one decimal, the sign glued on, no space.
      assert html =~ "10.0000"
      assert html =~ "Main Depot"
      assert html =~ "1,100.00"
      assert html =~ "+100.00"
      assert html =~ "+10.0%"
      refute html =~ "+10.00 %"

      # The unrealised figure states what it is measured against.
      unrealised = view |> element(~s([data-role="overview-unrealised"])) |> render()
      assert unrealised =~ "average cost"
    end

    # The money identity the figures rest on: value is the sum of the priced
    # rows and unrealised is that value less the cost the ledger recorded. A
    # row the app cannot price makes the total a dash — never a smaller number
    # that reads as a total.
    test "a held but unpriced position keeps its quantity and prints dashes for value and result",
         %{conn: conn} do
      world = WorldFixtures.base_world()

      security =
        WorldFixtures.create_security!(name: "Placeholder Anleihe 2031", ticker: nil, isin: nil)

      # #1316 (ADR-0010): a bought position is valued at its trade price, so
      # an unpriced one is delivered in, with no quote and no own trade.
      {:ok, _delivery} =
        Portfolixir.Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          security_id: security.id,
          type: "inbound_delivery",
          date: ~D[2026-02-02],
          quantity: "5",
          currency_code: "EUR"
        })

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      assert view |> element(~s([data-role="overview-holding"])) |> render() =~ "5.0000"
      assert view |> element(~s([data-role="overview-value"])) |> render() =~ "—"
      assert view |> element(~s([data-role="overview-unrealised"])) |> render() =~ "—"
    end

    test "a position held in two depots sums its quantity and says how many depots hold it",
         %{conn: conn} do
      world = WorldFixtures.base_world()

      %{cash: cash2, depot: depot2} =
        WorldFixtures.add_depot(world.portfolio,
          depot_name: "Second Depot",
          cash_name: "Second Cash"
        )

      security = WorldFixtures.create_security!(name: "Two Depot AG", ticker: "TWO")

      WorldFixtures.deposit!(world, "5000", ~D[2026-02-02])
      WorldFixtures.buy!(world, security, quantity: "4", price: "100", date: ~D[2026-02-02])

      WorldFixtures.deposit!(%{portfolio: world.portfolio, cash: cash2}, "5000", ~D[2026-02-02])

      WorldFixtures.buy!(
        %{portfolio: world.portfolio, depot: depot2, cash: cash2},
        security,
        quantity: "6",
        price: "100",
        date: ~D[2026-02-02]
      )

      WorldFixtures.put_quote!(security, Portfolixir.Clock.today(), "110")

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      holding = view |> element(~s([data-role="overview-holding"])) |> render()
      assert holding =~ "10.0000"
      assert holding =~ "2 depots"

      # 10 × 110 = 1,100.00 against a 1,000.00 cost across both depots.
      assert view |> element(~s([data-role="overview-value"])) |> render() =~ "1,100.00"
      assert view |> element(~s([data-role="overview-unrealised"])) |> render() =~ "+100.00"
    end

    test "a security without a position prints dashes rather than zeros", %{conn: conn} do
      security = WorldFixtures.create_security!(name: "Unheld AG", ticker: "UNHL")

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      holding = view |> element(~s([data-role="overview-holding"])) |> render()
      value = view |> element(~s([data-role="overview-value"])) |> render()

      assert holding =~ "—"
      assert value =~ "—"
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the master data one intent away behind "Edit",
  # so that the fields I rarely change do not occupy the surface I read daily.
  #
  # Acceptance criteria:
  # - The pane's header carries an Edit control.
  # - It opens the security dialog on its confirm step, pre-filled.
  # - The overview keeps no inline master-data form.
  describe "editing the master data" do
    test "the header's Edit control opens the pre-filled dialog", %{conn: conn} do
      %{security: security} = world()

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      refute has_element?(view, "#overview-details-form")

      view |> element("#detail-edit") |> render_click()

      assert has_element?(view, "#security-dialog-form")
      assert render(view) =~ "Helios Solar Systems SE"
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the personal note readable on the overview and editable on request,
  # so that the note is visible without a form standing open under it.
  #
  # Acceptance criteria:
  # - With no note the card says so and offers to add one; no field renders.
  # - The edit affordance reveals the form; saving stores the note, closes the
  #   form again and shows the text.
  describe "the personal note" do
    test "reveals its form on request and saves the note", %{conn: conn} do
      %{security: security} = world()

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      refute has_element?(view, "#overview-notes-form")

      view |> element("#overview-note-edit") |> render_click()
      assert has_element?(view, "#overview-notes-form")

      view
      |> form("#overview-notes-form", %{"security" => %{"note" => "Core position, hold."}})
      |> render_submit()

      assert Catalog.get_security(security.id).note == "Core position, hold."
      refute has_element?(view, "#overview-notes-form")
      assert panel(view) =~ "Core position, hold."
    end

    # The editor belongs to the security it was opened on: selecting another
    # one must not hand the operator a form they never opened, pre-filled with
    # the other security's note.
    test "the open editor does not follow a change of security", %{conn: conn} do
      %{security: first} = world()
      second = WorldFixtures.create_security!(name: "Second AG", ticker: "SEC2")

      {:ok, view, _html} = live(conn, "/securities/#{first.id}")

      view |> element("#overview-note-edit") |> render_click()
      assert has_element?(view, "#overview-notes-form")

      view |> render_patch("/securities/#{second.id}")

      refute has_element?(view, "#overview-notes-form")
      assert has_element?(view, "#overview-note-edit")
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the thesis state from the research log on the overview,
  # so that the position and what I believe about it are read together
  # (ADR-0044 §7).
  #
  # Acceptance criteria:
  # - With no entry the card says no thesis is recorded.
  # - With one the card shows its status and the thesis text, and links to the
  #   Research tab.
  describe "the thesis card" do
    test "shows the recorded thesis with its status and a link to Research", %{conn: conn} do
      %{security: security} = world()

      {:ok, _note} =
        Knowledge.append_note(Actor.owner_ui(), %{
          security_id: security.id,
          author: "agent",
          kind: "thesis",
          body: "Margin holds through the cycle.",
          source_quality: "primary",
          conviction: "high",
          as_of: ~D[2026-06-01]
        })

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      thesis = view |> element(~s([data-role="overview-thesis"])) |> render()
      assert thesis =~ "Margin holds through the cycle."
      assert thesis =~ "Intact"

      # The card leads to the log it reads from.
      view
      |> element(~s([data-role="overview-thesis"] button[phx-value-tab="research"]))
      |> render_click()

      assert has_element?(view, "#detail-tab-panel-research")
    end

    test "says so when the log holds no thesis", %{conn: conn} do
      %{security: security} = world()

      {:ok, view, _html} = live(conn, "/securities/#{security.id}")

      assert view |> element(~s([data-role="overview-thesis"])) |> render() =~
               "No thesis recorded yet."
    end
  end

  test "the overview reads in German", %{conn: conn} do
    %{security: security} = world()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?locale=de")

    html = panel(view)
    assert html =~ "Letzter Kurs"
    assert html =~ "Bestand"
    assert html =~ "Wert"
    assert html =~ "Unrealisiert"
    assert render(view) =~ "Bearbeiten"
  end

  # A security whose day change is a fraction of a basis point: 1,000.00
  # yesterday, 1,000.04 today (+0.004 %), and 800.00 a year and more ago,
  # when ten units were bought (+25.005 % over the year and on cost).
  defp flat_day_world do
    world = WorldFixtures.base_world()
    today = Portfolixir.Clock.today()

    security =
      WorldFixtures.create_security!(
        name: "Larkspur Rail AG",
        ticker: "LKRL",
        isin: "DE000000000L",
        asset_class: "equity"
      )

    WorldFixtures.deposit!(world, "10000", Date.add(today, -400))
    WorldFixtures.buy!(world, security, quantity: "10", price: "800", date: Date.add(today, -400))

    WorldFixtures.put_quotes!(security, [
      {Date.add(today, -400), "800.00"},
      {Date.add(today, -1), "1000.00"},
      {today, "1000.04"}
    ])

    %{world: world, security: security}
  end

  defp figure(view, role) do
    view
    |> element(~s([data-role="#{role}"]))
    |> render()
    |> Floki.parse_fragment!()
  end

  defp class_of(fragment, selector) do
    fragment |> Floki.find(selector) |> Floki.attribute("class") |> List.first("")
  end

  # User story (#1201, Sprint 21 γ2; board 02, ⑦): As the operator reading a
  # security's Overview tab, I want its percentages in the app's one percent
  # form, coloured by the figure as shown, so that a day change of +0,0041 %
  # no longer prints "0,00 %" in the gain colour and the tab reads as the
  # Holdings and Trades tabs do.
  #
  # Acceptance criteria:
  # - Tagesänderung and 1J print one decimal with the sign glued on and no
  #   space ("0,0%", "+25,0%"); a percent that rounds to 0,0 is unsigned and
  #   in body ink (`is-flat`), never in the gain colour.
  # - Unrealisiert keeps its amount at two places, coloured by the amount as
  #   shown; its sub-line's percent ("+25,0%") is a `decimal-positive` /
  #   `decimal-negative` span inside the muted line.
  test "the Overview's percentages read one decimal, the sign glued on, coloured as shown",
       %{conn: conn} do
    %{security: security} = flat_day_world()

    {:ok, view, _html} = live(conn, "/securities/#{security.id}?locale=de")

    day = figure(view, "overview-day-change")
    assert day |> Floki.find("dd") |> Floki.text() |> String.trim() == "0,0%"
    assert class_of(day, "dd") =~ "is-flat"
    refute class_of(day, "dd") =~ "is-positive"

    one_y = figure(view, "overview-1y")
    assert one_y |> Floki.find("dd") |> Floki.text() =~ "+25,0%"
    assert class_of(one_y, "dd") =~ "is-positive"

    unrealised = figure(view, "overview-unrealised")
    assert unrealised |> Floki.find("dd") |> Floki.text() =~ "+2.000,40"
    assert class_of(unrealised, "dd") =~ "is-positive"

    assert ["+25,0%"] ==
             unrealised
             |> Floki.find(".overview-metric__sub span.decimal-positive")
             |> Enum.map(&Floki.text/1)

    refute Floki.raw_html(unrealised) =~ " %"
  end

  # User story (#1201, Sprint 21 γ2; board 02, ⑦ and found while drawing 4):
  # As the operator scanning the securities list, I want its Tagesänderung %,
  # Performance 1M and Performance 1J columns and the phone row's day change
  # in the same percent form and colour rule as the Overview tab, so that no
  # list cell keeps the retired "+0,42 %" form.
  #
  # Acceptance criteria:
  # - The three percent columns print one decimal with the sign glued on;
  #   a percent that rounds to 0,0 is unsigned and `is-flat`.
  # - The phone row's day change takes the same form and colour.
  test "the list's percent columns and the phone row's day change take the same form",
       %{conn: conn} do
    %{security: security} = flat_day_world()

    {:ok, view, _html} = live(conn, "/securities?locale=de")

    view
    |> element("#securities-table")
    |> render_hook("set_columns", %{
      "columns" => ["name", "day_change_pct", "performance_1m", "performance_1y"]
    })

    row = view |> element("#security-row-#{security.id}") |> render() |> Floki.parse_fragment!()

    cells =
      row
      |> Floki.find("td.num span")
      |> Enum.map(&{String.trim(Floki.text(&1)), &1 |> Floki.attribute("class") |> List.first()})

    assert {"0,0%", "is-flat"} in cells
    assert {"+25,0%", "decimal-positive"} in cells
    refute Floki.raw_html(row) =~ " %"

    phone = figure(view, "phone-row")
    change = Floki.find(phone, ".phone-row__figure2 span")
    assert change |> Floki.text() |> String.trim() == "0,0%"
    assert change |> Floki.attribute("class") |> List.first() == "is-flat"
  end
end
