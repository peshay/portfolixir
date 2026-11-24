defmodule PortfolixirWeb.ApiV1MalformedFilterTest do
  # R-019 (the rule of #1301, applied to three more reads): a filter a read
  # takes is applied or refused by name, never dropped. Every name here is
  # synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Tax

  @not_ids ["abc", "0", "-1", "1.5", "IE00B4L5Y983", "25107x"]
  @not_years ["abc", "20255", "2025.0", "FY2025", "0", "-2025", "99999999999999999999"]

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn}
  end

  defp rows(conn, path), do: conn |> get(path) |> json_response(200) |> Map.fetch!("data")

  defp refused(conn, path),
    do: conn |> get(path) |> json_response(422) |> Map.fetch!("errors")

  # User story (architecture review 2026-11, R-019; #1301's rule):
  # As the agent filtering a portfolio's holdings by a security or a depot,
  # I want a value that is no id refused by name,
  # so that I never read every holding as the answer to my filter.
  #
  # Acceptance criteria:
  # - `security_id` and `securities_account_id` on
  #   GET /api/v1/portfolios/:portfolio_id/holdings answer 422
  #   `["is invalid"]` naming the parameter for a value that is no id, as the
  #   transactions read does.
  # - A valid id filters, an id no holding has answers an empty list, and an
  #   empty value stays absent.
  test "the holdings read refuses a security or depot filter that is no id", %{conn: conn} do
    world = base_world(name: "Filters", cash_name: "Filter Cash", depot_name: "Filter Depot")
    alder = create_security!(name: "Alder Vale Mills plc", ticker: "AVM")
    birch = create_security!(name: "Birch Hollow Works plc", ticker: "BHW")
    buy!(world, alder, quantity: "2", price: "10")
    buy!(world, birch, quantity: "3", price: "10")

    path = "/api/v1/portfolios/#{world.portfolio.id}/holdings"

    assert length(rows(conn, path)) == 2
    assert [%{"security_id" => id}] = rows(conn, path <> "?security_id=#{alder.id}")
    assert id == alder.id
    assert length(rows(conn, path <> "?securities_account_id=#{world.depot.id}")) == 2
    assert rows(conn, path <> "?security_id=#{birch.id + 1_000_000}") == []
    assert length(rows(conn, path <> "?security_id=&securities_account_id=")) == 2

    for key <- ~w(security_id securities_account_id), value <- @not_ids do
      assert refused(conn, path <> "?#{key}=#{value}") == %{key => ["is invalid"]},
             "#{key}=#{value}"
    end

    # A right filter beside a wrong one is refused too: nothing is dropped.
    assert refused(conn, path <> "?security_id=#{alder.id}&securities_account_id=abc") ==
             %{"securities_account_id" => ["is invalid"]}

    # The sibling reads, whose answer this one now shares.
    assert refused(conn, "/api/v1/transactions?security_id=abc") ==
             %{"security_id" => ["is invalid"]}
  end

  # User story (architecture review 2026-11, R-019):
  # As the agent reading a holder's tax records of one year,
  # I want a `tax_year` that is no year refused by name,
  # so that I never sum every year's rows as that year's.
  #
  # Acceptance criteria:
  # - `tax_year` on GET /api/v1/tax/statement_snapshots and
  #   GET /api/v1/tax/allowance_orders answers 422 `["is invalid"]` for a
  #   value that is not a whole year from 1 to 9999; a year filters, and an
  #   empty value stays absent.
  # - GET /api/v1/tax/trim_budget answers 422 `tax_year ["is invalid"]` for
  #   such a value and keeps `["is required"]` for an absent or empty one.
  test "the tax reads refuse a tax_year that is no year", %{conn: conn} do
    for year <- [2024, 2025] do
      {:ok, _} =
        Tax.create_snapshot(
          Actor.owner_ui(),
          %{
            institution: "Example Bank",
            holder: "Owner",
            tax_year: year,
            as_of: Date.new!(year, 12, 31),
            taxable_income: Decimal.new("100.00"),
            allowance_granted: Decimal.new("1000.00"),
            allowance_used: Decimal.new("100.00")
          },
          today: Date.new!(year + 1, 1, 15)
        )

      {:ok, _} =
        Tax.put_allowance_order(Actor.owner_ui(), %{
          holder: "Owner",
          institution: "Example Bank",
          tax_year: year,
          amount_granted: "500.00"
        })
    end

    for route <- ~w(statement_snapshots allowance_orders) do
      path = "/api/v1/tax/#{route}"

      assert length(rows(conn, path)) == 2, route
      assert [%{"tax_year" => 2025}] = rows(conn, path <> "?tax_year=2025")
      assert rows(conn, path <> "?tax_year=2031") == []
      assert length(rows(conn, path <> "?tax_year=")) == 2, route

      for value <- @not_years do
        assert refused(conn, path <> "?tax_year=#{value}") == %{"tax_year" => ["is invalid"]},
               "#{route} tax_year=#{value}"
      end
    end

    budget = "/api/v1/tax/trim_budget?holder=Owner"

    assert %{"data" => %{"allowance_granted" => _granted}} =
             conn |> get(budget <> "&tax_year=2025") |> json_response(200)

    for value <- @not_years do
      assert refused(conn, budget <> "&tax_year=#{value}") == %{"tax_year" => ["is invalid"]},
             "trim_budget tax_year=#{value}"
    end

    assert refused(conn, budget) == %{"tax_year" => ["is required"]}
    assert refused(conn, budget <> "&tax_year=") == %{"tax_year" => ["is required"]}
  end
end
