defmodule PortfolixirWeb.TransactionManagementLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # User story (ADR-0024, supersedes #471):
  # As a maintainer recording transactions,
  # I want the form to offer every depot directly — no portfolio strip, no
  # portfolio switch —
  # so that the depot choice alone decides where a transaction books and the
  # portfolio stays an internal compatibility record.
  #
  # Acceptance criteria:
  # - No portfolio strip renders; the word "Portfolio" is not used as a
  #   grouping control.
  # - Depots from every internal portfolio are offered together.
  # - A transaction books into the chosen depot's internal portfolio.
  test "offers every depot and books into the chosen depot's internal portfolio",
       %{conn: conn} do
    alpha =
      WorldFixtures.base_world(name: "Alpha", depot_name: "Alpha Depot", cash_name: "Alpha Cash")

    beta =
      WorldFixtures.base_world(name: "Beta", depot_name: "Beta Depot", cash_name: "Beta Cash")

    security = WorldFixtures.create_security!(name: "Switch Co", ticker: "SWC")

    {:ok, view, html} = live(conn, "/transactions")

    # No portfolio strip and no switch chips.
    refute has_element?(view, "#transaction-portfolio-strip")
    refute has_element?(view, "#portfolio-switch-#{alpha.portfolio.id}")
    refute html =~ "Portfolio:"

    # Both depots are offered at once.
    assert html =~ "Alpha Depot"
    assert html =~ "Beta Depot"

    # Booking against Beta's depot lands in Beta's internal portfolio.
    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(beta.depot.id),
        "security_id" => to_string(WorldFixtures.security_id_for(security)),
        "quantity" => "3",
        "price" => "100",
        "currency_code" => "EUR"
      }
    })

    assert Ledger.list_transactions_for_portfolio(beta.portfolio.id) != []
    assert Ledger.list_transactions_for_portfolio(alpha.portfolio.id) == []
  end

  # User story (#472):
  # As a maintainer choosing a depot, I want each option to read clearly — the
  # depot name with its linked cash account as a quiet caption — instead of an
  # arrow plus a separate footnote, so the dropdown is self-explanatory.
  #
  # Acceptance criteria:
  # - The depot option shows the depot name and its linked cash account as a
  #   parenthetical caption, not via a "->" arrow.
  # - The "Linked cash account is derived…" footnote is gone.
  test "depot option shows the linked cash account as a caption, no arrow/footnote (#472)",
       %{conn: conn} do
    WorldFixtures.base_world(name: "Solo", depot_name: "Main Depot", cash_name: "Local Cash")

    {:ok, _view, html} = live(conn, "/transactions")

    assert html =~ "Main Depot (Local Cash)"
    refute html =~ "Main Depot -&gt;"
    refute html =~ "Linked cash account is derived"
  end

  # User story (#473):
  # As a maintainer recording a trade, I want the currency derived from the
  # chosen depot's cash account and the rare fees/taxes tucked behind a
  # disclosure, so the common buy/sell path stays clean.
  #
  # Acceptance criteria:
  # - No free-text Currency input in the default field set.
  # - Fees/Taxes live behind a (collapsed) disclosure.
  # - A basic buy with no costs derives currency from the depot and stores 0 costs.
  test "derives currency from the depot and hides costs behind a disclosure (#473)",
       %{conn: conn} do
    world =
      WorldFixtures.base_world(
        name: "Solo",
        currency: "USD",
        depot_name: "Main",
        cash_name: "Cash"
      )

    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB", currency: "USD")

    {:ok, view, _html} = live(conn, "/transactions")

    refute has_element?(view, "input[name='transaction[currency_code]']")
    assert has_element?(view, "details#transaction-costs")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50"
      }
    })

    [tx] = Ledger.list_transactions_for_portfolio(world.portfolio.id)
    assert tx.currency_code == "USD"
    assert Decimal.equal?(tx.fees, Decimal.new("0"))
    assert Decimal.equal?(tx.taxes, Decimal.new("0"))
  end

  # The phx-change that drives the derived-currency caption must not blank the
  # depot select: the chosen option keeps its server-rendered `selected` state.
  test "keeps the chosen depot selected after a form change (#473)", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo", depot_name: "Main", cash_name: "Cash")

    {:ok, view, _html} = live(conn, "/transactions")

    html =
      view
      |> element("#transaction-form")
      |> render_change(%{
        "transaction" => %{"securities_account_id" => to_string(world.depot.id)}
      })

    assert html =~ ~r/<option[^>]*value="#{world.depot.id}"[^>]*selected/
    assert html =~ "Currency: EUR"
  end

  test "records fees entered in the costs disclosure (#473)", %{conn: conn} do
    world =
      WorldFixtures.base_world(
        name: "Solo",
        currency: "EUR",
        depot_name: "Main",
        cash_name: "Cash"
      )

    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB", currency: "EUR")

    {:ok, view, _html} = live(conn, "/transactions")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50",
        "fees" => "3.50"
      }
    })

    [tx] = Ledger.list_transactions_for_portfolio(world.portfolio.id)
    assert Decimal.equal?(tx.fees, Decimal.new("3.50"))
  end

  # User story (#474):
  # As a maintainer, I want the input form to read as the primary task with
  # holdings and history as secondary supporting panels, and only the 6 core
  # fields up front, so the screen says "enter here, see results there".
  #
  # Acceptance criteria:
  # - The default form shows exactly the 6 core fields plus the costs disclosure.
  # - Holdings/history render as a secondary region but keep their DOM ids and
  #   still show their data after a transaction is recorded.
  test "shows the 6 core fields and keeps holdings/history panels (#474)", %{conn: conn} do
    world =
      WorldFixtures.base_world(
        name: "Solo",
        currency: "EUR",
        depot_name: "Main",
        cash_name: "Cash"
      )

    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB", currency: "EUR")

    {:ok, view, _html} = live(conn, "/transactions")

    for field <- ~w(type date securities_account_id security_id quantity price) do
      assert has_element?(view, "#transaction-form [name='transaction[#{field}]']")
    end

    assert has_element?(view, "details#transaction-costs")
    # The holdings/history panels are grouped as a secondary region.
    assert has_element?(view, ".transaction-secondary #holdings-panel")
    assert has_element?(view, ".transaction-secondary #transaction-list-panel")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50"
      }
    })

    # The preserved ids still resolve and render their data.
    assert has_element?(view, "#holdings-panel #holdings-table")
    assert has_element?(view, "#transaction-list-panel #transaction-list")
  end

  # User story (Steve cold-start #2):
  # As a German-speaking maintainer recording a transaction,
  # I want the Type dropdown and history to read in my language,
  # so that the form does not feel half-built with raw "buy"/"sell" leaking
  # through an otherwise localized screen.
  #
  # Acceptance criteria:
  # - The Type select offers localized option labels ("Buy"/"Sell" in English),
  #   while the submitted value stays the stored enum ("buy"/"sell").
  # - The transaction history Type column shows the localized label, not the
  #   raw stored enum.
  test "localizes the transaction Type options and history labels", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")
    security = WorldFixtures.create_security!(name: "Localize Co", ticker: "LOC")

    {:ok, view, _html} = live(conn, "/transactions")

    # The option keeps its machine value but renders a human, localized label.
    assert has_element?(
             view,
             "#transaction-form select[name='transaction[type]'] option[value='buy']",
             "Buy"
           )

    assert has_element?(
             view,
             "#transaction-form select[name='transaction[type]'] option[value='sell']",
             "Sell"
           )

    # A recorded buy shows the localized label in the history, not raw "buy".
    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2",
        "price" => "50"
      }
    })

    assert has_element?(view, "#transaction-list tbody tr td", "Buy")
  end

  # User story (fix round, UAT locale):
  # As a German-speaking maintainer,
  # I want to type decimal commas into the price/quantity/fees/taxes fields,
  # so that "100,50" books as 100.50 instead of failing validation.
  #
  # Acceptance criteria:
  # - A single comma with no dot is normalized to a dot at the form boundary.
  # - The stored Decimal values are exact; nothing else touches persisted
  #   parsing.
  test "accepts German decimal commas in the money fields", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Komma")
    security = WorldFixtures.create_security!(name: "Komma Co", ticker: "KOM")

    {:ok, view, _html} = live(conn, "/transactions")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-03-02",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "2,5",
        "price" => "100,50",
        "fees" => "1,25"
      }
    })

    assert [tx] = Ledger.list_transactions_for_portfolio(world.portfolio.id)
    assert Decimal.equal?(tx.quantity, Decimal.new("2.5"))
    assert Decimal.equal?(tx.price, Decimal.new("100.50"))
    assert Decimal.equal?(tx.fees, Decimal.new("1.25"))
  end

  # User story (fix round, UAT locale):
  # As a German-speaking maintainer,
  # I want a failed submit to explain itself in German,
  # so that "price is invalid" never leaks raw Ecto messages into a
  # translated page.
  test "renders the changeset error translated instead of the raw message", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Fehler")
    security = WorldFixtures.create_security!(name: "Fehler Co", ticker: "FLR")

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    html =
      view
      |> element("#transaction-form")
      |> render_submit(%{
        "transaction" => %{
          "type" => "buy",
          "date" => "2026-03-02",
          "securities_account_id" => to_string(world.depot.id),
          "security_id" => to_string(security.id),
          "quantity" => "2",
          "price" => "abc"
        }
      })

    refute html =~ "price is invalid"
    assert html =~ "Preis"
    assert html =~ "ist ungültig"
  end

  # User story (fix round, UAT locale):
  # As a German-speaking maintainer,
  # I want the history's month-group headers in German with money-formatted
  # sums,
  # so that the localized page never mixes English month names or raw
  # decimals into the section heads (same precedent as the income matrix).
  test "localizes the month-group headers and money-formats the group sums", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Monat")
    security = WorldFixtures.create_security!(name: "Monat Co", ticker: "MON")
    WorldFixtures.deposit!(world, "1000", ~D[2026-03-01])
    WorldFixtures.buy!(world, security, quantity: "2", price: "50", date: ~D[2026-03-02])

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    header = view |> element("tr.tx-group-head[data-month-group='2026-03']") |> render()
    assert header =~ "März 2026"
    refute header =~ "March"
    # Money-formatted subtotal in the German locale (1000 + 100 = 1.100,00).
    assert header =~ "1.100,00"
  end

  # User story (fix round, UAT locale):
  # As a German-speaking maintainer with a year-spanning history,
  # I want EVERY month-group header translated,
  # so that no strftime English month name (May, October, ...) leaks into the
  # localized history for any month of the year.
  test "translates the month-group header for every month", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Jahr")

    for month <- 4..12 do
      WorldFixtures.deposit!(world, "10", Date.new!(2026, month, 1))
    end

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    expected = %{
      4 => "April 2026",
      5 => "Mai 2026",
      6 => "Juni 2026",
      7 => "Juli 2026",
      8 => "August 2026",
      9 => "September 2026",
      10 => "Oktober 2026",
      11 => "November 2026",
      12 => "Dezember 2026"
    }

    for {month, label} <- expected do
      group = "2026-#{month |> Integer.to_string() |> String.pad_leading(2, "0")}"
      header = view |> element("tr.tx-group-head[data-month-group='#{group}']") |> render()
      assert header =~ label
    end

    html = render(view)
    refute html =~ "May 2026"
    refute html =~ "October 2026"
    refute html =~ "December 2026"
  end

  # User story (fix round, UAT locale):
  # As a German-speaking maintainer who submits an incomplete form,
  # I want the flash to name every offending field with its localized label,
  # so that "securities_account_id can't be blank" never leaks schema field
  # names into a translated page.
  #
  # Acceptance criteria:
  # - A submit without a depot keeps the ledger empty and reports the missing
  #   depot/security/date (and the negative costs) in German.
  # - The internal portfolio binding is simply absent when no depot matched —
  #   no crash, the changeset reports it.
  test "a submit without a depot names every missing field in German", %{conn: conn} do
    WorldFixtures.base_world(name: "Leer")
    _security = WorldFixtures.create_security!(name: "Leer Co", ticker: "LER")

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    html =
      view
      |> element("#transaction-form")
      |> render_submit(%{
        "transaction" => %{
          "type" => "buy",
          "date" => "",
          "securities_account_id" => "",
          "security_id" => "",
          "quantity" => "2",
          "price" => "10",
          "fees" => "-1",
          "taxes" => "-1"
        }
      })

    assert Portfolixir.Ledger.list_transactions() == []

    # Localized field labels, not schema field names.
    assert html =~ "Depot darf nicht leer sein"
    assert html =~ "Wertpapier darf nicht leer sein"
    assert html =~ "Datum darf nicht leer sein"
    assert html =~ "Verrechnungskonto darf nicht leer sein"
    refute html =~ "securities_account_id can&#39;t be blank"

    # Negative costs are rejected with the localized number message.
    assert html =~ "Gebühren muss größer oder gleich 0 sein"
    assert html =~ "Steuern muss größer oder gleich 0 sein"
  end

  # User story (fix round, robustness):
  # As a local portfolio maintainer whose stale browser tab sends a degraded
  # payload (missing cost fields, an unknown type, a malformed currency),
  # I want the save to answer with translated validation errors,
  # so that a hostile or out-of-date client can neither crash the view nor
  # write an invalid transaction.
  test "a degraded client payload gets translated errors, nothing is written", %{conn: conn} do
    WorldFixtures.base_world(name: "Kaputt")

    {:ok, view, _html} = live(conn, "/transactions?locale=de")

    # Sent straight at the event handler: no fees/taxes keys at all, an
    # unknown type and a two-letter currency the form would never produce.
    html =
      render_submit(view, "save_transaction", %{
        "transaction" => %{
          "type" => "bogus",
          "date" => "2026-01-05",
          "currency_code" => "EU",
          "quantity" => "1",
          "price" => "1"
        }
      })

    assert Portfolixir.Ledger.list_transactions() == []
    assert html =~ "Typ ist ungültig"
    # The pluralized length message runs through the errors domain (count).
    assert html =~ "Währung muss genau 3 Zeichen lang sein"

    # A cash kind without its amount reports the localized Amount label.
    html =
      render_submit(view, "save_transaction", %{
        "transaction" => %{"type" => "dividend", "date" => "2026-01-05"}
      })

    assert Portfolixir.Ledger.list_transactions() == []
    assert html =~ "Betrag darf nicht leer sein"
    assert html =~ "Verrechnungskonto darf nicht leer sein"
  end

  # The history lists every ledger kind, not just buy/sell (e.g. an imported
  # dividend). Every PP kind now carries a translated label (Steve UAT,
  # reconsolidation); unknown kinds still fall back to their stored name
  # rather than crashing the table.
  test "history shows a translated label for non-buy/sell kinds", %{conn: conn} do
    world = WorldFixtures.base_world(name: "Solo")
    security = WorldFixtures.create_security!(name: "Payer Inc", ticker: "PAY")

    {:ok, _tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: WorldFixtures.security_id_for(security),
        type: "dividend",
        date: ~D[2026-02-01],
        gross_amount: "100",
        currency_code: "EUR"
      })

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-list tbody tr td", "Dividend")
  end

  # User story (Steve cold-start #1):
  # As a new user who has set up a portfolio and a depot but no securities yet,
  # I want the transaction form to tell me a security must exist first and send
  # me to create one,
  # so that I do not fill in the whole form only to hit an empty, unselectable
  # "Wertpapier auswählen" dropdown that silently blocks submission.
  #
  # Acceptance criteria:
  # - With no securities, the Security field is replaced by an empty-state that
  #   links to /securities (the missing prerequisite is named at the point of
  #   pain), and the dead security <select> is not rendered.
  # - Once a security exists, the normal Security select is back.
  test "names the missing-security prerequisite instead of a dead empty select",
       %{conn: conn} do
    _world = WorldFixtures.base_world(name: "Solo")

    {:ok, view, _html} = live(conn, "/transactions")

    # The dead, unselectable security dropdown is gone...
    refute has_element?(view, "#transaction-form select[name='transaction[security_id]']")
    # ...replaced by a teaching empty-state that links to where you fix it.
    assert has_element?(view, "#transaction-no-securities a[href='/securities']")
  end

  test "shows the security select again once a security exists", %{conn: conn} do
    _world = WorldFixtures.base_world(name: "Solo")
    WorldFixtures.create_security!(name: "Has Sec", ticker: "HAS")

    {:ok, view, _html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-form select[name='transaction[security_id]']")
    refute has_element?(view, "#transaction-no-securities")
  end

  # User story (Steve UAT #414):
  # As a maintainer with a long transaction history,
  # I want to filter the list (by type, security and date range, plus text
  # search) and read a summary of what the current filter selects,
  # so that I can find and understand my transactions instead of scrolling a
  # flat wall of rows.
  #
  # Acceptance criteria:
  # - A summary header reports the count of the currently shown transactions
  #   and a per-type breakdown.
  # - Filtering by type narrows both the list and the summary.
  # - Filtering by security narrows the list.
  # - A date-range filter keeps only transactions within the range.
  # - A filter that matches nothing shows a distinct no-match state, not the
  #   "no transactions yet" empty state.
  describe "transaction overview (#414)" do
    defp overview_world do
      world =
        WorldFixtures.base_world(name: "Overview", depot_name: "Depot", cash_name: "Cash")

      etf = WorldFixtures.create_security!(name: "World ETF", ticker: "WLD")
      bond = WorldFixtures.create_security!(name: "Bond Fund", ticker: "BND")

      mk = fn attrs ->
        {:ok, _} =
          Ledger.create_transaction(
            Portfolixir.Actor.owner_ui(),
            Map.merge(
              %{
                portfolio_id: world.portfolio.id,
                cash_account_id: world.cash.id,
                securities_account_id: world.depot.id,
                currency_code: "EUR"
              },
              attrs
            )
          )
      end

      mk.(%{
        security_id: WorldFixtures.security_id_for(etf),
        type: "buy",
        date: ~D[2026-01-10],
        quantity: "10",
        price: "100"
      })

      mk.(%{
        security_id: WorldFixtures.security_id_for(etf),
        type: "sell",
        date: ~D[2026-03-15],
        quantity: "4",
        price: "120"
      })

      mk.(%{
        security_id: WorldFixtures.security_id_for(bond),
        type: "buy",
        date: ~D[2026-02-20],
        quantity: "5",
        price: "50"
      })

      %{world: world, etf: etf, bond: bond}
    end

    test "summary header reports the count and a per-type breakdown", %{conn: conn} do
      overview_world()

      {:ok, view, _html} = live(conn, "/transactions")

      summary = view |> element("#transaction-summary") |> render()
      # Three transactions in total, two of them buys.
      assert summary =~ "3"
      assert has_element?(view, "#transaction-summary [data-role='summary-total']", "3")
      assert has_element?(view, "#transaction-summary [data-type='buy']", "2")
      assert has_element?(view, "#transaction-summary [data-type='sell']", "1")
    end

    test "filtering by type narrows the list and the summary", %{conn: conn} do
      overview_world()

      {:ok, view, _html} = live(conn, "/transactions")

      view
      |> form("#transaction-filters", %{"filters" => %{"type" => "sell"}})
      |> render_change()

      rows = view |> element("#transaction-list tbody") |> render()
      assert rows =~ "Sell"
      refute rows =~ "Buy"
      assert has_element?(view, "#transaction-summary [data-role='summary-total']", "1")
    end

    test "filtering by security narrows the list", %{conn: conn} do
      %{bond: bond} = overview_world()

      {:ok, view, _html} = live(conn, "/transactions")

      view
      |> form("#transaction-filters", %{
        "filters" => %{"security_id" => to_string(WorldFixtures.security_id_for(bond))}
      })
      |> render_change()

      rows = view |> element("#transaction-list tbody") |> render()
      assert rows =~ "Bond Fund"
      refute rows =~ "World ETF"
    end

    test "a date-range filter keeps only transactions in the range", %{conn: conn} do
      overview_world()

      {:ok, view, _html} = live(conn, "/transactions")

      view
      |> form("#transaction-filters", %{
        "filters" => %{"from" => "2026-02-01", "to" => "2026-02-28"}
      })
      |> render_change()

      # Only the 2026-02-20 bond buy falls in February.
      assert has_element?(view, "#transaction-summary [data-role='summary-total']", "1")
      rows = view |> element("#transaction-list tbody") |> render()
      assert rows =~ "Bond Fund"
      refute rows =~ "World ETF"
    end

    test "a filter that matches nothing shows a distinct no-match state", %{conn: conn} do
      overview_world()

      {:ok, view, _html} = live(conn, "/transactions")

      view
      |> form("#transaction-filters", %{"filters" => %{"query" => "zzz-no-such-thing"}})
      |> render_change()

      assert has_element?(view, "#transaction-no-match")
      refute has_element?(view, "#transaction-list tbody tr")
    end

    # User story (Steve UAT #414 follow-up):
    # As a maintainer scanning a long history,
    # I want the rows sectioned by month with a subtotal per section,
    # so that I read the ledger in meaningful chunks instead of one undivided
    # run of rows.
    #
    # Acceptance criteria:
    # - Transactions are grouped into month sections (most recent first), each
    #   with a header row carrying the month and a count + amount subtotal.
    # - Sections honour the active filter.
    test "sections the history by month with per-month subtotals", %{conn: conn} do
      overview_world()

      {:ok, view, _html} = live(conn, "/transactions")

      # Three buys/sells across Jan, Feb and Mar 2026 -> three month sections.
      assert has_element?(view, "#transaction-list tr.tx-group-head[data-month-group='2026-03']")
      assert has_element?(view, "#transaction-list tr.tx-group-head[data-month-group='2026-02']")
      assert has_element?(view, "#transaction-list tr.tx-group-head[data-month-group='2026-01']")

      # Each month's header subtotals its single transaction.
      jan = view |> element("tr.tx-group-head[data-month-group='2026-01']") |> render()
      assert jan =~ "1"

      # Filtering to sells leaves only the March section.
      view
      |> form("#transaction-filters", %{"filters" => %{"type" => "sell"}})
      |> render_change()

      assert has_element?(view, "#transaction-list tr.tx-group-head[data-month-group='2026-03']")
      refute has_element?(view, "#transaction-list tr.tx-group-head[data-month-group='2026-01']")
    end
  end

  # User story (Steve UAT #412 follow-up, UX-DR13):
  # As a maintainer who submits the transaction form with a bad value,
  # I want the offending field itself marked invalid with its error message
  # associated to it,
  # so that the error is announced on the field (a screen reader can reach it)
  # instead of only as a detached banner.
  #
  # Acceptance criteria:
  # - A field that fails validation gets aria-invalid="true" and an
  #   aria-describedby pointing at its inline error message.
  # - The associated error message element exists.
  # - Valid fields are not marked invalid.
  test "associates field errors with aria-invalid/aria-describedby (#412)", %{conn: conn} do
    world =
      WorldFixtures.base_world(name: "Solo", depot_name: "Main", cash_name: "Cash")

    security = WorldFixtures.create_security!(name: "Globex", ticker: "GLB", currency: "EUR")

    {:ok, view, _html} = live(conn, "/transactions")

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" => %{
        "type" => "buy",
        "date" => "2026-02-01",
        "securities_account_id" => to_string(world.depot.id),
        "security_id" => to_string(WorldFixtures.security_id_for(security)),
        "quantity" => "",
        "price" => "50"
      }
    })

    # The blank required quantity is marked invalid and points at its message.
    assert has_element?(
             view,
             "#transaction-form input[name='transaction[quantity]'][aria-invalid='true'][aria-describedby='tx-error-quantity']"
           )

    assert has_element?(view, "#tx-error-quantity")

    # The valid price field is not flagged.
    refute has_element?(
             view,
             "#transaction-form input[name='transaction[price]'][aria-invalid='true']"
           )
  end

  # User story (Steve UAT, reconsolidation):
  # As a maintainer scanning the Transactions page,
  # I want holdings quantities and the summary shown as clean numbers with
  # translated type labels,
  # so that "200.000000000000" internals and raw type keys like "deposit"
  # do not undermine trust in the ledger view.
  #
  # Acceptance criteria:
  # - Holdings quantities render normalized (200, not 200.000000000000).
  # - The per-type summary uses translated labels for every PP kind and
  #   locale-formatted amounts.
  test "holdings and the summary render clean numbers and translated labels", %{conn: conn} do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Clean Co", ticker: "CLN")

    WorldFixtures.deposit!(world, "52000", ~D[2026-01-02])
    WorldFixtures.buy!(world, security, quantity: "200", price: "10", date: ~D[2026-01-03])

    {:ok, _view, html} = live(conn, "/transactions")

    # Holdings show the normalized quantity, not Decimal internals.
    refute html =~ "200.000000000000"
    assert html =~ ~r/>\s*200\s*</

    # The summary translates every type key and formats the amounts.
    assert html =~ ~r/data-type="deposit"/
    refute html =~ ~s(deposit:)
    assert html =~ "Deposit"
    assert html =~ "52,000.00"
    refute html =~ "52000.000000"
  end
end
