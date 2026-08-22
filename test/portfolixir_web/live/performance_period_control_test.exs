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

    # User story (issue #721, D5):
    # As a local portfolio maintainer picking a custom period,
    # I want a labelled from/to pair that validates as a range and shows the
    # applied range in the period control,
    # so that the surface can always answer "what am I looking at" and a
    # mistake is reported against the field that can fix it.
    #
    # Acceptance criteria:
    # - The from/to inputs carry visible labels (not two anonymous fields).
    # - An applied range echoes into the segmented period group as an active
    #   chip carrying the resolved dates.
    # - from > to is refused with the violation on the `to` field; an
    #   unparsable date is flagged on its own field. The shown period keeps.
    test "the custom range is labelled, validates as a range, and echoes as a chip",
         %{conn: conn} do
      seed_accounts()

      {:ok, view, _html} = live(conn, "/portfolio")

      disclosure =
        view |> element(~s(#portfolio-performance details[data-role="period-custom"])) |> render()

      assert disclosure =~ ~s(<label for="performance-from")
      assert disclosure =~ ~s(<label for="performance-to")
      refute disclosure =~ ~s(class="visually-hidden" for="performance-from")

      view
      |> element(~s(form[data-role="period-range"]))
      |> render_submit(%{"from" => "2026-01-01", "to" => "2026-03-31"})

      chip = view |> element(~s([data-role="custom-period-chip"])) |> render()
      assert chip =~ "2026-01-01"
      assert chip =~ "2026-03-31"
      assert chip =~ ~s(aria-pressed="true")

      # Backwards range: refused, reported on the field that can fix it,
      # and the applied period keeps (the chip stays).
      view
      |> element(~s(form[data-role="period-range"]))
      |> render_submit(%{"from" => "2026-03-31", "to" => "2026-01-01"})

      assert view |> element("#performance-to") |> render() =~ ~s(aria-invalid="true")
      assert has_element?(view, ~s([data-role="range-error"]))
      assert has_element?(view, ~s([data-role="custom-period-chip"]))

      # An unparsable from is the from field's error.
      view
      |> element(~s(form[data-role="period-range"]))
      |> render_submit(%{"from" => "not-a-date", "to" => "2026-03-31"})

      assert view |> element("#performance-from") |> render() =~ ~s(aria-invalid="true")
    end

    test "the stylesheet gives segmented options focus and the coarse floor" do
      app_css = File.read!("priv/static/app.css")

      assert app_css =~
               ~r/\.segmented-control__option:focus-visible \{[^}]*outline: 2px solid var\(--color-accent\)/s

      assert app_css =~
               ~r/@media \(pointer: coarse\) \{\s*\.segmented-control__option \{\s*min-height: 44px/s

      # {components.selected-segment}.option-active (design-critic fix round):
      # active = accent fill + on-accent text, no font-weight change — the
      # width-reserve rule (UX-DR18) demands a fixed track.
      active = Regex.run(~r/\.segmented-control__option\.is-active \{[^}]*\}/s, app_css) |> hd()
      assert active =~ "background: var(--color-accent)"
      assert active =~ "color: var(--color-on-accent)"
      refute active =~ "font-weight"
    end
  end
end
