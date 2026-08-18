defmodule PortfolixirWeb.SnapshotsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.WorldFixtures

  # User story (Andi, 2026-07-16, ADR-0027):
  # As a local portfolio maintainer restructuring my strategy,
  # I want a Wealth tab where I freeze the current state as a named snapshot
  # and later see, as numbers and as a chart, whether keeping those holdings
  # would have beaten my real performance since,
  # so that the "was the restructuring worth it?" answer lives in the app.
  #
  # Acceptance criteria:
  # - The Snapshots tab lists snapshots and creates one (name, scope, as-of).
  # - Selecting a snapshot shows the comparison: as-of value, frozen value
  #   today, snapshot price return, real TTWROR since — plus the basis
  #   (gross, price-return only) as microcopy (UX-DR11).
  # - The chart's data is also reachable as a table (UX-DR10).
  # - Unvalued securities are surfaced as a gap notice, never silently.
  # - Deleting a snapshot removes it from the list.

  defp seeded_world do
    world = WorldFixtures.base_world(name: "Snap", currency: "EUR")
    sec = WorldFixtures.create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")

    WorldFixtures.deposit!(world, "10000", ~D[2026-01-02], [])
    WorldFixtures.buy!(world, sec, quantity: "5", price: "100", date: ~D[2026-01-05])
    WorldFixtures.put_quote!(sec, ~D[2026-02-14], "110")
    WorldFixtures.put_quote!(sec, ~D[2026-03-10], "120")

    Map.put(world, :security, sec)
  end

  test "creates a snapshot from the form and lists it", %{conn: conn} do
    seeded_world()

    {:ok, view, _html} = live(conn, "/snapshots")

    view
    |> form("#snapshot-create-form", %{
      "snapshot" => %{"name" => "Before restructuring", "as_of" => "2026-02-15", "view_id" => ""}
    })
    |> render_submit()

    assert render(view) =~ "Before restructuring"
    assert [snapshot] = Snapshots.list_snapshots()
    assert snapshot.name == "Before restructuring"
    assert snapshot.as_of == ~D[2026-02-15]
    assert snapshot.view_id == nil
  end

  test "selecting a snapshot renders the comparison with basis and table", %{conn: conn} do
    seeded_world()

    {:ok, _snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Before restructuring",
        as_of: ~D[2026-02-15]
      })

    {:ok, view, _html} = live(conn, "/snapshots")

    html =
      view
      |> element("[data-role=snapshot-row] button[phx-click=select_snapshot]")
      |> render_click()

    # KPI values: frozen 5 × 110 = 550 at as-of; 5 × 120 = 600 today.
    assert html =~ "550.00"
    assert html =~ "600.00"

    # Self-describing basis (UX-DR11) and chart-as-table (UX-DR10).
    assert html =~ "gross"
    assert has_element?(view, "[data-role=comparison-table]")
    assert has_element?(view, "svg[role=img]")
  end

  test "unvalued securities appear as a gap notice", %{conn: conn} do
    world = seeded_world()
    ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
    WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

    {:ok, _} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    html =
      view
      |> element("[data-role=snapshot-row] button[phx-click=select_snapshot]")
      |> render_click()

    assert html =~ "Unquoted"
    assert has_element?(view, "[data-role=comparison-gaps]")
  end

  test "deletes a snapshot", %{conn: conn} do
    seeded_world()

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Old marker", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    view
    |> element("button[phx-click=delete_snapshot][phx-value-id='#{snapshot.id}']")
    |> render_click()

    refute render(view) =~ "Old marker"
    assert Snapshots.list_snapshots() == []
  end

  # Review finding: deleting a snapshot that vanished in another tab (or via
  # API/MCP) crashed the LiveView through a {:ok, _} match on :not_found.
  test "deleting an already-deleted snapshot does not crash", %{conn: conn} do
    seeded_world()

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Racy", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    {:ok, _} = Snapshots.delete_snapshot(Actor.owner_ui(), snapshot.id)

    html =
      view
      |> element("button[phx-click=delete_snapshot][phx-value-id='#{snapshot.id}']")
      |> render_click()

    refute html =~ "Racy"
    assert Snapshots.list_snapshots() == []
  end

  # Steve UAT finding: a failed create (duplicate name) used to collapse the
  # details and swallow the error — the form now stays open with an associated
  # error message.
  test "a duplicate snapshot name keeps the form open with a visible error", %{conn: conn} do
    seeded_world()

    {:ok, _} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Twice", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    html =
      view
      |> form("#snapshot-create-form", %{
        "snapshot" => %{"name" => "Twice", "as_of" => "2026-03-01", "view_id" => ""}
      })
      |> render_submit()

    assert html =~ ~s(id="snapshot-form-error")
    assert html =~ "has already been taken"
    assert has_element?(view, "details.snapshot-create[open]")
    assert has_element?(view, "input[name='snapshot[name]'][aria-invalid='true']")
  end

  test "shows the empty state until accounts exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/snapshots")
    assert html =~ "Create a depot and cash account first"
  end

  test "ignores crafted non-integer event payloads instead of crashing", %{conn: conn} do
    seeded_world()

    {:ok, _} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Sturdy", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")

    assert render_click(view, "select_snapshot", %{"id" => "abc"}) =~ "Sturdy"
    assert render_click(view, "delete_snapshot", %{"id" => "abc"}) =~ "Sturdy"
    assert [_] = Snapshots.list_snapshots()
  end

  test "selecting a vanished snapshot flashes an error instead of crashing", %{conn: conn} do
    seeded_world()

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Fleeting", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")
    {:ok, _} = Snapshots.delete_snapshot(Actor.owner_ui(), snapshot.id)

    html = render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})
    assert html =~ "Could not load the comparison"

    # The canonical inline-result alert region (design-critic fix round),
    # not the legacy .alert-error paragraph.
    assert has_element?(
             view,
             "#snapshots-action-result-alert[role=alert]",
             "Could not load the comparison"
           )
  end

  test "a view-scoped snapshot lists its view name; deleting another snapshot keeps the comparison",
       %{conn: conn} do
    seeded_world()
    {:ok, view_record} = Portfolixir.Buckets.create_view(Actor.owner_ui(), %{name: "Stocks"})

    {:ok, scoped} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{
        name: "Scoped",
        as_of: ~D[2026-02-15],
        view_id: view_record.id
      })

    {:ok, other} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Other", as_of: ~D[2026-02-15]})

    {:ok, view, html} = live(conn, "/snapshots")
    assert html =~ "Stocks"

    render_click(view, "select_snapshot", %{"id" => "#{scoped.id}"})
    html = render_click(view, "delete_snapshot", %{"id" => "#{other.id}"})

    # The unrelated delete leaves the selected comparison on screen.
    assert has_element?(view, "[data-role=snapshot-comparison]")
    refute html =~ "Other"
  end

  test "a snapshot whose holdings are all unquoted renders the nothing-to-compare state",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Bare", currency: "EUR")
    ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
    WorldFixtures.deposit!(world, "1000", ~D[2026-01-02], [])
    WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

    {:ok, snapshot} =
      Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Bare marker", as_of: ~D[2026-02-15]})

    {:ok, view, _html} = live(conn, "/snapshots")
    render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

    assert has_element?(view, "[data-role=comparison-empty]")
    assert has_element?(view, "[data-role=comparison-gaps]")
  end

  # User story (#671, EXPERIENCE.md → Component Patterns → Snapshots
  # comparison; DESIGN.md → data-note, disclosure, value-slot):
  # As a local portfolio maintainer reading the counterfactual comparison,
  # I want the snapshots surface to follow the design language — the
  # comparison primary, findings as data notes, the chart's table behind the
  # one quiet disclosure, and absent values quiet —
  # so that the surface conforms to the spec instead of its own idiom.
  #
  # Acceptance criteria:
  # - The comparison section renders above the snapshot list (the comparison
  #   is the surface; the list is secondary).
  # - The basis line states what is compared; the v1 gross/price-only
  #   limitation is a note-severity data note, not prose.
  # - Excluded securities render as an attention data note with glyph + word.
  # - A not-computable KPI renders as a quiet muted dash, not at value weight.
  # - The data-as-table disclosure is the quiet control with a stated purpose
  #   line (≤ 90 characters) and the defined chevron, as is the create form's.
  describe "design-language alignment (#671)" do
    test "the comparison renders above the snapshot list", %{conn: conn} do
      seeded_world()

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      html = render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      comparison_at = :binary.match(html, ~s(data-role="snapshot-comparison")) |> elem(0)
      list_at = :binary.match(html, ~s(data-role="snapshot-list")) |> elem(0)
      assert comparison_at < list_at
    end

    test "the basis is a line and the v1 limitation a note-severity data note",
         %{conn: conn} do
      seeded_world()

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      basis = view |> element(~s([data-role="comparison-basis"])) |> render()
      assert basis =~ "2026-02-15"
      assert basis =~ "EUR"

      note = view |> element(~s([data-role="comparison-limitation"])) |> render()
      assert note =~ "data-note--note"
      assert note =~ "Note"
      assert note =~ "gross"
    end

    test "excluded securities render as an attention data note", %{conn: conn} do
      world = seeded_world()
      ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
      WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      gaps = view |> element(~s([data-role="comparison-gaps"])) |> render()
      assert gaps =~ "data-note--attention"
      assert gaps =~ "Attention"
      assert gaps =~ "Unquoted"
    end

    test "a not-computable KPI is a quiet dash, not at value weight", %{conn: conn} do
      world = WorldFixtures.base_world(name: "Bare", currency: "EUR")
      ghost = WorldFixtures.create_security!(name: "Unquoted", ticker: "GHST", currency: "EUR")
      WorldFixtures.deposit!(world, "1000", ~D[2026-01-02], [])
      WorldFixtures.buy!(world, ghost, quantity: "3", price: "10", date: ~D[2026-01-20])

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Bare marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      assert has_element?(view, ".stat .stat-empty")
      refute has_element?(view, ".stat strong .stat-empty")
    end

    test "both disclosures use the quiet summary; the table states its purpose",
         %{conn: conn} do
      seeded_world()

      {:ok, snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{name: "Marker", as_of: ~D[2026-02-15]})

      {:ok, view, _html} = live(conn, "/snapshots")
      render_click(view, "select_snapshot", %{"id" => "#{snapshot.id}"})

      create = view |> element(".snapshot-create summary") |> render()
      assert create =~ "disclosure-summary"
      assert create =~ "disclosure-chevron"

      table_disclosure =
        view |> element(~s(details[data-role="comparison-disclosure"])) |> render()

      assert table_disclosure =~ "disclosure-summary"
      assert table_disclosure =~ "Data as table"
      assert table_disclosure =~ ~s(data-role="disclosure-purpose")
    end
  end

  # User story (#708, ADR-0027 amendment §4 — review-blocking):
  # As a maintainer who restructured a depot,
  # I want to see what the trades cost and whether they are earned back,
  # never the flattering pre-cost figure on its own,
  # so that "were the changes right?" and "have they paid for themselves?" are
  # both answered instead of one number serving neither.
  #
  # Acceptance criteria:
  # - When trades cost something, the surface shows the pre-cost return, the
  #   cost total and the recovery state TOGETHER.
  # - When nothing was paid, the group is absent — a second identical figure
  #   beside the real return would be noise dressed as insight.
  # - The basis line names which costs left the return and which stayed in it.
  describe "transaction costs on the comparison (#708)" do
    # A buy's gross_amount is INCLUSIVE of its fees (`Projection.buy_cost/1`),
    # and the top-up is funded to the cent, so nothing but the fee separates
    # the real side from the frozen one. A fixture that passes a bare
    # quantity x price beside a fee describes a trade whose fee never leaves
    # the cash account, and the pre-cost figure then removes a cost nobody
    # paid.
    # Its own world rather than `seeded_world/0`: that one leaves ~9,500 idle
    # cash, and cash drags the real return far below an equity-only frozen
    # side no matter what a fee does — so no fee could ever produce the middle
    # recovery state there.
    #
    # Here the portfolio is fully invested and the top-up is funded to the
    # cent, so nothing but the fee separates the two sides:
    #
    #   as-of 2026-02-15: 5 shares at 110 = 550, no cash -> 5 x 120 today.
    #   in-window: deposit 110 + fee, buy 1 at 110 with that fee. A buy's
    #   gross_amount is INCLUSIVE of its fee (`Projection.buy_cost/1`), so a
    #   fixture passing a bare quantity x price beside a fee would describe a
    #   trade whose fee never leaves the cash account.
    defp costly_world(fees) do
      world = WorldFixtures.base_world(name: "Snap", currency: "EUR")
      sec = WorldFixtures.create_security!(name: "EUR Stock", ticker: "EURS", currency: "EUR")

      book = fn attrs ->
        {:ok, _} =
          Ledger.create_transaction(
            Actor.owner_ui(),
            Map.merge(%{portfolio_id: world.portfolio.id, currency_code: "EUR"}, attrs)
          )
      end

      book.(%{
        cash_account_id: world.cash.id,
        type: "deposit",
        date: ~D[2026-01-02],
        gross_amount: "550"
      })

      book.(%{
        cash_account_id: world.cash.id,
        securities_account_id: world.depot.id,
        security_id: WorldFixtures.security_id_for(sec),
        type: "buy",
        date: ~D[2026-01-05],
        quantity: "5",
        price: "110",
        gross_amount: "550"
      })

      WorldFixtures.put_quote!(sec, ~D[2026-01-05], "110")
      WorldFixtures.put_quote!(sec, ~D[2026-02-14], "110")
      WorldFixtures.put_quote!(sec, ~D[2026-03-10], "120")

      {:ok, _snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{
          name: "Before restructuring",
          as_of: ~D[2026-02-15]
        })

      funding = Decimal.add(Decimal.new("110"), Decimal.new(fees))

      book.(%{
        cash_account_id: world.cash.id,
        type: "deposit",
        date: ~D[2026-02-20],
        gross_amount: Decimal.to_string(funding, :normal)
      })

      book.(%{
        cash_account_id: world.cash.id,
        securities_account_id: world.depot.id,
        security_id: WorldFixtures.security_id_for(sec),
        type: "buy",
        date: ~D[2026-02-20],
        quantity: "1",
        price: "110",
        gross_amount: Decimal.to_string(funding, :normal),
        fees: fees
      })

      Map.merge(world, %{security: sec, book: book})
    end

    defp open_comparison(conn) do
      {:ok, view, _html} = live(conn, "/snapshots")

      view
      |> element("[data-role=snapshot-row] button[phx-click=select_snapshot]")
      |> render_click()

      view
    end

    test "the three figures appear together, never the pre-cost one alone", %{conn: conn} do
      costly_world("40")

      view = open_comparison(conn)

      assert has_element?(view, "#comparison-costs [data-role='pre-cost-return']")
      assert has_element?(view, "#comparison-costs [data-role='transaction-costs']")
      assert has_element?(view, "#comparison-costs [data-role='cost-recovery']")

      # The cost figure is the money, in the base currency.
      costs = view |> element("#comparison-costs [data-role='transaction-costs']") |> render()
      assert costs =~ "40"
      assert costs =~ "EUR"
    end

    test "with nothing paid the group is absent rather than duplicating a figure", %{conn: conn} do
      costly_world("0")

      view = open_comparison(conn)

      refute has_element?(view, "#comparison-costs")
      # The comparison itself still renders.
      assert has_element?(view, "[data-role='comparison-basis']")
    end

    # The three states of ADR-0027 amendment §3 are the point of the feature, so
    # each one is exercised on the surface rather than only in the engine. The
    # fixtures differ in what the REAL portfolio did after the snapshot, which
    # is what the states are actually about.
    # The boundary case, and it is the COMMON restructuring rather than an
    # exotic one: topping up a position already held gives the real side
    # exactly the frozen side's price path, so before costs the two are equal
    # and the fee is the entire gap. Reporting "behind even before costs" there
    # would be false, and false in the direction that discourages a correct
    # decision.
    test "partly recovered: before costs the two match, so the fee is the whole gap", %{
      conn: conn
    } do
      costly_world("40")

      view = open_comparison(conn)
      recovery = view |> element("[data-role='cost-recovery']") |> render()

      assert recovery =~ "Not yet"
      refute recovery =~ "Behind even before costs"
    end

    test "recovered: the real side is ahead even after its costs", %{conn: conn} do
      world = costly_world("40")

      # It sold out on 2026-02-20 at 110 and sat in cash; the frozen holdings
      # then fell to 90. Being in cash beat holding, costs and all.
      {:ok, _} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          securities_account_id: world.depot.id,
          security_id: WorldFixtures.security_id_for(world.security),
          type: "sell",
          date: ~D[2026-02-21],
          quantity: "6",
          price: "110",
          gross_amount: "660",
          currency_code: "EUR"
        })

      WorldFixtures.put_quote!(world.security, ~D[2026-03-11], "90")

      recovery = open_comparison(conn) |> element("[data-role='cost-recovery']") |> render()
      assert recovery =~ "Yes"
    end

    test "not recovered: behind the frozen holdings even before costs", %{conn: conn} do
      world = costly_world("40")

      # Sold out early and sat in cash while the frozen holdings kept rising to
      # 120 — the costs are not why this is behind, and the label says so.
      {:ok, _} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          securities_account_id: world.depot.id,
          security_id: WorldFixtures.security_id_for(world.security),
          type: "sell",
          date: ~D[2026-02-21],
          quantity: "6",
          price: "110",
          gross_amount: "660",
          currency_code: "EUR"
        })

      recovery = open_comparison(conn) |> element("[data-role='cost-recovery']") |> render()
      assert recovery =~ "Behind even before costs"
    end

    test "the basis line names which costs left the return and which stayed", %{conn: conn} do
      costly_world("40")

      basis = open_comparison(conn) |> element("[data-role='comparison-basis']") |> render()

      assert basis =~ "Transaction costs"
      assert basis =~ "standalone"
      assert basis =~ "dividend withholding"
    end
  end
end
