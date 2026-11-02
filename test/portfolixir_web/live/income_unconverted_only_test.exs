defmodule PortfolixirWeb.IncomeUnconvertedOnlyTest do
  # #1293's review (Sprint 22 R9): a portfolio whose every dividend and
  # interest payment has no stored rate to its base currency has no
  # per-position row, because an unconverted payment is in no total. The
  # table must not then say nothing was booked; it says the payments could
  # not be converted and points to the note that names them. Synthetic data
  # only; no rate is stored at all.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  setup do
    world =
      WorldFixtures.base_world(
        name: "Synthetic Franc Book",
        currency: "EUR",
        cash_currency: "CHF"
      )

    payer =
      WorldFixtures.create_security!(
        name: "Synthetic Franc Payer",
        ticker: "SFP",
        currency: "CHF"
      )

    {:ok, _} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: world.portfolio.id,
        cash_account_id: world.cash.id,
        security_id: payer.id,
        type: "dividend",
        date: ~D[2025-05-02],
        gross_amount: "40.00",
        taxes: "0",
        currency_code: "CHF"
      })

    :ok
  end

  # User story (#1293's review):
  # As the operator whose payments all lack a rate,
  # I want "Per position" to say they could not be converted,
  # so that I do not read the table as "nothing was paid".
  #
  # Acceptance criteria:
  # - #income-positions does not say "No dividends or interest booked yet."
  # - It says "1 payment could not be converted to EUR, so no position has
  #   a figure — the note above names it."
  # - In German: "1 Zahlung konnte nicht nach EUR umgerechnet werden, daher
  #   hat keine Position einen Betrag — der Hinweis oben nennt sie."
  test "Per position says the payments could not be converted", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/cashflow")

    refute has_element?(view, "#income-positions", "No dividends or interest booked yet.")

    assert has_element?(
             view,
             "#income-positions .empty-state",
             "1 payment could not be converted to EUR, so no position has a figure — the note above names it."
           )

    Gettext.with_locale(PortfolixirWeb.Gettext, "de", fn ->
      assert Gettext.dngettext(
               PortfolixirWeb.Gettext,
               "default",
               "%{count} payment could not be converted to %{currency}, so no position has a figure — the note above names it.",
               "%{count} payments could not be converted to %{currency}, so no position has a figure — the note above names them.",
               1,
               currency: "EUR"
             ) ==
               "1 Zahlung konnte nicht nach EUR umgerechnet werden, daher hat keine Position einen Betrag — der Hinweis oben nennt sie."
    end)
  end
end
