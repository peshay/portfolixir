defmodule PortfolixirWeb.PrivacyModeRoutesTest do
  # The privacy mode's backstop beside the browser walk (fix round of the
  # Sprint 26 closing act, P3): every live route of the router, and every
  # view a page links in place (Cash flow's facets, "After the sale"'s
  # comparison modes, a security's detail tabs), renders with the mode on,
  # on its first (HTTP) render and its connected one, and its text names no
  # amount or quantity. Two pages crashed in the mode unseen, because the
  # walk read the re-joined page: this test runs in the test job, needs no
  # browser, and fails on a crash with the address that crashed. The walk
  # (test/browser/privacy_leak_test.exs) stays the authority on what a
  # browser shows: CSS, scripts, attributes, the charts' payloads.
  #
  # The world is synthetic: a sale with closes over its spans and buys from
  # its proceeds, a flagged benchmark, a classification and predictions.
  # async: false: "After the sale" and the predictions read every row.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures
  import PortfolixirWeb.PreferenceCookieHelpers

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Predictions

  # Figures that stay in the mode where a decimal comma alone would read as
  # an amount, as the walk lists them: Risk's metric cards are percentages
  # and ratios of returns; the predictions' calibration report holds Brier
  # scores, sharpness and probability bands, ratios of probabilities; the
  # journal's stored ratios (a probability, a weight, an exchange rate) read
  # as stored, a raw decimal in a table cell.
  @plain_selectors [
    "[data-role^='risk-metric-']",
    "#prediction-calibration",
    "[data-role='prediction-bands']",
    "[data-role='prediction-groups']",
    "[data-figure='ratio']"
  ]

  # A page's views are many but finite; this bounds a link that would
  # generate new addresses forever.
  @max_addresses 250

  # --- Sprint 28 S6 lens begin ---
  # Wealth's single value line over the Max window, which opens at zero.
  @zero_start "/portfolio?level=total&period=max"
  # --- Sprint 28 S6 lens end ---

  setup do
    world = base_world(name: "Privacy Routes")

    # --- Sprint 28 S6 lens begin ---
    # A window that opens at zero (the S6 lens of the closing act): the
    # world's first booking is a buy three days before the money that pays
    # it, so the value is 0 on the first day of the Max window, and the
    # value line's percent axis must not read the amounts as percentages.
    zero_start = create_security!(name: "Synthetic Zero Start Fund", ticker: "SZS")
    put_quotes!(zero_start, [{~D[2024-12-30], "100"}, {~D[2025-06-30], "104"}])
    buy!(world, zero_start, quantity: "10", price: "100", date: ~D[2024-12-30])
    # --- Sprint 28 S6 lens end ---

    deposit!(world, "20000", ~D[2025-01-02])

    sold = create_security!(name: "Synthetic Masked Fund", ticker: "SMF")

    put_quotes!(sold, [
      {~D[2025-01-10], "95"},
      {~D[2025-01-15], "100"},
      {~D[2025-02-14], "110"},
      {~D[2025-04-15], "120"},
      {~D[2026-01-15], "90"}
    ])

    buy!(world, sold, quantity: "20", price: "95.00", date: ~D[2025-01-10])

    sell!(world, sold,
      quantity: "10",
      price: "101.50",
      fees: "1.50",
      taxes: "10.00",
      date: ~D[2025-01-15]
    )

    next = create_security!(name: "Synthetic Next Fund", ticker: "SNX")

    put_quotes!(next, [
      {~D[2025-01-20], "100"},
      {~D[2025-02-14], "105"},
      {~D[2025-04-15], "110"},
      {~D[2026-01-15], "120"}
    ])

    buy!(world, next, quantity: "8", price: "100", fees: "2.00", date: ~D[2025-01-20])

    # A sale of delivered shares, with no matched buy: Cash flow → Trades
    # lists it apart, with its quantity.
    gift = create_security!(name: "Synthetic Delivered Fund", ticker: "SDF")
    put_quotes!(gift, [{~D[2025-03-03], "50"}])
    deliver_untraded!(world, gift, "6", date: ~D[2025-03-01])
    sell!(world, gift, quantity: "6", price: "50.00", date: ~D[2025-03-03])

    # Two bonds priced on two scales, one each way, so a bond's Overview
    # shows its block and its two-scales note (Sprint 27 closing act,
    # browser job: the walk saw both draw a hidden figure as its text, on a
    # bond this world did not hold).
    forward = bond!("Synthetic Forward Bond 2031", "2.5")
    buy!(world, forward, quantity: "1000", price: "0.985", date: ~D[2025-01-20])
    put_quotes!(forward, [{~D[2025-01-20], "98.50"}, {~D[2026-01-15], "97.25"}])

    reverse = bond!("Synthetic Reverse Bond 2029", "1.5")
    buy!(world, reverse, quantity: "10", price: "98.50", date: ~D[2025-01-20])
    put_quotes!(reverse, [{~D[2025-01-20], "0.9820"}, {~D[2026-01-15], "0.9850"}])

    {:ok, bench} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Masked Index",
        currency_code: "EUR",
        asset_class: "etf",
        is_benchmark: true
      })

    put_quotes!(bench, [
      {~D[2025-01-15], "200"},
      {~D[2025-02-14], "204"},
      {~D[2025-04-15], "210"},
      {~D[2026-01-15], "220"}
    ])

    {:ok, tree} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Synthetic Strategy"})

    # A category holding one fund, so Wealth's stacked chart (I23) has a
    # category to drill into; the other fund stays unclassified.
    {:ok, core} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: tree.id,
        name: "Synthetic Core"
      })

    {:ok, _} = Classifications.assign_security(Actor.owner_ui(), next.id, tree.id, core.id)

    # --- Sprint 28 S6 begin ---
    # A band that changes sign inside the 1Y window (#1426; #1433, D-A2): a
    # buy booked two days before the money that pays it overdraws the cash,
    # so every stacked level draws the cash's part below zero.
    overdraw = create_security!(name: "Synthetic Overdraw Fund", ticker: "SOF")
    overdrawn_on = Date.add(Clock.today(), -50)
    put_quotes!(overdraw, [{overdrawn_on, "100"}])
    buy!(world, overdraw, quantity: "200", price: "100", date: overdrawn_on)
    deposit!(world, "5000", Date.add(overdrawn_on, 2))
    # --- Sprint 28 S6 end ---

    made = DateTime.new!(~D[2025-01-15], ~T[12:00:00.000000], "Etc/UTC")

    {:ok, _resolved} =
      Predictions.create_prediction(
        Actor.api_token_rw("routes-agent"),
        %{
          "security_id" => sold.id,
          "direction" => "outperform",
          "probability" => "0.70",
          "benchmark" => "security:#{bench.id}",
          "resolves_on" => "2025-04-15",
          "model" => "model-synthetic-1"
        },
        now: made
      )

    {:ok, _open} =
      Predictions.create_prediction(Actor.owner_ui(), %{
        "security_id" => next.id,
        "direction" => "underperform",
        "probability" => "0.65",
        "benchmark" => "rate:0.03",
        "resolves_on" => Date.to_iso8601(Date.add(Clock.today(), 60))
      })

    %{sold: sold, next: next, tree: tree, core: core, bonds: [forward, reverse]}
  end

  defp bond!(name, coupon) do
    {:ok, bond} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: "EUR",
        asset_class: "bond",
        coupon_rate: coupon,
        coupon_frequency: "annual",
        maturity_date: ~D[2031-06-15],
        face_value: "1000"
      })

    bond
  end

  defp masked_conn do
    build_conn()
    |> put_preference_cookie("portfolixir_privacy", "on")
    |> put_preference_cookie("portfolixir_locale", "de")
  end

  # User story (P3, fix round of the closing act):
  # As the owner who trusts the privacy mode's gate,
  # I want every page and every view a page links in place rendered with
  # the mode on in the test job,
  # so that a page that crashes in the mode fails a test instead of passing
  # the walk unread.
  #
  # Acceptance criteria:
  # - Every live route of the router is opened with the mode on: its HTTP
  #   render answers below 400 and its connected render does not crash.
  # - From each page, its in-place views are opened the same way: Cash
  #   flow's facets, "After the sale"'s four comparison modes, a security's
  #   detail tabs, any link to the same path that names a tab, and Wealth's
  #   stacked chart (I23; Sprint 27 plan D-8, carry-forward 2): its bar's
  #   levels and sorts and a category drilled into, opened from the value
  #   series' category stack. Since #1433 (D-A2) the stack keeps its shape
  #   in the mode, so each level is walked, the filter (a category, the
  #   unassigned rest) at each level, and a band that changes sign; since
  #   FR-57 (Sprint 28 S4) the TTWROR series' lines at each level and under
  #   a filter, reached from its own bar.
  # - No page's text names an amount or a quantity, and none draws a hidden
  #   figure as its stand-in text instead of the bar.
  test "every page and every in-place view renders with the privacy mode on and names no amount",
       ctx do
    start = shell_paths(ctx)
    visited = walk(start, MapSet.new(start), [])

    # Each kind of view was reached, so the walk did not pass by reading less.
    for expected <- [
          "/cashflow?tab=realized",
          "/cashflow?tab=realized&hindsight=reinvestment",
          "/securities/#{ctx.sold.id}?tab=trades&hindsight=rate",
          "/securities/#{ctx.sold.id}?tab=predictions",
          "/predictions",
          "/journal",
          "/portfolio?level=category",
          "/portfolio?level=security",
          "/portfolio?level=security&category=#{ctx.core.id}",
          "/portfolio?level=category&sort=change",
          # --- Sprint 28 S6 begin ---
          "/portfolio?level=total",
          "/portfolio?level=category&category=#{ctx.core.id}",
          "/portfolio?level=total&category=#{ctx.core.id}",
          "/portfolio?level=category&category=unclassified",
          # --- Sprint 28 S6 end ---
          # --- Sprint 28 S4 begin ---
          # FR-57: the TTWROR series keeps the bar, each band a line.
          "/portfolio?level=category&scale=ttwror",
          "/portfolio?level=security&scale=ttwror",
          "/portfolio?level=category&category=#{ctx.core.id}&scale=ttwror",
          # --- Sprint 28 S4 end ---
          # --- Sprint 28 S6 lens begin ---
          @zero_start
          # --- Sprint 28 S6 lens end ---
        ] do
      assert expected in visited, "the walk never opened #{expected}"
    end

    # --- Sprint 28 S6 begin ---
    # The cash band changes sign in the window, so the walk read its part
    # below zero at the stacked levels.
    for address <- ["/portfolio?level=category", "/portfolio?level=security"] do
      {:ok, view, _html} = live(masked_conn(), address)
      render_async(view, 5_000)
      assert has_element?(view, "path.stack-band--negative[data-band='cash']"), address
      assert has_element?(view, "path.stack-band[data-band='cash']:not([data-part])"), address
    end

    # --- Sprint 28 S6 end ---

    # --- Sprint 28 S6 lens begin ---
    # The value line of a window that opens at zero reads in percent of its
    # first day above zero: no tick of the masked axis is a tick of the
    # plain one, an amount printed as a percentage.
    {:ok, %{series: [day_one | _rest]}} = Performance.for_view(nil, period: "max")
    assert Decimal.equal?(day_one.value, 0), "the Max window opens at #{inspect(day_one)}"

    plain = @zero_start |> zero_start_render(build_conn()) |> value_ticks()
    masked = @zero_start |> zero_start_render(masked_conn()) |> value_ticks()
    assert length(plain) == 5 and length(masked) == 5, inspect({plain, masked})
    assert Enum.all?(masked, &String.ends_with?(&1, "%")), inspect(masked)

    for tick <- masked, amount <- plain do
      refute abs(tick_number(tick) - tick_number(amount)) < 1,
             "#{@zero_start} prints the amount #{amount} as #{tick}"
    end

    # --- Sprint 28 S6 lens end ---
  end

  # --- Sprint 28 S6 lens begin ---
  defp zero_start_render(path, conn) do
    {:ok, view, _html} = live(put_preference_cookie(conn, "portfolixir_locale", "de"), path)
    html = render_async(view, 5_000)
    assert html =~ ~s(data-chart-mode="value"), "#{path} draws no value line"
    html
  end

  defp value_ticks(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#performance-figure .chart-axis-y")
    |> Enum.map(&String.trim(LazyHTML.text(&1)))
  end

  # A German tick as a number: "20.500", "-1.025,00", "+26,0%".
  defp tick_number(tick) do
    {number, _rest} =
      tick
      |> String.replace(~r/[.%+]/, "")
      |> String.replace(",", ".")
      |> Float.parse()

    number
  end

  # --- Sprint 28 S6 lens end ---

  defp shell_paths(ctx) do
    PortfolixirWeb.Router.__routes__()
    |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
    |> Enum.map(& &1.path)
    |> Enum.uniq()
    |> Enum.flat_map(fn
      "/securities/:id" ->
        Enum.map([ctx.sold, ctx.next | ctx.bonds], &"/securities/#{&1.id}")

      "/classifications/:id" ->
        ["/classifications/#{ctx.tree.id}"]

      # The value series' category stack, from which the walk follows the
      # bar's links: the stack shows only in the value series.
      "/portfolio" ->
        # --- Sprint 28 S6 lens: the Max window, which opens at zero ---
        ["/portfolio", "/portfolio?level=category", @zero_start]

      path ->
        if String.contains?(path, ":"), do: flunk("no address for #{path}"), else: [path]
    end)
  end

  defp walk([], _seen, visited), do: Enum.reverse(visited)

  defp walk([path | rest], seen, visited) do
    html = open!(path)
    refute_amounts(path, html)

    fresh =
      html
      |> views(path)
      |> Enum.reject(&MapSet.member?(seen, &1))
      |> Enum.uniq()

    seen = Enum.reduce(fresh, seen, &MapSet.put(&2, &1))
    assert MapSet.size(seen) <= @max_addresses, "the walk keeps finding new addresses"
    walk(rest ++ fresh, seen, [path | visited])
  end

  # The page's HTTP render and its connected render; the connected one's
  # markup is returned.
  defp open!(path) do
    conn = crash_named(path, "HTTP", fn -> get(masked_conn(), path) end)

    assert conn.status < 400,
           "#{path} answered #{conn.status} with the privacy mode on"

    crash_named(path, "connected", fn ->
      case live(masked_conn(), path) do
        {:ok, view, _html} -> render_async(view, 5_000)
        {:error, {kind, %{to: to}}} -> flunk("#{path} answered a #{kind} to #{to}")
      end
    end)
  end

  defp crash_named(path, render, fun) do
    fun.()
  rescue
    error in [ExUnit.AssertionError] ->
      reraise error, __STACKTRACE__

    error ->
      flunk(
        "#{path} crashed on its #{render} render with the privacy mode on: " <>
          Exception.message(error)
      )
  catch
    :exit, reason ->
      flunk(
        "#{path} crashed on its #{render} render with the privacy mode on: " <>
          inspect(reason, limit: 6)
      )
  end

  # The addresses of the views a page links in place: a link to the same
  # path naming a tab, a hindsight mode or a stack level (I23), the facets,
  # the comparison modes, and a detail tab's button as the address that
  # opens it.
  defp views(html, path) do
    doc = LazyHTML.from_document(html)
    %URI{path: own} = URI.parse(path)

    links =
      doc
      |> LazyHTML.query("main a[href]")
      |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))
      |> Enum.filter(fn href ->
        uri = URI.parse(href)
        uri.host == nil and uri.path == own and in_place?(uri.query)
      end)

    tabs =
      doc
      |> LazyHTML.query("[data-tab-level='2'] [role='tab'][phx-value-tab]")
      |> Enum.flat_map(&LazyHTML.attribute(&1, "phx-value-tab"))
      |> Enum.map(&"#{own}?tab=#{&1}")

    links ++ tabs
  end

  defp in_place?(nil), do: false
  defp in_place?(query), do: query =~ ~r/(^|&)(tab|hindsight|level)=/

  # The walk's text scan (test/browser/privacy_leak.js), on the server's
  # markup, text node by text node: an amount in German form outside a
  # percentage, percentage points, a ratio or a JSON array of ids, a
  # quantity its unit names, a raw stored decimal in a table cell ("123.45",
  # the journal's stored values; closing act of Sprint 26, finding S2),
  # and the stand-in text of a hidden figure where the bar belongs. Scripts,
  # styles and templates are not text; the plain selectors' figures stay.
  @amount ~r/(?<![\d.,])(?<!×)(?<!× )(?<!x)(?<!x )(?<!\[)([+\-−]?\d{1,3}(?:\.\d{3})*,\d+)(?![\d,])(?!\s*(?:%|pp\b|Pp\b|PP\b|Prozentpunkte|Jahre|years|MB\b|-Fache|times\b))/u
  @quantity ~r/(?<![\d.,])(\d[\d.,]*)\s*(Stück|shares?|units?)(?![\p{L}])/u

  # A raw decimal as stored ("123.45", "1234.5", "-0.5"): a point and one to
  # four digits, not part of a word, a time, a German date ("06.11.2026",
  # "06.11."), a version ("0.1.14") or a German amount ("1.234,56"), and not
  # a percentage. What reads as no decimal is left out: three digits after
  # at most three are a German thousands group ("1.250", a count), a month
  # and a year are a German month ("11.2025").
  @raw ~r/(?<![\p{L}\d.,:\/_])([+\-−]?\d+\.\d{1,4})(?![\d.])(?!,\d)(?!\s*(?:%|pp\b|Pp\b|PP\b|Prozentpunkte))/u
  @not_decimal [~r/^[+\-−]?\d{1,3}\.\d{3}$/u, ~r/^(0?[1-9]|1[0-2])\.(19|20)\d\d$/u]

  defp refute_amounts(path, html) do
    tree = readable_tree(html)
    nodes = collect_text(tree)

    raw =
      tree
      |> Floki.find("td, th")
      |> Enum.flat_map(&(&1 |> collect_text() |> Enum.join(" ") |> raw_decimals()))

    hits =
      Enum.flat_map(nodes, fn text ->
        Enum.map(Regex.scan(@amount, text), fn [_, amount] -> amount end) ++
          Enum.map(Regex.scan(@quantity, text), fn [_, n, unit] -> n <> " " <> unit end)
      end) ++ raw

    assert hits == [], "#{path} names #{inspect(Enum.take(hits, 8))} with the privacy mode on"

    refute Enum.any?(nodes, &String.contains?(&1, PortfolixirWeb.PrivacyMode.text())),
           "#{path} draws a hidden figure as its text, not as the bar"
  end

  defp raw_decimals(text) do
    for [_, decimal] <- Regex.scan(@raw, text),
        not Enum.any?(@not_decimal, &Regex.match?(&1, decimal)),
        do: decimal
  end

  # The page as the walk reads it, without scripts, styles, templates and
  # the plain selectors' elements.
  defp readable_tree(html) do
    tree = Floki.parse_document!(html)

    Enum.reduce(["script", "style", "template" | @plain_selectors], tree, fn selector, acc ->
      Floki.filter_out(acc, selector)
    end)
  end

  defp collect_text(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &collect_text/1)
  defp collect_text(text) when is_binary(text), do: [text]
  defp collect_text({_tag, _attributes, children}), do: collect_text(children)
  defp collect_text(_other), do: []
end
