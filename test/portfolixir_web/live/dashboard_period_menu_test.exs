defmodule PortfolixirWeb.DashboardPeriodMenuTest do
  # Sprint 32 T4 (I59; ADR-0062's amendment of 2026-11-25, point 6; board
  # ux-design-2026-11-25-sprint32/04 ① and ②; plan D-5): the top bar shows
  # the quick choice as chips and one button with the active period's name
  # (and its dates beside it for an own period); the button opens the menu
  # in four groups — rolling, calendar, own, year — with ★ to add or remove
  # a quick choice, and „Eigenen Zeitraum anlegen …“ with its dialog. The
  # browser half (the keyboard's focus, the sheet at a phone's width) is
  # test/browser/dashboard_period_menu_test.exs. Every name is synthetic.
  #
  # group: :periods -- a period's create takes the count lock of
  # `Portfolixir.LockTable` row 31; every module that creates one joins it.
  use PortfolixirWeb.ConnCase, async: true, group: :periods

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers
  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Periods
  alias PortfolixirWeb.Format

  defp seed do
    world = base_world()

    {:ok, security} =
      Portfolixir.Catalog.create_security(Actor.owner_ui(), %{name: "ACME", currency_code: "EUR"})

    first = Date.new!(Clock.today().year - 1, 1, 10)
    buy!(world, security, quantity: "10", price: "100", date: first)
    put_quote!(security, first, "100")
    put_quote!(security, Clock.today(), "120")
    world
  end

  defp german(conn), do: put_preference_cookie(conn, "portfolixir_locale", "de")

  defp text(nodes),
    do: nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/, " ") |> String.trim()

  defp document(view), do: view |> render() |> Floki.parse_document!()

  defp find(view, selector), do: view |> document() |> Floki.find(selector)

  defp chips(view), do: view |> find("[data-role='dashboard-period'] button") |> Enum.map(&text/1)

  defp toggle(view), do: view |> element("[data-role='period-menu-toggle']") |> render_click()

  defp option(view, key),
    do: view |> element("[data-role='period-option'][data-period='#{key}']") |> render_click()

  defp star(view, key),
    do: view |> element("[data-role='period-star'][data-period='#{key}']") |> render_click()

  defp label(view), do: view |> find("[data-role='period-menu-label']") |> text()

  # User story:
  # As the operator,
  # I want only my quick choice in the bar and every other period one
  # click away in one menu,
  # so that the bar stays calm and nothing I might want is missing.
  #
  # Acceptance criteria:
  # - With nothing stored, the bar shows 1W, lfd. Monat, YTD, 1J, Max and
  #   the button „Zeitraum ▾“, closed (aria-expanded false).
  # - The button opens the menu: four groups, each a group named by its
  #   heading — „Rollierend · bis heute“ (1T to Max), „Kalender“ (lfd.
  #   Monat, Vormonat, lfd. Quartal, Vorquartal, Q1 to Q4 of this year,
  #   YTD, Vorjahr), „Eigene · gespeichert“, „Jahr“ (this year and the five
  #   before); a quarter not yet begun is drawn and cannot be chosen.
  # - A pick in the menu moves the address (`?period=3m`), closes the menu
  #   and names the period on the button; Escape closes it without a pick.
  # - Each option's ★ is pressed exactly for the quick choice.
  test "the bar holds the quick choice and one button; the menu has four groups", %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/")

    assert chips(view) == ["1W", "lfd. Monat", "YTD", "1J", "Max"]
    assert label(view) == "Zeitraum"

    assert has_element?(
             view,
             "[data-role='period-menu-toggle'][aria-expanded='false'][aria-controls='dashboard-period-menu']"
           )

    refute has_element?(view, "#dashboard-period-menu")

    toggle(view)
    assert has_element?(view, "[data-role='period-menu-toggle'][aria-expanded='true']")

    groups =
      view
      |> find("#dashboard-period-menu [role='group']")
      |> Enum.map(fn group ->
        [labelled_by] = Floki.attribute(group, "aria-labelledby")
        heading = view |> find("#" <> labelled_by) |> text()

        keys =
          group |> Floki.find("[data-role='period-option']") |> Floki.attribute("data-period")

        {heading, keys}
      end)

    year = Clock.today().year

    assert [
             {"Rollierend · bis heute", rolling},
             {"Kalender", calendar},
             {"Eigene · gespeichert", []},
             {"Jahr", years}
           ] = groups

    assert rolling == Periods.rolling()
    assert calendar == Periods.calendar()
    assert years == Enum.map(year..(year - 5)//-1, &"year:#{&1}")

    for key <- Periods.calendar() do
      begun? = match?({:ok, _}, Periods.resolve(key))

      disabled =
        view
        |> find("[data-role='period-option'][data-period='#{key}']")
        |> Floki.attribute("disabled")

      assert disabled == [] == begun?, key
    end

    pressed =
      view
      |> find("[data-role='period-star'][aria-pressed='true']")
      |> Floki.attribute("data-period")

    assert Enum.sort(pressed) == Enum.sort(~w(1w mtd ytd 1y max))

    option(view, "3m")
    assert_patch(view, "/?period=3m")
    refute has_element?(view, "#dashboard-period-menu")
    assert label(view) == "3M"

    toggle(view)
    view |> element("#dashboard-period-menu") |> render_keydown(%{"key" => "Escape"})
    refute has_element?(view, "#dashboard-period-menu")
    assert_push_event(view, "dashboard-edit-focus", %{ids: ["dashboard-period-menu-toggle"]})
  end

  # User story:
  # As the operator,
  # I want a star beside each period that puts it into the bar or takes it
  # out, stored on the server,
  # so that my bar is the same on every device.
  #
  # Acceptance criteria:
  # - ☆ on Vorquartal adds it at the end of the quick choice, stored; the
  #   chip appears in the bar. ★ on 1W takes it out.
  # - A seventh is refused with a sentence in the menu, nothing stored.
  test "a star adds a period to the quick choice and takes it out", %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/")
    toggle(view)

    star(view, "prev_quarter")
    assert Periods.quick_choice().keys == ~w(1w mtd ytd 1y max prev_quarter)
    assert chips(view) == ["1W", "lfd. Monat", "YTD", "1J", "Max", "Vorquartal"]

    assert has_element?(
             view,
             "[data-role='period-star'][data-period='prev_quarter'][aria-pressed='true'][aria-label='Schnellwahl: Vorquartal']"
           )

    star(view, "1w")
    assert Periods.quick_choice().keys == ~w(mtd ytd 1y max prev_quarter)

    star(view, "1w")
    star(view, "6m")
    assert length(Periods.quick_choice().keys) == 6

    star(view, "3y")
    assert length(Periods.quick_choice().keys) == 6
    assert has_element?(view, "[data-role='period-say']", "höchstens 6")
  end

  # User story:
  # As the operator,
  # I want to make a period of my own in the menu, open-ended or fixed,
  # and see it applied at once with its dates beside its name,
  # so that „Seit Umschichtung“ never leaves me guessing what it spans.
  #
  # Acceptance criteria:
  # - „Eigenen Zeitraum anlegen …“ opens the dialog (a native dialog): Name,
  #   Von, Bis „heute“ or a date, „in der Schnellwahl zeigen“.
  # - An empty name is refused in the dialog with its reason; nothing is
  #   stored.
  # - „Speichern und anwenden“ stores it (journaled under the UI), closes
  #   the dialog, applies it (`?period=saved:<id>`): the button names it
  #   and its dates stand beside it, from its first day to today; checked,
  #   it joins the quick choice.
  # - Its ⋯ in the menu opens the same dialog filled in: a change is
  #   stored with the lock_version read, „Löschen“ deletes it and the menu
  #   says so.
  test "an own period is made, applied, changed and deleted from the menu", %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/")
    toggle(view)

    view |> element("[data-role='period-add']") |> render_click()
    assert has_element?(view, "dialog#period-dialog[phx-hook='ModalDialog']")

    view
    |> form("#period-form", period: %{name: "", from: "2025-03-01", to_mode: "today"})
    |> render_submit()

    assert has_element?(
             view,
             "#period-dialog [data-role='period-field-error'][data-field='name']"
           )

    assert Periods.list_saved() == []

    view
    |> form("#period-form",
      period: %{name: "Seit Umschichtung", from: "2025-03-01", to_mode: "today", quick: "true"}
    )
    |> render_submit()

    [own] = Periods.list_saved()
    key = "saved:#{own.id}"
    assert_patch(view, "/?" <> URI.encode_query(%{"period" => key}))
    refute has_element?(view, "#period-dialog")
    assert label(view) == "Seit Umschichtung"

    assert view |> find("[data-role='period-dates']") |> text() ==
             Format.date(~D[2025-03-01]) <> " – " <> Format.date(Clock.today())

    assert key in Periods.quick_choice().keys
    assert "Seit Umschichtung" in chips(view)

    toggle(view)

    assert view |> find("[data-role='period-own'] [data-role='period-option']") |> text() =~
             "Seit Umschichtung"

    view |> element("[data-role='period-edit'][data-period='#{key}']") |> render_click()

    view
    |> form("#period-form",
      period: %{
        name: "Seit Umschichtung",
        from: "2025-04-01",
        to_mode: "date",
        to: "2025-12-31",
        quick: "true"
      }
    )
    |> render_submit()

    assert %{from: ~D[2025-04-01], to: ~D[2025-12-31], lock_version: 2} =
             Periods.get_saved(own.id)

    assert view |> find("[data-role='period-dates']") |> text() ==
             Format.date(~D[2025-04-01]) <> " – " <> Format.date(~D[2025-12-31])

    toggle(view)
    view |> element("[data-role='period-edit'][data-period='#{key}']") |> render_click()
    view |> element("#period-dialog [data-role='period-delete']") |> render_click()

    assert Periods.list_saved() == []
    assert has_element?(view, "[data-role='period-say']", "Seit Umschichtung")
    refute "Seit Umschichtung" in chips(view)
  end

  # User story:
  # As the operator saving an own period in the dialog while my agent
  # changes, deletes or adds periods,
  # I want each refusal said in the dialog, the dialog kept open and
  # nothing stored over the other's change,
  # so that no change is lost unseen and I know why nothing happened.
  #
  # Acceptance criteria:
  # - A period the agent changed since the dialog read it: „Dieser
  #   Zeitraum wurde anderswo geändert …“, the dialog shows it as stored
  #   (the agent's name), and the store is the agent's.
  # - A period the agent deleted since: „Der Zeitraum konnte nicht
  #   gespeichert werden.“, nothing stored again.
  # - With fifty stored, a new one: „Es sind fünfzig eigene Zeiträume
  #   gespeichert …“, nothing stored.
  test "the dialog says a stale, a deleted and a 51st period, storing nothing", %{conn: conn} do
    seed()

    {:ok, own} =
      Periods.create_saved(Actor.owner_ui(), %{"name" => "Sommer", "from" => "2025-06-01"})

    key = "saved:#{own.id}"
    {:ok, view, _html} = conn |> german() |> live("/")
    toggle(view)
    view |> element("[data-role='period-edit'][data-period='#{key}']") |> render_click()

    {:ok, _} =
      Periods.replace_saved(Actor.api_token_rw("mcp"), own.id, %{
        "name" => "Sommer (Agent)",
        "from" => "2025-07-01",
        "to" => nil,
        "lock_version" => 1
      })

    submit = fn name ->
      view
      |> form("#period-form", period: %{name: name, from: "2025-06-15", to_mode: "today"})
      |> render_submit()
    end

    submit.("Sommer (ich)")

    assert has_element?(
             view,
             "#period-dialog [role='alert']",
             "Dieser Zeitraum wurde anderswo geändert"
           )

    assert has_element?(view, "#period-form input[name='period[name]'][value='Sommer (Agent)']")
    assert %{name: "Sommer (Agent)", lock_version: 2} = Periods.get_saved(own.id)

    {:ok, _} = Periods.delete_saved(Actor.api_token_rw("mcp"), own.id)
    submit.("Sommer (ich)")

    assert has_element?(
             view,
             "#period-dialog [role='alert']",
             "Der Zeitraum konnte nicht gespeichert werden."
           )

    assert Periods.list_saved() == []

    for n <- 1..50 do
      {:ok, _} =
        Periods.create_saved(Actor.api_token_rw("mcp"), %{
          "name" => "Synthetic #{n}",
          "from" => "2025-01-01"
        })
    end

    view
    |> element("#period-dialog button.button-ghost[phx-click='period_dialog_close']")
    |> render_click()

    toggle(view)
    view |> element("[data-role='period-add']") |> render_click()
    submit.("Einundfünfzig")

    assert has_element?(
             view,
             "#period-dialog [role='alert']",
             "Es sind fünfzig eigene Zeiträume gespeichert"
           )

    assert length(Periods.list_saved()) == 50
  end

  # User story:
  # As the operator whose quick choice is full, or who stars an own period
  # my agent deleted while the menu was open,
  # I want the menu to say why the quick choice did not take it,
  # so that a star never seems to work when nothing was stored.
  #
  # Acceptance criteria:
  # - With six in the quick choice, a period saved with „in der
  #   Schnellwahl zeigen“ is stored and applied, and the menu says the
  #   quick choice holds at most 6; the quick choice is unchanged.
  # - ☆ on an own period deleted since the menu was drawn: „Die
  #   Schnellwahl konnte nicht gespeichert werden.“, the quick choice
  #   unchanged.
  test "a full quick choice and a deleted period's star are said, nothing stored", %{conn: conn} do
    seed()
    six = ~w(1d 1w 1m 3m 6m 1y)
    {:ok, _} = Periods.put_quick_choice(Actor.owner_ui(), six)

    {:ok, view, _html} = conn |> german() |> live("/")
    toggle(view)
    view |> element("[data-role='period-add']") |> render_click()

    view
    |> form("#period-form",
      period: %{name: "Seit Umschichtung", from: "2025-03-01", to_mode: "today", quick: "true"}
    )
    |> render_submit()

    [own] = Periods.list_saved()
    assert_patch(view, "/?" <> URI.encode_query(%{"period" => "saved:#{own.id}"}))
    assert has_element?(view, "[data-role='period-say']", "höchstens 6")
    assert Periods.quick_choice().keys == six

    {:ok, _} = Periods.put_quick_choice(Actor.owner_ui(), ~w(1w 1y))
    toggle(view)
    {:ok, _} = Periods.delete_saved(Actor.api_token_rw("mcp"), own.id)
    star(view, "saved:#{own.id}")

    assert has_element?(
             view,
             "[data-role='period-say']",
             "Die Schnellwahl konnte nicht gespeichert werden."
           )

    assert Periods.quick_choice().keys == ~w(1w 1y)
  end

  # User story (T3's menu half):
  # As the operator whose agent deleted a period of my quick choice,
  # I want the menu to say once that it left the bar,
  # so that a chip does not vanish without a word.
  #
  # Acceptance criteria:
  # - The bar leaves the deleted period out; the open menu says, in one
  #   sentence, that an own period of the quick choice was deleted.
  # - The next star stores the choice without it, and the sentence is gone.
  test "a deleted period of the quick choice drops out, said once in the menu", %{conn: conn} do
    seed()

    {:ok, summer} =
      Periods.create_saved(Actor.owner_ui(), %{
        "name" => "Sommer 2026",
        "from" => "2026-06-01",
        "to" => "2026-08-31"
      })

    {:ok, _} = Periods.put_quick_choice(Actor.owner_ui(), ["1w", "saved:#{summer.id}", "1y"])
    {:ok, _} = Periods.delete_saved(Actor.api_token_rw("mcp"), summer.id)

    {:ok, view, _html} = conn |> german() |> live("/")
    assert chips(view) == ["1W", "1J"]
    toggle(view)

    assert [note] = find(view, "[data-role='period-quick-dropped']")
    assert text(note) =~ "gelöscht"

    star(view, "max")
    assert Periods.quick_choice() == %{keys: ~w(1w 1y max), default: false, dropped: []}
    refute has_element?(view, "[data-role='period-quick-dropped']")
  end

  # User story (S32 closing act; board 04 ②):
  # As the operator who sees a ★ beside every period,
  # I want the menu to say what the star means and why a quarter is drawn
  # dashed or twice,
  # so that I need not guess.
  #
  # Acceptance criteria:
  # - The open menu ends with the board's footnote: ★ is the bar's quick
  #   choice and a click takes a period in or out; a quarter not yet begun
  #   is drawn dashed and cannot be chosen; „lfd. Quartal“ and this
  #   quarter's chip („Q4 26“) are the same quarter today, one moving on,
  #   the other staying.
  test "the menu's footnote says what ★ means", %{conn: conn} do
    seed()
    {:ok, view, _html} = conn |> german() |> live("/")
    refute has_element?(view, "[data-role='period-menu-note']")
    toggle(view)

    today = Clock.today()
    quarter = "Q#{div(today.month - 1, 3) + 1} #{rem(today.year, 100)}"

    assert [note] = find(view, "#dashboard-period-menu [data-role='period-menu-note']")
    note = text(note)
    assert note =~ "★ = in der Leiste als Schnellwahl"
    assert note =~ "ein Klick auf den Stern nimmt einen Zeitraum hinein oder heraus"
    assert note =~ "gestrichelt und ist nicht wählbar"
    assert note =~ "„lfd. Quartal“ und „#{quarter}“ sind heute dasselbe Quartal"
  end
end
