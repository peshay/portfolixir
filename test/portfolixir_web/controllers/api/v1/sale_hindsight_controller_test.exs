defmodule PortfolixirWeb.Api.V1.SaleHindsightControllerTest do
  # Sprint 25 Lane S, S2 (I18 modes 1 and 2; the plan's D-3):
  # GET /api/v1/sales/hindsight, the read of what a sale missed. The figures
  # are SaleHindsight's (pinned with hand computations in its own test); this
  # test pins the wire: Decimal strings, the filters, the optional
  # benchmark= of ADR-0046 through BenchmarkParam unchanged, the 422s, the
  # cap and the auth. Every name and figure here is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures,
    only: [base_world: 1, create_security!: 1, put_quotes!: 2, sell!: 3]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Clock

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp benchmark!(name, ticker) do
    security = create_security!(name: name, ticker: ticker, currency: "EUR")
    {:ok, flagged} = Catalog.update_security(Actor.owner_ui(), security, %{is_benchmark: true})
    flagged
  end

  defp span(row, label), do: Enum.find(row["spans"], &(&1["span"] == label))

  # A sale on 2025-01-15 whose 1m, 3m and 12m spans have all passed by the
  # host's today, and a recent one whose spans have not.
  defp world do
    world = base_world(name: "Hindsight API")
    security = create_security!(name: "Synthetic Sold Fund", ticker: "SSF", currency: "EUR")
    put_quotes!(security, [{~D[2025-01-15], "100"}, {~D[2025-02-14], "110"}])
    sale = sell!(world, security, quantity: "10", price: "101.50", date: ~D[2025-01-15])

    recent_day = Date.add(Clock.today(), -3)
    recent_security = create_security!(name: "Synthetic Recent Fund", ticker: "SRF")
    put_quotes!(recent_security, [{recent_day, "40"}])
    recent = sell!(world, recent_security, quantity: "1", price: "40", date: recent_day)

    %{world: world, security: security, sale: sale, recent: recent}
  end

  # User story (S2, I18; D-3):
  # As the agent asked what the operator's sales missed,
  # I want one read answering every sale booking with its four spans,
  # so that I hand over the server's figures rather than recompute them.
  #
  # Acceptance criteria:
  # - data carries as_of, the span labels, benchmark (null without one),
  #   rows, limit, truncated and computation_basis.
  # - A row names the transaction, the date, the security, the booked
  #   quantity, price and currency, and the start close; every financial
  #   value is a Decimal string.
  # - Each span carries span, end_on, days, status, reason, security
  #   {return, start, end}, benchmark and difference.
  test "answers one row per sale with its spans as Decimal strings", %{conn: conn} do
    %{security: security, sale: sale, recent: recent} = world()

    %{"data" => data} = conn |> get("/api/v1/sales/hindsight") |> json_response(200)

    assert data["as_of"] == Date.to_iso8601(Clock.today())
    assert data["spans"] == ["1m", "3m", "12m", "latest"]
    assert data["benchmark"] == nil
    assert data["limit"] == 100
    assert data["truncated"] == false
    assert Enum.map(data["rows"], & &1["sale_id"]) == [recent.id, sale.id]

    row = Enum.find(data["rows"], &(&1["sale_id"] == sale.id))
    assert row["date"] == "2025-01-15"

    assert row["security"] == %{
             "id" => security.id,
             "name" => "Synthetic Sold Fund",
             "currency_code" => "EUR"
           }

    assert row["quantity"] == "10"
    assert row["price"] == "101.5"
    assert row["currency_code"] == "EUR"
    assert row["start"]["date"] == "2025-01-15"
    assert row["start"]["close"] == "100"
    assert row["start"]["eur_value"] == "100"
    assert row["start_reason"] == nil

    one = span(row, "1m")
    assert one["status"] == "complete"
    assert one["end_on"] == "2025-02-15"
    assert one["days"] == 31
    assert one["reason"] == nil
    assert one["security"]["return"] == "0.1"
    assert one["security"]["end"]["date"] == "2025-02-14"
    assert one["security"]["end"]["stands_for"] == "2025-02-15"
    assert one["benchmark"] == nil
    assert one["difference"] == nil

    # 3m (2025-04-15) has no close in the 7 days before it.
    assert %{"status" => "incomplete", "reason" => "no_end_close"} = span(row, "3m")

    recent_row = Enum.find(data["rows"], &(&1["sale_id"] == recent.id))
    assert %{"status" => "pending", "security" => nil} = span(recent_row, "1m")

    basis = data["computation_basis"]

    for key <- ~w(input_series window reference gaps price_only sales booked_price) do
      assert is_binary(basis[key]), key
    end
  end

  # User story (S2, D-3: the comparison is optional and chosen per request):
  # As the agent comparing a sale with a fixed rate or an index,
  # I want benchmark= read exactly as the benchmark comparison reads it,
  # so that one spelling works on both reads and a non-benchmark security is
  # refused, never silently compared against.
  #
  # Acceptance criteria:
  # - rate:<decimal> and security:<id> (flagged is_benchmark) answer the
  #   benchmark object and each span's benchmark side and difference.
  # - An unflagged security, a malformed value and an out-of-bound rate
  #   answer 422 errors.benchmark.
  test "takes benchmark= as the benchmark comparison does", %{conn: conn} do
    %{sale: sale} = world()
    bench = benchmark!("Synthetic Bench Index", "SBI")
    put_quotes!(bench, [{~D[2025-01-15], "200"}, {~D[2025-02-14], "210"}])
    plain = create_security!(name: "Synthetic Plain", ticker: "SPL")

    %{"data" => by_security} =
      conn
      |> get("/api/v1/sales/hindsight", %{"benchmark" => "security:#{bench.id}"})
      |> json_response(200)

    assert by_security["benchmark"] == %{
             "kind" => "security",
             "security_id" => bench.id,
             "name" => "Synthetic Bench Index",
             "currency_code" => "EUR"
           }

    # 1m: 0.1 against 210 / 200 - 1 = 0.05, difference 0.05.
    row = Enum.find(by_security["rows"], &(&1["sale_id"] == sale.id))
    one = span(row, "1m")
    assert one["benchmark"]["return"] == "0.05"
    assert one["benchmark"]["start"]["close"] == "200"
    assert one["difference"] == "0.05"
    assert by_security["computation_basis"]["reference"] =~ "security #{bench.id} (EUR)"

    %{"data" => by_rate} =
      conn
      |> get("/api/v1/sales/hindsight", %{"benchmark" => "rate:0.05"})
      |> json_response(200)

    assert by_rate["benchmark"] == %{"kind" => "rate", "annual_rate" => "0.05"}
    rate_row = Enum.find(by_rate["rows"], &(&1["sale_id"] == sale.id))
    # 31 days at 5 % p.a.: 0.004152419664798823558111758969043 (the
    # context test's hand computation).
    assert span(rate_row, "1m")["benchmark"] == %{
             "return" => "0.004152419664798823558111758969043",
             "start" => nil,
             "end" => nil
           }

    for value <- ["security:#{plain.id}", "security:abc", "index:1", "rate:11", "rate:x"] do
      %{"errors" => errors} =
        conn |> get("/api/v1/sales/hindsight", %{"benchmark" => value}) |> json_response(422)

      assert Map.has_key?(errors, "benchmark"), value
    end
  end

  # User story (S2): the filters and their refusals, as the sibling reads.
  #
  # Acceptance criteria:
  # - portfolio_id, security_id, from and to narrow the rows; an unknown id
  #   answers no rows.
  # - A malformed id, date or limit answers 422 naming it; to before from
  #   answers 422 on to.
  # - limit caps the rows, newest first, with truncated.
  test "narrows by portfolio, security and sale date, and refuses bad input", %{conn: conn} do
    %{world: world, security: security, sale: sale, recent: recent} = world()
    other = base_world(name: "Hindsight Other")
    other_sale = sell!(other, security, quantity: "1", price: "100", date: ~D[2025-01-20])

    ids = fn params ->
      conn
      |> get("/api/v1/sales/hindsight", params)
      |> json_response(200)
      |> get_in(["data", "rows"])
      |> Enum.map(& &1["sale_id"])
    end

    assert ids.(%{"portfolio_id" => "#{world.portfolio.id}"}) == [recent.id, sale.id]
    assert ids.(%{"security_id" => "#{security.id}"}) == [other_sale.id, sale.id]
    assert ids.(%{"from" => "2025-01-16", "to" => "2025-12-31"}) == [other_sale.id]
    assert ids.(%{"portfolio_id" => "999999"}) == []

    %{"data" => capped} =
      conn |> get("/api/v1/sales/hindsight", %{"limit" => "1"}) |> json_response(200)

    assert Enum.map(capped["rows"], & &1["sale_id"]) == [recent.id]
    assert capped["limit"] == 1
    assert capped["truncated"] == true

    for {params, field} <- [
          {%{"portfolio_id" => "x"}, "portfolio_id"},
          {%{"security_id" => "0"}, "security_id"},
          {%{"security_id" => "99999999999999999999"}, "security_id"},
          {%{"from" => "2025-13-01"}, "from"},
          {%{"to" => "soon"}, "to"},
          {%{"from" => "2025-02-01", "to" => "2025-01-31"}, "to"},
          {%{"limit" => "0"}, "limit"}
        ] do
      %{"errors" => errors} =
        conn |> get("/api/v1/sales/hindsight", params) |> json_response(422)

      assert Map.has_key?(errors, field), "#{inspect(params)}: #{inspect(errors)}"
    end
  end

  # User story (S2): the read is the API token's, as every /api/v1 read.
  test "refuses a request without the API token" do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> get("/api/v1/sales/hindsight")
    |> json_response(401)
  end
end
