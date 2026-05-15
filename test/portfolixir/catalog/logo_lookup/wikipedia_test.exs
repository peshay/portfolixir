defmodule Portfolixir.Catalog.LogoLookup.WikipediaTest do
  # User story (covered through the dispatcher in logo_lookup_test):
  # Equity / ETF / Fund logos come from Wikipedia REST, since there is no
  # free open-data equivalent of CoinGecko for stocks.
  #
  # Acceptance criteria:
  # - The adapter calls `/api/rest_v1/page/summary/{title}` with the
  #   security name URL-encoded.
  # - Returns `{:ok, url}` when `body["originalimage"]["source"]` exists.
  # - Returns `:not_found` when the page resolves but has no original
  #   image.
  # - Returns `{:error, ...}` on 4xx/5xx or transport errors so the
  #   caller does not silently swallow problems.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.LogoLookup.Wikipedia

  defp plug_stub(fun), do: [plug: fun]

  test "URL-encodes the title in the request path" do
    stub =
      plug_stub(fn conn ->
        # Apple Inc. -> Apple%20Inc.
        assert conn.request_path =~ "Apple%20Inc."

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"originalimage" => %{"source" => "https://wikipedia/Apple.png"}})
        )
      end)

    assert {:ok, "https://wikipedia/Apple.png"} = Wikipedia.lookup("Apple Inc.", req: stub)
  end

  test "returns :not_found when the response has no originalimage" do
    stub =
      plug_stub(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"title" => "Apple Inc."}))
      end)

    assert :not_found = Wikipedia.lookup("Apple Inc.", req: stub)
  end

  test "returns {:error, ...} on 404" do
    stub =
      plug_stub(fn conn ->
        Plug.Conn.send_resp(conn, 404, "not found")
      end)

    assert {:error, _} = Wikipedia.lookup("DoesNotExist", req: stub)
  end
end
