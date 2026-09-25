defmodule PortfolixirWeb.LifecycleFreezeLiveTest do
  # ADR-0050 §11 first bullet and §16 invariant 15 on the UI paths (risk-tier:
  # money and identity, ADR-0036): the security form, and the search dialog's
  # "merge into existing" from a listing in another currency — the writer
  # §11 names because it can put a listing's currency onto an existing
  # security — answer a frozen currency with the field error under the
  # currency select, and write nothing. The accounts page writes only the
  # liquidity role today; its edit on a booked account still lands, because
  # the freeze holds the identity fields, not the row.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Portfolios
  alias Portfolixir.WorldFixtures

  defp open_edit(view, security) do
    view
    |> element(
      ~s(#securities-table button[phx-click="open_row_menu"][phx-value-id="#{security.id}"])
    )
    |> render_click()

    view
    |> element(~s(button[phx-value-action="edit"][phx-value-id="#{security.id}"]))
    |> render_click()
  end

  defp form_values(security, overrides) do
    Map.merge(
      %{
        "name" => security.name,
        "ticker_symbol" => security.ticker_symbol,
        "currency_code" => security.currency_code,
        "asset_class" => security.asset_class
      },
      overrides
    )
  end

  # User story:
  # As the operator correcting a security's master data in the form,
  # I want a currency change on a security with bookings refused under the
  # currency field,
  # so that the edit cannot re-denominate its booked history, and I see why.
  #
  # Acceptance criteria:
  # - Saving the edit form with another currency on a booked security keeps
  #   the dialog open with the frozen-field error under the currency select;
  #   the security keeps its currency.
  # - Saving the same form with the stored currency and a new name lands.
  test "the edit form refuses a currency change on a booked security", %{conn: conn} do
    world = WorldFixtures.base_world()
    security = WorldFixtures.create_security!(name: "Booked ETF", ticker: "BKD")
    WorldFixtures.buy!(world, security)

    {:ok, view, _html} = live(conn, "/securities")
    open_edit(view, security)

    view
    |> element("#security-form-dialog form")
    |> render_submit(%{"security" => form_values(security, %{"currency_code" => "USD"})})

    assert has_element?(
             view,
             "#security-form-dialog .field-error",
             "is frozen once referenced (1 transaction)"
           )

    assert Catalog.get_security(security.id).currency_code == "EUR"

    view
    |> element("#security-form-dialog form")
    |> render_submit(%{"security" => form_values(security, %{"name" => "Booked ETF (acc)"})})

    refute has_element?(view, "#security-form-dialog")
    assert %{name: "Booked ETF (acc)", currency_code: "EUR"} = Catalog.get_security(security.id)
  end

  # User story:
  # As the operator adding a listing the catalog already holds,
  # I want "Merge online fields" and "Update existing" from a listing in
  # another currency refused on a security with bookings,
  # so that picking the Xetra listing of a security booked in USD cannot turn
  # its booked history into EUR.
  #
  # Acceptance criteria:
  # - After picking a listing in another currency and seeing the conflict,
  #   both "Merge online fields" and the conflict-mode save leave the dialog
  #   open with the frozen-field error under the currency select.
  # - The existing security keeps its currency and none of the listing's
  #   other fields land.
  test "a search result from a listing in another currency is not merged into a booked security",
       %{conn: conn} do
    world = WorldFixtures.base_world(cash_currency: "USD")

    {:ok, existing} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Apple Inc.",
        ticker_symbol: "AAPL",
        isin: "US0378331005",
        currency_code: "USD",
        asset_class: "equity",
        provider: "portfolio_performance",
        online_id: "us0378331005",
        feed: "PORTFOLIO_PERFORMANCE"
      })

    WorldFixtures.buy!(world, existing, currency: "USD")

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#open-new-dialog") |> render_click()
    view |> element("button[phx-value-mode='security']") |> render_click()

    view
    |> element("#security-form-dialog form")
    |> render_change(%{"dialog_query" => "apple"})

    view |> element("#security-form-dialog .search-result") |> render_click()

    # The Xetra listing, quoted in EUR: the fake provider's second market, and
    # the dialog's recommended one.
    view
    |> element("#security-form-dialog [data-role='market-recommended'] button[phx-value-idx='1']")
    |> render_click()

    assert has_element?(view, "#security-form-dialog", "This security already exists")

    view
    |> element("#security-form-dialog button", "Merge online fields")
    |> render_click()

    assert has_element?(
             view,
             "#security-form-dialog .field-error",
             "is frozen once referenced (1 transaction)"
           )

    view
    |> element("#security-form-dialog form")
    |> render_submit(%{
      "security" => %{
        "name" => "Apple Inc.",
        "ticker_symbol" => "APC",
        "isin" => "US0378331005",
        "currency_code" => "EUR",
        "exchange_code" => "XETR",
        "asset_class" => "equity",
        "feed" => "PORTFOLIO_PERFORMANCE"
      }
    })

    assert has_element?(
             view,
             "#security-form-dialog .field-error",
             "is frozen once referenced (1 transaction)"
           )

    assert %{currency_code: "USD", ticker_symbol: "AAPL", exchange_code: nil} =
             Catalog.get_security(existing.id)
  end

  # User story:
  # As the operator classifying a booked cash account,
  # I want its liquidity role to stay editable,
  # so that the freeze holds the account's currency and portfolio binding,
  # not the account.
  #
  # Acceptance criteria:
  # - Changing the liquidity role of an account with bookings and a linked
  #   depot on the accounts page stores the new role.
  test "the accounts page still edits a booked account's liquidity role", %{conn: conn} do
    world = WorldFixtures.base_world(cash_name: "Giro")
    WorldFixtures.deposit!(world, "100", ~D[2026-01-02])

    {:ok, view, _html} = live(conn, "/portfolios")

    view
    |> element("#liquidity-role-form-#{world.cash.id}")
    |> render_change(%{"liquidity_role" => "reserve"})

    assert Portfolios.get_cash_account(world.cash.id).liquidity_role == "reserve"
  end
end
