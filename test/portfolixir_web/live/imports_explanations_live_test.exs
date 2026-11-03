defmodule PortfolixirWeb.ImportsExplanationsLiveTest do
  # Board `ux-design-2026-11-03-sprint23-i1` on the Imports preview (Sprint
  # 23, Lane I; I1's anatomy, variant R with its Q1 corrections) and #1339's
  # matched-securities list. Every name, amount and identifier is synthetic.
  use PortfolixirWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Classifications
  alias Portfolixir.Imports
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.Repo

  @fund %{"name" => "Example Fund", "isin" => "DE000EXMPL17", "currency" => "EUR"}

  defp num(digits), do: Jason.Fragment.new(digits)

  defp history do
    [
      %{
        "type" => "DEPOSIT",
        "account" => "Test-Cash",
        "date" => "2026-01-02",
        "currency" => "EUR",
        "amount" => num("2000.00")
      },
      %{
        "type" => "PURCHASE",
        "account" => "Test-Cash",
        "portfolio" => "Depot Muster",
        "date" => "2026-01-15",
        "time" => "10:00",
        "currency" => "EUR",
        "amount" => num("1000.00"),
        "shares" => num("10"),
        "security" => @fund
      }
    ]
  end

  # A delivery with a tax refund: a parser warning, the rest previews.
  defp refund_rows do
    [
      %{
        "type" => "DEPOSIT",
        "account" => "Test-Cash",
        "date" => "2026-02-02",
        "currency" => "EUR",
        "amount" => num("2000.00")
      },
      %{
        "type" => "INBOUND_DELIVERY",
        "portfolio" => "Test-Depot",
        "date" => "2026-02-03",
        "currency" => "EUR",
        "amount" => num("999.60"),
        "shares" => num("10"),
        "security" => %{"name" => "Arbolia Inc.", "currency" => "EUR"},
        "units" => [%{"type" => "TAX", "amount" => num("-0.40")}]
      }
    ]
  end

  defp body(rows), do: Jason.encode!(%{"version" => 1, "transactions" => rows})

  # The history applied once, then a configured security the file never
  # names, bought in the same depot: a re-drop of the history matches the
  # fund, books nothing and leaves the configured one untouched.
  defp world! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "PP Import Target",
        base_currency_code: "EUR"
      })

    {:ok, preview} = Imports.parse_portfolio_performance(body(history()), filename: "h.json")
    {:ok, _result} = Imports.apply(preview, %{portfolio_id: portfolio.id})

    cash = Repo.one!(from(a in CashAccount, where: a.name == "Test-Cash"))
    depot = Repo.one!(from(a in SecuritiesAccount, where: a.name == "Depot Muster"))

    {:ok, leftover} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Leftover Robotics AG",
        isin: "DE000LEFT003",
        currency_code: "EUR"
      })

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        type: "buy",
        date: ~D[2026-01-20],
        currency_code: "EUR",
        security_id: leftover.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        quantity: Decimal.new("1"),
        price: Decimal.new("10"),
        gross_amount: Decimal.new("10")
      })

    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: "Strategy"})

    {:ok, category} =
      Classifications.create_category(Actor.owner_ui(), %{
        classification_id: classification.id,
        name: "Core"
      })

    {:ok, _} =
      Classifications.assign_security(
        Actor.owner_ui(),
        leftover.id,
        classification.id,
        category.id
      )

    %{leftover: leftover}
  end

  defp drop!(view, rows) do
    file_input(view, "#pp-import-form", :pp_file, [
      %{
        name: "synthetic.json",
        content: body(rows),
        type: "application/json",
        last_modified: 1_700_000_000_000
      }
    ])
    |> render_upload("synthetic.json")

    render_async(view)
  end

  defp german(conn), do: put_req_header(conn, "accept-language", "de-DE,de;q=0.9")

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # User story (Sprint 23, Lane I, Imports; board
  # ux-design-2026-11-03-sprint23-i1 ③ ⑦):
  # As the operator previewing a Portfolio Performance export,
  # I want each note cut to two lines with its remedy in view, and the
  # matched-securities list to stay open while I map,
  # so that the mapping stays near the top and nothing a note says is lost.
  #
  # Acceptance criteria:
  # - „Alle 2 Einträge sind bereits importiert. …“ (`nothing-to-import`)
  #   clamps: `data-note--clamped`, an id, the sentence in its text.
  # - The configured-securities note (`unmatched-config`) clamps: its title
  #   and its remedy sentence stay in the text; the security links, where
  #   the remedy is made, sit in its actions and not in the text.
  # - The parser warnings clamp the same way: the heading and the rows in
  #   the text, the copy button in the actions.
  # - #1339: „1 Wertpapier passt zu bestehenden Einträgen“ is a disclosure
  #   with an id and `phx-hook="DisclosureState"`, so a patch keeps it open.
  # - „Quellformat: JSON“ stays.
  test "the preview's notes clamp with their remedy in view, and the matched list stays open",
       %{conn: conn} do
    %{leftover: leftover} = world!()

    {:ok, view, _html} = live(german(conn), "/imports")
    drop!(view, history())

    assert has_element?(view, "p.muted", "Quellformat: JSON")

    nothing = "#nothing-to-import-note.data-note--clamped[data-role='nothing-to-import']"

    assert text(view, nothing <> " .data-note__text") ==
             "Alle 2 Einträge sind bereits importiert. Der Import legt nichts an: " <>
               "keine Buchung, kein Konto, kein Depot, kein Wertpapier."

    config = "#import-unmatched-config.data-note--clamped[data-role='unmatched-config']"

    assert text(view, config <> " .data-note__text h3") ==
             "Konfigurierte Wertpapiere, die dieser Import nicht berührt"

    assert text(view, config <> " .data-note__text p") =~ ~r/Abhilfe: den ISIN-Wechsel/

    assert has_element?(
             view,
             config <> " .data-note__actions li a[href='/securities/#{leftover.id}']",
             "Leftover Robotics AG"
           )

    refute has_element?(view, config <> " .data-note__text a")

    assert has_element?(
             view,
             "details#import-matched-securities[data-role='matched-securities'][phx-hook='DisclosureState']"
           )

    assert text(view, "#import-matched-securities > summary") ==
             "1 Wertpapier passt zu bestehenden Einträgen"

    {:ok, warned, _html} = live(german(conn), "/imports")
    drop!(warned, refund_rows())

    box = "#parser-warnings-box.data-note--clamped[data-role='parser-warnings']"
    assert text(warned, box <> " .data-note__text h3") == "Parser-Warnungen"
    assert text(warned, box <> " .data-note__text pre") =~ ~r/^Eintrag 2: Einlieferung/
    assert has_element?(warned, box <> " .data-note__actions button#copy-parser-warnings")
    refute has_element?(warned, box <> " .data-note__text button")
  end
end
