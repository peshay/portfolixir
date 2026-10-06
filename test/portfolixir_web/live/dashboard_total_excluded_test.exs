defmodule PortfolixirWeb.DashboardTotalExcludedTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Clock
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  # Board 01's synthetic data (#1081, D-3): the Overview's EUR world with
  # a valued fund, and what the total cannot value — USD accounts with no
  # EUR rate, a bond with no price, a USD share with a price but no rate.
  defp world do
    world = base_world(name: "Board", cash_name: "Girokonto", depot_name: "Depot")
    fund = create_security!(name: "Lumen Index Fonds", ticker: "LMN", asset_class: "etf")
    deposit!(world, "2000", days_ago(40))
    buy!(world, fund, quantity: "10", price: "100", date: days_ago(30))
    put_quote!(fund, Clock.today(), "120")
    world
  end

  defp days_ago(days), do: Date.add(Clock.today(), -days)

  defp usd_account!(world, name, balance, role \\ "free_cash") do
    {:ok, account} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: name,
        currency_code: "USD",
        liquidity_role: role
      })

    if balance do
      {:ok, _} =
        Ledger.set_cash_balance(Actor.owner_ui(), account, %{date: days_ago(5), amount: balance})
    end

    account
  end

  defp deliver!(world, security, quantity, depot \\ nil) do
    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        securities_account_id: (depot || world.depot).id,
        security_id: security.id,
        type: "inbound_delivery",
        date: days_ago(5),
        quantity: quantity,
        currency_code: security.currency_code
      })
  end

  defp bond! do
    create_security!(name: "Placeholder Anleihe 2031 3,25%", ticker: nil, asset_class: "bond")
  end

  defp text(nodes),
    do: nodes |> Floki.text() |> String.replace(~r/\s+/, " ") |> String.trim()

  defp note_text(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s([data-role="wealth-card-excluded"] .data-note__body))
    |> text()
  end

  defp de_live(conn, path) do
    conn = get(conn, path <> "?locale=de")
    live(conn, path <> "?locale=de")
  end

  # User story (#1081, D-3, board 01 pick J1 A; UX-DR25):
  # As a stranger reading the Overview's total for the first time,
  # I want the total to say, beside the figure, which cash accounts and held
  # positions it leaves out, with each account's own balance,
  # so that a figure that is right by its own rules is not wrong by mine.
  #
  # Acceptance criteria:
  # - Under the "Alles" card, inside the card's section, one attention data
  #   note reads the board sentence word for word in German: the count, the
  #   names, each account's native balance, the groups separated by " · ",
  #   and a "Details in Vermögen →" link to /portfolio, with no control.
  # - The card's section carries no `grid` class, so the card keeps its
  #   width and the note takes its own row.
  # - An account with no rate and a zero balance is not named.
  test "the note under the total reads the board sentence and links to Wealth", %{conn: conn} do
    world = world()
    usd_account!(world, "USD Settlement", "1850")
    usd_account!(world, "US Broker", "60")
    usd_account!(world, "Leer USD", nil)
    deliver!(world, bond!(), "10")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 2 Verrechnungskonten ohne Wechselkurs zu EUR — " <>
               "USD Settlement (1.850,00 USD), US Broker (60,00 USD) · " <>
               "1 gehaltene Position ohne Preis — Placeholder Anleihe 2031 3,25%. " <>
               "Details in Vermögen →"

    section = "section#dashboard-wealth"

    assert has_element?(view, "#{section} #dashboard-wealth-card")

    assert has_element?(
             view,
             "#{section} [role='status'] .data-note--attention[data-role='wealth-card-excluded']"
           )

    assert has_element?(
             view,
             "[data-role='wealth-card-excluded'] a[href='/portfolio']",
             "Details in Vermögen →"
           )

    refute has_element?(view, "[data-role='wealth-card-excluded'] button")
    refute has_element?(view, "section.grid #dashboard-wealth-card")
    refute note_text(view) =~ "Leer USD"
  end

  test "the note's English source says the same", %{conn: conn} do
    world = world()
    usd_account!(world, "USD Settlement", "1850")
    deliver!(world, bond!(), "10")

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Not in the total: 1 cash account with no exchange rate to EUR — " <>
               "USD Settlement (1,850.00 USD) · " <>
               "1 held position with no price — Placeholder Anleihe 2031 3,25%. " <>
               "Details in Wealth →"
  end

  # User story (#1081, D-3; UX-DR2 — no all-clear; UX-DR17 — one status
  # region that exists before the read lands):
  # As a reader of the Overview,
  # I want nothing under the total when it leaves nothing out, and the note
  # announced once when it arrives,
  # so that silence means complete and an arriving note is heard.
  #
  # Acceptance criteria:
  # - The card's section holds one role="status" region before the async
  #   read lands.
  # - With every balance and position valued, the region is present and
  #   empty, and no note renders.
  test "with everything valued no note renders, and the status region is there and empty",
       %{conn: conn} do
    world = world()
    usd_account!(world, "Leer USD", nil)

    # The dead render: nothing, not even whitespace, inside the region, so
    # `.wealth-card-status:empty` holds and the region takes no room.
    # LiveViewTest's render drops whitespace, so this is where it is seen.
    assert conn |> get("/") |> html_response(200) =~
             ~s(role="status" class="wealth-card-status"></div>)

    {:ok, view, html} = live(conn, "/")

    # Before the read lands: the region exists, the card is still pending.
    assert [_region] =
             html
             |> Floki.parse_document!()
             |> Floki.find(
               "section#dashboard-wealth #dashboard-wealth-card-status[role='status']"
             )

    render_async(view)

    assert has_element?(view, "#dashboard-wealth-card")
    refute has_element?(view, "[data-role='wealth-card-excluded']")

    assert [region] =
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find(
               "section#dashboard-wealth #dashboard-wealth-card-status[role='status']"
             )

    assert Floki.children(region) == []
  end

  # User story (#1081, board 01 ⑤): Wealth's rule shortens each group.
  #
  # Acceptance criteria:
  # - With nine accounts left out, the count says nine, six names follow,
  #   then "+3".
  test "a long group names six and then +N, the count staying true", %{conn: conn} do
    world = world()

    for n <- 1..9 do
      usd_account!(world, "USD Konto #{n}", "#{n}00")
    end

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 9 Verrechnungskonten ohne Wechselkurs zu EUR — " <>
               "USD Konto 1 (100,00 USD), USD Konto 2 (200,00 USD), " <>
               "USD Konto 3 (300,00 USD), USD Konto 4 (400,00 USD), " <>
               "USD Konto 5 (500,00 USD), USD Konto 6 (600,00 USD), +3. " <>
               "Details in Vermögen →"
  end

  # User story (#1081, board 01 ⑤; #406):
  # As a reader of the Overview,
  # I want a held position that has a price but no exchange rate named in a
  # group of its own, with its native price,
  # so that the note says why it is out as Wealth's missing-FX note does.
  #
  # Acceptance criteria:
  # - The groups follow in order: cash, no price, no rate; the no-rate group
  #   reads "1 gehaltene Position ohne Wechselkurs zu EUR — Name (12,40 USD)".
  test "a price with no rate path is a third group, after the other two", %{conn: conn} do
    world = world()
    usd_account!(world, "USD Settlement", "1850")
    deliver!(world, bond!(), "10")

    harbor =
      create_security!(name: "Harborline Freight", ticker: "HBF", currency: "USD")

    deliver!(world, harbor, "5")
    put_quote!(harbor, days_ago(1), "12.40")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 1 Verrechnungskonto ohne Wechselkurs zu EUR — " <>
               "USD Settlement (1.850,00 USD) · " <>
               "1 gehaltene Position ohne Preis — Placeholder Anleihe 2031 3,25% · " <>
               "1 gehaltene Position ohne Wechselkurs zu EUR — Harborline Freight (12,40 USD). " <>
               "Details in Vermögen →"
  end

  # User story (#1081, D-3, pick J1.2 A; UX-DR26):
  # As a reader of the strip, whose basis line speaks of held positions,
  # I want the stale count to say that it counts the catalog,
  # so that the difference between the two is stated, not a contradiction.
  #
  # Acceptance criteria:
  # - The quotes cell's sub-line reads "%{count} veraltet im Katalog".
  # - The data-quality line reads "%{count} Wertpapiere im Katalog ohne Kurs
  #   seit 7 Tagen".
  test "the stale count says it counts the catalog, in the cell and on the line",
       %{conn: conn} do
    world()
    create_security!(name: "Watch One", ticker: "WO1")
    create_security!(name: "Watch Two", ticker: "WO2")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    doc = view |> render() |> Floki.parse_document!()

    assert doc
           |> Floki.find(~s([data-role="kpi-freshness"] .kpi-strip__sub--attention))
           |> text() == "2 veraltet im Katalog"

    assert doc |> Floki.find(~s([data-role="dq-quotes"])) |> text() ==
             "2 Wertpapiere im Katalog ohne Kurs seit 7 Tagen"
  end

  # User story (#1081, board 01 "found while drawing" 3):
  # As a reader of the data-quality line,
  # I want its first finding to carry its noun,
  # so that a line with no stale quote does not open "4 ohne Anlageklasse".
  #
  # Acceptance criteria:
  # - With no stale quote, the class finding that opens the line reads
  #   "%{count} Wertpapiere ohne Anlageklasse", and the logo finding after it
  #   keeps its short form.
  # - With neither a stale quote nor a missing class, the logo finding opens
  #   the line with its noun.
  test "the line's first finding carries its noun", %{conn: conn} do
    world()

    unclassed =
      for n <- 1..4 do
        security = create_security!(name: "Lumen #{n}", ticker: "LM#{n}", asset_class: nil)
        put_quote!(security, Clock.today(), "10")
        security
      end

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    # Every quote is fresh; no security carries a logo, the fund included.
    doc = view |> render() |> Floki.parse_document!()
    assert Floki.find(doc, ~s([data-role="dq-quotes"])) == []

    assert doc |> Floki.find(~s([data-role="dq-class"])) |> text() ==
             "4 Wertpapiere ohne Anlageklasse"

    assert doc |> Floki.find(~s([data-role="dq-logo"])) |> text() == "5 ohne Logo"

    for security <- unclassed do
      {:ok, _} = Catalog.update_security(Actor.owner_ui(), security, %{asset_class: "equity"})
    end

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    doc = view |> render() |> Floki.parse_document!()
    assert Floki.find(doc, ~s([data-role="dq-class"])) == []
    assert doc |> Floki.find(~s([data-role="dq-logo"])) |> text() == "5 Wertpapiere ohne Logo"
  end

  # User story (#1081, D-3; PR #1102 built the agreement):
  # As a reader following a count on the Overview,
  # I want the list it opens to hold as many rows as the count says,
  # so that a benchmark or a retired security never makes the two differ.
  #
  # Acceptance criteria:
  # - With a benchmark and a retired security among the unquoted, logo-less,
  #   unclassed securities, each Overview count equals the rows of the list
  #   its link opens: stale quotes and logos leave both out, the asset-class
  #   finding leaves out the retired one and keeps the benchmark.
  test "the Overview's counts equal the rows of the lists they link to", %{conn: conn} do
    world()
    create_security!(name: "Watch One", ticker: "WO1", asset_class: nil)
    retired = create_security!(name: "Closed Two", ticker: "CL2", asset_class: nil)
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})
    bench = create_security!(name: "Index Three", ticker: "IX3", asset_class: nil)
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), bench, %{is_benchmark: true})

    {:ok, view, _html} = live(conn, "/")
    render_async(view)

    # Watch One is stale; the fund and Watch One have no logo; Watch One and
    # the benchmark have no class.
    for {role, expected} <- [{"dq-quotes", 1}, {"dq-logo", 2}, {"dq-class", 2}] do
      [finding] =
        view |> render() |> Floki.parse_document!() |> Floki.find(~s([data-role="#{role}"]))

      [href] = Floki.attribute(finding, "href")
      {count, _rest} = finding |> text() |> String.replace_prefix("one ", "1 ") |> Integer.parse()
      assert count == expected, role

      {:ok, list, _html} = live(conn, href)

      rows =
        list |> render() |> Floki.parse_document!() |> Floki.find("tr[id^='security-row-']")

      assert length(rows) == count, role
    end
  end

  # User story (#1081, review round):
  # As a reader of the note, I want each security left out counted once,
  # however many depots hold it, and two securities that share a name counted
  # as two, so that the count is the number of securities missing.
  #
  # Acceptance criteria:
  # - One unpriced security delivered into two depots is named once, "1 …".
  # - Two different unpriced securities with one name are counted twice.
  test "a group counts securities, not depots and not labels", %{conn: conn} do
    world = world()

    %{depot: second} =
      add_depot(world.portfolio, cash_name: "Zweitkonto", depot_name: "Zweitdepot")

    bond = bond!()
    deliver!(world, bond, "10")
    deliver!(world, bond, "5", second)

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 1 gehaltene Position ohne Preis — " <>
               "Placeholder Anleihe 2031 3,25%. Details in Vermögen →"

    deliver!(world, create_security!(name: "Placeholder Anleihe 2031 3,25%", ticker: nil), "3")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 2 gehaltene Positionen ohne Preis — " <>
               "Placeholder Anleihe 2031 3,25%, Placeholder Anleihe 2031 3,25%. " <>
               "Details in Vermögen →"
  end

  # User story (#1081, review round; PR #1102):
  # As a reader of the Overview's total, I want a retired security I still
  # hold and cannot price named under it, because the total leaves it out —
  # although Wealth's no-price note, whose link opens a list without retired
  # securities, does not name it.
  test "a retired held position with no price is named under the total", %{conn: conn} do
    world = world()
    bond = bond!()
    deliver!(world, bond, "10")
    {:ok, _} = Catalog.update_security(Actor.owner_ui(), bond, %{is_retired: true})

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 1 gehaltene Position ohne Preis — " <>
               "Placeholder Anleihe 2031 3,25%. Details in Vermögen →"
  end

  # User story (#1081, review round):
  # As a reader, I want a last name that ends in a full stop to close the
  # sentence, so that the note never reads "Inc..".
  test "a last name ending in a full stop is not given a second one", %{conn: conn} do
    world = world()
    deliver!(world, create_security!(name: "Harborline Freight Inc.", ticker: "HBF"), "5")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 1 gehaltene Position ohne Preis — " <>
               "Harborline Freight Inc. Details in Vermögen →"
  end

  # User story (#1081, review round; D-3):
  # As a reader whose Overview follows a default view, I want the note to
  # speak of the card's own total, so that accounts outside the view are not
  # named under a figure that never held them.
  test "the note follows the card's default view", %{conn: conn} do
    world = world()
    usd_account!(world, "USD Settlement", "1850")

    {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "euro"})
    :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), world.depot, [bucket.id])
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), world.cash, [bucket.id])
    {:ok, euro} = Buckets.create_view(Actor.owner_ui(), %{name: "Euro", include_all: false})
    :ok = Buckets.set_view_buckets(Actor.owner_ui(), euro, [bucket.id], [])
    :ok = Portfolixir.Settings.set_default_view(euro.id)

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert has_element?(view, "#dashboard-wealth-card", "Euro")
    refute has_element?(view, "[data-role='wealth-card-excluded']")
  end

  # User story (#1081, review round; UX-DR25):
  # As a reader, I want a reserve or credit-line account left out of the
  # total named like any other, since the total leaves its money out too.
  test "a reserve or credit-line account with no rate is named", %{conn: conn} do
    world = world()
    usd_account!(world, "USD Reserve", "500", "reserve")
    usd_account!(world, "USD Kreditlinie", "-250", "credit_line")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    assert note_text(view) ==
             "Nicht in der Summe: 2 Verrechnungskonten ohne Wechselkurs zu EUR — " <>
               "USD Reserve (500,00 USD), USD Kreditlinie (-250,00 USD). " <>
               "Details in Vermögen →"
  end

  # User story (#1081, board 01 ⑤): the "+N" rule's boundary — six names
  # are shown whole, a seventh becomes "+1".
  test "six names show whole, a seventh becomes +1", %{conn: conn} do
    world = world()

    for n <- 1..6, do: usd_account!(world, "USD Konto #{n}", "#{n}0")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    six = note_text(view)
    assert six =~ "6 Verrechnungskonten ohne Wechselkurs zu EUR — USD Konto 1 (10,00 USD), "
    assert six =~ "USD Konto 6 (60,00 USD). Details in Vermögen →"
    refute six =~ "+"

    usd_account!(world, "USD Konto 7", "70")

    {:ok, view, _html} = de_live(conn, "/")
    render_async(view)

    seven = note_text(view)
    assert seven =~ "7 Verrechnungskonten ohne Wechselkurs zu EUR — "
    assert seven =~ "USD Konto 6 (60,00 USD), +1. Details in Vermögen →"
    refute seven =~ "USD Konto 7"
  end

  # User story (#1087's Overview half, board 01):
  # As a German reader of "Fällig",
  # I want its dates in the house format,
  # so that the card reads like the rest of the page.
  #
  # Acceptance criteria:
  # - An upcoming event's date renders through Format.date: DD.MM.YYYY in DE.
  test "the Due dates read in the house format", %{conn: conn} do
    world()
    candidate = create_security!(name: "Nordwind Industrie", ticker: "NWI")
    date = Date.add(Clock.today(), 9)

    {:ok, _} =
      Events.create_event(Actor.owner_ui(), %{
        security_id: candidate.id,
        kind: "earnings",
        timing: "exact",
        source_quality: "primary",
        date: date
      })

    {:ok, view, _html} = de_live(conn, "/")

    assert has_element?(
             view,
             "#dashboard-upcoming [data-role='upcoming-event'] .num",
             Calendar.strftime(date, "%d.%m.%Y")
           )

    refute has_element?(view, "#dashboard-upcoming .num", Date.to_iso8601(date))
  end
end
