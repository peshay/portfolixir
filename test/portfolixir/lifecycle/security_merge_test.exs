defmodule Portfolixir.Lifecycle.SecurityMergeTest do
  # ADR-0050 §9 up to and including splits and split events, with §8, §10,
  # §12's record write and §13 (L4, #608; risk-tier: quantity identity and
  # import idempotency, ADR-0036). The §16 invariants of the security merge
  # were written before the code:
  #
  #   * 10's security half — per portfolio, depot and date the merged
  #     quantity equals the fold of the target's pre-merge rows plus the fold
  #     of the source's kept rows, each under its own pre-merge split set, a
  #     collapsed split scaling the combined position once; the split
  #     refusal; the split-event-set refusal; and a split whose combined-once
  #     rounding differs from the sum of the separately rounded positions;
  #   * 11 — one journal entry per moved or deleted row, one aggregate entry
  #     per override change, nothing removed by a cascade, notes and rule
  #     versions never touched;
  #   * 13 — each refusal answers its code and leaves every table unchanged;
  #     a stale digest answers plan_changed and writes nothing.
  #
  # Every name, amount and quantity is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Buckets
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Clock
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge
  alias Portfolixir.Knowledge.SecurityNote
  alias Portfolixir.Ledger
  alias Portfolixir.Ledger.Positions
  alias Portfolixir.Ledger.Transaction
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Lifecycle.RetiredImportHash
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PolicyRuleVersion

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    main = portfolio!("Main")
    second = portfolio!("Second")
    c1 = cash!(main, "Main cash")
    c2 = cash!(second, "Second cash")

    %{
      main: main,
      second: second,
      c1: c1,
      c2: c2,
      d1: depot!(main, c1, "Broker A"),
      d2: depot!(main, c1, "Broker B"),
      d3: depot!(second, c2, "Broker C"),
      target: security!("Fund X"),
      source: security!("Fund X")
    }
  end

  describe "the worked example (§9 rows, §8)" do
    # User story:
    # As the operator repairing a duplicate security that an import created
    # with a second copy of the history,
    # I want the preview to show the key-equal booking pairs, the splits that
    # collapse, and every affected position before and after for either
    # answer to the duplicate question, and the merge to land on exactly
    # those figures,
    # so that I see what the merge does to my holdings before I confirm.
    #
    # Acceptance criteria:
    # - The preview pairs the source's dividend and buy with the target's
    #   key-equal twins, and lists the same-day, same-ratio split of the same
    #   portfolio as collapsing — never as a pair, whatever the choice.
    # - Broker A: source 10 + target 20 → 30 after without collapse, 26 with
    #   it; Broker B, held by the source alone, moves unchanged (6). A depot
    #   only the target holds is not listed.
    # - The apply moves every other source row onto the target, deletes the
    #   source's collapsed split and the source, and the target's holdings
    #   are the preview's after-figures.
    test "the preview states both outcomes, and each apply lands on its figures", ctx do
      rows = worked_example!(ctx)

      assert {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      assert preview.kind == :security
      assert "sha256:" <> _ = preview.plan_digest
      assert Enum.all?(preview.guards, & &1.passed)
      assert preview.choice_required
      assert preview.source.transaction_count == 6
      assert preview.target.transaction_count == 7

      assert Enum.map(
               preview.key_equal_pairs,
               &{&1.source_transaction_id, &1.target_transaction_id}
             ) == [{rows.s_div.id, rows.t_div.id}, {rows.s_pair.id, rows.t_pair.id}]

      assert [collapsed] = preview.splits.collapsed
      assert collapsed.source_transaction_id == rows.s_split.id
      assert collapsed.target_transaction_id == rows.t_split_main.id
      assert collapsed.portfolio_id == ctx.main.id
      assert preview.splits.moved == []

      assert preview.split_events.after == [
               %{date: ~D[2025-09-01], ratio: %{numerator: 2, denominator: 1}}
             ]

      keep = preview.outcomes[false]
      collapse = preview.outcomes[true]

      assert Enum.map(keep.positions, & &1.securities_account_id) ==
               Enum.sort([ctx.d1.id, ctx.d2.id])

      assert quantities(keep, ctx.d1) == {dec("10"), dec("20"), dec("30")}
      assert quantities(collapse, ctx.d1) == {dec("10"), dec("20"), dec("26")}
      assert quantities(keep, ctx.d2) == {dec("6"), nil, dec("6")}
      assert keep.rounding_differences == []
      assert keep.cash_accounts == []

      # The split collapses under either value of the choice.
      for outcome <- [keep, collapse] do
        assert rows.s_split.id in Enum.map(outcome.deleted, & &1.id)
        refute rows.s_split.id in outcome.moved_transaction_ids
      end

      assert {:ok, %MergeRecord{} = record, :applied} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: false
               })

      assert record.kind == :security
      assert record.source_id == ctx.source.id
      assert record.target_id == ctx.target.id
      assert record.portfolio_id == nil
      assert record.plan_digest == preview.plan_digest
      assert record.actor_label == "synthetic-agent"

      assert record.manifest["choices"] == %{
               "collapse_key_equal" => false,
               "identity_choice" => nil,
               "isin_changed_on" => nil
             }

      refute Repo.get(Security, ctx.source.id)
      refute Repo.get(Transaction, rows.s_split.id)
      assert Repo.get(Transaction, rows.t_split_main.id)

      for row <- [rows.s_buy_a, rows.s_buy_b, rows.s_div, rows.s_pair, rows.s_sell] do
        moved = Repo.get!(Transaction, row.id)
        assert moved.security_id == ctx.target.id
        assert moved.securities_account_id == row.securities_account_id
        assert moved.cash_account_id == row.cash_account_id
      end

      assert held(ctx.d1, ctx.target) == dec("30")
      assert held(ctx.d2, ctx.target) == dec("6")
      assert held(ctx.d3, ctx.target) == dec("8")

      # Every figure the outcome promised is what the ledger's own
      # moving-average fold reads from the stored rows.
      for %{securities_account_id: depot_id, after: after_figures} <- keep.positions do
        assert stored_figures(depot_id, ctx.target.id) ==
                 {n(after_figures.quantity), n(after_figures.cost_basis)}
      end
    end

    test "with collapse, the key-equal source rows go and the positions are the collapse outcome",
         ctx do
      rows = worked_example!(ctx)
      balance_before = balance(ctx.c1)
      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

      assert [%{id: cash_id, balance_before: before, balance_after: after_collapse}] =
               preview.outcomes[true].cash_accounts

      assert cash_id == ctx.c1.id
      assert n(before) == balance_before

      assert {:ok, %MergeRecord{} = record, :applied} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: true
               })

      refute Repo.get(Transaction, rows.s_div.id)
      refute Repo.get(Transaction, rows.s_pair.id)
      assert Repo.get(Transaction, rows.t_div.id)
      assert Repo.get(Transaction, rows.t_pair.id)
      assert held(ctx.d1, ctx.target) == dec("26")
      assert balance(ctx.c1) == n(after_collapse)

      assert record.manifest["choices"] == %{
               "collapse_key_equal" => true,
               "identity_choice" => nil,
               "isin_changed_on" => nil
             }

      for %{securities_account_id: depot_id, after: after_figures} <-
            preview.outcomes[true].positions do
        assert stored_figures(depot_id, ctx.target.id) ==
                 {n(after_figures.quantity), n(after_figures.cost_basis)}
      end
    end
  end

  describe "the security linearity (§9 rows, §16 invariant 10)" do
    # User story:
    # As the operator merging a duplicate security into the one I keep,
    # I want the kept security's quantity in every depot on every day to be
    # what both held there together,
    # so that no booking is lost, counted twice or rescaled by the merge.
    #
    # Acceptance criteria:
    # - Per portfolio, depot and date (every date either security has a row,
    #   and today), the merged quantity equals the fold of the target's
    #   pre-merge rows plus the fold of the source's kept rows, each under
    #   its own pre-merge split set — the collapsed rows left out, a
    #   collapsed split scaling the combined position once.
    test "at every date the merged quantity is the sum of both folds", ctx do
      rows = worked_example!(ctx)
      oracle = daily_sums(ctx, [])
      merge!(ctx, false)
      assert merged_quantities(ctx, Map.keys(oracle)) == oracle

      ctx = fresh_pair!(ctx, "Fund Y")
      rows_again = worked_example!(ctx)
      collapsed = [rows_again.s_div.id, rows_again.s_pair.id]
      oracle = daily_sums(ctx, collapsed)
      merge!(ctx, true)
      assert merged_quantities(ctx, Map.keys(oracle)) == oracle
      assert rows.s_div.id != rows_again.s_div.id
    end

    # User story:
    # As the operator whose two securities both went through a reverse
    # split while one depot held both,
    # I want the merge to scale the combined position once, as the ledger
    # would have if they had always been one security, and to show me where
    # that differs from the two positions rounded apart,
    # so that a difference of one unit of the volume scale is explained, not
    # a surprise and not a refused merge.
    #
    # Acceptance criteria:
    # - One share of each in Broker A and a 1:3 split of each in the same
    #   portfolio on the same day: apart 0.333333 + 0.333333 = 0.666666,
    #   combined 2 → 0.666667.
    # - The preview lists the portfolio, the depot, the split date and both
    #   figures with their difference of 0.000001; the merge applies, and
    #   the target holds 0.666667 afterwards; before the split the merged
    #   quantity is the sum of both.
    test "a collapsed split scales the combined position once; the rounding difference is listed",
         ctx do
      buy!(ctx, ctx.d1, ctx.c1, ctx.target, "1", "10.00", ~D[2025-01-10])
      buy!(ctx, ctx.d1, ctx.c1, ctx.source, "1", "10.00", ~D[2025-01-12])
      t_split = split!(ctx.main, ctx.target, ~D[2025-03-01], {1, 3})
      split!(ctx.main, ctx.source, ~D[2025-03-01], {1, 3})

      assert held(ctx.d1, ctx.target) == dec("0.333333")
      assert held(ctx.d1, ctx.source) == dec("0.333333")

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      assert Enum.all?(preview.guards, & &1.passed)

      assert [difference] = preview.outcomes[false].rounding_differences
      assert difference.portfolio_id == ctx.main.id
      assert difference.securities_account_id == ctx.d1.id
      assert difference.date == ~D[2025-03-01]
      assert difference.split_transaction_id == t_split.id
      assert difference.ratio == %{numerator: 1, denominator: 3}
      assert n(difference.combined) == dec("0.666667")
      assert n(difference.separate_sum) == dec("0.666666")
      assert n(difference.difference) == dec("0.000001")
      assert quantities(preview.outcomes[false], ctx.d1) |> elem(2) == dec("0.666667")

      oracle = daily_sums(ctx, [])
      merge!(ctx, false, preview)

      assert held(ctx.d1, ctx.target) == dec("0.666667")

      merged = merged_quantities(ctx, Map.keys(oracle))

      for {{date, _depot} = key, quantity} <- oracle,
          Date.compare(date, ~D[2025-03-01]) == :lt do
        assert merged[key] == quantity
      end

      assert merged[{~D[2025-03-01], ctx.d1.id}] == dec("0.666667")
    end

    # User story:
    # As the operator of the merge,
    # I want two splits of one day in one portfolio with different ratios
    # refused before anything is paired,
    # so that the merge never has to guess which ratio is the real one.
    #
    # Acceptance criteria:
    # - A 2:1 split of the source and a 3:1 split of the target in the same
    #   portfolio on the same day refuse as split_ratio_mismatch, naming the
    #   date and both ratios, on the preview and the apply; every table is
    #   unchanged.
    test "a same-day split of another ratio in the same portfolio refuses", ctx do
      buy!(ctx, ctx.d1, ctx.c1, ctx.source, "2", "10.00", ~D[2025-01-10])
      buy!(ctx, ctx.d1, ctx.c1, ctx.target, "3", "10.00", ~D[2025-01-12])
      split!(ctx.main, ctx.source, ~D[2025-03-01], {2, 1})
      split!(ctx.main, ctx.target, ~D[2025-03-01], {3, 1})

      detail = refused!(ctx, :split_ratio_mismatch)
      assert detail =~ "2025-03-01"
      assert detail =~ "2:1"
      assert detail =~ "3:1"

      # The refusal names its conflict as data too, for the operator's page
      # to say it in the operator's language (L5b, board 03).
      assert [
               %{
                 date: ~D[2025-03-01],
                 portfolio_name: "Main",
                 source_ratio: %{numerator: 2, denominator: 1},
                 target_ratio: %{numerator: 3, denominator: 1}
               }
             ] = refused_guard!(ctx, :split_ratio_mismatch).conflicts
    end

    # User story:
    # As the operator whose source security carries a split its duplicate
    # never booked,
    # I want the merge refused while the duplicate has a booking or a quote
    # from before that split, naming the split and the side lacking it,
    # so that the merged split-event set never rebases a history that was
    # not split (ADR-0028 §2).
    #
    # Acceptance criteria:
    # - The source's 2:1 split of 2025-03-01, lacked by a target with a buy
    #   before it, refuses as split_event_mismatch naming the date, the
    #   ratio, the target and the remedy (book the split on that side first).
    # - The same with a target whose only earlier record is a quote.
    # - A target whose whole history lies after the split merges, and the
    #   source's split row moves onto it.
    test "an event one side lacks refuses while that side has earlier bookings or quotes", ctx do
      buy!(ctx, ctx.d1, ctx.c1, ctx.source, "2", "10.00", ~D[2025-01-10])
      s_split = split!(ctx.main, ctx.source, ~D[2025-03-01], {2, 1})
      early = buy!(ctx, ctx.d3, ctx.c2, ctx.target, "4", "10.00", ~D[2025-01-12])

      detail = refused!(ctx, :split_event_mismatch)
      assert detail =~ "2025-03-01"
      assert detail =~ "2:1"
      assert detail =~ "target"
      assert detail =~ ~r/book the split on the target first/i

      assert [
               %{
                 kind: :lacking,
                 side: :target,
                 date: ~D[2025-03-01],
                 ratio: %{numerator: 2, denominator: 1},
                 earlier: %{kind: :booking, date: ~D[2025-01-12]}
               }
             ] = refused_guard!(ctx, :split_event_mismatch).issues

      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), early)
      buy!(ctx, ctx.d3, ctx.c2, ctx.target, "4", "10.00", ~D[2025-04-01])
      quote!(ctx.target, ~D[2025-02-01], "10.00")

      detail = refused!(ctx, :split_event_mismatch)
      assert detail =~ "2025-03-01"
      assert detail =~ "quote"

      assert [%{kind: :lacking, side: :target, earlier: %{kind: :quote, date: ~D[2025-02-01]}}] =
               refused_guard!(ctx, :split_event_mismatch).issues

      Repo.delete_all(from(q in "security_quotes", where: q.security_id == ^ctx.target.id))

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      assert Enum.map(preview.splits.moved, & &1.id) == [s_split.id]
      merge!(ctx, false, preview)

      assert Repo.get!(Transaction, s_split.id).security_id == ctx.target.id
      assert held(ctx.d1, ctx.target) == dec("4")
      assert held(ctx.d3, ctx.target) == dec("4")
    end

    # User story:
    # As the operator of the merge,
    # I want one split booked on two dates, and two ratios on one day in
    # different portfolios, refused as a split-event mismatch,
    # so that the merged security never carries two versions of one event.
    #
    # Acceptance criteria:
    # - The source's 2:1 of 2025-03-01 in one portfolio and the target's 3:1
    #   of the same day in another refuse as split_event_mismatch, naming
    #   both ratios.
    # - The source's 2:1 of 2025-03-01 and the target's 2:1 of 2025-03-05
    #   refuse as split_event_mismatch, naming both dates.
    test "two ratios on one day, or one split on two dates, refuse", ctx do
      buy!(ctx, ctx.d1, ctx.c1, ctx.source, "2", "10.00", ~D[2025-01-10])
      buy!(ctx, ctx.d3, ctx.c2, ctx.target, "4", "10.00", ~D[2025-01-12])
      split!(ctx.main, ctx.source, ~D[2025-03-01], {2, 1})
      t_split = split!(ctx.second, ctx.target, ~D[2025-03-01], {3, 1})

      detail = refused!(ctx, :split_event_mismatch)
      assert detail =~ "2:1"
      assert detail =~ "3:1"

      assert %{
               kind: :two_ratios,
               date: ~D[2025-03-01],
               ratios: [
                 %{ratio: %{numerator: 2, denominator: 1}, sides: [:source]},
                 %{ratio: %{numerator: 3, denominator: 1}, sides: [:target]}
               ]
             } in refused_guard!(ctx, :split_event_mismatch).issues

      {:ok, _} = Ledger.delete_transaction(Actor.owner_ui(), t_split)
      split!(ctx.second, ctx.target, ~D[2025-03-05], {2, 1})

      detail = refused!(ctx, :split_event_mismatch)
      assert detail =~ "2025-03-01"
      assert detail =~ "2025-03-05"
    end

    # User story:
    # As the operator whose two securities carry the same split, booked in
    # different portfolios,
    # I want the merge refused where a split would rescale bookings it never
    # scaled before, naming the split date,
    # so that a target-side split never rescales moved rows (ADR-0028 §1),
    # and no split row of the source rescales the target's own history.
    #
    # Acceptance criteria:
    # - Both split-event sets are {2025-03-01 2:1}, but the source's row sits
    #   in the portfolio where the target holds Broker B unsplit: the merge
    #   refuses as split_linearity naming the date and the depot, and writes
    #   nothing.
    test "a split that would rescale the other side's bookings refuses", ctx do
      buy!(ctx, ctx.d1, ctx.c1, ctx.source, "2", "10.00", ~D[2025-01-10])
      split!(ctx.main, ctx.source, ~D[2025-03-01], {2, 1})
      buy!(ctx, ctx.d3, ctx.c2, ctx.target, "4", "10.00", ~D[2025-01-12])
      split!(ctx.second, ctx.target, ~D[2025-03-01], {2, 1})
      buy!(ctx, ctx.d2, ctx.c1, ctx.target, "1", "10.00", ~D[2025-02-01])

      detail = refused!(ctx, :split_linearity)
      assert detail =~ "2025-03-01"
      assert detail =~ "Broker B"

      assert %{date: ~D[2025-03-01], securities_account_name: "Broker B"} =
               refused_guard!(ctx, :split_linearity).failure
    end

    # User story:
    # As the operator whose target security carries a split in a portfolio
    # where the duplicate was bought before that date, unsplit,
    # I want the merge refused naming the split date,
    # so that a target-side split never rescales the moved rows (ADR-0028
    # §1, the case §9 names).
    #
    # Acceptance criteria:
    # - The target's 2:1 split of 2025-03-01 in Main, the source's in Second
    #   only, and the source's Broker B buy in Main before it: split_linearity
    #   naming the date and the depot; nothing written.
    test "a target-side split that would rescale moved rows refuses", ctx do
      buy!(ctx, ctx.d1, ctx.c1, ctx.target, "4", "10.00", ~D[2025-01-12])
      split!(ctx.main, ctx.target, ~D[2025-03-01], {2, 1})
      buy!(ctx, ctx.d3, ctx.c2, ctx.source, "1", "10.00", ~D[2025-01-05])
      split!(ctx.second, ctx.source, ~D[2025-03-01], {2, 1})
      buy!(ctx, ctx.d2, ctx.c1, ctx.source, "2", "10.00", ~D[2025-01-10])

      detail = refused!(ctx, :split_linearity)
      assert detail =~ "2025-03-01"
      assert detail =~ "Broker B"
      assert detail =~ "4"
    end
  end

  describe "view membership (§9 configuration, §7's membership rule per depot)" do
    # User story:
    # As the operator whose duplicate security sits in views through its
    # positions,
    # I want each position's view membership to stay what it was, per depot,
    # so that a merge never moves history between views behind my back.
    #
    # Acceptance criteria:
    # - The source's override in a depot where the target holds nothing is
    #   carried onto the target's position there.
    # - The source's override in a depot the target holds, equal to the
    #   target's effective set, is dropped as redundant.
    # - A dead override of the target in a depot only the source holds,
    #   while the source's position inherits, is cleared.
    # - A differing effective set where both hold refuses as
    #   position_buckets_mismatch naming the depot.
    test "an override is carried, dropped or cleared so every position keeps its set", ctx do
      worked_example!(ctx)
      d4 = depot!(ctx.main, ctx.c1, "Broker D")
      buy!(ctx, d4, ctx.c1, ctx.source, "1", "100.00", ~D[2025-02-20])

      {:ok, long} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Long term"})
      {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})

      for depot <- [ctx.d1, ctx.d2, d4],
          do: :ok = Buckets.set_depot_default_buckets(Actor.owner_ui(), depot, [long.id])

      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.d2, ctx.source, [spec.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.d1, ctx.source, [long.id])
      :ok = Buckets.set_position_override(Actor.owner_ui(), d4, ctx.target, [spec.id])

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

      assert plan_of(preview, ctx.d2) == :carry
      assert plan_of(preview, ctx.d1) == :drop_redundant
      assert plan_of(preview, d4) == :clear_target

      merge!(ctx, false, preview)

      assert Buckets.effective_position_buckets(ctx.d2.id, ctx.target.id) == [spec.id]
      assert Buckets.effective_position_buckets(ctx.d1.id, ctx.target.id) == [long.id]
      assert Buckets.effective_position_buckets(d4.id, ctx.target.id) == [long.id]
      assert Buckets.position_override(d4.id, ctx.target.id) == :inherit
      assert Buckets.position_override(ctx.d1.id, ctx.target.id) == :inherit
    end

    test "a differing effective set where both hold refuses, naming the depot", ctx do
      worked_example!(ctx)
      {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.d1, ctx.source, [spec.id])

      detail = refused!(ctx, :position_buckets_mismatch)
      assert detail =~ "Broker A"
      refute detail =~ "Broker B"

      spec_id = spec.id

      assert [
               %{
                 securities_account_name: "Broker A",
                 source_buckets: [^spec_id],
                 target_buckets: []
               }
             ] =
               refused_guard!(ctx, :position_buckets_mismatch).positions
    end
  end

  describe "journal, hashes and the record (§3, §12, §13, §16 invariants 4 and 11)" do
    # User story:
    # As the maintainer auditing a security merge,
    # I want every row it moved or deleted journaled exactly once, each
    # override change as its one aggregate entry, and nothing removed by a
    # cascade,
    # so that the journal and the merge record reconstruct what happened.
    #
    # Acceptance criteria:
    # - Each moved or deleted transaction has exactly one journal entry under
    #   the merge's actor; unchanged rows have none.
    # - The collapsed split is deleted and journaled like a collapsed pair,
    #   and listed in the manifest with its reason.
    # - The carried override is one position_bucket_override update on the
    #   target's position and one delete on the source's; the source one
    #   security delete; the record one merge_record create — nothing else.
    # - No row disappears that the manifest does not list, and no research
    #   note or rule version is touched.
    test "one entry per touched row, one per aggregate, nothing else", ctx do
      rows = worked_example!(ctx)
      {:ok, spec} = Buckets.create_bucket(Actor.owner_ui(), %{name: "Speculative"})
      :ok = Buckets.set_position_override(Actor.owner_ui(), ctx.d2, ctx.source, [spec.id])
      untouched = buy!(ctx, ctx.d1, ctx.c1, ctx.target, "1", "100.00", ~D[2025-12-01])
      other = security!("Other Co")
      note!(other)
      rule!(ctx.main, other)
      notes_before = Repo.all(from(n in SecurityNote, order_by: n.id))
      versions_before = Repo.all(from(v in PolicyRuleVersion, order_by: v.id))
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
               Enum.sort([rows.s_div.id, rows.s_pair.id, rows.s_split.id])

      assert %{"reason" => "collapsed_split", "superseded_by" => superseded} =
               Enum.find(
                 record.manifest["transactions"]["deleted"],
                 &(&1["id"] == rows.s_split.id)
               )

      assert superseded == rows.t_split_main.id

      moved = Enum.map(record.manifest["transactions"]["moved"], & &1["id"])
      assert Enum.sort(moved) == Enum.sort([rows.s_buy_a.id, rows.s_buy_b.id, rows.s_sell.id])
      assert Enum.sort(transaction_ids) == Enum.sort(Enum.map(deleted ++ moved, &to_string/1))

      assert Repo.aggregate(Transaction, :count) == count_before - length(deleted)
      assert Enum.all?(entries, &(&1.actor_label == "synthetic-agent"))

      by_type = Enum.frequencies_by(entries, &{&1.resource_type, &1.operation})

      assert Map.drop(by_type, [{"transaction", :update}, {"transaction", :delete}]) == %{
               {"position_bucket_override", :update} => 1,
               {"position_bucket_override", :delete} => 1,
               {"security", :delete} => 1,
               {"merge_record", :create} => 1
             }

      assert record.manifest["position_bucket_overrides"]["carried"] == [
               %{"securities_account_id" => ctx.d2.id, "bucket_ids" => [spec.id]}
             ]

      assert Repo.all(from(n in SecurityNote, order_by: n.id)) == notes_before
      assert Repo.all(from(v in PolicyRuleVersion, order_by: v.id)) == versions_before
    end

    # User story:
    # As the operator who merged a duplicate whose history came from an
    # import,
    # I want every hash a collapsed row carried retired under the merge
    # record,
    # so that no writer can book that row again and the set of known hashes
    # only grows.
    #
    # Acceptance criteria:
    # - After the merge, every hash held or retired before is still held or
    #   retired.
    # - Each collapsed pair's source row is retired as collapsed_duplicate,
    #   superseded by its target twin; the collapsed split carries no hash
    #   and retires none.
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
                 {rows.s_div.id, :collapsed_duplicate, rows.t_div.id},
                 {rows.s_pair.id, :collapsed_duplicate, rows.t_pair.id}
               ])
    end

    # User story (#851, ADR-0039, §13 of ADR-0050):
    # As the operator reading a memoised walk right after a merge,
    # I want the merge's writes to bump the derived basis of what each moved
    # row affected,
    # so that no figure computed before the merge is served after it.
    #
    # Acceptance criteria:
    # - Both portfolios' data versions are higher after the merge.
    test "the merge bumps the derived basis of every portfolio it touched", ctx do
      worked_example!(ctx)
      main = DataVersion.portfolio_basis(ctx.main.id)
      main_before = DataVersion.current(main)

      merge!(ctx, false)

      assert DataVersion.current(main) > main_before
    end

    # User story:
    # As the agent whose merge call timed out,
    # I want a retry of the same pair to answer the merge that happened, and
    # a merge of the same source into another security refused,
    # so that a retry never merges twice.
    #
    # Acceptance criteria:
    # - A retry answers the original record and journals nothing.
    # - A merge or preview of the merged source into another security
    #   answers already_merged with the record and writes nothing.
    test "a retry answers the original record; another target is already_merged", ctx do
      worked_example!(ctx)
      record = merge!(ctx, false)
      other = security!("Fund X")
      mark = journal_mark()

      assert {:ok, %MergeRecord{id: id}, :already_applied} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: record.plan_digest,
                 collapse_key_equal: false
               })

      assert id == record.id
      before = fingerprint()

      assert {:error, {:already_merged, %MergeRecord{id: ^id}}} =
               Lifecycle.merge_security(agent(), ctx.source.id, other.id, %{
                 plan_digest: record.plan_digest,
                 collapse_key_equal: false
               })

      assert {:error, {:already_merged, %MergeRecord{id: ^id}}} =
               Lifecycle.preview_security_merge(ctx.source.id, other.id)

      assert entries_since(mark) == []
      assert fingerprint() == before
    end
  end

  describe "refusals (§9 guards, §16 invariant 13)" do
    # User story:
    # As the operator about to merge the wrong pair of securities,
    # I want every merge the guards forbid refused with a named reason before
    # anything is written,
    # so that a security of another currency, another benchmark flag or
    # another quote basis, a retired target, the security itself or a
    # vanished one can never be merged.
    #
    # Acceptance criteria:
    # - Each guard answers {:refused, guards} naming its code, on the preview
    #   and on the apply, and every table is unchanged.
    # - An unknown source answers :not_found.
    test "each guard refuses with its code and writes nothing", ctx do
      worked_example!(ctx)
      dollar = security!("Fund X", "USD")
      benchmark = security!("Fund X")

      {:ok, benchmark} =
        Catalog.update_security(Actor.owner_ui(), benchmark, %{is_benchmark: true})

      retired = security!("Fund X")
      {:ok, retired} = Catalog.update_security(Actor.owner_ui(), retired, %{is_retired: true})
      gone = security!("Fund X")
      {:ok, _} = Catalog.delete_security(Actor.owner_ui(), gone)

      cases = [
        {ctx.source.id, :same_security},
        {dollar.id, :currency_mismatch},
        {benchmark.id, :benchmark_mismatch},
        {retired.id, :retired_target},
        {gone.id, :not_live}
      ]

      for {target_id, code} <- cases do
        assert code in refusal_codes(ctx.source.id, target_id), "#{code}"
      end

      assert {:error, :not_found} = Lifecycle.preview_security_merge(gone.id, ctx.target.id)
    end

    # User story:
    # As the operator whose source security has quotes of another basis,
    # I want the merge refused while the two treat their quotes differently,
    # so that the moved quotes never change their basis silently.
    #
    # Acceptance criteria:
    # - A source with quotes and a target that treats its synced quotes as
    #   raw refuses as quote_basis_mismatch; without source quotes the flag
    #   is not compared.
    test "a differing quote basis refuses while the source has quotes", ctx do
      worked_example!(ctx)

      {:ok, _} =
        Catalog.update_security(Actor.owner_ui(), ctx.target, %{treat_quotes_as_raw: true})

      refute :quote_basis_mismatch in refusal_codes(ctx.source.id, ctx.target.id)

      quote!(ctx.source, ~D[2025-12-01], "60.00")
      assert :quote_basis_mismatch in refusal_codes(ctx.source.id, ctx.target.id)
    end

    # User story:
    # As the operator whose source security carries research notes or is
    # read by a policy rule,
    # I want the merge refused naming them, with "merge the other way"
    # offered only when that merge would really pass,
    # so that an append-only note or an in-force rule version never moves
    # or vanishes (ADR-0044 §3, ADR-0049 §8).
    #
    # Acceptance criteria:
    # - Notes on the source refuse as research_notes; the remedy is to merge
    #   the other way while the reverse merge passes its guards.
    # - A rule version naming the source refuses as policy_rules, naming the
    #   rule and its status, in ADR-0049 §8's shape.
    # - With notes on both, the remedy is to keep both; merging the other way
    #   is not offered.
    # - A mergeable preview reports whether the reverse merge would pass.
    test "notes and rules on the source refuse, naming the reverse only when it is real", ctx do
      worked_example!(ctx)

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      assert preview.reverse == %{mergeable: true, refused: []}

      note!(ctx.source)
      guard = refused_guard!(ctx, :research_notes)
      assert guard.remedy == :merge_other_way
      assert guard.detail =~ "merge the other way"
      assert {:ok, _reverse} = Lifecycle.preview_security_merge(ctx.target.id, ctx.source.id)

      note!(ctx.target)
      guard = refused_guard!(ctx, :research_notes)
      assert guard.remedy == :keep_both
      refute guard.detail =~ "merge the other way"

      ctx = fresh_pair!(ctx, "Fund Y")
      worked_example!(ctx)
      rule = rule!(ctx.main, ctx.source)
      guard = refused_guard!(ctx, :policy_rules)
      assert guard.detail =~ "Fund Y at most 12 %"
      assert [%{id: rule_id, name: "Fund Y at most 12 %", status: _status}] = guard.policy_rules
      assert rule_id == rule.id
      assert guard.remedy == :merge_other_way
    end

    # User story:
    # As the operator merging a live duplicate into a security I retired,
    # I want the refusal to say that merging the other way would pass,
    # so that I keep the live one without guessing.
    #
    # Acceptance criteria:
    # - A retired target with a live source refuses as retired_target with
    #   the remedy to merge the other way; the reverse preview passes.
    test "a retired target names the reverse merge", ctx do
      worked_example!(ctx)
      {:ok, _} = Catalog.update_security(Actor.owner_ui(), ctx.target, %{is_retired: true})

      guard = refused_guard!(ctx, :retired_target)
      assert guard.remedy == :merge_other_way
      assert {:ok, _reverse} = Lifecycle.preview_security_merge(ctx.target.id, ctx.source.id)
    end
  end

  describe "consent (§8, §10)" do
    # User story:
    # As the operator who approved a preview an hour ago,
    # I want the merge refused when a booking of either security changed
    # since, with the fresh preview,
    # so that the figures applied are always the ones I approved.
    #
    # Acceptance criteria:
    # - An apply whose digest no longer matches answers {:plan_changed,
    #   fresh_preview} and writes nothing; the fresh digest applies.
    # - Without a digest the apply answers {:invalid, :plan_digest, _}; with
    #   key-equal pairs and no collapse_key_equal it answers
    #   {:choice_required, :collapse_key_equal, 2}; neither writes anything.
    # - Without key-equal pairs no choice is required.
    test "a stale digest answers plan_changed with the fresh preview, and writes nothing", ctx do
      rows = worked_example!(ctx)
      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

      {:ok, _} = Ledger.update_transaction(agent(), rows.s_buy_b, %{price: "106.00"})
      before = fingerprint()

      assert {:error, {:plan_changed, fresh}} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest,
                 collapse_key_equal: false
               })

      assert fresh.plan_digest != preview.plan_digest
      assert fingerprint() == before

      assert {:error, {:invalid, :plan_digest, _}} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 collapse_key_equal: false
               })

      assert {:error, {:choice_required, :collapse_key_equal, 2}} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: fresh.plan_digest
               })

      assert fingerprint() == before

      assert {:ok, _record, :applied} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: fresh.plan_digest,
                 collapse_key_equal: false
               })
    end

    test "without key-equal pairs, no choice is required", ctx do
      buy!(ctx, ctx.d1, ctx.c1, ctx.source, "2", "40.00", ~D[2025-01-02])
      buy!(ctx, ctx.d1, ctx.c1, ctx.target, "3", "40.00", ~D[2025-01-02])

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      refute preview.choice_required
      assert preview.outcomes[false] == preview.outcomes[true]

      assert {:ok, _record, :applied} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: preview.plan_digest
               })

      assert held(ctx.d1, ctx.target) == dec("5")
    end

    # User story:
    # As the maintainer of the digest,
    # I want one pair to have one digest whatever the operator will choose,
    # and any change of a row or a split to change it,
    # so that consent covers exactly what the preview showed.
    #
    # Acceptance criteria:
    # - Two previews of an unchanged pair carry the same digest.
    # - A new booking of either security changes it; so does a new split.
    test "the digest is stable for one pair and moves with its rows", ctx do
      worked_example!(ctx)
      {:ok, first} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      {:ok, again} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      assert first.plan_digest == again.plan_digest

      buy!(ctx, ctx.d1, ctx.c1, ctx.target, "1", "100.00", ~D[2026-02-01])
      {:ok, changed} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      refute changed.plan_digest == first.plan_digest
    end
  end

  # --- the worked example --------------------------------------------------------

  # Fund X twice (the source a duplicate of the target), in two portfolios:
  #
  #   Main    Broker A  target: buy 10 @ 100, dividend 50, buy 2 @ 120, sell 4 @ 70
  #                     source: buy 5 @ 110, dividend 50, buy 2 @ 120, sell 2 @ 130
  #           Broker B  source: buy 3 @ 105
  #   Second  Broker C  target: buy 4 @ 100
  #   splits  2:1 on 2025-09-01: the target in Main and Second, the source in
  #           Main (collapses with the target's)
  #   pairs   the dividend and the buy of 2025-06-30 and 2025-07-01 are
  #           booked once on each security
  defp worked_example!(ctx, opts \\ []) do
    hashed? = Keyword.get(opts, :hashed, false)
    hash = fn label -> if hashed?, do: "synthetic-security-hash-#{ctx.source.id}-#{label}" end
    %{c1: c1, c2: c2, d1: d1, d2: d2, d3: d3, source: s, target: t} = ctx

    cash_book!(ctx.main, c1, "deposit", "10000.00", ~D[2025-01-02])
    cash_book!(ctx.second, c2, "deposit", "5000.00", ~D[2025-01-02])

    rows = %{
      t_buy_a: buy!(ctx, d1, c1, t, "10", "100.00", ~D[2025-01-10], hash.("t-buy-a")),
      t_buy_b: buy!(ctx, d3, c2, t, "4", "100.00", ~D[2025-01-12], hash.("t-buy-b")),
      t_div: dividend!(ctx.main, d1, c1, t, "50.00", ~D[2025-06-30], hash.("t-div")),
      t_pair: buy!(ctx, d1, c1, t, "2", "120.00", ~D[2025-07-01], hash.("t-pair")),
      s_buy_a: buy!(ctx, d1, c1, s, "5", "110.00", ~D[2025-02-10], hash.("s-buy-a")),
      s_buy_b: buy!(ctx, d2, c1, s, "3", "105.00", ~D[2025-02-12], hash.("s-buy-b")),
      s_div: dividend!(ctx.main, d1, c1, s, "50.00", ~D[2025-06-30], hash.("s-div")),
      s_pair: buy!(ctx, d1, c1, s, "2", "120.00", ~D[2025-07-01], hash.("s-pair")),
      s_sell: trade!(ctx, "sell", {d1, c1}, s, {"2", "130.00"}, ~D[2025-08-01], hash.("s-sell"))
    }

    splits = %{
      t_split_main: split!(ctx.main, t, ~D[2025-09-01], {2, 1}),
      t_split_second: split!(ctx.second, t, ~D[2025-09-01], {2, 1}),
      s_split: split!(ctx.main, s, ~D[2025-09-01], {2, 1})
    }

    t_sell = trade!(ctx, "sell", {d1, c1}, t, {"4", "70.00"}, ~D[2025-10-01], hash.("t-sell"))

    rows |> Map.merge(splits) |> Map.put(:t_sell, t_sell)
  end

  # A second pair of securities, for a test that merges twice. Its own name:
  # a name-only identity shared with the first pair's survivor would be
  # ambiguous after the merge, and the resolvability precondition refuses
  # that (§9).
  defp fresh_pair!(ctx, name),
    do: %{ctx | target: security!(name), source: security!(name)}

  # --- world ------------------------------------------------------------------------

  defp portfolio!(name) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: name, base_currency_code: "EUR"})

    portfolio
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

  defp security!(name, currency \\ "EUR") do
    {:ok, security} =
      Catalog.create_security(Actor.owner_ui(), %{
        name: name,
        currency_code: currency,
        asset_class: "etf"
      })

    security
  end

  defp cash_book!(portfolio, cash, type, amount, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
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

  defp trade!(_ctx, type, {depot, cash}, security, {quantity, price}, date, hash) do
    create!(
      %{
        portfolio_id: depot.portfolio_id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: type,
        date: date,
        quantity: quantity,
        price: price,
        currency_code: security.currency_code
      },
      hash
    )
  end

  defp dividend!(portfolio, depot, cash, security, amount, date, hash) do
    create!(
      %{
        portfolio_id: portfolio.id,
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

  # One split row in one portfolio, booked through the ledger's own writer
  # (the split flow fans out through the same call per portfolio), so a test
  # places each row where it needs it.
  defp split!(portfolio, security, date, {numerator, denominator}) do
    {:ok, tx} =
      Ledger.create_transaction(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        security_id: security.id,
        type: "split",
        date: date,
        currency_code: security.currency_code,
        split_ratio_numerator: numerator,
        split_ratio_denominator: denominator
      })

    tx
  end

  # Written the way the Portfolio Performance importer writes a row
  # (`Imports.Applier`).
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

  defp quote!(security, date, close) do
    {:ok, _} =
      Catalog.upsert_quotes(Actor.owner_ui(), security.id, [
        %{"date" => Date.to_iso8601(date), "close" => close}
      ])

    :ok
  end

  defp note!(security) do
    {:ok, note} =
      Knowledge.append_note(agent(), %{
        security_id: security.id,
        author: "agent",
        kind: "evidence",
        body: "a synthetic finding that must never vanish",
        source_quality: "primary",
        as_of: ~D[2026-08-01]
      })

    note
  end

  defp rule!(portfolio, security) do
    {:ok, rule} =
      PolicyRules.create_rule(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: "#{security.name} at most 12 %",
        version: %{
          subject_type: "security",
          security_id: security.id,
          measure: "weight",
          kind: "cap",
          threshold: "12",
          severity: "hard"
        }
      })

    rule
  end

  defp merge!(ctx, collapse?, preview \\ nil) do
    {:ok, preview} =
      if preview,
        do: {:ok, preview},
        else: Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

    {:ok, record, :applied} =
      Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest,
        collapse_key_equal: collapse?
      })

    record
  end

  # Refused on the preview and the apply with `code` among the failed guards,
  # every table unchanged: the failed guard of that code.
  defp refused_guard!(ctx, code) do
    before = fingerprint()

    assert {:error, {:refused, guards}} =
             Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

    assert code in failed(guards), "preview #{code}: #{inspect(failed(guards))}"

    assert {:error, {:refused, apply_guards}} =
             Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
               plan_digest: "sha256:whatever",
               collapse_key_equal: false
             })

    assert code in failed(apply_guards), "apply #{code}: #{inspect(failed(apply_guards))}"
    assert fingerprint() == before

    Enum.find(guards, &(&1.code == code and not &1.passed))
  end

  defp refused!(ctx, code), do: refused_guard!(ctx, code).detail

  defp refusal_codes(source_id, target_id) do
    before = fingerprint()

    codes =
      case Lifecycle.preview_security_merge(source_id, target_id) do
        {:error, {:refused, guards}} -> failed(guards)
        {:ok, _preview} -> []
      end

    case Lifecycle.merge_security(agent(), source_id, target_id, %{
           plan_digest: "sha256:whatever",
           collapse_key_equal: false
         }) do
      {:error, {:refused, guards}} -> assert failed(guards) == codes
      {:error, {:plan_changed, _fresh}} -> assert codes == []
    end

    assert fingerprint() == before
    codes
  end

  # --- oracles ------------------------------------------------------------------------

  # `{date, depot_id} => quantity`: at the end of every date either security
  # has a row on, and today, the fold of the target's rows under its own
  # splits plus the fold of the source's kept rows under its own splits —
  # from the ledger's own position fold, per depot.
  defp daily_sums(ctx, collapsed_ids) do
    t_rows = security_rows(ctx.target)
    s_rows = ctx.source |> security_rows() |> Enum.reject(&(&1.id in collapsed_ids))
    depots = depots_of(t_rows ++ s_rows)
    dates = Enum.uniq([Clock.today() | Enum.map(t_rows ++ s_rows, & &1.date)])

    for date <- dates, depot <- depots, into: %{} do
      target = at(t_rows, date) |> Map.get({depot, ctx.target.id}, dec("0"))
      source = at(s_rows, date) |> Map.get({depot, ctx.source.id}, dec("0"))
      {{date, depot}, n(Decimal.add(target, source))}
    end
  end

  defp merged_quantities(ctx, keys) do
    rows = security_rows(ctx.target)

    Map.new(keys, fn {date, depot} = key ->
      {key, n(Map.get(at(rows, date), {depot, ctx.target.id}, dec("0")))}
    end)
  end

  defp security_rows(security),
    do: Repo.all(from(t in Transaction, where: t.security_id == ^security.id))

  defp depots_of(rows) do
    rows
    |> Enum.flat_map(&[&1.securities_account_id, &1.counter_securities_account_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp at(rows, date),
    do: rows |> Enum.filter(&(Date.compare(&1.date, date) != :gt)) |> Positions.calculate()

  defp held(depot, security) do
    Ledger.positions_for_portfolio(depot.portfolio_id)
    |> Map.get({depot.id, security.id}, dec("0"))
    |> n()
  end

  defp stored_figures(depot_id, security_id) do
    depot = Portfolios.get_securities_account(depot_id)

    row =
      depot.portfolio_id
      |> Ledger.holdings_for_portfolio(prices: %{})
      |> Enum.find(&(&1.securities_account_id == depot_id and &1.security_id == security_id))

    {n(row.quantity), n(row.cost_basis)}
  end

  defp balance(account),
    do: Map.get(Ledger.cash_balances(), account.id, dec("0")) |> Decimal.normalize()

  defp position(outcome, depot),
    do: Enum.find(outcome.positions, &(&1.securities_account_id == depot.id))

  defp quantities(outcome, depot) do
    position = position(outcome, depot)
    quantity = fn figures -> figures && n(figures.quantity) end
    {quantity.(position.source), quantity.(position.target), quantity.(position.after)}
  end

  defp plan_of(preview, depot) do
    %{action: action} =
      Enum.find(preview.position_buckets, &(&1.securities_account_id == depot.id))

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
