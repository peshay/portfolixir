defmodule PortfolixirWeb.PrivacyOpenStatesTest do
  # The privacy mode in the states a page opens — a flow's preview, a
  # drawer, a dialog — which the route walk (privacy_mode_routes_test.exs)
  # never opens (fix round of the Sprint 26 closing act, privacy lens): each
  # state is opened with the mode on, and its markup, its text and what it
  # hands the clipboard name no amount or quantity, and draw no hidden figure
  # as its stand-in text. Every name and amount is synthetic.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest
  import PortfolixirWeb.PreferenceCookieHelpers

  import Portfolixir.WorldFixtures,
    only: [add_depot: 2, base_world: 1, deposit!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Imports
  alias Portfolixir.Imports.PortfolioPerformance
  alias Portfolixir.Imports.PreviewStore
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias PortfolixirWeb.PrivacyMode

  @session_token "PRIVACYOPENSTATES0000000"

  defp masked(conn, locale \\ "de") do
    conn
    |> init_test_session(%{"_csrf_token" => @session_token})
    |> put_preference_cookie("portfolixir_privacy", "on")
    |> put_preference_cookie("portfolixir_locale", locale)
  end

  defp upload(view, name, content, type) do
    view
    |> file_input("#pp-import-form", :pp_file, [
      %{name: name, content: content, type: type, last_modified: 1_700_000_000_000}
    ])
    |> render_upload(name)

    render_async(view)
  end

  defp text(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # An amount in German or English form, a quantity its unit names, and
  # the stand-in text where the bar belongs.
  @amount ~r/(?<![\d.,])[+\-−]?\d{1,3}(?:[.,]\d{3})*[.,]\d+(?![\d.,])/u
  @quantity ~r/(?<![\d.,])\d[\d.,]*\s*(Stück|shares?|units?)(?![\p{L}])/u

  defp refute_figures(label, text) do
    assert Regex.scan(@amount, text) == [], "#{label} names an amount: #{text}"
    assert Regex.scan(@quantity, text) == [], "#{label} names a quantity: #{text}"
  end

  defp refute_stand_in(label, text) do
    refute String.contains?(text, PrivacyMode.text()),
           "#{label} draws a hidden figure as its text, not as the bar: #{text}"
  end

  # The bar's markup inside an attribute value (an input's value, a title):
  # a hidden figure a template put where no markup can go.
  defp refute_mask_in_attributes(label, html) do
    leaked =
      html
      |> Floki.parse_fragment!()
      |> Floki.find("*")
      |> Enum.flat_map(fn {_tag, attributes, _children} ->
        for {name, value} <- attributes,
            String.contains?(value, "pf-mask"),
            not (name == "class" and value == "pf-mask"),
            do: {name, value}
      end)

    assert leaked == [], "#{label} holds the bar's markup in an attribute: #{inspect(leaked)}"
  end

  describe "the import preview" do
    setup do
      {:ok, _portfolio} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{
          name: "PP Import Target",
          base_currency_code: "EUR"
        })

      on_exit(fn -> PreviewStore.delete(PreviewStore.key_for(@session_token)) end)
      :ok
    end

    # User story (fix round of the Sprint 26 closing act, privacy lens, S2):
    # As the operator who imports an export while sharing my screen with
    # the privacy mode on,
    # I want the preview's parser warnings to hide the file's amounts,
    # so that a mismatched Gesamtpreis does not print my figures on the
    # screen or into the clipboard.
    #
    # Acceptance criteria:
    # - The warning of a row whose Gesamtpreis contradicts its Betrag names
    #   the row and the columns, each figure drawn as the bar; no figure of
    #   the file is in the warnings' markup, and no stand-in text either.
    # - The copy button hands the clipboard the same warning with each
    #   figure as the stand-in text „••••“ (a clipboard holds no markup), no
    #   figure of the file.
    # - With the mode off, the warning reads as before, its figures as the
    #   file wrote them.
    test "a Gesamtpreis warning hides the file's figures on the screen and in the clipboard",
         %{conn: conn} do
      csv = File.read!("priv/demo/pp_csv_gesamtpreis_demo.csv")

      {:ok, view, _html} = live(masked(conn), "/imports")
      upload(view, "gesamtpreis.csv", csv, "text/csv")

      box = view |> element("#parser-warnings-box pre") |> render()
      shown = text(box)

      assert shown =~ "Zeile 5: Gesamtpreis"
      assert shown =~ "passt nicht zu Betrag"
      assert box =~ "pf-mask"
      refute_figures("the warnings box", box)
      refute_stand_in("the warnings box", shown)

      view |> element("#copy-parser-warnings") |> render_click()
      assert_push_event(view, "copy-to-clipboard", %{text: copied})

      assert copied =~ "Zeile 5: Gesamtpreis #{PrivacyMode.text()} passt nicht zu Betrag"
      refute_figures("the copied warnings", copied)

      PreviewStore.delete(PreviewStore.key_for(@session_token))

      {:ok, plain, _html} =
        live(
          conn
          |> init_test_session(%{"_csrf_token" => @session_token})
          |> put_preference_cookie("portfolixir_locale", "de"),
          "/imports"
        )

      upload(plain, "gesamtpreis.csv", csv, "text/csv")

      assert plain |> element("#parser-warnings-box pre") |> render() |> text() =~
               "Zeile 5: Gesamtpreis 845,00 passt nicht zu Betrag 850,00"
    end

    # User story (fix round of the Sprint 26 closing act, privacy lens, S2):
    # As the operator who drops an export again with the privacy mode on,
    # I want a refused row's "already booked" line to hide the stored
    # booking's figures and the file's, each drawn as the bar,
    # so that neither reaches the screen, as text or as its stand-in.
    #
    # Acceptance criteria:
    # - "Eintrag 3: Buchung mit einer negativen Gebühr ([bar]) … bereits
    #   gebucht: Kauf vom 03.03.2026, Arbolia Inc., [bar] Stück, [bar] EUR auf
    #   Test-Cash, von Hand erfasst." — no figure and no stand-in text.
    # - The refused delivery's refund („Steuererstattung [bar]“) too.
    test "an already-booked line draws every figure as the bar", %{conn: conn} do
      arbolia =
        ~s("security": {"name": "Arbolia Inc.", "isin": "DE000ACME016", "currency": "EUR"})

      history = [
        ~s({"type": "DEPOSIT", "account": "Test-Cash", "date": "2026-02-02",
          "currency": "EUR", "amount": "2000.00"}),
        ~s({"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
          "date": "2026-02-04", "currency": "EUR", "amount": "501.00", "shares": "5",
          #{arbolia}, "units": [{"type": "FEE", "amount": "1.00"}]})
      ]

      refused = [
        ~s({"type": "PURCHASE", "account": "Test-Cash", "portfolio": "Test-Depot",
          "date": "2026-03-03", "currency": "EUR", "amount": "1003.00", "shares": "10",
          #{arbolia},
          "units": [{"type": "FEE", "amount": "5.00"}, {"type": "FEE", "amount": "-2.00"}]}),
        ~s({"type": "INBOUND_DELIVERY", "portfolio": "Test-Depot", "date": "2026-03-04",
          "currency": "EUR", "amount": "999.60", "shares": "4", #{arbolia},
          "units": [{"type": "TAX", "amount": "-0.40"}]})
      ]

      body = fn rows -> ~s({"version": 1, "transactions": [#{Enum.join(rows, ",")}]}) end
      portfolio = Portfolios.default_portfolio(Actor.owner_ui())
      {:ok, parsed} = PortfolioPerformance.parse(body.(history), filename: "history.json")
      {:ok, _result} = Imports.apply(parsed, %{portfolio_id: portfolio.id})
      by_hand!(portfolio)

      {:ok, view, _html} = live(masked(conn), "/imports")
      upload(view, "history.json", body.(history ++ refused), "application/json")

      box = view |> element("#parser-warnings-box pre") |> render()
      shown = text(box)

      assert shown =~ "bereits gebucht: Kauf vom 03.03.2026, Arbolia Inc."
      assert shown =~ "Einlieferung mit Steuererstattung"
      refute_figures("the already-booked line", box)
      refute_stand_in("the already-booked line", shown)
    end
  end

  describe "the notes-only drawer" do
    # User story (fix round of the Sprint 26 closing act, privacy lens, S2):
    # As the operator who opens "Edit" on a cash transfer with the privacy
    # mode on,
    # I want its fixed facts to show each figure as the bar,
    # so that the drawer neither prints the amount nor the bar's markup as
    # a field's text.
    #
    # Acceptance criteria:
    # - The amount fact is no input: a static element in its place holds
    #   the bar, and no attribute of the drawer holds the bar's markup.
    # - The facts that are no figure (type, date, accounts) keep their
    #   disabled controls with their values.
    # - With the mode off, the amount is the disabled input with its value,
    #   as before.
    test "a fixed amount is the bar in a static element, never an input's value", %{conn: conn} do
      world = base_world(name: "Masked Drawer", cash_name: "Girokonto", depot_name: "Depot 1")
      deposit!(world, "1500", ~D[2026-09-03])
      savings = add_depot(world.portfolio, cash_name: "Tagesgeld", depot_name: "Depot 2")

      {:ok, transfer} =
        Ledger.create_transaction(Actor.owner_ui(), %{
          type: "cash_transfer",
          portfolio_id: world.portfolio.id,
          cash_account_id: world.cash.id,
          counter_cash_account_id: savings.cash.id,
          gross_amount: "1500",
          currency_code: "EUR",
          date: ~D[2026-09-03]
        })

      view = open_edit(masked(conn, "en"), transfer)
      facts = view |> element("#booking-facts") |> render()

      refute_mask_in_attributes("the drawer's facts", facts)
      refute has_element?(view, "#booking-facts [name='note[gross_amount]']")
      assert has_element?(view, "#booking-facts [data-fact='gross_amount'] .pf-mask")
      refute_figures("the drawer's facts", facts)
      refute_stand_in("the drawer's facts", text(facts))

      assert has_element?(
               view,
               "#booking-facts input[name='note[date]'][disabled][value='2026-09-03']"
             )

      plain = open_edit(conn, transfer)

      assert has_element?(
               plain,
               "#booking-facts input[name='note[gross_amount]'][disabled][value='1,500.00']"
             )
    end
  end

  defp open_edit(conn, tx) do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#tx-kebab-#{tx.id}") |> render_click()
    view |> element("#tx-edit-#{tx.id}") |> render_click()
    view
  end

  defp by_hand!(portfolio) do
    [cash] = Portfolios.list_cash_accounts_for_portfolio(portfolio.id)
    [depot] = Portfolios.list_securities_accounts_for_portfolio(portfolio.id)
    [security] = Catalog.list_securities()

    {:ok, transaction} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        type: "buy",
        date: ~D[2026-03-03],
        security_id: security.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        currency_code: "EUR",
        quantity: Decimal.new("10"),
        price: Decimal.new("100.00"),
        fees: Decimal.new("3.00"),
        taxes: Decimal.new("0")
      })

    transaction
  end
end
