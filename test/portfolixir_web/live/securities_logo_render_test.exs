defmodule PortfolixirWeb.SecuritiesLogoRenderTest do
  # User story:
  # As a local portfolio maintainer,
  # I want a small logo next to every security so I can scan my list faster.
  # When a logo has been discovered, it should render inline; otherwise a
  # tasteful initial-letter circle should stand in.
  #
  # This module covers the render side of the contract:
  # - With `attributes["logo_path"]`, an `<img>` is rendered with that
  #   src in the row and in the detail-pane header.
  # - Without it, an initial-letter fallback span is rendered.
  use PortfolixirWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  test "renders an img tag when the security has a logo_path", %{conn: conn} do
    {:ok, sec} =
      Catalog.create_security(%{
        name: "Apple Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, _updated} =
      Catalog.update_security(sec, %{
        attributes: %{
          "logo_path" => "/security_logos/#{sec.id}.png",
          "logo_source" => "wikipedia"
        }
      })

    {:ok, view, _html} = live(conn, "/securities")
    html = render(view)

    assert html =~ ~s(src="/security_logos/#{sec.id}.png")
    assert html =~ ~s(class="security-logo security-logo--row")
  end

  test "renders the initial-letter fallback when no logo_path is set",
       %{conn: conn} do
    {:ok, _sec} =
      Catalog.create_security(%{
        name: "Apple Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    {:ok, view, _html} = live(conn, "/securities")
    html = render(view)

    assert html =~ ~s(security-logo--initial)
    # First letter is 'A' uppercase
    assert html =~ ~r/security-logo--initial[^>]*>[\s]*A[\s]*</
  end

  test "renders the logo in the detail-pane header when a security is selected",
       %{conn: conn} do
    {:ok, sec} =
      Catalog.create_security(%{
        name: "Bitcoin",
        currency_code: "EUR",
        provider: "coingecko",
        asset_class: "crypto",
        online_id: "bitcoin"
      })

    {:ok, _updated} =
      Catalog.update_security(sec, %{
        attributes: %{
          "logo_path" => "/security_logos/#{sec.id}.png",
          "logo_source" => "coingecko"
        }
      })

    {:ok, view, _html} = live(conn, "/securities?id=#{sec.id}")
    html = render(view)

    assert html =~ ~s(security-logo--lg)
    assert html =~ ~s(src="/security_logos/#{sec.id}.png")
  end
end
