defmodule PortfolixirWeb.SecuritiesLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  describe "list view" do
    test "renders empty-state when no securities exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(view, "#securities-panel")
      assert has_element?(view, "#securities-table", "No securities yet")
    end

    test "shows the toolbar buttons and search field", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(view, "#securities-search-form input[name='query']")
      assert has_element?(view, "button#open-new-dialog")
      assert has_element?(view, "button#toggle-filter-popover")
      assert has_element?(view, "button#toggle-column-popover")
    end

    test "search filters the list", %{conn: conn} do
      {:ok, _} =
        Catalog.create_security(%{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, _} =
        Catalog.create_security(%{
          name: "Bitcoin",
          ticker_symbol: "BTC",
          currency_code: "EUR",
          asset_class: "crypto"
        })

      {:ok, view, _html} = live(conn, "/securities")
      assert has_element?(view, "td", "Apple Inc.")
      assert has_element?(view, "td", "Bitcoin")

      view
      |> form("#securities-search-form", %{"query" => "Apple"})
      |> render_change()

      assert has_element?(view, "td", "Apple Inc.")
      refute has_element?(view, "td", "Bitcoin")
    end

    test "+ button opens the new-security dialog with the choose step", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      view |> element("#open-new-dialog") |> render_click()

      assert has_element?(view, "#security-form-dialog")
      assert has_element?(view, "button[phx-value-mode='security']")
      assert has_element?(view, "button[phx-value-mode='crypto']")
    end
  end

  describe "create flow via dialog (fake provider)" do
    test "creates an Apple security via Portfolio Performance fake", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      view |> element("#open-new-dialog") |> render_click()
      view |> element("button[phx-value-mode='security']") |> render_click()

      view
      |> element("#security-form-dialog form")
      |> render_change(%{"query" => "apple"})

      assert has_element?(view, "#security-form-dialog", "Apple Inc.")

      view |> element("#security-form-dialog .search-result") |> render_click()

      # Apple fixture has two markets, expect the market step
      assert has_element?(view, "#security-form-dialog", "NASDAQ")

      view
      |> element("#security-form-dialog .market-list button[phx-value-idx='0']")
      |> render_click()

      assert has_element?(view, "#security-form-dialog input[name='security[name]']")

      view
      |> element("#security-form-dialog form")
      |> render_submit(%{
        "security" => %{
          "name" => "Apple Inc.",
          "ticker_symbol" => "AAPL",
          "isin" => "US0378331005",
          "currency_code" => "USD",
          "asset_class" => "equity",
          "feed" => "PORTFOLIO_PERFORMANCE"
        }
      })

      refute has_element?(view, "#security-form-dialog")
      assert has_element?(view, "#securities-table", "Apple Inc.")
      assert Catalog.list_securities() |> length() == 1
    end

    test "duplicate insert surfaces a conflict banner instead of an exception", %{conn: conn} do
      {:ok, _existing} =
        Catalog.create_security(%{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          currency_code: "USD",
          asset_class: "equity",
          provider: "portfolio_performance",
          online_id: "us0378331005",
          feed: "PORTFOLIO_PERFORMANCE"
        })

      {:ok, view, _html} = live(conn, "/securities")

      view |> element("#open-new-dialog") |> render_click()
      view |> element("button[phx-value-mode='security']") |> render_click()

      view
      |> element("#security-form-dialog form")
      |> render_change(%{"query" => "apple"})

      view |> element("#security-form-dialog .search-result") |> render_click()

      view
      |> element("#security-form-dialog .market-list button[phx-value-idx='0']")
      |> render_click()

      assert has_element?(view, "#security-form-dialog", "This security already exists")
      assert Catalog.list_securities() |> length() == 1
    end
  end

  describe "column picker" do
    test "toggling a column removes it from the table header", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      view |> element("#toggle-column-popover") |> render_click()

      assert has_element?(view, "#column-picker")
      assert has_element?(view, "#securities-table thead", "Name")

      # Untick "Name" — submitting the form posts the remaining checked columns.
      view
      |> element("#column-picker form")
      |> render_change(%{"columns" => ["ticker_symbol", "isin"]})

      refute has_element?(view, "#securities-table thead button", "Name")
      assert has_element?(view, "#securities-table thead", "Ticker")
    end
  end

  describe "filter popover" do
    test "filter on asset_class adds a chip and narrows the list", %{conn: conn} do
      {:ok, _} =
        Catalog.create_security(%{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, _} =
        Catalog.create_security(%{
          name: "Bitcoin",
          ticker_symbol: "BTC",
          currency_code: "EUR",
          asset_class: "crypto"
        })

      {:ok, view, _html} = live(conn, "/securities")
      view |> element("#toggle-filter-popover") |> render_click()

      view
      |> element("#filter-popover form")
      |> render_submit(%{
        "field" => "asset_class",
        "operator" => "eq",
        "value" => "crypto"
      })

      assert has_element?(view, "#filter-chips .chip", "Cryptocurrency")
      assert has_element?(view, "td", "Bitcoin")
      refute has_element?(view, "td", "Apple Inc.")

      # Remove the chip again
      view |> element("#filter-chips .chip-remove") |> render_click()
      refute has_element?(view, "#filter-chips")
      assert has_element?(view, "td", "Apple Inc.")
    end
  end
end
