defmodule PortfolixirWeb.ApiV1NumericColumnBoundsTest do
  # E25 S4, G16 and G17 (#889), with F26 (#888), from the S3/S4 review round:
  # the column rule (round to the column's scale, then bound by its precision)
  # had reached the ledger only. A quote close, a tax statement's money field
  # or an allowance past its column's precision failed in the database with a
  # 500, and a positive close finer than its column's scale passed the
  # positive check and was stored as zero.
  use PortfolixirWeb.ConnCase, async: true

  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Repo
  alias Portfolixir.Tax.AllowanceOrder
  alias Portfolixir.Tax.Parameters
  alias Portfolixir.Tax.StatementSnapshot

  @too_big "100000000000000"

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, security: create_security!(name: "Northwind Rail Holdings", ticker: "NRH")}
  end

  defp quote_row(close), do: %{"date" => "2026-01-02", "close" => close, "source" => "manual"}

  # User story:
  # As the operator's agent writing a quote by hand,
  # I want a close that the database would round to zero refused, and a finer
  # close stored exactly as I am answered,
  # so that no zero ever becomes the valuation price.
  #
  # Acceptance criteria:
  # - A positive close that rounds to zero at the column's scale answers 422
  #   on close and stores nothing.
  # - A close finer than the column's scale is stored rounded half up.
  test "a close that rounds to zero answers 422, a finer close is stored rounded",
       %{conn: conn, security: security} do
    path = "/api/v1/securities/#{security.id}/quotes"

    body = conn |> put(path, %{"quotes" => [quote_row("0.0000004")]}) |> json_response(422)
    assert Map.has_key?(body["errors"], "close")
    assert Repo.aggregate(Quote, :count) == 0

    assert %{"data" => %{"upserted" => 1}} =
             conn |> put(path, %{"quotes" => [quote_row("12.3456785")]}) |> json_response(200)

    assert [%Quote{close: close}] = Repo.all(Quote)
    assert Decimal.equal?(close, Decimal.new("12.345679"))
  end

  # User story:
  # As the operator's agent transcribing a tax statement or writing a quote,
  # I want an amount larger than its column holds refused as a field error,
  # so that a typo answers a 422 naming the field instead of a server error.
  #
  # Acceptance criteria:
  # - A quote close, every tax statement money field, an allowance order's
  #   amount and a tax year's allowances past their column's precision answer
  #   422 naming the field, and store nothing.
  test "every other numeric writer answers an out-of-range amount with a 422",
       %{conn: conn, security: security} do
    snapshot = fn field ->
      {:post, "/api/v1/tax/statement_snapshots",
       %{
         "statement_snapshot" => %{
           "institution" => "Example Bank",
           "holder" => "Owner",
           "tax_year" => 2025,
           "as_of" => "2025-12-31",
           field => @too_big
         }
       }, field}
    end

    parameters = fn field ->
      {:put, "/api/v1/tax/parameters",
       %{
         "parameters" =>
           Map.put(
             %{
               "jurisdiction" => "DE",
               "tax_year" => 2031,
               "capital_gains_tax_rate" => "0.25",
               "solidarity_surcharge_rate" => "0.055",
               "saver_allowance_single" => "1000",
               "saver_allowance_joint" => "2000"
             },
             field,
             @too_big
           )
       }, field}
    end

    writes =
      [
        {:put, "/api/v1/securities/#{security.id}/quotes", %{"quotes" => [quote_row(@too_big)]},
         "close"},
        {:put, "/api/v1/tax/allowance_orders",
         %{
           "allowance_order" => %{
             "holder" => "Owner",
             "institution" => "Example Bank",
             "tax_year" => 2026,
             "amount_granted" => @too_big
           }
         }, "amount_granted"},
        parameters.("saver_allowance_single"),
        parameters.("saver_allowance_joint")
      ] ++ Enum.map(StatementSnapshot.money_fields(), &snapshot.(Atom.to_string(&1)))

    for {verb, path, body, field} <- writes do
      conn = Phoenix.ConnTest.dispatch(conn, @endpoint, verb, path, body)
      assert conn.status == 422, "#{verb} #{path} #{field}: #{conn.status}"

      assert Map.has_key?(Jason.decode!(conn.resp_body)["errors"], field),
             "#{verb} #{path}: #{conn.resp_body}"
    end

    assert Repo.aggregate(Quote, :count) == 0
    assert Repo.aggregate(StatementSnapshot, :count) == 0
    assert Repo.aggregate(AllowanceOrder, :count) == 0
    refute Repo.get_by(Parameters, tax_year: 2031)
  end
end
