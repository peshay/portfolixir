defmodule PortfolixirWeb.StaticHeadersTest do
  # Issue #763: Plug.Static runs ahead of the router, so the browser pipeline's
  # secure headers never reached a stored logo or the stylesheet.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog.LogoStore

  # A 1x1 PNG, the smallest body the logo route serves.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
       )

  # User story:
  # As an operator,
  # I want stored logo bytes and static assets served with nosniff,
  # so that a browser never re-interprets a stored file as something else.
  #
  # Acceptance criteria:
  # - A static asset response carries x-content-type-options: nosniff.
  test "static assets are served with nosniff", %{conn: conn} do
    conn = get(conn, "/app.css")

    assert conn.status == 200
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  # User story (E25 S7, F07):
  # As an operator with the UI open in one tab,
  # I want my stored logos and the app's own assets to refuse being embedded
  # by another site,
  # so that a page elsewhere cannot probe which companies I hold by loading
  # their logos from my instance.
  #
  # Acceptance criteria:
  # - Every static asset (the stylesheet, the icons, the vendored scripts)
  #   carries cross-origin-resource-policy: same-origin.
  # - A stored logo, served by the route behind the UI login, carries it too,
  #   as does every page the browser pipeline answers.
  test "static assets, stored logos and pages carry cross-origin-resource-policy: same-origin",
       %{conn: conn} do
    assets = ~w(/app.css /favicon.svg /vendor/phoenix.min.js /vendor/phoenix_live_view.min.js)

    for path <- assets do
      response = get(conn, path)
      assert response.status == 200, path
      assert get_resp_header(response, "cross-origin-resource-policy") == ["same-origin"], path
    end

    file = write_logo!()
    logo = get(conn, "/security_logos/#{file}")
    assert logo.status == 200
    assert get_resp_header(logo, "cross-origin-resource-policy") == ["same-origin"]

    page = get(conn, "/login")
    assert get_resp_header(page, "cross-origin-resource-policy") == ["same-origin"]
  end

  defp write_logo! do
    dir = LogoStore.storage_dir()
    File.mkdir_p!(dir)
    file = "#{System.unique_integer([:positive])}.png"
    path = Path.join(dir, file)
    File.write!(path, @png)
    on_exit(fn -> File.rm(path) end)
    file
  end
end
