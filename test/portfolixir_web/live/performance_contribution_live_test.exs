defmodule PortfolixirWeb.PerformanceContributionLiveTest do
  # FR-41, ADR-0051 §12: the human view of the contribution, pick A of the
  # board `mockups/fr41-2026-09-25/01-contribution-surface` — a table in
  # Wealth → Holdings → Performance, directly under the chart, sharing the
  # section's period control and the page's view.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [
      base_world: 1,
      buy!: 3,
      create_security!: 1,
      deposit!: 3,
      deposit!: 4,
      put_quotes!: 2,
      sell!: 3
    ]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance.Contribution
  alias PortfolixirWeb.Format
  alias PortfolixirWeb.Portfolio.ContributionTable

  setup do
    Classifications.ensure_builtins()
    :ok
  end

  # -- synthetic worlds -----------------------------------------------------------
  #
  # Invented names and figures only; every date is relative to the page's own
  # today (`Clock.today/0`), so the default 1Y period covers the bookings.

  defp today, do: Clock.today()
  defp days_ago(days), do: Date.add(today(), -days)

  defp cash!(world, type, amount, date, opts \\ []) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: Keyword.get(opts, :security_id),
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  # Three positions and two remainder lines, all inside the default 1Y window
  # (the walk starts in it, so every start value is 0):
  #
  #   Alpha  10 @ 100, fees 5; quoted 120 today      →  1200 − 1000 − 5 = +195
  #   Gamma   5 @ 200, fees 2; sold 5 @ 220, fees 3  →  1100 − 1000 − 5 =  +95
  #   Beta   20 @ 50; dividend 30; quoted 45 today   →  900 − 1000 + 30 =  −70
  #   interest 12, a standalone fee 7                                  +12, −7
  #
  # The period's money result is 10225 − 0 − 10000 = +225.
  defp sum_world do
    world = base_world(name: "Contribution World", cash_name: "Giro", depot_name: "Depot")
    alpha = create_security!(name: "Alpha Industrial AG", ticker: "ALPH")
    beta = create_security!(name: "Beta Utilities SE", ticker: "BETA")
    gamma = create_security!(name: "Gamma Robotics NV", ticker: "GAMR")
    d0 = days_ago(40)

    deposit!(world, "10000", d0)
    buy!(world, alpha, quantity: "10", price: "100", fees: "5", date: d0)
    buy!(world, beta, quantity: "20", price: "50", date: d0)
    buy!(world, gamma, quantity: "5", price: "200", fees: "2", date: Date.add(d0, 5))
    cash!(world, "dividend", "30", Date.add(d0, 10), security_id: beta.id)
    cash!(world, "interest", "12", Date.add(d0, 15))
    cash!(world, "fee", "7", Date.add(d0, 16))
    sell!(world, gamma, quantity: "5", price: "220", fees: "3", date: Date.add(d0, 20))

    put_quotes!(alpha, [{d0, "100"}, {today(), "120"}])
    put_quotes!(beta, [{d0, "50"}, {today(), "45"}])
    put_quotes!(gamma, [{Date.add(d0, 5), "200"}, {Date.add(d0, 20), "220"}])

    %{world: world, alpha: alpha, beta: beta, gamma: gamma}
  end

  # Twelve positions, each one unit bought at 100: ten gain 1..10, two lose
  # 40 and 50. The ten largest by absolute amount leave out the +1 and the +2;
  # the sum still covers all twelve: 55 − 90 = −35.
  defp twelve_world do
    world = base_world(name: "Twelve World", cash_name: "Giro", depot_name: "Depot")
    d0 = days_ago(30)
    deposit!(world, "2000", d0)

    gainers =
      for k <- 1..10 do
        security = create_security!(name: "Position #{pad(k)}", ticker: "P#{pad(k)}")
        buy!(world, security, quantity: "1", price: "100", date: d0)
        put_quotes!(security, [{d0, "100"}, {today(), Integer.to_string(100 + k)}])
        {k, security}
      end

    losers =
      for {name, close} <- [{"Loser Forty", "60"}, {"Loser Fifty", "50"}] do
        security = create_security!(name: name, ticker: nil)
        buy!(world, security, quantity: "1", price: "100", date: d0)
        put_quotes!(security, [{d0, "100"}, {today(), close}])
        security
      end

    %{world: world, gainers: Map.new(gainers), losers: losers}
  end

  defp pad(k), do: k |> Integer.to_string() |> String.pad_leading(2, "0")

  # -- reading the page -------------------------------------------------------------

  # The element's text, one space between text nodes: the test DOM drops the
  # whitespace-only nodes a browser renders as the gap between two cells.
  defp text_of(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.split()
    |> Enum.join(" ")
  end

  defp row_ids(view, selector \\ "#contribution-table tr[data-role='contribution-row']") do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.flat_map(&Floki.attribute(&1, "data-security-id"))
    |> Enum.map(&String.to_integer/1)
  end

  defp row(security), do: "#contribution-table tr[data-security-id='#{security.id}']"

  # Every load the page starts, and every load a landing one starts in turn:
  # a result that finds the other read on older data reloads it (FR-41
  # review round), so one `render_async/1` can leave a second load running.
  defp settle(view), do: Enum.each(1..4, fn _round -> render_async(view) end)

  # User story (FR-41, ADR-0051 §1–§3 and §12, board pick A):
  # As a local portfolio maintainer reading my period result on Wealth,
  # I want a table directly under the performance chart that says which
  # position made how much of it, with what no position owns listed apart,
  # so that the "+x EUR in the period" beside the TTWROR has an address.
  #
  # Acceptance criteria:
  # - Under the chart of Wealth → Holdings → Performance a contribution table
  #   renders, one row per position, sorted largest contribution first; a
  #   position sold inside the period is a row, held at neither end.
  # - Each row carries start value, flows, income, costs, end value and the
  #   contribution, the contribution signed and in its sign colour, with a
  #   decorative diverging bar (aria-hidden) scaled to the largest absolute
  #   contribution: the largest fills 45 % of the track.
  # - The remainder lines — interest, standalone fees and taxes, the currency
  #   effect on cash (balances and trades' settlement differences) — follow
  #   under their own head, each with its own figure.
  # - The sum row equals the money figure of the section's badge, to the cent.
  # - The table is not on the Allocation & targets tab (never in the tree).
  test "the contribution table renders under the chart and its sum is the badge's figure",
       %{conn: conn} do
    %{alpha: alpha, beta: beta, gamma: gamma} = sum_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    section = view |> element("#portfolio-performance") |> render()
    {figure_at, _} = :binary.match(section, ~s(id="performance-figure"))
    {table_at, _} = :binary.match(section, ~s(id="performance-contribution"))
    assert figure_at < table_at

    assert has_element?(view, "#performance-contribution h3", "Contribution by position")

    assert text_of(view, "#performance-contribution [data-role='contribution-scope']") ==
             "1Y · View Everything · sorted by contribution"

    assert row_ids(view) == [alpha.id, gamma.id, beta.id]

    assert text_of(view, row(alpha)) =~
             "Alpha Industrial AG not held at the start 0.00 +1,000.00 0.00 5.00 1,200.00 +195.00"

    assert text_of(view, row(gamma)) =~
             "Gamma Robotics NV held at neither end 0.00 -100.00 0.00 5.00 0.00 +95.00"

    assert text_of(view, row(beta)) =~
             "Beta Utilities SE not held at the start 0.00 +1,000.00 +30.00 0.00 900.00 -70.00"

    # The figure carries the sign and the colour; the bar is decoration.
    assert has_element?(view, "#{row(alpha)} td.num span.is-positive", "+195.00")
    assert has_element?(view, "#{row(beta)} td.num span.is-negative", "-70.00")

    assert has_element?(
             view,
             ~s(#{row(alpha)} .drift-bar[aria-hidden="true"] .drift-bar__fill.is-over[style="width: 45.0%"])
           )

    # 70 / 195 × 45 = 16.2
    assert has_element?(
             view,
             ~s(#{row(beta)} .drift-bar[aria-hidden="true"] .drift-bar__fill.is-under[style="width: 16.2%"])
           )

    assert has_element?(
             view,
             "#contribution-table [data-role='contribution-rest-head']",
             "Not attributed to a position"
           )

    assert text_of(view, "#contribution-table [data-line='interest']") =~ "Interest"
    assert text_of(view, "#contribution-table [data-line='interest']") =~ "+12.00"

    assert text_of(view, "#contribution-table [data-line='standalone_fees_and_taxes']") =~
             "Standalone fees and taxes"

    assert text_of(view, "#contribution-table [data-line='standalone_fees_and_taxes']") =~
             "-7.00"

    currency_line = text_of(view, "#contribution-table [data-line='cash_currency_effect']")
    assert currency_line =~ "Currency effect on cash"
    assert currency_line =~ "settlement differences"
    assert currency_line =~ "0.00"

    # The sum row: every column summed over the positions, the contribution
    # column over the positions and the remainder lines.
    assert text_of(view, "#contribution-table tr[data-role='contribution-sum']") =~
             "Sum = result in the period 0.00 +1,900.00 +30.00 10.00 2,100.00 +225.00 EUR"

    sum = text_of(view, "[data-role='contribution-sum-figure']")
    badge = text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")
    assert sum == "+225.00 EUR"
    assert sum == badge

    # Never in the classifications tree, nor anywhere on the Allocation tab.
    {:ok, allocation, _html} = live(conn, "/portfolio?tab=allocation")
    render_async(allocation)
    refute has_element?(allocation, "#performance-contribution")
  end

  # User story (FR-41, ADR-0051 §12):
  # As a local portfolio maintainer with many positions,
  # I want the table to show the ten that moved the most and let me open
  # the rest,
  # so that the table stays readable while its sum never leaves one out.
  #
  # Acceptance criteria:
  # - With more than ten positions the table shows the ten largest by
  #   absolute amount, in the table's order, and a "Show all N" control,
  #   saying how many smaller ones are hidden and that the sum includes them.
  # - The sum row covers every position, shown or not, and equals the badge.
  # - "Show all N" opens every row; the control then offers the ten largest
  #   again.
  test "more than ten positions show the ten largest and a show-all control",
       %{conn: conn} do
    %{gainers: gainers, losers: [forty, fifty]} = twelve_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    shown = for k <- 10..3//-1, do: gainers[k].id
    assert row_ids(view) == shown ++ [forty.id, fifty.id]
    refute has_element?(view, row(gainers[1]))
    refute has_element?(view, row(gainers[2]))

    assert text_of(view, "#contribution-table [data-role='contribution-more']") =~
             "2 smaller positions are not shown; the sum includes them."

    assert has_element?(
             view,
             ~s(#contribution-table button[data-role="contribution-show-all"][aria-expanded="false"]),
             "Show all 12"
           )

    assert text_of(view, "[data-role='contribution-sum-figure']") == "-35.00 EUR"

    assert text_of(view, "[data-role='contribution-sum-figure']") ==
             text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")

    # The phone rows show the same ten.
    assert length(row_ids(view, "#contribution-phone-rows li[data-role='contribution-row']")) ==
             10

    view
    |> element(~s(#contribution-table button[data-role="contribution-show-all"]))
    |> render_click()

    all = for k <- 10..1//-1, do: gainers[k].id
    assert row_ids(view) == all ++ [forty.id, fifty.id]

    assert has_element?(
             view,
             ~s(#contribution-table button[data-role="contribution-show-all"][aria-expanded="true"]),
             "Show the ten largest"
           )

    assert text_of(view, "[data-role='contribution-sum-figure']") == "-35.00 EUR"
  end

  # User story (Sprint 18 PR β design critic, R3; board
  # ux-review-2026-10-03/01-contribution-repairs; UX-DR6, the Accessibility
  # Floor):
  # As a local portfolio maintainer on a touch screen or a keyboard,
  # I want the "Show all N" control to be a target I can hit and a focus I
  # can see,
  # so that opening the hidden positions is not a 20 px aim or a guess.
  #
  # Acceptance criteria:
  # - In the table and in the phone rows the control carries its own class,
  #   `contribution-show-all`, beside `.link-button`.
  # - The stylesheet gives that control — not every `.link-button` — 44 px
  #   under a coarse pointer and the 2 px accent ring on `:focus-visible`,
  #   the treatment a rule's name on Risk has.
  test "the show-all control meets the touch floor and draws the accent ring", %{conn: conn} do
    twelve_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(
             view,
             ~s(#contribution-table button.link-button.contribution-show-all[data-role="contribution-show-all"])
           )

    assert has_element?(
             view,
             ~s(#contribution-phone-rows button.link-button.contribution-show-all[data-role="contribution-show-all"])
           )

    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/\.link-button\.contribution-show-all:focus-visible\s*\{\s*outline:\s*2px solid var\(--color-accent\);\s*outline-offset:\s*2px;/

    assert css =~
             ~r/@media \(pointer: coarse\) \{\s*\.link-button\.contribution-show-all \{\s*min-height: 44px;/

    refute css =~ ~r/@media \(pointer: coarse\) \{\s*\.link-button \{/
  end

  # User story (FR-41, ADR-0051 §10, UX-DR25):
  # As a local portfolio maintainer whose history has a position without a
  # price,
  # I want the table to say which positions counted zero, and on how many
  # days,
  # so that I know where the figure is incomplete while it still adds up.
  #
  # Acceptance criteria:
  # - An attention data note under the table states the count and names
  #   each affected position with its days and the reason.
  # - Each affected row carries a marker in words; an unaffected row none.
  # - The position stays in the table and in the sum.
  test "unvalued positions are named in a note and marked on their rows", %{conn: conn} do
    world = base_world(name: "Gap World", cash_name: "Giro", depot_name: "Depot")
    alpha = create_security!(name: "Alpha Industrial AG", ticker: "ALPH")
    ghost = create_security!(name: "Ghost Mining Corp", ticker: "GHST")
    d0 = days_ago(20)

    deposit!(world, "1000", d0)
    buy!(world, alpha, quantity: "5", price: "100", date: d0)
    put_quotes!(alpha, [{d0, "100"}, {today(), "110"}])

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: world.depot.id,
        security_id: ghost.id,
        type: "inbound_delivery",
        date: d0,
        quantity: "5",
        currency_code: "EUR"
      })

    {:ok, expected} = Contribution.for_view(nil, period: "1y")
    days = Enum.find(expected.positions, &(&1.security_id == ghost.id)).unvalued_days
    assert days > 0

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(view, row(ghost))

    assert text_of(view, "#{row(ghost)} [data-role='contribution-unvalued-mark']") ==
             "#{days} days at zero"

    refute has_element?(view, "#{row(alpha)} [data-role='contribution-unvalued-mark']")

    note = text_of(view, "#performance-contribution .data-note--attention")
    assert note =~ "One position counted zero on some days of the period:"
    assert note =~ "Ghost Mining Corp (#{days} days, no price stored)"
    assert note =~ "It stays in the sum, as in the result above."

    # Every balance is in EUR: no cash account is named or marked (#1055).
    refute note =~ "cash account"

    refute has_element?(
             view,
             "#contribution-table tr[data-line='cash_currency_effect'] .contribution-unvalued-mark"
           )

    assert text_of(view, "[data-role='contribution-sum-figure']") ==
             text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")
  end

  # A EUR portfolio whose "Tagesgeld CHF" received 2000 CHF 60 days ago,
  # while CHF's first stored rate (EUR/CHF 0.8) is from 42 days ago: the walk
  # counts the balance zero for 18 days, then at 2500 EUR (board J2's data).
  defp franc_world do
    world = base_world(name: "Franc World", cash_name: "Giro", depot_name: "Depot")

    {:ok, franc} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Tagesgeld CHF",
        currency_code: "CHF"
      })

    deposit!(world, "1000", days_ago(80))
    deposit!(%{portfolio: world.portfolio, cash: franc}, "2000", days_ago(60), currency: "CHF")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "CHF",
          date: days_ago(42),
          rate: "0.8",
          source: "manual"
        }
      ])

    %{world: world, franc: franc}
  end

  # User story (#1055, ADR-0051 §10, board J2 A):
  # As a local portfolio maintainer reading German, whose CHF day-money
  # account was filled before the instance held a CHF rate,
  # I want the contribution note to name the account with its CHF balance,
  # its days and the day its first rate came, and the currency-effect row to
  # carry its marker,
  # so that the jump in "Währungseffekt auf Bargeld" and in the badge reads
  # as a deposit that became visible, not as a currency gain.
  #
  # Acceptance criteria:
  # - The attention note under the table reads "Ein Verrechnungskonto
  #   zählte an einigen Tagen des Zeitraums null: Tagesgeld CHF (2.000,00
  #   CHF, 18 Tage, kein Wechselkurs gespeichert). Mit dem ersten Kurs am
  #   <dd.mm.yyyy> kam sein ganzer Saldo in den „Währungseffekt auf Bargeld“
  #   — das ist kein Währungsgewinn.", the figures in the house formats.
  # - The "Währungseffekt auf Bargeld" row carries the marker "Tagesgeld CHF:
  #   18 Tage null"; the other lines carry none; the phone remainder row
  #   carries it too.
  # - Every figure is unchanged: the row holds +2.500,00 and the sum row is
  #   the badge's money figure.
  test "a cash account held before its first rate is named in German, board J2 A",
       %{conn: conn} do
    %{franc: franc} = franc_world()
    first_rate = Format.date(days_ago(42), "de")

    conn = get(conn, "/portfolio?locale=de")
    {:ok, view, _html} = live(conn, "/portfolio?locale=de")
    render_async(view)

    note =
      view
      |> text_of("#performance-contribution [data-role='contribution-unvalued']")
      |> String.replace(" .", ".")

    assert note ==
             "Achtung Ein Verrechnungskonto zählte an einigen Tagen des Zeitraums null: " <>
               "Tagesgeld CHF (2.000,00 CHF, 18 Tage, kein Wechselkurs gespeichert). Mit dem " <>
               "ersten Kurs am #{first_rate} kam sein ganzer Saldo in den „Währungseffekt auf " <>
               "Bargeld“ — das ist kein Währungsgewinn."

    currency_row = "#contribution-table tr[data-line='cash_currency_effect']"

    assert text_of(view, "#{currency_row} .contribution-unvalued-mark") ==
             "Tagesgeld CHF: 18 Tage null"

    assert has_element?(
             view,
             "#{currency_row} [data-role='contribution-unvalued-mark'][data-cash-account-id='#{franc.id}']"
           )

    for line <- ["interest", "standalone_fees_and_taxes"] do
      refute has_element?(
               view,
               "#contribution-table tr[data-line='#{line}'] .contribution-unvalued-mark"
             )
    end

    assert text_of(view, "#{currency_row} td:last-child") == "+2.500,00"

    assert text_of(view, "#contribution-phone-rows [data-role='contribution-phone-rest']") ==
             "Keiner Position zugeordnet Zinsen 0,00 · Gebühren/Steuern 0,00 · " <>
               "Währung +2.500,00 · Tagesgeld CHF: 18 Tage null +2.500,00"

    assert text_of(view, "[data-role='contribution-sum-figure']") == "+2.500,00 EUR"

    assert text_of(view, "[data-role='contribution-sum-figure']") ==
             text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")
  end

  # User story (FR-41, ADR-0051 §4):
  # As a local portfolio maintainer picking a period with nothing in it,
  # I want the section to say so in a sentence,
  # so that an empty period never reads as a table of zeros.
  #
  # Acceptance criteria:
  # - A custom range before the history shows the empty-state sentence and
  #   no table, no remainder lines and no sum row.
  # - The scope line names the period and the view but no order: nothing is
  #   listed to be sorted (design critic R7a, board
  #   ux-review-2026-10-03/01-contribution-repairs).
  test "an empty window is the empty-state sentence, never a table of zeros", %{conn: conn} do
    sum_world()

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)
    assert has_element?(view, "#contribution-table")

    view
    |> element(~s(form[data-role="period-range"]))
    |> render_submit(%{
      "from" => Date.to_iso8601(days_ago(400)),
      "to" => Date.to_iso8601(days_ago(300))
    })

    render_async(view)

    assert has_element?(
             view,
             "#performance-contribution p.empty-state[data-role='contribution-empty']",
             "Nothing to break down in this period"
           )

    refute has_element?(view, "#contribution-table")
    refute has_element?(view, "#contribution-phone-rows")

    scope = text_of(view, "#performance-contribution [data-role='contribution-scope']")
    assert scope =~ ~r/ · View Everything$/
    refute scope =~ "sorted by contribution"
  end

  # User story (Sprint 18 PR β design critic, R7b):
  # As a local portfolio maintainer using a screen reader,
  # I want the contribution table's placeholder to say it is busy,
  # so that "computing" is announced as a region still loading, not as its
  # content.
  #
  # Acceptance criteria:
  # - While the contribution computes, the block's skeleton is a status
  #   region with `aria-busy="true"`; the table, once there, carries neither.
  test "the skeleton is a busy status region" do
    html =
      render_component(&ContributionTable.table/1,
        contribution: nil,
        period_label: "1Y",
        view_name: "Everything"
      )

    assert [skeleton] =
             html
             |> Floki.parse_fragment!()
             |> Floki.find("[data-role='contribution-skeleton']")

    assert Floki.attribute(skeleton, "role") == ["status"]
    assert Floki.attribute(skeleton, "aria-busy") == ["true"]
  end

  # User story (FR-41, ADR-0051 §4, board pick A):
  # As a local portfolio maintainer switching the performance period,
  # I want the contribution table to follow the period control,
  # so that its sum keeps answering the badge above it.
  #
  # Acceptance criteria:
  # - The table opens on the section's period (1Y) and recomputes when the
  #   period changes; its scope line names the period.
  # - Under each period the sum row equals the badge's money figure.
  test "a period change updates the table with the badge", %{conn: conn} do
    world = base_world(name: "Long World", cash_name: "Giro", depot_name: "Depot")
    delta = create_security!(name: "Delta Shipping ASA", ticker: "DLTA")

    deposit!(world, "1000", days_ago(500))
    buy!(world, delta, quantity: "10", price: "100", date: days_ago(500))
    put_quotes!(delta, [{days_ago(500), "100"}, {days_ago(400), "150"}, {today(), "150"}])

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    # 1Y: held at both ends at 1500, so it contributed nothing.
    assert text_of(view, row(delta)) =~ "Delta Shipping ASA 1,500.00 0.00 0.00 0.00 1,500.00 0.00"
    assert text_of(view, "[data-role='contribution-sum-figure']") == "0.00 EUR"

    # R1 (board ux-review-2026-10-03): a zero money figure takes the badge's
    # flat colour from its own class, whatever the TTWROR beside it.
    assert has_element?(view, "[data-role='period-badge-money'].is-flat", "0.00 EUR")

    view |> element("button[phx-value-period='max']") |> render_click()
    render_async(view)

    assert text_of(view, "#performance-contribution [data-role='contribution-scope']") =~
             "Max · "

    assert text_of(view, row(delta)) =~
             "Delta Shipping ASA not held at the start 0.00 +1,000.00 0.00 0.00 1,500.00 +500.00"

    assert text_of(view, "[data-role='contribution-sum-figure']") == "+500.00 EUR"

    assert text_of(view, "[data-role='contribution-sum-figure']") ==
             text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")
  end

  # User story (FR-41 review round, ADR-0051 §12, ADR-0032 §6):
  # As a local portfolio maintainer whose data changes while the page is open
  # (a second tab, an agent's booking, an import, the background quote sync),
  # I want a period switch to keep the table's sum on the badge's figure,
  # so that the two never answer from different data.
  #
  # Acceptance criteria:
  # - After a booking lands behind the open page, a period switch shows a sum
  #   row equal to the badge's money figure, both reading the new booking.
  # - After the page's view is deleted in another tab, a period switch shows
  #   the Everything table under the Everything badge, the sum equal to it.
  test "data that changes behind the open page: a period switch keeps the sum on the badge",
       %{conn: conn} do
    world = base_world(name: "Moving World", cash_name: "Giro", depot_name: "Depot")
    delta = create_security!(name: "Delta Shipping ASA", ticker: "DLTA")

    deposit!(world, "1000", days_ago(500))
    buy!(world, delta, quantity: "10", price: "100", date: days_ago(500))
    put_quotes!(delta, [{days_ago(500), "100"}, {days_ago(400), "150"}, {today(), "150"}])

    {:ok, view, _html} = live(conn, "/portfolio")
    settle(view)

    # Booked behind the open page, as an agent or a second tab would.
    cash!(world, "interest", "50", days_ago(10))

    view |> element("button[phx-value-period='max']") |> render_click()
    settle(view)

    assert text_of(view, "[data-role='contribution-sum-figure']") == "+550.00 EUR"

    assert text_of(view, "[data-role='contribution-sum-figure']") ==
             text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")
  end

  test "a view deleted behind the open page: the period switch reads Everything on both",
       %{conn: conn} do
    world = base_world(name: "Shrinking World", cash_name: "Giro A", depot_name: "Depot A")

    other =
      world.portfolio
      |> Portfolixir.WorldFixtures.add_depot(cash_name: "Giro B", depot_name: "Depot B")
      |> Map.put(:portfolio, world.portfolio)

    inside = create_security!(name: "Inside Holdings AG", ticker: "INSD")
    outside = create_security!(name: "Outside Holdings AG", ticker: "OUTS")
    d0 = days_ago(30)

    deposit!(world, "1000", d0)
    deposit!(other, "1000", d0)
    buy!(world, inside, quantity: "5", price: "100", date: d0)
    buy!(other, outside, quantity: "5", price: "100", date: d0)
    put_quotes!(inside, [{d0, "100"}, {today(), "104"}])
    put_quotes!(outside, [{d0, "100"}, {today(), "90"}])

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Inside bucket"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])
    {:ok, scoped} = Buckets.create_view(Actor.owner_ui(), %{name: "Inside", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), scoped, [bucket.id], [])

    conn = get(conn, "/portfolio?view=#{scoped.id}")
    {:ok, view, _html} = live(conn, "/portfolio?view=#{scoped.id}")
    settle(view)

    assert text_of(view, "[data-role='contribution-sum-figure']") == "+20.00 EUR"

    {:ok, _deleted} = Buckets.delete_view(Actor.owner_ui(), scoped)

    view |> element("button[phx-value-period='max']") |> render_click()
    settle(view)

    assert row_ids(view) == [inside.id, outside.id]
    assert text_of(view, "[data-role='contribution-sum-figure']") == "-30.00 EUR"

    assert text_of(view, "[data-role='contribution-sum-figure']") ==
             text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")
  end

  # User story (FR-41, ADR-0051 §6):
  # As a local portfolio maintainer working in a view,
  # I want the contribution table scoped to the page's view,
  # so that it breaks down the same result the badge shows for that view.
  #
  # Acceptance criteria:
  # - With a view picked, only the positions inside it are rows, and the sum
  #   row equals the view's badge figure; its scope line names the view.
  # - A dividend credited inside the view for a position outside it is that
  #   security's income: an ordinary row, held at neither end (ADR-0051 §6).
  # - Without a view (Everything) every position is a row.
  test "the table follows the page's view", %{conn: conn} do
    world = base_world(name: "Scoped World", cash_name: "Giro A", depot_name: "Depot A")

    other =
      world.portfolio
      |> Portfolixir.WorldFixtures.add_depot(cash_name: "Giro B", depot_name: "Depot B")
      |> Map.put(:portfolio, world.portfolio)

    inside = create_security!(name: "Inside Holdings AG", ticker: "INSD")
    outside = create_security!(name: "Outside Holdings AG", ticker: "OUTS")
    d0 = days_ago(30)

    deposit!(world, "1000", d0)
    deposit!(other, "1000", d0)
    buy!(world, inside, quantity: "5", price: "100", date: d0)
    buy!(other, outside, quantity: "5", price: "100", date: d0)
    put_quotes!(inside, [{d0, "100"}, {today(), "104"}])
    put_quotes!(outside, [{d0, "100"}, {today(), "90"}])
    # Credited to Giro A, inside the view, for the position in Depot B.
    cash!(world, "dividend", "6", Date.add(d0, 10), security_id: outside.id)

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Inside bucket"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])
    {:ok, scoped} = Buckets.create_view(Actor.owner_ui(), %{name: "Inside", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), scoped, [bucket.id], [])

    {:ok, everything, _html} = live(conn, "/portfolio")
    render_async(everything)
    assert row_ids(everything) == [inside.id, outside.id]

    conn = get(conn, "/portfolio?view=#{scoped.id}")
    {:ok, view, _html} = live(conn, "/portfolio?view=#{scoped.id}")
    render_async(view)

    assert row_ids(view) == [inside.id, outside.id]

    assert text_of(view, row(outside)) ==
             "Outside Holdings AG held at neither end 0.00 0.00 +6.00 0.00 0.00 +6.00"

    assert text_of(view, "#performance-contribution [data-role='contribution-scope']") =~
             "View Inside"

    assert text_of(view, "[data-role='contribution-sum-figure']") == "+26.00 EUR"

    assert text_of(view, "[data-role='contribution-sum-figure']") ==
             text_of(view, "[data-role='period-badge'] [data-role='period-badge-money']")
  end

  # User story (Sprint 18 PR β design critic, R1; board
  # ux-review-2026-10-03/01-contribution-repairs; DESIGN.md → Colors,
  # "Semantic color applies wherever a sign exists"):
  # As a local portfolio maintainer whose return and money result point in
  # different directions,
  # I want the badge's money figure in the colour of its own sign,
  # so that a loss never reads green above the table's red sum of the same
  # figure.
  #
  # Acceptance criteria:
  # - With a positive TTWROR and a negative money result, the badge's money
  #   span carries `is-negative`, as the contribution table's sum figure
  #   does; the TTWROR keeps its own colour.
  # - A zero money result takes the badge's flat colour, never the TTWROR's.
  test "the badge's money figure carries its own sign's colour", %{conn: conn} do
    # A doubling on 100, then a deposit of 10,000 bought at the top and a 5 %
    # fall: the time-weighted return is about +90 %, the money result
    # 51 × 190 − 0 − 10,100 = −410.
    world = base_world(name: "Timing World", cash_name: "Giro", depot_name: "Depot")
    echo = create_security!(name: "Echo Rail AG", ticker: "ECHR")
    d0 = days_ago(100)

    deposit!(world, "100", d0)
    buy!(world, echo, quantity: "1", price: "100", date: d0)
    deposit!(world, "10000", Date.add(d0, 31))
    buy!(world, echo, quantity: "50", price: "200", date: Date.add(d0, 31))

    put_quotes!(echo, [
      {d0, "100"},
      {Date.add(d0, 30), "200"},
      {Date.add(d0, 31), "200"},
      {today(), "190"}
    ])

    {:ok, view, _html} = live(conn, "/portfolio")
    render_async(view)

    assert has_element?(view, "[data-role='period-badge'].is-positive")

    assert has_element?(
             view,
             "[data-role='period-badge'] [data-role='period-badge-money'].is-negative",
             "-410.00 EUR"
           )

    assert has_element?(view, "[data-role='contribution-sum-figure'] span.is-negative", "-410.00")

    css = File.read!("priv/static/app.css")
    assert css =~ ~r/\.perf-badge \.is-flat\s*\{[^}]*color:\s*var\(--color-text-muted\)/
  end

  # User story (FR-41, board pick A, UX-DR27):
  # As a local portfolio maintainer reading German on a phone,
  # I want the table in German, with the house number formats, and as
  # two-line rows under 560 px,
  # so that it reads like every other surface of the app.
  #
  # Acceptance criteria:
  # - The labels render in German: the heading, the columns, the remainder
  #   head and lines, the sum row.
  # - Numbers carry the German separators and their sign.
  # - Beside the table, two-line phone rows carry each shown position, the
  #   remainder and the sum; the stylesheet shows them under 560 px and hides
  #   the table there.
  test "German labels, house formats and the two-line phone rows", %{conn: conn} do
    %{alpha: alpha} = sum_world()

    conn = get(conn, "/portfolio?locale=de")
    {:ok, view, _html} = live(conn, "/portfolio?locale=de")
    render_async(view)

    assert has_element?(view, "#performance-contribution h3", "Beitrag je Position")

    assert text_of(view, "#performance-contribution [data-role='contribution-scope']") ==
             "1J · Ansicht Alles · sortiert nach Beitrag"

    header = text_of(view, "#contribution-table thead")

    assert header ==
             "Wertpapier Anfangswert Zu-/Abflüsse Erträge Kosten Endwert Beitrag"

    assert text_of(view, row(alpha)) =~ "zu Beginn nicht im Bestand"
    assert text_of(view, row(alpha)) =~ "+1.000,00"
    assert text_of(view, row(alpha)) =~ "+195,00"

    assert has_element?(
             view,
             "#contribution-table [data-role='contribution-rest-head']",
             "Keiner Position zugeordnet"
           )

    assert text_of(view, "#contribution-table [data-line='cash_currency_effect']") =~
             "Währungseffekt auf Bargeld"

    assert text_of(view, "#contribution-table [data-line='cash_currency_effect']") =~
             "Abrechnungsdifferenzen"

    assert text_of(view, "#contribution-table tr[data-role='contribution-sum']") =~
             "Summe = Ergebnis im Zeitraum"

    assert text_of(view, "[data-role='contribution-sum-figure']") == "+225,00 EUR"

    # The phone rows: three positions, the remainder and the sum.
    assert length(row_ids(view, "#contribution-phone-rows li[data-role='contribution-row']")) ==
             3

    assert text_of(view, "#contribution-phone-rows li[data-security-id='#{alpha.id}']") ==
             "Alpha Industrial AG zu Beginn nicht im Bestand · Zufluss 1.000,00 +195,00"

    assert text_of(view, "#contribution-phone-rows [data-role='contribution-phone-rest']") ==
             "Keiner Position zugeordnet Zinsen +12,00 · Gebühren/Steuern -7,00 · Währung 0,00 +5,00"

    assert text_of(view, "#contribution-phone-rows [data-role='contribution-phone-sum']") ==
             "Summe = Ergebnis im Zeitraum Positionen und Restposten +225,00 EUR"
  end

  # User story (FR-41, board pick A; DESIGN.md → the contribution table):
  # As a local portfolio maintainer reading the contribution table,
  # I want its anatomy to be rules of the stylesheet,
  # so that the bar, the remainder band, the sum row and the phone rows
  # look the same wherever the table renders.
  #
  # Acceptance criteria:
  # - The drift bar rides under its figure, right-aligned, at a fixed width.
  # - The remainder lines sit on the muted band; the sum row is bold under a
  #   strong rule.
  # - The table is a reading table: it fits its wrapper, the figures never
  #   wrap.
  # - The phone row has two children, body and figures; the 560 px block
  #   hides the table's wrapper.
  # - The unvalued marker, on a position row and on the currency-effect line
  #   alike (#1055, board J2 A), is one rule: the warning colour inside a
  #   dashed pill, the word the channel.
  test "the stylesheet carries the pick's rules" do
    css = File.read!("priv/static/app.css")

    assert css =~
             ~r/\.contribution-unvalued-mark\s*\{[^}]*border:\s*1px dashed var\(--color-warning\);[^}]*color:\s*var\(--color-warning\);/

    assert css =~
             ~r/\.contribution-table td\.contribution-table__figure \.drift-bar\s*\{[^}]*display:\s*block;[^}]*width:\s*110px;[^}]*margin:\s*5px 0 0 auto/

    # R2 (board ux-review-2026-10-03): the band outranks the zebra stripe
    # `.data-table tbody tr:nth-child(even) td` (0,2,3) at 0,3,3, so the head
    # row and every remainder line sit on it whatever the row count.
    assert css =~
             ~r/\.data-table\.contribution-table tbody tr\.contribution-table__rest-head td,\s*\.data-table\.contribution-table tbody tr\.contribution-table__rest td\s*\{\s*background:\s*var\(--color-bg-muted\);/

    refute css =~
             ~r/\.contribution-table tr\.contribution-table__rest(-head)? td\s*\{[^}]*background/

    assert css =~
             ~r/\.contribution-table tr\.contribution-table__sum td\s*\{[^}]*font-weight:\s*700;[^}]*border-top:\s*2px solid var\(--color-border-strong\)/

    assert css =~ ~r/\.data-table-wrapper > \.contribution-table\s*\{[^}]*min-width:\s*0/

    assert css =~
             ~r/\.contribution-table td\.num,\s*\.contribution-table th\.num\s*\{[^}]*white-space:\s*nowrap/

    assert css =~ ~r/#contribution-phone-rows \.phone-row\s*\{[^}]*minmax\(0, 1fr\) auto/

    [phone_block] =
      Regex.run(~r/@media \(max-width: 560px\) \{\s*\/\* phone lists.*?\n\}/s, css)

    assert phone_block =~ "#contribution-table-wrap"
  end

  # User story (Sprint 18 PR β design critic, R4; board
  # ux-review-2026-10-03/01-contribution-repairs):
  # As a local portfolio maintainer reading German at tablet width,
  # I want a name and its sub-line to wrap between words,
  # so that "Fremdwährungskonten" never reads as "Fremdwährungsko" over "nten".
  #
  # Acceptance criteria:
  # - The name cell wraps with `overflow-wrap: break-word` and
  #   `hyphens: auto`, never `anywhere`, keeping its 14ch floor.
  # - The page names its language, so the browser hyphenates German as
  #   German.
  test "a name wraps between words, never mid-word", %{conn: conn} do
    css = File.read!("priv/static/app.css")

    [name_rule] =
      Regex.run(~r/\.contribution-table td\.contribution-table__name \{[^}]*\}/, css)

    assert name_rule =~ "min-width: 14ch;"
    assert name_rule =~ "overflow-wrap: break-word;"
    assert name_rule =~ "-webkit-hyphens: auto;"
    assert name_rule =~ ~r/[^-]hyphens: auto;/
    refute name_rule =~ "anywhere"

    assert conn |> get("/portfolio?locale=de") |> html_response(200) =~ ~s(<html lang="de")
  end

  # User story (Sprint 18 PR β design critic, R5; board
  # ux-review-2026-10-03/01-contribution-repairs; UX-DR27):
  # As a local portfolio maintainer reading the contribution on a phone,
  # I want the remainder row's name and figure on the same edges as every
  # other row's,
  # so that the right-aligned figures read as one column down to the sum.
  #
  # Acceptance criteria:
  # - The remainder row keeps its {colors.bg-muted} band, bled into the
  #   list's gutter by a negative inline margin equal to its inline padding,
  #   so its content sits where the other rows' content sits.
  test "under 560 px the remainder keeps the rows' edges" do
    css = File.read!("priv/static/app.css")

    [rest_rule] =
      Regex.run(~r/#contribution-phone-rows \.contribution-phone-rows__rest \{[^}]*\}/, css)

    assert rest_rule =~ "margin-inline: calc(-1 * var(--space-2));"
    assert rest_rule =~ "padding-inline: var(--space-2);"
    assert rest_rule =~ "background: var(--color-bg-muted);"
  end
end
