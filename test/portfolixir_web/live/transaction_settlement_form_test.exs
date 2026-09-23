defmodule PortfolixirWeb.TransactionSettlementFormTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  import Portfolixir.WorldFixtures, only: [base_world: 1, create_security!: 1]

  alias Portfolixir.Fx
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Repo

  # Synthetic figures only: EUR hub, 1 EUR = 1.10 USD on the booking date, so
  # one USD is 0.909090… EUR.

  setup do
    world = base_world(name: "Settle Form", cash_name: "SF EUR Cash", depot_name: "SF Depot")
    usd = create_security!(name: "Kestrel Test Co", ticker: "KTC", currency: "USD")
    eur = create_security!(name: "Heron Test AG", ticker: "HTA", currency: "EUR")

    {:ok, _} =
      Fx.upsert_many([
        %{
          base_currency: "EUR",
          quote_currency: "USD",
          date: ~D[2026-04-01],
          rate: "1.10",
          source: "manual"
        }
      ])

    %{world: world, usd: usd, eur: eur}
  end

  defp open(conn) do
    {:ok, view, _html} = live(conn, "/transactions")
    view |> element("#open-booking") |> render_click()
    view
  end

  defp form_params(w, security, overrides) do
    Map.merge(
      %{
        "type" => "buy",
        "date" => "2026-04-01",
        "securities_account_id" => to_string(w.depot.id),
        "security_id" => to_string(security.id),
        "quantity" => "10",
        "price" => "200",
        "fees" => "0",
        "taxes" => "0",
        "notes" => ""
      },
      overrides
    )
  end

  defp change(view, params, target) do
    view
    |> element("#transaction-form")
    |> render_change(%{"_target" => ["transaction", target], "transaction" => params})
  end

  defp input_value(view, name) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s(#transaction-form input[name="transaction[#{name}]"]))
    |> Floki.attribute("value")
    |> List.first()
  end

  # User story (#395 rescoped, pick F3-A of board 03-settlement-inputs):
  # As the operator buying a USD security through a EUR depot,
  # I want the booking form to ask for the settlement in EUR,
  # so that the trade is booked in the security's currency with its cash leg
  # in the account's — instead of the form booking the USD price as euros.
  #
  # Acceptance criteria:
  # - The fieldset "Settlement in EUR" appears when the security's currency
  #   differs from the depot's cash account, and only then.
  # - It is prefilled from the stored exchange rates on or before the booking
  #   date and says so; amount and rate derive each other as either is typed,
  #   and a changed quantity or price re-derives the amount from the rate.
  # - Saved, the booking is in the security's currency with its security
  #   amount, the settlement amount, the rate the two amounts imply, and a
  #   cash amount that meets the settlement guard: plus fees and taxes on a
  #   buy, less them on a sell.
  # - The fieldset states the guard in one sentence, so a 422 never surprises.
  test "a cross-currency buy asks for its settlement and books both legs",
       %{conn: conn, world: w, usd: usd} do
    view = open(conn)
    change(view, form_params(w, usd, %{}), "security_id")

    assert has_element?(view, "#settlement-fieldset legend", "Settlement in EUR")
    assert has_element?(view, "#settlement-fieldset", "USD")
    assert has_element?(view, "#settlement-fieldset", "stored exchange rates")
    assert has_element?(view, "#settlement-fieldset", "fees and taxes")
    assert input_value(view, "settlement_fx_rate") == "0.909091"
    assert input_value(view, "settlement_amount") == "1818.18"

    # Either figure derives the other.
    change(view, form_params(w, usd, %{"settlement_amount" => "1800"}), "settlement_amount")
    assert input_value(view, "settlement_fx_rate") == "0.9"

    change(
      view,
      form_params(w, usd, %{"settlement_amount" => "1800", "settlement_fx_rate" => "0,92"}),
      "settlement_fx_rate"
    )

    assert input_value(view, "settlement_amount") == "1840.00"

    change(
      view,
      form_params(w, usd, %{
        "quantity" => "20",
        "settlement_amount" => "1840.00",
        "settlement_fx_rate" => "0.92"
      }),
      "quantity"
    )

    assert input_value(view, "settlement_amount") == "3680.00"

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" =>
        form_params(w, usd, %{
          "fees" => "4,90",
          "settlement_amount" => "1818.18",
          "settlement_fx_rate" => "0.909091"
        })
    })

    [tx] = Repo.all(Transaction)

    # The history shows the cash amount in the currency it moved in — the
    # account's — never labelled with the security's (closing act, UAT).
    amount = view |> element("#transaction-list [data-role=amount]") |> render()
    assert amount =~ "EUR"
    refute amount =~ "USD"
    assert view |> element(".summary-type[data-type=buy]") |> render() =~ "EUR"

    assert tx.currency_code == "USD"
    assert Decimal.equal?(tx.price, Decimal.new("200"))
    assert Decimal.equal?(tx.security_amount, Decimal.new("2000"))
    assert Decimal.equal?(tx.settlement_amount, Decimal.new("1818.18"))
    assert Decimal.equal?(tx.gross_amount, Decimal.new("1823.08"))
    assert Decimal.equal?(tx.settlement_fx_rate, Decimal.new("0.90909"))

    # A sell's cash is the settlement less fees and taxes.
    view |> element("#open-booking") |> render_click()

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" =>
        form_params(w, usd, %{
          "type" => "sell",
          "quantity" => "4",
          "price" => "210",
          "fees" => "2",
          "taxes" => "3.50",
          "settlement_amount" => "763.64"
        })
    })

    sell = Repo.get_by!(Transaction, type: "sell")
    assert Decimal.equal?(sell.security_amount, Decimal.new("840"))
    assert Decimal.equal?(sell.gross_amount, Decimal.new("758.14"))
  end

  test "a same-currency booking shows no settlement fieldset", %{conn: conn, world: w, eur: eur} do
    view = open(conn)
    change(view, form_params(w, eur, %{}), "security_id")

    refute has_element?(view, "#settlement-fieldset")

    view
    |> element("#transaction-form")
    |> render_submit(%{"transaction" => form_params(w, eur, %{})})

    [tx] = Repo.all(Transaction)
    assert tx.currency_code == "EUR"
    assert is_nil(tx.settlement_amount)
  end

  test "without a stored rate the fieldset asks for the statement's figure",
       %{conn: conn, world: w, usd: usd} do
    view = open(conn)
    params = form_params(w, usd, %{"date" => "2026-03-01"})
    change(view, params, "date")

    assert has_element?(view, "#settlement-fieldset", "No stored exchange rate")
    assert input_value(view, "settlement_amount") in [nil, ""]

    html = view |> element("#transaction-form") |> render_submit(%{"transaction" => params})

    assert Repo.all(Transaction) == []
    assert html =~ ~s(id="tx-error-settlement_amount")
  end

  test "editing a cross-currency booking opens with its settlement",
       %{conn: conn, world: w, usd: usd} do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-04-01],
        quantity: "10",
        price: "200",
        currency_code: "USD",
        security_amount: "2000",
        settlement_amount: "1818.18",
        gross_amount: "1818.18"
      })

    {:ok, view, _html} = live(conn, "/transactions")
    render_click(view, "edit_transaction", %{"id" => to_string(tx.id)})

    assert has_element?(view, "#settlement-fieldset")
    assert input_value(view, "settlement_amount") == "1818.18"
    assert input_value(view, "settlement_fx_rate") == "0.90909"
  end

  # User story (#395, the importer's account-currency form):
  # As the operator correcting the note of an imported USD trade,
  # I want the edit to leave its figures alone,
  # so that a row the importer booked in the account's currency (price in
  # EUR, its settlement legs stored) is not re-read as a USD booking.
  #
  # Acceptance criteria:
  # - Such a row opens without the settlement fieldset, its currency line
  #   naming the account's currency.
  # - Saving a note keeps its currency, price and settlement legs.
  test "an imported account-currency row edits as it was booked",
       %{conn: conn, world: w, usd: usd} do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-04-01],
        quantity: "10",
        price: "181.818",
        currency_code: "EUR",
        security_amount: "2000",
        settlement_amount: "1818.18",
        gross_amount: "1818.18"
      })

    {:ok, view, _html} = live(conn, "/transactions")
    render_click(view, "edit_transaction", %{"id" => to_string(tx.id)})

    refute has_element?(view, "#settlement-fieldset")
    assert has_element?(view, ~s([data-role="derived-currency"]), "EUR")

    form =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("#transaction-form input, #transaction-form select option[selected]")

    assert Floki.attribute(form, ~s(input[name="transaction[settlement_mode]"]), "value") ==
             ["account"]

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" =>
        form_params(w, usd, %{
          "price" => "181.818",
          "notes" => "re-read",
          "settlement_mode" => "account"
        })
    })

    saved = Repo.get!(Transaction, tx.id)
    assert saved.notes == "re-read"
    assert saved.currency_code == "EUR"
    assert Decimal.equal?(saved.price, Decimal.new("181.818"))
    assert Decimal.equal?(saved.settlement_amount, Decimal.new("1818.18"))
    assert Decimal.equal?(saved.security_amount, Decimal.new("2000"))
  end

  # Acceptance criteria (closing act, correctness and edge-case hunters —
  # risk-tier: each of these moved money without a word):
  # - Typing the settlement amount before quantity and price does not crash
  #   the page.
  # - The figure the operator typed last is kept: after the amount, a changed
  #   quantity or price re-derives the rate, never the amount; a note, fees
  #   or a date re-derive nothing (the amount used to move by a cent on every
  #   keystroke).
  test "the typed settlement amount is kept, and typing it first does not crash",
       %{conn: conn, world: w, usd: usd} do
    view = open(conn)

    blank =
      form_params(w, usd, %{"quantity" => "", "price" => "", "settlement_amount" => "1818.18"})

    change(view, blank, "settlement_amount")
    assert input_value(view, "settlement_amount") == "1818.18"

    typed = form_params(w, usd, %{"settlement_amount" => "1818.18"})
    change(view, typed, "price")
    assert input_value(view, "settlement_amount") == "1818.18"
    assert input_value(view, "settlement_fx_rate") == "0.90909"

    for target <- ["notes", "fees", "date"] do
      change(
        view,
        Map.merge(typed, %{
          "settlement_fx_rate" => "0.90909",
          "notes" => "Broker 42",
          "fees" => "4,90"
        }),
        target
      )

      assert input_value(view, "settlement_amount") == "1818.18", "#{target} moved the amount"
    end
  end

  # Acceptance criteria (closing act, edge-case hunter — risk-tier): an edit
  # that turns a cross-currency booking into a same-currency one leaves no
  # settlement legs and no stale cash amount behind; the cash follows the new
  # quantity, price and fees.
  test "leaving the cross-currency pair clears the settlement legs",
       %{conn: conn, world: w, usd: usd, eur: eur} do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-04-01],
        quantity: "10",
        price: "200",
        fees: "1",
        currency_code: "USD",
        security_amount: "2000",
        settlement_amount: "1818.18",
        gross_amount: "1819.18"
      })

    {:ok, view, _html} = live(conn, "/transactions")
    render_click(view, "edit_transaction", %{"id" => to_string(tx.id)})

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" =>
        form_params(w, eur, %{
          "quantity" => "5",
          "price" => "10",
          "fees" => "1",
          "settlement_mode" => "security"
        })
    })

    saved = Repo.get!(Transaction, tx.id)
    assert saved.currency_code == "EUR"
    assert is_nil(saved.settlement_amount)
    assert is_nil(saved.security_amount)
    assert is_nil(saved.settlement_fx_rate)
    assert is_nil(saved.gross_amount)
  end

  # Acceptance criteria (closing act, edge-case hunter): an imported row in
  # the account-currency form can have its fees corrected in the form — its
  # cash amount follows its stored settlement, so the guard holds.
  test "an imported account-currency row's fees can be corrected",
       %{conn: conn, world: w, usd: usd} do
    {:ok, tx} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: w.portfolio.id,
        securities_account_id: w.depot.id,
        cash_account_id: w.cash.id,
        security_id: usd.id,
        type: "buy",
        date: ~D[2026-04-01],
        quantity: "10",
        price: "181.818",
        fees: "1",
        currency_code: "EUR",
        security_amount: "2000",
        settlement_amount: "1818.18",
        gross_amount: "1819.18"
      })

    {:ok, view, _html} = live(conn, "/transactions")
    render_click(view, "edit_transaction", %{"id" => to_string(tx.id)})

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" =>
        form_params(w, usd, %{
          "price" => "181.818",
          "fees" => "2",
          "settlement_mode" => "account",
          "settlement_amount" => "1818.18"
        })
    })

    saved = Repo.get!(Transaction, tx.id)
    assert Decimal.equal?(saved.fees, Decimal.new("2"))
    assert Decimal.equal?(saved.gross_amount, Decimal.new("1820.18"))
    assert Decimal.equal?(saved.settlement_amount, Decimal.new("1818.18"))
  end

  # Acceptance criteria (closing act, edge-case hunter):
  # - A cross-currency buy at price 0 (a spin-off, a free allotment) books:
  #   no cash moves, so there is no cash amount to record.
  # - A sale whose fees and taxes exceed its settlement is refused on the
  #   settlement field the form shows, not on a field it does not have.
  test "a zero-price buy books, and a sale netting below zero is named",
       %{conn: conn, world: w, usd: usd} do
    view = open(conn)

    view
    |> element("#transaction-form")
    |> render_submit(%{
      "transaction" =>
        form_params(w, usd, %{
          "price" => "0",
          "settlement_amount" => "0",
          "settlement_fx_rate" => "0.909091"
        })
    })

    assert [free] = Repo.all(Transaction)
    assert Decimal.equal?(free.price, Decimal.new("0"))
    assert is_nil(free.gross_amount)

    view |> element("#open-booking") |> render_click()

    html =
      view
      |> element("#transaction-form")
      |> render_submit(%{
        "transaction" =>
          form_params(w, usd, %{
            "type" => "sell",
            "quantity" => "1",
            "price" => "5",
            "fees" => "9,90",
            "settlement_amount" => "4,55"
          })
      })

    assert html =~ ~s(id="tx-error-settlement_amount")
    assert length(Repo.all(Transaction)) == 1
  end
end
