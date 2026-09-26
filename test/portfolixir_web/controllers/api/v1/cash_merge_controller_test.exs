defmodule PortfolixirWeb.Api.V1.CashMergeControllerTest do
  # ADR-0050 §7, §8, §10 and §12 over the API (L3a, #328; risk-tier: money
  # identity and idempotency, ADR-0036): the cash-account merge preview, a
  # read, and the apply, which takes the preview's digest and the operator's
  # choice. §16 invariant 12 (the preview's after-figures equal the API reads
  # right after the apply) and 13 (each refusal answers its code and writes
  # nothing; a stale digest answers 409 plan_changed with the fresh preview)
  # are pinned here on the wire. Every name and amount is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Portfolios

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Merge API",
        base_currency_code: "EUR"
      })

    target = cash!(portfolio, "Savings")
    source = cash!(portfolio, "Savings (old)")

    %{conn: conn, portfolio: portfolio, source: source, target: target}
  end

  # User story:
  # As the agent tidying up a household's accounts,
  # I want a preview of merging one cash account into another that states
  # every figure the merge will produce, for either answer to the duplicate
  # question, with a digest I send back,
  # so that I can show the operator the consequence before anything is
  # written.
  #
  # Acceptance criteria:
  # - GET /api/v1/cash_accounts/:id/merge_preview?target_id= answers 200 with
  #   plan_digest, both accounts with their balances, the guards, the S↔T
  #   transfers, the key-equal pairs, the former names after, and
  #   outcome_by_collapse_key_equal for "false" and "true" (balance, rows
  #   moved and deleted, restated anchors as stated + other = after, flow
  #   changes).
  # - Every financial decimal is a string.
  # - It writes nothing.
  test "the preview answers every figure, decimals as strings, and writes nothing", ctx do
    rows = example!(ctx)
    mark = journal_mark()

    assert %{"data" => preview} =
             ctx.conn
             |> get(
               "/api/v1/cash_accounts/#{ctx.source.id}/merge_preview?target_id=#{ctx.target.id}"
             )
             |> json_response(200)

    assert "sha256:" <> _ = preview["plan_digest"]
    assert preview["kind"] == "cash_account"
    assert preview["source"]["balance"] == "902.5"
    assert preview["target"]["balance"] == "807.5"
    assert preview["choice_required"] == true
    assert Enum.all?(preview["guards"], & &1["passed"])
    assert [%{"id" => transfer_id, "gross_amount" => "200"}] = preview["internal_transfers"]
    assert transfer_id == rows.transfer.id
    assert length(preview["key_equal_pairs"]) == 2
    assert preview["former_names"]["after"] == ["Savings (old)"]

    %{"false" => keep, "true" => collapse} = preview["outcome_by_collapse_key_equal"]
    assert keep["balance"] == "1710"
    assert collapse["balance"] == "1702.5"

    assert %{
             "stated" => "900",
             "other_balance" => "712.4",
             "after" => "1612.4",
             "side" => "source"
           } =
             Enum.find(keep["restated_anchors"], &(&1["id"] == rows.s_anchor.id))

    assert [%{"kind" => "absorbed", "change" => "12.4", "cash_account_id" => absorbed_on}] =
             collapse["flow_changes"]

    assert absorbed_on == ctx.source.id
    assert journal_mark() == mark
  end

  # User story:
  # As the operator whose agent merged the accounts I approved,
  # I want the figures the API reads right after the merge to be the ones
  # the preview promised,
  # so that what I approved is what I got.
  #
  # Acceptance criteria:
  # - POST /api/v1/cash_accounts/:id/merge with target_id, plan_digest and
  #   collapse_key_equal answers 201 with the merge record (the actor is the
  #   token's).
  # - Right after, GET /api/v1/cash_accounts shows the target with the
  #   preview's balance and former names and no source; the linked depot
  #   links to the target; every restated anchor carries the preview's
  #   after amount on GET /api/v1/transactions.
  # - A retry of the same call answers 200 with the same record and journals
  #   nothing.
  test "the apply lands on the preview's figures, and a retry answers the record", ctx do
    example!(ctx)

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: ctx.source.id,
        name: "Broker depot"
      })

    preview = preview!(ctx)
    outcome = preview["outcome_by_collapse_key_equal"]["true"]

    body = %{
      target_id: ctx.target.id,
      plan_digest: preview["plan_digest"],
      collapse_key_equal: true
    }

    assert %{"data" => record, "already_applied" => false} =
             ctx.conn
             |> post("/api/v1/cash_accounts/#{ctx.source.id}/merge", body)
             |> json_response(201)

    assert record["kind"] == "cash_account"
    assert record["source_id"] == ctx.source.id
    assert record["target_id"] == ctx.target.id
    assert record["plan_digest"] == preview["plan_digest"]
    assert record["actor_type"] == "api_token_rw"
    assert record["manifest"]["choices"] == %{"collapse_key_equal" => true}

    accounts =
      ctx.conn |> get("/api/v1/cash_accounts") |> json_response(200) |> Map.fetch!("data")

    refute Enum.any?(accounts, &(&1["id"] == ctx.source.id))
    target = Enum.find(accounts, &(&1["id"] == ctx.target.id))
    assert target["balance"] == outcome["balance"]
    assert target["former_names"] == preview["former_names"]["after"]

    depots =
      ctx.conn |> get("/api/v1/securities_accounts") |> json_response(200) |> Map.fetch!("data")

    assert Enum.find(depots, &(&1["id"] == depot.id))["cash_account_id"] == ctx.target.id

    transactions =
      ctx.conn |> get("/api/v1/transactions") |> json_response(200) |> Map.fetch!("data")

    for %{"id" => id, "after" => amount} <- outcome["restated_anchors"] do
      assert Decimal.equal?(
               Decimal.new(Enum.find(transactions, &(&1["id"] == id))["gross_amount"]),
               Decimal.new(amount)
             )
    end

    assert length(
             Enum.filter(
               transactions,
               &(&1["cash_account_id"] == ctx.target.id or
                   &1["counter_cash_account_id"] == ctx.target.id)
             )
           ) ==
             outcome["transaction_count"]

    mark = journal_mark()

    assert %{"data" => again, "already_applied" => true} =
             ctx.conn
             |> post("/api/v1/cash_accounts/#{ctx.source.id}/merge", body)
             |> json_response(200)

    assert again["id"] == record["id"]
    assert journal_mark() == mark
  end

  # User story:
  # As the agent whose merge was refused,
  # I want the answer to name its code and what to do,
  # so that I never retry blindly and never half-merge.
  #
  # Acceptance criteria:
  # - A pair a guard forbids answers 409 with errors.code (currency_mismatch
  #   here), errors.detail and errors.guards, on the preview and the apply,
  #   and writes nothing.
  # - A digest that no longer matches answers 409 plan_changed with
  #   errors.preview, the fresh preview, and writes nothing.
  # - A missing plan_digest answers 422 on plan_digest; a missing
  #   collapse_key_equal where pairs exist answers 422 on collapse_key_equal;
  #   a non-boolean one 422; a missing target_id 422 on target_id.
  # - An unknown source answers 404; a source already merged into another
  #   account answers 409 already_merged naming the survivor.
  test "each refusal answers its code and writes nothing", ctx do
    rows = example!(ctx)
    usd = cash!(ctx.portfolio, "Broker USD", "USD")
    mark = journal_mark()

    for request <- [
          fn ->
            get(
              ctx.conn,
              "/api/v1/cash_accounts/#{ctx.source.id}/merge_preview?target_id=#{usd.id}"
            )
          end,
          fn ->
            post(ctx.conn, "/api/v1/cash_accounts/#{ctx.source.id}/merge", %{
              target_id: usd.id,
              plan_digest: "sha256:whatever",
              collapse_key_equal: false
            })
          end
        ] do
      assert %{"errors" => errors} = request.() |> json_response(409)
      assert errors["code"] == "currency_mismatch"
      assert errors["detail"] =~ "EUR and USD"

      assert Enum.any?(
               errors["guards"],
               &(&1["code"] == "currency_mismatch" and &1["passed"] == false)
             )
    end

    preview = preview!(ctx)
    {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), rows.s_fee, %{gross_amount: "6.00"})
    mark = max(mark, journal_mark())

    assert %{"errors" => errors} =
             ctx.conn
             |> post("/api/v1/cash_accounts/#{ctx.source.id}/merge", %{
               target_id: ctx.target.id,
               plan_digest: preview["plan_digest"],
               collapse_key_equal: false
             })
             |> json_response(409)

    assert errors["code"] == "plan_changed"
    assert errors["preview"]["plan_digest"] != preview["plan_digest"]
    assert errors["preview"]["outcome_by_collapse_key_equal"]["false"]["balance"] == "1709"

    path = "/api/v1/cash_accounts/#{ctx.source.id}/merge"
    fresh = errors["preview"]["plan_digest"]

    assert %{"errors" => %{"plan_digest" => [_]}} =
             ctx.conn
             |> post(path, %{target_id: ctx.target.id, collapse_key_equal: false})
             |> json_response(422)

    assert %{"errors" => %{"collapse_key_equal" => [message]}} =
             ctx.conn
             |> post(path, %{target_id: ctx.target.id, plan_digest: fresh})
             |> json_response(422)

    assert message =~ "2 key-equal pairs"

    assert %{"errors" => %{"collapse_key_equal" => ["must be true or false"]}} =
             ctx.conn
             |> post(path, %{
               target_id: ctx.target.id,
               plan_digest: fresh,
               collapse_key_equal: "yes"
             })
             |> json_response(422)

    assert %{"errors" => %{"target_id" => ["can't be blank"]}} =
             ctx.conn
             |> get("/api/v1/cash_accounts/#{ctx.source.id}/merge_preview")
             |> json_response(422)

    assert journal_mark() == mark

    assert ctx.conn
           |> get("/api/v1/cash_accounts/999999999/merge_preview?target_id=#{ctx.target.id}")
           |> json_response(404)

    other = cash!(ctx.portfolio, "Other")

    {:ok, _record, :applied} =
      Portfolixir.Lifecycle.merge_cash_account(Actor.owner_ui(), ctx.source.id, ctx.target.id, %{
        plan_digest: fresh,
        collapse_key_equal: false
      })

    assert %{"errors" => errors} =
             ctx.conn
             |> post(path, %{target_id: other.id, plan_digest: fresh, collapse_key_equal: false})
             |> json_response(409)

    assert errors["code"] == "already_merged"
    assert errors["merged_into"] == %{"kind" => "cash_account", "id" => ctx.target.id}
  end

  # --- world ------------------------------------------------------------------

  # The worked example of the context test: source 902.50 and target 807.50,
  # a transfer between them, two key-equal interest pairs, an anchor each.
  defp example!(ctx) do
    %{
      s_deposit: book!(ctx, ctx.source, "deposit", "1000.00", ~D[2025-01-02]),
      t_deposit: book!(ctx, ctx.target, "deposit", "500.00", ~D[2025-01-03]),
      transfer: transfer!(ctx, "200.00", ~D[2025-02-01]),
      s_interest: book!(ctx, ctx.source, "interest", "12.40", ~D[2025-03-31]),
      t_interest: book!(ctx, ctx.target, "interest", "12.40", ~D[2025-03-31]),
      s_anchor: anchor!(ctx.source, "900.00", ~D[2025-04-30]),
      t_anchor: anchor!(ctx.target, "800.00", ~D[2025-05-31]),
      s_fee: book!(ctx, ctx.source, "fee", "5.00", ~D[2025-06-15]),
      s_interest_late: book!(ctx, ctx.source, "interest", "7.50", ~D[2025-07-31]),
      t_interest_late: book!(ctx, ctx.target, "interest", "7.50", ~D[2025-07-31])
    }
  end

  defp preview!(ctx) do
    ctx.conn
    |> get("/api/v1/cash_accounts/#{ctx.source.id}/merge_preview?target_id=#{ctx.target.id}")
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp cash!(portfolio, name, currency \\ "EUR") do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: currency
      })

    cash
  end

  defp book!(ctx, account, type, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: account.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp transfer!(ctx, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: ctx.source.id,
        counter_cash_account_id: ctx.target.id,
        type: "cash_transfer",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp anchor!(account, amount, date) do
    {:ok, tx} = Ledger.set_cash_balance(Actor.owner_ui(), account, %{date: date, amount: amount})
    tx
  end

  defp journal_mark do
    Portfolixir.Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0
  end
end
