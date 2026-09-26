defmodule PortfolixirWeb.Api.V1.MergeIdentityCheckControllerTest do
  # ADR-0050 §7 step 6, §10 and §16 invariants 9, 10 and 13 over the API
  # (the closing act's patch-coverage pass, #328; risk-tier: money and
  # quantity identity, ADR-0036): a merge whose identity check fails — a
  # bug in the merge, never an expected answer — answers the agent a clean
  # 409 `identity_check_failed` naming the date and both figures, the
  # figures as strings, and writes nothing. The fault is a write that lands
  # other than planned (`Portfolixir.MisplannedWrite`); the context half is
  # test/portfolixir/lifecycle/merge_identity_check_test.exs.
  #
  # async: false — creating a trigger on `transactions` takes a lock every
  # concurrent test on the ledger would wait on.
  #
  # Every name, amount and quantity is synthetic.
  use PortfolixirWeb.ConnCase, async: false

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.MisplannedWrite
  alias Portfolixir.Portfolios
  alias Portfolixir.Repo

  import Ecto.Query, only: [from: 2]

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Identity API",
        base_currency_code: "EUR"
      })

    %{conn: conn, portfolio: portfolio}
  end

  # User story:
  # As the agent applying a merge the operator approved,
  # I want a merge that would not add up answered with a conflict that
  # names the date and both figures,
  # so that I report a bug to the operator instead of a server error, and
  # nothing was changed.
  #
  # Acceptance criteria:
  # - A cash merge answers 409 identity_check_failed; errors.identity holds
  #   the date and the expected and found balance as strings; the detail
  #   says the merge was rolled back.
  # - A depot merge answers the same, naming the security too.
  # - Neither writes a merge record or a journal entry.
  test "a merge that would not add up answers 409 identity_check_failed", ctx do
    target = cash!(ctx.portfolio, "Savings")
    source = cash!(ctx.portfolio, "Savings (old)")
    deposit!(ctx.portfolio, target, "500.00", ~D[2025-01-02])
    deposit!(ctx.portfolio, source, "250.00", ~D[2025-01-03])

    broker = cash!(ctx.portfolio, "Broker cash")
    depot_t = depot!(ctx.portfolio, broker, "Depot 1")
    depot_s = depot!(ctx.portfolio, broker, "Depot 2")
    security = security!("Synthetic Identity ETF")
    delivery!(ctx.portfolio, depot_t, security, "10", ~D[2025-01-02])
    delivery!(ctx.portfolio, depot_s, security, "4", ~D[2025-01-03])

    cash_digest = digest(ctx.conn, "cash_accounts", source.id, target.id)
    depot_digest = digest(ctx.conn, "securities_accounts", depot_s.id, depot_t.id)

    MisplannedWrite.install!([
      {"cash_account_id", "gross_amount"},
      {"securities_account_id", "quantity"}
    ])

    mark = journal_mark()

    assert %{"errors" => cash_errors} =
             ctx.conn
             |> post("/api/v1/cash_accounts/#{source.id}/merge", %{
               target_id: target.id,
               plan_digest: cash_digest,
               collapse_key_equal: false
             })
             |> json_response(409)

    assert cash_errors["code"] == "identity_check_failed"

    assert cash_errors["identity"] == %{
             "date" => "2025-01-03",
             "expected" => "750",
             "actual" => "751"
           }

    assert cash_errors["detail"] =~
             "on 2025-01-03: 750 expected, 751 found): the merge was rolled back"

    assert %{"errors" => depot_errors} =
             ctx.conn
             |> post("/api/v1/securities_accounts/#{depot_s.id}/merge", %{
               target_id: depot_t.id,
               plan_digest: depot_digest,
               collapse_key_equal: false
             })
             |> json_response(409)

    assert depot_errors["code"] == "identity_check_failed"

    assert depot_errors["identity"] == %{
             "date" => "2025-01-03",
             "security_id" => security.id,
             "expected" => "14",
             "actual" => "15"
           }

    assert depot_errors["detail"] =~
             "on 2025-01-03 for security ##{security.id}: 14 expected, 15 found"

    assert journal_mark() == mark
    assert Repo.aggregate(MergeRecord, :count) == 0
  end

  # --- world ----------------------------------------------------------------------

  defp digest(conn, collection, source_id, target_id) do
    conn
    |> get("/api/v1/#{collection}/#{source_id}/merge_preview?target_id=#{target_id}")
    |> json_response(200)
    |> get_in(["data", "plan_digest"])
  end

  defp cash!(portfolio, name) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp depot!(portfolio, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  defp security!(name) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{name: name, currency_code: "EUR"})

    security
  end

  defp deposit!(portfolio, cash, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp delivery!(portfolio, depot, security, quantity, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        security_id: security.id,
        type: "inbound_delivery",
        date: date,
        quantity: quantity,
        currency_code: "EUR"
      })

    tx
  end

  defp journal_mark do
    Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0
  end
end
