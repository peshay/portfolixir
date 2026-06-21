defmodule Portfolixir.Catalog.LogoLookup.WikipediaTest do
  # User story (covered through the dispatcher in logo_lookup_test):
  # Equity / ETF / Fund logos come from Wikipedia REST, since there is no
  # free open-data equivalent of CoinGecko for stocks.
  #
  # Acceptance criteria:
  # - The adapter calls `/api/rest_v1/page/summary/{title}` with the
  #   security name URL-encoded.
  # - If the summary exposes a Wikidata item with a logo image (P154),
  #   that logo redirect is preferred over a generic page photo.
  # - Summary thumbnails are preferred over `originalimage`, because the
  #   store has a deliberately small image-size limit.
  # - Returns `{:ok, url}` when `body["originalimage"]["source"]` exists.
  # - Returns `:not_found` when the page resolves but has no original
  #   image.
  # - Returns `:not_found` on HTTP 404 so the dispatcher can try another
  #   deterministic title variant.
  # - Returns `{:error, ...}` on other 4xx/5xx or transport errors so the
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

  # User story:
  # As a local portfolio maintainer updating the Alphabet logo,
  # I want Wikipedia lookup to use the logo image from Wikidata instead of
  # the page's generic campus photo,
  # so that the logo update stores a small actual logo and does not hit the
  # image-size guard.
  #
  # Acceptance criteria:
  # - The page summary is still fetched by title.
  # - A Wikidata P154 logo claim is converted into a Commons PNG redirect.
  # - The logo redirect wins over summary thumbnail/original images.
  test "prefers Wikidata P154 logo image over summary photos" do
    stub =
      plug_stub(fn conn ->
        cond do
          conn.request_path =~ "/api/rest_v1/page/summary/Alphabet%20Inc." ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "wikibase_item" => "Q20800404",
                "thumbnail" => %{"source" => "https://wikipedia/Campus-small.jpg"},
                "originalimage" => %{"source" => "https://wikipedia/Campus-large.jpg"}
              })
            )

          conn.request_path =~ "/wiki/Special:EntityData/Q20800404.json" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "entities" => %{
                  "Q20800404" => %{
                    "claims" => %{
                      "P154" => [
                        %{
                          "mainsnak" => %{
                            "datavalue" => %{
                              "value" => "Alphabet Inc Logo 2015.svg"
                            }
                          }
                        }
                      ]
                    }
                  }
                }
              })
            )
        end
      end)

    # Special:FilePath with a width renders an SVG logo to PNG, so the logo
    # store accepts it instead of rejecting the raw SVG (#483).
    assert {:ok,
            "https://commons.wikimedia.org/wiki/Special:FilePath/Alphabet%20Inc%20Logo%202015.svg?width=256"} =
             Wikipedia.lookup("Alphabet Inc.", req: stub)
  end

  test "prefers summary thumbnail over originalimage when no Wikidata logo exists" do
    stub =
      plug_stub(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "thumbnail" => %{"source" => "https://wikipedia/thumb.png"},
            "originalimage" => %{"source" => "https://wikipedia/huge.png"}
          })
        )
      end)

    assert {:ok, "https://wikipedia/thumb.png"} = Wikipedia.lookup("Alphabet Inc.", req: stub)
  end

  test "returns :not_found on 404 so callers can try fallback titles" do
    stub =
      plug_stub(fn conn ->
        Plug.Conn.send_resp(conn, 404, "not found")
      end)

    assert :not_found = Wikipedia.lookup("DoesNotExist", req: stub)
  end
end
