defmodule Portfolixir.Lifecycle.CashMergeTest do
  # ADR-0050 §7 (the cash half), §8, §10, §12's record write and §13, with
  # the §16 invariants of the cash merge written before the code (L3a, #328;
  # risk-tier: money identity and idempotency, ADR-0036): 4 (the held-or-
  # retired hash set only grows), 9 (the cash identity), 11 (one journal
  # entry per moved, restated or deleted row, one aggregate entry per bucket
  # link change, no cascade) and 13 (each refusal answers its code and
  # leaves every table unchanged; a stale digest answers plan_changed and
  # writes nothing). The re-import half (1, 5, 6 and 9's last clause) is
  # test/portfolixir/lifecycle/cash_merge_reimport_test.exs; the API half
  # (12, and 13 over the wire) is the controller test.
  #
  # Every name and amount is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Projection
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.Performance
  alias Portfolixir.Portfolios.SecuritiesAccount

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Merge World",
        base_currency_code: "EUR"
      })

    target = cash!(portfolio, "Savings")
    source = cash!(portfolio, "Savings (old)")

    %{portfolio: portfolio, source: source, target: target}
  end

  describe "the worked example (§7 steps 2–7, §8)" do
    # User story:
    # As the operator folding an obsolete savings account into its successor,
    # I want the merge to move the history, drop the transfers between the
    # two, restate every balance anchor to the combined balance and ask me
    # about the bookings both accounts carry,
    # so that the survivor shows the sum of both accounts on every day.
    #
    # Acceptance criteria:
    # - The preview names the S↔T transfer, the key-equal pairs and every
    #   anchor with "stated + other account = after", for both values of
    #   collapse_key_equal, and a plan digest.
    # - Without collapse, the source's anchor becomes 900.00 + 712.40 =
    #   1612.40 and moves; the target's becomes 800.00 + 900.00 = 1700.00;
    #   the merged balance is 1710.00, the sum of both accounts.
    # - With collapse, the two key-equal source rows are deleted and the
    #   merged balance is 1702.50: the later collapsed interest is gone, the
    #   earlier one was absorbed by the source's anchor.
    test "the preview states both outcomes, and each apply lands on its figures", ctx do
      rows = worked_example!(ctx)

      assert {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      assert "sha256:" <> _ = preview.plan_digest
      assert Enum.all?(preview.guards, & &1.passed)
      assert n(preview.source.balance) == dec("902.50")
      assert n(preview.target.balance) == dec("807.50")
      assert preview.choice_required

      assert [%{id: transfer_id}] = preview.internal_transfers
      assert transfer_id == rows.transfer.id

      assert Enum.map(
               preview.key_equal_pairs,
               &{&1.source_transaction_id, &1.target_transaction_id}
             ) ==
               [
                 {rows.s_interest.id, rows.t_interest.id},
                 {rows.s_interest_late.id, rows.t_interest_late.id}
               ]

      keep = preview.outcomes[false]
      collapse = preview.outcomes[true]

      assert n(keep.balance) == dec("1710.00")
      assert n(collapse.balance) == dec("1702.50")

      assert anchor_line(keep, rows.s_anchor.id) ==
               {~D[2025-04-30], :source, dec("900.00"), dec("712.40"), dec("1612.40")}

      assert anchor_line(keep, rows.t_anchor.id) ==
               {~D[2025-05-31], :target, dec("800.00"), dec("900.00"), dec("1700.00")}

      # The source's anchor stands after the first collapsed interest, so a
      # collapse moves that interest's amount into the anchor's residual: a
      # flow the preview lists (§16 invariant 9).
      assert [%{transaction_id: absorbing, date: ~D[2025-04-30], change: change}] =
               Enum.filter(collapse.flow_changes, &(&1.kind == :absorbed))

      assert absorbing == rows.s_anchor.id
      assert n(change) == dec("12.40")

      assert {:ok, %MergeRecord{} = record, :applied} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: false
               })

      assert record.kind == :cash_account
      assert record.source_id == ctx.source.id
      assert record.target_id == ctx.target.id
      assert record.portfolio_id == ctx.portfolio.id
      assert record.plan_digest == preview.plan_digest
      assert record.actor_label == "synthetic-agent"
      assert record.manifest["choices"] == %{"collapse_key_equal" => false}

      assert balance(ctx.target) == dec("1710.00")
      refute Portfolios.get_cash_account(ctx.source.id)
      refute Repo.get(Transaction, rows.transfer.id)
      assert n(Repo.get!(Transaction, rows.s_anchor.id).gross_amount) == dec("1612.40")
      assert Repo.get!(Transaction, rows.s_anchor.id).cash_account_id == ctx.target.id
      assert n(Repo.get!(Transaction, rows.t_anchor.id).gross_amount) == dec("1700.00")
      assert Repo.get!(Transaction, rows.s_interest.id).cash_account_id == ctx.target.id
    end

    test "with collapse, the key-equal source rows go and the balance is the collapse outcome",
         ctx do
      rows = worked_example!(ctx)
      {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)

      assert {:ok, %MergeRecord{} = record, :applied} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: true
               })

      assert balance(ctx.target) == n(preview.outcomes[true].balance)
      assert balance(ctx.target) == dec("1702.50")
      refute Repo.get(Transaction, rows.s_interest.id)
      refute Repo.get(Transaction, rows.s_interest_late.id)
      assert Repo.get(Transaction, rows.t_interest.id)
      assert record.manifest["choices"] == %{"collapse_key_equal" => true}
    end
  end

  describe "the cash identity (§7 step 6, §16 invariant 9)" do
    # User story:
    # As the operator merging two accounts that each carry balance anchors,
    # I want the merged account's balance on every day to be the sum of what
    # both accounts showed on that day,
    # so that no anchor erases the other account's history.
    #
    # Acceptance criteria:
    # - At every date either account has a row and today, the merged balance
    #   equals the fold of the source's kept rows plus the fold of the
    #   target's kept rows, each under its own pre-merge anchors: with
    #   anchors on either side, on both sides on one day, two anchors on one
    #   day, and a collapse with an anchor of either side after a collapsed
    #   source row.
    # - On a day where both accounts carry anchors, the target's last anchor
    #   holds the sum of both last anchors, and the others of that day are
    #   deleted.
    test "anchors on either side, on both sides on one day, and two on one day", ctx do
      worked_example!(ctx)
      book!(ctx, ctx.source, "deposit", "40.00", ~D[2025-09-01])
      book!(ctx, ctx.target, "deposit", "60.00", ~D[2025-09-02])
      s_fold_first = anchor!(ctx.source, "250.00", ~D[2025-09-30])
      s_fold_last = anchor!(ctx.source, "300.00", ~D[2025-09-30])
      t_fold_first = anchor!(ctx.target, "650.00", ~D[2025-09-30])
      t_fold_last = anchor!(ctx.target, "700.00", ~D[2025-09-30])
      book!(ctx, ctx.source, "interest", "3.00", ~D[2025-10-15])
      t_two_a = anchor!(ctx.target, "400.00", ~D[2025-10-31])
      t_two_b = anchor!(ctx.target, "450.00", ~D[2025-10-31])
      book!(ctx, ctx.target, "fee", "2.00", ~D[2025-11-03])

      oracle = daily_sums(ctx, [])
      merge!(ctx, false)

      assert merged_balances(ctx, Map.keys(oracle)) == oracle

      # The fold day: the target's last anchor holds 300.00 + 700.00, the
      # other three anchors of the day are gone.
      assert n(Repo.get!(Transaction, t_fold_last.id).gross_amount) == dec("1000.00")
      refute Repo.get(Transaction, s_fold_first.id)
      refute Repo.get(Transaction, s_fold_last.id)
      refute Repo.get(Transaction, t_fold_first.id)

      # Two target anchors on one day, none of the source's: each is
      # restated by the source's end-of-day balance (300.00 + 3.00).
      assert n(Repo.get!(Transaction, t_two_a.id).gross_amount) == dec("703.00")
      assert n(Repo.get!(Transaction, t_two_b.id).gross_amount) == dec("753.00")
    end

    test "a collapse with an anchor of either side after a collapsed source row", ctx do
      rows = worked_example!(ctx)
      s_after = anchor!(ctx.source, "950.00", ~D[2025-08-31])
      t_after = anchor!(ctx.target, "820.00", ~D[2025-08-15])

      collapsed = [rows.s_interest.id, rows.s_interest_late.id]
      oracle = daily_sums(ctx, collapsed)
      merge!(ctx, true)

      assert merged_balances(ctx, Map.keys(oracle)) == oracle
      assert Repo.get!(Transaction, s_after.id).cash_account_id == ctx.target.id
      assert Repo.get(Transaction, t_after.id)
    end

    # User story:
    # As the operator whose performance history spans both accounts,
    # I want a merge without collapse to leave every day's external flow
    # and the total value unchanged, and a collapse to change them by the
    # collapsed rows alone, each such change listed in the preview,
    # so that a merge never rewrites my returns behind my back.
    #
    # Acceptance criteria:
    # - Without collapse, the performance walk's flow and value are equal on
    #   every day before and after the merge.
    # - With collapse, they differ exactly by the listed flow changes: a
    #   collapsed deposit removes its flow on its day; a collapsed row
    #   before one of the source's anchors moves its amount into that
    #   anchor's residual on the anchor's day; values differ by the
    #   collapsed rows until the source's anchor restates them.
    test "without collapse, flows per day and total value are unchanged", ctx do
      worked_example!(ctx)
      before = walk(ctx)
      merge!(ctx, false)
      assert walk(ctx) == before
    end

    test "with collapse, flows and values change by the collapsed rows alone", ctx do
      rows = worked_example!(ctx)
      s_deposit = book!(ctx, ctx.source, "deposit", "25.00", ~D[2025-02-20])
      t_deposit = book!(ctx, ctx.target, "deposit", "25.00", ~D[2025-02-20])
      before = walk(ctx)

      {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      changes = preview.outcomes[true].flow_changes

      assert %{kind: :removed, transaction_id: removed_id, change: removed} =
               Enum.find(changes, &(&1.date == ~D[2025-02-20]))

      assert removed_id == s_deposit.id
      assert n(removed) == dec("-25.00")
      assert Repo.get(Transaction, t_deposit.id)

      merge!(ctx, true, preview)
      after_merge = walk(ctx)

      expected_flows =
        Enum.reduce(changes, flows(before), fn %{date: date, change: change}, acc ->
          Map.update!(acc, date, &n(Decimal.add(&1, change)))
        end)

      assert flows(after_merge) == expected_flows

      # Values: the deposit and the early interest are gone from 2025-02-20
      # and 2025-03-31 on, until the source's anchor on 2025-04-30 states
      # the balance again; the late interest (2025-07-31) stays gone.
      for {date, value} <- values(before) do
        missing =
          cond do
            Date.compare(date, ~D[2025-02-20]) == :lt -> "0"
            Date.compare(date, ~D[2025-03-31]) == :lt -> "25.00"
            Date.compare(date, ~D[2025-04-30]) == :lt -> "37.40"
            Date.compare(date, ~D[2025-07-31]) == :lt -> "0"
            true -> "7.50"
          end

        assert Decimal.equal?(values(after_merge)[date], Decimal.sub(value, dec(missing))),
               "value on #{date}"
      end

      assert rows.s_anchor.id in Enum.map(changes, & &1.transaction_id)
    end

    # User story:
    # As the operator collapsing a transfer the old account and the new one
    # both made to a third account,
    # I want the preview to say that the third account's later set balance
    # absorbs the removed transfer,
    # so that a collapse never moves a flow in my returns I was not shown.
    #
    # Acceptance criteria:
    # - The collapse outcome lists an absorbed flow change naming the third
    #   account, its first anchor after the collapsed transfer, that anchor's
    #   date and the third account's leg of the transfer.
    # - Every flow change names the cash account it lands on.
    # - After the apply, the performance walk's flows differ from before by
    #   exactly the listed changes.
    test "a collapsed transfer to a third account moves its leg into that account's later anchor",
         ctx do
      side = cash!(ctx.portfolio, "Side pocket")
      book!(ctx, ctx.source, "deposit", "400.00", ~D[2025-01-02])
      book!(ctx, ctx.target, "deposit", "500.00", ~D[2025-01-02])
      s_transfer = transfer!(ctx, ctx.source, side, "50.00", ~D[2025-03-01], nil)
      transfer!(ctx, ctx.target, side, "50.00", ~D[2025-03-01], nil)
      side_anchor = anchor!(side, "100.00", ~D[2025-04-01])
      before = walk(ctx)

      {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      changes = preview.outcomes[true].flow_changes

      assert [
               %{
                 kind: :absorbed,
                 cash_account_id: side_id,
                 transaction_id: absorbing,
                 date: ~D[2025-04-01],
                 change: change,
                 collapsed_transaction_id: collapsed
               }
             ] = changes

      assert side_id == side.id
      assert absorbing == side_anchor.id
      assert collapsed == s_transfer.id
      assert n(change) == dec("50.00")

      merge!(ctx, true, preview)

      expected_flows =
        Enum.reduce(changes, flows(before), fn %{date: date, change: change}, acc ->
          Map.update!(acc, date, &n(Decimal.add(&1, change)))
        end)

      assert flows(walk(ctx)) == expected_flows
    end

    test "every flow change names the cash account it lands on", ctx do
      rows = worked_example!(ctx)
      s_deposit = book!(ctx, ctx.source, "deposit", "25.00", ~D[2025-02-20])
      book!(ctx, ctx.target, "deposit", "25.00", ~D[2025-02-20])

      {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      changes = preview.outcomes[true].flow_changes

      assert changes != []
      assert Enum.all?(changes, &(&1.cash_account_id == ctx.source.id))
      assert s_deposit.id in Enum.map(changes, & &1.transaction_id)
      assert rows.s_anchor.id in Enum.map(changes, & &1.transaction_id)
    end
  end

  describe "journal, depots, buckets and names (§7 steps 5 and 7, §13, §16 invariant 11)" do
    # User story:
    # As the maintainer auditing a merge,
    # I want every row it moved, restated or deleted journaled exactly once,
    # the source's bucket links removed in one aggregate entry, its linked
    # depots re-pointed one by one, and nothing removed by a cascade,
    # so that the journal and the merge record reconstruct what happened.
    #
    # Acceptance criteria:
    # - Each moved, restated or deleted transaction has exactly one journal
    #   entry under the merge's actor; unchanged rows have none.
    # - The source's bucket links go in one cash_account_bucket_assignment
    #   entry; each linked depot has one securities_account update; the
    #   source one cash_account delete; the target one update carrying the
    #   former names; the record one merge_record create; each retired hash
    #   one retired_import_hash create — and nothing else is journaled.
    # - No row disappears that the manifest does not list.
    test "one entry per touched row, one per aggregate, nothing else", ctx do
      rows = worked_example!(ctx)
      {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Long term"})
      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), ctx.source, [bucket.id])
      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), ctx.target, [bucket.id])
      depot = depot!(ctx, ctx.source, "Broker depot")
      untouched = book!(ctx, ctx.target, "deposit", "1.00", ~D[2025-12-01])
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
               Enum.sort([rows.transfer.id, rows.s_interest.id, rows.s_interest_late.id])

      for id <- deleted do
        assert [%{operation: :delete}] =
                 Enum.filter(
                   entries,
                   &(&1.resource_type == "transaction" and &1.resource_id == to_string(id))
                 )
      end

      # Every moved, restated or deleted row has its entry, and no other row
      # has one: a moved source anchor is one row with one entry.
      moved = Enum.map(record.manifest["transactions"]["moved"], & &1["id"])
      restated = Enum.map(record.manifest["transactions"]["restated"], & &1["id"])
      assert moved != [] and restated != []
      assert rows.t_anchor.id in restated

      assert Enum.sort(transaction_ids) ==
               Enum.sort(Enum.map(Enum.uniq(deleted ++ moved ++ restated), &to_string/1))

      assert Repo.aggregate(Transaction, :count) == count_before - length(deleted)
      assert Enum.all?(entries, &(&1.actor_label == "synthetic-agent"))

      # The example's rows carry no import hash, so nothing is retired here;
      # the retirements are counted in the hash test below.
      assert retired_hashes(record) == []
      by_type = Enum.frequencies_by(entries, &{&1.resource_type, &1.operation})

      assert Map.drop(by_type, [{"transaction", :update}, {"transaction", :delete}]) == %{
               {"cash_account_bucket_assignment", :update} => 1,
               {"securities_account", :update} => 1,
               {"cash_account", :delete} => 1,
               {"cash_account", :update} => 1,
               {"merge_record", :create} => 1
             }

      assert Repo.get!(SecuritiesAccount, depot.id).cash_account_id == ctx.target.id
      assert Buckets.cash_account_bucket_ids(ctx.target.id) == [bucket.id]
      assert record.manifest["securities_accounts"]["repointed"] == [depot.id]
      assert record.manifest["cash_account_buckets"]["removed"] == [bucket.id]
    end

    # User story (#851, ADR-0039, §13 of ADR-0050):
    # As the operator reading a memoised walk right after a merge,
    # I want the merge's writes to bump the derived basis of what each moved
    # row affected before and after,
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
    # the merged-away account,
    # I want its name and its former names to become former names of the
    # survivor, skipping the survivor's own name,
    # so that the import books onto the survivor and two same-named accounts
    # stop being ambiguous once merged.
    #
    # Acceptance criteria:
    # - The target's former names gain the source's name and former names, in
    #   that order, after its own.
    # - Merging two accounts of one name records nothing.
    test "the source's names become former names of the target", ctx do
      {:ok, source} =
        Portfolios.update_cash_account(agent(), ctx.source, %{name: "Savings (older)"})

      {:ok, source} = Portfolios.update_cash_account(agent(), source, %{name: "Savings (old)"})
      assert source.former_names == ["Savings (older)"]
      book!(ctx, source, "deposit", "10.00", ~D[2025-01-02])

      {:ok, preview} = Lifecycle.preview_cash_merge(source.id, ctx.target.id)
      assert preview.former_names.after == ["Savings (old)", "Savings (older)"]
      merge!(%{ctx | source: source}, false, preview)

      assert Portfolios.get_cash_account(ctx.target.id).former_names ==
               ["Savings (old)", "Savings (older)"]
    end

    test "merging two accounts of one name records no former name", ctx do
      twin = legacy_cash!(ctx.portfolio, "Savings")
      book!(ctx, twin, "deposit", "10.00", ~D[2025-01-02])

      {:ok, preview} = Lifecycle.preview_cash_merge(twin.id, ctx.target.id)
      assert preview.former_names.after == []
      merge!(%{ctx | source: twin}, false, preview)

      assert Portfolios.get_cash_account(ctx.target.id).former_names == []

      assert Repo.all(from(a in CashAccount, where: a.name == "Savings", select: a.id)) == [
               ctx.target.id
             ]
    end
  end

  describe "hashes and the merge record (§3, §12, §16 invariant 4)" do
    # User story:
    # As the operator who merged an account whose history came from an
    # import,
    # I want every hash a removed row carried retired under the merge record,
    # so that no writer can book that row again and the set of known hashes
    # only grows.
    #
    # Acceptance criteria:
    # - After the merge, every hash held by a transaction or retired before
    #   is still held or retired.
    # - Each removed row's hash is retired under the merge's record, with
    #   reason internal_transfer or collapsed_duplicate (superseded by its
    #   paired target row); the deferred foreign key finds its record.
    # - Ledger.create_transaction/3 with a retired hash answers a changeset
    #   error on import_hash.
    test "every removed row's hash is retired, and refused afterwards", ctx do
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
                 {rows.s_interest.id, :collapsed_duplicate, rows.t_interest.id},
                 {rows.s_interest_late.id, :collapsed_duplicate, rows.t_interest_late.id}
               ])

      for %RetiredImportHash{import_hash: hash} <- retired do
        assert {:error, changeset} =
                 Ledger.create_transaction(
                   Actor.import_session(),
                   %{
                     portfolio_id: ctx.portfolio.id,
                     cash_account_id: ctx.target.id,
                     type: "deposit",
                     date: ~D[2026-01-05],
                     gross_amount: "1.00",
                     currency_code: "EUR"
                   },
                   import_hash: hash
                 )

        assert %{import_hash: ["was retired by a merge and cannot be booked again"]} =
                 errors_on(changeset)
      end
    end

    # User story:
    # As the agent whose merge call timed out,
    # I want a retry of the same pair to answer the merge that happened, and
    # a merge of the same source into another account to be refused,
    # so that a retry never merges twice and never fails a completed merge.
    #
    # Acceptance criteria:
    # - A retry of a completed merge of the same pair answers the original
    #   record and journals nothing, whatever digest it carries.
    # - A merge of an already merged source into another target answers
    #   already_merged with the record, and writes nothing.
    test "a retry answers the original record; another target is already_merged", ctx do
      worked_example!(ctx)
      record = merge!(ctx, false)
      other = cash!(ctx.portfolio, "Other")
      mark = journal_mark()

      assert {:ok, %MergeRecord{id: id}, :already_applied} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: record.plan_digest,
                 collapse_key_equal: false
               })

      assert id == record.id
      before = fingerprint()

      assert {:error, {:already_merged, %MergeRecord{id: ^id}}} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, other.id, %{
                 plan_digest: record.plan_digest,
                 collapse_key_equal: false
               })

      assert {:error, {:already_merged, %MergeRecord{id: ^id}}} =
               Lifecycle.preview_cash_merge(ctx.source.id, other.id)

      assert entries_since(mark) == []
      assert fingerprint() == before
    end
  end

  describe "refusals and consent (§7 guards, §8, §10, §16 invariant 13)" do
    # User story:
    # As the operator about to merge the wrong pair,
    # I want every merge the guards forbid refused with a named reason before
    # anything is written,
    # so that a foreign-currency account, another liquidity role, other
    # buckets, the account itself or a vanished one can never be merged.
    #
    # Acceptance criteria:
    # - Each guard answers {:refused, guards} naming its code, on the preview
    #   and on the apply, and every table is unchanged.
    test "each guard refuses with its code and writes nothing", ctx do
      worked_example!(ctx)
      usd = cash!(ctx.portfolio, "Broker USD", currency_code: "USD")
      credit = cash!(ctx.portfolio, "Credit line", liquidity_role: "credit_line")
      {:ok, bucket} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Short term"})
      tagged = cash!(ctx.portfolio, "Fixed deposit")
      :ok = Buckets.set_cash_account_buckets(Actor.owner_ui(), tagged, [bucket.id])

      {:ok, elsewhere} =
        Portfolios.create_portfolio(Actor.owner_ui(), %{
          name: "Elsewhere",
          base_currency_code: "EUR"
        })

      foreign = cash!(elsewhere, "Savings abroad")
      gone = cash!(ctx.portfolio, "Gone")
      {:ok, _} = Portfolios.delete_cash_account(Actor.owner_ui(), gone)

      cases = [
        {ctx.source.id, :same_account},
        {usd.id, :currency_mismatch},
        {credit.id, :liquidity_role_mismatch},
        {tagged.id, :buckets_mismatch},
        {foreign.id, :portfolio_mismatch},
        {gone.id, :not_live}
      ]

      before = fingerprint()

      for {target_id, code} <- cases do
        assert {:error, {:refused, guards}} =
                 Lifecycle.preview_cash_merge(ctx.source.id, target_id)

        assert code in failed(guards), "preview #{code}: #{inspect(guards)}"

        assert {:error, {:refused, guards}} =
                 Lifecycle.merge_cash_account(agent(), ctx.source.id, target_id, %{
                   plan_digest: "sha256:whatever",
                   collapse_key_equal: false
                 })

        assert code in failed(guards), "apply #{code}: #{inspect(guards)}"
        assert fingerprint() == before
      end

      assert {:error, :not_found} = Lifecycle.preview_cash_merge(gone.id, ctx.target.id)
    end

    # User story:
    # As the operator who approved a preview an hour ago,
    # I want the merge refused when a booking of either account changed
    # since, with the fresh preview,
    # so that the figures applied are always the ones I approved.
    #
    # Acceptance criteria:
    # - An apply whose digest no longer matches answers {:plan_changed,
    #   fresh_preview} and writes nothing; the fresh preview's digest applies.
    # - Without a digest the apply answers {:invalid, :plan_digest, _}; with
    #   key-equal pairs and no collapse_key_equal it answers
    #   {:choice_required, :collapse_key_equal, pairs}; neither writes anything.
    test "a stale digest answers plan_changed with the fresh preview, and writes nothing", ctx do
      rows = worked_example!(ctx)
      {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)

      {:ok, _} = Ledger.update_transaction(agent(), rows.s_fee, %{gross_amount: "6.00"})
      before = fingerprint()

      assert {:error, {:plan_changed, fresh}} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: false
               })

      assert fresh.plan_digest != preview.plan_digest
      assert n(fresh.outcomes[false].balance) == dec("1709.00")
      assert fingerprint() == before

      assert {:error, {:invalid, :plan_digest, _}} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 collapse_key_equal: false
               })

      assert {:error, {:choice_required, :collapse_key_equal, 2}} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: fresh.plan_digest
               })

      assert fingerprint() == before

      assert {:ok, _record, :applied} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: fresh.plan_digest,
                 collapse_key_equal: false
               })
    end

    # User story:
    # As the operator merging an account whose balance carries the fraction
    # of a trade booked without its amount,
    # I want the merge refused up front, naming the anchor it could not
    # store and the trade that makes it so,
    # so that the preview never promises a figure the ledger cannot hold
    # and the merge never fails after I confirmed it.
    #
    # Acceptance criteria:
    # - A buy on the source of 0.333333333333 shares at 3.333333 with no
    #   amount makes the source's balance -1.111110999998888889, so the
    #   target's later anchor of 100.00 would have to become
    #   98.888889000001111111, which the amount column (6 places) cannot
    #   hold.
    # - Preview and apply answer {:refused, guards} with
    #   unstorable_anchor, whose detail and anchors name the anchor and
    #   whose detail names the trade; every table is unchanged.
    # - With the trade's amount recorded, the same pair merges.
    test "an anchor restatement the amount column cannot hold is refused by name", ctx do
      depot = depot!(ctx, ctx.source, "Savings plan depot")

      {:ok, security} =
        Portfolixir.Catalog.create_security(Actor.owner_ui(), %{
          name: "Synthetic Fraction Fund",
          currency_code: "EUR"
        })

      {:ok, buy} =
        Ledger.create_transaction(agent(), %{
          portfolio_id: ctx.portfolio.id,
          type: "buy",
          date: ~D[2025-01-10],
          security_id: security.id,
          securities_account_id: depot.id,
          cash_account_id: ctx.source.id,
          quantity: "0.333333333333",
          price: "3.333333",
          currency_code: "EUR"
        })

      anchor = anchor!(ctx.target, "100.00", ~D[2025-02-01])
      before = fingerprint()

      assert {:error, {:refused, guards}} =
               Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)

      assert :unstorable_anchor in failed(guards)
      failed_guard = Enum.find(guards, &(&1.code == :unstorable_anchor))
      assert [%{id: anchor_id, date: ~D[2025-02-01]}] = failed_guard.anchors
      assert anchor_id == anchor.id
      assert [%{id: booking_id, date: ~D[2025-01-10]}] = failed_guard.bookings
      assert booking_id == buy.id
      assert failed_guard.detail =~ "##{anchor.id}"
      assert failed_guard.detail =~ "##{buy.id}"
      assert failed_guard.detail =~ "98.888889000001111111"

      assert {:error, {:refused, guards}} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: "sha256:whatever"
               })

      assert :unstorable_anchor in failed(guards)
      assert fingerprint() == before

      {:ok, _} = Ledger.update_transaction(agent(), buy, %{gross_amount: "1.11"})
      assert {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      merge!(ctx, false, preview)
      assert balance(ctx.target) == dec("98.89")
    end

    test "without key-equal pairs, no choice is required", ctx do
      book!(ctx, ctx.source, "deposit", "10.00", ~D[2025-01-02])
      book!(ctx, ctx.target, "deposit", "20.00", ~D[2025-01-02])

      {:ok, preview} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      refute preview.choice_required
      assert preview.outcomes[false] == preview.outcomes[true]

      assert {:ok, _record, :applied} =
               Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest
               })

      assert balance(ctx.target) == dec("30.00")
    end

    # User story:
    # As the maintainer of the digest,
    # I want one pair to have one digest whatever the operator will choose,
    # and any change of a figure, a row or a guard to change it,
    # so that consent covers exactly what the preview showed.
    #
    # Acceptance criteria:
    # - Two previews of an unchanged pair carry the same digest.
    # - A new booking on either side changes it.
    test "the digest is stable for one pair and moves with its rows", ctx do
      worked_example!(ctx)
      {:ok, first} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      {:ok, again} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      assert first.plan_digest == again.plan_digest

      book!(ctx, ctx.target, "deposit", "1.00", ~D[2026-02-01])
      {:ok, changed} = Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)
      refute changed.plan_digest == first.plan_digest
    end
  end

  # --- the worked example ------------------------------------------------------

  # Source "Savings (old)" and target "Savings": a deposit each, a transfer
  # from source to target, two key-equal interest pairs, one anchor each,
  # and a fee on the source.
  #
  #   source: 1000.00, -200.00, +12.40, anchor 900.00, -5.00, +7.50 => 902.50
  #   target:  500.00, +200.00, +12.40, anchor 800.00, +7.50        => 807.50
  defp worked_example!(ctx, opts \\ []) do
    hashed? = Keyword.get(opts, :hashed, false)
    hash = fn label -> if hashed?, do: "synthetic-hash-#{label}" end

    %{
      s_deposit: book!(ctx, ctx.source, "deposit", "1000.00", ~D[2025-01-02], hash.("s-deposit")),
      t_deposit: book!(ctx, ctx.target, "deposit", "500.00", ~D[2025-01-03], hash.("t-deposit")),
      transfer:
        transfer!(ctx, ctx.source, ctx.target, "200.00", ~D[2025-02-01], hash.("transfer")),
      s_interest:
        book!(ctx, ctx.source, "interest", "12.40", ~D[2025-03-31], hash.("s-interest")),
      t_interest:
        book!(ctx, ctx.target, "interest", "12.40", ~D[2025-03-31], hash.("t-interest")),
      s_anchor: anchor!(ctx.source, "900.00", ~D[2025-04-30]),
      t_anchor: anchor!(ctx.target, "800.00", ~D[2025-05-31]),
      s_fee: book!(ctx, ctx.source, "fee", "5.00", ~D[2025-06-15], hash.("s-fee")),
      s_interest_late:
        book!(ctx, ctx.source, "interest", "7.50", ~D[2025-07-31], hash.("s-interest-late")),
      t_interest_late:
        book!(ctx, ctx.target, "interest", "7.50", ~D[2025-07-31], hash.("t-interest-late"))
    }
  end

  # --- world ------------------------------------------------------------------

  defp cash!(portfolio, name, opts \\ []) do
    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: Keyword.get(opts, :currency_code, "EUR"),
        liquidity_role: Keyword.get(opts, :liquidity_role, "free_cash")
      })

    cash
  end

  defp depot!(ctx, cash, name) do
    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: ctx.portfolio.id,
        cash_account_id: cash.id,
        name: name
      })

    depot
  end

  # A duplicate name from before the guard, inserted the way the old writer
  # did.
  defp legacy_cash!(portfolio, name) do
    {:ok, %{account: account}} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :account,
        Ecto.Changeset.change(%CashAccount{}, %{
          portfolio_id: portfolio.id,
          name: name,
          currency_code: "EUR"
        })
      )
      |> Journal.record(Actor.owner_ui(),
        resource_type: "cash_account",
        operation: :create,
        source: :account
      )
      |> Repo.transaction()

    account
  end

  defp book!(ctx, account, type, amount, date, hash \\ nil) do
    attrs = %{
      portfolio_id: ctx.portfolio.id,
      cash_account_id: account.id,
      type: type,
      date: date,
      gross_amount: amount,
      currency_code: "EUR"
    }

    opts = if hash, do: [import_hash: hash], else: []
    {:ok, tx} = Ledger.create_transaction(agent(), attrs, opts)
    tx
  end

  defp transfer!(ctx, from, to, amount, date, hash) do
    attrs = %{
      portfolio_id: ctx.portfolio.id,
      cash_account_id: from.id,
      counter_cash_account_id: to.id,
      type: "cash_transfer",
      date: date,
      gross_amount: amount,
      currency_code: "EUR"
    }

    opts = if hash, do: [import_hash: hash], else: []
    {:ok, tx} = Ledger.create_transaction(agent(), attrs, opts)
    tx
  end

  defp anchor!(account, amount, date) do
    {:ok, tx} = Ledger.set_cash_balance(agent(), account, %{date: date, amount: amount})
    tx
  end

  defp merge!(ctx, collapse?, preview \\ nil) do
    {:ok, preview} =
      if preview,
        do: {:ok, preview},
        else: Lifecycle.preview_cash_merge(ctx.source.id, ctx.target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_cash_account(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: collapse?
      })

    record
  end

  # --- oracles ----------------------------------------------------------------

  # The sum of both accounts' balances at the end of every date either has a
  # row on, and today, from the ledger's own projection over the rows as they
  # stand before the merge, the collapsed source rows left out.
  defp daily_sums(ctx, collapsed_ids) do
    ids = [ctx.source.id, ctx.target.id]

    rows =
      Repo.all(
        from(t in Transaction,
          where: t.cash_account_id in ^ids or t.counter_cash_account_id in ^ids
        )
      )

    kept = Enum.reject(rows, &(&1.id in collapsed_ids))
    dates = Enum.uniq([Portfolixir.Clock.today() | Enum.map(rows, & &1.date)])

    Map.new(dates, fn date ->
      balances =
        kept |> Enum.filter(&(Date.compare(&1.date, date) != :gt)) |> Projection.cash_balances()

      sum =
        Decimal.add(
          Map.get(balances, ctx.source.id, dec("0")),
          Map.get(balances, ctx.target.id, dec("0"))
        )

      {date, Decimal.normalize(sum)}
    end)
  end

  defp merged_balances(ctx, dates) do
    rows =
      Repo.all(
        from(t in Transaction,
          where:
            t.cash_account_id == ^ctx.target.id or t.counter_cash_account_id == ^ctx.target.id
        )
      )

    Map.new(dates, fn date ->
      balances =
        rows |> Enum.filter(&(Date.compare(&1.date, date) != :gt)) |> Projection.cash_balances()

      {date, Decimal.normalize(Map.get(balances, ctx.target.id, dec("0")))}
    end)
  end

  defp walk(ctx) do
    ctx.portfolio.id
    |> Performance.analysis()
    |> Map.fetch!(:daily)
    |> Map.new(&{&1.date, {Decimal.normalize(&1.flow), Decimal.normalize(&1.value)}})
  end

  defp flows(walk), do: Map.new(walk, fn {date, {flow, _value}} -> {date, flow} end)
  defp values(walk), do: Map.new(walk, fn {date, {_flow, value}} -> {date, value} end)

  defp balance(account) do
    Map.get(Ledger.cash_balances(), account.id, dec("0")) |> Decimal.normalize()
  end

  defp anchor_line(outcome, id) do
    %{date: date, side: side, stated: stated, other_balance: other, after: after_restatement} =
      Enum.find(outcome.restated_anchors, &(&1.id == id))

    {date, side, n(stated), n(other), n(after_restatement)}
  end

  defp held_or_retired do
    live =
      Repo.all(from(t in Transaction, where: not is_nil(t.import_hash), select: t.import_hash))

    retired = Repo.all(from(r in RetiredImportHash, select: r.import_hash))
    MapSet.new(live ++ retired)
  end

  defp retired_hashes(record),
    do: Repo.all(from(r in RetiredImportHash, where: r.merge_record_id == ^record.id))

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
