defmodule PortfolixirWeb.DialogFieldErrorsDeTest do
  # Sprint 18 pick H8.3 (#921; board ux-design-2026-10-02/08-dialogs-copy,
  # before/after; EXPERIENCE.md "Language (binding)" and "Voice and Tone"):
  # the security dialog and the account create dialog show their field
  # errors in the page's language. A plain changeset message goes through
  # the `errors` domain; the name guard and the former-name guard read in the
  # rename dialog's own words, which address no one; the currency freeze has
  # words of its own, with its counts. The API and MCP keep the English.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, buy!: 3, create_security!: 1, deposit!: 3, put_quote!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Portfolios

  defp german(conn), do: Plug.Test.put_req_cookie(conn, "portfolixir_locale", "de")

  defp field_error(view, form, field) do
    view
    |> element(
      "#{form} input[name$='[#{field}]'] ~ .field-error, #{form} select[name$='[#{field}]'] ~ .field-error"
    )
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.text()
    |> String.trim()
  end

  defp open_depot_form(view) do
    view |> element("#add-account-button") |> render_click()
    view |> element("#account-form-dialog button[phx-value-mode='depot']") |> render_click()
  end

  defp choose_cash(view) do
    view |> element("#account-form-dialog button[phx-value-mode='cash']") |> render_click()
  end

  defp submit_account(view, fields) do
    view
    |> form("#account-dialog-form", %{
      "account" => Map.merge(%{"currency_code" => "EUR", "new_tag" => ""}, fields)
    })
    |> render_submit()
  end

  # User story (#921; pick H8.3, board 08-dialogs-copy):
  # As the operator creating a depot on a German page,
  # I want a refused name to say why in German, in the words the rename
  # dialog already uses,
  # so that I do not read English and an internal "#4" under the field.
  #
  # Acceptance criteria:
  # - A depot name another depot carries reads "„Depot 1“ heißt bereits ein
  #   anderes Depot. Einen anderen Namen wählen oder jenes Depot
  #   zusammenführen oder umbenennen." — impersonal, no "Sie", no id.
  # - A depot name another depot carries as a former name reads the rename
  #   dialog's former-name sentence, naming that depot.
  # - A cash account name another cash account carries reads the cash
  #   account's sentence; a blank one reads "darf nicht leer sein".
  test "the account create dialog's field errors read in German", %{conn: conn} do
    world = base_world(name: "Hauptportfolio", depot_name: "Depot 1", cash_name: "Giro")
    assert Portfolios.default_portfolio(Actor.owner_ui()).id == world.portfolio.id

    {:ok, sued} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Depot 2",
        cash_account_id: world.cash.id
      })

    {:ok, _} = Portfolios.update_securities_account(Actor.owner_ui(), sued, %{name: "Depot Süd"})

    {:ok, view, _html} = live(german(conn), "/portfolios")

    open_depot_form(view)

    submit_account(view, %{
      "depot_name" => "Depot 1",
      "cash_account_id" => "",
      "cash_name" => "Neu"
    })

    assert field_error(view, "#account-dialog-form", "depot_name") ==
             "„Depot 1“ heißt bereits ein anderes Depot. Einen anderen Namen wählen oder jenes Depot zusammenführen oder umbenennen."

    submit_account(view, %{
      "depot_name" => "Depot 2",
      "cash_account_id" => "",
      "cash_name" => "Neu"
    })

    assert field_error(view, "#account-dialog-form", "depot_name") ==
             "„Depot 2“ ist ein früherer Name von „Depot Süd“ — ein Import unter diesem Namen bucht dorthin. Einen anderen Namen wählen oder ihn bei „Depot Süd“ entfernen."

    view |> element("#account-dialog-form button.button-ghost") |> render_click()
    choose_cash(view)
    submit_account(view, %{"cash_name" => "Giro"})

    assert field_error(view, "#account-dialog-form", "cash_name") ==
             "„Giro“ heißt bereits ein anderes Verrechnungskonto. Einen anderen Namen wählen oder jenes Konto zusammenführen oder umbenennen."

    submit_account(view, %{"cash_name" => ""})
    assert field_error(view, "#account-dialog-form", "cash_name") == "darf nicht leer sein"

    assert length(Portfolios.list_securities_accounts()) == 2
  end

  # User story (#921; pick H8.3):
  # As the operator editing a security's master data on a German page,
  # I want its field errors in German,
  # so that a refused value says why in the page's language.
  #
  # Acceptance criteria:
  # - Entering a security by hand, a blank name reads "darf nicht leer
  #   sein"; editing one, a malformed ISIN reads the `errors` domain's German
  #   ISIN sentence.
  # - A currency change on a security with a booking and a quote reads
  #   "steht fest, sobald etwas darauf verweist (1 Buchung, 1 Kurs)".
  test "the security dialog's field errors read in German", %{conn: conn} do
    world = base_world(name: "Wertpapiere")
    security = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    deposit!(world, "1000", ~D[2026-01-02])
    buy!(world, security, quantity: "2", price: "100", date: ~D[2026-01-05])
    put_quote!(security, ~D[2026-01-05], "100")

    {:ok, view, _html} = live(german(conn), "/securities")

    view |> element("#open-new-dialog") |> render_click()

    view
    |> element(~s(button[phx-click="choose_mode"][phx-value-mode="manual"]))
    |> render_click()

    view
    |> form("#security-dialog-form", %{"security" => %{"name" => "", "currency_code" => "EUR"}})
    |> render_submit()

    assert field_error(view, "#security-dialog-form", "name") == "darf nicht leer sein"

    {:ok, view, _html} = live(german(conn), "/securities/#{security.id}")
    view |> element("#detail-edit") |> render_click()

    view
    |> form("#security-dialog-form", %{
      "security" => %{"name" => "Nordwind Industrie AG", "isin" => "DE000000000"}
    })
    |> render_submit()

    assert field_error(view, "#security-dialog-form", "isin") ==
             "ist keine ISIN (zwei Buchstaben, neun Buchstaben oder Ziffern und eine Prüfziffer)"

    view
    |> form("#security-dialog-form", %{
      "security" => %{"name" => "Nordwind Industrie AG", "currency_code" => "USD"}
    })
    |> render_submit()

    assert field_error(view, "#security-dialog-form", "currency_code") ==
             "steht fest, sobald etwas darauf verweist (1 Buchung, 1 Kurs)"
  end

  test "the freeze's counts read in English on an English page", %{conn: conn} do
    world = base_world(name: "Securities")
    security = create_security!(name: "Nordwind Industrie AG", ticker: "NWI")
    deposit!(world, "1000", ~D[2026-01-02])
    buy!(world, security, quantity: "2", price: "100", date: ~D[2026-01-05])
    buy!(world, security, quantity: "1", price: "101", date: ~D[2026-01-06])
    put_quote!(security, ~D[2026-01-05], "100")

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")
    view |> element("#detail-edit") |> render_click()

    view
    |> form("#security-dialog-form", %{
      "security" => %{"name" => "Nordwind Industrie AG", "currency_code" => "USD"}
    })
    |> render_submit()

    assert field_error(view, "#security-dialog-form", "currency_code") ==
             "is frozen once referenced (2 bookings, 1 quote)"
  end

  # User story (#921; pick H8.3, the finding inside the scope):
  # As the operator renaming a depot on a German page,
  # I want the refusal of a taken name to state the fact and the way out
  # without addressing me,
  # so that the dialog keeps the impersonal voice EXPERIENCE.md binds.
  #
  # Acceptance criteria:
  # - The rename dialog's taken-name sentence reads "… Einen anderen Namen
  #   wählen oder jenes Depot zusammenführen oder umbenennen." — no "Sie".
  # - No msgstr of the German catalog addresses the reader as "Sie".
  test "the rename dialog's taken-name refusal is impersonal", %{conn: conn} do
    world = base_world(name: "Umbenennen", depot_name: "Depot 1", cash_name: "Giro")

    {:ok, _second} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        name: "Depot 2",
        cash_account_id: world.cash.id
      })

    {:ok, view, _html} = live(german(conn), "/portfolios")

    view |> element("#account-kebab-#{world.depot.id}") |> render_click()

    view
    |> element("#account-row-menu-#{world.depot.id} [data-role='menu-rename']")
    |> render_click()

    view |> form("#rename-form", rename: %{name: "Depot 2"}) |> render_submit()

    assert view
           |> element("#rename-error")
           |> render()
           |> Floki.parse_fragment!()
           |> Floki.text()
           |> String.trim() ==
             "„Depot 2“ heißt bereits ein anderes Depot. Einen anderen Namen wählen oder jenes Depot zusammenführen oder umbenennen."

    po = File.read!("priv/gettext/de/LC_MESSAGES/default.po")
    refute po =~ ~r/msgstr.*\b(Wählen|führen|benennen|geben|prüfen) Sie\b/
  end
end
