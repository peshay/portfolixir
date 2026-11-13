defmodule PortfolixirWeb.ApiV1SecurityCyclesTest do
  # ADR-0060 §11 (Sprint 29, H6, FR-58): GET /api/v1/securities/:security_id/cycles
  # and the dossier's cycles line. The figures are the context's
  # (test/portfolixir/catalog/security_cycles_test.exs recomputes them); this
  # test pins what the API makes of them: decimals as strings, dates ISO,
  # the parameters it takes and refuses, 401, 404 and merged_into.
  #
  # The dossier's cycles line is also written, ids normalized, to
  # mcp-server/test/fixtures/cycles/dossier-cycles.json, and the companion's
  # test (cycles.test.ts) runs it through `callTool` and counts what the tool
  # returns; this test fails when the fixture no longer matches what the
  # server answers. Regenerate it with PORTFOLIXIR_WRITE_CYCLES_BUDGET=1.
  # Every name, close and date is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Lifecycle

  @fixture Path.expand(
             "../../../mcp-server/test/fixtures/cycles/dossier-cycles.json",
             __DIR__
           )

  # About 40 tokens: characters / 4 of the line as the companion spells it.
  @budget 40

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  # Litecoin's interval: a chain without a source, so halvings are written
  # by hand. Five halvings, four confirmed; closes that give both bands,
  # their parts and agree (Sprint 29 H5's verdict walk), each multiplied by
  # `scale` and given `cents`, so the widest figures can be measured.
  defp coin!(name, scale \\ "1", cents \\ "0") do
    coin = create_security!(name: name, ticker: nil, asset_class: "crypto")
    {:ok, coin} = Catalog.update_security(agent(), coin, %{halving_chain: :litecoin})

    for {k, date, confirmed} <- [
          {1, "2013-01-10", true},
          {2, "2015-01-10", true},
          {3, "2017-01-10", true},
          {4, "2019-01-10", true},
          {5, "2021-01-05", false}
        ] do
      {:ok, _event} =
        Events.create_event(agent(), %{
          "security_id" => coin.id,
          "kind" => "halving",
          "chain_height" => k * 840_000,
          "date" => date,
          "timing" => "exact",
          "confirmed" => confirmed,
          "source_quality" => "unverified"
        })
    end

    closes = [
      {~D[2013-01-10], "40"},
      {~D[2013-03-01], "50"},
      {~D[2013-06-01], "80"},
      {~D[2014-09-01], "10"},
      {~D[2015-01-10], "9"},
      {~D[2016-03-01], "200"},
      {~D[2016-09-01], "30"},
      {~D[2017-01-10], "50"},
      {~D[2017-08-01], "500"},
      {~D[2018-05-01], "100"},
      {~D[2019-01-10], "470"},
      {~D[2019-10-01], "1500"},
      {~D[2020-05-01], "1000"}
    ]

    rows =
      for {date, close} <- closes do
        value =
          close
          |> Decimal.new()
          |> Decimal.mult(Decimal.new(scale))
          |> Decimal.add(Decimal.new(cents))

        %{date: date, close: value, source: "manual"}
      end

    {:ok, _count} = Quotes.upsert_many(coin.id, rows)
    coin
  end

  defp decimal_string?(value), do: is_binary(value) and match?({_, ""}, Decimal.parse(value))

  # User story (ADR-0060 §11):
  # As the operator's agent,
  # I want a bound security's halving cycles over the API, with every figure
  # a string and every date ISO,
  # so that I read the same cycles, bands and basis the chart draws without
  # losing a digit.
  #
  # Acceptance criteria:
  # - 401 without the token.
  # - 200 carries security_id, chain, chain_source, halvings, next_halving,
  #   cycles, intervals, projection (kind analog_band, not_a_forecast true,
  #   next_low and next_top with band, agree, state, parts), reason null and
  #   computation_basis; no aligned key unless asked for.
  # - Closes, factors, changes and band prices are decimal strings, dates
  #   ISO 8601, enums strings.
  # - include=aligned adds aligned, each point's index a decimal string.
  test "GET /api/v1/securities/:security_id/cycles answers the read as strings", %{conn: conn} do
    coin = coin!("Synthetic Cycle Coin")
    path = "/api/v1/securities/#{coin.id}/cycles"

    assert build_conn() |> get(path) |> json_response(401)

    %{"data" => data} = conn |> get(path) |> json_response(200)

    assert data["security_id"] == coin.id
    assert data["chain"] == "litecoin"
    assert data["chain_source"] == %{"chain" => "litecoin", "has_source" => false}
    assert data["reason"] == nil
    refute Map.has_key?(data, "aligned")

    assert hd(data["halvings"]) == %{
             "height" => 840_000,
             "chain" => "litecoin",
             "date" => "2013-01-10",
             "date_end" => nil,
             "timing" => "exact",
             "confirmed" => true,
             "source_quality" => "unverified"
           }

    assert data["next_halving"] == %{
             "height" => 4_200_000,
             "date" => "2021-01-05",
             "date_end" => nil,
             "note" => nil,
             "checked_at" => nil,
             "source_url" => nil,
             "inputs" => nil
           }

    [first | _] = data["cycles"]
    assert first["kind"] == "complete"

    assert first["top"] == %{
             "date" => "2013-06-01",
             "close" => "80",
             "final" => true,
             "anchor" => true
           }

    assert decimal_string?(first["max_drawdown"])

    top_to_top = data["intervals"]["top_to_top"]
    assert top_to_top["n"] == 3

    assert Enum.all?(
             [top_to_top["factor"]["min"], top_to_top["factor"]["max"]],
             &decimal_string?/1
           )

    projection = data["projection"]
    assert {projection["kind"], projection["not_a_forecast"]} == {"analog_band", true}

    for event <- ["next_low", "next_top"] do
      band = projection[event]["band"]
      assert decimal_string?(band["price"]["from"]) and decimal_string?(band["price"]["to"])
      assert {:ok, _from} = Date.from_iso8601(band["window"]["from"])
      assert is_binary(projection[event]["state"])
      assert Enum.all?(projection[event]["parts"], &is_binary(&1["relation"]))
    end

    basis = data["computation_basis"]
    assert basis["anchor_threshold"] == "0.2"
    assert basis["projection"]["not_a_forecast"] == true
    assert basis["series"]["first_close"] == "2013-01-10"

    %{"data" => aligned} = conn |> get(path <> "?include=aligned") |> json_response(200)

    assert Map.delete(aligned, "aligned")
           |> Map.update!("computation_basis", &Map.delete(&1, "aligned")) == data

    [window | _] = aligned["aligned"]
    assert window["base"] == %{"date" => "2013-01-10", "close" => "40"}
    assert hd(window["points"]) == %{"date" => "2013-01-10", "days" => 0, "index" => "1"}

    assert Enum.at(window["points"], 2) == %{
             "date" => "2013-06-01",
             "days" => 142,
             "index" => "2"
           }

    assert aligned["computation_basis"]["aligned"] =~ "no_halving_close"
  end

  # User story (ADR-0060 §8, §11, §13 item 12):
  # As the maintainer keeping level (d) out,
  # I want the route to refuse as_of and every parameter but include=aligned,
  # and to name a merged-away id's survivor,
  # so that no caller computes a past cycle's band and an old id is followed.
  #
  # Acceptance criteria:
  # - as_of answers 422 naming it and the replay; any other parameter,
  #   include with another value and include as a list answer 422 naming
  #   them.
  # - An unknown id answers 404; a merged-away id 404 with
  #   errors.merged_into {kind: security, id}.
  test "as_of, unknown parameters, 404 and merged_into", %{conn: conn} do
    coin = coin!("Synthetic Refused Coin")
    path = "/api/v1/securities/#{coin.id}/cycles"

    assert %{"errors" => %{"as_of" => [message]}} =
             conn |> get(path <> "?as_of=2017-01-01") |> json_response(422)

    assert message =~ "level (d)"

    assert %{"errors" => %{"window" => [_], "include" => [include]}} =
             conn |> get(path <> "?window=1y&include=bands") |> json_response(422)

    assert include =~ "aligned"

    assert %{"errors" => %{"include" => [_]}} =
             conn |> get(path <> "?include[]=aligned") |> json_response(422)

    assert %{"errors" => %{"detail" => "not found"}} =
             conn |> get("/api/v1/securities/999999999/cycles") |> json_response(404)

    target = create_security!(name: "Synthetic Survivor Coin", ticker: nil)
    source = create_security!(name: "Synthetic Survivor Coin", ticker: nil)
    {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_security(Actor.owner_ui(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    assert %{"errors" => %{"merged_into" => %{"kind" => "security", "id" => id}}} =
             conn |> get("/api/v1/securities/#{source.id}/cycles") |> json_response(404)

    assert id == target.id
  end

  defp spelled(line), do: Jason.encode!(line)

  defp normalize(line) do
    %{"data" => %{"security_id" => 1, "cycles" => line}}
    |> Jason.encode!(pretty: true)
  end

  defp fixture!(line) do
    normalized = normalize(line) <> "\n"

    if System.get_env("PORTFOLIXIR_WRITE_CYCLES_BUDGET") == "1" do
      File.mkdir_p!(Path.dirname(@fixture))
      File.write!(@fixture, normalized)
    else
      assert File.read!(@fixture) == normalized,
             "#{@fixture} no longer matches the server's answer: regenerate it with " <>
               "PORTFOLIXIR_WRITE_CYCLES_BUDGET=1 and rerun the companion's test"
    end
  end

  # User story (ADR-0060 §11, "the dossier gains a cycles line"):
  # As the operating agent starting a research run from the dossier,
  # I want the next low's and the next top's bands with their states in the
  # dossier, in about 40 tokens,
  # so that I know where the security stands in its cycle before I read the
  # cycles themselves.
  #
  # Acceptance criteria:
  # - cycles carries low and top, the next low's and the next top's band,
  #   each [window from, window to,
  #   price from, price to, state, n] from the cycles read's band, n the
  #   fewest observations of a present part's time side; null without the
  #   view; parts.cycles names the read.
  # - With 7- and 8-digit prices at 6 decimals, the line holds 40 tokens on the
  #   companion's text, and it is the fixture the companion's test measures.
  test "the dossier carries the cycles line within its budget", %{conn: conn} do
    coin = coin!("Synthetic Dossier Coin", "3400", "0.123457")

    %{"data" => dossier} =
      conn |> get("/api/v1/securities/#{coin.id}/dossier") |> json_response(200)

    assert dossier["parts"]["cycles"] =~ "portfolixir.securities.cycles"

    %{"data" => cycles} =
      conn |> get("/api/v1/securities/#{coin.id}/cycles") |> json_response(200)

    line = dossier["cycles"]

    for {key, event} <- [{"low", "next_low"}, {"top", "next_top"}] do
      read = cycles["projection"][event]
      present = Enum.filter(read["parts"], & &1["window"])

      assert line[key] == [
               read["band"]["window"]["from"],
               read["band"]["window"]["to"],
               read["band"]["price"]["from"],
               read["band"]["price"]["to"],
               read["state"],
               present |> Enum.map(& &1["n_time"]) |> Enum.min()
             ]
    end

    # The widest prices: 7 and 8 digits before the point, 6 after it.
    assert String.length(Enum.at(line["low"], 3)) >= 14
    assert String.length(Enum.at(line["top"], 3)) >= 15

    assert String.length(spelled(line)) / 4 <= @budget,
           "#{spelled(line)} #{String.length(spelled(line)) / 4} tokens"

    fixture!(line)

    unbound = create_security!(name: "Synthetic Unbound Coin", ticker: nil)

    %{"data" => none} =
      conn |> get("/api/v1/securities/#{unbound.id}/dossier") |> json_response(200)

    assert Map.has_key?(none, "cycles")
    assert none["cycles"] == nil
  end
end
