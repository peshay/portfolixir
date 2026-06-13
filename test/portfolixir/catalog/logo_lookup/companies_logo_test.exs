defmodule Portfolixir.Catalog.LogoLookup.CompaniesLogoTest do
  # User story:
  # As a maintainer whose equities get no logo from CoinGecko/Wikipedia,
  # I want companieslogo.com tried as a fallback, so well-known companies
  # (e.g. Baozun) still get a logo without manual work.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.LogoLookup.CompaniesLogo

  defp plug_stub(fun), do: [plug: fun]

  defp html(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body)
  end

  test "returns the og:image from the company logo page" do
    stub =
      plug_stub(fn conn ->
        assert conn.request_path =~ "/baozun/logo/"

        html(
          conn,
          ~s(<html><head><meta property="og:image" content="https://companieslogo.com/img/baozun.png"></head></html>)
        )
      end)

    assert {:ok, "https://companieslogo.com/img/baozun.png"} =
             CompaniesLogo.fetch_image_url("Baozun Inc.", req: stub)
  end

  test "falls back to the first-token slug when the full slug 404s" do
    stub =
      plug_stub(fn conn ->
        cond do
          conn.request_path =~ "/advanced-micro-devices/logo/" ->
            Plug.Conn.send_resp(conn, 404, "")

          conn.request_path =~ "/advanced/logo/" ->
            html(conn, ~s(<meta content="https://x/amd.png" property="og:image">))

          true ->
            Plug.Conn.send_resp(conn, 404, "")
        end
      end)

    assert {:ok, "https://x/amd.png"} =
             CompaniesLogo.fetch_image_url("Advanced Micro Devices", req: stub)
  end

  test "a page without og:image yields :not_found" do
    stub = plug_stub(fn conn -> html(conn, "<html><head></head></html>") end)
    assert :not_found = CompaniesLogo.fetch_image_url("Nothing Co", req: stub)
  end

  test "slug_candidates drops legal suffixes and parentheticals" do
    assert CompaniesLogo.slug_candidates("Apple Inc.") == ["apple"]

    assert CompaniesLogo.slug_candidates("Advanced Micro Devices") ==
             ["advanced-micro-devices", "advanced"]

    assert CompaniesLogo.slug_candidates("Alphabet A (ex Google)") == ["alphabet-a", "alphabet"]
  end
end
