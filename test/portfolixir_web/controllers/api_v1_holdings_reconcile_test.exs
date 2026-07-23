defmodule PortfolixirWeb.ApiV1HoldingsReconcileTest do
  use PortfolixirWeb.ConnCase

  alias Portfolixir.Catalog
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  @guidance "resolve a difference by booking the missing transaction of the correct kind; " <>
              "balance snapshots and unpriced deliveries are last resorts that distort cost basis"

  defp api_conn(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer test-api-token")
  end

  defp seed! do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Reconcile Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Reconcile Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Reconcile Depot"
      })

    {:ok, security} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Reconciled AG",
        isin: "DE0007100000",
        wkn: "710000",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "10",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    %{portfolio: portfolio, security: security}
  end

  # User story:
  # As the operating LLM agent holding an external broker position list,
  # I want a read-only reconcile endpoint that matches the list through the
  # stable-identity ladder and computes exact quantity deltas,
  # so that discrepancies become exact, guided, bookable facts instead of
  # arithmetic done in my head (ADR-0029 6, FR-35).
  #
  # Acceptance criteria:
  # - POST /api/v1/holdings/reconcile returns matched rows with matched_via,
  #   ledger/external quantities and delta as Decimal strings.
  # - The response embeds the resolution guidance verbatim and states its
  #   basis (as_of, scope).
  # - Unmatched rows and ledger positions absent from the list are surfaced.
  test "reconciles an external list against the ledger, read-only and guided", %{conn: conn} do
    %{portfolio: portfolio, security: security} = seed!()

    {:ok, absent} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Absent AG",
        isin: "US0378331005",
        currency_code: "USD",
        asset_class: "equity"
      })

    {:ok, cash2} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Absent Cash",
        currency_code: "USD"
      })

    {:ok, depot2} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash2.id,
        name: "Absent Depot"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot2.id,
        cash_account_id: cash2.id,
        security_id: absent.id,
        type: "buy",
        date: ~D[2026-01-03],
        quantity: "3",
        price: "10",
        fees: "0",
        taxes: "0",
        currency_code: "USD"
      })

    data =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "rows" => [
          %{"identifier" => "DE0007100000", "quantity" => "12.5"},
          %{"identifier" => "unknown thing", "quantity" => "1"}
        ]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["guidance"] == @guidance
    assert data["basis"]["scope"] == "instance"
    assert data["basis"]["as_of"] == Date.to_iso8601(Date.utc_today())

    assert [matched] = data["matched"]
    assert matched["security"]["id"] == security.id
    assert matched["matched_via"] == "isin"
    assert matched["weak_match"] == false
    assert matched["ledger_quantity"] == "10"
    assert matched["external_quantity"] == "12.5"
    assert matched["delta"] == "2.5"

    assert [unmatched] = data["unmatched"]
    assert unmatched["identifier"] == "unknown thing"
    assert unmatched["reason"] == "currency_required"

    assert [missing] = data["missing_from_list"]
    assert missing["security"]["id"] == absent.id
    assert missing["ledger_quantity"] == "3"
  end

  # User story:
  # As the operating agent matching through the weak tiers,
  # I want tier-3/4 matches to carry the weak-match caveat,
  # so that I confirm the security before booking anything (ADR-0029 6).
  #
  # Acceptance criteria:
  # - A name+currency match carries weak_match: true and the caveat text.
  test "a weak name match carries the confirm-before-booking caveat", %{conn: conn} do
    seed!()

    data =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "rows" => [
          %{"identifier" => "Reconciled AG", "quantity" => "10", "currency" => "EUR"}
        ]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert [matched] = data["matched"]
    assert matched["matched_via"] == "name"
    assert matched["weak_match"] == true
    assert matched["caveat"] == "confirm the security before booking"
  end

  # User story:
  # As the operating agent,
  # I want non-canonical quantity strings rejected with a clear message,
  # so that locale parsing stays the client's job and no number is silently
  # misread (ADR-0029 6).
  #
  # Acceptance criteria:
  # - A comma-decimal quantity is a 422 naming the offending row.
  # - An empty rows list is a 422.
  test "comma decimals and empty row lists are 422s", %{conn: conn} do
    seed!()

    comma =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "rows" => [%{"identifier" => "DE0007100000", "quantity" => "12,5"}]
      })
      |> json_response(422)

    assert [message] = comma["errors"]["rows"]
    assert message =~ "row 1"
    assert message =~ "canonical dot-decimal"

    empty =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{"rows" => []})
      |> json_response(422)

    assert [empty_message] = empty["errors"]["rows"]
    assert empty_message =~ "non-empty"
  end

  # User story:
  # As the operating agent reconciling one depot's list,
  # I want an optional portfolio scope on the compare,
  # so that other portfolios' positions do not bleed into the deltas.
  #
  # Acceptance criteria:
  # - portfolio_id bounds the ledger side; the basis states the scope.
  # - An unknown portfolio_id is a 404.
  test "portfolio scope bounds the compare and unknown portfolios 404", %{conn: conn} do
    %{portfolio: portfolio, security: security} = seed!()

    {:ok, other} =
      Portfolios.create_portfolio(Portfolixir.Actor.owner_ui(), %{
        name: "Other Portfolio",
        base_currency_code: "EUR"
      })

    {:ok, other_cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: other.id,
        name: "Other Cash",
        currency_code: "EUR"
      })

    {:ok, other_depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: other.id,
        cash_account_id: other_cash.id,
        name: "Other Depot"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: other.id,
        securities_account_id: other_depot.id,
        cash_account_id: other_cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2026-01-04],
        quantity: "5",
        price: "100",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    data =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "portfolio_id" => portfolio.id,
        "rows" => [%{"identifier" => "DE0007100000", "quantity" => "10"}]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["basis"]["scope"] == "portfolio"
    assert data["basis"]["portfolio_id"] == portfolio.id
    assert [matched] = data["matched"]
    assert matched["ledger_quantity"] == "10"
    assert matched["delta"] == "0"

    conn
    |> api_conn()
    |> post("/api/v1/holdings/reconcile", %{
      "portfolio_id" => other.id + 1_000_000,
      "rows" => [%{"identifier" => "DE0007100000", "quantity" => "10"}]
    })
    |> json_response(404)
  end

  # User story:
  # As the accountable owner of the local instance,
  # I want the reconcile endpoint to persist nothing (NFR-4),
  # so that the external list is compared and forgotten — read-only by
  # construction.
  #
  # Acceptance criteria:
  # - No securities, transactions, or audit-journal rows are created.
  # - The endpoint requires the bearer token.
  test "reconcile persists nothing and requires auth", %{conn: conn} do
    seed!()

    counts = fn ->
      {
        Repo.aggregate(Portfolixir.Catalog.Security, :count),
        Repo.aggregate(Portfolixir.Ledger.Transaction, :count),
        Repo.aggregate(Portfolixir.Journal.Entry, :count)
      }
    end

    before_counts = counts.()

    conn
    |> api_conn()
    |> post("/api/v1/holdings/reconcile", %{
      "rows" => [
        %{"identifier" => "DE0007100000", "quantity" => "999"},
        %{"identifier" => "Never Seen Before AG", "quantity" => "1", "currency" => "EUR"}
      ]
    })
    |> json_response(200)

    assert counts.() == before_counts

    conn
    |> put_req_header("accept", "application/json")
    |> post("/api/v1/holdings/reconcile", %{
      "rows" => [%{"identifier" => "DE0007100000", "quantity" => "1"}]
    })
    |> json_response(401)
  end
end
