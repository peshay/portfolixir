defmodule PortfolixirWeb.SaleHindsightLiveTest do
  # Sprint 26 V3 (I18 modes 1 and 2, FR-50; board
  # ux-design-2026-11-06-sprint26-i18, pick C): the human view of what a
  # sale missed. A section "After the sale" of its own under the trades list
  # of Cash flow → Trades and on a security's Trades tab, one row per sale
  # booking, a comparison chooser (none, a fixed rate, a flagged benchmark
  # security) as query state, the four spans with every figure and no
  # click, `pending` and `incomplete` with their reasons, the computation
  # basis behind the ⓘ, and no verdict word anywhere. The figures are
  # `Portfolixir.Portfolios.Performance.SaleHindsight`'s, the function
  # `GET /api/v1/sales/hindsight` answers with, so a figure on the screen is
  # compared with the API's answer for the same request. Every name and
  # figure here is synthetic. async: false: the section reads every sale.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, put_quotes!: 2, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias PortfolixirWeb.Format

  defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> squish()
  end

  defp api_conn(conn) do
    conn
    |> recycle()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp api_span(conn, params, sale_id, label) do
    %{"data" => data} =
      conn |> api_conn() |> get("/api/v1/sales/hindsight", params) |> json_response(200)

    row = Enum.find(data["rows"], &(&1["sale_id"] == sale_id))
    Enum.find(row["spans"], &(&1["span"] == label))
  end

  defp percent(string), do: string |> Decimal.new() |> Format.signed_percent() |> Kernel.<>("%")

  # --- Sprint 26 R3 begin ---
  # Mode 3 (ADR-0057): the API's reinvestment block of one sale, and one of
  # its spans, for the same sales the screen reads.
  defp api_block(conn, sale_id) do
    %{"data" => data} =
      conn
      |> api_conn()
      |> get("/api/v1/sales/hindsight", %{"include" => "reinvestment"})
      |> json_response(200)

    Enum.find(data["rows"], &(&1["sale_id"] == sale_id))["reinvestment"]
  end

  defp api_switch_span(block, label), do: Enum.find(block["spans"], &(&1["span"] == label))

  # The text of every element the selector matches, in document order.
  defp texts(view, selector) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> squish()))
  end

  defp money(string), do: string |> Decimal.new() |> Format.decimal(2)
  defp signed_money(string), do: string |> Decimal.new() |> Format.signed_decimal(2)

  # A sale and the buys its proceeds went into (ADR-0057 §1), all from the
  # one cash account: the 2025-01-15 sale (10 x 101.50, fees 1.50, taxes
  # 10.00, so 1,003.50 of proceeds) pays a buy 5 days later in full (8 x
  # 100 + 2.00 fees = 802.00) and 201.50 of a 300.00 buy 21 days later. The
  # first bought fund has a close on every span's end; the second none after
  # April 2025, so the 12m and latest spans miss a close on the switched
  # side. A recent sale's proceeds pay a buy on its own day, so its spans
  # run. A third sale has no buy within 30 days.
  defp switch_world do
    world = base_world(name: "Switch Screen")

    sold = create_security!(name: "Synthetic Sold Fund", ticker: "SSF")

    put_quotes!(sold, [
      {~D[2025-01-15], "100"},
      {~D[2025-02-14], "110"},
      {~D[2025-04-15], "120"},
      {~D[2026-01-15], "90"}
    ])

    sale =
      sell!(world, sold,
        quantity: "10",
        price: "101.50",
        fees: "1.50",
        taxes: "10.00",
        date: ~D[2025-01-15]
      )

    next = create_security!(name: "Synthetic Next Fund", ticker: "SNF")

    put_quotes!(next, [
      {~D[2025-01-20], "100"},
      {~D[2025-02-14], "105"},
      {~D[2025-04-15], "110"},
      {~D[2026-01-15], "120"}
    ])

    second = create_security!(name: "Synthetic Second Fund", ticker: "SSE")

    put_quotes!(second, [
      {~D[2025-02-05], "100"},
      {~D[2025-02-14], "102"},
      {~D[2025-04-15], "104"}
    ])

    buy!(world, next, quantity: "8", price: "100", fees: "2.00", date: ~D[2025-01-20])
    buy!(world, second, quantity: "3", price: "100", date: ~D[2025-02-05])

    recent_day = Date.add(Clock.today(), -3)
    recent_security = create_security!(name: "Synthetic Recent Fund", ticker: "SRF")
    put_quotes!(recent_security, [{recent_day, "40"}])
    recent = sell!(world, recent_security, quantity: "1", price: "40", date: recent_day)
    buy!(world, next, quantity: "1", price: "30", date: recent_day)

    alone = create_security!(name: "Synthetic Alone Fund", ticker: "SAF")
    put_quotes!(alone, [{~D[2025-06-02], "12"}])
    lone = sell!(world, alone, quantity: "2", price: "12", date: ~D[2025-06-02])

    %{sold: sold, sale: sale, recent: recent, recent_day: recent_day, lone: lone}
  end

  # --- Sprint 26 R3 end ---

  # A sale on 2025-01-15 whose 1m, 3m and 12m spans have passed, a flagged
  # benchmark with closes on the same days, a recent sale whose spans have
  # not ended, and a sale with no close at all.
  defp world do
    world = base_world(name: "Hindsight Screen")

    sold = create_security!(name: "Synthetic Sold Fund", ticker: "SSF", currency: "EUR")

    put_quotes!(sold, [
      {~D[2025-01-15], "100"},
      {~D[2025-02-14], "110"},
      {~D[2025-04-15], "120"},
      {~D[2026-01-15], "90"}
    ])

    # #1416 (B2): bought before it is sold out, so neither fund is held
    # today and the benchmark select's „In holdings“ group stays the test's.
    buy!(world, sold, quantity: "10", price: "90", date: ~D[2024-12-02])
    sale = sell!(world, sold, quantity: "10", price: "101.50", date: ~D[2025-01-15])

    bench = create_security!(name: "Synthetic Bench Index", ticker: "SBI", currency: "EUR")
    {:ok, bench} = Catalog.update_security(Actor.owner_ui(), bench, %{is_benchmark: true})

    put_quotes!(bench, [
      {~D[2025-01-15], "200"},
      {~D[2025-02-14], "204"},
      {~D[2025-04-15], "210"},
      {~D[2026-01-15], "220"}
    ])

    recent_day = Date.add(Clock.today(), -3)
    recent_security = create_security!(name: "Synthetic Recent Fund", ticker: "SRF")
    put_quotes!(recent_security, [{recent_day, "40"}])
    buy!(world, recent_security, quantity: "1", price: "38", date: Date.add(recent_day, -5))
    recent = sell!(world, recent_security, quantity: "1", price: "40", date: recent_day)

    bare = create_security!(name: "Synthetic Unpriced Fund", ticker: "SUF")
    unpriced = sell!(world, bare, quantity: "2", price: "12", date: ~D[2025-06-02])

    %{
      world: world,
      sold: sold,
      sale: sale,
      bench: bench,
      recent: recent,
      recent_day: recent_day,
      unpriced: unpriced
    }
  end

  # User story (V3, I18 modes 1 and 2, FR-50; board 03 pick C):
  # As the operator reading my closed trades,
  # I want a section "After the sale" under the trades list with one row
  # per sale booking and its four spans, each with every figure,
  # so that I see what each sale missed without a click and without asking
  # the agent.
  #
  # Acceptance criteria:
  # - Cash flow → Trades carries the section after the trades list, one
  #   row per sale booking (a sale with no matched buy too), newest first.
  # - With the flagged benchmark chosen, a span reads the difference over
  #   "security vs. benchmark", and the difference is the API's for the
  #   same request (benchmark=security:<id>), to the displayed digit.
  # - A span that has not ended reads "running" over "until <date>"; a
  #   span the read cannot measure reads its reason ("no start close") with
  #   the long reason as the cell's title.
  # - The ⓘ carries the computation basis; the legend names what the lead
  #   figure is and that distributions are not included.
  test "Cash flow → Trades shows one row per sale with its four spans, as the API answers",
       %{conn: conn} do
    %{sale: sale, bench: bench, recent: recent, recent_day: recent_day, unpriced: unpriced} =
      world()

    {:ok, view, _html} =
      live(conn, "/cashflow?tab=realized&hindsight=security&hindsight_benchmark=#{bench.id}")

    assert has_element?(view, "section#sale-hindsight h2", "After the sale")

    rows =
      view
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query("#sale-hindsight tr[data-role='hindsight-row']")
      |> Enum.map(&(&1 |> LazyHTML.attribute("data-sale") |> hd()))

    assert rows == Enum.map([recent, unpriced, sale], &Integer.to_string(&1.id))

    api = api_span(conn, %{"benchmark" => "security:#{bench.id}"}, sale.id, "1m")
    cell = "#sale-hindsight tr[data-sale='#{sale.id}'] td[data-span='1m']"

    assert text(view, "#{cell} .hs-lead") == percent(api["difference"])
    assert text(view, "#{cell} .hs-lead") == "+8.0%"

    assert text(view, "#{cell} .stat__sub") ==
             "#{percent(api["security"]["return"])} vs. #{percent(api["benchmark"]["return"])}"

    pending = "#sale-hindsight tr[data-sale='#{recent.id}'] td[data-span='1m']"
    until = Format.date(Date.shift(recent_day, month: 1))
    assert text(view, "#{pending} .hs-lead") == "running"
    assert text(view, "#{pending} .stat__sub") == "until #{until}"

    missing = "#sale-hindsight tr[data-sale='#{unpriced.id}'] td[data-span='1m']"
    assert text(view, missing) =~ "no start close"

    assert has_element?(
             view,
             "#{missing}[title='No close on the sale day and none in the 7 days before']"
           )

    assert text(view, "#sale-hindsight [data-role='hindsight-info'] p") =~
             "One row per sale booking, not per FIFO lot"

    assert text(view, "#sale-hindsight .hs-legend") =~
             "Price return: distributions after the sale not included"

    # The section sits after the trades list and before the matrix.
    html = render(view)
    {trades_at, _} = :binary.match(html, ~s(id="realized-trades"))
    {section_at, _} = :binary.match(html, ~s(id="sale-hindsight"))
    {annual_at, _} = :binary.match(html, ~s(id="realized-annual"))
    assert trades_at < section_at and section_at < annual_at
  end

  # User story (V3; board 03 ①, the chooser as query state):
  # As the operator comparing a sale with something else,
  # I want to choose none, a fixed rate or a flagged security, and type a
  # rate and press Enter,
  # so that each span reads the difference to what I chose, and a rate I
  # mistyped is named, not computed and not a crash.
  #
  # Acceptance criteria:
  # - "None" reads each span's own price return, as the API does without
  #   a benchmark.
  # - "Fixed rate" opens the rate field; submitting 2.5 patches the address
  #   with the rate and each span reads the difference the API answers for
  #   benchmark=rate:0.025.
  # - A misspelled rate and one beyond the engine's bound are named in an
  #   alert beside the field; the spans keep the security's own return.
  test "the chooser compares with none, a fixed rate and a flagged security", %{conn: conn} do
    %{sale: sale, bench: bench} = world()
    cell = "#sale-hindsight tr[data-sale='#{sale.id}'] td[data-span='3m'] .hs-lead"

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    # The default with a flagged benchmark: that benchmark.
    assert has_element?(view, "[data-role='hindsight-compare'] a.is-active", "Security")
    assert has_element?(view, "select[name='benchmark'] option[selected]", bench.name)

    view |> element("[data-role='hindsight-compare'] a", "None") |> render_click()
    assert_patch(view, "/cashflow?tab=realized&hindsight=none")
    own = api_span(conn, %{}, sale.id, "3m")
    assert text(view, cell) == percent(own["security"]["return"])
    assert text(view, cell) == "+20.0%"

    view |> element("[data-role='hindsight-compare'] a", "Fixed rate") |> render_click()
    assert_patch(view, "/cashflow?tab=realized&hindsight=rate")

    view
    |> form("form[data-role='hindsight-rate-form']", %{"rate" => "2.5"})
    |> render_submit()

    assert_patch(view, "/cashflow?tab=realized&hindsight=rate&hindsight_rate=2.5")
    rated = api_span(conn, %{"benchmark" => "rate:0.025"}, sale.id, "3m")
    assert text(view, cell) == percent(rated["difference"])
    refute has_element?(view, "[data-role='hindsight-rate-error']")

    for typo <- ["2,5x", "5000", "abc"] do
      view
      |> form("form[data-role='hindsight-rate-form']", %{"rate" => typo})
      |> render_submit()

      assert has_element?(view, "[data-role='hindsight-rate-error'][role='alert']"), typo
      assert text(view, cell) == percent(own["security"]["return"]), typo
    end

    view |> element("[data-role='hindsight-compare'] a", "Security") |> render_click()

    view
    |> form("form[data-role='hindsight-benchmark-form']", %{"benchmark" => "#{bench.id}"})
    |> render_change()

    assert_patch(
      view,
      "/cashflow?tab=realized&hindsight=security&hindsight_benchmark=#{bench.id}"
    )

    by_bench = api_span(conn, %{"benchmark" => "security:#{bench.id}"}, sale.id, "3m")
    assert text(view, cell) == percent(by_bench["difference"])
  end

  # User story (V3; a link handed over):
  # As the operator sending myself or the agent a link to a comparison,
  # I want the address to carry the chooser,
  # so that the link opens the same comparison, and a link with a rate
  # nobody can compute says so rather than crashing.
  #
  # Acceptance criteria:
  # - /cashflow?tab=realized&hindsight=rate&hindsight_rate=3 opens with
  #   "Fixed rate" chosen, the field reading 3 and the difference the API
  #   answers for rate:0.03; a German "3,5" reads as 3.5.
  # - An invalid rate in the link is named in the alert, the page renders.
  # - Without a flagged benchmark "Security" shows the shipped hint.
  test "a link carries the chooser, and an invalid rate in it is named", %{conn: conn} do
    %{sale: sale, bench: bench} = world()
    cell = "#sale-hindsight tr[data-sale='#{sale.id}'] td[data-span='1m'] .hs-lead"

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=rate&hindsight_rate=3")
    assert has_element?(view, "[data-role='hindsight-compare'] a.is-active", "Fixed rate")
    assert has_element?(view, "input[name='rate'][value='3']")
    rated = api_span(conn, %{"benchmark" => "rate:0.03"}, sale.id, "1m")
    assert text(view, cell) == percent(rated["difference"])

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=rate&hindsight_rate=3,5")
    rated = api_span(conn, %{"benchmark" => "rate:0.035"}, sale.id, "1m")
    assert text(view, cell) == percent(rated["difference"])

    {:ok, view, _html} =
      live(conn, "/cashflow?tab=realized&hindsight=rate&hindsight_rate=1e999")

    assert has_element?(view, "[data-role='hindsight-rate-error'][role='alert']")

    {:ok, _bench} = Catalog.update_security(Actor.owner_ui(), bench, %{is_benchmark: false})
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=security")

    assert has_element?(
             view,
             "#sale-hindsight [data-role='benchmark-none']",
             "No benchmark securities yet"
           )
  end

  # User story (V3; board 03, the security's Trades tab):
  # As the operator on one security's page,
  # I want the same section on its Trades tab, filtered to it,
  # so that I read what its sales missed where I read its trades.
  #
  # Acceptance criteria:
  # - /securities/:id?tab=trades carries the section under the closed
  #   trades with an h3 heading, only that security's sales, and no
  #   security column.
  # - Its chooser keeps the tab in the address.
  test "the security's Trades tab carries the section filtered to it", %{conn: conn} do
    %{sold: sold, sale: sale, bench: bench} = world()

    {:ok, view, _html} = live(conn, "/securities/#{sold.id}?tab=trades")

    assert has_element?(
             view,
             "#detail-tab-panel-trades #detail-sale-hindsight h3",
             "After the sale"
           )

    assert has_element?(view, "#detail-sale-hindsight tr[data-sale='#{sale.id}']")

    assert [_one] =
             view
             |> render()
             |> LazyHTML.from_document()
             |> LazyHTML.query("#detail-sale-hindsight tr[data-role='hindsight-row']")
             |> Enum.to_list()

    refute has_element?(view, "#detail-sale-hindsight [data-role='hindsight-name']")

    view
    |> element("#detail-sale-hindsight [data-role='hindsight-compare'] a", "None")
    |> render_click()

    assert_patch(view, "/securities/#{sold.id}?tab=trades&hindsight=none")

    _ = bench
  end

  # User story (V3; board 03, "what it does not build"; AGENTS.md: no
  # advice):
  # As the owner holding the line between a figure and a verdict,
  # I want the section in German with the board's words and no verdict,
  # so that it reports what the price did and never says a sale was wrong.
  #
  # Acceptance criteria:
  # - In German the section reads "Nach dem Verkauf", the chooser
  #   "Vergleich: Ohne · Fester Zins · Wertpapier", the spans "1M · 3M ·
  #   12M · Bis heute", a running span "läuft", a missing start "kein
  #   Startkurs".
  # - No verdict word appears in the section: too early, too late, right,
  #   wrong, mistake, missed out, better, worse (nor their German).
  # - Mode 3 (R3, ADR-0057 §5), in English and in German, carries none
  #   either, and speaks German: „Anschlusskauf“, „Angelegt“, „behalten“,
  #   „gewechselt“, „Erlös angelegt in“, „Keine Anschlusskäufe gefunden“.
  test "the section speaks German and carries no verdict", %{conn: conn} do
    %{recent: recent, unpriced: unpriced} = world()
    %{sale: switched, lone: lone} = switch_world()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&locale=de")

    assert has_element?(view, "#sale-hindsight h2", "Nach dem Verkauf")

    assert text(view, "[data-role='hindsight-compare']") =~
             "Vergleich Ohne Fester Zins Wertpapier"

    assert text(view, "#sale-hindsight thead") =~ "1M 3M 12M Bis heute"

    assert text(view, "#sale-hindsight tr[data-sale='#{recent.id}'] td[data-span='3m']") =~
             "läuft"

    assert text(view, "#sale-hindsight tr[data-sale='#{unpriced.id}'] td[data-span='1m']") =~
             "kein Startkurs"

    refute_verdict(view)

    # --- Sprint 26 R3 begin ---
    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=reinvestment&locale=de")

    assert text(view, "[data-role='hindsight-compare']") =~
             "Vergleich Ohne Fester Zins Wertpapier Anschlusskauf"

    assert text(view, "#sale-hindsight thead") =~ "Angelegt 1M 3M 12M Bis heute"
    one = text(view, "#sale-hindsight tr[data-sale='#{switched.id}'] td[data-span='1m']")
    assert one =~ "behalten" and one =~ "gewechselt" and one =~ "Steuern zugerechnet"

    assert text(
             view,
             "#sale-hindsight tr[data-role='hindsight-detail'][data-sale='#{switched.id}']"
           ) =~
             "Erlös angelegt in: Synthetic Next Fund, gekauft 20.01.2025 (5 Tage nach dem Verkauf)"

    assert text(view, "#sale-hindsight tr[data-sale='#{lone.id}'] td.hs-nobuys") =~
             "Keine Anschlusskäufe gefunden"

    assert text(view, "#sale-hindsight [data-role='hindsight-info'] p") =~
             "der letzte zählt anteilig; Verkäufe und Käufe desselben Tages teilen anteilig."

    refute_verdict(view)

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=reinvestment")
    assert text(view, "#sale-hindsight thead") =~ "Invested"
    refute_verdict(view)
    # --- Sprint 26 R3 end ---
  end

  @verdicts [
    "too early",
    "too late",
    "wrong",
    "mistake",
    "missed out",
    "better",
    "worse",
    "zu früh",
    "zu spät",
    "richtig",
    "falsch",
    "fehler",
    "besser",
    "schlechter",
    "verpasst"
  ]

  defp refute_verdict(view) do
    section = view |> text("#sale-hindsight") |> String.downcase()

    for word <- @verdicts do
      refute section =~ word, word
    end
  end

  # --- Sprint 26 R3 begin ---

  # User story (R3, I18 mode 3; ADR-0057 §6; board 03 frame m3):
  # As the operator who sold one thing and bought another with the money,
  # I want the chooser's fourth comparison „Anschlusskauf“ to set each sale
  # against the buys its proceeds went into, per span,
  # so that I see what the switch did, with its fees, its taxes and the
  # days to the first buy, without asking the agent.
  #
  # Acceptance criteria:
  # - With hindsight=reinvestment a span reads the difference switched −
  #   kept in EUR over "kept" and "switched", and "taxes added back" where
  #   the sale paid taxes; the difference is the API's for
  #   include=reinvestment, to the displayed cent.
  # - The third column reads "Invested": what the buys took and its share
  #   of the proceeds.
  # - Under each matched sale its buys: name, date, the days after the sale,
  #   the amount, "pro rata x of y" for a buy funded in part; then the cost
  #   line of its latest measured span: the fees inside, the sale's taxes
  #   added back, the buys' income not added.
  # - A span not ended reads "running"; one the read cannot measure reads
  #   its reason and the side it is missing on; a sale with no follow-on
  #   purchase reads its reason in words across the spans.
  # - The phone rows carry the same figures; the ⓘ and the legend add mode
  #   3's basis.
  test "Follow-on purchase sets each sale against the buys its money went into, as the API answers",
       %{conn: conn} do
    %{sale: sale, recent: recent, recent_day: recent_day, lone: lone} = switch_world()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=reinvestment")

    assert has_element?(
             view,
             "[data-role='hindsight-compare'] a.is-active",
             "Follow-on purchase"
           )

    block = api_block(conn, sale.id)
    assert block["status"] == "matched"
    row = "#sale-hindsight tr[data-role='hindsight-row'][data-sale='#{sale.id}']"

    one = api_switch_span(block, "1m")

    assert text(view, "#{row} td[data-span='1m'] .hs-lead") ==
             signed_money(one["difference"]) <> " EUR"

    assert text(view, "#{row} td[data-span='1m'] .hs-lead") =~ "44.47"

    assert texts(view, "#{row} td[data-span='1m'] .stat__sub") == [
             "kept #{money(one["kept"])}",
             "switched #{money(one["switched"])}",
             "taxes added back #{signed_money(one["taxes_apart"])}"
           ]

    assert texts(view, "#{row} td[data-role='hindsight-invested'] .stat__sub") ==
             ["100.0% of the proceeds"]

    assert text(view, "#{row} td[data-role='hindsight-invested']") =~ "1,003.50 EUR"

    twelve = text(view, "#{row} td[data-span='12m']")
    assert twelve =~ "no end close" and twelve =~ "switched side"

    assert has_element?(
             view,
             "#{row} td[data-span='12m'][title=\"No close at the span's end and none in the 7 days before\"]"
           )

    detail = "#sale-hindsight tr[data-role='hindsight-detail'][data-sale='#{sale.id}']"
    three = api_switch_span(block, "3m")

    assert texts(view, "#{detail} .hs-detail__buys, #{detail} .hs-detail__costs") == [
             "Proceeds invested in: Synthetic Next Fund, bought #{Format.date(~D[2025-01-20])} " <>
               "(5 days after the sale), 802.00 EUR; Synthetic Second Fund, bought " <>
               "#{Format.date(~D[2025-02-05])} (21 days after the sale), pro rata 201.50 of " <>
               "300.00 EUR",
             "3M · Fees, inside the difference: #{money(three["fees_inside"])} EUR · " <>
               "The sale's taxes, added back to the switched side: " <>
               "#{money(three["taxes_apart"])} EUR · The buys' income, not added: none"
           ]

    assert money(three["fees_inside"]) == "3.50"
    assert block["days_to_first_buy"] == 5

    pending = "#sale-hindsight tr[data-role='hindsight-row'][data-sale='#{recent.id}']"

    assert texts(view, "#{pending} td[data-role='hindsight-invested'] .stat__sub") ==
             ["75.0% of the proceeds"]

    assert texts(view, "#{pending} td[data-span='1m'] span") ==
             ["running", "until #{Format.date(Date.shift(recent_day, month: 1))}"]

    assert api_block(conn, lone.id)["reason"] == "no_buy_within_30_days"

    assert text(view, "#sale-hindsight tr[data-sale='#{lone.id}'] td.hs-nobuys") ==
             "No follow-on purchases found: no buy from the sale's cash account within 30 days of the sale day"

    refute has_element?(
             view,
             "#sale-hindsight tr[data-role='hindsight-detail'][data-sale='#{lone.id}']"
           )

    phone = "#sale-hindsight li[data-role='hindsight-phone-row'][data-sale='#{sale.id}']"
    assert text(view, phone) =~ "Invested 1,003.50 EUR · 100.0% of the proceeds"
    assert text(view, "#{phone} .hs-detail-phone") =~ "pro rata 201.50 of 300.00 EUR"

    assert text(view, "#sale-hindsight li[data-sale='#{lone.id}'] .hs-nobuys--phone") =~
             "No follow-on purchases found"

    assert text(view, "#sale-hindsight [data-role='hindsight-info'] p") =~
             "Follow-on purchase: the buys from the sale's cash account"

    # ADR-0057 as amended: sales and buys on one day share pro rata, never
    # in booking order.
    assert text(view, "#sale-hindsight [data-role='hindsight-info'] p") =~
             "the last one counts pro rata; sales and buys on the same day share pro rata."

    assert text(view, "#sale-hindsight .hs-legend") =~
             "Per span switched − kept in EUR, both before tax"
  end

  # User story (R3; the chooser's state is the address):
  # As the operator handing a link to the switch comparison to myself or
  # the agent,
  # I want the fourth choice to live in the address,
  # so that the link opens it again, on Cash flow and on the security's
  # Trades tab, and an address nobody wrote does not crash the page.
  #
  # Acceptance criteria:
  # - Choosing „Follow-on purchase“ patches hindsight=reinvestment; „None“
  #   from there drops the buys.
  # - An unknown hindsight value (misspelled, upper case, empty) opens the
  #   default comparison.
  # - The security's Trades tab opens mode 3 from its link, keeps the tab
  #   and shows its sale's buys under it.
  test "the fourth choice is part of the address, and an unknown one falls back",
       %{conn: conn} do
    %{sold: sold, sale: sale} = switch_world()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")
    assert has_element?(view, "[data-role='hindsight-compare'] a.is-active", "None")

    view |> element("[data-role='hindsight-compare'] a", "Follow-on purchase") |> render_click()
    assert_patch(view, "/cashflow?tab=realized&hindsight=reinvestment")
    assert has_element?(view, "tr[data-role='hindsight-detail'][data-sale='#{sale.id}']")

    view |> element("[data-role='hindsight-compare'] a", "None") |> render_click()
    assert_patch(view, "/cashflow?tab=realized&hindsight=none")
    refute has_element?(view, "tr[data-role='hindsight-detail']")

    for value <- ["Reinvestment", "reinvest", "", "%00"] do
      {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=#{value}")
      assert has_element?(view, "[data-role='hindsight-compare'] a.is-active", "None"), value
      refute has_element?(view, "tr[data-role='hindsight-detail']"), value
    end

    {:ok, view, _html} = live(conn, "/securities/#{sold.id}?tab=trades&hindsight=reinvestment")

    assert has_element?(
             view,
             "#detail-sale-hindsight [data-role='hindsight-compare'] a.is-active",
             "Follow-on purchase"
           )

    assert has_element?(
             view,
             "#detail-sale-hindsight tr[data-role='hindsight-detail'][data-sale='#{sale.id}'] td[colspan='6']",
             "Synthetic Next Fund"
           )

    refute has_element?(view, "#detail-sale-hindsight [data-role='hindsight-name']")

    view
    |> element("#detail-sale-hindsight [data-role='hindsight-compare'] a", "None")
    |> render_click()

    assert_patch(view, "/securities/#{sold.id}?tab=trades&hindsight=none")
  end

  # --- Sprint 26 R3 end ---

  # --- Sprint 26 fix P begin ---
  # The privacy mode (P1) on "After the sale" (closing act, P-fix 1): the
  # section built its phone rows, mode 3's invested line and its cost
  # title by concatenating a masked figure, which crashed the page.

  defp masked(conn),
    do:
      PortfolixirWeb.PreferenceCookieHelpers.put_preference_cookie(
        conn,
        "portfolixir_privacy",
        "on"
      )

  # The section renders, its figures are bars, none of `figures` is
  # anywhere in its markup (text or attribute), and no hidden figure is
  # drawn as its stand-in text.
  defp assert_masked(view, section, figures) do
    html = view |> element(section) |> render()

    assert html =~ "pf-mask", "no figure of #{section} is drawn as the bar"

    for figure <- figures do
      refute html =~ figure, "#{figure} shows in #{section} with the privacy mode on"
    end

    refute html |> LazyHTML.from_fragment() |> LazyHTML.text() |> String.contains?("••••"),
           "a hidden figure of #{section} is drawn as text"
  end

  # User story (P1 x V3/R3, the closing act's finding 1):
  # As the operator who switched the privacy mode on before sharing my
  # screen,
  # I want "After the sale" to render in each of its four comparisons, on
  # Cash flow → Trades and on a security's Trades tab, its amounts and
  # quantities as bars,
  # so that the mode neither crashes the page nor shows what a sale was.
  #
  # Acceptance criteria:
  # - Cash flow → Trades renders with the mode on in the comparisons none,
  #   a fixed rate, a flagged security and the follow-on purchase; the
  #   security's Trades tab in none and the follow-on purchase.
  # - No sale price, quantity, start close, invested amount, buy amount,
  #   kept or switched value, fee or tax shows, in the text or a cell's
  #   title; each is the bar, and none is drawn as the text „••••“.
  # - Percentages stay: a span's return, a fixed rate's percent.
  test "the section renders in every comparison with the privacy mode on and shows no amount",
       %{conn: conn} do
    %{sold: sold, sale: sale, bench: bench} = world()
    figures = ["101.50", "1,015.00", "1,000.00", "100.00", "10 ×"]

    for query <- [
          "hindsight=none",
          "hindsight=rate&hindsight_rate=3",
          "hindsight=security&hindsight_benchmark=#{bench.id}"
        ] do
      {:ok, view, _html} = conn |> masked() |> live("/cashflow?tab=realized&" <> query)
      assert_masked(view, "#sale-hindsight", figures)
      assert has_element?(view, "#sale-hindsight [data-role='hindsight-phone-row']"), query
    end

    {:ok, view, _html} =
      conn |> masked() |> live("/cashflow?tab=realized&hindsight=rate&hindsight_rate=3")

    assert text(view, "#sale-hindsight .hs-group") =~ "Difference to 3.00 % p.a."

    assert text(view, "#sale-hindsight tr[data-sale='#{sale.id}'] td[data-span='3m'] .hs-lead") =~
             "%"

    {:ok, view, _html} = conn |> masked() |> live("/securities/#{sold.id}?tab=trades")
    assert_masked(view, "#detail-sale-hindsight", figures)
  end

  test "the follow-on purchase renders with the privacy mode on and shows no amount",
       %{conn: conn} do
    %{sold: sold, sale: sale} = switch_world()
    figures = ["101.50", "1,003.50", "802.00", "201.50", "300.00", "10.00", "1.50"]

    {:ok, view, _html} = conn |> masked() |> live("/cashflow?tab=realized&hindsight=reinvestment")
    assert_masked(view, "#sale-hindsight", figures)

    assert has_element?(
             view,
             "#sale-hindsight tr[data-role='hindsight-detail'][data-sale='#{sale.id}']",
             "Synthetic Next Fund"
           )

    assert has_element?(
             view,
             "#sale-hindsight td[data-span='1m'][title*='Fees, inside the difference: ••••']"
           )

    assert text(
             view,
             "#sale-hindsight tr[data-sale='#{sale.id}'] [data-role='hindsight-invested']"
           ) =~
             "of the proceeds"

    {:ok, view, _html} =
      conn |> masked() |> live("/securities/#{sold.id}?tab=trades&hindsight=reinvestment")

    assert_masked(view, "#detail-sale-hindsight", figures)
  end

  # --- Sprint 26 fix P end ---

  # --- Sprint 26 fix D begin ---
  # User story (closing act, UAT persona on V3):
  # As the operator typing the rate as I would write it,
  # I want „2,5 %“ in the fixed-rate field to be read as 2.5,
  # so that the percent sign the label already names does not turn the
  # rate into an error.
  #
  # Acceptance criteria:
  # - A rate with a trailing percent sign, with or without spaces around it
  #   („2,5 %“, „2.5%“, „ 3 % “), is read as the number before it, typed
  #   or in a link, and each span reads the difference the API answers for
  #   that rate.
  # - Anything else stays refused as before: a sign alone, a sign with
  #   text after it, a rate beyond the bound.
  test "a fixed rate typed with a percent sign is read as its number", %{conn: conn} do
    %{sale: sale} = world()
    cell = "#sale-hindsight tr[data-sale='#{sale.id}'] td[data-span='3m'] .hs-lead"
    rated = api_span(conn, %{"benchmark" => "rate:0.025"}, sale.id, "3m")

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&hindsight=rate")

    for typed <- ["2,5 %", "2.5%", " 2.5 % "] do
      view
      |> form("form[data-role='hindsight-rate-form']", %{"rate" => typed})
      |> render_submit()

      refute has_element?(view, "[data-role='hindsight-rate-error']"), typed
      assert text(view, cell) == percent(rated["difference"]), typed
    end

    {:ok, view, _html} =
      live(
        conn,
        "/cashflow?tab=realized&hindsight=rate&hindsight_rate=" <> URI.encode_www_form("3 %")
      )

    refute has_element?(view, "[data-role='hindsight-rate-error']")
    three = api_span(conn, %{"benchmark" => "rate:0.03"}, sale.id, "3m")
    assert text(view, cell) == percent(three["difference"])

    for typo <- ["%", "2,5 %x", "% 2,5x", "5000 %"] do
      view
      |> form("form[data-role='hindsight-rate-form']", %{"rate" => typo})
      |> render_submit()

      assert has_element?(view, "[data-role='hindsight-rate-error'][role='alert']"), typo
    end
  end

  # --- Sprint 26 fix D end ---

  # --- Sprint 29 B2 begin ---
  # The select's optgroups in order, each with its options' names.
  defp select_groups(view) do
    view
    |> element("#sale-hindsight select[name='benchmark']")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("optgroup")
    |> Enum.map(fn group ->
      [label] = LazyHTML.attribute(group, "label")

      {label,
       group |> LazyHTML.query("option") |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))}
    end)
  end

  # A fund held today, with closes on the sale's days.
  defp held_fund!(world) do
    held = create_security!(name: "Synthetic Held Fund", ticker: "SHLD", currency: "EUR")
    buy!(world, held, quantity: "4", price: "50", date: ~D[2024-12-02])

    put_quotes!(held, [
      {~D[2024-12-02], "50"},
      {~D[2025-01-15], "50"},
      {~D[2025-02-14], "55"},
      {~D[2025-04-15], "60"},
      {~D[2026-01-15], "40"}
    ])

    held
  end

  # User story (#1416, B2; ADR-0046's amendment of 2026-11-07, point 3;
  # ADR-0058 F5; board 02 ③, Q1 A):
  # As the operator asking what a sale missed against a fund I hold,
  # I want „Nach dem Verkauf“'s select to offer the flagged benchmarks and
  # then the securities I hold today, as two labelled groups,
  # so that I pick my own fund and each span reads the difference to it,
  # the same the API answers.
  #
  # Acceptance criteria:
  # - The select carries the optgroups „Benchmarks“ (flagged, with a
  #   quote) then „In holdings“ (held today, with a quote, unflagged), by
  #   name; its default stays the first flagged security.
  # - Choosing the held fund patches the address with
  #   hindsight_benchmark=<id>, the select shows it chosen, and the 3m span
  #   reads the difference GET /api/v1/sales/hindsight answers for
  #   benchmark=security:<id>.
  test "the select offers the held funds after the benchmarks and compares with the one picked",
       %{conn: conn} do
    %{world: world, sale: sale, bench: bench} = world()
    held = held_fund!(world)
    cell = "#sale-hindsight tr[data-sale='#{sale.id}'] td[data-span='3m'] .hs-lead"

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized")

    assert select_groups(view) == [
             {"Benchmarks", ["Synthetic Bench Index"]},
             {"In holdings", ["Synthetic Held Fund"]}
           ]

    assert has_element?(view, "select[name='benchmark'] option[selected]", bench.name)

    view
    |> form("form[data-role='hindsight-benchmark-form']", %{"benchmark" => "#{held.id}"})
    |> render_change()

    assert_patch(
      view,
      "/cashflow?tab=realized&hindsight=security&hindsight_benchmark=#{held.id}"
    )

    assert has_element?(view, "select[name='benchmark'] option[selected]", held.name)
    by_held = api_span(conn, %{"benchmark" => "security:#{held.id}"}, sale.id, "3m")
    assert text(view, cell) == percent(by_held["difference"])
    assert text(view, "#sale-hindsight .hs-legend") =~ held.name
  end

  # Acceptance criteria (#1416, B2; ADR-0058 F5):
  # - A link naming a held fund opens with it chosen and compared, never
  #   dropped to the first flagged benchmark.
  # - A link naming an unheld security with a quote, which the API takes,
  #   opens with it chosen too, in a third group, so the select shows what
  #   is compared.
  # - A flagged fund that is also held is offered once, under „Benchmarks“.
  # - In German the groups read „Benchmarks“, „Im Bestand“, „Weitere“.
  test "a held or quoted security in the link stays chosen; a held benchmark is listed once",
       %{conn: conn} do
    %{world: world, sale: sale, bench: bench} = world()
    held = held_fund!(world)
    buy!(world, bench, quantity: "1", price: "200", date: ~D[2024-12-02])
    watched = create_security!(name: "Synthetic Watched Fund", ticker: "SWTF", currency: "EUR")
    put_quotes!(watched, [{~D[2025-01-15], "10"}, {~D[2025-04-15], "12"}])
    cell = "#sale-hindsight tr[data-sale='#{sale.id}'] td[data-span='3m'] .hs-lead"

    {:ok, view, _html} =
      live(conn, "/cashflow?tab=realized&hindsight=security&hindsight_benchmark=#{held.id}")

    assert has_element?(view, "select[name='benchmark'] option[selected]", held.name)
    by_held = api_span(conn, %{"benchmark" => "security:#{held.id}"}, sale.id, "3m")
    assert text(view, cell) == percent(by_held["difference"])

    link = "/cashflow?tab=realized&hindsight=security&hindsight_benchmark=#{watched.id}"
    {:ok, view, _html} = live(conn, link)

    assert has_element?(view, "select[name='benchmark'] option[selected]", watched.name)
    by_watched = api_span(conn, %{"benchmark" => "security:#{watched.id}"}, sale.id, "3m")
    assert text(view, cell) == percent(by_watched["difference"])

    {:ok, view, _html} = live(conn, link <> "&locale=de")

    assert select_groups(view) == [
             {"Benchmarks", ["Synthetic Bench Index"]},
             {"Im Bestand", ["Synthetic Held Fund"]},
             {"Weitere", ["Synthetic Watched Fund"]}
           ]
  end

  # --- Sprint 29 B2 end ---
end
