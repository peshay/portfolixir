defmodule PortfolixirWeb.SecuritiesAttributeDisplayTest do
  # E25 S3, F29 (#888): a security's attributes are free-form JSON a provider
  # or a token holder wrote, so the securities table renders any stored value
  # without crashing: a scalar as text, anything else as an empty cell.
  use PortfolixirWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Portfolixir.Catalog

  # User story:
  # As the operator browsing my securities with the provider columns shown,
  # I want a stored attribute of an unexpected shape shown as an empty cell,
  # so that one odd value never takes the whole securities page down.
  #
  # Acceptance criteria:
  # - With the exchange-name, market-URL and market-cap-rank columns visible,
  #   a security whose stored values for them are a map, a list and a string
  #   renders; the scalar reads as text and the others as empty cells.
  test "attribute columns render any stored value", %{conn: conn} do
    {:ok, odd} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Synthetic Odd Attributes",
        currency_code: "EUR",
        attributes: %{
          "exchange_name" => %{"nested" => "value"},
          "market_url" => ["a", "list"],
          "market_cap_rank" => "12"
        }
      })

    {:ok, view, _html} = live(conn, "/securities")
    view |> element("#toggle-column-popover") |> render_click()

    view
    |> element("#column-picker form")
    |> render_change(%{
      "columns" => ["name", "attr_exchange_name", "attr_market_url", "attr_market_cap_rank"]
    })

    assert has_element?(view, "#security-row-#{odd.id}", "Synthetic Odd Attributes")
    assert has_element?(view, "#security-row-#{odd.id} td", "12")
    refute render(view) =~ "nested"
  end
end
