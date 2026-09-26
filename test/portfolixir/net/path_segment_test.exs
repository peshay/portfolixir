defmodule Portfolixir.Net.PathSegmentTest do
  # E25 S3, F31 (#888): a stored identifier placed in a provider's request
  # path goes through one shared helper. Percent-encoding leaves the dot
  # unreserved, so a value made only of dots would survive encoding as a
  # relative-path segment and move the request to another path on the same
  # host; the helper refuses such values rather than re-encoding them, and
  # every adapter then makes no request.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog.LogoLookup.{CompaniesLogo, Wikipedia}
  alias Portfolixir.Catalog.QuoteSync.Yahoo
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.CoinGecko
  alias Portfolixir.Net.PathSegment

  @relative ["", ".", "..", "..."]

  defp recording_stub(test_pid, answer \\ nil) do
    [
      plug: fn conn ->
        send(test_pid, {:request, conn.host, conn.request_path})

        if answer do
          answer.(conn)
        else
          Plug.Conn.send_resp(conn, 404, "")
        end
      end
    ]
  end

  # User story:
  # As an operator whose tickers and coin ids come from imports, searches and
  # provider payloads,
  # I want every identifier placed in a provider's request path to be exactly
  # one segment,
  # so that a stored value can never move a request to another path on the
  # provider's host.
  #
  # Acceptance criteria:
  # - Empty and dot-only values are refused, never re-encoded.
  # - Any other value is one percent-encoded segment: reserved characters are
  #   encoded, real ticker shapes keep their dots and dashes.
  # - A non-string is refused.
  test "the helper refuses relative-path segments and encodes the rest" do
    for value <- @relative ++ [nil, 42] do
      assert PathSegment.encode(value) == {:error, :invalid_path_segment}, inspect(value)
    end

    assert PathSegment.encode("SAP.DE") == {:ok, "SAP.DE"}
    assert PathSegment.encode("BRK-B") == {:ok, "BRK-B"}
    assert PathSegment.encode("A/B?x#y") == {:ok, "A%2FB%3Fx%23y"}
    assert PathSegment.encode("..a") == {:ok, "..a"}
    assert PathSegment.encode("Apple (company)") == {:ok, "Apple%20%28company%29"}
  end

  # Acceptance criteria:
  # - For a relative-path ticker, coin id, page title, Wikidata id or Commons
  #   file name, the adapter returns an error or not-found and no request
  #   reaches the provider with it.
  test "each adapter makes no request for a relative-path segment" do
    test_pid = self()

    for value <- @relative -- [""] do
      assert {:error, :invalid_path_segment} =
               Yahoo.fetch(%Security{ticker_symbol: value, provider: "manual"},
                 req: recording_stub(test_pid)
               )

      assert {:error, :invalid_path_segment} =
               CoinGecko.fetch_image_url(value, req: recording_stub(test_pid))

      assert {:error, :invalid_path_segment} =
               Wikipedia.lookup(value, req: recording_stub(test_pid))

      refute_received {:request, _, _}, "a request was made for #{inspect(value)}"
    end

    assert {:error, :invalid_path_segment} =
             CoinGecko.fetch_image_url("", req: recording_stub(test_pid))

    refute_received {:request, _, _}
  end

  test "identifiers from a provider payload are refused the same way" do
    test_pid = self()

    # A summary naming a dot-only Wikidata item: the item is never requested,
    # and the summary's own image is used instead.
    summary = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "wikibase_item" => "..",
          "originalimage" => %{"source" => "https://upload.wikimedia.org/x.png"}
        })
      )
    end

    assert {:ok, "https://upload.wikimedia.org/x.png"} =
             Wikipedia.lookup("Synthetic", req: recording_stub(test_pid, summary))

    assert_received {:request, "en.wikipedia.org", "/api/rest_v1/page/summary/Synthetic"}
    refute_received {:request, _, _}

    # A Wikidata entity naming a dot-only Commons file yields no Commons URL.
    answer = fn conn ->
      body =
        case conn.host do
          "en.wikipedia.org" ->
            %{"wikibase_item" => "Q1"}

          "www.wikidata.org" ->
            %{
              "entities" => %{
                "Q1" => %{
                  "claims" => %{
                    "P154" => [%{"mainsnak" => %{"datavalue" => %{"value" => ".."}}}]
                  }
                }
              }
            }
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end

    assert :not_found = Wikipedia.lookup("Synthetic", req: recording_stub(test_pid, answer))

    # companieslogo slugs are built from letters and digits only, and still
    # pass through the helper: a name with no usable token makes no request.
    assert :not_found = CompaniesLogo.fetch_image_url("...", req: recording_stub(test_pid))
    refute_received {:request, "companieslogo.com", _}
  end

  # User story:
  # As an operator,
  # I want a ticker or a provider id made only of dots refused when it is
  # stored,
  # so that such a value never waits in my catalog for the next sync.
  #
  # Acceptance criteria:
  # - A dot-only ticker or online id is a field error on the security
  #   changeset; real shapes with dots (SAP.DE, 0005.HK) still pass.
  # - An online id carrying whitespace or URL syntax is refused like a ticker.
  test "the security changeset refuses dot-only tickers and ids" do
    base = %{name: "Synthetic", currency_code: "EUR"}

    for value <- [".", "..", "..."] do
      changeset = Security.changeset(%Security{}, Map.put(base, :ticker_symbol, value))
      refute changeset.valid?, value
      assert errors_on(changeset)[:ticker_symbol]

      changeset =
        Security.changeset(
          %Security{},
          Map.merge(base, %{provider: "coingecko", online_id: value})
        )

      refute changeset.valid?, value
      assert errors_on(changeset)[:online_id]
    end

    for value <- ["a/b", "a b", "a?b", "a#b", "a%2Fb", String.duplicate("a", 129)] do
      changeset =
        Security.changeset(
          %Security{},
          Map.merge(base, %{provider: "coingecko", online_id: value})
        )

      refute changeset.valid?, value
      assert errors_on(changeset)[:online_id]
    end

    for {ticker, id} <- [{"SAP.DE", "US0378331005"}, {"0005.HK", "usd-coin"}] do
      changeset =
        Security.changeset(
          %Security{},
          Map.merge(base, %{ticker_symbol: ticker, online_id: id})
        )

      assert changeset.valid?, ticker
    end
  end
end
