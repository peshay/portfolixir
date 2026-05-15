defmodule Portfolixir.Catalog.LogoStoreTest do
  # User story (continuation of the dispatcher story):
  # Once a logo URL is known, Portfolixir downloads the image once and stores
  # it next to the app's other static assets, so that
  #   - the list view never makes third-party requests at render time,
  #   - the logo survives the upstream service going down or rotating URLs,
  #   - the user's holdings are not leaked to the source's CDN logs.
  #
  # Acceptance criteria:
  # - Successful PNG download is written to
  #   `<storage_dir>/<security_id>.png` and the security's
  #   `attributes["logo_path"]` + `attributes["logo_source"]` are updated.
  # - Content types outside the allowlist (png/jpg/jpeg/webp) are
  #   refused.
  # - Files larger than the configured max size are refused.
  # - Network/HTTP errors return `{:error, _}` and do not touch the DB.
  use Portfolixir.DataCase, async: false

  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoStore
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Repo

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  setup do
    tmp = Path.join(System.tmp_dir!(), "portfolixir-logos-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, sec} =
      Catalog.create_security(%{
        name: "Apple Inc.",
        currency_code: "USD",
        provider: "manual",
        asset_class: "equity"
      })

    %{tmp: tmp, security: sec}
  end

  defp png_stub(bytes, content_type \\ "image/png") do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type(content_type)
        |> Plug.Conn.send_resp(200, bytes)
      end
    ]
  end

  test "writes the image to <storage_dir>/<id>.png and updates the attributes",
       %{tmp: tmp, security: sec} do
    assert {:ok, updated} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.png",
               :wikipedia,
               req: png_stub(@png),
               storage_dir: tmp
             )

    expected_path = "/security_logos/#{sec.id}.png"
    assert updated.attributes["logo_path"] == expected_path
    assert updated.attributes["logo_source"] == "wikipedia"
    assert File.read!(Path.join(tmp, "#{sec.id}.png")) == @png

    # Reload from DB to verify persistence
    reloaded = Repo.get!(Security, sec.id)
    assert reloaded.attributes["logo_path"] == expected_path
  end

  test "refuses content types outside the image allowlist",
       %{tmp: tmp, security: sec} do
    assert {:error, :unsupported_content_type} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.html",
               :wikipedia,
               req: png_stub("<html/>", "text/html"),
               storage_dir: tmp
             )

    refute File.exists?(Path.join(tmp, "#{sec.id}.png"))
    refute Repo.get!(Security, sec.id).attributes["logo_path"]
  end

  test "refuses SVG content and leaves the security untouched",
       %{tmp: tmp, security: sec} do
    svg = ~S|<svg xmlns="http://www.w3.org/2000/svg"><script>alert("x")</script></svg>|

    assert {:error, :unsupported_content_type} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.svg",
               :wikipedia,
               req: png_stub(svg, "image/svg+xml"),
               storage_dir: tmp
             )

    refute File.exists?(Path.join(tmp, "#{sec.id}.svg"))
    refute Repo.get!(Security, sec.id).attributes["logo_path"]
  end

  test "refuses files larger than the size limit", %{tmp: tmp, security: sec} do
    big = :binary.copy(<<0>>, 300 * 1024)

    assert {:error, :too_large} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/big.png",
               :wikipedia,
               req: png_stub(big),
               storage_dir: tmp,
               max_bytes: 256 * 1024
             )

    refute File.exists?(Path.join(tmp, "#{sec.id}.png"))
  end

  test "transport errors surface and leave the security untouched",
       %{tmp: tmp, security: sec} do
    stub = [
      plug: fn conn ->
        Plug.Conn.send_resp(conn, 503, "down")
      end
    ]

    assert {:error, _} =
             LogoStore.download_and_store(
               sec,
               "https://example.test/logo.png",
               :wikipedia,
               req: stub,
               storage_dir: tmp
             )

    refute Repo.get!(Security, sec.id).attributes["logo_path"]
  end
end
