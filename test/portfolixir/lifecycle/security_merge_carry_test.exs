defmodule Portfolixir.Lifecycle.SecurityMergeCarryTest do
  # ADR-0050 §9's second half for the security merge (L4b, #608; risk-tier:
  # quantity identity and import idempotency, ADR-0036): what a source
  # carries besides its bookings — its quotes (gap-filled), its configuration
  # (category assignments, position targets across active, draft and archived
  # plans, security events, identifier aliases) and its identifiers (the
  # required identity choice, WKN, ticker and feed adopted where the target
  # lacks them, name, asset class and logo following the target) — and the
  # resolvability precondition. Written before the code, with the §16
  # invariants they pin:
  #
  #   * 11 — every moved or deleted row of a journaled table has exactly one
  #     journal entry; every moved or dropped quote appears in the manifest
  #     and in no journal entry; nothing references the source afterwards;
  #   * 13 — each refusal answers its code and leaves every table unchanged;
  #   * 14 — a source created by a name-only import and given a ticker
  #     afterwards is refused while its imported name would no longer
  #     resolve (the positive half, both identities resolving to the target
  #     after a merge, is in security_merge_reimport_test.exs).
  #
  # Every name, amount, identifier and quote is synthetic.
  use Portfolixir.DataCase, async: true

  alias Portfolixir.Actor
  alias Portfolixir.Catalog
  alias Portfolixir.Catalog.IdentifierAlias
  alias Portfolixir.Catalog.Quote, as: SecurityQuote
  alias Portfolixir.Catalog.Quotes
  alias Portfolixir.Catalog.Security
  alias Portfolixir.Classifications
  alias Portfolixir.Classifications.Assignment
  alias Portfolixir.Clock
  alias Portfolixir.Derived.DataVersion
  alias Portfolixir.Journal
  alias Portfolixir.Knowledge.Events
  alias Portfolixir.Ledger
  alias Portfolixir.Lifecycle
  alias Portfolixir.Portfolios
  alias Portfolixir.Portfolios.Target
  alias Portfolixir.Portfolios.Targets

  # Synthetic ISINs whose check digits agree (ISO 6166).
  @isin_old "XS00EXOLDA04"
  @isin_source "XS00EXSRCE01"
  @isin_target "XS00EXTGTF03"

  defp agent, do: Actor.api_token_rw("synthetic-agent")

  setup do
    {:ok, main} =
      Portfolios.create_portfolio(Actor.owner_ui(), %{name: "Main", base_currency_code: "EUR"})

    {:ok, cash} =
      Portfolios.create_cash_account(Actor.owner_ui(), %{
        portfolio_id: main.id,
        name: "Main cash",
        currency_code: "EUR"
      })

    {:ok, depot} =
      Portfolios.create_securities_account(Actor.owner_ui(), %{
        portfolio_id: main.id,
        cash_account_id: cash.id,
        name: "Broker A"
      })

    target = security!(%{name: "Carry Fund"})
    source = security!(%{name: "Carry Fund"})
    buy!(main, depot, cash, target, "10", "100.00", ~D[2025-01-10])
    buy!(main, depot, cash, source, "4", "110.00", ~D[2025-02-10])

    %{main: main, cash: cash, depot: depot, target: target, source: source}
  end

  describe "quotes (§9 gap-fill)" do
    # User story:
    # As the operator merging a duplicate security that carries its own
    # price history,
    # I want its quotes on the days the security I keep has none moved over,
    # and on a day both have one the kept security's close to win, with the
    # dropped close recorded and a dropped manual close shown to me first,
    # so that no price I typed vanishes unseen and the kept history is never
    # overwritten.
    #
    # Acceptance criteria:
    # - The preview counts the source's quotes, the ones that move and the
    #   collisions, and lists each collision whose source quote is manual
    #   with both closes.
    # - After the apply the target keeps its own close on each collision
    #   date, and holds the source's quote, with its source, on every other
    #   date.
    # - No quote write is journaled; the manifest lists every moved quote
    #   and every dropped one with its date, close and source and the
    #   target's close that won.
    # - Both securities' quote bases are bumped.
    test "the source's quotes fill the target's gaps; on a collision the target wins", ctx do
      provider!(ctx.target, [{~D[2025-03-03], "50.00"}, {~D[2025-03-04], "51.00"}])
      manual!(ctx.source, [{~D[2025-03-03], "49.50"}, {~D[2025-03-06], "53.25"}])
      provider!(ctx.source, [{~D[2025-03-04], "50.90"}, {~D[2025-03-05], "52.00"}])

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      assert Enum.all?(preview.guards, & &1.passed)

      assert %{source_count: 4, moved_count: 2, collision_count: 2} = preview.quotes

      assert [manual] = preview.quotes.manual_collisions
      assert manual.date == ~D[2025-03-03]
      assert n(manual.source_close) == dec("49.5")
      assert n(manual.target_close) == dec("50")
      assert manual.target_source == "auto"

      t_basis = DataVersion.security_basis(ctx.target.id)
      s_basis = DataVersion.security_basis(ctx.source.id)
      {t_before, s_before} = {DataVersion.current(t_basis), DataVersion.current(s_basis)}
      mark = journal_mark()

      record = merge!(ctx, preview)

      assert stored_quotes(ctx.target) == [
               {~D[2025-03-03], dec("50"), "auto"},
               {~D[2025-03-04], dec("51"), "auto"},
               {~D[2025-03-05], dec("52"), "auto"},
               {~D[2025-03-06], dec("53.25"), "manual"}
             ]

      assert stored_quotes(ctx.source) == []
      refute Enum.any?(entries_since(mark), &(&1.resource_type == "security_quotes"))

      assert Enum.sort(Enum.map(record.manifest["quotes"]["moved"], & &1["date"])) ==
               ["2025-03-05", "2025-03-06"]

      assert Enum.sort_by(record.manifest["quotes"]["dropped"], & &1["date"]) == [
               %{
                 "date" => "2025-03-03",
                 "close" => "49.5",
                 "source" => "manual",
                 "target_close" => "50",
                 "target_source" => "auto"
               },
               %{
                 "date" => "2025-03-04",
                 "close" => "50.9",
                 "source" => "auto",
                 "target_close" => "51",
                 "target_source" => "auto"
               }
             ]

      assert DataVersion.current(t_basis) > t_before
      assert DataVersion.current(s_basis) > s_before
    end

    # User story:
    # As the maintainer of the merge's consent,
    # I want a quote written on either security after the preview to change
    # its digest,
    # so that the quotes the apply moves or drops are the ones the operator
    # saw.
    #
    # Acceptance criteria:
    # - A quote of either security changes the digest; a merge under the old
    #   digest answers plan_changed and writes nothing.
    test "a quote written after the preview changes the plan", ctx do
      {:ok, first} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      provider!(ctx.target, [{~D[2025-03-03], "50.00"}])
      {:ok, second} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      refute second.plan_digest == first.plan_digest
      provider!(ctx.source, [{~D[2025-03-04], "50.00"}])
      before = fingerprint()

      assert {:error, {:plan_changed, _fresh}} =
               Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
                 plan_digest: second.plan_digest
               })

      assert fingerprint() == before
    end
  end

  describe "configuration (§9)" do
    # User story:
    # As the operator whose duplicate security sits in my own classification
    # trees,
    # I want its category assignments moved where the security I keep has
    # none in that tree, and the kept security's to win where it has one,
    # each change listed first,
    # so that my classification survives the merge without a silent
    # re-filing.
    #
    # Acceptance criteria:
    # - The preview lists, per classification of the source, the move or
    #   the drop with both categories.
    # - The source's assignment where the target has none is re-pointed
    #   (the same row, one journaled update); where the target has one, the
    #   source's is deleted (one journaled delete) and the target's stays.
    test "category assignments move where the target has none, else the target's wins", ctx do
      {style, %{"Growth" => growth, "Value" => value}} = tree!("Style", ~w(Growth Value))
      {sector, %{"Tech" => tech}} = tree!("Sector", ~w(Tech Health))
      assign!(ctx.target, style, value)
      assign!(ctx.source, style, growth)
      moved = assign!(ctx.source, sector, tech)

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

      assert Enum.sort_by(preview.configuration.category_assignments, & &1.classification_id) ==
               Enum.sort_by(
                 [
                   %{
                     classification_id: style.id,
                     classification_name: "Style",
                     source_category_id: growth.id,
                     source_category_name: "Growth",
                     target_category_id: value.id,
                     target_category_name: "Value",
                     action: :drop
                   },
                   %{
                     classification_id: sector.id,
                     classification_name: "Sector",
                     source_category_id: tech.id,
                     source_category_name: "Tech",
                     target_category_id: nil,
                     target_category_name: nil,
                     action: :move
                   }
                 ],
                 & &1.classification_id
               )

      mark = journal_mark()
      record = merge!(ctx, preview)

      assert Classifications.get_assignment(ctx.target.id, style.id).category_id == value.id

      assert %Assignment{id: moved_id, category_id: tech_id} =
               Classifications.get_assignment(ctx.target.id, sector.id)

      assert {moved_id, tech_id} == {moved.id, tech.id}
      assert Repo.all(from(a in Assignment, where: a.security_id == ^ctx.source.id)) == []

      assignment_entries =
        mark
        |> entries_since()
        |> Enum.filter(&(&1.resource_type == "security_category_assignment"))
        |> Enum.map(&{&1.operation, &1.resource_id})

      assert Enum.sort(assignment_entries) ==
               Enum.sort([{:update, to_string(moved.id)}, {:delete, assignment_id(style, ctx)}])

      assert [%{"classification_id" => _}] =
               record.manifest["category_assignments"]["moved"]

      assert [%{"classification_id" => _}] =
               record.manifest["category_assignments"]["dropped"]
    end

    # User story:
    # As the operator whose duplicate security carries position targets in
    # active, draft and archived plan versions,
    # I want each moved onto the security I keep, unless the kept security
    # already has a row in that plan or the row would no longer sit under
    # the kept security's category — then it is deleted and listed with
    # its reason,
    # so that no plan version ends with two rows for one security or a
    # target that steers a category the security is not in.
    #
    # Acceptance criteria:
    # - Region (the target's category Europe): the source's rows in the
    #   archived and the active plan move; in the draft that already holds
    #   the target's row, the source's is deleted as `collides`.
    # - Style (the target's category Value wins over the source's Growth):
    #   the source's row under Growth is deleted as `stale`.
    # - Each move is one journaled `target` update of the same row, each
    #   deletion one journaled `target` delete.
    test "position targets move, or are deleted where they collide or go stale", ctx do
      {region, %{"Europe" => europe}} = tree!("Region", ~w(Europe Asia))
      {style, %{"Growth" => growth, "Value" => value}} = tree!("Style", ~w(Growth Value))
      assign!(ctx.target, region, europe)
      assign!(ctx.source, region, europe)
      assign!(ctx.target, style, value)
      assign!(ctx.source, style, growth)

      {:ok, _} = position!(ctx.main, region, europe, ctx.source, "0.2")
      [archived_row] = position_rows(ctx.source)
      {:ok, draft} = Targets.duplicate_plan(Actor.owner_ui(), archived_row.plan_id)
      {:ok, _} = Targets.activate_plan(Actor.owner_ui(), draft)
      {:ok, second_draft} = Targets.duplicate_plan(Actor.owner_ui(), draft.id)
      {:ok, _} = position!(ctx.main, region, europe, ctx.target, "0.3", plan: second_draft.id)
      {:ok, _} = position!(ctx.main, style, growth, ctx.source, "0.1")

      rows = Map.new(position_rows(ctx.source), &{&1.plan_id, &1})
      active_row = Map.fetch!(rows, draft.id)
      colliding_row = Map.fetch!(rows, second_draft.id)
      [stale_row] = Enum.filter(Map.values(rows), &(&1.classification_id == style.id))

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

      assert Map.new(preview.configuration.position_targets, &{&1.id, {&1.action, &1.reason}}) ==
               %{
                 archived_row.id => {:move, nil},
                 active_row.id => {:move, nil},
                 colliding_row.id => {:drop, :collides},
                 stale_row.id => {:drop, :stale}
               }

      assert Enum.find(preview.configuration.position_targets, &(&1.id == archived_row.id)).plan_status ==
               "archived"

      mark = journal_mark()
      record = merge!(ctx, preview)

      assert Repo.get!(Target, archived_row.id).security_id == ctx.target.id
      assert Repo.get!(Target, active_row.id).security_id == ctx.target.id
      refute Repo.get(Target, colliding_row.id)
      refute Repo.get(Target, stale_row.id)
      assert position_rows(ctx.source) == []

      target_entries =
        mark
        |> entries_since()
        |> Enum.filter(&(&1.resource_type == "target"))
        |> Enum.map(&{&1.operation, &1.resource_id})
        |> Enum.sort()

      assert target_entries ==
               Enum.sort([
                 {:update, to_string(archived_row.id)},
                 {:update, to_string(active_row.id)},
                 {:delete, to_string(colliding_row.id)},
                 {:delete, to_string(stale_row.id)}
               ])

      assert Enum.sort(Enum.map(record.manifest["position_targets"]["deleted"], & &1["reason"])) ==
               ["collides", "stale"]
    end

    # User story:
    # As the operator whose duplicate security carries calendar events,
    # I want them moved onto the security I keep, and a same-kind event on
    # the same day on both listed as a possible duplicate,
    # so that no event vanishes and I can clean up a double entry myself.
    #
    # Acceptance criteria:
    # - Both source events move (one journaled update each); the earnings
    #   date both carry is listed as a possible duplicate, and nothing is
    #   deleted.
    test "security events move; a same-kind, same-day pair is listed", ctx do
      t_event = event!(ctx.target, "earnings", ~D[2026-10-30])
      s_twin = event!(ctx.source, "earnings", ~D[2026-10-30])
      s_other = event!(ctx.source, "ex_dividend", ~D[2026-11-05])

      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

      assert Enum.sort(Enum.map(preview.events.moved, & &1.id)) ==
               Enum.sort([s_twin.id, s_other.id])

      assert preview.events.possible_duplicates == [
               %{
                 source_event_id: s_twin.id,
                 target_event_id: t_event.id,
                 kind: :earnings,
                 date: ~D[2026-10-30]
               }
             ]

      mark = journal_mark()
      merge!(ctx, preview)

      assert Enum.sort(Enum.map(Events.list_for_security(ctx.target.id), & &1.id)) ==
               Enum.sort([t_event.id, s_twin.id, s_other.id])

      assert mark
             |> entries_since()
             |> Enum.filter(&(&1.resource_type == "security_event"))
             |> Enum.map(&{&1.operation, &1.resource_id})
             |> Enum.sort() ==
               Enum.sort([{:update, to_string(s_twin.id)}, {:update, to_string(s_other.id)}])
    end
  end

  describe "identifiers (§9)" do
    # User story:
    # As the operator repairing a duplicate that carries an ISIN of its own,
    # I want to choose which ISIN the kept security answers to, never
    # preselected, with the other kept as a former ISIN, and the duplicate's
    # WKN, ticker and feed taken over only where the kept security lacks
    # them,
    # so that every export, old or new, still finds the kept security and
    # nothing about it changes that I did not see.
    #
    # Acceptance criteria:
    # - With an ISIN on both, the preview states the identifiers after each
    #   identity choice; the apply without one answers
    #   {:choice_required, :identity_choice, _}, with an unknown one
    #   {:invalid, :identity_choice, _}, and writes nothing.
    # - keep_target_isin with the operator's date: the target keeps its ISIN,
    #   the source's becomes a former ISIN changed on that date, and the
    #   source's own former ISIN is reassigned to the target.
    # - The target takes the source's WKN and feed, which it lacks, and
    #   keeps its own ticker and name; the preview lists what it adopts and
    #   every difference that follows the target.
    test "keep_target_isin: the source's ISIN becomes a former ISIN of the target", ctx do
      {source, target} = identified_pair!(ctx)

      {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)
      assert preview.identifiers.choice_required

      assert preview.identifiers.outcomes.keep_target_isin == %{
               isin: @isin_target,
               wkn: "SRC001",
               ticker_symbol: "TGTX",
               feed: "MANUAL",
               name: "Carry Fund",
               asset_class: "etf",
               former_isins: Enum.sort([@isin_old, @isin_source])
             }

      assert preview.identifiers.outcomes.adopt_source_isin.isin == @isin_source

      assert preview.identifiers.outcomes.adopt_source_isin.former_isins ==
               Enum.sort([@isin_old, @isin_target])

      assert Enum.sort(Enum.map(preview.identifiers.adopted, & &1.field)) == [:feed, :wkn]

      assert %{field: :ticker_symbol, source: "SRCX", target: "TGTX"} in preview.identifiers.differences

      assert %{field: :name, source: "Carry Fund (duplicate)", target: "Carry Fund"} in preview.identifiers.differences

      before = fingerprint()
      base = %{plan_digest: preview.plan_digest}

      assert {:error, {:choice_required, :identity_choice, _}} =
               Lifecycle.merge_security(agent(), source.id, target.id, base)

      assert {:error, {:invalid, :identity_choice, _}} =
               Lifecycle.merge_security(
                 agent(),
                 source.id,
                 target.id,
                 Map.put(base, :identity_choice, "whatever")
               )

      assert fingerprint() == before

      assert {:ok, record, :applied} =
               Lifecycle.merge_security(agent(), source.id, target.id, %{
                 plan_digest: preview.plan_digest,
                 identity_choice: "keep_target_isin",
                 isin_changed_on: ~D[2025-05-01]
               })

      kept = Repo.get!(Security, target.id)

      assert {kept.isin, kept.wkn, kept.ticker_symbol, kept.feed, kept.name} ==
               {@isin_target, "SRC001", "TGTX", "MANUAL", "Carry Fund"}

      assert aliases(target) == [
               {@isin_old, ~D[2024-06-01]},
               {@isin_source, ~D[2025-05-01]}
             ]

      assert record.manifest["choices"]["identity_choice"] == "keep_target_isin"
      assert record.source_snapshot["isin"] == @isin_source
    end

    # User story:
    # As the operator repairing ADR-0029 §3's wrong-order duplicate,
    # I want the kept security to take the duplicate's newer ISIN and keep
    # its old one as a former ISIN,
    # so that the security I keep answers to the ISIN the exports carry now.
    #
    # Acceptance criteria:
    # - adopt_source_isin without a date: the target's ISIN is the source's,
    #   its old ISIN a former ISIN changed on the merge date.
    test "adopt_source_isin: the target takes the source's ISIN", ctx do
      {source, target} = identified_pair!(ctx)
      {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

      assert {:ok, _record, :applied} =
               Lifecycle.merge_security(agent(), source.id, target.id, %{
                 plan_digest: preview.plan_digest,
                 identity_choice: :adopt_source_isin
               })

      assert Repo.get!(Security, target.id).isin == @isin_source

      assert aliases(target) == [
               {@isin_old, ~D[2024-06-01]},
               {@isin_target, Clock.today()}
             ]
    end

    # User story:
    # As the operator merging a duplicate whose ISIN the kept security lacks,
    # I want the kept security to take it without a question,
    # so that an export carrying it still finds the kept security.
    #
    # Acceptance criteria:
    # - Only the source carries an ISIN: no choice is required, and the
    #   target takes it.
    test "an ISIN only the source carries is adopted without a choice", ctx do
      {:ok, _} = Catalog.update_security(Actor.owner_ui(), ctx.source, %{isin: @isin_source})
      {:ok, preview} = Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)
      refute preview.identifiers.choice_required
      assert preview.identifiers.outcomes.no_choice.isin == @isin_source

      merge!(ctx, preview)
      assert Repo.get!(Security, ctx.target.id).isin == @isin_source
    end
  end

  describe "resolvability (§9, §16 invariant 14)" do
    # User story:
    # As the operator about to merge a security that a Portfolio Performance
    # import created from its name alone and that I gave a ticker later,
    # I want the merge refused while the name the file carries would no
    # longer find the kept security, naming that identifier,
    # so that the next import of that file never creates a duplicate the
    # merge promised away.
    #
    # Acceptance criteria:
    # - The preview and the apply refuse as identity_unresolvable, naming
    #   the imported name and the security, and every table is unchanged.
    # - The same source with a name the target shares merges.
    test "a name-only import given a ticker since is refused while its name would not resolve",
         ctx do
      {:ok, _} = Catalog.update_security(Actor.owner_ui(), ctx.target, %{name: "Target Fund"})

      {:ok, imported} =
        Catalog.create_security(Actor.import_session(), %{
          name: "Solo Fund",
          currency_code: "EUR",
          provider: "portfolio_performance",
          feed: "PORTFOLIO_PERFORMANCE"
        })

      {:ok, imported} =
        Catalog.update_security(Actor.owner_ui(), imported, %{ticker_symbol: "SOLO"})

      buy!(ctx.main, ctx.depot, ctx.cash, imported, "1", "10.00", ~D[2025-03-01])
      ctx = %{ctx | source: imported}

      guard = refused_guard!(ctx, :identity_unresolvable)
      assert guard.detail =~ "Solo Fund"
      assert guard.detail =~ "##{imported.id}"
      assert guard.detail =~ ~r/import/i

      assert [%{security_id: id, identity: :imported, ref: %{name: "Solo Fund"}}] =
               guard.unresolvable

      assert id == imported.id

      {:ok, _} = Catalog.update_security(Actor.owner_ui(), ctx.target, %{name: "Solo Fund"})
      {:ok, preview} = Lifecycle.preview_security_merge(imported.id, ctx.target.id)
      assert Enum.all?(preview.guards, & &1.passed)
    end
  end

  describe "everything a source carries (§16 invariant 11)" do
    # User story:
    # As the maintainer auditing a security merge,
    # I want a source that carries quotes, configuration, events, aliases
    # and identifiers merged with nothing left pointing at it and every
    # change accounted for,
    # so that the hardened delete of the source never drops a reference and
    # the journal and the manifest reconstruct the merge.
    #
    # Acceptance criteria:
    # - After the merge no row of any table references the source.
    # - Every journal entry of the merge is one of the kinds the plan lists,
    #   and no row is touched twice.
    test "nothing references the source afterwards, and every change is journaled once", ctx do
      {source, target} = identified_pair!(ctx)
      {region, %{"Europe" => europe}} = tree!("Region", ~w(Europe Asia))
      assign!(source, region, europe)
      {:ok, _} = position!(ctx.main, region, europe, source, "0.25")
      event!(source, "earnings", ~D[2026-10-30])
      provider!(source, [{~D[2025-03-05], "52.00"}])
      manual!(target, [{~D[2025-03-05], "51.00"}])
      mark = journal_mark()

      {:ok, preview} = Lifecycle.preview_security_merge(source.id, target.id)

      {:ok, _record, :applied} =
        Lifecycle.merge_security(agent(), source.id, target.id, %{
          plan_digest: preview.plan_digest,
          identity_choice: :keep_target_isin
        })

      assert references_to(source.id) == %{}

      entries = entries_since(mark)

      assert entries
             |> Enum.map(&{&1.resource_type, &1.resource_id, &1.operation})
             |> Enum.frequencies()
             |> Map.values()
             |> Enum.uniq() == [1]

      assert Enum.all?(entries, &(&1.actor_label == "synthetic-agent"))
      assert Repo.get(Security, source.id) == nil
    end
  end

  # --- the world ---------------------------------------------------------------

  # A pair where both carry an ISIN: the source was renamed from an older
  # ISIN (a former ISIN of its own), has a WKN, a ticker and a feed; the
  # target has another ISIN and ticker and no WKN or feed.
  defp identified_pair!(ctx) do
    {:ok, source} =
      Catalog.update_security(Actor.owner_ui(), ctx.source, %{
        name: "Carry Fund (duplicate)",
        isin: @isin_old,
        wkn: "SRC001",
        ticker_symbol: "SRCX",
        feed: "MANUAL"
      })

    {:ok, %{security: source}} =
      Catalog.record_isin_change(Actor.owner_ui(), source, @isin_source,
        changed_on: ~D[2024-06-01]
      )

    {:ok, target} =
      Catalog.update_security(Actor.owner_ui(), ctx.target, %{
        isin: @isin_target,
        ticker_symbol: "TGTX",
        feed: nil
      })

    {source, target}
  end

  defp security!(attrs) do
    {:ok, security} =
      Catalog.create_security(
        Actor.owner_ui(),
        Map.merge(%{currency_code: "EUR", asset_class: "etf"}, attrs)
      )

    security
  end

  defp buy!(portfolio, depot, cash, security, quantity, price, date) do
    {:ok, tx} =
      Ledger.create_transaction(agent(), %{
        portfolio_id: portfolio.id,
        securities_account_id: depot.id,
        cash_account_id: cash.id,
        security_id: security.id,
        type: "buy",
        date: date,
        quantity: quantity,
        price: price,
        currency_code: "EUR"
      })

    tx
  end

  # Provider quotes, written as the sync writes them (the unjournaled writer
  # test fixtures may call).
  defp provider!(security, rows) do
    {:ok, _count} =
      Quotes.upsert_many(
        security.id,
        Enum.map(rows, fn {date, close} -> %{date: date, close: close, source: "auto"} end)
      )

    :ok
  end

  defp manual!(security, rows) do
    {:ok, _} =
      Catalog.upsert_quotes(
        Actor.owner_ui(),
        security.id,
        Enum.map(rows, fn {date, close} ->
          %{"date" => Date.to_iso8601(date), "close" => close}
        end)
      )

    :ok
  end

  defp stored_quotes(security) do
    from(q in SecurityQuote, where: q.security_id == ^security.id, order_by: q.date)
    |> Repo.all()
    |> Enum.map(&{&1.date, n(&1.close), &1.source})
  end

  defp tree!(name, category_names) do
    {:ok, classification} =
      Classifications.create_classification(Actor.owner_ui(), %{name: name})

    categories =
      Map.new(category_names, fn category_name ->
        {:ok, category} =
          Classifications.create_category(Actor.owner_ui(), %{
            classification_id: classification.id,
            name: category_name
          })

        {category_name, category}
      end)

    {classification, categories}
  end

  defp assign!(security, classification, category) do
    {:ok, assignment} =
      Classifications.assign_security(
        Actor.owner_ui(),
        security.id,
        classification.id,
        category.id
      )

    assignment
  end

  defp assignment_id(classification, ctx) do
    # The source's assignment in `classification`, read from the journal's
    # create entry (the row itself is gone after the merge).
    Repo.one!(
      from(e in Journal.Entry,
        where:
          e.resource_type == "security_category_assignment" and e.operation == :create and
            fragment("(?->>'security_id')::bigint", e.after) == ^ctx.source.id and
            fragment("(?->>'classification_id')::bigint", e.after) == ^classification.id,
        select: e.resource_id
      )
    )
  end

  defp position!(portfolio, classification, category, security, weight, opts \\ []) do
    Targets.set_targets(
      Actor.owner_ui(),
      portfolio.id,
      classification.id,
      [%{category_id: category.id, security_id: security.id, target_weight: weight}],
      opts
    )
  end

  defp position_rows(security),
    do: Repo.all(from(t in Target, where: t.security_id == ^security.id, order_by: t.id))

  defp event!(security, kind, date) do
    {:ok, event} =
      Events.create_event(agent(), %{
        security_id: security.id,
        kind: kind,
        date: date,
        timing: "exact",
        source_quality: "primary"
      })

    event
  end

  defp aliases(security) do
    from(a in IdentifierAlias,
      where: a.security_id == ^security.id,
      order_by: a.former_isin,
      select: {a.former_isin, a.changed_on}
    )
    |> Repo.all()
  end

  defp merge!(ctx, preview) do
    {:ok, record, :applied} =
      Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
        plan_digest: preview.plan_digest
      })

    record
  end

  defp refused_guard!(ctx, code) do
    before = fingerprint()

    assert {:error, {:refused, guards}} =
             Lifecycle.preview_security_merge(ctx.source.id, ctx.target.id)

    assert code in failed(guards), "preview #{code}: #{inspect(failed(guards))}"

    assert {:error, {:refused, apply_guards}} =
             Lifecycle.merge_security(agent(), ctx.source.id, ctx.target.id, %{
               plan_digest: "sha256:whatever"
             })

    assert code in failed(apply_guards)
    assert fingerprint() == before
    Enum.find(guards, &(&1.code == code and not &1.passed))
  end

  defp failed(guards), do: for(%{passed: false, code: code} <- guards, do: code)

  # Every table with a `security_id` column, counted for `id`: the source
  # must be referenced by nothing once it is gone.
  defp references_to(id) do
    %{rows: tables} =
      Repo.query!("""
      SELECT table_name FROM information_schema.columns
      WHERE table_schema = 'public' AND column_name = 'security_id'
      ORDER BY table_name
      """)

    for [table] <- tables,
        %{rows: [[count]]} =
          Repo.query!(~s[SELECT count(*) FROM "#{table}" WHERE security_id = $1], [id]),
        count > 0,
        into: %{},
        do: {table, count}
  end

  defp journal_mark, do: Repo.one(from(e in Journal.Entry, select: max(e.id))) || 0

  defp entries_since(mark),
    do: Repo.all(from(e in Journal.Entry, where: e.id > ^mark, order_by: e.id))

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
