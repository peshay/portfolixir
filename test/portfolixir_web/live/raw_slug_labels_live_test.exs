defmodule PortfolixirWeb.RawSlugLabelsLiveTest do
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.WorldFixtures

  # User story (#785, the review's D2):
  # As a local portfolio maintainer reading the transactions history,
  # I want a balance snapshot to read as "Balance snapshot" in the filter
  # chip and in its row,
  # so that no internal slug reaches the page.
  #
  # Acceptance criteria:
  # - The chip and the row read the localized label; the page never carries
  #   "balance_adjustment".
  test "a balance snapshot reads as a word in the history, never as its slug", %{conn: conn} do
    world = WorldFixtures.base_world()

    {:ok, _snapshot} =
      Ledger.set_cash_balance(Actor.owner_ui(), world.cash, %{
        date: ~D[2026-03-01],
        amount: "4250"
      })

    {:ok, view, html} = live(conn, "/transactions")

    assert has_element?(view, "#transaction-list tbody tr td", "Balance snapshot")
    assert has_element?(view, "button[phx-value-option='balance_adjustment']", "Balance snapshot")
    # The slug may live on in a form value or a chip attribute; it never
    # reaches the text the reader sees.
    refute visible_text(html) =~ "balance_adjustment"
  end

  # User story (#785, the review's D2, second site):
  # As a local portfolio maintainer reading a security's overview,
  # I want its feed to read "Portfolio Performance",
  # so that the master data reads as words, not as an import identifier.
  test "the security overview names the feed, never its identifier", %{conn: conn} do
    security = WorldFixtures.create_security!(name: "Feed Co", ticker: "FED")

    {:ok, security} =
      Catalog.update_security(Actor.owner_ui(), security, %{
        feed: "PORTFOLIO_PERFORMANCE",
        latest_feed: "COINGECKO"
      })

    {:ok, _view, html} = live(conn, "/securities/#{security.id}")

    assert html =~ "Portfolio Performance"
    assert html =~ "CoinGecko"
    refute visible_text(html) =~ "PORTFOLIO_PERFORMANCE"
    refute visible_text(html) =~ "COINGECKO"
  end

  defp visible_text(html), do: html |> Floki.parse_document!() |> Floki.text(sep: " ")
end
