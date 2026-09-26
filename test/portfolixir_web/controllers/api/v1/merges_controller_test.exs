defmodule PortfolixirWeb.Api.V1.MergesControllerTest do
  # ADR-0050 §12 over the API (L5a, #328): the merge records a lifecycle
  # merge leaves behind, listed as the audit read of a destructive write.
  # Agent-first: the list view lands no later than Sprint 17 under the
  # two-way deadline. Every name and amount is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Merges read",
        base_currency_code: "EUR"
      })

    %{conn: conn, portfolio: portfolio}
  end

  # User story:
  # As the agent auditing what happened to a household's accounts,
  # I want to list every merge the instance recorded, newest first, with
  # what went into what, who did it and what it moved,
  # so that I can explain a missing account or a former name without
  # reading the journal row by row.
  #
  # Acceptance criteria:
  # - GET /api/v1/merges answers the merge records newest first, each with
  #   id, kind, source {id, name}, target {id, name, merged_into},
  #   portfolio_id, actor_type, actor_label, inserted_at and
  #   manifest_summary: the manifest with every list replaced by its count
  #   and every other value as stored (the operator's choices among them).
  # - The source's name is the one its snapshot recorded; the target's is its
  #   live name, and merged_into is null while it is live.
  # - A target a later merge took away keeps the name that merge recorded,
  #   and merged_into names the live end of the chain.
  # - meta states the order, the count and the limit applied.
  test "lists the merge records newest first with the manifest summarized", ctx do
    savings = cash!(ctx.portfolio, "Savings")
    old = cash!(ctx.portfolio, "Savings (old)")
    older = cash!(ctx.portfolio, "Savings (older)")
    book!(ctx.portfolio, old, "deposit", "100.00", ~D[2025-01-02])
    book!(ctx.portfolio, older, "deposit", "40.00", ~D[2025-01-03])
    book!(ctx.portfolio, savings, "deposit", "10.00", ~D[2025-01-04])

    first = merge_cash!(older, old)
    second = merge_cash!(old, savings)

    assert %{"data" => [newest, oldest], "meta" => meta} =
             ctx.conn |> get("/api/v1/merges") |> json_response(200)

    assert meta == %{"order" => "inserted_at:desc,id:desc", "count" => 2, "limit" => 100}

    assert newest["id"] == second.id
    assert newest["kind"] == "cash_account"
    assert newest["source"] == %{"id" => old.id, "name" => "Savings (old)"}
    assert newest["target"] == %{"id" => savings.id, "name" => "Savings", "merged_into" => nil}
    assert newest["portfolio_id"] == ctx.portfolio.id
    assert newest["actor_type"] == "api_token_rw"
    assert newest["actor_label"] == "merges-test"
    assert {:ok, _at, 0} = DateTime.from_iso8601(newest["inserted_at"])

    summary = newest["manifest_summary"]
    assert summary["choices"] == %{"collapse_key_equal" => nil}
    assert summary["transactions"] == %{"moved" => 2, "restated" => 0, "deleted" => 0}
    assert summary["former_names"] == %{"appended" => 2, "not_kept" => 0}
    assert summary["linearity"] == %{"dates_checked" => 4}

    # The first merge's target was merged away by the second: its name is the
    # one the second recorded, and merged_into names the survivor.
    assert oldest["id"] == first.id
    assert oldest["source"] == %{"id" => older.id, "name" => "Savings (older)"}

    assert oldest["target"] == %{
             "id" => old.id,
             "name" => "Savings (old)",
             "merged_into" => savings.id
           }

    refute Map.has_key?(newest, "manifest")
    refute Map.has_key?(newest, "source_snapshot")
  end

  # User story:
  # As the agent,
  # I want the merge list bounded like every other list read,
  # so that one call never asks the instance to materialise an unbounded
  # table.
  #
  # Acceptance criteria:
  # - limit= keeps the newest records; absent is 100, an oversized value is
  #   capped at 1000 and echoed in meta.limit.
  # - Zero, a negative or a non-number answers 422 naming limit.
  # - No merge yet answers an empty list.
  test "takes the list-limit family's limit", ctx do
    assert %{"data" => [], "meta" => %{"count" => 0}} =
             ctx.conn |> get("/api/v1/merges") |> json_response(200)

    a = cash!(ctx.portfolio, "Giro")
    b = cash!(ctx.portfolio, "Giro (old)")
    c = cash!(ctx.portfolio, "Giro (older)")
    merge_cash!(c, a)
    newest = merge_cash!(b, a)

    assert %{"data" => [only], "meta" => %{"limit" => 1, "count" => 1}} =
             ctx.conn |> get("/api/v1/merges?limit=1") |> json_response(200)

    assert only["id"] == newest.id

    assert %{"meta" => %{"limit" => 1000}} =
             ctx.conn |> get("/api/v1/merges?limit=999999") |> json_response(200)

    for bad <- ["0", "-3", "abc"] do
      assert %{"errors" => %{"limit" => [_ | _]}} =
               ctx.conn |> get("/api/v1/merges?limit=#{bad}") |> json_response(422)
    end
  end

  # User story:
  # As the agent,
  # I want a depot merge listed under its kind with the depot's portfolio,
  # so that the list reads the same for every merge kind.
  #
  # Acceptance criteria:
  # - A depot merge answers kind securities_account, its portfolio, and
  #   its manifest's position-bucket and rounding lists as counts.
  test "lists a depot merge under its kind", ctx do
    cash = cash!(ctx.portfolio, "Broker cash")
    depot_1 = depot!(ctx.portfolio, "Depot 1", cash)
    depot_2 = depot!(ctx.portfolio, "Depot 2", cash)

    {:ok, preview} = Lifecycle.preview_depot_merge(depot_2.id, depot_1.id)

    {:ok, _record, :applied} =
      Lifecycle.merge_depot(actor(), depot_2.id, depot_1.id, %{plan_digest: preview.plan_digest})

    assert %{"data" => [record]} = ctx.conn |> get("/api/v1/merges") |> json_response(200)
    assert record["kind"] == "securities_account"
    assert record["portfolio_id"] == ctx.portfolio.id
    assert record["source"] == %{"id" => depot_2.id, "name" => "Depot 2"}
    assert record["target"]["name"] == "Depot 1"
    assert record["manifest_summary"]["rounding_differences"] == 0
  end

  defp actor, do: Actor.api_token_rw("merges-test")

  defp merge_cash!(source, target) do
    {:ok, preview} = Lifecycle.preview_cash_merge(source.id, target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_cash_account(actor(), source.id, target.id, %{
        plan_digest: preview.plan_digest
      })

    record
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

  defp depot!(portfolio, name, cash) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        cash_account_id: cash.id
      })

    depot
  end

  defp book!(portfolio, account, type, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        cash_account_id: account.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end
end
