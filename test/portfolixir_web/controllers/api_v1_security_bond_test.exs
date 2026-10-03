defmodule PortfolixirWeb.ApiV1SecurityBondTest do
  # #330 (ADR-0052): a bond's master data set and read over the securities
  # routes, and the bond reading on the detail read — the API half of the
  # Overview's bond strip. The MCP tools are portfolixir.securities.create,
  # .update and .get. Every name, ISIN, figure and date is invented.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 0, buy!: 3, put_quote!: 3]

  alias Portfolixir.Clock

  @maturity ~D[2031-06-15]

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp create_bond!(conn, extra \\ %{}) do
    body = %{
      "security" =>
        Map.merge(
          %{
            "name" => "Musterland Anleihe 2031",
            "isin" => "XSAPIBND0318",
            "currency_code" => "EUR",
            "asset_class" => "government_bond",
            "coupon_rate" => "2.5",
            "coupon_frequency" => "annual",
            "maturity_date" => Date.to_iso8601(@maturity),
            "issue_date" => "2021-06-15",
            "face_value" => "1000",
            "face_value_currency_code" => "EUR"
          },
          extra
        )
    }

    conn |> post("/api/v1/securities", Jason.encode!(body)) |> json_response(201)
  end

  # User story (#330, ADR-0052 §1):
  # As the operator's agent recording a bond from a statement,
  # I want to set its coupon, payment frequency, maturity, issue date and
  # denomination through the securities API and read them back,
  # so that the master data I enter is the master data the screen shows.
  #
  # Acceptance criteria:
  # - POST and PATCH /api/v1/securities take the six fields and answer them
  #   with decimals as strings and dates as ISO dates.
  # - A PATCH with null clears a field; an impossible value is a 422 naming
  #   its field, and nothing is written.
  test "sets, reads, clears and refuses a bond's master data", %{conn: conn} do
    %{"data" => created} = create_bond!(conn)

    assert %{
             "coupon_rate" => coupon_rate,
             "coupon_frequency" => "annual",
             "maturity_date" => "2031-06-15",
             "issue_date" => "2021-06-15",
             "face_value" => face_value,
             "face_value_currency_code" => "EUR"
           } = created

    assert Decimal.equal?(Decimal.new(coupon_rate), Decimal.new("2.5"))
    assert Decimal.equal?(Decimal.new(face_value), Decimal.new("1000"))

    patched =
      conn
      |> patch(
        "/api/v1/securities/#{created["id"]}",
        Jason.encode!(%{
          "security" => %{"issue_date" => nil, "coupon_frequency" => "semi_annual"}
        })
      )
      |> json_response(200)

    assert patched["data"]["issue_date"] == nil
    assert patched["data"]["coupon_frequency"] == "semi_annual"

    refused =
      conn
      |> patch(
        "/api/v1/securities/#{created["id"]}",
        Jason.encode!(%{"security" => %{"coupon_rate" => "250", "coupon_frequency" => "monthly"}})
      )
      |> json_response(422)

    assert %{"coupon_rate" => [_], "coupon_frequency" => ["is invalid"]} = refused["errors"]

    unchanged = conn |> get("/api/v1/securities/#{created["id"]}") |> json_response(200)
    assert Decimal.equal?(Decimal.new(unchanged["data"]["coupon_rate"]), Decimal.new("2.5"))
  end

  # User story (#330, ADR-0052 §2–§4):
  # As the operator's agent reading a bond,
  # I want the detail read to carry the nominal held, the remaining term,
  # the current yield and the linear yield to maturity, each with its
  # computation basis, and the two-scales finding,
  # so that I read the figures the Overview shows, with how they were made.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities/:id of a bond held at 100 units and quoted
  #   97.25 carries bond.nominal_held 10000 EUR, the remaining term in days
  #   to the maturity, current_yield 0.025707 with its price and source
  #   "quote", and the linear yield to maturity over the same days.
  # - Every metric carries computation_basis with input_series, window,
  #   reference, gaps and assumptions; decimals are strings.
  # - two_scales is null for the hundredth reading and names a bond bought
  #   at 0.985 per unit; a non-bond has bond: null, and so has the listing.
  test "the detail read carries the bond reading with each metric's basis", %{conn: conn} do
    %{"data" => %{"id" => id}} = create_bond!(conn)
    world = base_world()
    buy!(world, id, quantity: "100", price: "98.50", date: ~D[2026-03-12])
    put_quote!(id, ~D[2026-09-30], "97.25")

    %{"data" => %{"bond" => bond}} =
      conn |> get("/api/v1/securities/#{id}") |> json_response(200)

    today = Clock.today()
    days = Date.diff(@maturity, today)

    assert bond["as_of"] == Date.to_iso8601(today)
    assert bond["quantity"] == "100"
    assert bond["nominal_held"]["amount"] == "10000"
    assert bond["nominal_held"]["currency_code"] == "EUR"
    assert bond["remaining_term"]["days"] == days
    refute bond["remaining_term"]["matured"]

    assert bond["current_yield"]["value"] == "0.025707"
    assert bond["current_yield"]["price"]["source"] == "quote"
    assert bond["current_yield"]["price"]["date"] == "2026-09-30"
    assert bond["current_yield"]["missing"] == []

    expected_ytm =
      Decimal.new("100")
      |> Decimal.sub(Decimal.new("97.25"))
      |> Decimal.mult(365)
      |> Decimal.div(days)
      |> Decimal.add(Decimal.new("2.5"))
      |> Decimal.div(Decimal.new("97.25"))
      |> Decimal.round(6, :half_up)
      |> Decimal.normalize()
      |> Decimal.to_string(:normal)

    assert bond["yield_to_maturity"]["value"] == expected_ytm

    for metric <- ~w(nominal_held remaining_term current_yield yield_to_maturity) do
      basis = bond[metric]["computation_basis"]

      for key <- ~w(input_series window reference gaps assumptions) do
        assert is_binary(basis[key]) and basis[key] != "", "#{metric}.computation_basis.#{key}"
      end
    end

    assert bond["two_scales"] == nil

    %{"data" => %{"id" => face_id}} =
      create_bond!(conn, %{"name" => "Musterland Anleihe 2029", "isin" => "XSAPIBND0292"})

    buy!(world, face_id, quantity: "10000", price: "0.985", date: ~D[2026-03-12])
    put_quote!(face_id, ~D[2026-09-30], "97.25")

    %{"data" => %{"bond" => face}} =
      conn |> get("/api/v1/securities/#{face_id}") |> json_response(200)

    assert face["nominal_held"]["amount"] == "1000000"

    assert %{
             "latest_quote" => %{"close" => "97.25", "date" => "2026-09-30"},
             "unit_scale_buys" => 1,
             "last_unit_scale_buy" => %{"price" => "0.985", "date" => "2026-03-12"},
             "rule" => rule
           } = face["two_scales"]

    assert rule =~ "between 20 and 500 times"

    %{"data" => %{"id" => etf_id}} =
      conn
      |> post(
        "/api/v1/securities",
        Jason.encode!(%{
          "security" => %{
            "name" => "Examplia World ETF",
            "currency_code" => "EUR",
            "asset_class" => "etf"
          }
        })
      )
      |> json_response(201)

    assert %{"data" => %{"bond" => nil}} =
             conn |> get("/api/v1/securities/#{etf_id}") |> json_response(200)

    %{"data" => rows} =
      conn |> get("/api/v1/securities?projection=full") |> json_response(200)

    assert Enum.all?(rows, &(&1["bond"] == nil))
  end
end
