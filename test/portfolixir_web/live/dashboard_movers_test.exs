defmodule PortfolixirWeb.DashboardMoversTest do
  # Sprint 30 Lane T, T3 (FR-59, idea I32; ADR-0061 §9; board
  # `ux-design-2026-11-15-sprint30/04-tops-flops`, A and A1): the Overview's
  # card „Tops und Flops“, every figure on it compared with the API's answer
  # for the same window (`GET /api/v1/movers`, the Overview's scope when no
  # default view is set; the plan's D-1, criterion 7).
  #
  # Sprint 31 D5 (ADR-0062 §5; idea board ux-design-2026-11-21-idea-i56
  # 05, A, which supersedes the window chips inside the widget): the
  # dashboard's period above the widgets drives the card's window by the
  # registry's rule (1T Day, 1W Week, 1M Month, 3M Quarter, YTD, 1J 1Y;
  # 3J and Max read 1Y and say so), and the address carries it as
  # `?period=`; dashboard_period_test.exs holds the period itself.
  use PortfolixirWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      buy!: 3,
      create_security!: 1,
      deliver_untraded!: 4,
      deposit!: 3,
      put_quotes!: 2,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.Performance.Movers
  alias Portfolixir.Repo
  alias Portfolixir.Settings
  alias PortfolixirWeb.Format

  # The dashboard's period for each of the read's windows.
  @windows [
    {"1d", "day"},
    {"1w", "week"},
    {"1m", "month"},
    {"3m", "quarter"},
    {"ytd", "ytd"},
    {"1y", "1y"}
  ]

  # Four securities priced every day of the last 400, each on its own slope;
  # the share stops two days ago (a weekend's „Tag“ is Friday against
  # Thursday). A bond has no close at all (no price return; its position is
  # valued at its booking's price, so it contributes exactly zero and is
  # counted, never ranked: board 04 ②), a
  # dollar fund has closes but no exchange rate (no price return, and its
  # position is valued on no day, so it is counted, not ranked). One
  # position is sold today, so it is in every window's contribution and in
  # no price ranking.
  defp seed! do
    today = Clock.today()
    world = base_world(name: "Movers Card", cash_name: "Giro", depot_name: "Depot")
    deposit!(world, "50000", Date.add(today, -420))

    climber = create_security!(name: "Synthetic Climber Fund", ticker: "SCF")
    steady = create_security!(name: "Synthetic Steady Fund", ticker: "SSF")
    share = create_security!(name: "Synthetic Falling Share", ticker: "SFS")
    sold = create_security!(name: "Synthetic Sold Fund", ticker: "SSO")
    unpriced = create_security!(name: "Synthetic Unpriced Bond", ticker: "SUB")
    dollar = create_security!(name: "Synthetic Dollar Fund", ticker: "SDO", currency: "USD")

    for {security, step, last} <- [
          {climber, "0.5", 0},
          {steady, "0.05", 0},
          {share, "-0.1", 2},
          {sold, "0.2", 0},
          {dollar, "0.3", 0}
        ] do
      put_quotes!(
        security,
        for(back <- 400..last//-1, do: {Date.add(today, -back), price(step, 400 - back)})
      )
    end

    for security <- [climber, steady, share, unpriced, dollar],
        do: buy!(world, security, quantity: "10", price: "100", date: Date.add(today, -390))

    buy!(world, sold, quantity: "5", price: "170", date: Date.add(today, -30))
    sell!(world, sold, quantity: "5", price: "180", date: today)

    %{today: today, share: share, sold: sold}
  end

  # 100 + step × day: a close that moves by `step` every day.
  defp price(step, day), do: step |> Decimal.new() |> Decimal.mult(day) |> Decimal.add(100)

  defp api(path) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
    |> get(path)
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  # The sentence naming Wealth's other view, its `<bdi>`s read as running
  # text.
  defp wealth_view(doc),
    do: doc |> Floki.find("[data-role='movers-wealth-view']") |> Floki.text() |> String.trim()

  defp attribute(node, name), do: node |> Floki.attribute(name) |> List.first()

  # The name slot's own text, before its badge, its marker and its sub-line.
  defp row_name(row) do
    [{_tag, _attrs, [name | _rest]}] = Floki.find(row, ".attention-name")
    String.trim(name)
  end

  defp loaded(view, window) do
    render_async(view)
    doc = document(view)
    assert [_card] = Floki.find(doc, "#dashboard-movers")
    assert Floki.find(doc, "[data-role='movers-skeleton']") == []
    assert doc |> Floki.find("#dashboard-movers") |> Floki.attribute("data-window") == [window]
    doc
  end

  # The count lines under „Contribution“, one per reason, in order.
  defp contribution_counts(doc),
    do: doc |> Floki.find("[data-role='movers-contribution-count']") |> Enum.map(&text/1)

  defp percent(text), do: Format.signed_percent(Decimal.new(text)) <> "%"
  defp money(text), do: Format.signed_decimal(Decimal.new(text), 2) <> " EUR"

  defp weekday(%Date{} = date), do: Calendar.strftime(date, "%a")

  # Every figure on the card against the API's answer for the same window:
  # the rows in order, each name, link, figure, sold badge and date line,
  # the halves' sizes, the counts and the link to Wealth.
  defp assert_card_is_the_api(doc, window) do
    answer = api("/api/v1/movers?window=#{window}")
    assert answer["window"] == window

    for half <- ~w(highest lowest) do
      rows =
        Floki.find(
          doc,
          "[data-role='movers-return'] [data-half='#{half}'] [data-role='movers-row']"
        )

      entries = answer["price_return"][half]
      assert length(rows) == length(entries), "#{window} price #{half}"

      for {row, entry} <- Enum.zip(rows, entries) do
        assert attribute(row, "href") == "/securities/#{entry["security"]["id"]}"
        assert row_name(row) == entry["security"]["name"]

        assert row |> Floki.find("[data-role='movers-figure']") |> text() ==
                 percent(entry["return"])

        assert Floki.find(row, "[data-role='movers-sold']") == []

        assert row |> Floki.find("[data-role='movers-dates']") |> text() ==
                 price_dates(window, entry, answer)
      end

      rows =
        Floki.find(
          doc,
          "[data-role='movers-contribution'] [data-half='#{half}'] [data-role='movers-row']"
        )

      entries = answer["contribution"][half]
      assert length(rows) == length(entries), "#{window} contribution #{half}"

      for {row, entry} <- Enum.zip(rows, entries) do
        assert attribute(row, "href") == "/securities/#{entry["security"]["id"]}"
        assert row_name(row) == entry["security"]["name"]

        assert row |> Floki.find("[data-role='movers-figure']") |> text() ==
                 money(entry["contribution"])

        sold? = Floki.find(row, "[data-role='movers-sold']") != []
        assert sold? == (entry["held_at_end"] == false)
      end
    end

    contribution = answer["contribution"]

    [link] = Floki.find(doc, "[data-role='movers-wealth-link']")

    assert attribute(link, "href") ==
             "/portfolio?from=#{contribution["from"]}&to=#{contribution["to"]}"

    # Wealth remembers the card's own scope here: no sentence names another.
    assert Floki.find(doc, "[data-role='movers-wealth-view']") == []

    answer
  end

  defp price_dates("day", entry, _answer),
    do:
      "#{weekday(Date.from_iso8601!(entry["start"]["date"]))} #{Format.date(Date.from_iso8601!(entry["start"]["date"]))}" <>
        " → " <>
        "#{weekday(Date.from_iso8601!(entry["end"]["date"]))} #{Format.date(Date.from_iso8601!(entry["end"]["date"]))}"

  defp price_dates(_window, entry, answer) do
    if entry["end"]["date"] == answer["end_on"],
      do: "",
      else: "last close #{Format.date(Date.from_iso8601!(entry["end"]["date"]))}"
  end

  # User story (FR-59, ADR-0061 §1 and §9; board 04, A):
  # As the operator landing on the Overview,
  # I want the securities that moved most and the positions that made or
  # cost me most, today, this week, this month, this quarter, this year and
  # over one year, side by side,
  # so that I see what moved and what it meant for me without choosing a
  # period first, and with the same figures my agent reads.
  #
  # Acceptance criteria:
  # - The card „Tops and flops“ stands under the KPI strip, before the
  #   closed trades and „Off target“; its window is the dashboard's period
  #   (Sprint 31 D5: 1Y by default), and it has no chips of its own.
  # - Each period of the dashboard (1D, 1W, 1M, 3M, YTD, 1Y) patches the
  #   address (`?period=`, none for 1Y) and the card reads its window (Day,
  #   Week, Month, Quarter, YTD, 1Y) in the background; every figure on it
  #   equals the API's
  #   answer for the same window: price return first, contribution beside
  #   it, each with its highest over its lowest, in the API's order, each
  #   name linking to its security.
  # - A position sold in the window is marked „sold“ in the contribution
  #   column and is in no price ranking.
  # - Under each list the count without an answer: per reason for the price
  #   return; for the contribution the positions valued on no day, and the
  #   positions without a contribution, whose 0,00 stands in neither half
  #   (board 04 ②: „19 Positionen ohne Beitrag im Zeitraum“; Sprint 30
  #   closing act, design critic, finding 4).
  # - A „Day“ row names its two closes' dates with their weekdays; a row of
  #   another window whose last close is before the window's end names it.
  # - „View in Wealth →“ opens Wealth with the contribution's window as a
  #   custom range, and no `view=` (#1081's rule).
  test "every figure on the card is the API's for each window the period chooses", %{conn: conn} do
    %{today: today, share: share, sold: sold} = seed!()

    {:ok, view, _html} = live(conn, "/")
    doc = loaded(view, "1y")

    html = render(view)
    {strip_at, _} = :binary.match(html, ~s(id="dashboard-wealth"))
    {card_at, _} = :binary.match(html, ~s(id="dashboard-movers"))
    {trades_at, _} = :binary.match(html, ~s(id="dashboard-trades"))
    assert strip_at < card_at and card_at < trades_at

    assert doc |> Floki.find("#movers-title") |> text() == "Tops and flops"
    assert Floki.find(doc, "[data-role='movers-bar']") == []
    assert Floki.find(doc, "[data-role='movers-period']") == []

    for {period, window} <- @windows do
      doc =
        if window == "1y" do
          doc
        else
          view
          |> element("[data-role='dashboard-period'] button[data-period='#{period}']")
          |> render_click()

          assert_patch(view, "/?period=#{period}")
          loaded(view, window)
        end

      answer = assert_card_is_the_api(doc, window)

      # Three held securities priced, so two over one. The bond's
      # contribution is exactly zero, so it stands in neither half; on „Day“
      # the share's too (its last close is two days old, so it moved nothing
      # on D, today). Four positions with a contribution, the sold one among
      # them, so two over two; on „Day“ three, so two over one.
      # The share's last close is two days before today, so it moved
      # nothing in a window that starts on or after that day: „Day“ always,
      # „Week“ on a Monday (S is the Sunday before), „Month“ on the 1st or
      # 2nd. The rule is the window's, not the weekday the suite runs on.
      share_moved? =
        window != "day" and
          Date.compare(Date.add(today, -2), Movers.start_on(window, today)) == :gt

      zeros = if share_moved?, do: 1, else: 2
      assert answer["price_return"]["answered"] == 3
      assert length(answer["price_return"]["highest"]) == 2
      assert length(answer["price_return"]["lowest"]) == 1
      assert answer["contribution"]["answered"] == 5 - zeros
      assert length(answer["contribution"]["highest"]) == 2
      assert length(answer["contribution"]["lowest"]) == 3 - zeros

      price_ids =
        for half <- ~w(highest lowest), e <- answer["price_return"][half], do: e["security"]["id"]

      refute sold.id in price_ids

      [sold_row] =
        doc
        |> Floki.find("[data-role='movers-contribution'] [data-role='movers-row']")
        |> Enum.filter(&(attribute(&1, "href") == "/securities/#{sold.id}"))

      assert sold_row |> Floki.find("[data-role='movers-sold']") |> text() == "sold"

      # The unanswered, each by its reason on the price side: the bond (on
      # „Day“ it has no latest close; otherwise none at the start) and the
      # dollar fund (no exchange rate); on the money side the dollar fund,
      # valued on no day, and the bond (on „Day“ also the share), whose
      # contribution is 0.
      if window == "day" do
        assert answer["price_return"]["unanswered"]["no_close_at_end"] == 1

        assert doc |> Floki.find("[data-role='movers-return-count']") |> text() ==
                 "2 without a price return: 1 without a recent close, 1 without an exchange rate"
      else
        assert answer["price_return"]["unanswered"]["no_close_at_start"] == 1

        assert doc |> Floki.find("[data-role='movers-return-count']") |> text() ==
                 "2 without a price return: 1 without a close at the start, 1 without an exchange rate"
      end

      assert answer["price_return"]["unanswered"]["no_fx_rate"] == 1

      assert answer["contribution"]["unanswered"] == %{
               "no_valuation" => 1,
               "zero_contribution" => zeros
             }

      assert contribution_counts(doc) == [
               "1 position not valued on any day of the period",
               cond do
                 window == "day" -> "2 positions without a contribution on their day"
                 share_moved? -> "1 position without a contribution in the period"
                 true -> "2 positions without a contribution in the period"
               end
             ]

      # The share's row names its dates: on „Day“ the close before its
      # latest against that latest, two days before today; otherwise its
      # last close, which is before the window's end.
      [share_row] =
        doc
        |> Floki.find("[data-role='movers-return'] [data-role='movers-row']")
        |> Enum.filter(&(attribute(&1, "href") == "/securities/#{share.id}"))

      last = Date.add(today, -2)

      expected =
        if window == "day",
          do:
            "#{weekday(Date.add(today, -3))} #{Format.date(Date.add(today, -3))} → #{weekday(last)} #{Format.date(last)}",
          else: "last close #{Format.date(last)}"

      assert share_row |> Floki.find("[data-role='movers-dates']") |> text() == expected
    end
  end

  # User story (ADR-0061 §9; board 04, the chips' links):
  # As the operator handing a colleague the Overview on this quarter, or
  # reloading it,
  # I want the window in the address to open the card on that window,
  # so that the link shows what I saw.
  #
  # Acceptance criteria:
  # - `/?period=3m` opens the card on „Quarter“, its figures the API's
  #   for the quarter, its basis line naming the quarter's dates
  #   (Sprint 31 D5: the dashboard's period in the address).
  # - `/?period=1d` opens it on „Day“; a value that is no period opens the
  #   dashboard's default, 1J, the card on „1Y“.
  test "a handed-over link opens the card on its window", %{conn: conn} do
    %{today: today} = seed!()

    {:ok, view, _html} = live(conn, "/?period=3m")
    doc = loaded(view, "quarter")
    answer = assert_card_is_the_api(doc, "quarter")

    start_on = Date.from_iso8601!(answer["start_on"])

    assert doc |> Floki.find("[data-role='movers-basis']") |> text() ==
             "View Everything · Quarter: close #{Format.date(start_on)} to #{Format.date(today)}" <>
               " · in EUR, from stored closes and bookings"

    {:ok, view, _html} = live(conn, "/?period=decade")
    doc = loaded(view, "1y")
    assert_card_is_the_api(doc, "1y")

    {:ok, view, _html} = live(conn, "/?period=1d")
    doc = loaded(view, "day")
    answer = assert_card_is_the_api(doc, "day")

    assert doc |> Floki.find("[data-role='movers-basis']") |> text() ==
             "View Everything · Day: since each security's previous close, the dates at the row" <>
               "; contribution on #{Format.date(Date.from_iso8601!(answer["contribution"]["from"]))}" <>
               " · in EUR"
  end

  # User story (ADR-0061 §9; board 04 ④; DESIGN.md → the privacy mode):
  # As the operator with the privacy mode on,
  # I want the card to keep its percentages and its order and hide every
  # amount,
  # so that the glance stays useful on a screen others can see.
  #
  # Acceptance criteria:
  # - The price returns read as without the mode.
  # - Every contribution is the app's mask, no digit of it on the page; its
  #   sign colour and its bar's width stay.
  # - The count lines read as without the mode.
  test "the privacy mode hides the amounts and keeps the order, the bars and the percentages",
       %{conn: conn} do
    seed!()

    {:ok, view, _html} =
      conn |> put_preference_cookie("portfolixir_privacy", "on") |> live("/?period=1m")

    doc = loaded(view, "month")
    answer = api("/api/v1/movers?window=month")

    rows = Floki.find(doc, "[data-role='movers-return'] [data-role='movers-row']")
    entries = answer["price_return"]["highest"] ++ answer["price_return"]["lowest"]

    assert Enum.map(rows, &(&1 |> Floki.find("[data-role='movers-figure']") |> text())) ==
             Enum.map(entries, &percent(&1["return"]))

    rows = Floki.find(doc, "[data-role='movers-contribution'] [data-role='movers-row']")
    entries = answer["contribution"]["highest"] ++ answer["contribution"]["lowest"]
    assert length(rows) == length(entries)

    largest =
      entries |> Enum.map(&Decimal.abs(Decimal.new(&1["contribution"]))) |> Enum.max(Decimal)

    for {row, entry} <- Enum.zip(rows, entries) do
      assert row_name(row) == entry["security"]["name"]
      [figure] = Floki.find(row, "[data-role='movers-figure']")
      assert Floki.find(figure, ".pf-mask") != []
      refute text(figure) =~ ~r/\d/

      contribution = Decimal.new(entry["contribution"])
      fills = Floki.find(row, ".drift-bar__fill")

      case Format.displayed_sign(contribution, 2) do
        :zero ->
          assert attribute(figure, "class") in [nil, ""]
          assert fills == []

        sign ->
          assert attribute(figure, "class") =~ "is-#{sign}"

          width =
            contribution
            |> Decimal.abs()
            |> Decimal.div(largest)
            |> Decimal.mult(45)
            |> Decimal.round(1)
            |> Decimal.to_string(:normal)

          assert [fill] = fills
          assert attribute(fill, "style") == "width: #{width}%"
      end
    end

    assert contribution_counts(doc) == [
             "1 position not valued on any day of the period",
             "1 position without a contribution in the period"
           ]
  end

  # User story (board 04 ⑤, the states):
  # As the operator whose default view holds nothing yet,
  # I want the card to keep its frame and say so in one sentence,
  # so that an empty list is not mistaken for a quiet market.
  #
  # Acceptance criteria:
  # - With a default view that holds no depot, the card shows its period
  #   tag and „No holdings in this view.“, no list and no link to Wealth, as the
  #   API's answer for that view holds nothing.
  # - While the card's read runs it shows its block skeleton, marked busy,
  #   under its head.
  test "an empty view keeps the frame and says so; a loading card is busy", %{conn: conn} do
    seed!()

    {:ok, empty} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic Empty View", include_all: false})

    :ok = set_default_view(empty.id)

    first = conn |> get("/") |> html_response(200) |> Floki.parse_document!()
    assert [_tag] = Floki.find(first, "#dashboard-movers [data-role='widget-period']")

    assert [skeleton] = Floki.find(first, "#dashboard-movers [data-role='movers-skeleton']")
    assert attribute(skeleton, "aria-busy") == "true"

    {:ok, view, _html} = live(conn, "/?period=1w")
    doc = loaded(view, "week")

    answer = api("/api/v1/views/#{empty.id}/movers?window=week")
    assert answer["price_return"]["answered"] == 0
    assert answer["contribution"]["answered"] == 0

    assert doc |> Floki.find("[data-role='movers-empty']") |> text() ==
             "No holdings in this view."

    assert Floki.find(doc, "[data-role='movers-row']") == []
    assert Floki.find(doc, "[data-role='movers-wealth-link']") == []

    assert doc |> Floki.find("#dashboard-movers [data-role='widget-period']") |> text() ==
             "follows · 1W → Week"
  end

  # User story (board 04, the German labels):
  # As the operator reading the app in German,
  # I want the card in German, its period as board 05 names it,
  # so that the card reads like the rest of the Overview.
  #
  # Acceptance criteria:
  # - „Tops und Flops“, „folgt · 1W“ (at 3M „folgt · 3M → Quartal“, the
  #   window it reads), „Kursrendite“ and „Beitrag“, each with „Höchste“
  #   and „Niedrigste“, „verkauft“, and „In Vermögen ansehen →“.
  test "the card reads in German", %{conn: conn} do
    seed!()

    {:ok, view, _html} =
      conn |> put_preference_cookie("portfolixir_locale", "de") |> live("/?period=1w")

    doc = loaded(view, "week")

    assert doc |> Floki.find("#movers-title") |> text() == "Tops und Flops"

    assert doc |> Floki.find("#dashboard-movers [data-role='widget-period']") |> text() ==
             "folgt · 1W → Woche"

    assert doc |> Floki.find("[data-role='movers-return'] h3") |> text() == "Kursrendite"
    assert doc |> Floki.find("[data-role='movers-contribution'] h3") |> text() == "Beitrag"

    assert doc |> Floki.find("[data-role='movers-return'] h4") |> Enum.map(&text/1) ==
             ["Höchste", "Niedrigste"]

    assert doc |> Floki.find("[data-role='movers-sold']") |> text() == "verkauft"

    assert doc |> Floki.find("[data-role='movers-wealth-link']") |> text() ==
             "In Vermögen ansehen →"

    view
    |> element("[data-role='dashboard-period'] button[data-period='3m']")
    |> render_click()

    doc = loaded(view, "quarter")

    assert doc |> Floki.find("#dashboard-movers [data-role='widget-period']") |> text() ==
             "folgt · 3M → Quartal"
  end

  # User story (board 04, the states; #1351's clamped failure note):
  # As the operator landing on the Overview while the card's read fails,
  # I want the card to say so in a problem note and keep its frame,
  # so that an empty card is never mistaken for a quiet market.
  #
  # Acceptance criteria:
  # - A read that fails renders „Couldn't load the tops and flops.“ as a
  #   clamped problem note under its head, and the page stays up.
  test "a read that fails shows the card's clamped problem note", %{conn: conn} do
    seed!()

    # Every full row read of the cash accounts fails (the trades card's
    # failure test does the same), inside the test's own transaction.
    Repo.query!(
      "ALTER TABLE cash_accounts RENAME COLUMN liquidity_role TO liquidity_role_unreadable"
    )

    capture_log(fn ->
      {:ok, view, _html} = live(conn, "/")
      render_async(view)

      assert has_element?(
               view,
               "#dashboard-movers #movers-error.data-note--problem.data-note--clamped .data-note__text",
               "Couldn't load the tops and flops."
             )

      assert has_element?(view, "#dashboard-movers [data-role='widget-period']")
      assert Process.alive?(view.pid)
    end)
  end

  # User story (Sprint 30 closing act, correctness lens, finding 2; #1081's
  # rule, D-3, as the wealth card's sentence keeps it):
  # As the operator following „View in Wealth →“ from the card, I want the
  # card to say when Wealth is scoped to another view than the one it ranks,
  # so that I do not compare two scopes' contributions and wonder why they
  # differ — without the Overview making a view choice for me.
  #
  # Acceptance criteria:
  # - The link is `/portfolio?from=…&to=…`; no `view=` (a link does not
  #   change the view Wealth remembers), and following it keeps Wealth on
  #   its remembered view.
  # - With Wealth remembering „Synthetic Chosen View“ and the card on
  #   Everything, one sentence reads "Wealth is currently scoped to the view
  #   “Synthetic Chosen View”; this card shows “Everything”." (German
  #   "Vermögen ist gerade auf die Ansicht „Synthetic Chosen View“
  #   eingegrenzt; diese Karte zeigt „Alles“."), both names in `<bdi>`.
  # - Where Wealth's view is the card's, no sentence (the test above).
  test "the card names Wealth's other view, and its link names none", %{conn: conn} do
    seed!()

    {:ok, chosen} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic Chosen View", include_all: false})

    # No default view: the card reads Everything. Wealth remembers the
    # explicit choice of another view.
    conn = put_preference_cookie(conn, "portfolixir_view", Integer.to_string(chosen.id))

    {:ok, view, _html} = live(conn, "/?period=1m")
    doc = loaded(view, "month")
    assert doc |> Floki.find("[data-role='movers-basis']") |> text() =~ "View Everything"

    assert wealth_view(doc) ==
             "Wealth is currently scoped to the view “Synthetic Chosen View”; " <>
               "this card shows “Everything”."

    assert doc |> Floki.find("[data-role='movers-wealth-view'] bdi") |> Enum.map(&text/1) ==
             ["Synthetic Chosen View", "Everything"]

    refute has_element?(view, "a[href*='view=']")
    [link] = Floki.find(doc, "[data-role='movers-wealth-link']")
    refute attribute(link, "href") =~ "view="

    {:ok, wealth, _html} = live(conn, attribute(link, "href"))
    assert :sys.get_state(wealth.pid).socket.assigns.active_view_id == chosen.id

    {:ok, view, _html} = live(get(conn, "/?locale=de"), "/?locale=de&period=1m")
    doc = loaded(view, "month")

    assert wealth_view(doc) ==
             "Vermögen ist gerade auf die Ansicht „Synthetic Chosen View“ eingegrenzt; " <>
               "diese Karte zeigt „Alles“."
  end

  # The same with the card on a default view: Wealth remembering an explicit
  # Everything is named; Wealth on the default view (no choice remembered)
  # is not.
  test "the card names Wealth's Everything beside its default view", %{conn: conn} do
    seed!()

    {:ok, default} =
      Buckets.create_view(Actor.owner_ui(), %{name: "Synthetic Default View", include_all: true})

    :ok = set_default_view(default.id)

    {:ok, view, _html} = live(conn, "/?period=1m")
    doc = loaded(view, "month")

    assert doc |> Floki.find("[data-role='movers-basis']") |> text() =~
             "View Synthetic Default View"

    assert Floki.find(doc, "[data-role='movers-wealth-view']") == []

    conn = put_preference_cookie(conn, "portfolixir_view", "total")
    {:ok, view, _html} = live(conn, "/?period=1m")
    doc = loaded(view, "month")

    assert wealth_view(doc) ==
             "Wealth is currently scoped to the view “Everything”; " <>
               "this card shows “Synthetic Default View”."

    [link] = Floki.find(doc, "[data-role='movers-wealth-link']")
    refute attribute(link, "href") =~ "view="

    {:ok, wealth, _html} = live(conn, attribute(link, "href"))
    assert :sys.get_state(wealth.pid).socket.assigns.active_view_id == nil
  end

  # User story (the Overview's polish list #1358, decided: keep ADR-0061
  # §4's rule; Sprint 31 D3):
  # As the operator whose fund had no price for days of the window,
  # I want its gain shown in „Höchste“ with the mark that it counted zero on
  # those days,
  # so that I read the gain as made of days at zero, not hidden.
  #
  # Acceptance criteria:
  # - A fund delivered before the year and first priced in its last two
  #   days stands in „Höchste“ under „Beitrag“, its row marked with its days
  #   at zero, as GET /api/v1/movers?window=1y counts them.
  test "a gain on days at zero stands in the highest, marked", %{conn: conn} do
    today = Clock.today()
    world = base_world(name: "Mark Card", cash_name: "Giro", depot_name: "Depot")
    late = create_security!(name: "Synthetic Late Price Fund", ticker: "SLP")
    deliver_untraded!(world, late, "1", date: Date.add(today, -400))
    put_quotes!(late, [{Date.add(today, -1), "40"}, {today, "41"}])

    {:ok, view, _html} = live(conn, "/")
    doc = loaded(view, "1y")

    [row] =
      Floki.find(
        doc,
        "[data-role='movers-contribution'] [data-half='highest'] [data-role='movers-row']"
      )

    assert row_name(row) == "Synthetic Late Price Fund"
    [entry] = api("/api/v1/movers?window=1y")["contribution"]["highest"]
    assert entry["unvalued_days"] > 0

    assert row |> Floki.find("[data-role='movers-unvalued-mark']") |> text() ==
             "#{entry["unvalued_days"]} days at zero"
  end

  defp set_default_view(id), do: Settings.set_default_view(Actor.owner_ui(), id)
end
