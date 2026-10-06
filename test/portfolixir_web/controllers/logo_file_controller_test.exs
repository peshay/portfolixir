defmodule PortfolixirWeb.LogoFileControllerTest do
  # User story (#764; #933, review pass 2):
  # As an operator whose stored logos come in each format the store accepts,
  # I want every one of them served under its own content type,
  # so that the shape check the route shares with the logo reconciliation
  # admits what the store writes and nothing else.
  #
  # Acceptance criteria:
  # - A stored .png, .jpg and .webp answer 200 with image/png, image/jpeg and
  #   image/webp, and nosniff.
  # - An uppercase or unknown extension answers 404.
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog.LogoStore

  @bytes %{
    "png" => <<137, 80, 78, 71, 13, 10, 26, 10>>,
    "jpg" => <<0xFF, 0xD8, 0xFF, 0xE0>>,
    "webp" => "RIFF" <> <<0, 0, 0, 0>> <> "WEBP"
  }

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "portfolixir-logo-serve-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    previous = Application.get_env(:portfolixir, LogoStore, [])
    Application.put_env(:portfolixir, LogoStore, Keyword.put(previous, :storage_dir, tmp))

    on_exit(fn ->
      Application.put_env(:portfolixir, LogoStore, previous)
      File.rm_rf(tmp)
    end)

    %{tmp: tmp}
  end

  test "serves every stored extension under its own content type", %{conn: conn, tmp: tmp} do
    for {ext, type} <- [{"png", "image/png"}, {"jpg", "image/jpeg"}, {"webp", "image/webp"}] do
      File.write!(Path.join(tmp, "7.#{ext}"), @bytes[ext])

      response = get(conn, "/security_logos/7.#{ext}")

      assert response(response, 200) == @bytes[ext], ext
      assert [content_type] = get_resp_header(response, "content-type")
      assert content_type =~ type, ext
      assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    end

    File.write!(Path.join(tmp, "7.PNG"), @bytes["png"])
    File.write!(Path.join(tmp, "7.svg"), "<svg/>")

    assert conn |> get("/security_logos/7.PNG") |> response(404)
    assert conn |> get("/security_logos/7.svg") |> response(404)
  end
end
