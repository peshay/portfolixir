defmodule PortfolixirWeb.SecuritiesUrlFiltersTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes

  defp create_security(attrs) do
    defaults = %{currency_code: "EUR", asset_class: "equity"}
    {:ok, security} = Catalog.create_security(Actor.owner_ui(), Map.merge(defaults, attrs))
    security
  end

  # User story:
  # As a local portfolio maintainer,
  # I want the securities list filters to be URL-addressable,
  # so that a link can open the list pre-filtered (issue #651, UX-DR2:
  # the Overview data-quality line links to a pre-filtered securities list).
  #
  # Acceptance criteria:
  # - `?q=` opens the list pre-searched.
  # - `?holding=` opens the list pre-filtered by holding status.
  # - `?filter[]=key:op[:value]` opens the list with column filters applied
  #   and their chips visible.
  # - Invalid filter params are dropped without crashing.
  describe "URL-addressable filters (#651)" do
    test "?q= opens the list pre-searched", %{conn: conn} do
      create_security(%{name: "Apple Inc.", ticker_symbol: "AAPL"})
      create_security(%{name: "Bitcoin", ticker_symbol: "BTC", asset_class: "crypto"})

      {:ok, view, _html} = live(conn, "/securities?q=Apple")

      assert has_element?(view, "td", "Apple Inc.")
      refute has_element?(view, "td", "Bitcoin")
      assert has_element?(view, "#securities-search-form input[name='query'][value='Apple']")
    end

    test "?holding= opens the list pre-filtered by holding status", %{conn: conn} do
      create_security(%{name: "Never Held ETF", ticker_symbol: "NEVR"})

      {:ok, view, _html} = live(conn, "/securities?holding=held")

      refute has_element?(view, "td", "Never Held ETF")
      assert has_element?(view, "[data-role='no-results']")
    end

    test "?filter[]= applies a column filter and renders its chip", %{conn: conn} do
      create_security(%{name: "Classified Co.", ticker_symbol: "CLS"})

      # A name no asset-class heuristic matches stays genuinely unclassified.
      {:ok, _unclassified} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Mystery Instrument",
          ticker_symbol: "MYS",
          currency_code: "EUR"
        })

      {:ok, view, _html} = live(conn, "/securities?filter[]=asset_class:is_nil")

      assert has_element?(view, "td", "Mystery Instrument")
      refute has_element?(view, "td", "Classified Co.")
      assert has_element?(view, "#filter-chips .chip")
    end

    test "?filter[]= with a value applies an equality filter", %{conn: conn} do
      create_security(%{name: "Euro Stock", ticker_symbol: "EUS"})
      create_security(%{name: "Dollar Stock", ticker_symbol: "USS", currency_code: "USD"})

      {:ok, view, _html} = live(conn, "/securities?filter[]=currency_code:eq:USD")

      assert has_element?(view, "td", "Dollar Stock")
      refute has_element?(view, "td", "Euro Stock")
    end

    test "invalid filter params are dropped without crashing", %{conn: conn} do
      create_security(%{name: "Sane Co.", ticker_symbol: "SANE"})

      {:ok, view, _html} =
        live(conn, "/securities?filter[]=bogus_key:eq:zzz&filter[]=oops&dq=bogus")

      assert has_element?(view, "td", "Sane Co.")
      refute has_element?(view, "#filter-chips .chip")
    end

    test "applying a search patches the URL so the state is linkable", %{conn: conn} do
      create_security(%{name: "Apple Inc.", ticker_symbol: "AAPL"})

      {:ok, view, _html} = live(conn, "/securities")

      view
      |> form("#securities-search-form", %{"query" => "Apple"})
      |> render_change()

      assert_patch(view, "/securities?q=Apple")
    end

    test "changing the holding status patches the URL", %{conn: conn} do
      create_security(%{name: "Apple Inc.", ticker_symbol: "AAPL"})

      {:ok, view, _html} = live(conn, "/securities")

      view
      |> element(~s(button[phx-click="set_holding_status"][phx-value-status="held"]))
      |> render_click()

      assert_patch(view, "/securities?holding=held")
    end

    test "selecting a row keeps the active filters in the URL", %{conn: conn} do
      apple = create_security(%{name: "Apple Inc.", ticker_symbol: "AAPL"})

      {:ok, view, _html} = live(conn, "/securities?q=Apple")

      view
      |> element("#security-row-#{apple.id} .row-target")
      |> render_click()

      assert_patch(view, "/securities/#{apple.id}?q=Apple")
      assert has_element?(view, "#securities-search-form input[name='query'][value='Apple']")
    end
  end

  # User story:
  # As a local portfolio maintainer following a data-quality count,
  # I want dedicated filters for missing/stale quotes and missing logos,
  # so that the count links to exactly the offending securities (issue #561).
  #
  # Acceptance criteria:
  # - `?dq=stale_quote` lists securities without a quote in the last 7 days
  #   (including those with no quote at all — the dashboard's count).
  # - `?dq=missing_quote` lists securities with no quote at all.
  # - `?dq=missing_logo` lists securities without a stored logo.
  # - The active data-quality filter renders as a removable chip.
  describe "data-quality filters (#561)" do
    test "?dq=stale_quote lists securities without a recent quote", %{conn: conn} do
      fresh = create_security(%{name: "Fresh Quote Co.", ticker_symbol: "FRSH"})
      stale = create_security(%{name: "Stale Quote Co.", ticker_symbol: "STAL"})
      create_security(%{name: "No Quote Co.", ticker_symbol: "NOQ"})

      today = Date.utc_today()

      {:ok, _} =
        Quotes.upsert_many(fresh.id, [%{date: today, close: "10.00", source: "manual"}])

      {:ok, _} =
        Quotes.upsert_many(stale.id, [
          %{date: Date.add(today, -30), close: "10.00", source: "manual"}
        ])

      {:ok, view, _html} = live(conn, "/securities?dq=stale_quote")

      assert has_element?(view, "td", "Stale Quote Co.")
      assert has_element?(view, "td", "No Quote Co.")
      refute has_element?(view, "td", "Fresh Quote Co.")
      assert has_element?(view, "#filter-chips .chip", "No quote in 7 days")
    end

    test "?dq=missing_quote lists securities with no quote at all", %{conn: conn} do
      quoted = create_security(%{name: "Quoted Co.", ticker_symbol: "QTD"})
      create_security(%{name: "Unquoted Co.", ticker_symbol: "UNQ"})

      {:ok, _} =
        Quotes.upsert_many(quoted.id, [
          %{date: Date.add(Date.utc_today(), -30), close: "10.00", source: "manual"}
        ])

      {:ok, view, _html} = live(conn, "/securities?dq=missing_quote")

      assert has_element?(view, "td", "Unquoted Co.")
      refute has_element?(view, "td", "Quoted Co.")
    end

    test "?dq=missing_logo lists securities without a stored logo", %{conn: conn} do
      with_logo = create_security(%{name: "Logo Co.", ticker_symbol: "LOGO"})

      {:ok, _} =
        Catalog.update_security(Actor.owner_ui(), with_logo, %{
          attributes: %{"logo_path" => "logos/logo-co.png"}
        })

      create_security(%{name: "Logoless Co.", ticker_symbol: "NLGO"})

      {:ok, view, _html} = live(conn, "/securities?dq=missing_logo")

      assert has_element?(view, "td", "Logoless Co.")
      refute has_element?(view, "td", "Logo Co.")
    end

    # User story:
    # As a local portfolio maintainer looking at the securities without a logo,
    # I want a bulk "retry logo lookup" action with inline feedback,
    # so that missing logos are re-attempted in one step instead of per row
    # (issue #561).
    #
    # Acceptance criteria:
    # - The missing-logo filtered list offers a bulk retry button.
    # - Triggering it reports the queued lookup inline, in a status region
    #   that exists before the action runs (no toast, no timer).
    test "the missing-logo list offers a bulk logo retry with inline feedback",
         %{conn: conn} do
      create_security(%{name: "Logoless Co.", ticker_symbol: "NLGO"})

      {:ok, view, _html} = live(conn, "/securities?dq=missing_logo")

      assert has_element?(view, "#retry-missing-logos")
      assert has_element?(view, "#logo-retry-result[role='status']")

      view
      |> element("#retry-missing-logos")
      |> render_click()

      assert has_element?(
               view,
               "#logo-retry-result",
               "Logo lookup queued for all securities without a logo."
             )
    end

    test "the bulk logo retry is absent without the missing-logo filter", %{conn: conn} do
      create_security(%{name: "Plain Co.", ticker_symbol: "PLN"})

      {:ok, view, _html} = live(conn, "/securities")

      refute has_element?(view, "#retry-missing-logos")
    end

    test "removing the data-quality chip patches back to the unfiltered list",
         %{conn: conn} do
      create_security(%{name: "Plain Co.", ticker_symbol: "PLN"})

      {:ok, view, _html} = live(conn, "/securities?dq=missing_logo")

      view
      |> element(~s(#filter-chips button[phx-click="remove_dq"]))
      |> render_click()

      assert_patch(view, "/securities")
      refute has_element?(view, "#filter-chips .chip")
    end
  end
end
