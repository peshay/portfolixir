defmodule Portfolixir.Catalog.LogoLookupTest do
  # User story:
  # As a local portfolio maintainer,
  # I want Portfolixir to find a logo for each new security on its own
  # (crypto via CoinGecko, equities/ETFs via Wikipedia), so I don't have to
  # download images manually like I did in Portfolio Performance.
  #
  # Acceptance criteria for the dispatcher:
  # - Crypto with `provider="coingecko"` and an `online_id` consults the
  #   CoinGecko detail API and yields `{:ok, url, :coingecko}`.
  # - Equity/ETF/Fund consults Wikipedia REST `page/summary/{title}` and
  #   yields `{:ok, url, :wikipedia}` when the page returns an
  #   `originalimage`.
  # - Anything else (index, commodity, bond, crypto without online_id,
  #   …) returns `:skip` without touching the network.
  # - Transport-level errors are surfaced as `{:error, reason}` so the
  #   caller can log them; the security is left unchanged.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Catalog.Security

  defp plug_stub(fun), do: [plug: fun]

  defp json_response(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  describe "find_url/2" do
    test "crypto -> CoinGecko detail endpoint -> image.large" do
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "/coins/bitcoin"

          json_response(conn, 200, %{
            "image" => %{
              "thumb" => "thumb.png",
              "small" => "small.png",
              "large" => "https://coingecko/large.png"
            }
          })
        end)

      security = %Security{
        provider: "coingecko",
        online_id: "bitcoin",
        asset_class: "crypto",
        name: "Bitcoin"
      }

      assert {:ok, "https://coingecko/large.png", :coingecko} =
               LogoLookup.find_url(security, req: stub)
    end

    test "equity -> Wikipedia REST page summary -> originalimage.source" do
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "/api/rest_v1/page/summary/"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/Apple_Inc..png"}
          })
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "Apple Inc.",
        ticker_symbol: "AAPL"
      }

      assert {:ok, "https://wikipedia/Apple_Inc..png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "Wikipedia page without originalimage -> :skip" do
      stub =
        plug_stub(fn conn ->
          # No originalimage in the body
          json_response(conn, 200, %{"title" => "Whatever"})
        end)

      security = %Security{provider: "manual", asset_class: "equity", name: "Whatever Inc."}

      assert :skip = LogoLookup.find_url(security, req: stub)
    end

    test "ambiguous bare names get the (company) disambiguator on Wikipedia" do
      # "Apple" alone resolves to the fruit; "Apple (company)" redirects to
      # Apple Inc. The dispatcher must prefer the (company) variant for
      # names without a corporate suffix to avoid picking up the wrong page.
      stub =
        plug_stub(fn conn ->
          assert conn.request_path =~ "Apple%20%28company%29"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/Apple_logo.png"}
          })
        end)

      security = %Security{
        provider: "manual",
        asset_class: "equity",
        name: "Apple"
      }

      assert {:ok, "https://wikipedia/Apple_logo.png", :wikipedia} =
               LogoLookup.find_url(security, req: stub)
    end

    test "names that already carry a corporate suffix go straight to the bare lookup" do
      stub =
        plug_stub(fn conn ->
          # No (company) suffix appended for names like "SAP SE" or "Apple Inc."
          refute conn.request_path =~ "company"

          json_response(conn, 200, %{
            "originalimage" => %{"source" => "https://wikipedia/SAP.png"}
          })
        end)

      for name <- ["SAP SE", "Apple Inc.", "Tesla, Inc", "Siemens AG"] do
        security = %Security{provider: "manual", asset_class: "equity", name: name}
        assert {:ok, _url, :wikipedia} = LogoLookup.find_url(security, req: stub)
      end
    end

    test "asset classes outside the heuristic return :skip without HTTP" do
      stub =
        plug_stub(fn _conn ->
          flunk("must not hit the network for skipped asset classes")
        end)

      for {asset_class, online_id} <- [
            {"index", nil},
            {"commodity", nil},
            {"bond", nil},
            {"crypto", nil}
          ] do
        security = %Security{
          provider: "manual",
          asset_class: asset_class,
          online_id: online_id,
          name: "X"
        }

        assert :skip = LogoLookup.find_url(security, req: stub)
      end
    end

    test "transport errors propagate as {:error, reason}" do
      stub =
        plug_stub(fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.send_resp(500, "boom")
        end)

      security = %Security{
        provider: "coingecko",
        online_id: "bitcoin",
        asset_class: "crypto",
        name: "Bitcoin"
      }

      assert {:error, _} = LogoLookup.find_url(security, req: stub)
    end
  end
end
