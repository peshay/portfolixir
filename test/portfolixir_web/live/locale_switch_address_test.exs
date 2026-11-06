defmodule PortfolixirWeb.LocaleSwitchAddressTest do
  # The language switch keeps the page's address (closing act of Sprint 26,
  # finding S3): like the privacy switch since its fix (P4, P5), it links to
  # the page's own path and query as its last `handle_params` saw them
  # (`@page_address`, kept by `PortfolixirWeb.PrivacyMode.on_mount/4`), with
  # `locale` set. Every name and figure is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Portfolixir.WorldFixtures

  setup do
    world = base_world(name: "Locale Switch")
    security = create_security!(name: "Locale Fixture AG", ticker: "LFX")
    buy!(world, security, quantity: "3", price: "10", date: ~D[2026-01-05])
    %{security: security}
  end

  # User story (S3, the closing act's finding on the language switch):
  # As the operator switching the language on a security's Predictions tab
  # or a filtered list,
  # I want the switch to bring me back to the page I was on, with its tab,
  # its filters and its comparison,
  # so that switching the language never takes me off the page.
  #
  # Acceptance criteria:
  # - On every page both language links go to the page's own address, path
  #   and query as written (a list's repeated keys and their order
  #   included), with one `locale` set: a security's detail with its tab,
  #   Cash flow's facet with the "After the sale" comparison, a filtered
  #   list, the journal.
  # - A `locale` already in the address is replaced, not repeated.
  # - After a patch inside the page (a detail tab) the links follow the new
  #   address.
  # - A doubled leading slash stays a local path, never a link to another
  #   host.
  test "the language switch keeps the page's address, its tab, filters and comparison", %{
    conn: conn,
    security: security
  } do
    for address <- [
          "/securities/#{security.id}?tab=predictions",
          "/securities?q=Locale&holding=all",
          "/securities?cur[]=EUR&cur[]=USD&q=x",
          "/cashflow?tab=realized&hindsight=rate&hindsight_rate=3",
          "/predictions?author=agent",
          "/journal?keep=1",
          "/?keep=1"
        ] do
      {:ok, _view, html} = live(conn, address)

      for locale <- ["en", "de"] do
        assert locale_href(html, locale) == with_locale(address, locale), address
      end
    end

    {:ok, _view, html} = live(conn, "/journal?locale=de&keep=1")
    assert locale_href(html, "en") == "/journal?keep=1&locale=en"

    {:ok, view, _html} = live(conn, "/securities/#{security.id}")
    view |> element("#detail-tab-predictions") |> render_click()

    assert locale_href(render(view), "en") ==
             "/securities/#{security.id}?tab=predictions&locale=en"

    html =
      conn
      |> get("http://www.example.com//securities/#{security.id}?tab=predictions")
      |> html_response(200)

    assert locale_href(html, "en") == "/securities/#{security.id}?tab=predictions&locale=en"
  end

  defp locale_href(html, locale) do
    [href] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#locale-#{locale}")
      |> LazyHTML.attribute("href")

    href
  end

  defp with_locale(address, locale) do
    separator = if String.contains?(address, "?"), do: "&", else: "?"
    address <> separator <> "locale=" <> locale
  end
end
