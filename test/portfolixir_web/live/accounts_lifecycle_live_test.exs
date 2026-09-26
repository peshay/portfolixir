defmodule PortfolixirWeb.AccountsLifecycleLiveTest do
  # ADR-0050 §4, §11, §12 on Accounts & depots (L5a, #328; board
  # 01-accounts-lifecycle, pick G1-A: the existing row menu, one dialog per
  # action; board 13-l5a-merged-from, G13.1-A). Every name is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Repo

  defp world do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    giro = cash!(portfolio, "Giro")
    depot = depot!(portfolio, "Depot 1", giro)
    old = cash!(portfolio, "Tagesgeld (alt)")
    depot_2 = depot!(portfolio, "Depot 2", old)
    festgeld = cash!(portfolio, "Festgeld", "USD")

    %{
      portfolio: portfolio,
      giro: giro,
      depot: depot,
      old: old,
      depot_2: depot_2,
      festgeld: festgeld
    }
  end

  # User story:
  # As the operator tidying up my accounts,
  # I want every depot and cash account row to carry its own row menu with
  # rename, merge and delete, ordered by consequence,
  # so that I change an account's identity where the account is listed.
  #
  # Acceptance criteria:
  # - The depot row, the cash row of a pair and a lone cash account each carry
  #   a kebab named for its entity; the repeated row of a shared account
  #   carries none.
  # - The menu lists Rename, Tag separately (the depot row of a pair that is
  #   tagged together only), Merge into…, then Delete last in danger colour.
  # - A split pair's depot row keeps its kebab.
  test "every entity row carries its own row menu, ordered by consequence", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/portfolios")

    assert label(view, "#account-kebab-#{w.depot.id}") == "Actions for Depot 1"
    assert label(view, "#cash-kebab-#{w.giro.id}") == "Actions for Giro"
    assert label(view, "#cash-kebab-#{w.festgeld.id}") == "Actions for Festgeld"

    view |> element("#account-kebab-#{w.depot.id}") |> render_click()

    assert items(view, "#account-row-menu-#{w.depot.id}") ==
             ["Rename", "Tag separately", "Merge into…", "Delete"]

    assert has_element?(
             view,
             "#account-row-menu-#{w.depot.id} .row-context-menu__item--danger:last-child",
             "Delete"
           )

    view |> element("#cash-kebab-#{w.festgeld.id}") |> render_click()
    refute has_element?(view, "#account-row-menu-#{w.depot.id}")
    assert items(view, "#cash-row-menu-#{w.festgeld.id}") == ["Rename", "Merge into…", "Delete"]

    # Split the pair: the depot row keeps its kebab, without "Tag separately".
    view |> element("#account-kebab-#{w.depot.id}") |> render_click()
    view |> element("#split-pair-#{w.depot.id}") |> render_click()
    view |> element("#account-kebab-#{w.depot.id}") |> render_click()
    assert items(view, "#account-row-menu-#{w.depot.id}") == ["Rename", "Merge into…", "Delete"]
  end

  test "the repeated row of a shared cash account carries no kebab", %{conn: conn} do
    w = world()
    depot_3 = depot!(w.portfolio, "Depot 3", w.giro)
    {:ok, view, _html} = live(conn, "/portfolios")

    assert has_element?(view, "#account-row-depot-#{w.depot.id} #cash-kebab-#{w.giro.id}")
    refute has_element?(view, "#account-row-depot-#{depot_3.id} #cash-kebab-#{w.giro.id}")
    assert has_element?(view, "#account-kebab-#{depot_3.id}")
  end

  # User story:
  # As the operator renaming an account,
  # I want the rename dialog to say what happens to the old name,
  # so that I know whether an import that still names it books here.
  #
  # Acceptance criteria:
  # - "Rename" opens a dialog titled for the account, with the name field.
  # - It says the current name stays a former name, so an import naming it
  #   keeps booking here — or, while another account of the kind carries that
  #   name as its live name, that it is not kept and an import naming it books
  #   to that other account (the MCP rename description's two cases).
  # - Saving renames the account; the row updates in place, with the old name
  #   as its former-name line; the dialog closes and no banner appears.
  test "renames a cash account and keeps the old name as a former name", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/portfolios")

    open_menu_item(view, "cash", w.giro.id, "rename")
    assert has_element?(view, "#rename-dialog h2", "Rename — Giro")

    assert view |> element("#rename-dialog [data-role='rename-former-case']") |> render() =~
             "The current name “Giro” stays a former name: an import that still names it keeps booking to this account."

    view |> form("#rename-form", rename: %{name: "Hauptkonto"}) |> render_submit()

    assert Portfolios.get_cash_account(w.giro.id).name == "Hauptkonto"
    assert Portfolios.get_cash_account(w.giro.id).former_names == ["Giro"]
    refute has_element?(view, "#rename-dialog")
    refute has_element?(view, ".alert-success")

    assert view
           |> element("#account-row-depot-#{w.depot.id} [data-role='account-former']")
           |> render() =~
             "former: Giro"
  end

  test "the rename dialog says when the old name is not kept", %{conn: conn} do
    w = world()
    # A name two accounts shared before the name guard existed.
    legacy_cash!(w.portfolio, "Giro")

    {:ok, view, _html} = live(conn, "/portfolios")
    open_menu_item(view, "cash", w.giro.id, "rename")

    assert view |> element("#rename-dialog [data-role='rename-former-case']") |> render() =~
             "Another cash account is also named “Giro”, so the current name is not kept: an import that names it books to that account. Merge or rename that account to change this."
  end

  test "renaming a depot says it keeps booking to this depot", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/portfolios")

    open_menu_item(view, "depot", w.depot.id, "rename")
    assert has_element?(view, "#rename-dialog h2", "Rename — Depot 1")

    assert view |> element("#rename-dialog [data-role='rename-former-case']") |> render() =~
             "an import that still names it keeps booking to this depot."

    view |> form("#rename-form", rename: %{name: "Broker"}) |> render_submit()
    assert Portfolios.get_securities_account(w.depot.id).former_names == ["Depot 1"]
  end

  # User story:
  # As the operator choosing a name another account answers to,
  # I want the refusal at the field, naming the account and the way out,
  # so that I do not route an old export onto the wrong account.
  #
  # Acceptance criteria:
  # - A name another cash account carries as a former name is refused at the
  #   field, naming that account; nothing is written and the dialog stays.
  # - A live name of another account is refused the same way.
  test "refuses a name another account answers to, at the field", %{conn: conn} do
    w = world()
    {:ok, _} = Portfolios.update_cash_account(Actor.owner_ui(), w.festgeld, %{name: "Tagesgeld"})
    {:ok, view, _html} = live(conn, "/portfolios")

    open_menu_item(view, "cash", w.giro.id, "rename")
    html = view |> form("#rename-form", rename: %{name: "Festgeld"}) |> render_submit()

    assert html =~
             "“Festgeld” is a former name of “Tagesgeld”: an import under this name books there. Choose another name or remove it from “Tagesgeld”."

    assert has_element?(view, "#rename-form input[aria-invalid='true']")
    assert Portfolios.get_cash_account(w.giro.id).name == "Giro"

    html = view |> form("#rename-form", rename: %{name: "Tagesgeld (alt)"}) |> render_submit()
    # The way out, as DESIGN.md G1-A asks for every taken name (review
    # finding M-5, board 14 ⑤).
    assert html =~
             "“Tagesgeld (alt)” is already the name of another cash account. Choose another name, or merge or rename that account."

    assert Portfolios.get_cash_account(w.giro.id).name == "Giro"
  end

  # User story (E25 S7, G20 on the L5a rename):
  # As the operator renaming an account on screen,
  # I want a name carrying a character I cannot see refused at the field,
  # naming that character by its code point,
  # so that no hidden text reaches the agent through an account name or,
  # after a merge, through a former name.
  #
  # Acceptance criteria:
  # - A name with a zero-width space (a cash account) or a bidirectional
  #   control (a depot) is refused at the field with the text rule's message
  #   naming the code point; the field is marked invalid and nothing is
  #   written.
  test "refuses a name with an invisible character, naming it", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/portfolios")

    open_menu_item(view, "cash", w.giro.id, "rename")
    html = view |> form("#rename-form", rename: %{name: "Giro\u200B2"}) |> render_submit()

    assert html =~
             "must not contain invisible characters (U+200B); retype the text without them"

    assert has_element?(view, "#rename-form input[aria-invalid='true']")
    assert Portfolios.get_cash_account(w.giro.id).name == "Giro"

    view |> element("#rename-dialog button", "Cancel") |> render_click()
    open_menu_item(view, "depot", w.depot.id, "rename")
    html = view |> form("#rename-form", rename: %{name: "Depot \u202E1"}) |> render_submit()

    assert html =~
             "must not contain invisible characters (U+202E); retype the text without them"

    assert Portfolios.get_securities_account(w.depot.id).name == "Depot 1"
  end

  # User story:
  # As the operator,
  # I want an account's former names listed where I rename it, each
  # removable with a confirmation that says what removing costs,
  # so that I can stop an old name from routing imports here.
  #
  # Acceptance criteria:
  # - The dialog lists the former names under "Former names", each with
  #   Remove, whose confirmation reads "An import that still names '<name>'
  #   will then create a new account." (a new depot for a depot).
  # - Removing takes effect at once, journaled; the dialog stays open and a
  #   typed name stays typed.
  # - The row shows its newest former name and how many more ("+N").
  test "lists former names and removes one with its consequence stated", %{conn: conn} do
    w = world()
    {:ok, giro} = Portfolios.update_cash_account(Actor.owner_ui(), w.giro, %{name: "Giro 2"})
    {:ok, _giro} = Portfolios.update_cash_account(Actor.owner_ui(), giro, %{name: "Hauptkonto"})

    {:ok, view, _html} = live(conn, "/portfolios")

    assert view
           |> element("#account-row-depot-#{w.depot.id} [data-role='account-former']")
           |> render() =~
             "former: Giro 2 +1"

    open_menu_item(view, "cash", w.giro.id, "rename")
    assert former_names(view) == ["Giro", "Giro 2"]

    assert view
           |> element("#rename-dialog [data-role='remove-former-name'][phx-value-name='Giro']")
           |> render() =~
             "data-confirm=\"Remove “Giro” as a former name? An import that still names &#39;Giro&#39; will then create a new account.\""

    view |> element("#rename-form") |> render_change(%{rename: %{name: "Typed"}})

    view
    |> element("#rename-dialog [data-role='remove-former-name'][phx-value-name='Giro']")
    |> render_click()

    assert Portfolios.get_cash_account(w.giro.id).former_names == ["Giro 2"]
    assert former_names(view) == ["Giro 2"]
    assert has_element?(view, "#rename-form input[value='Typed']")

    open_menu_item(view, "depot", w.depot.id, "rename")
    refute has_element?(view, "#rename-dialog [data-role='former-names']")

    {:ok, _} =
      Portfolios.update_securities_account(Actor.owner_ui(), w.depot_2, %{name: "Depot zwei"})

    {:ok, view, _html} = live(conn, "/portfolios")
    open_menu_item(view, "depot", w.depot_2.id, "rename")

    assert view
           |> element("#rename-dialog [data-role='remove-former-name']")
           |> render() =~ "will then create a new depot."
  end

  # User story:
  # As the operator deleting an account that is still in use,
  # I want the refusal to say what uses it and offer the merge instead,
  # so that I never lose history and know the way forward.
  #
  # Acceptance criteria:
  # - Delete on a referenced account opens "Cannot delete" directly — no
  #   confirmation first — naming its bookings and linked depots, counted.
  # - "Merge into…" in that dialog opens the merge's first step for it.
  # - A depot with bookings names its bookings the same way.
  test "a referenced account's delete opens the refusal with Merge instead", %{conn: conn} do
    w = world()
    deposit!(w.portfolio, w.old, "100.00", ~D[2025-01-02])
    deposit!(w.portfolio, w.old, "50.00", ~D[2025-01-03])

    {:ok, view, _html} = live(conn, "/portfolios")
    view |> element("#cash-kebab-#{w.old.id}") |> render_click()

    delete = element(view, "#cash-row-menu-#{w.old.id} [data-role='menu-delete']")
    refute render(delete) =~ "data-confirm"
    render_click(delete)

    dialog = view |> element("#delete-blocked-dialog") |> render()
    assert dialog =~ "Cannot delete"

    assert dialog =~
             "“Tagesgeld (alt)” still has 2 bookings and 1 linked depot (Depot 2) — merge it first."

    assert Portfolios.get_cash_account(w.old.id)

    view |> element("#delete-blocked-dialog [data-role='merge-instead']") |> render_click()
    refute has_element?(view, "#delete-blocked-dialog")
    assert has_element?(view, "#merge-dialog h2", "Merge Tagesgeld (alt)")
    assert has_element?(view, "#merge-dialog", "Step 1 of 2 · Target")
  end

  # User story:
  # As the operator deleting an account nothing uses,
  # I want one confirmation that says it is unused, then the delete,
  # so that destructive actions are confirmed once, never twice.
  #
  # Acceptance criteria:
  # - Delete on an unreferenced account carries one confirmation naming it
  #   and saying it has no bookings and no linked depot; with buckets it adds
  #   that its bucket assignments are removed with it.
  # - Confirming deletes it (journaled, its bucket links first) and the row
  #   disappears.
  test "an unreferenced account is deleted after one confirmation", %{conn: conn} do
    w = world()
    {:ok, tag} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Reserve"})
    :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), w.festgeld, [tag.id])

    {:ok, view, _html} = live(conn, "/portfolios")
    view |> element("#cash-kebab-#{w.festgeld.id}") |> render_click()
    delete = element(view, "#cash-row-menu-#{w.festgeld.id} [data-role='menu-delete']")

    assert render(delete) =~
             "data-confirm=\"Delete “Festgeld”? The account has no bookings and no linked depot. Its bucket assignments are removed with it.\""

    render_click(delete)

    refute Portfolios.get_cash_account(w.festgeld.id)
    refute has_element?(view, "#account-row-cash-#{w.festgeld.id}")
  end

  # User story:
  # As the operator looking at an account that absorbed another,
  # I want the row to say it was merged from that account and when,
  # so that a merge does not look like a rename (board 13, G13.1-A).
  #
  # Acceptance criteria:
  # - The survivor's row carries "merged from <source> · <date>", the newest
  #   merge and "+N" for older ones.
  # - The source's name is not repeated in the "former" line; a former name
  #   it carried is.
  # - In the rename dialog the merged name carries its origin line.
  test "the survivor says what it was merged from", %{conn: conn} do
    w = world()
    source = cash!(w.portfolio, "Sparkonto")

    {:ok, source} =
      Portfolios.update_cash_account(Actor.owner_ui(), source, %{name: "Tagesgeld 2"})

    tagesgeld = cash!(w.portfolio, "Tagesgeld")
    merge_cash!(source, tagesgeld)

    {:ok, view, _html} = live(conn, "/portfolios?locale=de")
    row = "#account-row-cash-#{tagesgeld.id}"
    today = Portfolixir.Clock.today() |> Calendar.strftime("%d.%m.%Y")

    assert view |> element("#{row} [data-role='account-merged-from']") |> render() =~
             "zusammengeführt aus Tagesgeld 2 · #{today}"

    former = view |> element("#{row} [data-role='account-former']") |> render()
    assert former =~ "früher: Sparkonto"
    refute former =~ "Tagesgeld 2"

    # A second merge into the same account: the newest is named, "+1" counts
    # the older one.
    third = cash!(w.portfolio, "Tagesgeld 3")
    merge_cash!(third, tagesgeld)
    {:ok, view, _html} = live(conn, "/portfolios?locale=de")

    assert view |> element("#{row} [data-role='account-merged-from']") |> render() =~
             "zusammengeführt aus Tagesgeld 3 · #{today} +1"

    open_menu_item(view, "cash", tagesgeld.id, "rename")

    assert view |> element("#rename-dialog [data-role='former-names']") |> render() =~
             "zusammengeführt am #{today}"
  end

  # User story:
  # As a German-locale operator,
  # I want the lifecycle controls in German,
  # so that the menu, the dialogs and the confirmations read as the boards do.
  test "translates the lifecycle controls for the German locale", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/portfolios?locale=de")

    view |> element("#cash-kebab-#{w.festgeld.id}") |> render_click()

    assert items(view, "#cash-row-menu-#{w.festgeld.id}") ==
             ["Umbenennen", "Zusammenführen in…", "Löschen"]

    assert view
           |> element("#cash-row-menu-#{w.festgeld.id} [data-role='menu-delete']")
           |> render() =~
             "„Festgeld“ löschen? Das Konto hat keine Buchungen und kein verknüpftes Depot."

    open_menu_item(view, "cash", w.giro.id, "rename")
    assert has_element?(view, "#rename-dialog h2", "Umbenennen — Giro")

    assert view |> element("#rename-dialog [data-role='rename-former-case']") |> render() =~
             "Der bisherige Name „Giro“ bleibt als früherer Name gespeichert: Ein Import, der ihn noch nennt, bucht weiter auf dieses Konto."
  end

  test "a forged or stale lifecycle event changes nothing", %{conn: conn} do
    w = world()
    {:ok, view, _html} = live(conn, "/portfolios")

    for {event, payload} <- [
          {"row_rename", %{"kind" => "cash", "id" => "999999"}},
          {"row_rename", %{"kind" => "vault", "id" => "#{w.giro.id}"}},
          {"row_delete", %{"kind" => "cash", "id" => "abc"}},
          {"row_merge", %{"kind" => "depot"}},
          {"open_account_menu", %{"kind" => "cash", "id" => "-1"}}
        ] do
      render_hook(view, event, payload)
    end

    refute has_element?(view, "#rename-dialog")
    refute has_element?(view, "#merge-dialog")
    assert Portfolios.get_cash_account(w.giro.id)
  end

  # -- helpers ----------------------------------------------------------------

  defp open_menu_item(view, "cash", id, item) do
    view |> element("#cash-kebab-#{id}") |> render_click()
    view |> element("#cash-row-menu-#{id} [data-role='menu-#{item}']") |> render_click()
  end

  defp open_menu_item(view, "depot", id, item) do
    view |> element("#account-kebab-#{id}") |> render_click()
    view |> element("#account-row-menu-#{id} [data-role='menu-#{item}']") |> render_click()
  end

  defp items(view, menu) do
    view
    |> element(menu)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find(".row-context-menu__item")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp former_names(view) do
    view
    |> element("#rename-dialog [data-role='former-names']")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("li [data-role='former-name']")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp label(view, selector) do
    view
    |> element(selector)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("aria-label")
    |> List.first()
  end

  # A second account under one name, as two accounts could share one before
  # the name guard existed (ADR-0050 §4): written past the changeset's guard,
  # journaled like any write.
  defp legacy_cash!(portfolio, name) do
    {:ok, %{account: account}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :account,
        Ecto.Changeset.change(%CashAccount{}, %{
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        })
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "cash_account",
        operation: :create,
        source: :account
      )
      |> Repo.transaction()

    account
  end

  defp merge_cash!(source, target) do
    {:ok, preview} = Lifecycle.preview_cash_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_cash_account(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })
  end

  defp cash!(portfolio, name, currency \\ "EUR") do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: currency
      })

    cash
  end

  defp depot!(portfolio, name, cash) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        cash_account_id: cash.id
      })

    depot
  end

  defp deposit!(portfolio, account, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: account.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: account.currency_code
      })

    tx
  end
end
