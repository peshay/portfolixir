defmodule Portfolixir.Lifecycle.MergeRaceTest do
  # ADR-0050 §10, "every race ends in a clean answer, never a 500", for the
  # windows every merge kind leaves between two reads (the closing act's
  # patch-coverage pass, #328; risk-tier: the merge record and import
  # idempotency, ADR-0036). Each merge kind — cash account, depot, security —
  # answers:
  #
  #   * a source another writer merged into the same target between the
  #     apply's pre-check and its lock: that merge's record, as already
  #     applied;
  #   * a source another writer merged elsewhere in that window:
  #     already_merged, naming that record;
  #   * a source another writer deleted in that window: not_found;
  #   * a stale digest whose source another writer merged away before the
  #     fresh preview was read: the refusal that preview gives, never a
  #     preview of a source that no longer exists;
  #
  # and in every case the apply itself writes nothing. The security merge
  # also refuses to go on when a depot it did not lock took a first booking
  # of the source between its depot read and its security lock.
  #
  # The other writer runs at the exact point of the window through
  # `Portfolixir.Interleave`: the read that opens the window has returned,
  # the next one has not been sent. Outside the merge's transaction it
  # commits as another connection's would; inside it, its write is rolled
  # back with the merge, which is what the last test states.
  #
  # Every name and amount is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Interleave
  alias Portfolixir.Journal
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Lifecycle.MergeRecord
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.CashAccount
  alias Portfolixir.Portfolios.SecuritiesAccount
  alias Portfolixir.WorldFixtures

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  @kinds [:cash_account, :securities_account, :security]

  # A digest no preview of these worlds carries.
  @approved "sha256:" <> String.duplicate("0", 64)

  for kind <- @kinds do
    describe "#{kind}: another writer between the pre-check and the lock (§10)" do
      @describetag kind: kind

      # User story:
      # As the agent retrying a merge the operator also started on the
      # screen,
      # I want the apply that lost the race to answer the merge that won it,
      # so that I report the one record there is instead of a server error.
      #
      # Acceptance criteria:
      # - Another merge of the source into the same target commits after the
      #   apply's pre-check read no record: the apply answers that record as
      #   :already_applied.
      # - The apply journals nothing and writes no second record.
      test "a merge into the same target answers its record as already applied", ctx do
        world = world(ctx.kind)
        {:ok, preview} = preview(world, world.target)

        {result, won} =
          interleaved(&first_merge_record_read?/1, fn -> merge!(world, world.target) end, fn ->
            apply_merge(world, world.target, preview.plan_digest)
          end)

        assert %MergeRecord{} = won.record
        assert {:ok, record, :already_applied} = result
        assert record.id == won.record.id
        assert journal_mark() == won.mark
        assert merge_records(ctx.kind, world.source.id) == [won.record.id]
      end

      # User story:
      # As the agent whose approved merge another writer overtook with a
      # merge of the same source into a third row,
      # I want the refusal to name that merge,
      # so that I tell the operator where the source went.
      #
      # Acceptance criteria:
      # - The apply answers {:already_merged, record} naming the other
      #   target, and writes nothing.
      test "a merge elsewhere answers already_merged, naming that record", ctx do
        world = world(ctx.kind, twin: :other)

        # The digest the operator approved is never read: the source is gone
        # before the plan is.
        {result, won} =
          interleaved(&first_merge_record_read?/1, fn -> merge!(world, world.other) end, fn ->
            apply_merge(world, world.target, @approved)
          end)

        assert {:error, {:already_merged, record}} = result
        assert record.id == won.record.id
        assert record.target_id == world.other.id
        assert journal_mark() == won.mark
        assert merge_records(ctx.kind, world.source.id) == [won.record.id]
      end

      # User story:
      # As the agent whose approved merge lost its source to a delete,
      # I want the apply to answer not_found,
      # so that I stop instead of retrying a merge of nothing.
      #
      # Acceptance criteria:
      # - The source is deleted after the apply's pre-check: the apply
      #   answers {:error, :not_found}, writes no record and journals
      #   nothing.
      test "a deleted source answers not_found", ctx do
        world = world(ctx.kind, source_rows?: false)
        {:ok, preview} = preview(world, world.target)

        {result, deleted} =
          interleaved(&first_merge_record_read?/1, fn -> delete!(world) end, fn ->
            apply_merge(world, world.target, preview.plan_digest)
          end)

        assert deleted.record == :deleted
        assert {:error, :not_found} = result
        assert journal_mark() == deleted.mark
        assert merge_records(ctx.kind, world.source.id) == []
      end
    end

    describe "#{kind}: another writer between a stale digest and the fresh preview (§10)" do
      @describetag kind: kind

      # User story:
      # As the agent whose approval went stale while another writer merged
      # the source away,
      # I want the refusal the fresh preview gives rather than a preview,
      # so that I never show the operator a plan for a source that is gone.
      #
      # Acceptance criteria:
      # - A stale digest rolls the apply back; the source is merged away
      #   before the fresh preview is read: the apply answers
      #   {:already_merged, record} naming that merge, and writes nothing.
      test "the fresh preview's refusal is the answer", ctx do
        world = world(ctx.kind)

        {result, won} =
          interleaved(&rollback?/1, fn -> merge!(world, world.target) end, fn ->
            apply_merge(world, world.target, @approved)
          end)

        assert {:error, {:already_merged, record}} = result
        assert record.id == won.record.id
        assert journal_mark() == won.mark
        assert merge_records(ctx.kind, world.source.id) == [won.record.id]
      end
    end
  end

  describe "security: a depot that took a first booking under the merge (§10)" do
    # User story:
    # As the operator booking a buy of a security while an agent merges it,
    # I want the merge to stop rather than re-point a booking in a depot it
    # never locked,
    # so that the position the merge writes is the one it planned.
    #
    # Acceptance criteria:
    # - A depot books its first row of the source between the merge's depot
    #   lock and its security lock: the apply answers {:plan_changed,
    #   fresh_preview}, writes no record and journals nothing. (The booking,
    #   written inside the merge's transaction here, is rolled back with it.
    #   The depot re-read after the security lock and the digest comparison
    #   both answer this way, so the test pins the answer, not which of the
    #   two gives it.)
    test "the apply answers plan_changed and writes nothing" do
      world = world(:security)
      {:ok, preview} = preview(world, world.target)
      late = WorldFixtures.add_depot(world.portfolio, cash_name: "Late cash", depot_name: "Late")
      mark = journal_mark()

      {result, booked} =
        interleaved(&depot_lock?/1, fn -> buy!(world.portfolio, late, world.source) end, fn ->
          apply_merge(world, world.target, preview.plan_digest)
        end)

      assert %{id: _} = booked.record
      assert {:error, {:plan_changed, fresh}} = result
      assert fresh.plan_digest == preview.plan_digest
      assert journal_mark() == mark
      assert merge_records(:security, world.source.id) == []
      assert %Security{} = Repo.get(Security, world.source.id)
    end
  end

  # --- the interleaving ---------------------------------------------------------

  # `Portfolixir.Interleave.run/3`, answering the other writer's result with
  # the journal's last id after it: whatever the call journals later shows.
  defp interleaved(at?, other_writer, call) do
    Interleave.run(at?, fn -> %{record: other_writer.(), mark: journal_mark()} end, call)
  end

  defp first_merge_record_read?(%{source: "merge_records"}), do: true
  defp first_merge_record_read?(_metadata), do: false

  defp rollback?(%{query: "rollback"}), do: true
  defp rollback?(_metadata), do: false

  defp depot_lock?(%{source: "securities_accounts", query: query}),
    do: query =~ "FOR NO KEY UPDATE"

  defp depot_lock?(_metadata), do: false

  # --- the three kinds ---------------------------------------------------------

  # A source, the target it is merged into and another row it could be
  # merged into instead, in one portfolio; the source holds a booking unless
  # `source_rows?: false` (a source to delete). For securities, `twin:` names
  # the one (`:target` or `:other`) that shares the source's name, so a merge
  # into it passes the resolvability precondition (§9).
  defp world(kind, opts \\ []) do
    {:ok, portfolio} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{
        name: "Race World #{System.unique_integer([:positive])}",
        base_currency_code: "EUR"
      })

    kind
    |> rows(portfolio, Keyword.get(opts, :source_rows?, true), Keyword.get(opts, :twin, :target))
    |> Map.merge(%{kind: kind, portfolio: portfolio})
  end

  defp rows(:cash_account, portfolio, source_rows?, _twin) do
    [target, source, other] =
      for name <- ["Savings", "Savings (old)", "Savings (spare)"], do: cash!(portfolio, name)

    if source_rows?, do: deposit!(portfolio, source)
    %{target: target, source: source, other: other}
  end

  defp rows(:securities_account, portfolio, source_rows?, _twin) do
    cash = cash!(portfolio, "Broker cash")

    [target, source, other] =
      for name <- ["Depot 1", "Depot 2", "Depot 3"], do: depot!(portfolio, cash, name)

    if source_rows?,
      do: buy!(portfolio, %{depot: source, cash: cash}, security!("Synthetic Race ETF"))

    %{target: target, source: source, other: other}
  end

  defp rows(:security, portfolio, source_rows?, twin) do
    books = WorldFixtures.add_depot(portfolio, cash_name: "Broker cash", depot_name: "Depot 1")
    name = fn role -> if role == twin, do: "Synthetic Race Fund", else: "Synthetic Race Bond" end
    [target, other] = [security!(name.(:target)), security!(name.(:other))]
    source = security!("Synthetic Race Fund")

    if source_rows?, do: buy!(portfolio, books, source)
    %{target: target, source: source, other: other}
  end

  defp preview(%{kind: :cash_account} = world, target),
    do: Lifecycle.preview_cash_merge(world.source.id, target.id)

  defp preview(%{kind: :securities_account} = world, target),
    do: Lifecycle.preview_depot_merge(world.source.id, target.id)

  defp preview(%{kind: :security} = world, target),
    do: Lifecycle.preview_security_merge(world.source.id, target.id)

  defp apply_merge(%{kind: :cash_account} = world, target, digest),
    do: Lifecycle.merge_cash_account(agent(), world.source.id, target.id, consent(digest))

  defp apply_merge(%{kind: :securities_account} = world, target, digest),
    do: Lifecycle.merge_depot(agent(), world.source.id, target.id, consent(digest))

  defp apply_merge(%{kind: :security} = world, target, digest),
    do: Lifecycle.merge_security(agent(), world.source.id, target.id, consent(digest))

  defp consent(digest), do: %{plan_digest: digest, collapse_key_equal: false}

  defp merge!(world, target) do
    {:ok, preview} = preview(world, target)
    {:ok, record, :applied} = apply_merge(world, target, preview.plan_digest)
    record
  end

  defp delete!(%{kind: :cash_account, source: source}) do
    {:ok, _} = Portfolios.delete_cash_account(Actor.owner_ui(), source)
    :deleted
  end

  defp delete!(%{kind: :securities_account, source: source}) do
    {:ok, _} = Portfolios.delete_securities_account(Actor.owner_ui(), source)
    :deleted
  end

  defp delete!(%{kind: :security, source: source}) do
    {:ok, _} = Catalog.delete_security(Actor.owner_ui(), source)
    :deleted
  end

  # --- world --------------------------------------------------------------------

  defp cash!(portfolio, name) do
    {:ok, %CashAccount{} = cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: portfolio.id,
        name: name,
        currency_code: "EUR"
      })

    cash
  end

  defp depot!(portfolio, cash, name) do
    {:ok, %SecuritiesAccount{} = depot} =
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

  defp deposit!(portfolio, cash) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        cash_account_id: cash.id,
        type: "deposit",
        date: ~D[2025-01-02],
        gross_amount: "250.00",
        currency_code: "EUR"
      })

    tx
  end

  defp buy!(portfolio, %{depot: depot, cash: cash}, security) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: ~D[2025-01-10],
        quantity: "4",
        price: "25.00",
        currency_code: "EUR"
      })

    tx
  end

  # --- oracles ------------------------------------------------------------------

  defp merge_records(kind, source_id) do
    Repo.all(
      from(m in MergeRecord,
        where: m.kind == ^kind and m.source_id == ^source_id,
        select: m.id
      )
    )
  end

  defp journal_mark do
    Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0
  end
end
