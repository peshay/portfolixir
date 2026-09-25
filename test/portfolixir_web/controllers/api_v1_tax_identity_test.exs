defmodule PortfolixirWeb.ApiV1TaxIdentityTest do
  # E25 S6 (#891), G22: the allocation read's tax context and the trim-budget
  # read iterated raw holder spellings, so statements under two case
  # spellings of one taxpayer yielded two partial budgets. They now roll up
  # per identity, the database's fold of the holder.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Classifications
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios
  alias Portfolixir.Tax

  defp owner, do: Actor.owner_ui()

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp record!(holder, institution, as_of) do
    {:ok, _snapshot} =
      Tax.create_snapshot(owner(), %{
        institution: institution,
        holder: holder,
        tax_year: as_of.year,
        as_of: as_of,
        allowance_granted: Decimal.new("1000.00"),
        allowance_used: Decimal.new("400.00"),
        loss_pot_equities: Decimal.new("2500.00")
      })
  end

  # User story:
  # As the agent reading the tax headroom beside the allocation drift,
  # I want one trim budget per taxpayer, whatever case their statements
  # were recorded in,
  # so that I neither read half a budget nor count one twice.
  #
  # Acceptance criteria:
  # - Two statements under two case spellings of one holder yield one entry
  #   in the allocation read's trim_budgets, covering both institutions.
  # - GET /api/v1/tax/trim_budget under either spelling rolls up both.
  test "two case spellings of one holder yield one trim budget", %{conn: conn} do
    today = Clock.today()
    as_of = Enum.max([Date.add(today, -2), Date.new!(today.year, 1, 1)], Date)
    record!("Anna Muster", "Bank Eins", as_of)
    record!("ANNA MUSTER", "Bank Zwei", as_of)

    {:ok, portfolio} =
      Portfolios.create_portfolio(owner(), %{name: "Tax Identity", base_currency_code: "EUR"})

    {:ok, classification} = Classifications.create_classification(owner(), %{name: "Strategy"})

    response =
      conn
      |> api_conn()
      |> get(
        "/api/v1/portfolios/#{portfolio.id}/allocation?classification_id=#{classification.id}" <>
          "&tax_context=true"
      )
      |> json_response(200)

    assert [budget] = response["data"]["tax_context"]["trim_budgets"]
    assert length(budget["institutions"]) == 2

    trim =
      conn
      |> api_conn()
      |> get("/api/v1/tax/trim_budget?holder=anna%20muster&tax_year=#{as_of.year}")
      |> json_response(200)

    assert length(trim["data"]["institutions"]) == 2
  end
end
