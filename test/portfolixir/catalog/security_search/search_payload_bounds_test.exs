defmodule Portfolixir.Catalog.SecuritySearch.SearchPayloadBoundsTest do
  # E25 S3, F29 (#888): every field a search provider sends is type-matched
  # and size-bounded before it reaches a search result, the API and MCP
  # response, or a security's attributes; the raw provider entry is not
  # echoed, only the allow-listed keys the attributes read.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch
  alias Portfolixir.Catalog.SecuritySearch.{CoinGecko, PortfolioPerformance, SearchResult}
  alias PortfolixirWeb.Api.V1.JSON

  @blob String.duplicate("s", 100_000)

  defp json_stub(body) do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end
    ]
  end

  defp scalar_and_bounded?(map) do
    Enum.all?(map, fn {key, value} ->
      is_binary(key) and byte_size(key) <= 64 and
        ((is_binary(value) and byte_size(value) <= 500) or is_number(value) or is_boolean(value))
    end)
  end

  # User story:
  # As an operator who creates securities from a public search API I do not
  # control,
  # I want every field of a search answer checked for its type and bounded in
  # size, and the raw answer never echoed,
  # so that a hostile or broken answer can neither bloat my catalog and my
  # agent's responses nor carry arbitrary structures into them.
  #
  # Acceptance criteria:
  # - A text field of the wrong type or over its bound is absent from the
  #   result; a result whose name is unusable is dropped.
  # - Markets keep only type-matched, bounded fields; properties keep only
  #   bounded scalars whose key and text meet the text rule (no control
  #   character, which the database refuses in a stored attribute).
  # - The raw echo carries only the allow-listed keys, as bounded scalars, and
  #   the serialized result contains no unlisted provider field.
  # - The attributes a result writes are bounded scalars.
  test "Portfolio Performance entries with non-scalar or oversized fields are bounded" do
    body = [
      %{
        "description" => "Synthetic Corp",
        "isin" => %{"not" => "a string"},
        "wkn" => String.duplicate("W", 5000),
        "type" => "Common Stock",
        "unlisted_blob" => @blob,
        "markets" => [
          %{
            "symbol" => "SYN",
            "currency" => "EUR",
            "exchange" => "XETR",
            "exchangeName" => String.duplicate("E", 5000),
            "url" => %{"not" => "a url"},
            "properties" => %{
              "nested" => %{"a" => 1},
              "ok" => "fine",
              "big" => String.duplicate("b", 5000),
              "nul_value" => "a\u0000b",
              "nul\u0000key" => "x",
              "control" => "a\u0007b"
            }
          },
          %{"symbol" => ["not", "a", "symbol"], "currency" => "EUR"}
        ]
      },
      %{"description" => String.duplicate("N", 10_000), "type" => "ETF"},
      %{"description" => ["not", "a", "name"]}
    ]

    assert {:ok, [result]} =
             SecuritySearch.search("synthetic",
               providers: [PortfolioPerformance],
               req: json_stub(body)
             )

    assert result.name == "Synthetic Corp"
    assert result.isin == nil
    assert result.wkn == nil
    assert result.raw == %{"type" => "Common Stock"}

    assert [market] = result.markets
    assert market.symbol == "SYN"
    assert market.exchange_name == nil
    assert market.url == nil
    assert market.properties == %{"ok" => "fine"}

    encoded = result |> JSON.search_result() |> Jason.encode!()
    refute encoded =~ "unlisted_blob"
    refute encoded =~ String.duplicate("s", 1000)
    assert byte_size(encoded) < 2_000

    attributes = SearchResult.to_security_attrs(result, market).attributes
    assert scalar_and_bounded?(attributes)
  end

  test "CoinGecko coins with type-confused fields are bounded, not a failed search" do
    body = %{
      "coins" => [
        %{
          "id" => "synthetic-coin",
          "name" => "Synthetic Coin",
          "symbol" => 42,
          "market_cap_rank" => %{"not" => "a rank"},
          "unlisted_blob" => @blob
        },
        %{
          "id" => "plain-coin",
          "name" => "Plain Coin",
          "symbol" => "pln",
          "market_cap_rank" => 7
        },
        %{"id" => String.duplicate("i", 500), "name" => "Long Id Coin", "symbol" => "lic"}
      ]
    }

    assert {:ok, [confused, plain]} = CoinGecko.search("syn", req: json_stub(body))

    assert confused.ticker_symbol == nil
    assert confused.raw == %{"type" => "Cryptocurrency"}
    assert plain.ticker_symbol == "PLN"
    assert plain.raw == %{"type" => "Cryptocurrency", "market_cap_rank" => 7}

    for result <- [confused, plain] do
      assert scalar_and_bounded?(SearchResult.to_security_attrs(result).attributes)
    end
  end

  # User story:
  # As an operator,
  # I want a security's name and quote-feed URLs held to the length their
  # columns store,
  # so that an over-long value is a field error, not a failed write.
  #
  # Acceptance criteria:
  # - A name, feed URL or latest-feed URL over 255 characters is refused with
  #   a field error; 255 characters are accepted.
  test "the security changeset bounds name and feed URLs" do
    base = %{name: "Synthetic", currency_code: "EUR"}
    long = String.duplicate("ä", 256)
    fits = String.duplicate("ä", 255)

    for field <- [:name, :feed_url, :latest_feed_url] do
      changeset = Security.changeset(%Security{}, Map.put(base, field, long))
      refute changeset.valid?, "#{field} accepted 256 characters"
      assert errors_on(changeset)[field]

      assert Security.changeset(%Security{}, Map.put(base, field, fits)).valid?
    end
  end
end
