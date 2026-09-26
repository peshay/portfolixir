defmodule Portfolixir.Lifecycle.DepotMergeTest do
  # ADR-0050 §7 (the depot half), §8, §10, §12's record write and §13, with
  # the §16 invariants of the depot merge written before the code (L3b,
  # #328; risk-tier: quantity identity and idempotency, ADR-0036): 4 (the
  # held-or-retired hash set only grows), 10's depot half (the depot
  # linearity: at every date the merged quantity per security is the fold of
  # both depots' kept rows, each split scaling the combined position once —
  # the sum before the first split, the rounding difference of a split
  # listed, never a failure), 11 (one journal entry per moved or deleted
  # row, one aggregate entry per bucket or override change, no cascade) and
  # 13 (each refusal answers its code and leaves every table unchanged; a
  # stale digest answers plan_changed and writes nothing). The re-import half
  # (1, 5, 6) is depot_merge_reimport_test.exs; the API half (12, and 13 on
  # the wire) is the controller test.
  #
  # Every name, amount and quantity is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Splits
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.SecuritiesAccount

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Depot World",
        base_currency_code: "EUR"
      })

    cash_t = cash!(portfolio, "Broker cash")
    cash_s = cash!(portfolio, "Broker cash 2")
    target = depot!(portfolio, cash_t, "Depot 1")
    source = depot!(portfolio, cash_s, "Depot 2")

    %{
      portfolio: portfolio,
      cash_t: cash_t,
      cash_s: cash_s,
      source: source,
      target: target,
      meridian: security!("Meridian Global Equity ETF", "MRDN"),
      kestrel: security!("Kestrel Industrial Group NV", "KSTL"),
      heron: security!("Heron Bond Fund", "HRNB")
    }
  end

  describe "the worked example (§7 depot steps, §8)" do
    # User story:
    # As the operator folding a second depot at one broker into the first,
    # I want the preview to show every affected position's quantity,
    # moving-average cost and realized result before and after, for either
    # answer to the duplicate question, and the merge to land on exactly
    # those figures,
    # so that I see how the combined lots restate my cost basis before I
    # confirm.
    #
    # Acceptance criteria:
    # - The preview names the transfer between the two depots, the key-equal
    #   pairs and a plan digest; positions held only by the target are not
    #   listed.
    # - Meridian: source 35 (cost 3140, realized 0) + target 55 (cost 4690,
    #   realized 600) → 90 after (cost 7710, realized 480) without collapse,
    #   85 (cost 7270) with it: the target's sale now consumes the combined
    #   average of 84.00.
    # - Kestrel, held by the source alone, moves unchanged: 25 at 1030.
    # - A collapse changes the cash account its collapsed rows booked on,
    #   before and after; without collapse no cash account changes.
    # - The apply moves every source row onto the target, deletes the
    #   transfer and the source, and the target keeps its own cash account.
    test "the preview states both outcomes, and each apply lands on its figures", ctx do
      rows = worked_example!(ctx)

      assert {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)
      assert preview.kind == :securities_account
      assert "sha256:" <> _ = preview.plan_digest
      assert Enum.all?(preview.guards, & &1.passed)
      assert preview.choice_required
      assert preview.source.transaction_count == 5
      assert preview.target.transaction_count == 7

      assert [%{id: transfer_id}] = preview.internal_transfers
      assert transfer_id == rows.transfer.id

      assert Enum.map(
               preview.key_equal_pairs,
               &{&1.source_transaction_id, &1.target_transaction_id}
             ) == [{rows.s_div.id, rows.t_div.id}, {rows.s_buy_pair.id, rows.t_buy_pair.id}]

      keep = preview.outcomes[false]
      collapse = preview.outcomes[true]

      assert Enum.map(keep.positions, & &1.security_id) ==
               Enum.sort([ctx.meridian.id, ctx.kestrel.id])

      assert figures(keep, ctx.meridian, :source) == {dec("35"), dec("3140"), dec("0")}
      assert figures(keep, ctx.meridian, :target) == {dec("55"), dec("4690"), dec("600")}
      assert figures(keep, ctx.meridian, :after) == {dec("90"), dec("7710"), dec("480")}
      assert figures(collapse, ctx.meridian, :after) == {dec("85"), dec("7270"), dec("480")}
      assert figures(keep, ctx.kestrel, :source) == {dec("25"), dec("1030"), dec("0")}
      assert position(keep, ctx.kestrel).target == nil
      assert figures(keep, ctx.kestrel, :after) == {dec("25"), dec("1030"), dec("0")}
      assert n(position(keep, ctx.meridian).after.avg_cost) == n(Decimal.div(7710, 90))
      assert keep.rounding_differences == []

      assert keep.cash_accounts == []

      assert [%{id: cash_id, balance_before: before, balance_after: after_collapse}] =
               collapse.cash_accounts

      assert cash_id == ctx.cash_t.id
      assert n(before) == dec("5970")
      assert n(after_collapse) == dec("6360")

      assert {:ok, %MergeRecord{} = record, :applied} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: false
               })

      assert record.kind == :securities_account
      assert record.source_id == ctx.source.id
      assert record.target_id == ctx.target.id
      assert record.portfolio_id == ctx.portfolio.id
      assert record.plan_digest == preview.plan_digest
      assert record.actor_label == "synthetic-agent"
      assert record.manifest["choices"] == %{"collapse_key_equal" => false}

      refute Portfolios.get_securities_account(ctx.source.id)
      assert Portfolios.get_securities_account(ctx.target.id).cash_account_id == ctx.cash_t.id
      assert Portfolios.get_cash_account(ctx.cash_s.id)
      refute Repo.get(Transaction, rows.transfer.id)

      for row <- [rows.s_buy_a, rows.s_buy_b, rows.s_div, rows.s_buy_pair] do
        moved = Repo.get!(Transaction, row.id)
        assert moved.securities_account_id == ctx.target.id
        assert moved.cash_account_id == row.cash_account_id
      end

      assert held(ctx.target, ctx.meridian) == dec("90")
      assert held(ctx.target, ctx.kestrel) == dec("25")
      assert held(ctx.target, ctx.heron) == dec("5")
    end

    test "with collapse, the key-equal source rows go and the positions are the collapse outcome",
         ctx do
      rows = worked_example!(ctx)
      {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      assert {:ok, %MergeRecord{} = record, :applied} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: true
               })

      refute Repo.get(Transaction, rows.s_div.id)
      refute Repo.get(Transaction, rows.s_buy_pair.id)
      assert Repo.get(Transaction, rows.t_div.id)
      assert Repo.get(Transaction, rows.t_buy_pair.id)
      assert held(ctx.target, ctx.meridian) == dec("85")
      assert balance(ctx.cash_t) == dec("6360")
      assert record.manifest["choices"] == %{"collapse_key_equal" => true}

      # Every figure the collapse outcome promised is what the ledger's own
      # moving-average fold reads from the stored rows.
      for %{security_id: security_id, after: after_figures} <- preview.outcomes[true].positions do
        stored = stored_figures(ctx.target.id, security_id)
        assert stored == {n(after_figures.quantity), n(after_figures.cost_basis)}
      end
    end
  end

  describe "the depot linearity (§7, §16 invariant 10)" do
    # User story:
    # As the operator merging two depots that both hold a security,
    # I want the merged depot's quantity of each security on every day to
    # be what both depots held together,
    # so that no booking is lost or counted twice by the merge.
    #
    # Acceptance criteria:
    # - At every date either depot has a row and today, the merged quantity
    #   per security equals the fold of both depots' kept rows (the
    #   transfers between them void, the collapsed rows left out).
    # - Before the first split of a security, that is the sum of both
    #   depots' quantities.
    test "at every date the merged quantity is the fold of both depots' kept rows", ctx do
      rows = worked_example!(ctx)

      for collapse? <- [false, true] do
        ctx = if collapse?, do: fresh_pair!(ctx), else: ctx
        rows = if collapse?, do: worked_example!(ctx), else: rows

        collapsed = if collapse?, do: [rows.s_div.id, rows.s_buy_pair.id], else: []
        oracle = daily_sums(ctx, collapsed)
        merge!(ctx, collapse?)

        assert merged_quantities(ctx, Map.keys(oracle)) == oracle
      end
    end

    # User story:
    # As the operator whose merged-away depot exchanged shares with a third
    # depot,
    # I want those transfers kept, now between the survivor and the third
    # depot, on whichever leg the merged-away depot stood,
    # so that the third depot's history is untouched.
    #
    # Acceptance criteria:
    # - A transfer from a third depot into the source, and one from the
    #   source to the third depot, name the target afterwards on that leg.
    # - The third depot's quantity is unchanged; the target holds what the
    #   source held.
    test "a transfer with a third depot is re-pointed on either leg", ctx do
      third = depot!(ctx.portfolio, ctx.cash_t, "Depot 3")
      buy!(ctx, third, ctx.cash_t, ctx.heron, "10", "100.00", ~D[2025-01-05])
      inbound = transfer!(ctx, third, ctx.source, ctx.heron, "4", ~D[2025-02-01], nil)
      outbound = transfer!(ctx, ctx.source, third, ctx.heron, "1", ~D[2025-03-01], nil)

      merge!(ctx, false)

      assert Repo.get!(Transaction, inbound.id).counter_securities_account_id == ctx.target.id
      assert Repo.get!(Transaction, inbound.id).securities_account_id == third.id
      assert Repo.get!(Transaction, outbound.id).securities_account_id == ctx.target.id
      assert Repo.get!(Transaction, outbound.id).counter_securities_account_id == third.id
      assert held(ctx.target, ctx.heron) == dec("3")
      assert held(third, ctx.heron) == dec("7")
    end

    # User story:
    # As the operator whose old and new depot each received the same
    # transfer from a third depot,
    # I want the preview to name that third depot and how its holding
    # changes when I remove the duplicate,
    # so that a collapse never changes a depot I was not shown.
    #
    # Acceptance criteria:
    # - The key-equal pair names both depot legs of the transfer.
    # - The collapse outcome lists the third depot, the security and its
    #   quantity before (2) and after (6); without collapse no third depot
    #   changes.
    # - After the apply with collapse, the third depot holds what the
    #   preview said.
    test "a collapsed transfer with a third depot names that depot and its change", ctx do
      third = depot!(ctx.portfolio, ctx.cash_t, "Depot 3")
      buy!(ctx, third, ctx.cash_t, ctx.heron, "10", "100.00", ~D[2025-01-05])
      transfer!(ctx, third, ctx.source, ctx.heron, "4", ~D[2025-02-01], nil)
      transfer!(ctx, third, ctx.target, ctx.heron, "4", ~D[2025-02-01], nil)

      {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      assert [pair] = preview.key_equal_pairs
      assert pair.securities_account_id == third.id
      assert pair.counter_securities_account_id == ctx.source.id

      assert preview.outcomes[false].other_depots == []

      assert [
               %{
                 securities_account_id: third_id,
                 securities_account_name: "Depot 3",
                 security_id: heron_id,
                 quantity_before: before,
                 quantity_after: after_collapse
               }
             ] = preview.outcomes[true].other_depots

      assert third_id == third.id
      assert heron_id == ctx.heron.id
      assert n(before) == dec("2")
      assert n(after_collapse) == dec("6")

      merge!(ctx, true, preview)

      assert held(third, ctx.heron) == dec("6")
      assert held(ctx.target, ctx.heron) == dec("4")
    end

    # User story:
    # As the operator whose two depots both held a security through a
    # reverse split,
    # I want the merge to scale the combined position once, as the ledger
    # would have if it had always been one depot, and to show me where that
    # differs from the two positions rounded apart,
    # so that a difference of one unit of the volume scale is explained,
    # not a surprise and not a refused merge.
    #
    # Acceptance criteria:
    # - One share in each depot and a 1:3 split: apart, each rounds to
    #   0.333333 (0.666666 together); combined, 2 → 0.666667.
    # - The preview lists the security, the split date and both figures
    #   with their difference of 0.000001; the merge applies, and the
    #   target holds 0.666667 afterwards.
    # - Before the split, the merged quantity is the sum of both.
    test "a split scales the combined position once; the rounding difference is listed", ctx do
      buy!(ctx, ctx.target, ctx.cash_t, ctx.heron, "1", "10.00", ~D[2025-01-10])
      buy!(ctx, ctx.source, ctx.cash_s, ctx.heron, "1", "10.00", ~D[2025-01-12])

      {:ok, [split]} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: ctx.heron.id,
          date: ~D[2025-03-01],
          ratio_numerator: 1,
          ratio_denominator: 3
        })

      assert held(ctx.target, ctx.heron) == dec("0.333333")
      assert held(ctx.source, ctx.heron) == dec("0.333333")

      {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      assert [difference] = preview.outcomes[false].rounding_differences
      assert difference.security_id == ctx.heron.id
      assert difference.date == ~D[2025-03-01]
      assert difference.split_transaction_id == split.id
      assert n(difference.combined) == dec("0.666667")
      assert n(difference.separate_sum) == dec("0.666666")
      assert n(difference.difference) == dec("0.000001")
      assert figures(preview.outcomes[false], ctx.heron, :after) |> elem(0) == dec("0.666667")

      oracle = daily_sums(ctx, [])
      merge!(ctx, false, preview)

      assert held(ctx.target, ctx.heron) == dec("0.666667")

      before_split =
        Map.filter(oracle, fn {{date, _security}, _quantity} ->
          Date.compare(date, ~D[2025-03-01]) == :lt
        end)

      merged = merged_quantities(ctx, Map.keys(oracle))
      assert Map.take(merged, Map.keys(before_split)) == before_split
      assert merged[{~D[2025-03-01], ctx.heron.id}] == dec("0.666667")
    end

    # User story:
    # As the operator whose depots both kept booking a security after its
    # reverse split,
    # I want the merge's own check to hold the merged depot to the sum of
    # both depots' bookings on every day after the split too, in exact
    # arithmetic,
    # so that a booking lost or doubled after a split can never commit.
    #
    # Acceptance criteria:
    # - One share in each depot, a 1:3 split, then a buy of 0.5 on the
    #   source and a sale of 0.1 on the target: the merge applies (the
    #   rounding of the combined position is not a failure) and the target
    #   holds 0.666667 + 0.5 - 0.1 = 1.066667.
    test "after a split, bookings on either side merge and the target holds the fold", ctx do
      buy!(ctx, ctx.target, ctx.cash_t, ctx.heron, "1", "10.00", ~D[2025-01-10])
      buy!(ctx, ctx.source, ctx.cash_s, ctx.heron, "1", "10.00", ~D[2025-01-12])

      {:ok, _split} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: ctx.heron.id,
          date: ~D[2025-03-01],
          ratio_numerator: 1,
          ratio_denominator: 3
        })

      buy!(ctx, ctx.source, ctx.cash_s, ctx.heron, "0.5", "30.00", ~D[2025-04-01])

      trade!(
        ctx,
        "sell",
        {ctx.target, ctx.cash_t},
        ctx.heron,
        {"0.1", "31.00"},
        ~D[2025-05-01],
        nil
      )

      oracle = daily_sums(ctx, [])
      merge!(ctx, false)

      assert held(ctx.target, ctx.heron) == dec("1.066667")
      assert merged_quantities(ctx, Map.keys(oracle)) == oracle
    end

    # User story:
    # As the operator whose history spans both depots,
    # I want a merge without collapse to leave every day's external flow
    # and the total value unchanged,
    # so that a merge never rewrites my returns behind my back.
    #
    # Acceptance criteria:
    # - Without collapse, the performance walk's flow and value are equal on
    #   every day before and after the merge.
    test "without collapse, flows per day and total value are unchanged", ctx do
      worked_example!(ctx)
      before = walk(ctx)
      merge!(ctx, false)
      assert walk(ctx) == before
    end

    # User story:
    # As the operator collapsing bookings both depots settled on one cash
    # account,
    # I want the preview to say when a later set balance of that cash
    # account absorbs a removed booking,
    # so that a collapse never moves a flow in my returns I was not shown.
    #
    # Acceptance criteria:
    # - Without collapse nothing moves; the collapse outcome lists, per
    #   collapsed row before the cash account's next anchor, the account, the
    #   anchor, its date and the row's cash leg.
    # - After the apply, the performance walk's flows differ from before by
    #   exactly the listed changes.
    test "a collapsed booking before a later anchor of its cash account is a listed flow", ctx do
      rows = worked_example!(ctx)

      {:ok, anchor} =
        Ledger.set_cash_balance(agent(), ctx.cash_t, %{date: ~D[2025-08-01], amount: "6000.00"})

      before = walk(ctx)
      {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      assert preview.outcomes[false].flow_changes == []
      changes = preview.outcomes[true].flow_changes

      assert Enum.sort(
               Enum.map(
                 changes,
                 &{&1.kind, &1.cash_account_id, &1.transaction_id, &1.date, n(&1.change),
                  &1.collapsed_transaction_id}
               )
             ) ==
               Enum.sort([
                 {:absorbed, ctx.cash_t.id, anchor.id, ~D[2025-08-01], dec("50.00"),
                  rows.s_div.id},
                 {:absorbed, ctx.cash_t.id, anchor.id, ~D[2025-08-01], dec("-440"),
                  rows.s_buy_pair.id}
               ])

      merge!(ctx, true, preview)

      expected =
        Enum.reduce(changes, flows(before), fn %{date: date, change: change}, acc ->
          Map.update!(acc, date, &n(Decimal.add(&1, change)))
        end)

      assert flows(walk(ctx)) == expected
    end
  end

  describe "view membership (§7 depot guards, the membership rule)" do
    # User story:
    # As the operator whose depots sit in the same views,
    # I want each position's view membership to stay what it was,
    # so that a merge never moves history between views behind my back.
    #
    # Acceptance criteria:
    # - The source's override on a security the target does not hold moves
    #   onto the target: its effective buckets afterwards are the source's.
    # - The source's override on a security the target holds, equal to the
    #   target's effective set, is dropped as redundant.
    # - A dead override of the target on a security only the source holds,
    #   while the source's position inherits the default, is cleared so the
    #   moved rows keep the default.
    # - The preview states each position's plan.
    test "an override is carried, dropped or cleared so every position keeps its set", ctx do
      worked_example!(ctx)
      {:ok, long} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Long term"})
      {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), ctx.source, [long.id])
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), ctx.target, [long.id])

      # Kestrel: only the source holds it, under an override → carried.
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.source, ctx.kestrel, [spec.id])
      # Meridian: both hold it; the source's override equals the default → dropped.
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.source, ctx.meridian, [long.id])
      # A fourth security only the source holds, inheriting, while the target
      # carries a dead override for it → the target's override is cleared.
      lark = security!("Lark Small Cap", "LARK")
      buy!(ctx, ctx.source, ctx.cash_s, lark, "3", "20.00", ~D[2025-02-20])
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.target, lark, [spec.id])

      {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      assert plan_of(preview, ctx.kestrel) == :carry
      assert plan_of(preview, ctx.meridian) == :drop_redundant
      assert plan_of(preview, lark) == :clear_target

      merge!(ctx, false, preview)

      assert Buckets.effective_position_buckets(ctx.target.id, ctx.kestrel.id) == [spec.id]
      assert Buckets.effective_position_buckets(ctx.target.id, ctx.meridian.id) == [long.id]
      assert Buckets.effective_position_buckets(ctx.target.id, lark.id) == [long.id]
      assert Buckets.position_override(ctx.target.id, lark.id) == :inherit
      assert Buckets.position_override(ctx.target.id, ctx.meridian.id) == :inherit
    end
  end

  describe "an override the target cannot take (§7 depot guards, ADR-0024)" do
    # User story:
    # As the operator whose source depot carries an override stored before
    # a position could hold only one scope bucket,
    # I want the preview to refuse the merge naming that position,
    # so that the merge never fails half-way on a write the bucket rules
    # refuse, and never answers a changed plan it cannot resolve.
    #
    # Acceptance criteria:
    # - The source's override on a security the target does not hold, with
    #   two scope-dimension buckets, refuses as position_buckets_mismatch
    #   naming the position and the rule, and writes nothing.
    test "a carried override with two scope buckets is refused up front", ctx do
      worked_example!(ctx)
      {:ok, one} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Scope A", dimension: "scope"})
      {:ok, two} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Scope B", dimension: "scope"})

      # Stored the way an override was written before the one-scope rule.
      Repo.insert_all("position_bucket_overrides", [
        %{securities_account_id: ctx.source.id, security_id: ctx.kestrel.id, bucket_id: one.id},
        %{securities_account_id: ctx.source.id, security_id: ctx.kestrel.id, bucket_id: two.id}
      ])

      before = fingerprint()

      assert {:error, {:refused, guards}} =
               Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      assert %{code: :position_buckets_mismatch, detail: detail} =
               Enum.find(guards, &(not &1.passed))

      assert detail =~ "Kestrel Industrial Group NV"
      assert detail =~ "scope"
      assert fingerprint() == before
    end
  end

  describe "journal, buckets and names (§7, §13, §16 invariant 11)" do
    # User story:
    # As the maintainer auditing a depot merge,
    # I want every row it moved or deleted journaled exactly once, each
    # bucket or override change as its one aggregate entry, and nothing
    # removed by a cascade,
    # so that the journal and the merge record reconstruct what happened.
    #
    # Acceptance criteria:
    # - Each moved or deleted transaction has exactly one journal entry under
    #   the merge's actor; unchanged rows have none.
    # - The carried override is one position_bucket_override update on the
    #   target and one delete on the source; the redundant one is one delete;
    #   the source's default set one depot_bucket_assignment entry; the
    #   source one securities_account delete; the target one update carrying
    #   the former names; the record one merge_record create — nothing else.
    # - No row disappears that the manifest does not list.
    test "one entry per touched row, one per aggregate, nothing else", ctx do
      rows = worked_example!(ctx)
      {:ok, long} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Long term"})
      {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), ctx.source, [long.id])
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), ctx.target, [long.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.source, ctx.kestrel, [spec.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.source, ctx.meridian, [long.id])
      untouched = buy!(ctx, ctx.target, ctx.cash_t, ctx.heron, "1", "100.00", ~D[2025-12-01])
      count_before = Repo.aggregate(Transaction, :count)
      mark = journal_mark()

      record = merge!(ctx, true)
      entries = entries_since(mark)

      transaction_ids =
        Enum.map(Enum.filter(entries, &(&1.resource_type == "transaction")), & &1.resource_id)

      assert Enum.frequencies(transaction_ids) |> Map.values() |> Enum.uniq() == [1]
      refute to_string(untouched.id) in transaction_ids

      deleted = Enum.map(record.manifest["transactions"]["deleted"], & &1["id"])

      assert Enum.sort(deleted) ==
               Enum.sort([rows.transfer.id, rows.s_div.id, rows.s_buy_pair.id])

      moved = Enum.map(record.manifest["transactions"]["moved"], & &1["id"])
      assert Enum.sort(moved) == Enum.sort([rows.s_buy_a.id, rows.s_buy_b.id])
      assert Enum.sort(transaction_ids) == Enum.sort(Enum.map(deleted ++ moved, &to_string/1))

      assert Repo.aggregate(Transaction, :count) == count_before - length(deleted)
      assert Enum.all?(entries, &(&1.actor_label == "synthetic-agent"))

      by_type = Enum.frequencies_by(entries, &{&1.resource_type, &1.operation})

      assert Map.drop(by_type, [{"transaction", :update}, {"transaction", :delete}]) == %{
               {"position_bucket_override", :update} => 1,
               {"position_bucket_override", :delete} => 2,
               {"depot_bucket_assignment", :update} => 1,
               {"securities_account", :delete} => 1,
               {"securities_account", :update} => 1,
               {"merge_record", :create} => 1
             }

      assert record.manifest["position_bucket_overrides"]["carried"] == [
               %{"security_id" => ctx.kestrel.id, "bucket_ids" => [spec.id]}
             ]

      assert record.manifest["position_bucket_overrides"]["dropped"] == [
               %{"security_id" => ctx.meridian.id, "reason" => "redundant"}
             ]

      assert record.manifest["securities_account_buckets"]["removed"] == [long.id]
    end

    # User story (#851, ADR-0039, §13 of ADR-0050):
    # As the operator reading a memoised walk right after a merge,
    # I want the merge's writes to bump the derived basis of what each moved
    # row affected,
    # so that no figure computed before the merge is served after it.
    #
    # Acceptance criteria:
    # - The portfolio's data version is higher after the merge.
    test "the merge bumps the portfolio's derived basis", ctx do
      worked_example!(ctx)
      basis = DataVersion.portfolio_basis(ctx.portfolio.id)
      before = DataVersion.current(basis)

      merge!(ctx, false)

      assert DataVersion.current(basis) > before
    end

    # User story:
    # As the operator whose next Portfolio Performance import still names
    # the merged-away depot,
    # I want its name and its former names to become former names of the
    # surviving depot,
    # so that the import books onto the survivor.
    #
    # Acceptance criteria:
    # - The target's former names gain the source's name and former names,
    #   in that order, after its own.
    test "the source's names become former names of the target", ctx do
      {:ok, source} =
        Portfolios.update_securities_account(agent(), ctx.source, %{name: "Depot 2 (older)"})

      {:ok, source} = Portfolios.update_securities_account(agent(), source, %{name: "Depot 2"})
      assert source.former_names == ["Depot 2 (older)"]
      buy!(ctx, source, ctx.cash_s, ctx.kestrel, "1", "40.00", ~D[2025-01-02])

      {:ok, preview} = Lifecycle.preview_depot_merge(source.id, ctx.target.id)
      assert preview.former_names.after == ["Depot 2", "Depot 2 (older)"]
      merge!(%{ctx | source: source}, false, preview)

      assert Portfolios.get_securities_account(ctx.target.id).former_names ==
               ["Depot 2", "Depot 2 (older)"]
    end
  end

  describe "hashes and the merge record (§3, §12, §16 invariant 4)" do
    # User story:
    # As the operator who merged a depot whose history came from an import,
    # I want every hash a removed row carried retired under the merge record,
    # so that no writer can book that row again and the set of known hashes
    # only grows.
    #
    # Acceptance criteria:
    # - After the merge, every hash held or retired before is still held or
    #   retired.
    # - The transfer between the two depots is retired as internal_transfer;
    #   each collapsed row as collapsed_duplicate, superseded by its paired
    #   target row.
    test "every removed row's hash is retired", ctx do
      rows = worked_example!(ctx, hashed: true)
      held_before = held_or_retired()

      record = merge!(ctx, true)
      Repo.query!("SET CONSTRAINTS ALL IMMEDIATE")

      assert MapSet.subset?(held_before, held_or_retired())

      retired = Repo.all(from(r in RetiredImportHash, where: r.merge_record_id == ^record.id))

      assert Enum.sort(
               Enum.map(
                 retired,
                 &{&1.former_transaction_id, &1.reason, &1.superseded_by_transaction_id}
               )
             ) ==
               Enum.sort([
                 {rows.transfer.id, :internal_transfer, nil},
                 {rows.s_div.id, :collapsed_duplicate, rows.t_div.id},
                 {rows.s_buy_pair.id, :collapsed_duplicate, rows.t_buy_pair.id}
               ])
    end

    # User story:
    # As the agent whose merge call timed out,
    # I want a retry of the same pair to answer the merge that happened, and
    # a merge of the same source into another depot to be refused,
    # so that a retry never merges twice.
    #
    # Acceptance criteria:
    # - A retry of a completed merge of the same pair answers the original
    #   record and journals nothing.
    # - A merge or preview of an already merged source into another depot
    #   answers already_merged with the record and writes nothing.
    test "a retry answers the original record; another target is already_merged", ctx do
      worked_example!(ctx)
      record = merge!(ctx, false)
      other = depot!(ctx.portfolio, ctx.cash_t, "Depot 3")
      mark = journal_mark()

      assert {:ok, %MergeRecord{id: id}, :already_applied} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: record.plan_digest,
                 collapse_key_equal: false
               })

      assert id == record.id
      before = fingerprint()

      assert {:error, {:already_merged, %MergeRecord{id: ^id}}} =
               Lifecycle.merge_depot(agent(), ctx.source.id, other.id, %{
                 plan_digest: record.plan_digest,
                 collapse_key_equal: false
               })

      assert {:error, {:already_merged, %MergeRecord{id: ^id}}} =
               Lifecycle.preview_depot_merge(ctx.source.id, other.id)

      assert entries_since(mark) == []
      assert fingerprint() == before
    end
  end

  describe "refusals and consent (§7 depot guards, §8, §10, §16 invariant 13)" do
    # User story:
    # As the operator about to merge the wrong pair of depots,
    # I want every merge the guards forbid refused with a named reason before
    # anything is written,
    # so that a depot of another portfolio, other default buckets, a
    # position whose view membership would change, the depot itself or a
    # vanished one can never be merged.
    #
    # Acceptance criteria:
    # - Each guard answers {:refused, guards} naming its code, on the preview
    #   and on the apply, and every table is unchanged.
    # - The position guard names each position whose effective buckets
    #   differ where the target holds rows of it.
    test "each guard refuses with its code and writes nothing", ctx do
      worked_example!(ctx)
      {:ok, long} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Long term"})
      {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})

      tagged = depot!(ctx.portfolio, ctx.cash_t, "Tagged depot")
      :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), tagged, [long.id])

      {:ok, elsewhere} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{
          name: "Elsewhere",
          base_currency_code: "EUR"
        })

      foreign = depot!(elsewhere, cash!(elsewhere, "Abroad cash"), "Depot abroad")
      gone = depot!(ctx.portfolio, ctx.cash_t, "Gone")
      {:ok, _} = Portfolios.delete_securities_account(Actor.owner_ui(), gone)

      cases = [
        {ctx.source.id, :same_account},
        {tagged.id, :buckets_mismatch},
        {foreign.id, :portfolio_mismatch},
        {gone.id, :not_live}
      ]

      before = fingerprint()

      for {target_id, code} <- cases do
        assert {:error, {:refused, guards}} =
                 Lifecycle.preview_depot_merge(ctx.source.id, target_id)

        assert code in failed(guards), "preview #{code}: #{inspect(guards)}"

        assert {:error, {:refused, guards}} =
                 Lifecycle.merge_depot(agent(), ctx.source.id, target_id, %{
                   plan_digest: "sha256:whatever",
                   collapse_key_equal: false
                 })

        assert code in failed(guards), "apply #{code}: #{inspect(guards)}"
        assert fingerprint() == before
      end

      # Both hold Meridian, and the source's position sits in another bucket.
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.source, ctx.meridian, [spec.id])
      before = fingerprint()

      assert {:error, {:refused, guards}} =
               Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      assert %{code: :position_buckets_mismatch, detail: detail} =
               Enum.find(guards, &(not &1.passed))

      assert detail =~ "Meridian Global Equity ETF"
      refute detail =~ "Kestrel"

      # L5a: the refusal names its positions as data too, so a page can say
      # it in the operator's language (board 02, "Abgelehnt · Depot").
      assert %{positions: [position]} = Enum.find(guards, &(not &1.passed))

      assert position == %{
               security_id: ctx.meridian.id,
               security_name: "Meridian Global Equity ETF",
               source_buckets: [spec.id],
               target_buckets: [],
               action: :refuse
             }

      assert {:error, {:refused, _guards}} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: "sha256:whatever",
                 collapse_key_equal: false
               })

      assert fingerprint() == before
      assert {:error, :not_found} = Lifecycle.preview_depot_merge(gone.id, ctx.target.id)
    end

    # User story:
    # As the operator who approved a preview an hour ago,
    # I want the merge refused when a booking of either depot changed
    # since, with the fresh preview,
    # so that the figures applied are always the ones I approved.
    #
    # Acceptance criteria:
    # - An apply whose digest no longer matches answers {:plan_changed,
    #   fresh_preview} and writes nothing; the fresh digest applies.
    # - Without a digest the apply answers {:invalid, :plan_digest, _}; with
    #   key-equal pairs and no collapse_key_equal it answers
    #   {:choice_required, :collapse_key_equal, 2}; neither writes anything.
    test "a stale digest answers plan_changed with the fresh preview, and writes nothing", ctx do
      rows = worked_example!(ctx)
      {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

      {:ok, _} = Ledger.update_transaction(agent(), rows.s_buy_b, %{price: "42.00"})
      before = fingerprint()

      assert {:error, {:plan_changed, fresh}} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: false
               })

      assert fresh.plan_digest != preview.plan_digest

      assert figures(fresh.outcomes[false], ctx.kestrel, :after) ==
               {dec("25"), dec("1050"), dec("0")}

      assert fingerprint() == before

      assert {:error, {:invalid, :plan_digest, _}} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 collapse_key_equal: false
               })

      assert {:error, {:choice_required, :collapse_key_equal, 2}} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: fresh.plan_digest
               })

      assert fingerprint() == before

      assert {:ok, _record, :applied} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: fresh.plan_digest,
                 collapse_key_equal: false
               })
    end

    test "without key-equal pairs, no choice is required", ctx do
      buy!(ctx, ctx.source, ctx.cash_s, ctx.kestrel, "2", "40.00", ~D[2025-01-02])
      buy!(ctx, ctx.target, ctx.cash_t, ctx.kestrel, "3", "40.00", ~D[2025-01-02])

      {:ok, preview} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)
      refute preview.choice_required
      assert preview.outcomes[false] == preview.outcomes[true]

      assert {:ok, _record, :applied} =
               Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest
               })

      assert held(ctx.target, ctx.kestrel) == dec("5")
    end

    # User story:
    # As the maintainer of the digest,
    # I want one pair to have one digest whatever the operator will choose,
    # and any change of a row or an override to change it,
    # so that consent covers exactly what the preview showed.
    #
    # Acceptance criteria:
    # - Two previews of an unchanged pair carry the same digest.
    # - A new booking on either side changes it; so does a new split of a
    #   security either depot holds.
    test "the digest is stable for one pair and moves with its rows", ctx do
      worked_example!(ctx)
      {:ok, first} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)
      {:ok, again} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)
      assert first.plan_digest == again.plan_digest

      buy!(ctx, ctx.target, ctx.cash_t, ctx.heron, "1", "100.00", ~D[2026-02-01])
      {:ok, changed} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)
      refute changed.plan_digest == first.plan_digest

      {:ok, _} =
        Splits.book_split(Actor.owner_ui(), %{
          security_id: ctx.kestrel.id,
          date: ~D[2025-09-01],
          ratio_numerator: 2,
          ratio_denominator: 1
        })

      {:ok, split} = Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)
      refute split.plan_digest == changed.plan_digest
    end
  end

  # --- the worked example ------------------------------------------------------

  # Depot 2 (the source, cash "Broker cash 2") into Depot 1 (the target, cash
  # "Broker cash"):
  #
  #   Meridian  target: buy 60 @ 80, sell 30 @ 100, buy 10 @ 95
  #             source: buy 40 @ 90, then 10 transferred to the target
  #   Kestrel   source: buy 25 @ 41.20
  #   Heron     target: buy 5 @ 100 (not affected)
  #   pairs     a dividend of 50.00 on Meridian and a buy of 5 @ 88, both
  #             booked on "Broker cash" once from each depot
  defp worked_example!(ctx, opts \\ []) do
    hashed? = Keyword.get(opts, :hashed, false)
    hash = fn label -> if hashed?, do: "synthetic-depot-hash-#{ctx.source.id}-#{label}" end
    %{cash_t: cash_t, cash_s: cash_s, source: s, target: t, meridian: meridian} = ctx

    cash_book!(ctx, cash_t, "deposit", "10000.00", ~D[2025-01-02])
    cash_book!(ctx, cash_s, "deposit", "5000.00", ~D[2025-01-02])

    %{
      t_buy_a: buy!(ctx, t, cash_t, meridian, "60", "80.00", ~D[2025-01-10], hash.("t-buy-a")),
      s_buy_a: buy!(ctx, s, cash_s, meridian, "40", "90.00", ~D[2025-02-10], hash.("s-buy-a")),
      s_buy_b: buy!(ctx, s, cash_s, ctx.kestrel, "25", "41.20", ~D[2025-02-15], hash.("s-buy-b")),
      t_sell_a:
        trade!(
          ctx,
          "sell",
          {t, cash_t},
          meridian,
          {"30", "100.00"},
          ~D[2025-03-10],
          hash.("t-sell")
        ),
      t_buy_c: buy!(ctx, t, cash_t, ctx.heron, "5", "100.00", ~D[2025-03-20], hash.("t-buy-c")),
      t_buy_a2: buy!(ctx, t, cash_t, meridian, "10", "95.00", ~D[2025-04-10], hash.("t-buy-a2")),
      transfer: transfer!(ctx, s, t, meridian, "10", ~D[2025-05-10], hash.("transfer")),
      s_div: dividend!(ctx, s, cash_t, meridian, "50.00", ~D[2025-06-30], hash.("s-div")),
      t_div: dividend!(ctx, t, cash_t, meridian, "50.00", ~D[2025-06-30], hash.("t-div")),
      s_buy_pair: buy!(ctx, s, cash_t, meridian, "5", "88.00", ~D[2025-07-01], hash.("s-pair")),
      t_buy_pair: buy!(ctx, t, cash_t, meridian, "5", "88.00", ~D[2025-07-01], hash.("t-pair"))
    }
  end

  # A second pair of depots in the same portfolio, for a test that merges
  # twice.
  defp fresh_pair!(ctx) do
    cash_t = cash!(ctx.portfolio, "Broker cash #{System.unique_integer([:positive])}")
    cash_s = cash!(ctx.portfolio, "Broker cash #{System.unique_integer([:positive])}")

    %{
      ctx
      | cash_t: cash_t,
        cash_s: cash_s,
        target: depot!(ctx.portfolio, cash_t, "Depot #{System.unique_integer([:positive])}"),
        source: depot!(ctx.portfolio, cash_s, "Depot #{System.unique_integer([:positive])}")
    }
  end

  # --- world ------------------------------------------------------------------

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
      Ledger.create_transaction(agent(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: cash.id,
        type: type,
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      })

    tx
  end

  defp buy!(ctx, depot, cash, security, quantity, price, date, hash \\ nil),
    do: trade!(ctx, "buy", {depot, cash}, security, {quantity, price}, date, hash)

  defp trade!(ctx, type, {depot, cash}, security, {quantity, price}, date, hash) do
    attrs = %{
      portfolio_id: ctx.portfolio.id,
      securities_account_id: depot.id,
      cash_account_id: cash.id,
      security_id: security.id,
      type: type,
      date: date,
      quantity: quantity,
      price: price,
      currency_code: "EUR"
    }

    create!(attrs, hash)
  end

  defp transfer!(ctx, from, to, security, quantity, date, hash) do
    create!(
      %{
        portfolio_id: ctx.portfolio.id,
        securities_account_id: from.id,
        counter_securities_account_id: to.id,
        security_id: security.id,
        type: "security_transfer",
        date: date,
        quantity: quantity,
        currency_code: "EUR"
      },
      hash
    )
  end

  defp dividend!(ctx, depot, cash, security, amount, date, hash) do
    create!(
      %{
        portfolio_id: ctx.portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "dividend",
        date: date,
        gross_amount: amount,
        currency_code: "EUR"
      },
      hash
    )
  end

  # Written the way the Portfolio Performance importer writes a row
  # (`Imports.Applier`): the file names the cash account a trade settled on,
  # which need not be the depot's linked one — a rename zombie's bookings
  # settle on the survivor's cash account.
  defp create!(attrs, hash) do
    changeset = Transaction.import_changeset(%Transaction{}, Map.put(attrs, :import_hash, hash))

    {:ok, %{transaction: tx}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:transaction, changeset)
      |> Journal.record(Actor.import_session(),
        resource_type: "transaction",
        operation: :create,
        source: :transaction
      )
      |> Repo.transaction()

    tx
  end

  defp merge!(ctx, collapse?, preview \\ nil) do
    {:ok, preview} =
      if preview,
        do: {:ok, preview},
        else: Lifecycle.preview_depot_merge(ctx.source.id, ctx.target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_depot(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: collapse?
      })

    record
  end

  # --- oracles ----------------------------------------------------------------

  # `{date, security_id} => quantity`: at the end of every date either depot
  # has a row on, every split date and today, the fold of both depots' rows
  # before the merge — the transfers between them void, the collapsed rows
  # left out — as one depot, from the ledger's own position fold.
  defp daily_sums(ctx, collapsed_ids) do
    ids = [ctx.source.id, ctx.target.id]

    rows =
      Repo.all(
        from(t in Transaction,
          where: t.securities_account_id in ^ids or t.counter_securities_account_id in ^ids
        )
      )

    securities = rows |> Enum.map(& &1.security_id) |> Enum.uniq()

    splits =
      Repo.all(
        from(t in Transaction,
          where:
            t.type == "split" and t.portfolio_id == ^ctx.portfolio.id and
              t.security_id in ^securities
        )
      )

    kept =
      rows
      |> Enum.reject(&(&1.id in collapsed_ids))
      |> Enum.reject(&internal_transfer?(&1, ctx))
      |> Enum.map(&relabel(&1, ctx))

    dates = Enum.uniq([Portfolixir.Clock.today() | Enum.map(rows ++ splits, & &1.date)])

    for date <- dates, security <- securities, into: %{} do
      positions =
        (kept ++ splits)
        |> Enum.filter(&(Date.compare(&1.date, date) != :gt))
        |> Positions.calculate()

      {{date, security}, n(Map.get(positions, {ctx.target.id, security}, dec("0")))}
    end
  end

  defp internal_transfer?(%{type: "security_transfer"} = row, ctx),
    do:
      Enum.sort([row.securities_account_id, row.counter_securities_account_id]) ==
        Enum.sort([ctx.source.id, ctx.target.id])

  defp internal_transfer?(_row, _ctx), do: false

  defp relabel(row, ctx) do
    swap = fn
      id when id == ctx.source.id -> ctx.target.id
      id -> id
    end

    %{
      row
      | securities_account_id: swap.(row.securities_account_id),
        counter_securities_account_id: swap.(row.counter_securities_account_id)
    }
  end

  defp merged_quantities(ctx, keys) do
    rows = Repo.all(from(t in Transaction, where: t.portfolio_id == ^ctx.portfolio.id))

    Map.new(keys, fn {date, security} = key ->
      positions =
        rows |> Enum.filter(&(Date.compare(&1.date, date) != :gt)) |> Positions.calculate()

      {key, n(Map.get(positions, {ctx.target.id, security}, dec("0")))}
    end)
  end

  defp held(depot, security) do
    Ledger.positions_for_portfolio(depot.portfolio_id)
    |> Map.get({depot.id, security.id}, dec("0"))
    |> n()
  end

  defp stored_figures(depot_id, security_id) do
    depot = Repo.get!(SecuritiesAccount, depot_id)

    row =
      depot.portfolio_id
      |> Ledger.holdings_for_portfolio(prices: %{})
      |> Enum.find(&(&1.securities_account_id == depot_id and &1.security_id == security_id))

    {n(row.quantity), n(row.cost_basis)}
  end

  defp balance(account) do
    Map.get(Ledger.cash_balances(), account.id, dec("0")) |> Decimal.normalize()
  end

  defp walk(ctx) do
    ctx.portfolio.id
    |> Performance.analysis()
    |> Map.fetch!(:daily)
    |> Map.new(&{&1.date, {Decimal.normalize(&1.flow), Decimal.normalize(&1.value)}})
  end

  defp flows(walk), do: Map.new(walk, fn {date, {flow, _value}} -> {date, flow} end)

  defp position(outcome, security),
    do: Enum.find(outcome.positions, &(&1.security_id == security.id))

  defp figures(outcome, security, side) do
    %{quantity: quantity, cost_basis: cost, realized_result: realized} =
      Map.fetch!(position(outcome, security), side)

    {n(quantity), n(cost), n(realized)}
  end

  defp plan_of(preview, security) do
    %{action: action} = Enum.find(preview.position_buckets, &(&1.security_id == security.id))
    action
  end

  defp held_or_retired do
    live =
      Repo.all(from(t in Transaction, where: not is_nil(t.import_hash), select: t.import_hash))

    retired = Repo.all(from(r in RetiredImportHash, select: r.import_hash))
    MapSet.new(live ++ retired)
  end

  defp failed(guards), do: for(%{passed: false, code: code} <- guards, do: code)

  defp journal_mark do
    Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0
  end

  defp entries_since(mark) do
    Repo.all(from(e in Journal.Entry, where: e.id > ^mark, order_by: e.id))
  end

  # Every table's content, hashed: a refusal must leave each one as it was.
  defp fingerprint do
    %{rows: tables} =
      Repo.query!("""
      SELECT tablename FROM pg_tables
      WHERE schemaname = 'public' AND tablename <> 'schema_migrations'
      ORDER BY tablename
      """)

    Map.new(tables, fn [table] ->
      %{rows: [[digest]]} =
        Repo.query!(
          "SELECT md5(coalesce(string_agg(t::text, '|' ORDER BY t::text), '')) " <>
            ~s(FROM "#{table}" t)
        )

      {table, digest}
    end)
  end

  defp dec(value), do: value |> Decimal.new() |> Decimal.normalize()
  defp n(%Decimal{} = value), do: Decimal.normalize(value)
end
