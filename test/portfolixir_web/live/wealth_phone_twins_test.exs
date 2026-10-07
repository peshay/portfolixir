defmodule PortfolixirWeb.WealthPhoneTwinsTest do
  # Sprint 19 PR γ U4, board `mockups/ux-design-2026-10-04/06-phone-wealth`
  # (design Part 6): the Positions table's phone rows (#1065, pick J6 A), the
  # identifier that tells two securities of one name apart in the Positions
  # and the contribution tables (#1057, pick J6.2 A), and the KPI label that
  # keeps its "·" with the word before it (#1086). A LiveView test cannot
  # measure layout: these tests pin the markup and the classes the board's
  # rules act on; the CSS pins live in `test/invariants/`, the measurement in
  # the PR's Playwright record. Every name and identifier is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Clock

  # ISINs are unique instance-wide and async modules write at the same time
  # (#1018): these are this module's own.
  @juniper_a "XSU4TWIN0011"
  @juniper_b "XSU4TWIN0029"
  @quarry_a "XSU4TWIN0037"
  @quarry_b "XSU4TWIN0045"
  @nordwind "XSU4TWIN0052"
  @alike_a "XSU4TWIN0064"
  @alike_b "XSU4TWIN0072"
  @alike_shared "XSU4TWIN0080"
  @mixed_isin "XSU4TWIN0098"
  @lumen_plain "XSU4TWIN0106"
  @lumen_no_break "XSU4TWIN0114"

  setup do
    Classifications.ensure_builtins()
    :ok
  end

  defp today, do: Clock.today()
  defp days_ago(days), do: Date.add(today(), -days)

  defp security!(name, attrs \\ %{}) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{name: name, currency_code: "EUR", asset_class: "equity"}, attrs)
      )

    security
  end

  # Two depots of one portfolio, the board's twins in the first:
  #
  #   Demo Depot  Juniper Rail AG          ×2, two ISINs        → ISIN
  #   Demo Depot  Pinecrest Utilities SA   ×2, no ISIN, two WKNs → WKN
  #   Demo Depot  Orchid Bay …             ×2, no identifier     → Nr.
  #   Demo Depot  Quarry Lane Materials AG  (A)
  #   Depot 2     Quarry Lane Materials AG  (B) — same name, other depot,
  #                                              other security → ISIN
  #   both        Nordwind Industrie AG     one security in two depots
  #
  # Every booking sits inside the default 1Y window, with a quote at both
  # ends, so the contribution table lists every security.
  defp twin_world do
    world = base_world(name: "Twin World", cash_name: "Demo Cash", depot_name: "Demo Depot")

    second =
      Map.put(
        add_depot(world.portfolio, cash_name: "Cash 2", depot_name: "Depot 2"),
        :portfolio,
        world.portfolio
      )

    d0 = days_ago(40)

    deposit!(world, "100000", d0)
    deposit!(second, "100000", d0)

    juniper_a = security!("Juniper Rail AG", %{isin: @juniper_a, ticker_symbol: "JRA"})
    juniper_b = security!("Juniper Rail AG", %{isin: @juniper_b, ticker_symbol: "JRB"})
    pinecrest_a = security!("Pinecrest Utilities SA", %{wkn: "U4PCA1"})
    pinecrest_b = security!("Pinecrest Utilities SA", %{wkn: "U4PCB2"})
    orchid_a = security!("Orchid Bay Pharmaceuticals plc")
    orchid_b = security!("Orchid Bay Pharmaceuticals plc")
    quarry_a = security!("Quarry Lane Materials AG", %{isin: @quarry_a})
    quarry_b = security!("Quarry Lane Materials AG", %{isin: @quarry_b})
    nordwind = security!("Nordwind Industrie AG", %{isin: @nordwind})

    for {security, quantity} <- [
          {juniper_a, "18"},
          {juniper_b, "9"},
          {pinecrest_a, "8"},
          {pinecrest_b, "3"},
          {orchid_a, "12"},
          {orchid_b, "1"},
          {quarry_a, "2.5"},
          {nordwind, "25"}
        ],
        do: buy!(world, security, quantity: quantity, price: "10", date: d0)

    buy!(second, quarry_b, quantity: "4", price: "10", date: d0)
    buy!(second, nordwind, quantity: "10", price: "10", date: d0)

    for security <- [
          juniper_a,
          juniper_b,
          pinecrest_a,
          pinecrest_b,
          orchid_a,
          orchid_b,
          quarry_a,
          quarry_b,
          nordwind
        ],
        do: put_quotes!(security, [{d0, "10"}, {today(), "11"}])

    %{
      juniper_a: juniper_a,
      juniper_b: juniper_b,
      pinecrest_a: pinecrest_a,
      pinecrest_b: pinecrest_b,
      orchid_a: orchid_a,
      orchid_b: orchid_b,
      quarry_a: quarry_a,
      quarry_b: quarry_b,
      nordwind: nordwind
    }
  end

  # Every load the page starts, and every load a landing one starts in turn.
  defp settle(view), do: Enum.each(1..4, fn _round -> render_async(view) end)

  defp texts(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.map(&squish(Floki.text(&1, sep: " ")))
  end

  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  # User story (#1065; board 06, pick J6 A; EXPERIENCE.md → UX-DR27, which
  # names holdings among the entity lists):
  # As the operator reading my positions on a 390 px phone,
  # I want each position as a two-line row — its name over its depot, the
  # quantity on the right —
  # so that the quantity is on the screen without a sideways swipe and every
  # name stands whole.
  #
  # Acceptance criteria:
  # - Beside the table, `ul#holdings-phone-rows.phone-rows` carries one
  #   `li.phone-row` per holding row, in the table's order (depot, then name).
  # - A row is two children: `.phone-row__body` with the name
  #   (`.phone-row__name`) over the depot (`.phone-row__ids`), and
  #   `.phone-row__figures` with the quantity as "N units" — "1 unit" for one
  #   — in the table's own digits.
  # - The table and the "Columns" toggle stay in the markup: the 560 px rule
  #   swaps them, the desktop is unchanged.
  test "the Positions render as two-line phone rows beside the table", %{conn: conn} do
    twin_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(view, "#holdings-positions-wrapper #holdings-positions-table")
    assert has_element?(view, "#holdings-column-toggle")

    assert has_element?(
             view,
             ~s(ul#holdings-phone-rows.phone-rows[aria-label="Positions"])
           )

    table_rows = texts(view, "#holdings-positions-table tbody tr[data-role='holdings-position']")
    phone_rows = texts(view, "#holdings-phone-rows li.phone-row[data-role='holdings-position']")

    assert length(phone_rows) == 10
    assert length(phone_rows) == length(table_rows)

    names = texts(view, "#holdings-phone-rows .phone-row__body .phone-row__name")
    depots = texts(view, "#holdings-phone-rows .phone-row__body .phone-row__ids")
    figures = texts(view, "#holdings-phone-rows .phone-row__figures .phone-row__figure")

    # The table's order: depot, then name.
    assert depots == List.duplicate("Demo Depot", 8) ++ ["Depot 2", "Depot 2"]

    assert Enum.map(names, &String.replace(&1, ~r/ (ISIN|WKN) \S+$| no\. \d+$/, "")) == [
             "Juniper Rail AG",
             "Juniper Rail AG",
             "Nordwind Industrie AG",
             "Orchid Bay Pharmaceuticals plc",
             "Orchid Bay Pharmaceuticals plc",
             "Pinecrest Utilities SA",
             "Pinecrest Utilities SA",
             "Quarry Lane Materials AG",
             "Nordwind Industrie AG",
             "Quarry Lane Materials AG"
           ]

    assert Enum.sort(figures) ==
             Enum.sort([
               "18 units",
               "9 units",
               "25 units",
               "12 units",
               "1 unit",
               "8 units",
               "3 units",
               "2.5 units",
               "10 units",
               "4 units"
             ])
  end

  # User story (#1057 and its comment; board 06, pick J6.2 A; the review of
  # PR γ U4):
  # As the operator reading my positions,
  # I want two securities of one name to carry what tells them apart — the
  # ISIN, else the WKN, else their number — wherever in the table they sit,
  # so that "one row per depot and security" reads as two securities and not
  # as one row printed twice, even where the Depot column is switched off.
  #
  # Acceptance criteria:
  # - The collision is decided over the whole table by the displayed name:
  #   twins carry an identifier after the name, in the table cell and in the
  #   phone row, in one depot or in two; one security in two depots carries
  #   none.
  # - The identifier is `span.twin-id` after a real space, with a visually
  #   hidden "ISIN"/"WKN" and a real space before the value; without a
  #   distinct ISIN or WKN on every twin it is "no. <id>", which names
  #   itself and has no hidden label.
  test "twins anywhere in the Positions carry their identifier in the table and rows",
       %{conn: conn} do
    w = twin_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    for {surface, row} <- [
          {"#holdings-positions-table", "tr"},
          {"#holdings-phone-rows", "li"}
        ] do
      at = fn security -> "#{surface} #{row}[data-security-id='#{security.id}'] .twin-id" end

      assert texts(view, at.(w.juniper_a)) == ["ISIN #{@juniper_a}"]
      assert texts(view, at.(w.juniper_b)) == ["ISIN #{@juniper_b}"]
      assert texts(view, at.(w.juniper_a) <> " .visually-hidden") == ["ISIN"]

      assert texts(view, at.(w.pinecrest_a)) == ["WKN U4PCA1"]
      assert texts(view, at.(w.pinecrest_b)) == ["WKN U4PCB2"]

      assert texts(view, at.(w.orchid_a)) == ["no. #{w.orchid_a.id}"]
      assert texts(view, at.(w.orchid_b)) == ["no. #{w.orchid_b.id}"]
      # A number names itself: no hidden label at all.
      assert texts(view, at.(w.orchid_a) <> " .visually-hidden") == []

      # One name in two depots, two securities: a collision.
      assert texts(view, at.(w.quarry_a)) == ["ISIN #{@quarry_a}"]
      assert texts(view, at.(w.quarry_b)) == ["ISIN #{@quarry_b}"]

      # One security in two depots: no collision, on either of its rows.
      assert texts(view, at.(w.nordwind)) == []
    end

    # The identifier follows the name inside the name's own cell, after a
    # real space; the hidden label's separator is a real space too.
    html = render(view)

    twin =
      ~s(<span class="twin-id"><span class="visually-hidden">ISIN</span> #{@juniper_a}</span>)

    assert html =~ ~s(Juniper Rail AG #{twin}<)
    assert html =~ ~s(<span class="phone-row__name">Juniper Rail AG #{twin}</span>)
  end

  # User story (#1057; the review of PR γ U4):
  # As the operator whose two depots carry one name,
  # I want two same-named securities told apart even where the depot cells
  # read the same,
  # so that a depot name is never what I have to rely on to tell two
  # securities apart.
  #
  # Acceptance criteria:
  # - Two depots whose names read the same — "Demo Depot" and "Demo  Depot":
  #   the account name guard compares the stored names, and the browser
  #   collapses the double space — each with a different security named
  #   "Juniper Rail AG": both rows carry their identifier, in the table and
  #   in the phone rows.
  # - One security held in both depots carries none.
  test "two depots of one name do not hide two securities of one name", %{conn: conn} do
    world = base_world(name: "Alike World", cash_name: "Cash A", depot_name: "Demo Depot")

    second =
      Map.put(
        add_depot(world.portfolio, cash_name: "Cash B", depot_name: "Demo  Depot"),
        :portfolio,
        world.portfolio
      )

    d0 = days_ago(20)
    deposit!(world, "10000", d0)
    deposit!(second, "10000", d0)

    first_twin = security!("Juniper Rail AG", %{isin: @alike_a})
    second_twin = security!("Juniper Rail AG", %{isin: @alike_b})
    shared = security!("Nordwind Industrie AG", %{isin: @alike_shared})

    buy!(world, first_twin, quantity: "5", price: "10", date: d0)
    buy!(second, second_twin, quantity: "6", price: "10", date: d0)
    buy!(world, shared, quantity: "7", price: "10", date: d0)
    buy!(second, shared, quantity: "8", price: "10", date: d0)

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    for {surface, row} <- [
          {"#holdings-positions-table", "tr"},
          {"#holdings-phone-rows", "li"}
        ] do
      at = fn security -> "#{surface} #{row}[data-security-id='#{security.id}'] .twin-id" end

      assert texts(view, at.(first_twin)) == ["ISIN #{@alike_a}"]
      assert texts(view, at.(second_twin)) == ["ISIN #{@alike_b}"]
      assert texts(view, at.(shared)) == []
    end

    assert texts(view, "#holdings-phone-rows .phone-row__ids") ==
             List.duplicate("Demo Depot", 4)
  end

  # User story (#1057; the PR γ closing act, edge-case hunter #3):
  # As the operator holding two securities named "Lumen Werke AG", one of
  # them pasted with a no-break space,
  # I want both rows to carry their identifier,
  # so that two rows that print identically still say which security each
  # one is.
  #
  # Acceptance criteria:
  # - A name with U+00A0 between its words and the same name with a plain
  #   space are twins: both carry their ISIN, in the Positions table and in
  #   the phone rows.
  test "a name with a no-break space is the twin of the plain name", %{conn: conn} do
    world = base_world(name: "Lumen World", cash_name: "Lumen Cash", depot_name: "Lumen Depot")
    d0 = days_ago(10)
    deposit!(world, "10000", d0)

    plain = security!("Lumen Werke AG", %{isin: @lumen_plain})
    no_break = security!("Lumen Werke AG", %{isin: @lumen_no_break})

    buy!(world, plain, quantity: "1", price: "10", date: d0)
    buy!(world, no_break, quantity: "2", price: "11", date: d0)

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    for {surface, row} <- [
          {"#holdings-positions-table", "tr"},
          {"#holdings-phone-rows", "li"}
        ] do
      at = fn security -> "#{surface} #{row}[data-security-id='#{security.id}'] .twin-id" end

      assert texts(view, at.(plain)) == ["ISIN #{@lumen_plain}"]
      assert texts(view, at.(no_break)) == ["ISIN #{@lumen_no_break}"]
    end
  end

  # User story (#1065, #1057; the review of PR γ U4):
  # As the operator reading my positions on a phone in German,
  # I want the quantity's unit word and a twin's number in my language,
  # so that the row reads "3,25 Stück" and "Nr. 42", not a mix of two.
  #
  # Acceptance criteria:
  # - One unit reads "1 Stück", a fraction "3,25 Stück" with the German
  #   decimal comma, every stored digit.
  # - Twins without a distinct ISIN or WKN carry "Nr. <id>".
  # - One twin with only an ISIN and the other with only a WKN: neither
  #   identifier is on both, so both carry "Nr. <id>".
  test "the phone rows read in German, with Stück and Nr.", %{conn: conn} do
    world = base_world(name: "Deutsch World", cash_name: "Giro", depot_name: "Depot")
    d0 = days_ago(15)
    deposit!(world, "10000", d0)

    one = security!("Linden Bahn AG")
    fraction = security!("Linden Bahn AG")
    isin_only = security!("Harbour Mills plc", %{isin: @mixed_isin})
    wkn_only = security!("Harbour Mills plc", %{wkn: "U4MIX1"})

    buy!(world, one, quantity: "1", price: "10", date: d0)
    buy!(world, fraction, quantity: "3.25", price: "10", date: d0)
    buy!(world, isin_only, quantity: "2", price: "10", date: d0)
    buy!(world, wkn_only, quantity: "4", price: "10", date: d0)

    {:ok, view, _html} = live(conn, "/portfolio?locale=de")
    render_async(view)

    row = fn security -> "#holdings-phone-rows li[data-security-id='#{security.id}']" end

    assert texts(view, row.(one) <> " .phone-row__figure") == ["1 Stück"]
    assert texts(view, row.(fraction) <> " .phone-row__figure") == ["3,25 Stück"]
    assert texts(view, row.(isin_only) <> " .phone-row__figure") == ["2 Stück"]

    assert texts(view, row.(one) <> " .twin-id") == ["Nr. #{one.id}"]
    assert texts(view, row.(fraction) <> " .twin-id") == ["Nr. #{fraction.id}"]
    assert texts(view, row.(isin_only) <> " .twin-id") == ["Nr. #{isin_only.id}"]
    assert texts(view, row.(wkn_only) <> " .twin-id") == ["Nr. #{wkn_only.id}"]

    assert texts(
             view,
             "#holdings-positions-table tr[data-security-id='#{wkn_only.id}'] .twin-id"
           ) == ["Nr. #{wkn_only.id}"]
  end

  # User story (#1065; the review of PR γ U4):
  # As the operator of a portfolio with no holdings yet,
  # I want the Positions section to keep its one empty-state sentence,
  # so that a phone shows no empty list and no column control with nothing
  # behind it.
  #
  # Acceptance criteria:
  # - No `#holdings-phone-rows`, no table and no "Columns" toggle; the
  #   empty state is there.
  test "an empty portfolio shows the empty state and no phone rows", %{conn: conn} do
    world = base_world(name: "Empty World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", days_ago(5))

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(view, "#portfolio-positions #no-positions")
    refute has_element?(view, "#holdings-phone-rows")
    refute has_element?(view, "#holdings-positions-table")
    refute has_element?(view, "#holdings-column-toggle")
  end

  # User story (#1057; board 06, pick J6.2 A):
  # As the operator reading which position made my period's result,
  # I want two positions of one name told apart in the contribution table,
  # so that two identical rows never hide which security earned what.
  #
  # Acceptance criteria:
  # - The collision key is the name, over the whole payload: one row per
  #   security, so one name in two depots collides here.
  # - The identifier is the ISIN where every twin has a distinct one, else
  #   "no. <id>": the contribution payload carries no WKN (design Part 6,
  #   found while drawing 2).
  # - Both the table and the phone rows carry it; a unique name is bare.
  test "twins in the contribution table carry their identifier at both widths",
       %{conn: conn} do
    w = twin_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)

    for {surface, row} <- [
          {"#contribution-table", "tr[data-role='contribution-row']"},
          {"#contribution-phone-rows", "li[data-role='contribution-row']"}
        ] do
      at = fn security -> "#{surface} #{row}[data-security-id='#{security.id}'] .twin-id" end

      assert texts(view, at.(w.juniper_a)) == ["ISIN #{@juniper_a}"]
      assert texts(view, at.(w.juniper_b)) == ["ISIN #{@juniper_b}"]
      assert texts(view, at.(w.quarry_a)) == ["ISIN #{@quarry_a}"]
      assert texts(view, at.(w.quarry_b)) == ["ISIN #{@quarry_b}"]

      # No WKN in the payload: the chain falls through to the number.
      assert texts(view, at.(w.pinecrest_a)) == ["no. #{w.pinecrest_a.id}"]
      assert texts(view, at.(w.orchid_b)) == ["no. #{w.orchid_b.id}"]

      assert texts(view, at.(w.nordwind)) == []
    end
  end

  # User story (#1057; design Part 6: "checked over the whole payload"):
  # As the operator reading a contribution table that shows its ten largest,
  # I want a twin whose sibling is among the hidden rows to keep its
  # identifier,
  # so that the row does not read as the only security of that name.
  #
  # Acceptance criteria:
  # - With eleven positions the table shows its ten largest; a twin among
  #   them whose sibling is the hidden eleventh still carries its
  #   identifier, because the collision is decided before the cut.
  test "a shown twin keeps its identifier when its sibling is hidden", %{conn: conn} do
    world = base_world(name: "Eleven World", cash_name: "Giro", depot_name: "Depot")
    d0 = days_ago(30)
    deposit!(world, "5000", d0)

    for k <- 1..9 do
      security = security!("Filler #{k}")
      buy!(world, security, quantity: "1", price: "100", date: d0)
      put_quotes!(security, [{d0, "100"}, {today(), Integer.to_string(120 + k)}])
    end

    shown = security!("Juniper Rail AG")
    hidden = security!("Juniper Rail AG")

    buy!(world, shown, quantity: "1", price: "100", date: d0)
    put_quotes!(shown, [{d0, "100"}, {today(), "150"}])
    buy!(world, hidden, quantity: "1", price: "100", date: d0)
    put_quotes!(hidden, [{d0, "100"}, {today(), "101"}])

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)

    refute has_element?(view, "#contribution-table tr[data-security-id='#{hidden.id}']")

    assert texts(
             view,
             "#contribution-table tr[data-security-id='#{shown.id}'] .twin-id"
           ) == ["no. #{shown.id}"]
  end

  # User story (#1086; board 06, "Nachher · Kennzahlen"):
  # As the operator reading the KPI band on a 390 px phone,
  # I want the "·" of "Opening value · net flows (1Y)" to end a line rather
  # than open one,
  # so that the separator never stands alone at the start of the label's
  # second line.
  #
  # Acceptance criteria:
  # - A no-break space binds "·" to the word before it; the space after it
  #   stays breakable.
  test "the opening-value label binds its separator to the word before it", %{conn: conn} do
    world = base_world(name: "Label World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", days_ago(10))

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    [label] =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#kpi-invested .stat__head > span")
      |> Enum.map(&Floki.text/1)

    assert label =~ "Opening value\u{00A0}· net flows"
  end

  # User story (#1086, rule ④; the review of PR γ U4):
  # As the operator reading Wealth's KPI band on a phone,
  # I want the compact cards' smaller value to be a rule of this band,
  # so that Risk's metric cards, which share the card class, keep their
  # value apart from the 16 px "not computable" sentence.
  #
  # Acceptance criteria:
  # - Wealth's KPI band is `section#portfolio-kpis.kpi-band`, and its four
  #   compact cards sit inside it: the 560 px rule is scoped to that id
  #   (the CSS pin is in `css_layout_sweep_test.exs`).
  test "the KPI band carries the id its phone rule is scoped to", %{conn: conn} do
    world = base_world(name: "Band World", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "1000", days_ago(10))

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    for card <- ~w(kpi-securities kpi-cash kpi-invested kpi-multiple) do
      assert has_element?(view, "section#portfolio-kpis.kpi-band article##{card}.stat--compact")
    end
  end
end
