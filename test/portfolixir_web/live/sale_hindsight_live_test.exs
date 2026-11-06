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
    only: [base_world: 1, create_security!: 1, put_quotes!: 2, sell!: 3]

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
  test "the section speaks German and carries no verdict", %{conn: conn} do
    %{recent: recent, unpriced: unpriced} = world()

    {:ok, view, _html} = live(conn, "/cashflow?tab=realized&locale=de")

    assert has_element?(view, "#sale-hindsight h2", "Nach dem Verkauf")

    assert text(view, "[data-role='hindsight-compare']") =~
             "Vergleich Ohne Fester Zins Wertpapier"

    assert text(view, "#sale-hindsight thead") =~ "1M 3M 12M Bis heute"

    assert text(view, "#sale-hindsight tr[data-sale='#{recent.id}'] td[data-span='3m']") =~
             "läuft"

    assert text(view, "#sale-hindsight tr[data-sale='#{unpriced.id}'] td[data-span='1m']") =~
             "kein Startkurs"

    section = view |> text("#sale-hindsight") |> String.downcase()

    verdicts = [
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

    for word <- verdicts do
      refute section =~ word, word
    end
  end
end
