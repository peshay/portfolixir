defmodule PortfolixirWeb.Api.V1.DepotMergeControllerTest do
  # ADR-0050 §7 (the depot half), §8, §10 and §12 over the API (L3b, #328;
  # risk-tier: quantity identity and idempotency, ADR-0036): the depot merge
  # preview, a read, and the apply, which takes the preview's digest and the
  # operator's choice. §16 invariant 12 (the preview's after-figures equal the
  # API reads right after the apply) and 13 (each refusal answers its code
  # and writes nothing; a stale digest answers 409 plan_changed with the
  # fresh preview) are pinned here on the wire. Every name, amount and
  # quantity is synthetic.
  use PortfolixirWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Portfolios

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer test-api-token")

    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Depot Merge API",
        base_currency_code: "EUR"
      })

    cash_t = cash!(portfolio, "Broker cash")
    cash_s = cash!(portfolio, "Broker cash 2")

    %{
      conn: conn,
      portfolio: portfolio,
      cash_t: cash_t,
      cash_s: cash_s,
      target: depot!(portfolio, cash_t, "Depot 1"),
      source: depot!(portfolio, cash_s, "Depot 2"),
      meridian: security!("Meridian Global Equity ETF", "MRDN"),
      kestrel: security!("Kestrel Industrial Group NV", "KSTL")
    }
  end

  # User story:
  # As the agent tidying up two depots at one broker,
  # I want a preview of merging one depot into the other that states every
  # affected position before and after, for either answer to the duplicate
  # question, with its computation basis and a digest I send back,
  # so that I can show the operator the consequence before anything is
  # written.
  #
  # Acceptance criteria:
  # - GET /api/v1/securities_accounts/:id/merge_preview?target_id= answers
  #   200 with plan_digest, both depots, the guards, the transfers between
  #   them, the key-equal pairs, the bucket plan per position, the former
  #   names after, and outcome_by_collapse_key_equal for "false" and "true"
  #   (positions with quantity, cost_basis, avg_cost and realized_result for
  #   source and target before and target after, rounding differences, the
  #   cash accounts a collapse changes) and positions_basis.
  # - Every quantity and financial decimal is a string.
  # - It writes nothing.
  test "the preview answers every figure, decimals as strings, and writes nothing", ctx do
    rows = example!(ctx)
    mark = journal_mark()

    assert %{"data" => preview} =
             ctx.conn
             |> get(
               "/api/v1/securities_accounts/#{ctx.source.id}/merge_preview?target_id=#{ctx.target.id}"
             )
             |> json_response(200)

    assert "sha256:" <> _ = preview["plan_digest"]
    assert preview["kind"] == "securities_account"
    assert preview["source"]["transaction_count"] == 5
    assert preview["target"]["cash_account_id"] == ctx.cash_t.id
    assert preview["choice_required"] == true
    assert Enum.all?(preview["guards"], & &1["passed"])

    assert [%{"id" => transfer_id, "quantity" => "10"}] = preview["internal_transfers"]
    assert transfer_id == rows.transfer.id
    assert length(preview["key_equal_pairs"]) == 2
    assert preview["former_names"]["after"] == ["Depot 2"]

    assert Enum.map(preview["position_buckets"], &{&1["security_id"], &1["action"]}) ==
             Enum.sort([{ctx.meridian.id, "none"}, {ctx.kestrel.id, "none"}])

    %{"false" => keep, "true" => collapse} = preview["outcome_by_collapse_key_equal"]
    meridian = Enum.find(keep["positions"], &(&1["security_id"] == ctx.meridian.id))

    assert %{"quantity" => "35", "cost_basis" => "3140", "realized_result" => "0"} =
             meridian["source"]

    assert %{"quantity" => "55", "cost_basis" => "4690", "realized_result" => "600"} =
             meridian["target"]

    assert %{"quantity" => "90", "cost_basis" => "7710", "realized_result" => "480"} =
             meridian["after"]

    kestrel = Enum.find(keep["positions"], &(&1["security_id"] == ctx.kestrel.id))
    assert kestrel["target"] == nil
    assert kestrel["after"]["quantity"] == "25"

    assert [%{"id" => cash_id, "balance_before" => "6470", "balance_after" => "6860"}] =
             collapse["cash_accounts"]

    assert cash_id == ctx.cash_t.id
    assert keep["rounding_differences"] == []
    assert preview["positions_basis"] =~ "moving-average"
    assert preview["positions_basis"] =~ "realized_result"
    assert journal_mark() == mark
  end

  # User story:
  # As the operator whose agent merged the depots I approved,
  # I want the figures the API reads right after the merge to be the ones
  # the preview promised,
  # so that what I approved is what I got.
  #
  # Acceptance criteria:
  # - POST /api/v1/securities_accounts/:id/merge with target_id,
  #   plan_digest and collapse_key_equal answers 201 with the merge record.
  # - Right after, GET /api/v1/portfolios/:id/holdings shows each affected
  #   position on the target with the preview's quantity, cost_basis and
  #   avg_cost; GET /api/v1/securities_accounts shows the target with the
  #   preview's former names, its own cash account, and no source; GET
  #   /api/v1/transactions?securities_account_id= counts the preview's
  #   bookings.
  # - A retry of the same call answers 200 with the same record and journals
  #   nothing.
  test "the apply lands on the preview's figures, and a retry answers the record", ctx do
    example!(ctx)
    preview = preview!(ctx)
    outcome = preview["outcome_by_collapse_key_equal"]["true"]

    body = %{
      target_id: ctx.target.id,
      plan_digest: preview["plan_digest"],
      collapse_key_equal: true
    }

    assert %{"data" => record, "already_applied" => false} =
             ctx.conn
             |> post("/api/v1/securities_accounts/#{ctx.source.id}/merge", body)
             |> json_response(201)

    assert record["kind"] == "securities_account"
    assert record["source_id"] == ctx.source.id
    assert record["target_id"] == ctx.target.id
    assert record["plan_digest"] == preview["plan_digest"]
    assert record["actor_type"] == "api_token_rw"
    assert record["manifest"]["choices"] == %{"collapse_key_equal" => true}

    holdings =
      ctx.conn
      |> get("/api/v1/portfolios/#{ctx.portfolio.id}/holdings")
      |> json_response(200)
      |> Map.fetch!("data")

    for %{"security_id" => security_id, "after" => after_figures} <- outcome["positions"] do
      holding =
        Enum.find(
          holdings,
          &(&1["securities_account_id"] == ctx.target.id and &1["security_id"] == security_id)
        )

      for field <- ["quantity", "cost_basis", "avg_cost"] do
        assert Decimal.equal?(Decimal.new(holding[field]), Decimal.new(after_figures[field])),
               "#{field} of security #{security_id}"
      end
    end

    refute Enum.any?(holdings, &(&1["securities_account_id"] == ctx.source.id))

    depots =
      ctx.conn |> get("/api/v1/securities_accounts") |> json_response(200) |> Map.fetch!("data")

    refute Enum.any?(depots, &(&1["id"] == ctx.source.id))
    target = Enum.find(depots, &(&1["id"] == ctx.target.id))
    assert target["former_names"] == preview["former_names"]["after"]
    assert target["cash_account_id"] == ctx.cash_t.id

    transactions =
      ctx.conn
      |> get("/api/v1/transactions?securities_account_id=#{ctx.target.id}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert length(transactions) == outcome["transaction_count"]

    mark = journal_mark()

    assert %{"data" => again, "already_applied" => true} =
             ctx.conn
             |> post("/api/v1/securities_accounts/#{ctx.source.id}/merge", body)
             |> json_response(200)

    assert again["id"] == record["id"]
    assert journal_mark() == mark
  end

  # User story:
  # As the agent whose depot merge was refused,
  # I want the answer to name its code and what to do,
  # so that I never retry blindly and never half-merge.
  #
  # Acceptance criteria:
  # - A position whose buckets differ where both depots hold it answers 409
  #   position_buckets_mismatch with errors.detail naming the position and
  #   errors.guards, on the preview and the apply, and writes nothing.
  # - A digest that no longer matches answers 409 plan_changed with
  #   errors.preview, the fresh preview, and writes nothing.
  # - A missing plan_digest answers 422 on plan_digest; a missing
  #   collapse_key_equal where pairs exist answers 422 naming how many; a
  #   non-boolean one 422; a missing target_id 422.
  # - An unknown source answers 404; a source already merged into another
  #   depot answers 409 already_merged naming the survivor.
  test "each refusal answers its code and writes nothing", ctx do
    rows = example!(ctx)
    {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})
    :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.source, ctx.meridian, [spec.id])
    mark = journal_mark()
    path = "/api/v1/securities_accounts/#{ctx.source.id}/merge"

    for request <- [
          fn ->
            get(
              ctx.conn,
              "/api/v1/securities_accounts/#{ctx.source.id}/merge_preview?target_id=#{ctx.target.id}"
            )
          end,
          fn ->
            post(ctx.conn, path, %{
              target_id: ctx.target.id,
              plan_digest: "sha256:whatever",
              collapse_key_equal: false
            })
          end
        ] do
      assert %{"errors" => errors} = request.() |> json_response(409)
      assert errors["code"] == "position_buckets_mismatch"
      assert errors["detail"] =~ "Meridian Global Equity ETF"

      assert Enum.any?(
               errors["guards"],
               &(&1["code"] == "position_buckets_mismatch" and &1["passed"] == false)
             )
    end

    assert journal_mark() == mark
    :ok = Buckets.clear_position_override(Actor.owner_ui(), ctx.source, ctx.meridian)

    preview = preview!(ctx)
    {:ok, _} = Ledger.update_transaction(Actor.owner_ui(), rows.s_buy_b, %{price: "42.00"})
    mark = journal_mark()

    assert %{"errors" => errors} =
             ctx.conn
             |> post(path, %{
               target_id: ctx.target.id,
               plan_digest: preview["plan_digest"],
               collapse_key_equal: false
             })
             |> json_response(409)

    assert errors["code"] == "plan_changed"
    assert errors["preview"]["kind"] == "securities_account"
    assert errors["preview"]["plan_digest"] != preview["plan_digest"]
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
             |> get("/api/v1/securities_accounts/#{ctx.source.id}/merge_preview")
             |> json_response(422)

    assert journal_mark() == mark

    assert ctx.conn
           |> get(
             "/api/v1/securities_accounts/999999999/merge_preview?target_id=#{ctx.target.id}"
           )
           |> json_response(404)

    other = depot!(ctx.portfolio, ctx.cash_t, "Depot 3")

    {:ok, _record, :applied} =
      Portfolixir.Lifecycle.merge_depot(Actor.owner_ui(), ctx.source.id, ctx.target.id, %{
        plan_digest: fresh,
        collapse_key_equal: false
      })

    assert %{"errors" => errors} =
             ctx.conn
             |> post(path, %{target_id: other.id, plan_digest: fresh, collapse_key_equal: false})
             |> json_response(409)

    assert errors["code"] == "already_merged"
    assert errors["merged_into"] == %{"kind" => "securities_account", "id" => ctx.target.id}
    assert errors["detail"] =~ "securities account ##{ctx.source.id} was merged into"
  end

  # --- world ------------------------------------------------------------------

  # The worked example of the context test: Meridian held by both depots
  # (the target sells between the buys), Kestrel by the source alone, a
  # transfer between them, and two key-equal pairs booked on "Broker cash".
  defp example!(ctx) do
    %{cash_t: cash_t, cash_s: cash_s, source: s, target: t, meridian: meridian} = ctx
    cash_book!(ctx, cash_t, "deposit", "10000.00", ~D[2025-01-02])
    cash_book!(ctx, cash_s, "deposit", "5000.00", ~D[2025-01-02])

    %{
      t_buy_a: row!(ctx, "buy", {t, cash_t}, meridian, {"60", "80.00"}, ~D[2025-01-10]),
      s_buy_a: row!(ctx, "buy", {s, cash_s}, meridian, {"40", "90.00"}, ~D[2025-02-10]),
      s_buy_b: row!(ctx, "buy", {s, cash_s}, ctx.kestrel, {"25", "41.20"}, ~D[2025-02-15]),
      t_sell_a: row!(ctx, "sell", {t, cash_t}, meridian, {"30", "100.00"}, ~D[2025-03-10]),
      t_buy_a2: row!(ctx, "buy", {t, cash_t}, meridian, {"10", "95.00"}, ~D[2025-04-10]),
      transfer:
        insert!(%{
          portfolio_id: ctx.portfolio.id,
          securities_account_id: s.id,
          counter_securities_account_id: t.id,
          security_id: meridian.id,
          type: "security_transfer",
          date: ~D[2025-05-10],
          quantity: "10",
          currency_code: "EUR"
        }),
      s_div: dividend!(ctx, s, meridian),
      t_div: dividend!(ctx, t, meridian),
      s_pair: row!(ctx, "buy", {s, cash_t}, meridian, {"5", "88.00"}, ~D[2025-07-01]),
      t_pair: row!(ctx, "buy", {t, cash_t}, meridian, {"5", "88.00"}, ~D[2025-07-01])
    }
  end

  defp preview!(ctx) do
    ctx.conn
    |> get(
      "/api/v1/securities_accounts/#{ctx.source.id}/merge_preview?target_id=#{ctx.target.id}"
    )
    |> json_response(200)
    |> Map.fetch!("data")
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

  defp security!(name, ticker) do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        ticker_symbol: ticker,
        currency_code: "EUR",
        asset_class: "etf"
      })

    security
  end

  defp cash_book!(ctx, cash, type, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: cash.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp row!(ctx, type, {depot, cash}, security, {quantity, price}, date) do
    insert!(%{
      portfolio_id: ctx.portfolio.id,
      securities_account_id: depot.id,
      cash_account_id: cash.id,
      security_id: security.id,
      type: type,
      date: date,
      quantity: quantity,
      price: price,
      currency_code: "EUR"
    })
  end

  defp dividend!(ctx, depot, security) do
    insert!(%{
      portfolio_id: ctx.portfolio.id,
      securities_account_id: depot.id,
      cash_account_id: ctx.cash_t.id,
      security_id: security.id,
      type: "dividend",
      date: ~D[2025-06-30],
      gross_amount: "50.00",
      currency_code: "EUR"
    })
  end

  # Written the way the Portfolio Performance importer writes a row: the
  # file names the cash account a trade settled on, which need not be the
  # depot's linked one.
  defp insert!(attrs) do
    {:ok, %{transaction: tx}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:transaction, Transaction.import_changeset(%Transaction{}, attrs))
      |> Journal.record(Actor.import_session(),
        resource_type: "transaction",
        operation: :create,
        source: :transaction
      )
      |> Portfolixir.Repo.transaction()

    tx
  end

  defp journal_mark do
    Portfolixir.Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0
  end
end
