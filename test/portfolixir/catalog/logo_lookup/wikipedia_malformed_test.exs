defmodule Portfolixir.Catalog.LogoLookup.WikipediaMalformedTest do
  # E25 S3, F30 (#888): the Wikipedia adapter type-matches every field of the
  # search, summary and Wikidata payloads before it uses one, caps the search
  # candidates at the page size it asked for, and the lookup pipeline returns
  # an unexpected failure as a value for every caller.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.LogoLookup
  alias Portfolixir.Catalog.LogoLookup.Wikipedia
  alias Portfolixir.Catalog.Security

  @search_path "/w/rest.php/v1/search/page"

  defp json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  defp stub(test_pid, answer) do
    [
      plug: fn conn ->
        send(test_pid, {:request, conn.host, conn.request_path})
        answer.(conn)
      end
    ]
  end

  defp requests(acc \\ []) do
    receive do
      {:request, host, path} -> requests([{host, path} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # User story:
  # As an operator whose logo discovery reads a public API I do not control,
  # I want a search answer bounded by the page size the lookup asked for,
  # so that one lookup can never fan out into an unbounded number of requests.
  #
  # Acceptance criteria:
  # - However many candidates the search answers with, at most the requested
  #   page size of them is looked up.
  test "a search answer longer than the requested page is cut to it" do
    test_pid = self()

    pages =
      for n <- 1..50 do
        %{"key" => "Synthetic_#{n}", "title" => "Synthetic #{n}", "description" => "company"}
      end

    answer = fn conn ->
      case conn.request_path do
        @search_path -> json(conn, %{"pages" => pages})
        _ -> json(conn, %{"title" => "no image"})
      end
    end

    assert :not_found = Wikipedia.search_logo("Synthetic", req: stub(test_pid, answer))

    summaries = Enum.reject(requests(), fn {_host, path} -> path == @search_path end)
    assert length(summaries) <= 5
  end

  # User story:
  # As an operator,
  # I want a malformed upstream answer read as "no logo here",
  # so that a changed or hostile payload never crashes a lookup.
  #
  # Acceptance criteria:
  # - Search candidates whose fields have the wrong type are skipped.
  # - Summary and Wikidata payloads whose fields have the wrong type yield
  #   not-found, never a raise.
  test "type-confused search candidates are skipped without raising" do
    test_pid = self()

    pages = [
      "not a map",
      %{"title" => "Synthetic", "description" => %{"nested" => "company"}},
      %{"title" => "Synthetic", "excerpt" => ["company"], "description" => "company"},
      %{"title" => "Synthetic", "key" => 42, "description" => "company"},
      %{"title" => ["Synthetic"], "description" => "company"}
    ]

    answer = fn conn ->
      case conn.request_path do
        @search_path -> json(conn, %{"pages" => pages})
        _ -> json(conn, %{"title" => "no image"})
      end
    end

    assert :not_found = Wikipedia.search_logo("Synthetic", req: stub(test_pid, answer))
  end

  test "type-confused summary and Wikidata payloads are not-found without raising" do
    test_pid = self()

    entities = [
      ["not", "a", "map"],
      %{"Q1" => "not a map"},
      %{"Q1" => %{"claims" => ["not", "a", "map"]}},
      %{"Q1" => %{"claims" => %{"P154" => %{"not" => "a list"}}}},
      %{"Q1" => %{"claims" => %{"P154" => ["not a map"]}}},
      %{"Q1" => %{"claims" => %{"P154" => [%{"mainsnak" => ["x"]}]}}},
      %{"Q1" => %{"claims" => %{"P154" => [%{"mainsnak" => %{"datavalue" => "x"}}]}}},
      %{
        "Q1" => %{
          "claims" => %{"P154" => [%{"mainsnak" => %{"datavalue" => %{"value" => %{}}}}]}
        }
      }
    ]

    for entity <- entities do
      answer = fn conn ->
        case conn.host do
          "en.wikipedia.org" -> json(conn, %{"wikibase_item" => "Q1", "thumbnail" => "x"})
          "www.wikidata.org" -> json(conn, %{"entities" => entity})
        end
      end

      assert :not_found = Wikipedia.lookup("Synthetic", req: stub(test_pid, answer)),
             inspect(entity)
    end

    for summary <- [
          %{"thumbnail" => ["x"], "originalimage" => "x"},
          %{"wikibase_item" => 42},
          %{"thumbnail" => %{"source" => 42}}
        ] do
      assert :not_found =
               Wikipedia.lookup("Synthetic", req: stub(test_pid, &json(&1, summary))),
             inspect(summary)
    end

    requests()
  end

  # User story:
  # As the discovery job, the securities page and the API's rediscover action,
  # I want an unexpected failure inside a logo lookup returned as a named error,
  # so that no caller crashes on one upstream's answer.
  #
  # Acceptance criteria:
  # - A type-confused answer through the whole pipeline is a skip or an error
  #   value, never a raise.
  # - An exception anywhere in the lookup is {:error, :malformed_upstream}.
  test "the pipeline returns every failure as a value" do
    test_pid = self()

    answer = fn conn ->
      case conn.host do
        "en.wikipedia.org" -> json(conn, %{"wikibase_item" => "Q1"})
        "www.wikidata.org" -> json(conn, %{"entities" => ["not", "a", "map"]})
        _ -> Plug.Conn.send_resp(conn, 404, "")
      end
    end

    security = %Security{id: 1, provider: "manual", asset_class: "equity", name: "Synthetic Corp"}

    result = LogoLookup.run(security, req: stub(test_pid, answer))
    assert result == :skip or match?({:error, _}, result)

    # A request option the client refuses raises inside the adapter, before
    # any request: the pipeline still answers with a value.
    assert {:error, :malformed_upstream} =
             LogoLookup.run(security, req: [plug: answer, not_a_req_option: true])

    requests()
  end

  # 1x1 PNG
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0,
         0, 3, 0, 1, 5, 12, 60, 192, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  # User story (the S3/S4 review round):
  # As an operator reading why a logo lookup failed,
  # I want a local failure while storing a found logo reported as that,
  # so that the log and the rediscover answer do not blame a provider for a
  # fault of my own instance.
  #
  # Acceptance criteria:
  # - A failure after the logo was found, while it is stored, is
  #   {:error, :store_failed} and logged as a storage failure, not as a
  #   malformed upstream answer.
  test "a local failure while storing a found logo is not blamed on the upstream" do
    tmp = Path.join(System.tmp_dir!(), "portfolixir-logos-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Coin",
        currency_code: "USD",
        provider: "coingecko",
        asset_class: "crypto",
        online_id: "synthetic-coin"
      })

    answer = fn conn ->
      case conn.host do
        "api.coingecko.com" ->
          json(conn, %{"image" => %{"large" => "https://coingecko/synthetic.png"}})

        _image_host ->
          conn |> Plug.Conn.put_resp_content_type("image/png") |> Plug.Conn.send_resp(200, @png)
      end
    end

    # The row is gone by the time the found logo is recorded: a local fault.
    vanished = %{security | id: security.id + 1_000_000}

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :store_failed} =
                 LogoLookup.run(vanished, req: [plug: answer], storage_dir: tmp)
      end)

    assert log =~ "could not be stored"
    refute log =~ "malformed upstream"
  end
end
