defmodule PortfolixirWeb.ZeroFigureUnsignedTest do
  # #1149 (Sprint 21 γ4; board ux-design-2026-10-09/04-wealth-income ③ and
  # its found while drawing 2 to 5): a figure that reads zero carries neither
  # a sign nor a gain/loss colour, on every surface that prints one, not only
  # on the Trades surfaces. Invented names and figures only.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp classes(nodes), do: nodes |> Floki.attribute("class") |> Enum.join(" ")

  defp document(view), do: view |> render() |> Floki.parse_document!()

  # 1,000.00 deposited and spent on 10 shares at 100, quoted at 100.0004
  # today: the period gained 0.004 EUR, a TTWROR of +0.0004 %. Both read
  # zero at the precision they are printed at.
  defp fraction_of_a_cent_world do
    Classifications.ensure_builtins()
    today = Clock.today()
    start = Date.add(today, -30)
    world = WorldFixtures.base_world(name: "Flat", cash_name: "Giro", depot_name: "Depot")
    nordwind = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")

    WorldFixtures.deposit!(world, "1000", start)
    WorldFixtures.buy!(world, nordwind, quantity: "10", price: "100", date: start)
    WorldFixtures.put_quotes!(nordwind, [{start, "100"}, {today, "100.0004"}])
    %{world: world, nordwind: nordwind}
  end

  # User story (#1149, Sprint 21 γ4; found while drawing 1 and 2):
  # As the operator reading Wealth's period badge and the contribution sum,
  # I want a gain of a fraction of a cent to read "0.00" in body ink,
  # so that a flat period does not read as a gain.
  #
  # Acceptance criteria:
  # - The badge's TTWROR reads "0.0%" and its money "0.00 EUR", neither with
  #   a "+", both `is-flat`, never `is-positive`.
  # - The contribution table's sum reads "0.00 EUR" without a sign or a
  #   gain colour, and equals the badge's money; the position's row reads
  #   "0.00" uncoloured in the table and in its phone row, with no drift bar
  #   beside it.
  test "Wealth's badge and the contribution sum read a fraction of a cent as an unsigned zero",
       %{conn: conn} do
    fraction_of_a_cent_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)
    doc = document(view)

    [badge] = Floki.find(doc, ~s([data-role="period-badge"]))
    assert text(Floki.find(badge, "strong")) == "0.0%"
    refute classes([badge]) =~ "is-positive"
    assert classes([badge]) =~ "is-flat"

    money = Floki.find(badge, ~s([data-role="period-badge-money"]))
    assert text(money) == "0.00 EUR"
    assert classes(money) == "is-flat"

    sum = Floki.find(doc, ~s([data-role="contribution-sum-figure"]))
    assert text(sum) == "0.00 EUR"
    assert Floki.find(sum, ".is-positive") == []

    # The position's own row, at both widths.
    figure = Floki.find(doc, "#contribution-table tr[data-role='contribution-row'] td.num span")
    assert text(Enum.take(figure, 1)) == "0.00"

    assert Floki.find(doc, "#contribution-table tr[data-role='contribution-row'] .is-positive") ==
             []

    # Review SF-1: the bar beside a figure that reads zero is not drawn — no
    # `is-over` fill beside "0.00".
    assert Floki.find(
             doc,
             "#contribution-table tr[data-role='contribution-row'] .drift-bar__fill"
           ) ==
             []

    phone =
      Floki.find(
        doc,
        "#contribution-phone-rows li[data-role='contribution-row'] .phone-row__figure"
      )

    assert text(phone) == "0.00"
    refute classes(phone) =~ "is-positive"
  end

  # User story (#1149, Sprint 21 γ4; found while drawing 3, also board 01):
  # As the operator reading the Overview's key-figure strip,
  # I want a one-year TTWROR of +0.0004 % to read "0.0%" in body ink,
  # so that the strip agrees with its own digits.
  #
  # Acceptance criteria:
  # - The strip's TTWROR reads "0.0%", no "+", `is-flat`.
  test "the Overview's strip reads a TTWROR that rounds to zero unsigned", %{conn: conn} do
    fraction_of_a_cent_world()

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    figure =
      view |> document() |> Floki.find(~s(#dashboard-kpi-strip [data-role="kpi-ttwror"] strong))

    assert text(figure) == "0.0%"
    assert classes(figure) == "is-flat"
  end

  # User story (#1149, Sprint 21 γ4; board 04 ③):
  # As the operator reading a security's Overview tab,
  # I want a day change of +0.004 % and an unrealised result of -0.004 EUR
  # to read "0.0%" (the one-decimal form of issue 1201) and "0.00" in body ink,
  # so that a figure that reads zero is not coloured as a gain or a loss.
  #
  # Acceptance criteria:
  # - The day change and the unrealised figure carry neither `is-positive`
  #   nor `is-negative`.
  test "the security's Overview colours a day change and a result by the figure as shown",
       %{conn: conn} do
    world = WorldFixtures.base_world(name: "Overview", cash_name: "Giro", depot_name: "Depot")
    nordwind = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    today = Clock.today()

    WorldFixtures.deposit!(world, "1000", Date.add(today, -10))

    WorldFixtures.buy!(world, nordwind,
      quantity: "1",
      price: "100.008",
      date: Date.add(today, -10)
    )

    WorldFixtures.put_quotes!(nordwind, [{Date.add(today, -1), "100"}, {today, "100.004"}])

    {:ok, view, _html} = live(conn, "/securities/#{nordwind.id}")
    doc = document(view)

    day = Floki.find(doc, ~s([data-role="overview-day-change"] dd))
    assert text(day) == "0.0%"
    refute classes(day) =~ "is-positive"

    unrealised = Floki.find(doc, ~s([data-role="overview-unrealised"] dd))
    assert text(unrealised) =~ ~r/^0\.00 /
    refute classes(unrealised) =~ "is-negative"
  end

  # User story (#1149, Sprint 21 γ4; board 04 ③ and found while drawing 4
  # and 5):
  # As the operator reading the Cash-flow matrices,
  # I want a month whose sum reads zero to print the matrix's quiet dash,
  # never "-0.00" and never "0.00",
  # so that the Trades, Flows and Costs matrices follow the rule the Income
  # matrix keeps.
  #
  # Acceptance criteria:
  # - The Realized matrix's month of a sale that netted -0.004 EUR reads
  #   "–", its year total "0.00", and no cell reads "-0.00".
  # - The Flows and Costs matrices print "–" in every month that sums to
  #   zero; their totals stay figures.
  test "the Cash-flow matrices print a month that reads zero as the quiet dash", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Matrix", currency: "EUR")
    nordwind = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")

    WorldFixtures.deposit!(world, "1000.00", ~D[2026-01-10])
    WorldFixtures.buy!(world, nordwind, quantity: "1", price: "100.004", date: ~D[2026-01-12])
    WorldFixtures.sell!(world, nordwind, quantity: "1", price: "100", date: ~D[2026-02-16])

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        type: "fee",
        date: ~D[2026-03-05],
        gross_amount: "5.00",
        currency_code: "EUR"
      })

    {:ok, _view, html} = live(conn, "/cashflow?tab=realized")
    [row] = html |> Floki.parse_document!() |> Floki.find("#realized-annual tbody tr")
    cells = row |> Floki.find("td.num") |> Enum.map(&text([&1]))
    assert Enum.at(cells, 1) == "–"
    assert List.last(cells) == "0.00"
    refute Enum.member?(cells, "-0.00")
    assert Enum.count(cells, &(&1 == "–")) == 12

    {:ok, _view, html} = live(conn, "/cashflow?tab=flows")
    [deposits | _] = html |> Floki.parse_document!() |> Floki.find("#flows-annual tbody tr")
    deposit_cells = deposits |> Floki.find("td.num") |> Enum.map(&text([&1]))
    assert Enum.take(deposit_cells, 2) == ["1,000.00", "–"]
    assert Enum.count(deposit_cells, &(&1 == "–")) == 11
    assert List.last(deposit_cells) == "1,000.00"

    {:ok, _view, html} = live(conn, "/cashflow?tab=costs")
    [fees, taxes | _] = html |> Floki.parse_document!() |> Floki.find("#costs-annual tbody tr")
    fee_cells = fees |> Floki.find("td.num") |> Enum.map(&text([&1]))
    assert Enum.take(fee_cells, 3) == ["–", "–", "5.00"]
    assert List.last(fee_cells) == "5.00"
    tax_cells = taxes |> Floki.find("td.num") |> Enum.map(&text([&1]))
    assert Enum.count(tax_cells, &(&1 == "–")) == 12
    assert List.last(tax_cells) == "0.00"
  end

  # The review of the γ4 range (SF-1): the rule holds wherever a sign class
  # is decided, beyond the surfaces board 04 drew. Each pin below is a
  # figure of a fraction of a cent, or of a fraction of a basis point, that
  # reads zero where it is printed.
  describe "every other sign class decides on the figure as displayed (#1149, review SF-1)" do
    # User story (#1149, review SF-1):
    # As the operator comparing a snapshot with what really happened,
    # I want a frozen return of +0.004 % to read "0.0%" in body ink,
    # so that the comparison does not call a flat hold a gain.
    #
    # Acceptance criteria:
    # - The "Frozen (hold)" and "Real" figures read "0.0%", no "+", and
    #   carry no gain colour.
    test "the snapshot comparison's returns", %{conn: conn} do
      world = WorldFixtures.base_world(name: "Snap", currency: "EUR")
      stock = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")

      WorldFixtures.deposit!(world, "10000", ~D[2026-01-02], [])
      WorldFixtures.buy!(world, stock, quantity: "5", price: "100", date: ~D[2026-01-05])
      WorldFixtures.put_quote!(stock, ~D[2026-02-14], "100")
      WorldFixtures.put_quote!(stock, ~D[2026-03-10], "100.004")

      {:ok, _} =
        Portfolixir.Portfolios.Snapshots.create_snapshot(Portfolixir.Actor.owner_ui(), %{
          name: "Flat hold",
          as_of: ~D[2026-02-15]
        })

      {:ok, view, _html} = live(conn, "/snapshots")

      doc =
        view
        |> element("[data-role=snapshot-row] a[data-role=snapshot-select]")
        |> render_click()
        |> Floki.parse_document!()

      for role <- ~w(kpi-frozen kpi-real) do
        figure = Floki.find(doc, ~s([data-role="#{role}"] strong))
        assert text(figure) == "0.0%", role
        refute classes(figure) =~ "is-positive", role
      end
    end

    # User story (#1149, review SF-1):
    # As the operator previewing a sale,
    # I want a lot that gains 0.004 EUR to read "0.00" in body ink,
    # so that the preview does not colour a break-even sale as a gain.
    #
    # Acceptance criteria:
    # - The preview's total reads "0.00" and carries no `is-positive`.
    test "the sell preview's gain", %{conn: conn} do
      world = WorldFixtures.base_world(name: "Drawer", depot_name: "Main", cash_name: "Cash")
      stock = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
      WorldFixtures.deposit!(world, "5000", ~D[2026-01-02])
      WorldFixtures.buy!(world, stock, quantity: "1", price: "100", date: ~D[2026-01-10])

      {:ok, view, _html} = live(conn, "/transactions")
      view |> element("#open-booking") |> render_click()

      view
      |> element("#transaction-form")
      |> render_change(%{
        "transaction" => %{
          "type" => "sell",
          "date" => "2026-06-01",
          "securities_account_id" => to_string(world.depot.id),
          "security_id" => to_string(stock.id),
          "quantity" => "1",
          "price" => "100.004",
          "fees" => "0",
          "taxes" => "0",
          "notes" => ""
        }
      })

      total = view |> document() |> Floki.find("#booking-drawer [data-role='preview-total']")
      assert text(total) == "0.00 EUR"
      refute classes(total) =~ "is-positive"
    end

    # User story (#1149, review SF-1):
    # As the operator scanning the securities list,
    # I want a day change of +0.004 % to read "0.00 %" uncoloured,
    # so that the list agrees with its own digits.
    #
    # Acceptance criteria:
    # - The day-change cell's figure reads "0.00 %" and carries
    #   `decimal-neutral`, never `decimal-positive`.
    test "the securities list's day change", %{conn: conn} do
      stock = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
      today = Clock.today()
      WorldFixtures.put_quotes!(stock, [{Date.add(today, -1), "100"}, {today, "100.004"}])

      {:ok, view, _html} = live(conn, "/securities")

      figures =
        view
        |> document()
        |> Floki.find("table span")
        |> Enum.filter(&(text([&1]) == "0.00 %"))

      assert [_ | _] = figures
      assert Enum.map(figures, &classes([&1])) |> Enum.uniq() == ["decimal-neutral"]
    end

    # User story (#1149, review SF-1):
    # As the operator reading the Risk tab,
    # I want a maximum drawdown of -0.004 % to read "0.0" in body ink,
    # so that a drawdown that reads zero is not coloured as a loss.
    #
    # Acceptance criteria:
    # - The max-drawdown figure reads "0.0" and carries no `is-negative`.
    test "the Risk tab's maximum drawdown", %{conn: conn} do
      world = WorldFixtures.base_world()
      stock = WorldFixtures.create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
      day = fn offset -> Date.add(Date.utc_today(), offset) end

      WorldFixtures.deposit!(world, "10000", day.(-400))
      WorldFixtures.buy!(world, stock, quantity: "100", price: "100", date: day.(-400))

      WorldFixtures.put_quotes!(
        stock,
        for(offset <- -400..0, do: {day.(offset), if(offset == -100, do: "99.996", else: "100")})
      )

      {:ok, view, _html} = live(conn, "/risk")

      [figure] =
        view
        |> document()
        |> Floki.find(~s([data-role="risk-metric-max-drawdown"] span))
        |> Enum.filter(&(text([&1]) == "0.0"))

      refute classes([figure]) =~ "is-negative"
    end

    # User story (#1149, review SF-1):
    # As the operator reading the allocation's drift,
    # I want a category 0.004 EUR under its target to read "0.00" in body
    # ink,
    # so that a drift that reads zero is not coloured as an underweight.
    #
    # Acceptance criteria:
    # - The category's drift cell reads "0.00 EUR" and carries no
    #   `is-negative`.
    test "the allocation's drift", %{conn: conn} do
      owner = Portfolixir.Actor.owner_ui()
      world = WorldFixtures.base_world(name: "Drift", cash_name: "Giro", depot_name: "Depot")
      {:ok, tree} = Classifications.create_classification(owner, %{name: "Strategie"})

      {:ok, growth} =
        Classifications.create_category(owner, %{classification_id: tree.id, name: "Wachstum"})

      {:ok, income} =
        Classifications.create_category(owner, %{classification_id: tree.id, name: "Ertrag"})

      helios = WorldFixtures.create_security!(name: "Helios Solar Systems SE", ticker: "HSS")
      harbor = WorldFixtures.create_security!(name: "Harbor Light Utilities SE", ticker: "HLU")

      for {security, category} <- [{helios, growth}, {harbor, income}] do
        {:ok, _} = Classifications.assign_security(owner, security.id, tree.id, category.id)
      end

      WorldFixtures.deposit!(world, "200.008", ~D[2026-01-02])
      WorldFixtures.buy!(world, helios, quantity: "1", price: "100", date: ~D[2026-01-05])
      WorldFixtures.buy!(world, harbor, quantity: "1", price: "100.008", date: ~D[2026-01-05])

      {:ok, _} =
        Portfolixir.Portfolios.Targets.set_targets(owner, world.portfolio.id, tree.id, [
          %{"category_id" => growth.id, "target_weight" => "0.5"},
          %{"category_id" => income.id, "target_weight" => "0.5"}
        ])

      {:ok, view, _html} = live(conn, "/portfolio?tab=allocation&classification=#{tree.id}")
      render_async(view)

      [row] =
        view
        |> document()
        |> Floki.find("table.drift-table tbody tr")
        |> Enum.filter(&(&1 |> Floki.find("td:first-child") |> text() =~ "Wachstum"))

      [drift] = Floki.find(row, "td.col-subject")
      assert text([drift]) == "0.00 EUR"
      refute classes([drift]) =~ "is-negative"
    end
  end
end
