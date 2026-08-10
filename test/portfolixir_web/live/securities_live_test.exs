defmodule PortfolixirWeb.SecuritiesLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  defmodule RaisingAdapter do
    @moduledoc false
    @behaviour Portfolixir.Catalog.QuoteSync.Provider
    @impl true
    def id, do: :raising
    @impl true
    def fetch(_security, _opts), do: raise("boom")
  end

  describe "list view" do
    # User story:
    # As a local portfolio maintainer,
    # I want the securities list to use a full-width workspace below the top bar,
    # so that the table gets the horizontal and vertical room instead of nested panel chrome.
    #
    # Acceptance criteria:
    # - The securities page title is rendered in the top bar.
    # - The securities content opts into the workspace main layout.
    # - The securities table is not wrapped in the generic padded panel chrome.
    test "securities list uses a full-width workspace under the top bar", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(view, "#app-topbar-title", "Securities")
      assert has_element?(view, "main.app-main.app-main--workspace")
      assert has_element?(view, "#securities-panel.workspace-panel")
      refute has_element?(view, "#securities-panel.panel")
      refute has_element?(view, ".app-main .page-header")
    end

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

    # User story:
    # As a local portfolio maintainer,
    # I want the default app UI to be denser without relying on browser zoom,
    # so that more records fit on screen while controls remain normal CSS layout.
    #
    # Acceptance criteria:
    # - The global app font size and top bar height are reduced through CSS variables.
    # - Securities tables and detail panes use smaller padding values.
    # - The stylesheet does not use `zoom` or `transform: scale(...)` for density.
    test "stylesheet defines compact density without zoom or transform scaling" do
      app_css = File.read!("priv/static/app.css")

      assert app_css =~ "--density-font-size: 13px;"
      assert app_css =~ "--topbar-height: 52px;"
      assert app_css =~ "font-size: var(--density-font-size);"
      assert app_css =~ ".data-table tbody td {\n  padding: 7px 9px;"
      # Spacing now resolves through the 4px scale (#450): --space-3 == 12px.
      assert app_css =~
               ".detail-pane {\n  margin-top: var(--space-3);\n  padding: var(--space-3);"

      refute app_css =~ ~r/\bzoom\s*:/
      refute app_css =~ ~r/transform:\s*scale\(/i
    end

    # User story (Steve UAT #412):
    # As a maintainer entering security identifiers (ISIN, WKN, ticker),
    # I want those inputs to render in a monospace font,
    # so that the technical codes line up and are easy to scan. The form already
    # applied class="mono" to them, but no CSS rule backed it — a dead class
    # that did nothing.
    #
    # Acceptance criteria:
    # - The .mono utility is defined in the stylesheet.
    # - It uses the monospace font token (--font-mono), so the identifier inputs
    #   actually render monospaced.
    test "the dead .mono class is defined and uses the monospace font token" do
      app_css = File.read!("priv/static/app.css")

      assert app_css =~ ~r/\.mono\s*\{[^}]*font-family:\s*var\(--font-mono\)/s
    end

    test "search filters the list", %{conn: conn} do
      {:ok, _} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, _} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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

    # User story:
    # As a local portfolio maintainer narrowing the securities list,
    # I want a filtered zero-match to say "no matches", not "no securities",
    # so that the UI never asserts my portfolio is empty when my filter is
    # merely narrow (UX-DR13, issue 649).
    #
    # Acceptance criteria:
    # - A search with no hits renders a no-results state naming the query,
    #   with the controls still visible.
    # - The empty-surface message renders only when no securities exist.
    test "a filtered zero-match shows a no-results state, not the empty surface",
         %{conn: conn} do
      {:ok, _} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, view, _html} = live(conn, "/securities")

      html =
        view
        |> form("#securities-search-form", %{"query" => "zzz-no-match"})
        |> render_change()

      assert html =~ "No matches for"
      assert html =~ "zzz-no-match"
      refute html =~ "No securities yet"
      assert has_element?(view, "#securities-search-form input[name='query']")
    end

    # User story:
    # As a local portfolio maintainer,
    # I want one-click filters for all, held, and not-held securities,
    # so that I can focus the security list on current positions or cleanup candidates.
    #
    # Acceptance criteria:
    # - The toolbar offers Alle, Im Bestand, and Ohne Bestand in the German UI.
    # - Im Bestand shows only securities with a non-zero derived holding.
    # - Ohne Bestand shows sold-out and never-held securities.
    test "holding status toolbar filters the securities list", %{conn: conn} do
      {:ok, held} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Active ETF",
          ticker_symbol: "HELD",
          currency_code: "EUR",
          asset_class: "equity"
        })

      {:ok, flat} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Sold Out ETF",
          ticker_symbol: "FLAT",
          currency_code: "EUR",
          asset_class: "equity"
        })

      {:ok, _never} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Never Held ETF",
          ticker_symbol: "NEVR",
          currency_code: "EUR",
          asset_class: "equity"
        })

      {portfolio, cash_account, depot} = create_trade_accounts("Status Filter")

      for {security, type, quantity, date} <- [
            {held, "buy", "4", ~D[2026-01-02]},
            {flat, "buy", "2", ~D[2026-01-03]},
            {flat, "sell", "2", ~D[2026-01-04]}
          ] do
        assert {:ok, _} =
                 Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
                   portfolio_id: portfolio.id,
                   securities_account_id: depot.id,
                   cash_account_id: cash_account.id,
                   security_id: security.id,
                   type: type,
                   date: date,
                   quantity: Decimal.new(quantity),
                   price: Decimal.new("10"),
                   fees: Decimal.new("0"),
                   taxes: Decimal.new("0"),
                   currency_code: "EUR"
                 })
      end

      conn = put_req_header(conn, "accept-language", "de")
      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(view, "#holding-status-filter button", "Alle")
      assert has_element?(view, "#holding-status-filter button", "Im Bestand")
      assert has_element?(view, "#holding-status-filter button", "Ohne Bestand")

      view |> element("#holding-status-filter button", "Im Bestand") |> render_click()

      assert has_element?(view, "td", "Active ETF")
      refute has_element?(view, "td", "Sold Out ETF")
      refute has_element?(view, "td", "Never Held ETF")

      view |> element("#holding-status-filter button", "Ohne Bestand") |> render_click()

      refute has_element?(view, "td", "Active ETF")
      assert has_element?(view, "td", "Sold Out ETF")
      assert has_element?(view, "td", "Never Held ETF")

      view |> element("#holding-status-filter button", "Alle") |> render_click()

      assert has_element?(view, "td", "Active ETF")
      assert has_element?(view, "td", "Sold Out ETF")
      assert has_element?(view, "td", "Never Held ETF")
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
    # User story:
    # As a maintainer adding a security, when I type in the new-security
    # dialog's search field the dialog must show results — not silently filter
    # the table behind it (#489). The page filter and the dialog search must be
    # distinct fields so keystrokes never leak to the wrong one.
    test "dialog search field is distinct from the page filter and is focused (#489)",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      view |> element("#open-new-dialog") |> render_click()
      view |> element("button[phx-value-mode='security']") |> render_click()

      # The dialog search field has its own name and grabs focus on mount,
      # so it does not collide with the page filter's name="query".
      assert has_element?(view, "#security-form-dialog input[name='dialog_query']")
      refute has_element?(view, "#security-form-dialog input[name='query']")
      assert render(view) =~ "phx-mounted"

      # Typing in the dialog returns results from the provider.
      view
      |> element("#security-form-dialog form")
      |> render_change(%{"dialog_query" => "apple"})

      assert has_element?(view, "#security-form-dialog", "Apple Inc.")

      # Submitting the dialog search (Enter) uses the same field and works too.
      view
      |> element("#security-form-dialog form")
      |> render_submit(%{"dialog_query" => "apple"})

      assert has_element?(view, "#security-form-dialog", "Apple Inc.")
    end

    test "creates an Apple security via Portfolio Performance fake", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      view |> element("#open-new-dialog") |> render_click()
      view |> element("button[phx-value-mode='security']") |> render_click()

      view
      |> element("#security-form-dialog form")
      |> render_change(%{"dialog_query" => "apple"})

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
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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
      |> render_change(%{"dialog_query" => "apple"})

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
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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
      |> render_change(%{"dialog_query" => "apple"})

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
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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
      |> render_change(%{"dialog_query" => "apple"})

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
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Crashy",
          currency_code: "USD",
          provider: "manual"
        })

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

    test "Sync prices reports skipped work instead of saying prices synced",
         %{conn: conn} do
      # User story:
      # As a local portfolio maintainer,
      # I want quote-sync status to distinguish skipped securities from successful syncs,
      # so that missing ticker/provider setup is not reported as fresh prices.
      #
      # Acceptance criteria:
      # - A skipped sync clears the busy flag.
      # - The flash does not say "Prices synced." when every security was skipped.
      # - The status mentions skipped work.
      {:ok, _sec} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "No Adapter",
          currency_code: "USD",
          provider: "manual"
        })

      prior_cfg = Application.get_env(:portfolixir, Portfolixir.Catalog.QuoteSync, [])

      Application.put_env(
        :portfolixir,
        Portfolixir.Catalog.QuoteSync,
        Keyword.put(prior_cfg, :adapter_for, %{})
      )

      try do
        {:ok, view, _html} = live(conn, "/securities")

        view |> element("button#sync-prices") |> render_click()

        Enum.reduce_while(1..50, :ok, fn _i, _acc ->
          if has_element?(view, "button#sync-prices[disabled]") do
            Process.sleep(20)
            {:cont, :ok}
          else
            {:halt, :ok}
          end
        end)

        refute has_element?(view, ".status-toast", "Prices synced.")
        assert has_element?(view, ".status-toast", "skipped")
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
      assert has_element?(view, "tr#security-row-#{apple.id}.is-selected")
    end

    # User story:
    # As a local portfolio maintainer,
    # I want the securities list to use the whole workspace when no row is selected,
    # so that the list remains dense and uncluttered for scanning.
    #
    # Acceptance criteria:
    # - The list-only workspace is rendered on /securities.
    # - No detail pane or splitter is present without a selection.
    # - The existing table remains the primary list surface.
    test "list-only mode fills the securities workspace", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(view, "#securities-workspace.securities-workspace--list-only")
      assert has_element?(view, "#securities-list-pane")
      assert has_element?(view, "#securities-table")
      refute has_element?(view, "#securities-detail-splitter")
      refute has_element?(view, "#security-detail-pane")
    end

    # User story:
    # As a local portfolio maintainer,
    # I want a selected security to open in a resizable vertical split workspace,
    # so that I can keep the list context while reviewing the detail pane.
    #
    # Acceptance criteria:
    # - Selection renders list pane, separator, and detail pane.
    # - The separator has accessible horizontal separator semantics.
    # - The split height is browser-local through a stable storage key.
    test "selected security renders split workspace with accessible separator", %{
      conn: conn,
      apple: apple
    } do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      assert has_element?(view, "#securities-workspace.securities-workspace--split")
      assert has_element?(view, "#securities-list-pane")

      assert has_element?(
               view,
               "#securities-detail-splitter[role='separator'][aria-orientation='horizontal'][phx-hook='SecuritySplitPane']"
             )

      assert has_element?(
               view,
               "#securities-detail-splitter[data-storage-key='securities.detailSplitHeight']"
             )

      assert has_element?(view, "#security-detail-pane")
    end

    test "chart tab exposes the range buttons and Log scale toggle",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}?tab=chart")

      assert render(view) =~ "Log scale"

      for range <- ~w(1M 3M 6M YTD 1Y MAX) do
        assert has_element?(view, "button[phx-value-range='#{range}']", range)
      end
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

      view |> element("#detail-pane-close") |> render_click()

      refute has_element?(view, "#security-detail-pane")
    end

    test "unknown id silently falls back to the list view", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities/999999")
      refute has_element?(view, "#security-detail-pane")
    end
  end

  describe "detail pane tabs" do
    # User story:
    # As a local portfolio maintainer,
    # I want the security detail pane organized into named tabs,
    # so that I can navigate between price chart, transactions, trades,
    # quote history, holdings and master data without scrolling one long pane.
    #
    # Acceptance criteria:
    # - The pane renders a tablist with six tabs: overview, chart, transactions,
    #   trades, quotes, holdings.
    # - The selected tab is reflected in the URL (?tab=…) so deep-links and
    #   reloads keep the same tab active.
    # - An unknown tab value falls back to the default tab (never crashes,
    #   never creates atoms from external input).
    # - Only the active tab's panel content is visible.

    setup do
      {:ok, apple} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, apple: apple}
    end

    test "renders a tablist with the six known tabs", %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      assert has_element?(view, "#detail-pane-tabs[role='tablist']")

      for tab <- ~w(overview chart transactions trades quotes holdings) do
        assert has_element?(
                 view,
                 "#detail-pane-tabs button[role='tab'][phx-value-tab='#{tab}']"
               )
      end
    end

    test "classifications tab assigns the security to a custom category",
         %{conn: conn, apple: apple} do
      {:ok, classification} =
        Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
          name: "Strategy"
        })

      {:ok, category} =
        Portfolixir.Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      {:ok, view, html} = live(conn, "/securities/#{apple.id}?tab=classifications")

      assert html =~ "Strategy"
      assert html =~ "Core"

      view
      |> element("form.sc-form")
      |> render_change(%{
        "classification_id" => "#{classification.id}",
        "category_id" => "#{category.id}"
      })

      assignments =
        Portfolixir.Classifications.list_trees()
        |> Enum.find(&(&1.classification.id == classification.id))
        |> Map.fetch!(:assignments)

      assert assignments == [%{security_id: apple.id, category_id: category.id}]
    end

    test "classifications tab creates a category inline and assigns the security",
         %{conn: conn, apple: apple} do
      {:ok, classification} =
        Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
          name: "Strategy"
        })

      {:ok, view, _html} = live(conn, "/securities/#{apple.id}?tab=classifications")

      view
      |> element("form.sc-form")
      |> render_change(%{
        "classification_id" => "#{classification.id}",
        "category_id" => "__new__"
      })

      assert has_element?(view, "form.sc-new-category")

      view
      |> form("form.sc-new-category", %{"name" => "Core"})
      |> render_submit()

      tree =
        Portfolixir.Classifications.list_trees()
        |> Enum.find(&(&1.classification.id == classification.id))

      assert [category] = tree.categories
      assert category.name == "Core"
      assert tree.assignments == [%{security_id: apple.id, category_id: category.id}]
    end

    test "classifications tab unassigns the security when the category is cleared",
         %{conn: conn, apple: apple} do
      {:ok, classification} =
        Portfolixir.Classifications.create_classification(Portfolixir.Actor.owner_ui(), %{
          name: "Strategy"
        })

      {:ok, category} =
        Portfolixir.Classifications.create_category(Portfolixir.Actor.owner_ui(), %{
          classification_id: classification.id,
          name: "Core"
        })

      {:ok, view, _html} = live(conn, "/securities/#{apple.id}?tab=classifications")

      form = element(view, "form.sc-form")

      render_change(form, %{
        "classification_id" => "#{classification.id}",
        "category_id" => "#{category.id}"
      })

      # Clearing the category (empty value) unassigns the security.
      render_change(form, %{
        "classification_id" => "#{classification.id}",
        "category_id" => ""
      })

      # A non-numeric category id is ignored (no crash, no change).
      render_change(form, %{
        "classification_id" => "#{classification.id}",
        "category_id" => "not-a-number"
      })

      assignments =
        Portfolixir.Classifications.list_trees()
        |> Enum.find(&(&1.classification.id == classification.id))
        |> Map.fetch!(:assignments)

      assert assignments == []
    end

    test "overview tab is active by default and chart content is hidden",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      assert has_element?(
               view,
               "#detail-pane-tabs button[phx-value-tab='overview'][aria-selected='true']"
             )

      assert has_element?(view, "#detail-tab-panel-overview")
      refute has_element?(view, "#detail-tab-panel-chart")
    end

    test "?tab=transactions selects the transactions tab on load",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}?tab=transactions")

      assert has_element?(
               view,
               "#detail-pane-tabs button[phx-value-tab='transactions'][aria-selected='true']"
             )

      assert has_element?(view, "#detail-tab-panel-transactions")
      refute has_element?(view, "#detail-tab-panel-chart")
    end

    test "localized Chart and Transactions tab clicks patch the URL and swap panels",
         %{conn: conn, apple: apple} do
      conn = put_req_header(conn, "accept-language", "de")
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      view
      |> element("#detail-pane-tabs [role='tab']", "Diagramm")
      |> render_click()

      assert_patched(view, "/securities/#{apple.id}?tab=chart")
      assert has_element?(view, "#detail-tab-chart[aria-selected='true']", "Diagramm")
      assert has_element?(view, "#detail-tab-panel-chart")
      refute has_element?(view, "#detail-tab-panel-overview")

      view
      |> element("#detail-pane-tabs [role='tab']", "Transaktionen")
      |> render_click()

      assert_patched(view, "/securities/#{apple.id}?tab=transactions")

      assert has_element?(
               view,
               "#detail-tab-transactions[aria-selected='true']",
               "Transaktionen"
             )

      assert has_element?(view, "#detail-tab-panel-transactions")
      refute has_element?(view, "#detail-tab-panel-chart")
    end

    # User story:
    # As a local portfolio maintainer,
    # I want detail tab clicks to show immediate loading feedback,
    # so that chart or transaction loading never feels like a dead click.
    #
    # Acceptance criteria:
    # - Tab controls dispatch a LiveView click event so the client receives
    #   the built-in `phx-click-loading` state immediately.
    # - The compact app stylesheet defines a visible loading state for tabs.
    test "tab buttons expose immediate loading feedback while patching",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      assert has_element?(
               view,
               "#detail-tab-chart[phx-click='select_detail_tab'][phx-value-tab='chart']"
             )

      css = File.read!("priv/static/app.css")
      assert css =~ ".detail-pane-tab.phx-click-loading"
      assert css =~ "cursor: progress"
    end

    test "clicking a tab patches the URL and swaps the active panel",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      view
      |> element("#detail-pane-tabs button[phx-value-tab='trades']")
      |> render_click()

      assert_patched(view, "/securities/#{apple.id}?tab=trades")

      assert has_element?(
               view,
               "#detail-pane-tabs button[phx-value-tab='trades'][aria-selected='true']"
             )

      assert has_element?(view, "#detail-tab-panel-trades")
      refute has_element?(view, "#detail-tab-panel-chart")
    end

    test "unknown ?tab=… value silently falls back to the default overview tab",
         %{conn: conn, apple: apple} do
      # Guards against `String.to_atom/1` on external input.
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}?tab=__bogus__")

      assert has_element?(
               view,
               "#detail-pane-tabs button[phx-value-tab='overview'][aria-selected='true']"
             )
    end
  end

  describe "detail pane — chart enhancements" do
    # User story:
    # As a local portfolio maintainer,
    # I want a custom from/to date picker and a percent-return toggle on
    # the price chart,
    # so that I can analyse arbitrary windows and compare relative
    # performance without rebuilding the data.
    #
    # Acceptance criteria:
    # - Selecting a custom range narrows the rendered range and deselects
    #   the preset range buttons.
    # - The percent-return toggle changes the chart payload so the Y axis
    #   reflects % change from the first visible close.
    # - All math stays in Decimal until the final pixel conversion.

    setup do
      {:ok, security} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      today = Date.utc_today()

      # 90 daily quotes — enough for the MA30 toggle to render points.
      rows =
        for i <- 0..89 do
          %{
            date: Date.add(today, -i),
            close: Decimal.to_string(Decimal.new("100.00") |> Decimal.add(Decimal.new(i))),
            source: "manual"
          }
        end

      {:ok, _} = Quotes.upsert_many(security.id, rows)

      {:ok, security: security, today: today}
    end

    test "applying a custom date range deselects the preset range buttons",
         %{conn: conn, security: security, today: today} do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

      from = Date.to_iso8601(Date.add(today, -45))
      to = Date.to_iso8601(today)

      view
      |> form("#detail-custom-range", %{"from" => from, "to" => to})
      |> render_submit()

      # The default "1Y" range is no longer the active one
      refute has_element?(view, "button[phx-value-range='1Y'].is-active")
      assert has_element?(view, "#detail-custom-range[data-active='true']")
    end

    test "MA30 toggle adds a chart-ma-30 polyline to the SVG",
         %{conn: conn, security: security} do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

      view |> element("#toggle-ma-30") |> render_click()

      assert has_element?(view, "polyline.chart-ma-30")
      refute has_element?(view, "polyline.chart-cost-basis")
    end

    test "cost-basis toggle adds a chart-cost-basis polyline once transactions exist",
         %{conn: conn, security: security} do
      {:ok, portfolio} =
        Portfolixir.Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
          name: "P",
          base_currency_code: "USD"
        })

      {:ok, cash} =
        Portfolixir.Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "C",
          currency_code: "USD"
        })

      {:ok, depot} =
        Portfolixir.Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "D"
        })

      {:ok, _} =
        Portfolixir.Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: Date.add(Date.utc_today(), -45),
          quantity: Decimal.new("5"),
          price: Decimal.new("100.00"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "USD"
        })

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

      view |> element("#toggle-cost-basis") |> render_click()

      assert has_element?(view, "polyline.chart-cost-basis")
    end

    test "renders SVG and PNG export buttons on the chart tab",
         %{conn: conn, security: security} do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

      assert has_element?(view, "#chart-export-svg")
      assert has_element?(view, "#chart-export-png")
    end

    test "clear_detail_custom_range event clears any active custom range",
         %{conn: conn, security: security, today: today} do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

      from = Date.to_iso8601(Date.add(today, -45))
      to = Date.to_iso8601(today)

      view
      |> form("#detail-custom-range", %{"from" => from, "to" => to})
      |> render_submit()

      assert has_element?(view, "#detail-custom-range[data-active='true']")

      render_hook(view, "clear_detail_custom_range", %{})

      assert has_element?(view, "#detail-custom-range[data-active='false']")
    end

    test "percent-return toggle marks the chart payload as percent mode",
         %{conn: conn, security: security} do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=chart")

      view |> element("#toggle-percent-mode") |> render_click()

      assert has_element?(view, "#toggle-percent-mode.is-active")
      payload_html = element(view, "script[data-chart-payload]") |> render()
      assert payload_html =~ ~s|"mode":"percent"|
    end
  end

  describe "detail pane fullscreen" do
    # User story:
    # As a local portfolio maintainer,
    # I want to expand the security detail pane into a viewport-covering
    # fullscreen view,
    # so that I can analyse a security with maximum chart real estate.
    #
    # Acceptance criteria:
    # - A Maximize button on the detail-pane header toggles fullscreen.
    # - In fullscreen the pane has the `.detail-pane--fullscreen` class.
    # - The Escape key MUST NOT close the pane while fullscreen is active.
    # - Clicking the X button still closes the pane in either mode.

    setup do
      {:ok, apple} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, apple: apple}
    end

    test "toggles fullscreen via the maximize button", %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      refute has_element?(view, "#security-detail-pane.detail-pane--fullscreen")

      view |> element("#detail-pane-fullscreen-toggle") |> render_click()

      assert has_element?(view, "#security-detail-pane.detail-pane--fullscreen")

      view |> element("#detail-pane-fullscreen-toggle") |> render_click()

      refute has_element?(view, "#security-detail-pane.detail-pane--fullscreen")
    end

    test "X button still closes the pane while fullscreen is active",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      view |> element("#detail-pane-fullscreen-toggle") |> render_click()

      assert has_element?(view, "#security-detail-pane.detail-pane--fullscreen")

      view |> element("#detail-pane-close") |> render_click()

      refute has_element?(view, "#security-detail-pane")
    end

    test "the detail pane DOES NOT bind a window-level Escape handler — strict X-only close",
         %{conn: conn, apple: apple} do
      # If a future change accidentally wires `phx-window-keydown` on the
      # detail pane, this test catches it. The strict rule from the user's
      # ask is: in fullscreen only the X must close the pane.
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      view |> element("#detail-pane-fullscreen-toggle") |> render_click()

      pane = element(view, "#security-detail-pane") |> render()
      refute pane =~ ~s|phx-window-keydown|
      assert has_element?(view, "#security-detail-pane.detail-pane--fullscreen")
    end
  end

  describe "detail pane — overview tab" do
    # User story:
    # As a local portfolio maintainer,
    # I want a master-data summary for the selected security,
    # so that I can confirm its identifiers, classification and key metrics
    # at a glance without opening the edit dialog.
    #
    # Acceptance criteria:
    # - The overview tab shows ISIN, WKN, ticker, exchange, currency, asset
    #   class, and feed configuration when present.
    # - It surfaces the latest quote and 1M/1Y performance derived metrics.
    # - It shows a clearly labelled retired badge when the security is
    #   retired.
    # - Notes can be edited inline and the form persists via
    #   Catalog.update_security/2.

    setup do
      {:ok, apple} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          wkn: "865985",
          currency_code: "USD",
          exchange_code: "XNAS",
          asset_class: "equity",
          note: "Bellwether holding"
        })

      {:ok, apple: apple}
    end

    test "renders master data fields", %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      html = render(view)
      assert html =~ "US0378331005"
      assert html =~ "865985"
      assert html =~ "AAPL"
      assert html =~ "XNAS"
      assert html =~ "USD"
      # asset class is rendered through the existing AssetClasses copy
      assert html =~ "Equity"
    end

    test "shows the retired badge when the security is retired",
         %{conn: conn, apple: apple} do
      {:ok, _} =
        Portfolixir.Catalog.update_security(Portfolixir.Actor.owner_ui(), apple, %{
          is_retired: true
        })

      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      assert has_element?(view, "#detail-tab-panel-overview .badge", "Retired")
    end

    test "renders 1M / 1Y performance metrics when quotes are present",
         %{conn: conn, apple: apple} do
      today = Date.utc_today()

      {:ok, _} =
        Quotes.upsert_many(apple.id, [
          %{date: Date.add(today, -400), close: "100.00", source: "manual"},
          %{date: Date.add(today, -45), close: "120.00", source: "manual"},
          %{date: today, close: "150.00", source: "manual"}
        ])

      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      panel = element(view, "#detail-tab-panel-overview") |> render()
      assert panel =~ "1M"
      assert panel =~ "1Y"
      # The latest price appears in both the header and overview body.
      assert panel =~ "150"
    end

    test "saving the notes form persists via Catalog.update_security/2",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      view
      |> form("#overview-notes-form", %{"security" => %{"note" => "Long-term core position."}})
      |> render_submit()

      assert Catalog.get_security(apple.id).note == "Long-term core position."
    end

    test "saving the details form persists master data via Catalog.update_security/2",
         %{conn: conn, apple: apple} do
      {:ok, view, _html} = live(conn, "/securities/#{apple.id}")

      view
      |> form("#overview-details-form", %{
        "security" => %{"name" => "Apple Inc. (edited)", "ticker_symbol" => "AAPL2"}
      })
      |> render_submit()

      updated = Catalog.get_security(apple.id)
      assert updated.name == "Apple Inc. (edited)"
      assert updated.ticker_symbol == "AAPL2"
    end
  end

  describe "detail pane — transactions tab" do
    # User story:
    # As a local portfolio maintainer,
    # I want to see all ledger transactions that touched this security,
    # so that I can audit my buys and sells without scanning every portfolio.
    #
    # Acceptance criteria:
    # - When the security has no transactions a localized empty state shows.
    # - Each transaction renders date, type, quantity, price, fees, taxes,
    #   portfolio and depot names, and notes.
    # - Transactions are listed newest first.
    # - Decimal values format identically to the rest of the app (via the
    #   existing format helpers — no float drift).

    alias Portfolixir.Ledger
    alias Portfolixir.Portfolios

    setup do
      {:ok, security} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          isin: "US0378331005",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, portfolio} =
        Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
          name: "Local Portfolio",
          base_currency_code: "EUR"
        })

      {:ok, cash} =
        Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Local Cash",
          # The security trades in USD and every booking below is USD, so the
          # linked cash account is USD to keep the booking currency and the
          # cash account consistent (issue #343).
          currency_code: "USD"
        })

      {:ok, depot} =
        Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Main Depot"
        })

      {:ok, security: security, portfolio: portfolio, cash: cash, depot: depot}
    end

    test "shows a localized empty state when there are no transactions",
         %{conn: conn, security: security} do
      {:ok, view, _html} =
        live(conn, "/securities/#{security.id}?tab=transactions")

      assert has_element?(
               view,
               "#detail-tab-panel-transactions",
               "No transactions for this security yet"
             )
    end

    # User story:
    # As a local portfolio maintainer with Portfolio Performance history,
    # I want the transactions detail tab to render dividend rows with no
    # quantity or unit price,
    # so that non-trade bookkeeping entries do not crash the security page.
    #
    # Acceptance criteria:
    # - A dividend transaction with nil quantity and price renders in the
    #   security transactions tab.
    # - Missing quantity and price display as a dash instead of raising.
    # - The dividend gross amount remains visible.
    # - The LiveView stays mounted on the transactions tab.
    test "transactions tab renders non-trade rows with missing quantity and price",
         %{conn: conn, security: security, portfolio: portfolio, cash: cash} do
      {:ok, _dividend} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "dividend",
          date: ~D[2026-03-15],
          gross_amount: Decimal.new("12.34"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "USD",
          notes: "Quarterly dividend"
        })

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=transactions")

      panel = element(view, "#detail-tab-panel-transactions") |> render()
      assert panel =~ "dividend"
      assert panel =~ "Quarterly dividend"
      assert panel =~ "12.34"
      assert panel =~ "—"
      assert has_element?(view, "#detail-tab-transactions[aria-selected='true']")
    end

    test "trades tab renders open positions with unrealised P&L",
         %{conn: conn, security: security, portfolio: portfolio, cash: cash, depot: depot} do
      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-10],
          quantity: Decimal.new("10"),
          price: Decimal.new("100.00"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "USD"
        })

      {:ok, _} =
        Quotes.upsert_many(security.id, [
          %{date: Date.utc_today(), close: "150.00", source: "manual"}
        ])

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=trades")

      panel = element(view, "#detail-tab-panel-trades") |> render()
      assert panel =~ "Open positions"
      # unrealised P&L = 10 * (150 - 100) = +500
      assert panel =~ "+500"
    end

    test "trades tab renders closed round-trips with realised P&L",
         %{conn: conn, security: security, portfolio: portfolio, cash: cash, depot: depot} do
      common = %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        fees: Decimal.new("0"),
        taxes: Decimal.new("0"),
        currency_code: "USD"
      }

      {:ok, _} =
        Ledger.create_transaction(
          Portfolixir.Actor.owner_ui(),
          Map.merge(common, %{
            type: "buy",
            date: ~D[2026-01-10],
            quantity: Decimal.new("10"),
            price: Decimal.new("100.00")
          })
        )

      {:ok, _} =
        Ledger.create_transaction(
          Portfolixir.Actor.owner_ui(),
          Map.merge(common, %{
            type: "sell",
            date: ~D[2026-04-10],
            quantity: Decimal.new("10"),
            price: Decimal.new("150.00")
          })
        )

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=trades")

      panel = element(view, "#detail-tab-panel-trades") |> render()
      assert panel =~ "Closed trades"
      assert panel =~ "+500"
      assert panel =~ "2026-01-10"
      assert panel =~ "2026-04-10"
    end

    test "quotes tab lists the price history newest-first",
         %{conn: conn, security: security} do
      today = Date.utc_today()

      {:ok, _} =
        Quotes.upsert_many(security.id, [
          %{date: today, close: "150.00", source: "manual"},
          %{date: Date.add(today, -3), close: "148.00", source: "manual"},
          %{date: Date.add(today, -10), close: "120.00", source: "manual"}
        ])

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes")

      panel = element(view, "#detail-tab-panel-quotes") |> render()
      assert panel =~ "150.00"
      assert panel =~ "120.00"
      assert panel =~ Date.to_iso8601(today)

      # Newest first: today's quote appears before the older one.
      [_, today_idx | _] = String.split(panel, Date.to_iso8601(today), parts: 2)

      [_, older_idx | _] =
        String.split(panel, Date.to_iso8601(Date.add(today, -10)), parts: 2)

      assert String.length(today_idx) > String.length(older_idx)
    end

    test "holdings tab renders per-portfolio rows with current value",
         %{conn: conn, security: security, portfolio: portfolio, cash: cash, depot: depot} do
      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-10],
          quantity: Decimal.new("10"),
          price: Decimal.new("100.00"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "USD"
        })

      {:ok, _} =
        Quotes.upsert_many(security.id, [
          %{date: Date.utc_today(), close: "150.00", source: "manual"}
        ])

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=holdings")

      panel = element(view, "#detail-tab-panel-holdings") |> render()
      # ADR-0024: the internal portfolio is not surfaced as a grouping column.
      refute panel =~ "Local Portfolio"
      assert panel =~ "Main Depot"
      assert panel =~ "1,500.00"
      # 10 * (150 - 100) = +500 unrealised P&L
      assert panel =~ "+500"
    end

    test "holdings tab empty state when no open positions exist",
         %{conn: conn, security: security} do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=holdings")

      assert has_element?(
               view,
               "#detail-tab-panel-holdings",
               "No open positions"
             )
    end

    test "quotes tab empty state localizes when no quote history exists",
         %{conn: conn, security: security} do
      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=quotes")

      assert has_element?(
               view,
               "#detail-tab-panel-quotes",
               "No price history yet"
             )
    end

    test "lists transactions newest-first with type, qty, price, portfolio and depot",
         %{conn: conn, security: security, portfolio: portfolio, cash: cash, depot: depot} do
      {:ok, _earlier} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-10],
          quantity: Decimal.new("5"),
          price: Decimal.new("150.00"),
          fees: Decimal.new("1.50"),
          taxes: Decimal.new("0"),
          currency_code: "USD",
          notes: "Initial entry"
        })

      {:ok, _later} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "sell",
          date: ~D[2026-04-22],
          quantity: Decimal.new("2"),
          price: Decimal.new("180.00"),
          fees: Decimal.new("1.20"),
          taxes: Decimal.new("0.50"),
          currency_code: "USD"
        })

      {:ok, view, _html} =
        live(conn, "/securities/#{security.id}?tab=transactions")

      panel = element(view, "#detail-tab-panel-transactions") |> render()

      # Both transactions show
      assert panel =~ "2026-04-22"
      assert panel =~ "2026-01-10"
      assert panel =~ "Buy"
      assert panel =~ "Sell"

      # Quantities + prices + fees rendered as decimals
      assert panel =~ "150.00"
      assert panel =~ "180.00"
      assert panel =~ "Main Depot"
      # ADR-0024: the internal portfolio is not surfaced as a grouping column.
      refute panel =~ "Local Portfolio"
      assert panel =~ "Initial entry"

      # Newest first: the April row appears before the January row
      [_, april_idx | _] = String.split(panel, "2026-04-22", parts: 2)
      [_, january_idx | _] = String.split(panel, "2026-01-10", parts: 2)
      assert String.length(april_idx) > String.length(january_idx)
    end
  end

  # User story:
  # As a local portfolio maintainer,
  # I want to quickly assign an asset class to unclassified securities inline,
  # so that I can close classification gaps without leaving the securities list.
  #
  # Acceptance criteria:
  # - The asset_class column renders a <select> for securities where
  #   effective_asset_class is nil (no stored class, no heuristic match).
  # - Changing the select saves the class and removes the select (shows a badge).
  # - The "is unclassified" filter operator limits the list to truly unclassified rows.
  describe "quick-assign asset class" do
    test "renders select form for unclassified security", %{conn: conn} do
      {:ok, _classified} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, _unclassified} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Amazon",
          currency_code: "USD"
        })

      {:ok, view, _html} = live(conn, "/securities")

      assert has_element?(view, "form.quick-assign-form select[name='asset_class']")
      assert has_element?(view, "span.badge", "Equity")
    end

    test "changing the select saves the asset class", %{conn: conn} do
      {:ok, security} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Amazon",
          currency_code: "USD"
        })

      {:ok, view, _html} = live(conn, "/securities")
      assert has_element?(view, "form.quick-assign-form")

      view
      |> element("form.quick-assign-form")
      |> render_change(%{"asset_class" => "equity", "id" => to_string(security.id)})

      refute has_element?(view, "form.quick-assign-form")
      assert has_element?(view, "span.badge", "Equity")

      updated = Portfolixir.Catalog.get_security(security.id)
      assert updated.asset_class == "equity"
    end

    test "selecting empty value is a no-op", %{conn: conn} do
      {:ok, _} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Amazon",
          currency_code: "USD"
        })

      {:ok, view, _html} = live(conn, "/securities")

      view
      |> element("form.quick-assign-form")
      |> render_change(%{"asset_class" => ""})

      assert has_element?(view, "form.quick-assign-form")
    end

    test "invalid security id is silently ignored", %{conn: conn} do
      {:ok, _} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Amazon",
          currency_code: "USD"
        })

      {:ok, view, _html} = live(conn, "/securities")

      view
      |> element("form.quick-assign-form")
      |> render_change(%{"asset_class" => "equity", "id" => "0"})

      assert has_element?(view, "form.quick-assign-form")
    end
  end

  describe "filter popover" do
    test "filter on asset_class adds a chip and narrows the list", %{conn: conn} do
      {:ok, _} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          ticker_symbol: "AAPL",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, _} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
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

    test "filter popover renders is_nil operator for asset_class field", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/securities")
      view |> element("#toggle-filter-popover") |> render_click()

      html =
        view
        |> element("#filter-popover form")
        |> render_change(%{"field" => "asset_class"})

      assert html =~ "is_nil"
    end

    test "is_nil filter on asset_class shows only unclassified securities", %{conn: conn} do
      {:ok, _classified} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Apple Inc.",
          currency_code: "USD",
          asset_class: "equity"
        })

      {:ok, _unclassified} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Amazon",
          currency_code: "USD"
        })

      {:ok, view, _html} = live(conn, "/securities")
      assert has_element?(view, "td", "Apple Inc.")
      assert has_element?(view, "td", "Amazon")

      view |> element("#toggle-filter-popover") |> render_click()

      view
      |> element("#filter-popover form")
      |> render_submit(%{
        "field" => "asset_class",
        "operator" => "is_nil"
      })

      assert has_element?(view, "#filter-chips .chip")
      refute has_element?(view, "td", "Apple Inc.")
      assert has_element?(view, "td", "Amazon")
    end
  end

  # User story:
  # As a portfolio maintainer whose UI locale is German (de),
  # I want the security detail pane (transactions tab, holdings tab, trades tab,
  # and the detail header price) to render Decimal values with the DE locale
  # separators (thousands dot, decimal comma), so that "1.234,50" appears where
  # an EN user would see "1,234.50" — consistent with the portfolio view.
  #
  # Acceptance criteria:
  # - A price of 1234.50 in the transactions tab renders as "1.234,50" for DE
  #   and "1,234.50" for EN.
  # - The holdings tab current value formats correctly for both locales.
  # - The detail header latest price formats correctly for both locales.
  describe "locale-aware number formatting in securities detail" do
    setup do
      {:ok, security} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Format Test Security",
          ticker_symbol: "FMT",
          isin: "DE000FMT0001",
          currency_code: "EUR",
          asset_class: "equity"
        })

      {:ok, portfolio} =
        Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
          name: "Format Portfolio",
          base_currency_code: "EUR"
        })

      {:ok, cash} =
        Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Format Cash",
          currency_code: "EUR"
        })

      {:ok, depot} =
        Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Format Depot"
        })

      {:ok, security: security, portfolio: portfolio, cash: cash, depot: depot}
    end

    test "transactions tab renders price in DE locale as 1.234,50 and EN locale as 1,234.50",
         %{conn: conn, security: security, portfolio: portfolio, cash: cash, depot: depot} do
      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-10],
          quantity: Decimal.new("1"),
          price: Decimal.new("1234.50"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "EUR"
        })

      de_conn = put_req_header(conn, "accept-language", "de")
      {:ok, de_view, _} = live(de_conn, "/securities/#{security.id}?tab=transactions")
      de_panel = element(de_view, "#detail-tab-panel-transactions") |> render()
      assert de_panel =~ "1.234,50"
      refute de_panel =~ "1,234.50"

      en_conn = put_req_header(conn, "accept-language", "en")
      {:ok, en_view, _} = live(en_conn, "/securities/#{security.id}?tab=transactions")
      en_panel = element(en_view, "#detail-tab-panel-transactions") |> render()
      assert en_panel =~ "1,234.50"
      refute en_panel =~ "1.234,50"
    end

    test "holdings tab renders current value in DE locale as 1.234,50 and EN as 1,234.50",
         %{conn: conn, security: security, portfolio: portfolio, cash: cash, depot: depot} do
      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-10],
          quantity: Decimal.new("1"),
          price: Decimal.new("100.00"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "EUR"
        })

      {:ok, _} =
        Quotes.upsert_many(security.id, [
          %{date: Date.utc_today(), close: "1234.50", source: "manual"}
        ])

      de_conn = put_req_header(conn, "accept-language", "de")
      {:ok, de_view, _} = live(de_conn, "/securities/#{security.id}?tab=holdings")
      de_panel = element(de_view, "#detail-tab-panel-holdings") |> render()
      assert de_panel =~ "1.234,50"
      refute de_panel =~ "1,234.50"

      en_conn = put_req_header(conn, "accept-language", "en")
      {:ok, en_view, _} = live(en_conn, "/securities/#{security.id}?tab=holdings")
      en_panel = element(en_view, "#detail-tab-panel-holdings") |> render()
      assert en_panel =~ "1,234.50"
      refute en_panel =~ "1.234,50"
    end

    test "detail header latest price uses DE locale separators",
         %{conn: conn, security: security} do
      {:ok, _} =
        Quotes.upsert_many(security.id, [
          %{date: Date.utc_today(), close: "1234.50", source: "manual"}
        ])

      de_conn = put_req_header(conn, "accept-language", "de")
      {:ok, de_view, _} = live(de_conn, "/securities/#{security.id}")
      de_html = render(de_view)
      assert de_html =~ "1.234,50"
    end
  end

  defp create_trade_accounts(prefix) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "#{prefix} Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash_account} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "#{prefix} Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash_account.id,
        name: "#{prefix} Depot"
      })

    {portfolio, cash_account, depot}
  end

  # User story:
  # As a local portfolio maintainer who clicked "Update logo" on a security far
  # down the list,
  # I want the action status to appear as a fixed-position toast so it is
  # always visible regardless of scroll position,
  # so that I do not have to scroll back to the top to know whether the
  # operation succeeded.
  #
  # Acceptance criteria:
  # - When a logo-refresh result arrives the toast renders with the message
  #   and the correct ARIA role (role="status" for success, role="alert" for
  #   errors).
  # - The toast has a dismiss button.
  # - Clicking dismiss clears the toast from the DOM.
  describe "in-context status toast" do
    setup do
      {:ok, sec} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "Toast Corp",
          currency_code: "EUR",
          provider: "manual",
          asset_class: "equity"
        })

      [sec: sec]
    end

    test "logo refresh success renders a status toast with role=status and dismiss button",
         %{conn: conn, sec: sec} do
      {:ok, view, _html} = live(conn, "/securities")

      # Simulate the async logo-update message arriving.
      send(view.pid, {:logo_update_done, sec.id, {:ok, sec}})
      html = render(view)

      assert html =~ "Logo updated"
      assert has_element?(view, ".status-toast[role='status']", "Logo updated")
      assert has_element?(view, ".status-toast .status-toast__dismiss")
      refute has_element?(view, ".status-toast[role='alert']")
    end

    test "logo refresh failure renders a toast with role=alert", %{conn: conn, sec: sec} do
      {:ok, view, _html} = live(conn, "/securities")

      send(view.pid, {:logo_update_done, sec.id, {:error, :not_found}})
      _html = render(view)

      assert has_element?(view, ".status-toast[role='alert']", "Logo lookup failed")
      assert has_element?(view, ".status-toast .status-toast__dismiss")
      refute has_element?(view, ".status-toast[role='status']")
    end

    test "clicking dismiss clears the toast", %{conn: conn, sec: sec} do
      {:ok, view, _html} = live(conn, "/securities")

      send(view.pid, {:logo_update_done, sec.id, {:ok, sec}})
      assert has_element?(view, ".status-toast", "Logo updated")

      view |> element(".status-toast__dismiss") |> render_click()

      refute has_element?(view, ".status-toast")
    end
  end

  describe "holdings tab — per-position bucket override (issue #446)" do
    setup do
      {:ok, security} =
        Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
          name: "ACME",
          currency_code: "USD"
        })

      {:ok, portfolio} =
        Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
          name: "Main",
          base_currency_code: "EUR"
        })

      {:ok, cash} =
        Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          name: "Cash",
          currency_code: "USD"
        })

      {:ok, depot} =
        Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          cash_account_id: cash.id,
          name: "Main Depot"
        })

      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-10],
          quantity: Decimal.new("10"),
          price: Decimal.new("100.00"),
          fees: Decimal.new("0"),
          taxes: Decimal.new("0"),
          currency_code: "USD"
        })

      {:ok, security: security, portfolio: portfolio, cash: cash, depot: depot}
    end

    # User story:
    # As a local portfolio maintainer,
    # I want to override the buckets on one position, including a deliberate
    # explicit-empty choice that is distinct from inheriting the depot default,
    # so that a single holding can be scoped precisely.
    #
    # Acceptance criteria:
    # - The holdings tab shows the per-position override control with the three
    #   modes (inherit, explicit-empty, explicit list).
    # - Choosing a specific bucket records an explicit override.
    # - Choosing "no buckets (excluded)" records the explicit-empty state, which
    #   the context reports as :explicit_empty (not :inherit).
    test "records an explicit override and an explicit-empty override distinctly",
         %{conn: conn, security: security, depot: depot} do
      {:ok, core} = Buckets.create_bucket(Portfolixir.Actor.owner_ui(), %{name: "Core"})

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=holdings")

      # The override control and the inherit-vs-explicit-empty distinction render.
      assert has_element?(view, "#position-buckets-#{depot.id}")
      assert render(view) =~ "No buckets (excluded)"
      assert render(view) =~ "Inherit from depot"

      # An explicit set: pick Core.
      view
      |> form("#position-buckets-#{depot.id} form", %{
        "mode" => "explicit",
        "bucket_ids" => ["#{core.id}"]
      })
      |> render_submit()

      assert Buckets.position_override(depot.id, security.id) == {:explicit, [core.id]}

      # Explicit-empty: deliberately no buckets, distinct from inherit.
      view
      |> form("#position-buckets-#{depot.id} form", %{"mode" => "empty"})
      |> render_submit()

      assert Buckets.position_override(depot.id, security.id) == :explicit_empty

      # Back to inherit clears the override.
      view
      |> form("#position-buckets-#{depot.id} form", %{"mode" => "inherit"})
      |> render_submit()

      assert Buckets.position_override(depot.id, security.id) == :inherit
    end

    # User story:
    # As a local portfolio maintainer,
    # I want the inherit option to name the depot's default buckets,
    # so that I can see what "inherit" will actually apply before choosing it.
    #
    # Acceptance criteria:
    # - The inherit label lists the depot's default bucket names.
    test "the inherit option shows the depot's default bucket names",
         %{conn: conn, security: security, depot: depot} do
      {:ok, core} = Buckets.create_bucket(Portfolixir.Actor.owner_ui(), %{name: "Core"})
      :ok = Buckets.set_depot_default_buckets(Portfolixir.Actor.owner_ui(), depot, [core.id])

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=holdings")

      assert has_element?(view, "[data-role='inherited-buckets']", "Core")
    end

    # User story:
    # As a local portfolio maintainer,
    # I want a stale bucket id on a position override to fail cleanly,
    # so that a concurrent delete produces a friendly error, not a crash.
    #
    # Acceptance criteria:
    # - Submitting an explicit override with a non-existent bucket id shows the
    #   "bucket no longer exists" error and records no override.
    test "an explicit override with a stale bucket id surfaces a friendly error",
         %{conn: conn, security: security, depot: depot} do
      {:ok, core} = Buckets.create_bucket(Portfolixir.Actor.owner_ui(), %{name: "Core"})

      {:ok, view, _html} = live(conn, "/securities/#{security.id}?tab=holdings")

      # Deleting the bucket behind the rendered form makes the submitted id stale.
      {:ok, _} = Buckets.delete_bucket(Portfolixir.Actor.owner_ui(), core)

      html =
        view
        |> form("#position-buckets-#{depot.id} form", %{
          "mode" => "explicit",
          "bucket_ids" => ["#{core.id}"]
        })
        |> render_submit()

      assert html =~ "That bucket no longer exists"
      assert Buckets.position_override(depot.id, security.id) == :inherit
    end
  end
end
