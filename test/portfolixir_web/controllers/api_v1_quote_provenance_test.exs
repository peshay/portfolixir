defmodule PortfolixirWeb.ApiV1QuoteProvenanceTest do
  # E25 S6 (#891), F20 and G27 under decision T-9: a provenance value is the
  # system's to state. A quote written over the API is stored as manual
  # whatever source the body names, journaled with the rows it replaced, and
  # a manual pin is released back to provider data through a journaled route;
  # a tax statement snapshot's source is never taken from the body.
  use PortfolixirWeb.ConnCase, async: false

  import Ecto.Query
  import Portfolixir.WorldFixtures, only: [create_security!: 1]

  alias Portfolixir.Catalog.Quote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Journal
  alias Portfolixir.Repo
  alias Portfolixir.Tax.StatementSnapshot

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    %{conn: conn, security: create_security!(name: "Lakeside Grid Utilities AG", ticker: "LGU")}
  end

  defp sources(security) do
    Quote
    |> where([q], q.security_id == ^security.id)
    |> order_by([q], asc: q.date)
    |> Repo.all()
    |> Enum.map(&{Date.to_iso8601(&1.date), &1.source})
  end

  # User story:
  # As the operator whose valuations stand on stored closes,
  # I want a quote an agent writes over the API stored as manual whatever
  # source it names, and the dates it overwrote named in the answer,
  # so that no token holder can pass its own close off as provider data.
  #
  # Acceptance criteria:
  # - A row naming auto, coingecko or portfolio_performance is stored manual.
  # - The answer carries upserted and replaced (ISO dates of the stored rows
  #   the write changed); a new date is not replaced.
  # - The write leaves one journal entry for the security's quotes.
  test "an API quote write naming a reserved source is stored as manual",
       %{conn: conn, security: security} do
    {:ok, _, _} =
      Quotes.upsert_many(
        security.id,
        [%{date: ~D[2026-02-02], close: "20.00", source: "portfolio_performance"}],
        protect_manual: true
      )

    body =
      conn
      |> put("/api/v1/securities/#{security.id}/quotes", %{
        "quotes" => [
          %{"date" => "2026-02-02", "close" => "21.00", "source" => "auto"},
          %{"date" => "2026-02-03", "close" => "21.50", "source" => "coingecko"},
          %{"date" => "2026-02-04", "close" => "21.75", "source" => "portfolio_performance"}
        ]
      })
      |> json_response(200)

    assert body["data"] == %{"upserted" => 3, "replaced" => ["2026-02-02"]}

    assert sources(security) == [
             {"2026-02-02", "manual"},
             {"2026-02-03", "manual"},
             {"2026-02-04", "manual"}
           ]

    assert [entry] =
             Journal.list_entries(
               resource_type: "security_quotes",
               resource_id: Integer.to_string(security.id)
             )

    assert entry.actor_type == :api_token_rw
  end

  # User story:
  # As the operator's agent that pinned closes by hand,
  # I want to release the manual rows of a date range,
  # so that the next quote sync stores the provider's closes for those dates.
  #
  # Acceptance criteria:
  # - POST /api/v1/securities/:security_id/quotes/release with from and to
  #   removes the manual rows in the range, journaled, and answers the
  #   released dates; provider rows stay.
  # - A missing, malformed or reversed range answers 422 naming the field
  #   and removes nothing; an unknown security answers 404.
  test "a release removes the manual rows of a range and names them",
       %{conn: conn, security: security} do
    {:ok, _, _} =
      Quotes.upsert_many(
        security.id,
        [%{date: ~D[2026-02-05], close: "20.00", source: "auto"}],
        protect_manual: true
      )

    conn
    |> put("/api/v1/securities/#{security.id}/quotes", %{
      "quotes" => [
        %{"date" => "2026-02-02", "close" => "21.00"},
        %{"date" => "2026-02-03", "close" => "21.50"},
        %{"date" => "2026-03-02", "close" => "22.00"}
      ]
    })
    |> json_response(200)

    path = "/api/v1/securities/#{security.id}/quotes/release"

    for {params, field} <- [
          {%{"to" => "2026-02-28"}, "from"},
          {%{"from" => "2026-02-01"}, "to"},
          {%{"from" => "2026-02-30", "to" => "2026-02-28"}, "from"},
          {%{"from" => "2026-02-01", "to" => "3000-01-01"}, "to"},
          {%{"from" => "2026-02-28", "to" => "2026-02-01"}, "to"}
        ] do
      errors = conn |> post(path, params) |> json_response(422) |> Map.fetch!("errors")
      assert Map.has_key?(errors, field), inspect({params, errors})
    end

    assert conn
           |> post("/api/v1/securities/999999999/quotes/release", %{
             "from" => "2026-02-01",
             "to" => "2026-02-28"
           })
           |> json_response(404)

    assert length(sources(security)) == 4

    body =
      conn
      |> post(path, %{"from" => "2026-02-01", "to" => "2026-02-28"})
      |> json_response(200)

    assert body["data"] == %{
             "security_id" => security.id,
             "from" => "2026-02-01",
             "to" => "2026-02-28",
             "released" => ["2026-02-02", "2026-02-03"]
           }

    assert sources(security) == [{"2026-02-05", "auto"}, {"2026-03-02", "manual"}]

    assert [%{operation: :delete}, %{operation: :upsert}] =
             Journal.list_entries(
               resource_type: "security_quotes",
               resource_id: Integer.to_string(security.id)
             )
  end

  # User story:
  # As the operator reading a recorded tax statement,
  # I want its source stated by the system and never by the request body,
  # so that no caller can mark a typed statement as a PDF import.
  #
  # Acceptance criteria:
  # - A statement snapshot created or updated with a source in the body is
  #   stored with source manual.
  test "a tax statement snapshot's source is never taken from the body", %{conn: conn} do
    params = %{
      "institution" => "Example Bank",
      "holder" => "Owner",
      "tax_year" => 2025,
      "as_of" => "2025-12-31",
      "taxable_income" => "1200.00",
      "source" => "pdf_import"
    }

    body =
      conn
      |> post("/api/v1/tax/statement_snapshots", %{"statement_snapshot" => params})
      |> json_response(201)

    id = body["data"]["id"]
    assert Repo.get!(StatementSnapshot, id).source == "manual"

    conn
    |> patch("/api/v1/tax/statement_snapshots/#{id}", %{
      "statement_snapshot" => %{"source" => "pdf_import", "note" => "re-typed"}
    })
    |> json_response(200)

    assert %StatementSnapshot{source: "manual", note: "re-typed"} =
             Repo.get!(StatementSnapshot, id)
  end
end
