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
  # As the operator of a self-hosted instance,
  # I want the read-only reconcile to cap the number of external rows,
  # so that an oversized paste cannot be used to exhaust server resources
  # (DoS hardening).
  #
  # Acceptance criteria:
  # - More than 10,000 rows is a 422 naming the limit.
  test "rejects more than 10,000 rows with a 422 naming the limit", %{conn: conn} do
    seed!()

    rows =
      for _ <- 1..10_001, do: %{"identifier" => "DE0007100000", "quantity" => "1"}

    body =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{"rows" => rows})
      |> json_response(422)

    assert [message] = body["errors"]["rows"]
    assert message =~ "10000"
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

  # User story:
  # As the operating agent,
  # I want malformed rows and mistyped row fields rejected with a 422 that
  # names the offending row,
  # so that a bad external list is a precise, actionable error and never a
  # silently misread position (ADR-0029 6).
  #
  # Acceptance criteria:
  # - A row that is not a {identifier, quantity} object is a 422 naming it.
  # - A blank identifier and a non-string identifier are 422s.
  # - A non-string currency and a non-positive-integer security_id are 422s.
  test "rejects malformed rows and mistyped fields with a naming 422", %{conn: conn} do
    seed!()

    reject = fn rows ->
      [message] =
        conn
        |> api_conn()
        |> post("/api/v1/holdings/reconcile", %{"rows" => rows})
        |> json_response(422)
        |> get_in(["errors", "rows"])

      message
    end

    non_object = reject.(["not an object"])
    assert non_object =~ "row 1"
    assert non_object =~ "must be a {identifier, quantity} object"

    assert reject.([%{"identifier" => "   ", "quantity" => "1"}]) =~
             "identifier must be a non-empty string"

    assert reject.([%{"identifier" => 123, "quantity" => "1"}]) =~
             "identifier must be a non-empty string"

    assert reject.([%{"identifier" => "X", "quantity" => "1", "currency" => 5}]) =~
             "currency must be a string"

    assert reject.([%{"identifier" => "X", "quantity" => "1", "security_id" => "abc"}]) =~
             "security_id must be a positive integer"

    assert reject.([%{"identifier" => "X", "quantity" => "1", "security_id" => -3}]) =~
             "security_id must be a positive integer"
  end

  # User story:
  # As the operating agent who has already decided a security's identity,
  # I want to pin a row to a security via a positive security_id,
  # so that the ladder is skipped and the decided identity sticks (ADR-0029 6).
  #
  # Acceptance criteria:
  # - A row with a valid positive security_id matches that security with
  #   matched_via "pinned", regardless of its identifier text.
  test "an explicit positive security_id pins the match", %{conn: conn} do
    %{security: security} = seed!()

    data =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "rows" => [
          %{
            "identifier" => "whatever the broker calls it",
            "quantity" => "10",
            "security_id" => security.id
          }
        ]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert [matched] = data["matched"]
    assert matched["security"]["id"] == security.id
    assert matched["matched_via"] == "pinned"
    assert matched["delta"] == "0"
  end

  # User story:
  # As the operating agent scoping a compare,
  # I want the scope params validated,
  # so that an ambiguous or malformed scope is a precise error rather than a
  # silently wrong basis (ADR-0029 6, FR-13).
  #
  # Acceptance criteria:
  # - portfolio_id and view given together is a 422 ("not both").
  # - A non-numeric or non-integer portfolio_id is a 422 ("is invalid").
  # - A valid string portfolio_id resolves and bounds the compare.
  test "scope params reject both-given and malformed portfolio ids", %{conn: conn} do
    %{portfolio: portfolio} = seed!()
    rows = [%{"identifier" => "DE0007100000", "quantity" => "10"}]

    both =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "portfolio_id" => portfolio.id,
        "view" => 1,
        "rows" => rows
      })
      |> json_response(422)

    assert both["errors"]["scope"] == ["pass either portfolio_id or view, not both"]

    invalid =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{"portfolio_id" => "abc", "rows" => rows})
      |> json_response(422)

    assert invalid["errors"]["portfolio_id"] == ["is invalid"]

    float =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{"portfolio_id" => 1.5, "rows" => rows})
      |> json_response(422)

    assert float["errors"]["portfolio_id"] == ["is invalid"]

    data =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "portfolio_id" => to_string(portfolio.id),
        "rows" => rows
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["basis"]["scope"] == "portfolio"
    assert data["basis"]["portfolio_id"] == portfolio.id
    assert [matched] = data["matched"]
    assert matched["delta"] == "0"
  end

  # User story:
  # As the operating agent reconciling one saved view's positions,
  # I want an optional view scope on the compare,
  # so that only the positions inside that view count and the basis states it
  # (FR-13).
  #
  # Acceptance criteria:
  # - A valid view id bounds the ledger side; the basis states scope "view".
  # - An empty view param is treated as the unscoped instance default.
  # - A malformed view id is a 422; an unknown view id is a 404.
  test "view scope bounds the compare; empty is instance, invalid 422, unknown 404", %{conn: conn} do
    seed!()

    {:ok, view} =
      Portfolixir.Buckets.create_view(Portfolixir.Actor.owner_ui(), %{
        name: "Reconcile View",
        include_all: true
      })

    rows = [%{"identifier" => "DE0007100000", "quantity" => "10"}]

    scoped =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{"view" => view.id, "rows" => rows})
      |> json_response(200)
      |> Map.fetch!("data")

    assert scoped["basis"]["scope"] == "view"
    assert scoped["basis"]["view_id"] == view.id
    assert [matched] = scoped["matched"]
    assert matched["ledger_quantity"] == "10"
    assert matched["delta"] == "0"

    instance =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{"view" => "", "rows" => rows})
      |> json_response(200)
      |> Map.fetch!("data")

    assert instance["basis"]["scope"] == "instance"

    invalid =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{"view" => "abc", "rows" => rows})
      |> json_response(422)

    assert invalid["errors"]["view"] == ["is invalid"]

    conn
    |> api_conn()
    |> post("/api/v1/holdings/reconcile", %{"view" => 999_999, "rows" => rows})
    |> json_response(404)
  end

  # User story:
  # As the operating agent,
  # I want a cross-tier ambiguous row surfaced with its candidates over the API,
  # so that a string matching two securities is a visible decision, never a
  # silent pick (ADR-0029 6).
  #
  # Acceptance criteria:
  # - A WKN-of-A / ticker-of-B identifier is returned under "ambiguous" with
  #   both candidate securities and the row's identifier/index.
  test "an ambiguous row is serialized with its candidates", %{conn: conn} do
    %{portfolio: portfolio} = seed!()

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Ambig Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Ambig Depot"
      })

    {:ok, a} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Alpha AG",
        wkn: "AMBIG1",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, b} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Beta AG",
        ticker_symbol: "AMBIG1",
        currency_code: "EUR",
        asset_class: "equity"
      })

    for security <- [a, b] do
      {:ok, _} =
        Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
          portfolio_id: portfolio.id,
          securities_account_id: depot.id,
          cash_account_id: cash.id,
          security_id: security.id,
          type: "buy",
          date: ~D[2026-01-05],
          quantity: "1",
          price: "10",
          fees: "0",
          taxes: "0",
          currency_code: "EUR"
        })
    end

    data =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "rows" => [%{"identifier" => "AMBIG1", "quantity" => "2", "currency" => "EUR"}]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["matched"] == []
    assert [ambiguous] = data["ambiguous"]
    assert ambiguous["identifier"] == "AMBIG1"
    assert ambiguous["quantity"] == "2"
    assert ambiguous["currency"] == "EUR"

    candidate_ids = ambiguous["candidates"] |> Enum.map(& &1["id"]) |> Enum.sort()
    assert candidate_ids == Enum.sort([a.id, b.id])
  end

  # User story (2026-07-29, issue #609):
  # As the operating LLM agent reading a reconcile response,
  # I want matched rows in the order I sent them and no filler fields,
  # so that mapping a finding back to my input line is trivial and every row
  # costs only the tokens it needs.
  #
  # Acceptance criteria:
  # - matched[] is ordered by the lowest input row index of each match, not by
  #   security id.
  # - The embedded security carries identity only; no null asset_class filler.
  test "matched rows follow input order and carry identity only", %{conn: conn} do
    %{portfolio: portfolio, security: first} = seed!()

    {:ok, second} =
      Catalog.create_security(Portfolixir.Actor.owner_ui(), %{
        name: "Second AG",
        isin: "DE0008404005",
        currency_code: "EUR",
        asset_class: "equity"
      })

    {:ok, cash} =
      Portfolios.create_cash_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "Second Cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: "Second Depot"
      })

    {:ok, _} =
      Ledger.create_transaction(Portfolixir.Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: second.id,
        type: "buy",
        date: ~D[2026-01-02],
        quantity: "5",
        price: "50",
        fees: "0",
        taxes: "0",
        currency_code: "EUR"
      })

    # Sent second-then-first: the response must keep that order, not id order.
    body =
      conn
      |> api_conn()
      |> post("/api/v1/holdings/reconcile", %{
        "rows" => [
          %{"identifier" => second.isin, "quantity" => "5"},
          %{"identifier" => first.isin, "quantity" => "10"}
        ]
      })
      |> json_response(200)

    assert Enum.map(body["data"]["matched"], & &1["security"]["id"]) == [second.id, first.id]

    embedded = hd(body["data"]["matched"])["security"]
    refute Map.has_key?(embedded, "asset_class")
    assert Map.keys(embedded) |> Enum.sort() == ~w(currency_code id isin name ticker_symbol wkn)
  end
end
