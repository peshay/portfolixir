defmodule PortfolixirWeb.PerformancePeriodControlTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Portfolios

  defp seed_accounts do
    Classifications.ensure_builtins()

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Giro",
        currency_code: "EUR"
      })

    {:ok, _depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Depot"
      })

    portfolio
  end

  # User story (#669, DESIGN.md → Components → segmented control /
  # {components.period-control}):
  # As a local portfolio maintainer picking a performance period,
  # I want the period selector and chart-series toggle to be the app's
  # segmented control and the custom range to sit behind a disclosure,
  # so that the performance surface uses the one control vocabulary instead
  # of bare text controls as permanent chrome.
  #
  # Acceptance criteria:
  # - The period tokens and the €/% series toggle render as segmented
  #   controls with aria-pressed state.
  # - The previous-year select and the from/to custom range sit behind a
  #   "Custom range…" disclosure, not as permanent chrome.
  # - Date entry stays ISO (text input, YYYY-MM-DD pattern) per issue 641.
  # - The segmented option class carries the focus treatment and the
  #   coarse-pointer target floor (UX-DR6).
  describe "performance period control (#669)" do
    test "period tokens and series toggle are segmented controls", %{conn: conn} do
      seed_accounts()

      {:ok, view, _html} = live(conn, "/portfolio")

      assert has_element?(
               view,
               ~s(#portfolio-performance [data-role="period-tokens"].segmented-control button.segmented-control__option[aria-pressed])
             )

      assert has_element?(
               view,
               ~s(#portfolio-performance [data-role="chart-series"].segmented-control button.segmented-control__option[aria-pressed])
             )

      refute has_element?(view, "#portfolio-performance .button-mini[phx-click='select_period']")
    end

    test "the custom range sits behind a disclosure with ISO date fields", %{conn: conn} do
      seed_accounts()

      {:ok, view, _html} = live(conn, "/portfolio")

      assert has_element?(view, ~s(#portfolio-performance details[data-role="period-custom"]))

      disclosure =
        view |> element(~s(#portfolio-performance details[data-role="period-custom"])) |> render()

      assert disclosure =~ "Custom range"

      # ISO date entry survives (issue 641): text inputs with the ISO pattern.
      assert disclosure =~ ~s(id="performance-from")
      assert disclosure =~ ~s(placeholder="YYYY-MM-DD")
      assert disclosure =~ ~s(pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}")

      # The year re-chain stays available inside the disclosure.
      assert disclosure =~ ~s(id="performance-year")
    end

    test "the stylesheet gives segmented options focus and the coarse floor" do
      app_css = File.read!("priv/static/app.css")

      assert app_css =~
               ~r/\.segmented-control__option:focus-visible \{[^}]*outline: 2px solid var\(--color-accent\)/s

      assert app_css =~
               ~r/@media \(pointer: coarse\) \{\s*\.segmented-control__option \{\s*min-height: 44px/s
    end
  end
end
