defmodule PortfolixirWeb.SecuritiesNumericAttributeSortTest do
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Catalog.SecuritySearch.{CoinGecko, PortfolioPerformance}
  alias Portfolixir.Repo

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp json_stub(body) do
    [
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end
    ]
  end

  # A well-formed CoinGecko hit whose market_cap_rank is the given value.
  defp coin_hit(rank, symbol \\ "syc") do
    body = %{
      "coins" => [
        %{
          "id" => "synthetic-coin-#{symbol}",
          "name" => "Synthetic Coin #{String.upcase(symbol)}",
          "symbol" => symbol,
          "market_cap_rank" => rank
        }
      ]
    }

    assert {:ok, [hit]} = CoinGecko.search("synthetic", req: json_stub(body))
    hit
  end

  defp add_from_search(hit, market) do
    Catalog.create_from_search_result(Actor.owner_ui(), hit, market, %{currency_code: "EUR"})
  end

  defp ranked_security! do
    {:ok, ranked} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Ranked Coin",
        currency_code: "EUR",
        attributes: %{"market_cap_rank" => 5}
      })

    ranked
  end

  # A value stored before the write was typed: written past the changeset.
  defp stray_security!(value) do
    {:ok, stray} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Stray Rank",
        currency_code: "EUR"
      })

    {:ok, {1, _}} =
      Repo.transaction(fn ->
        Repo.query!("SELECT set_config('portfolixir.journal_actor', 'system_job', true)")

        from(s in Security, where: s.id == ^stray.id)
        |> Repo.update_all(set: [attributes: %{"market_cap_rank" => value}])
      end)

    stray
  end

  # The API read as a client sees it: the status Phoenix answered, or, when
  # the request raised, the status it sent for the exception and the message.
  defp sorted_api_read(conn, direction) do
    discard_previously_sent()

    conn =
      conn
      |> api_conn()
      |> get("/api/v1/securities?sort=attr_market_cap_rank&direction=#{direction}")

    {:answered, conn.status, conn}
  rescue
    error ->
      sent =
        receive do
          {ref, {status, _headers, _body}} when is_reference(ref) -> status
        after
          0 -> :none
        end

      {:raised, sent, error |> Exception.message() |> String.split("\n") |> hd()}
  end

  # An earlier request's sent-response message would otherwise be read as
  # this one's (Phoenix.ConnTest.assert_error_sent/2 drains the same way).
  defp discard_previously_sent do
    receive do
      {ref, {_status, _headers, _body}} when is_reference(ref) -> discard_previously_sent()
      {:plug_conn, :sent} -> discard_previously_sent()
    after
      0 -> :ok
    end
  end

  defp click_rank_sort(view) do
    view |> element("#toggle-column-popover") |> render_click()

    view
    |> element("#column-picker form")
    |> render_change(%{"columns" => ["name", "attr_market_cap_rank"]})

    sort_button = ~s{button.sort-toggle[phx-value-key="attr_market_cap_rank"]}
    assert has_element?(view, sort_button)

    {outcome, log} =
      with_log(fn ->
        try do
          view |> element(sort_button) |> render_click()
          :survived
        catch
          :exit, reason -> {:crashed, reason}
        end
      end)

    crash_line =
      log
      |> String.split("\n")
      |> Enum.find("", &(&1 =~ "Postgrex.Error" or &1 =~ "22P02"))

    assert outcome == :survived,
           "the sort click took the securities page down: " <> String.trim(crash_line)
  end

  # User story (security review 2026-10-12, H37):
  # As the operator and the agent sorting securities by market cap rank,
  # I want that attribute stored as a number or not at all, and the sort to
  # answer whatever is stored,
  # so that one value a provider or a writer sent never disables a
  # documented sort on the page, the API or the companion.
  #
  # Acceptance criteria:
  # - A search hit's rank that is a whole number (or its text) is stored as
  #   a number; anything else is not stored.
  # - An attributes write with a rank that is no whole number answers 422
  #   with a field error under attributes; a whole-number text is stored as
  #   a number.
  # - A value stored before the rule sorts with the empty ones: the API sort
  #   answers 200, the catalog read returns, the page survives the click.
  describe "a search hit's rank is typed at write" do
    test "a whole number is stored as one, its text too, anything else is dropped" do
      assert {:ok, seven} = add_from_search(coin_hit("7"), nil)
      assert seven.attributes["market_cap_rank"] == 7

      assert {:ok, unranked} = add_from_search(coin_hit("unranked", "sod"), nil)
      refute Map.has_key?(unranked.attributes, "market_cap_rank")
    end

    test "a Portfolio Performance listing whose properties carry a boolean rank stores none" do
      body = [
        %{
          "description" => "SYNTHETIC LISTED CORP",
          "type" => "Common Stock",
          "markets" => [
            %{
              "symbol" => "SYNPPX",
              "currency" => "EUR",
              "exchange" => "XETR",
              "properties" => %{"market_cap_rank" => true}
            }
          ]
        }
      ]

      assert {:ok, [hit]} = PortfolioPerformance.search("synthetic", req: json_stub(body))
      [market] = hit.markets
      assert {:ok, planted} = add_from_search(hit, market)
      refute Map.has_key?(planted.attributes, "market_cap_rank")
    end

    test "after a hit with a text rank was added, the API sort answers 200", %{conn: conn} do
      ranked = ranked_security!()
      _planted = add_from_search(coin_hit("unranked"), nil)

      {outcome, _log} = with_log(fn -> sorted_api_read(conn, "asc") end)

      assert match?({:answered, 200, _}, outcome),
             "GET /api/v1/securities?sort=attr_market_cap_rank did not answer 200: " <>
               inspect(outcome, limit: 4)

      {:answered, 200, resp} = outcome
      ids = Enum.map(json_response(resp, 200)["data"], & &1["id"])
      assert ranked.id in ids
    end
  end

  describe "an attributes write is typed" do
    test "the API refuses a rank that is no whole number with a field error", %{conn: conn} do
      _ranked = ranked_security!()

      for rank <- ["n/a", true, 1.5, %{"rank" => 1}] do
        created =
          conn
          |> api_conn()
          |> post(
            "/api/v1/securities",
            Jason.encode!(%{
              "security" => %{
                "name" => "Synthetic Agent-Written Coin",
                "currency_code" => "EUR",
                "attributes" => %{"market_cap_rank" => rank}
              }
            })
          )

        assert %{"errors" => %{"attributes" => ["market_cap_rank must be a whole number"]}} =
                 json_response(created, 422),
               "rank #{inspect(rank)}"
      end

      {outcome, _log} = with_log(fn -> sorted_api_read(build_conn(), "desc") end)
      assert match?({:answered, 200, _}, outcome)
    end

    test "a whole-number text is stored as a number" do
      {:ok, security} =
        Catalog.create_security(Actor.owner_ui(), %{
          name: "Synthetic Text Rank",
          currency_code: "EUR",
          attributes: %{"market_cap_rank" => "12"}
        })

      assert security.attributes["market_cap_rank"] == 12
    end

    test "an update that leaves a stray stored rank alone is not refused for it" do
      stray = stray_security!("unranked")

      assert {:ok, updated} =
               Catalog.update_security(Actor.owner_ui(), Repo.get!(Security, stray.id), %{
                 attributes: %{"exchange_name" => "Synthetic Exchange"}
               })

      assert updated.attributes["exchange_name"] == "Synthetic Exchange"
    end
  end

  describe "a value stored before the rule sorts with the empty ones" do
    test "the API sort answers 200 in both directions", %{conn: conn} do
      ranked = ranked_security!()
      stray = stray_security!("unranked")

      for direction <- ~w(asc desc) do
        {outcome, _log} = with_log(fn -> sorted_api_read(conn, direction) end)

        assert match?({:answered, 200, _}, outcome),
               "#{direction}: did not answer 200: " <> inspect(outcome, limit: 4)

        {:answered, 200, resp} = outcome
        ids = Enum.map(json_response(resp, 200)["data"], & &1["id"])
        assert ranked.id in ids and stray.id in ids
      end
    end

    test "the catalog read returns for a boolean and a text value" do
      _ranked = ranked_security!()
      _stray = stray_security!(true)
      _other = stray_security!("1e5")

      for direction <- [:asc, :desc] do
        outcome =
          try do
            {:ok, Catalog.list_securities(sort: {:attr_market_cap_rank, direction})}
          rescue
            error -> {:raised, error |> Exception.message() |> String.split("\n") |> hd()}
          end

        assert match?({:ok, [_ | _]}, outcome),
               "Catalog.list_securities(sort: {:attr_market_cap_rank, #{direction}}) raised: " <>
                 inspect(outcome)
      end
    end

    test "the page survives a click on the Market cap rank sort", %{conn: conn} do
      Process.flag(:trap_exit, true)
      ranked = ranked_security!()
      stray = stray_security!("unranked")

      {:ok, view, _html} = live(conn, "/securities")
      click_rank_sort(view)

      assert Process.alive?(view.pid)
      assert has_element?(view, "#security-row-#{ranked.id}")
      assert has_element?(view, "#security-row-#{stray.id}")
    end
  end

  test "control: numeric ranks only, the API sort orders them and the page survives the click",
       %{conn: conn} do
    Process.flag(:trap_exit, true)
    ranked = ranked_security!()

    {:ok, other} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: "Synthetic Second Coin",
        currency_code: "EUR",
        attributes: %{"market_cap_rank" => "12"}
      })

    {outcome, _log} = with_log(fn -> sorted_api_read(conn, "desc") end)
    assert {:answered, 200, resp} = outcome
    ids = Enum.map(json_response(resp, 200)["data"], & &1["id"])
    assert Enum.take(ids, 2) == [other.id, ranked.id]

    {:ok, view, _html} = live(build_conn(), "/securities")
    click_rank_sort(view)

    assert Process.alive?(view.pid)
    assert has_element?(view, "#security-row-#{other.id}")
  end
end
