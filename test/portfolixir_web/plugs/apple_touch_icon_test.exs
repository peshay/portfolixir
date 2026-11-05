defmodule PortfolixirWeb.AppleTouchIconTest do
  # Sprint 25 W1 (board 01, pick A; plan D-6): an iPhone's "Add to Home
  # Screen" showed a letter tile, a „P“, because the root layout linked only
  # favicon.svg and a 64 × 64 PNG named favicon.ico, and iOS takes neither.
  # Not async: the UI password is application environment.
  use PortfolixirWeb.ConnCase

  @password "correct-horse-battery-staple"

  setup do
    previous = Application.get_env(:portfolixir, :ui_password)
    Application.put_env(:portfolixir, :ui_password, @password)
    on_exit(fn -> Application.put_env(:portfolixir, :ui_password, previous) end)
    :ok
  end

  # User story:
  # As an operator who adds Portfolixir to an iPhone's home screen,
  # I want the shortcut to show the Portfolixir logo,
  # so that I find the app among the others instead of a letter tile.
  #
  # Acceptance criteria:
  # - The root layout links /apple-touch-icon.png as rel="apple-touch-icon".
  # - GET /apple-touch-icon.png answers 200 image/png with a UI password set
  #   and no session: iOS fetches the icon before any login.
  # - The PNG is 180 × 180 and opaque: its header says colour type 2 (RGB,
  #   no alpha), because iOS fills transparent pixels black.
  test "the home-screen icon is linked, served before login, 180 × 180 and opaque",
       %{conn: conn} do
    html = conn |> get("/login") |> html_response(200)
    assert html =~ ~s(<link rel="apple-touch-icon" href="/apple-touch-icon.png")

    icon = get(conn, "/apple-touch-icon.png")
    assert icon.status == 200
    assert [content_type] = get_resp_header(icon, "content-type")
    assert content_type =~ "image/png"

    assert <<137, "PNG", 13, 10, 26, 10, 13::32, "IHDR", width::32, height::32, _depth,
             colour_type, _rest::binary>> = icon.resp_body

    assert {width, height} == {180, 180}
    assert colour_type == 2
  end
end
