defmodule PortfolixirWeb.DisplayedDatesLiveTest do
  # Sprint 19 PR γ U3 (issues 1061 and 1087's Wealth half; board
  # ux-design-2026-10-04/05-dates-charts, its "Heute / Nachher" repairs and
  # the sweep its "found while drawing" 3 widened them to). UX-DR19 as
  # amended on 2026-10-03: a date the page only shows follows the page's
  # language through `Format.date`; inputs and `<time datetime>` keep ISO.
  # German pages, as the board draws them. Every name, figure and date is
  # invented; dates near today are relative to the host's calendar day.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quotes!: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios.Snapshots
  alias Portfolixir.Repo
  alias PortfolixirWeb.Format

  @iso ~r/\b\d{4}-\d{2}-\d{2}\b/

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp de(date), do: Format.date(date, "de")
  defp day(offset), do: Date.add(Clock.today(), offset)

  defp text(view, selector) do
    view |> element(selector) |> render() |> flat()
  end

  defp texts(view, selector) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(selector)
    |> Enum.map(&flat/1)
  end

  defp flat(html) when is_binary(html), do: html |> Floki.parse_fragment!() |> flat()

  defp flat(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp nordwind! do
    world = base_world(name: "Datum Depot", cash_name: "Girokonto", depot_name: "Depot 1")
    deposit!(world, "10000", ~D[2025-11-03])
    nordwind = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    buy!(world, nordwind, quantity: "10", price: "101.20", date: ~D[2026-03-02])
    %{world: world, nordwind: nordwind}
  end

  describe "the security detail (issue 1061)" do
    # User story (board 05, #1061 "Heute / Nachher"):
    # As a German-speaking operator reading a security,
    # I want its head, its Overview and its Transactions and Quotes tabs to
    # print their dates as DD.MM.YYYY,
    # so that "Letzter 112,40 (2026-09-30)" stops reading as the one
    # foreign line under a German title, and a date in a narrow column does
    # not break at its hyphen.
    #
    # Acceptance criteria:
    # - The head reads "Letzter 112,40 (<the quote's day, DD.MM.YYYY>)", and
    #   the Overview's latest price names the same day the same way.
    # - The Transactions tab's date column reads "02.03.2026".
    # - The Quotes table and its phone rows read every day DD.MM.YYYY.
    # - The manual-quotes note reads "vom <first> bis <last>" in the same
    #   form, each date a `<time>` whose `datetime` keeps ISO.
    test "the head, the Overview, the Transactions and Quotes tabs print German dates",
         %{conn: conn} do
      %{nordwind: nordwind} = nordwind!()
      put_quotes!(nordwind, [{day(-16), "106.10"}, {day(-15), "106.80"}, {day(-1), "112.40"}])

      {:ok, view, _html} = live(german(conn), "/securities/#{nordwind.id}")

      head = text(view, ".detail-pane-sub")
      assert head =~ "Letzter 112,40 (#{de(day(-1))})"
      refute head =~ @iso

      assert text(view, "[data-role='overview-latest-price']") =~ "(#{de(day(-1))})"

      {:ok, view, _html} = live(german(conn), "/securities/#{nordwind.id}?tab=transactions")

      assert texts(view, ".detail-transactions-table tbody tr td:first-child") == ["02.03.2026"]

      {:ok, view, _html} = live(german(conn), "/securities/#{nordwind.id}?tab=quotes")
      days = Enum.map([-1, -15, -16], &de(day(&1)))

      assert texts(view, "#quotes-table-wrapper tbody tr td:first-child") == days
      assert texts(view, "#quote-phone-rows .phone-row__name") == days

      note = view |> element("[data-role='manual-quotes-note']") |> render()
      assert flat(note) =~ "vom #{de(day(-16))} bis #{de(day(-1))}"
      assert note =~ ~s(<time datetime="#{Date.to_iso8601(day(-16))}">#{de(day(-16))}</time>)
      refute flat(note) =~ @iso
    end

    # User story (board 05, found while drawing 3 — the Termine tab):
    # As a German-speaking operator reading a security's calendar,
    # I want a day, a range and a month to read the way the rest of the page
    # reads its dates,
    # so that "2026-10" is not the one ISO month among German days.
    #
    # Acceptance criteria:
    # - A day reads DD.MM.YYYY, a window "DD.MM.YYYY – DD.MM.YYYY", a month
    #   MM.YYYY (`Format.month`), each in a `<time>` whose `datetime` keeps
    #   ISO.
    # - "Zuletzt geprüft" names its day DD.MM.YYYY.
    test "the Termine tab says a day, a window and a month in German", %{conn: conn} do
      security = create_security!(name: "Kestrel Reederei AG", ticker: "KRA")
      month = day(70) |> Date.beginning_of_month()

      for attrs <- [
            %{kind: "earnings", date: day(30), timing: "exact", checked_at: day(-2)},
            %{kind: "earnings", date: day(40), date_end: day(42), timing: "window"},
            %{kind: "earnings", date: month, timing: "month"}
          ] do
        {:ok, _event} =
          Events.create_event(
            Actor.owner_ui(),
            Map.merge(%{security_id: security.id, source_quality: "secondary_multi"}, attrs)
          )
      end

      {:ok, view, _html} = live(german(conn), "/securities/#{security.id}?tab=events")

      panel = view |> element("#detail-tab-panel-events") |> render()
      read = flat(panel)

      assert read =~ de(day(30))
      assert read =~ "#{de(day(40))} – #{de(day(42))}"
      assert read =~ Format.month(month, "de")
      assert read =~ "Zuletzt geprüft #{de(day(-2))}"
      refute read =~ ~r/\b\d{4}-\d{2}\b/

      assert panel =~ ~s(<time datetime="#{Date.to_iso8601(day(30))}">)
    end

    # User story (board 05, found while drawing 3 — the range chips and the
    # metric window):
    # As a German-speaking operator who zoomed the chart to a range,
    # I want the chip that names it and each metric's window to read their
    # days as DD.MM.YYYY,
    # so that the range I picked reads like every other date on the page,
    # while the fields I type into keep ISO.
    #
    # Acceptance criteria:
    # - The custom-range chip reads "<from> – <to>" in DD.MM.YYYY.
    # - The range's two fields keep their ISO values.
    # - Every metric cell's window reads "DD.MM.YYYY – DD.MM.YYYY" or says
    #   it measured none; none prints ISO.
    test "the custom-range chip and the metric windows read German days", %{conn: conn} do
      security = create_security!(name: "Halvorsen Shipping AS", ticker: "HSA")
      put_quotes!(security, for(offset <- -400..-1, do: {day(offset), "100"}))

      {:ok, view, _html} = live(german(conn), "/securities/#{security.id}?tab=chart")

      render_hook(view, "set_detail_custom_range", %{
        "from" => Date.to_iso8601(day(-300)),
        "to" => Date.to_iso8601(day(-10))
      })

      assert text(view, "[data-role='custom-range-chip']") ==
               "#{de(day(-300))} – #{de(day(-10))}"

      assert has_element?(view, "#detail-range-from[value='#{Date.to_iso8601(day(-300))}']")
      assert has_element?(view, "#detail-range-to[value='#{Date.to_iso8601(day(-10))}']")

      windows = texts(view, "#detail-metrics [data-role='metric-window']")
      assert windows != []
      assert Enum.any?(windows, &(&1 =~ ~r/^\d{2}\.\d{2}\.\d{4} – \d{2}\.\d{2}\.\d{4}$/))
      refute Enum.any?(windows, &(&1 =~ @iso))
    end

    # User story (board 05, found while drawing 3 — the list's date cells):
    # As a German-speaking operator who shows the latest price's date as a
    # column of the securities list,
    # I want its cells to read DD.MM.YYYY,
    # so that the list does not print the one ISO column.
    #
    # Acceptance criteria:
    # - The "Latest price date" cell reads the quote's day DD.MM.YYYY.
    test "the list's date column reads German days", %{conn: conn} do
      %{nordwind: nordwind} = nordwind!()
      put_quotes!(nordwind, [{day(-2), "111.00"}])

      {:ok, view, _html} = live(german(conn), "/securities")
      render_hook(view, "set_columns", %{"columns" => ["name", "latest_price_date"]})

      [row] =
        view
        |> render()
        |> Floki.parse_document!()
        |> Floki.find("#securities-table tbody tr")
        |> Enum.filter(&(flat(&1) =~ "Nordwind Industrie AG"))

      assert flat(row) =~ de(day(-2))
      refute flat(row) =~ @iso
    end
  end

  describe "Wealth (issue 1087's Wealth half)" do
    defp wealth_world! do
      Classifications.ensure_builtins()
      {:ok, _tree} = Classifications.create_classification(Actor.owner_ui(), %{name: "Strategie"})

      world = base_world(name: "Datum Depot", cash_name: "Girokonto", depot_name: "Depot 1")
      deposit!(world, "10000", day(-120))

      timber = create_security!(name: "Nordic Timber Holdings AB", ticker: "NTH")
      buy!(world, timber, quantity: "10", price: "48", date: day(-120))
      put_quotes!(timber, [{day(-120), "48"}, {day(-40), "52"}])

      # A Portfolio Performance typo, year 0219 for 2019: every writer
      # refuses it since E25 S4, so the row is history already stored —
      # written past the changeset, as the performance tests do.
      removal =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          type: "removal",
          date: ~D[2019-03-07],
          gross_amount: "30",
          currency_code: "EUR"
        })
        |> then(fn {:ok, tx} -> tx end)

      {:ok, {1, _}} =
        Repo.transaction(fn ->
          {type, _label} = Actor.to_columns(Actor.owner_ui())
          Repo.query!("SELECT set_config('portfolixir.journal_actor', $1, true)", [type])

          Transaction
          |> where(id: ^removal.id)
          |> Repo.update_all(set: [date: ~D[0219-03-07]])
        end)

      world
    end

    # User story (board 05, #1087 "Heute / Nachher"):
    # As a German-speaking operator reading Wealth's data quality and its
    # performance chart,
    # I want the notes and the basis line under the chart to print their
    # dates as DD.MM.YYYY,
    # so that "Nordic Timber Holdings AB (2026-08-29)" and "berechnet
    # 2026-10-04 00:09 UTC" stop reading as raw data in a German page.
    #
    # Acceptance criteria:
    # - The stale-quote note names the position with its price's day:
    #   "Nordic Timber Holdings AB (<DD.MM.YYYY>)".
    # - The suspect-dates note reads the year-0219 booking "07.03.0219".
    # - The basis line reads "<from> – <to> · berechnet DD.MM.YYYY HH:MM UTC".
    # - A per-month table under the chart names its months MM.YYYY.
    # - An applied custom range's chip reads "<from> – <to>" DD.MM.YYYY.
    test "the notes, the basis line, the month rows and the range chip read German dates",
         %{conn: conn} do
      wealth_world!()

      {:ok, view, _html} = live(german(conn), "/portfolio")
      render_async(view)

      assert text(view, ~s([data-role="dq-stale-priced"])) =~
               "Nordic Timber Holdings AB (#{de(day(-40))})"

      suspect = text(view, ~s([data-role="dq-suspect-dates"]))
      assert suspect =~ "(07.03.0219)"
      refute suspect =~ "0219-03-07"

      basis = text(view, ~s([data-role="performance-basis"]))

      assert basis =~
               ~r/^\d{2}\.\d{2}\.\d{4} – \d{2}\.\d{2}\.\d{4} · berechnet \d{2}\.\d{2}\.\d{4} \d{2}:\d{2} UTC$/

      refute basis =~ @iso

      months = texts(view, ~s([data-role="perf-summary-table"] tbody tr td:first-child))
      assert months != []
      assert Enum.all?(months, &(&1 =~ ~r/^\d{2}\.\d{4}$/))

      render_submit(view, "select_range", %{
        "from" => Date.to_iso8601(day(-90)),
        "to" => Date.to_iso8601(day(-1))
      })

      assert text(view, ~s([data-role="custom-period-chip"])) ==
               "#{de(day(-90))} – #{de(day(-1))}"
    end
  end

  describe "Wealth's period after a custom range (U3 review, finding 1)" do
    # User story (Sprint 19 U3 review):
    # As a German-speaking operator who picked a custom range on Wealth,
    # I want every place that names the period — the KPI heads, the badge
    # over the chart, the contribution table's scope — to read the range's
    # days as DD.MM.YYYY, as the range's own chip does,
    # so that one page does not name one period in two date forms.
    #
    # Acceptance criteria:
    # - After a custom range, the period badge, the TTWROR card and the
    #   contribution scope read "<from> – <to>" in DD.MM.YYYY, and none of
    #   them prints ISO.
    test "the KPI heads, the badge and the contribution scope name the range in German",
         %{conn: conn} do
      wealth_world!()

      {:ok, view, _html} = live(german(conn), "/portfolio")
      render_async(view)

      render_submit(view, "select_range", %{
        "from" => Date.to_iso8601(day(-90)),
        "to" => Date.to_iso8601(day(-1))
      })

      render_async(view)
      range = "#{de(day(-90))} – #{de(day(-1))}"

      for selector <- [
            ~s([data-role="period-badge"]),
            "#kpi-ttwror",
            ~s([data-role="contribution-scope"])
          ] do
        read = text(view, selector)
        assert read =~ range, "#{selector}: #{read}"
        refute read =~ @iso, "#{selector}: #{read}"
      end
    end
  end

  describe "the changed-since note (U3 review, finding 3)" do
    # User story (Sprint 19 U3 review):
    # As a German-speaking operator who narrowed a list to what changed
    # since a day,
    # I want the note that says so to name the day as DD.MM.YYYY,
    # so that "Geändert seit 2026-09-30 (UTC)" stops being the one ISO date
    # on the page; a full instant an agent's link carries is said as given.
    #
    # Acceptance criteria:
    # - On /transactions, the "7 Tage" chip's note reads the chip's day
    #   DD.MM.YYYY, followed by "(UTC)".
    # - On /securities?since=<day> the note reads the day DD.MM.YYYY.
    # - On /securities?since=<instant> the note reads the instant as given.
    test "the note names a day in German and an instant as given", %{conn: conn} do
      %{nordwind: _nordwind} = nordwind!()
      week_ago = Date.add(Date.utc_today(), -7)

      {:ok, view, _html} = live(german(conn), "/transactions")
      view |> element("#changed-since-chips-7d") |> render_click()

      note = text(view, "#transaction-since-note")
      assert note =~ "Geändert seit #{de(week_ago)} (UTC)"
      refute note =~ @iso

      since = Date.to_iso8601(day(-3))
      {:ok, view, _html} = live(german(conn), "/securities?since=#{since}")

      note = text(view, "#securities-since-note")
      assert note =~ "Geändert seit #{de(day(-3))} (UTC)"
      refute note =~ @iso

      {:ok, view, _html} = live(german(conn), "/securities?since=2026-09-30T12:00:00Z")
      assert text(view, "#securities-since-note") =~ "Geändert seit 2026-09-30T12:00:00Z (UTC)"
    end
  end

  describe "the structural check (U3 review, finding 5)" do
    # The text a reader sees: no script (the chart's JSON keeps ISO for its
    # hook) and no style; attributes (input values, datetimes) are not text.
    defp visible(html) do
      html
      |> Floki.parse_document!()
      |> Floki.filter_out("script")
      |> Floki.filter_out("style")
      |> Floki.text(sep: " ")
      |> String.replace(~r/\s+/, " ")
    end

    defp iso_hits(html),
      do: ~r/.{0,40}\b\d{4}-\d{2}-\d{2}\b.{0,20}/u |> Regex.scan(visible(html)) |> List.flatten()

    # User story (Sprint 19 U3 review):
    # As the maintainer keeping the date sweep swept,
    # I want one test to read the main German pages in the states an
    # operator puts them in — a custom range, a since chip, every tab of a
    # security — and find no ISO date in their visible text,
    # so that a raw `<%= date %>`, which the source scan cannot see, is
    # caught where it shows.
    #
    # Acceptance criteria:
    # - Wealth with a custom range applied, its Allocation tab, Cash flow,
    #   Transactions with the "7 Tage" chip, Securities with a since day,
    #   Accounts & depots, Tax, Risk and every detail tab of a held security
    #   with quotes, a booking, a research entry and a calendar fact print no
    #   `YYYY-MM-DD` in their visible text.
    test "no main German page prints an ISO date in its visible text", %{conn: conn} do
      world = wealth_world!()
      nordwind = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
      buy!(world, nordwind, quantity: "10", price: "101.20", date: day(-60))
      put_quotes!(nordwind, for(offset <- -60..-1//3, do: {day(offset), "110"}))

      {:ok, _note} =
        Portfolixir.Knowledge.append_note(Actor.owner_ui(), %{
          security_id: nordwind.id,
          author: "operator",
          kind: "evidence",
          body: "a synthetic finding",
          source_quality: "primary",
          as_of: day(-5)
        })

      {:ok, _event} =
        Events.create_event(Actor.owner_ui(), %{
          security_id: nordwind.id,
          kind: "earnings",
          date: day(20),
          timing: "exact",
          source_quality: "secondary_multi",
          checked_at: day(-1)
        })

      {:ok, view, _html} = live(german(conn), "/portfolio")
      render_async(view)

      render_submit(view, "select_range", %{
        "from" => Date.to_iso8601(day(-90)),
        "to" => Date.to_iso8601(day(-1))
      })

      render_async(view)
      states = [{"/portfolio (custom range)", render(view)}]

      {:ok, view, _html} = live(german(conn), "/transactions")
      view |> element("#changed-since-chips-7d") |> render_click()
      states = [{"/transactions (7 Tage)", render(view)} | states]

      pages =
        [
          "/portfolio?tab=allocation",
          "/cashflow",
          "/securities?since=#{Date.to_iso8601(day(-3))}"
        ] ++
          ["/portfolios", "/tax", "/risk"] ++
          for tab <-
                ~w(overview chart transactions trades quotes holdings classifications research events),
              do: "/securities/#{nordwind.id}?tab=#{tab}"

      states =
        Enum.reduce(pages, states, fn path, acc ->
          {:ok, view, _html} = live(german(conn), path)
          render_async(view)
          [{path, render(view)} | acc]
        end)

      hits = for {state, html} <- states, hit <- iso_hits(html), do: "#{state}: #{hit}"
      assert hits == [], Enum.join(hits, "\n")
    end
  end

  describe "the other surfaces the sweep reached" do
    # User story (Sprint 19 U3, the sweep):
    # As a German-speaking operator drilling into a year of income,
    # I want each payment's date in the year's table, and each position's
    # last payment, as DD.MM.YYYY,
    # so that the tables read their dates like the chart's own labels.
    #
    # Acceptance criteria:
    # - The drilled year's payments table reads "15.03.2025", not ISO.
    # - The positions table's last payment reads "15.03.2025", not ISO.
    test "the income year's payments and the last payment read German dates", %{conn: conn} do
      world = base_world(name: "Ertrag Depot", cash_name: "Girokonto", depot_name: "Depot 1")
      payer = create_security!(name: "Kestrel Versorger AG", ticker: "KVA")

      {:ok, _} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          security_id: payer.id,
          type: "dividend",
          date: ~D[2025-03-15],
          gross_amount: "80",
          currency_code: "EUR"
        })

      {:ok, view, _html} = live(german(conn), "/cashflow")

      positions = text(view, "#income-positions")
      assert positions =~ "15.03.2025"
      refute positions =~ @iso

      view |> element(".link-button[phx-value-year='2025']") |> render_click()

      table = text(view, ~s([data-role="income-payments-disclosure"]))
      assert table =~ "15.03.2025"
      refute table =~ @iso
    end

    # User story (Sprint 19 U3, the sweep):
    # As a German-speaking operator comparing a snapshot with today,
    # I want the snapshot list's as-of day and the comparison table's days
    # as DD.MM.YYYY,
    # so that the snapshot page reads its dates as Wealth does.
    #
    # Acceptance criteria:
    # - The list's as-of cell reads "15.02.2026".
    # - The comparison table's date column reads DD.MM.YYYY.
    test "the snapshot list and its comparison read German dates", %{conn: conn} do
      world = base_world(name: "Snap", cash_name: "Girokonto", depot_name: "Depot 1")
      sec = create_security!(name: "Meridian Stock", ticker: "MRS")
      deposit!(world, "10000", ~D[2026-01-02])
      buy!(world, sec, quantity: "5", price: "100", date: ~D[2026-01-05])
      put_quotes!(sec, [{~D[2026-02-14], "110"}, {~D[2026-03-10], "120"}])

      {:ok, _snapshot} =
        Snapshots.create_snapshot(Actor.owner_ui(), %{
          name: "Vor dem Umbau",
          as_of: ~D[2026-02-15]
        })

      {:ok, view, _html} = live(german(conn), "/snapshots")

      assert text(view, "[data-role=snapshot-row]") =~ "15.02.2026"
      refute text(view, "[data-role=snapshot-row]") =~ @iso

      view
      |> element("[data-role=snapshot-row] a[data-role=snapshot-select]")
      |> render_click()

      dates = texts(view, "[data-role=comparison-table] tbody tr td:first-child")
      assert dates != []
      assert Enum.all?(dates, &(&1 =~ ~r/^\d{2}\.\d{2}\.\d{4}$/))
    end
  end
end
