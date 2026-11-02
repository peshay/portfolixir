defmodule PortfolixirWeb.BookingDrawerLeglessRowTest do
  # ADR-0015, amendment of 2026-11-01 (#1335; Sprint 22 R10, board 03 ①):
  # a cross-currency trade stored without its settlement legs is corrected in
  # the currency it is stored in, never re-booked as the security's currency
  # in place. Risk tier (ADR-0036): every figure is pinned with an exact
  # Decimal.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.SettlementBackfill
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # Synthetic figures only: the review seed's shape — 10 "Arbolia Inc."-like
  # USD shares bought from a EUR account at 80.00 EUR, fee 5.00, tax 1.00,
  # cash 806.00 EUR, imported with no USD rate stored, so no legs.

  # Every field a booking stores that a correction could move.
  @figures [
    :type,
    :date,
    :portfolio_id,
    :securities_account_id,
    :cash_account_id,
    :security_id,
    :currency_code,
    :quantity,
    :price,
    :fees,
    :taxes,
    :gross_amount,
    :security_amount,
    :settlement_amount,
    :settlement_fx_rate,
    :import_hash
  ]

  setup %{conn: conn} do
    world = base_world(name: "Legless", cash_name: "LL EUR Cash", depot_name: "LL Depot")
    usd = create_security!(name: "Larchwood Test Inc.", ticker: "LTI", currency: "USD")

    {:ok, legless} =
      Ledger.create_transaction(
        Actor.owner_ui(),
        %{
          portfolio_id: world.portfolio.id,
          securities_account_id: world.depot.id,
          cash_account_id: world.cash.id,
          security_id: usd.id,
          type: "buy",
          date: ~D[2026-04-15],
          quantity: "10",
          price: "80",
          fees: "5",
          taxes: "1",
          currency_code: "EUR",
          gross_amount: "806.00"
        },
        import_hash: String.duplicate("a", 64)
      )

    api =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{world: world, usd: usd, legless: legless, api: api}
  end

  defp figures(id), do: Transaction |> Repo.get!(id) |> Map.take(@figures)

  defp open_edit(conn, id) do
    {:ok, view, _html} = live(conn, "/transactions?locale=de")
    render_click(view, "edit_transaction", %{"id" => to_string(id)})
    view
  end

  defp form_inputs(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find("#transaction-form input")
    |> Map.new(fn input ->
      {input |> Floki.attribute("name") |> List.first(),
       input |> Floki.attribute("value") |> List.first()}
    end)
  end

  # The fields the drawer sends on save, as the browser would: the form's
  # inputs and selected options, overlaid with what the operator typed.
  defp submit(view, w, usd, overrides) do
    hidden =
      view
      |> form_inputs()
      |> Enum.flat_map(fn
        {"transaction[" <> rest, value} -> [{String.trim_trailing(rest, "]"), value}]
        _other -> []
      end)
      |> Map.new()

    params =
      hidden
      |> Map.merge(%{
        "type" => "buy",
        "date" => "2026-04-15",
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(usd.id),
        "notes" => ""
      })
      |> Map.merge(overrides)

    view |> element("#transaction-form") |> render_submit(%{"transaction" => params})
  end

  defp api_row(api, id) do
    api
    |> get("/api/v1/transactions/#{id}")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  # User story (#1335; ADR-0015, amendment of 2026-11-01, identity L1):
  # As the operator correcting an imported buy of a USD security paid from
  # my EUR account, stored in EUR because the import had no USD rate,
  # I want the drawer to open it in EUR and save it in EUR,
  # so that a note or a typo fix never re-books 80.00 EUR as 80.00 USD.
  #
  # Acceptance criteria (L1):
  # - The drawer shows "Preis (EUR)" with the stored 80, "Währung: EUR", no
  #   settlement fields, and a Hinweis naming the rate backfill under
  #   Cashflow → "Trades".
  # - Saving without a change, or with a note, changes no stored figure:
  #   currency, quantity, price, fees, taxes, cash and the three legs are
  #   exactly as stored; the API's read differs in the note only.
  # - A price edit to 81 stores 81.00 EUR, every other figure unchanged.
  # - After the rate backfill the same row opens with its legs.
  test "L1: a legless cross-currency buy is corrected in the currency it is stored in",
       %{conn: conn, world: w, usd: usd, legless: tx, api: api} do
    stored = figures(tx.id)
    api_before = api_row(api, tx.id)

    view = open_edit(conn, tx.id)

    refute has_element?(view, "#settlement-fieldset")
    assert has_element?(view, "#transaction-form label span", "Preis (EUR)")
    refute render(view) =~ "Preis (USD)"
    assert form_inputs(view)["transaction[price]"] == "80"
    assert has_element?(view, ~s([data-role="derived-currency"]), "Währung: EUR")

    assert has_element?(
             view,
             ~s([data-role="legless-booking"]),
             "In EUR gebucht — das Wertpapier notiert in USD"
           )

    assert has_element?(view, ~s([data-role="legless-booking"]), "Cashflow → „Trades“")

    # Saved without a change: every stored figure exactly as it was.
    submit(view, w, usd, %{})
    assert figures(tx.id) == stored

    # A note edit saves and changes no figure; the API's read moves only in
    # the note (and the row's own change stamp).
    view = open_edit(conn, tx.id)
    submit(view, w, usd, %{"notes" => "checked against the statement"})

    assert figures(tx.id) == stored
    assert Repo.get!(Transaction, tx.id).notes == "checked against the statement"

    drop = &Map.drop(&1, ["notes", "updated_at", "inserted_at"])
    assert drop.(api_row(api, tx.id)) == drop.(api_before)

    # A price edit to 81 stores 81.00 EUR; nothing else moves.
    view = open_edit(conn, tx.id)
    submit(view, w, usd, %{"price" => "81"})

    corrected = Repo.get!(Transaction, tx.id)
    assert corrected.currency_code == "EUR"
    assert Decimal.equal?(corrected.price, Decimal.new("81.00"))

    assert Map.drop(figures(tx.id), [:price]) == Map.drop(stored, [:price])

    # After the rate backfill the same row opens with its legs: the importer's
    # account-currency form, no Hinweis.
    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-04-15],
          rate: "1.25",
          source: "manual"
        }
      ])

    {:ok, %{updated: 1}} = SettlementBackfill.run(Actor.system_job("settlement_backfill"))

    backfilled = Repo.get!(Transaction, tx.id)
    assert backfilled.currency_code == "EUR"
    assert Decimal.equal?(backfilled.settlement_amount, Decimal.new("800.00"))
    assert Decimal.equal?(backfilled.security_amount, Decimal.new("1000.00"))

    view = open_edit(conn, tx.id)
    refute has_element?(view, ~s([data-role="legless-booking"]))
    assert form_inputs(view)["transaction[settlement_mode]"] == "account"
  end

  # Acceptance criteria (risk tier; the rule is the server's, not the form's):
  # - A save that drops the hidden form state and types a settlement amount
  #   still keeps the row in EUR: no edit in the drawer turns it into a
  #   cross-currency booking (ADR-0015 amendment of 2026-11-01, point 2).
  test "a legless row is never re-booked in the security's currency, whatever the form sends",
       %{conn: conn, world: w, usd: usd, legless: tx} do
    stored = figures(tx.id)
    view = open_edit(conn, tx.id)

    params = %{
      "type" => "buy",
      "date" => "2026-04-15",
      "securities_account_id" => to_string(w.depot.id),
      "security_id" => to_string(usd.id),
      "quantity" => "10",
      "price" => "80",
      "fees" => "5",
      "taxes" => "1",
      "notes" => "",
      "settlement_amount" => "640",
      "settlement_fx_rate" => "0,8"
    }

    view |> element("#transaction-form") |> render_change(%{"transaction" => params})
    refute has_element?(view, "#settlement-fieldset")

    view |> element("#transaction-form") |> render_submit(%{"transaction" => params})

    assert figures(tx.id) == stored
  end

  # Acceptance criteria (the API PATCH, ADR-0015 amendment of 2026-11-01,
  # "What does not change"): a PATCH that corrects the note or the price of
  # a legless row keeps its stored currency and every other figure — the
  # API derives no currency from the security/account pair.
  test "the API PATCH corrects a legless row in its stored currency",
       %{legless: tx, api: api} do
    stored = figures(tx.id)

    api
    |> put_req_header("content-type", "application/json")
    |> patch("/api/v1/transactions/#{tx.id}", %{"transaction" => %{"price" => "81"}})
    |> json_response(200)

    corrected = Repo.get!(Transaction, tx.id)
    assert corrected.currency_code == "EUR"
    assert Decimal.equal?(corrected.price, Decimal.new("81.00"))
    assert Map.drop(figures(tx.id), [:price]) == Map.drop(stored, [:price])
  end
end
