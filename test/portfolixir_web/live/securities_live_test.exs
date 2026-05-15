defmodule PortfolixirWeb.SecuritiesLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  defmodule RaisingAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider
    @impl true
    def id, do: :raising
    @impl true
    def fetch(_security, _opts), do: raise("boom")
  end

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

    test "in conflict mode, Save updates the existing record with the form values",
         %{conn: conn} do
      # User story:
      # As a local portfolio maintainer,
      # I want the dialog's Save button to update the matched existing
      # security when a conflict is shown,
      # so that I can fix a value (e.g. switch the quote feed) without
      # having to find a separate edit screen.
      {:ok, existing} =
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
      assert has_element?(view, "#security-form-dialog button[type='submit']", "Update existing")

      # User edits the feed via the form, then hits Save.
      view
      |> element("#security-form-dialog form")
      |> render_submit(%{
        "security" => %{
          "name" => "Apple Inc.",
          "ticker_symbol" => "AAPL",
          "isin" => "US0378331005",
          "currency_code" => "USD",
          "asset_class" => "equity",
          "feed" => "MANUAL"
        }
      })

      refute has_element?(view, "#security-form-dialog")
      updated = Catalog.get_security!(existing.id)
      assert updated.feed == "MANUAL"
    end

    test "in conflict mode, Merge online fields applies the user's form edits on top",
         %{conn: conn} do
      {:ok, existing} =
        Catalog.create_security(%{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          currency_code: "USD",
          asset_class: "equity",
          provider: "portfolio_performance",
          online_id: "us0378331005",
          feed: "PORTFOLIO_PERFORMANCE",
          note: "kept across merges"
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

      # User edits feed in the form, then triggers merge.
      view
      |> element("#security-form-dialog form")
      |> render_change(%{"security" => %{"feed" => "MANUAL"}})

      view
      |> element("#security-form-dialog button", "Merge online fields")
      |> render_click()

      refute has_element?(view, "#security-form-dialog")
      updated = Catalog.get_security!(existing.id)
      assert updated.feed == "MANUAL"
      assert updated.note == "kept across merges"
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
    # User story:
    # As a local portfolio maintainer,
    # I want the securities list headers to read like a data table,
    # so that sorting feels integrated instead of looking like button columns.
    #
    # Acceptance criteria:
    # - Sortable headers keep accessible button semantics.
    # - Sort buttons are styled as table-header controls, not gradient buttons.
    # - The table has stronger row and header separation for scanning.
    test "securities table keeps sort semantics while using neutral table styling", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(view, "#securities-table thead button.sort-toggle", "Name")

      app_css = File.read!("priv/static/app.css")

      refute app_css =~
               "button {\n  justify-self: start;\n  min-height: 42px;\n  padding: 9px 14px;\n  color: #ffffff;\n  cursor: pointer;\n  background: linear-gradient"

      assert app_css =~ ".sort-toggle"
      assert app_css =~ "background: transparent;"
      assert app_css =~ "box-shadow: none;"
      assert app_css =~ ".sort-toggle::after"
      assert app_css =~ ".data-table tbody tr"
      assert app_css =~ "border-bottom: 1px solid var(--color-border);"
    end

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

  describe "price columns and sync" do
    alias Portfolixir.Catalog.Quote, as: SecurityQuote
    alias Portfolixir.Repo

    setup do
      {:ok, apple} =
        Catalog.create_security(%{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          currency_code: "USD",
          asset_class: "equity",
          provider: "portfolio_performance",
          online_id: "us0378331005"
        })

      [%{date: ~D[2026-05-14], close: "120.00"}, %{date: ~D[2026-05-15], close: "126.00"}]
      |> Enum.each(fn row ->
        %SecurityQuote{}
        |> SecurityQuote.changeset(Map.merge(row, %{security_id: apple.id, source: "manual"}))
        |> Repo.insert!()
      end)

      %{apple: apple}
    end

    # User story:
    # As a local portfolio maintainer,
    # I want the securities list to show the latest price and the day change
    # for each security and to navigate to a detail page when I click a row,
    # so that I can scan price movement and drill in like in Portfolio
    # Performance.
    #
    # Acceptance criteria:
    # - Default columns include "Latest price" and "Day change %".
    # - The latest close and absolute day-change render in the row.
    # - Clicking a row navigates to /securities/:id.
    # - A "Sync prices" toolbar button is available.
    test "shows latest price and day-change for a security with quote history",
         %{conn: conn, apple: _apple} do
      {:ok, view, _html} = live(conn, "/securities")

      html = render(view)
      assert html =~ "Latest price"
      assert html =~ "Day change"
      assert html =~ "126.00"
      # Day change %: (126 - 120) / 120 = +5.00 %
      assert html =~ "+5.00"
    end

    test "exposes a Sync prices toolbar button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")
      assert has_element?(view, "button#sync-prices")
    end

    test "Sync prices recovers even if the background sync raises",
         %{conn: conn} do
      # User story:
      # As a local portfolio maintainer,
      # I want the Sync-prices button to recover when the background sync
      # crashes (adapter exception, DB blip, …),
      # so I don't have to reload the page to try again.
      #
      # The handler must guarantee `:sync_done` delivery (try/after) so
      # the busy flag clears even when QuoteSync.sync_all/0 raises.
      {:ok, _sec} =
        Catalog.create_security(%{name: "Crashy", currency_code: "USD", provider: "manual"})

      prior_cfg = Application.get_env(:portfolixir, Portfolixir.Catalog.QuoteSync, [])

      Application.put_env(
        :portfolixir,
        Portfolixir.Catalog.QuoteSync,
        Keyword.put(prior_cfg, :adapter_for, %{"manual" => RaisingAdapter})
      )

      try do
        {:ok, view, _html} = live(conn, "/securities")

        ExUnit.CaptureLog.with_log(fn ->
          view |> element("button#sync-prices") |> render_click()

          # Poll for the busy flag to clear (try/after delivers :sync_done
          # even after the inner raise).
          Enum.reduce_while(1..50, :ok, fn _i, _acc ->
            if has_element?(view, "button#sync-prices[disabled]") do
              Process.sleep(20)
              {:cont, :ok}
            else
              {:halt, :ok}
            end
          end)

          refute has_element?(view, "button#sync-prices[disabled]")
        end)
      after
        Application.put_env(:portfolixir, Portfolixir.Catalog.QuoteSync, prior_cfg)
      end
    end

    test "rows are navigable to the detail page", %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(
               view,
               ~s|tr#security-row-#{apple.id} a[href="/securities/#{apple.id}"]|
             )
    end

    test "opens the detail pane when the URL points at a security", %{conn: conn, apple: apple} do
      {:ok, view, html} = live(conn, "/securities/#{apple.id}")

      assert html =~ "security-detail-pane"
      assert html =~ "Apple Inc."
      assert html =~ "Log scale"

      for range <- ~w(1M 3M 6M YTD 1Y MAX) do
        assert has_element?(view, "button[phx-value-range='#{range}']", range)
      end

      assert has_element?(view, "tr#security-row-#{apple.id}.is-selected")
    end

    test "patching to a row id opens the pane without a full navigation",
         %{conn: conn, apple: apple} do
      {:ok, view, html_before} = live(conn, "/securities")
      refute html_before =~ "security-detail-pane"

      view |> element("tr#security-row-#{apple.id} a") |> render_click()

      assert has_element?(view, "#security-detail-pane")
    end

    test "patching back to /securities closes the pane", %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")
      assert has_element?(view, "#security-detail-pane")

      view |> element("#security-detail-pane .icon-button") |> render_click()

      refute has_element?(view, "#security-detail-pane")
    end

    test "unknown id silently falls back to the list view", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities/999999")
      refute has_element?(view, "#security-detail-pane")
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
