defmodule PortfolixirWeb.ApiV1QuoteBasisTest do
  use PortfolixirWeb.ConnCase

  import Portfolixir.WorldFixtures, only: [base_world: 1, buy!: 3, create_security!: 1]

  alias Portfolixir.Actor
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Repo

  @auth {"authorization", "Bearer test-api-token"}

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(elem(@auth, 0), elem(@auth, 1))
  end

  defp insert_quote!(security, date, close, source) do
    {:ok, _} =
      %SecurityQuote{}
      |> SecurityQuote.changeset(%{
        security_id: security.id,
        date: date,
        close: Decimal.new(close),
        source: source
      })
      |> Repo.insert()
  end

  defp split_world do
    world = base_world(name: "QB World", cash_name: "QB Cash", depot_name: "QB Depot")
    security = create_security!(name: "QB Co", ticker: "QBB")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    insert_quote!(security, ~D[2026-01-31], "110", "manual")
    insert_quote!(security, ~D[2026-02-05], "12", "manual")

    {:ok, _} =
      Splits.book_split(Actor.owner_ui(), %{
        security_id: security.id,
        date: ~D[2026-02-02],
        ratio_numerator: 10,
        ratio_denominator: 1
      })

    {world, security}
  end

  # User story (ADR-0028 §2, FR-13 self-describing responses, issue #590):
  # As an API/MCP consumer reading quote history after a split was booked,
  # I want each row to carry the stored close, the split-adjusted close and
  # the row's basis,
  # so that I can render a continuous series without re-deriving factors —
  # while the auditable stored values stay untouched.
  test "GET /api/v1/securities/:id/quotes serves stored close plus adjusted_close and basis", %{
    conn: conn
  } do
    {_world, security} = split_world()

    response =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}/quotes")
      |> json_response(200)

    assert [pre_split, post_split] = response["data"]

    assert pre_split["date"] == "2026-01-31"
    assert pre_split["close"] == "110"
    assert pre_split["adjusted_close"] == "11"
    assert pre_split["basis"] == "raw"
    assert pre_split["adjusted"] == true

    assert post_split["date"] == "2026-02-05"
    assert post_split["close"] == "12"
    assert post_split["adjusted_close"] == "12"
    assert post_split["adjusted"] == false
  end

  # User story (ADR-0028 §2 misclassification guard over the API, issue #590):
  # As an MCP agent previewing a split booking,
  # I want the preview response to carry the stored closes around the
  # effective date and the basis check — with the escape-hatch flag named,
  # so that I can detect an already-adjusted history before booking.
  test "POST /api/v1/splits/preview exposes quotes_around and the quote_basis_check", %{
    conn: conn
  } do
    world = base_world(name: "QP World", cash_name: "QP Cash", depot_name: "QP Depot")
    security = create_security!(name: "QP Co", ticker: "QPP")
    buy!(world, security, quantity: "10", price: "100", date: ~D[2026-01-05])
    # Continuous series classified raw: the guard must warn.
    insert_quote!(security, ~D[2026-02-01], "10", "manual")
    insert_quote!(security, ~D[2026-02-02], "10.2", "manual")

    response =
      conn
      |> api_conn()
      |> post(
        "/api/v1/splits/preview",
        Jason.encode!(%{
          "security_id" => security.id,
          "date" => "2026-02-02",
          "ratio_numerator" => 10,
          "ratio_denominator" => 1
        })
      )
      |> json_response(200)

    data = response["data"]
    assert "quote_basis_contradiction" in data["warnings"]
    assert data["quote_basis_check"]["status"] == "contradiction"
    assert data["quote_basis_check"]["expected_basis"] == "raw"
    assert data["quote_basis_check"]["observed"] == "continuous"
    assert data["quote_basis_check"]["note"] =~ "treat_quotes_as_raw"

    assert [%{"date" => "2026-02-01", "close" => "10", "source" => "manual"}, _after] =
             data["quotes_around"]
  end

  # User story (ADR-0028 §2 escape hatch over the API, issue #590):
  # As an API consumer,
  # I want the per-security treat_quotes_as_raw override readable and
  # writable through the securities endpoints,
  # so that a never-adjusting provider can be flagged without the UI (AR-11).
  test "PATCH /api/v1/securities/:id round-trips treat_quotes_as_raw", %{conn: conn} do
    security = create_security!(name: "Flag Co", ticker: "FLG")

    response =
      conn
      |> api_conn()
      |> get("/api/v1/securities/#{security.id}")
      |> json_response(200)

    assert response["data"]["treat_quotes_as_raw"] == false

    response =
      conn
      |> api_conn()
      |> patch(
        "/api/v1/securities/#{security.id}",
        Jason.encode!(%{"security" => %{"treat_quotes_as_raw" => true}})
      )
      |> json_response(200)

    assert response["data"]["treat_quotes_as_raw"] == true
  end
end
