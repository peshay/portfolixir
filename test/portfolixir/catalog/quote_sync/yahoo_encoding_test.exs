defmodule Portfolixir.Catalog.QuoteSync.YahooEncodingTest do
  # Issue #763: the ticker is a caller- and import-supplied string placed in
  # the request path of a fixed host. Reserved characters must not rewrite
  # the path or the query.
  use ExUnit.Case, async: true

  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Catalog.Security

  # User story:
  # As an operator whose tickers come from an import,
  # I want a ticker with reserved characters sent as one encoded path segment,
  # so that a value like "A/B?x" can neither change the endpoint nor the query.
  #
  # Acceptance criteria:
  # - "/", "?", "#" and "&" in the ticker are percent-encoded in the path.
  # - The query still carries only the adapter's own parameters.
  test "encodes the ticker as a single unreserved path segment" do
    parent = self()

    plug = fn conn ->
      send(parent, {:request, conn.request_path, conn.query_params})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s({"chart":{"result":[]}}))
    end

    security = %Security{
      ticker_symbol: "A/B?x=1#frag&y",
      provider: "manual",
      currency_code: "EUR"
    }

    assert {:ok, []} = Yahoo.fetch(security, req: [plug: plug])

    assert_received {:request, path, query}
    assert path == "/v8/finance/chart/A%2FB%3Fx%3D1%23frag%26y"
    assert Map.keys(query) |> Enum.sort() == ["interval", "period1", "period2"]
  end
end
